--!nonstrict
-- Now-playing via playerctl/MPRIS. Compact/expand width (in characters) are
-- settings below; hovering animates from one to the other, but only actually
-- grows if the text is longer than the compact width -- a short title just
-- stays put. If it's still too long even at the expanded width while
-- hovering, it scrolls as a marquee instead of truncating. Left-click opens
-- the media panel, right-click toggles play/pause (matches the native Media
-- widget's own click/right-click split).

local COVER_SIZE_DEFAULT = 20 -- px, square cover-art icon in place of the play/pause glyph
local ROUND_SIZE = 128 -- px, fixed processing canvas the mask is rendered at before downscale

-- The progress bar is rendered as an actual image (not text) so it's always
-- a flat solid fill and never has to share a font with the title label --
-- no installed font renders block/shade characters as a true flat fill
-- (they're dither patterns by design), and forcing a font for them fights
-- the widget's own per-widget Font setting. Position is discretized into
-- FILL_STEPS buckets so there are only ever a handful of distinct bar
-- images to render/cache, not one per frame.
local FILL_STEPS = 24
-- When cover art is on, the bar sits *beside* the art (not over it): the art
-- and a progress pill are composited side by side into one image (the widget
-- only has a single image slot). Sizes are in the ROUND_SIZE processing space.
local COMBO_GAP = 16 -- px, transparent gap between art and bar
local COMBO_BAR_W = 220 -- px, bar width (kept wide vs. tall so it reads as a bar, not a blob)
local COMBO_BAR_H = 52 -- px, bar height
local COMBO_CANVAS_W = ROUND_SIZE + COMBO_GAP + COMBO_BAR_W -- total composited width
-- Standalone bar (cover art off), shown in place of the play/pause glyph.
local STANDALONE_BAR_W = 200 -- px canvas
local STANDALONE_BAR_H = 64
local STANDALONE_DISP_SCALE = 2.4 -- display width = cover_size * this (bar has no art to size against)

-- Same open/close tuning as the clock/volume/sysmon widgets: 0.16 @ 16ms.
local EASE = 0.16
local ANIM_INTERVAL = 16
local SCROLL_INTERVAL = 150 -- ms per marquee character step
local IDLE_INTERVAL = 1000 -- ms poll cadence when settled and not scrolling
-- Re-poll every this many scroll ticks too, so a track change is still
-- noticed while continuously hovering/scrolling (previously only polled in
-- the idle branch, so a long-hovered widget could get stuck on a stale
-- track indefinitely).
local SCROLL_POLL_EVERY = math.max(1, math.floor(IDLE_INTERVAL / SCROLL_INTERVAL + 0.5))

local hovering = false
local progress = 0.0 -- 0 = compact (20), 1 = expanded (40)
local target = 0.0
local scrollOffset = 0
local ticksSincePoll = 0

local hasMedia = false
local playing = false
local artist = ""
local title = ""
local artUrl = ""
local position = 0
local length = 0

-- Cover art is only ever a local file (barWidget.setImage has no network
-- fetcher), so http(s) art (Spotify etc.) gets downloaded once per track into
-- a cache file and reused; file:// art (most local players) is used directly.
local CACHE_DIR = `{noctalia.pluginDir()}/cache`
local DOWNLOAD_PATH = `{CACHE_DIR}/cover-src.jpg`
local ROUND_PATH = `{CACHE_DIR}/cover-round.png`
local COVER_BAR_PATH = `{CACHE_DIR}/cover-bar.png`
noctalia.mkdirAll(CACHE_DIR)

-- playerctl with no -p picks a player by its own internal ordering, not by
-- who's actually playing -- confirmed it can land on a paused/stale player
-- (e.g. a YouTube tab that navigated away, leaving stale MPRIS metadata)
-- over a genuinely Playing one. pick-player.sh checks all players' status
-- first and prefers one that's actually Playing.
local PICK_PLAYER_SCRIPT = `{noctalia.pluginDir()}/pick-player.sh`

-- barWidget.setImage has no radius/rounding option (that's a native-widget-only
-- C++ feature -- confirmed no such field exists on the plugin image binding),
-- so rounding is done by shelling out to ImageMagick to bake a circular alpha
-- mask into a cached copy, and pointing setImage at that instead.
local MAGICK_AVAILABLE = noctalia.commandExists("magick") or noctalia.commandExists("convert")
local MAGICK_CMD = noctalia.commandExists("magick") and "magick" or "convert"

local lastRequestedArtUrl = nil
local downloadedArtUrl = nil
-- Cache keys are keyed on artUrl (the art's identity), NOT the file path:
-- downloaded art always lands at the same cover-src.jpg path, so a path-based
-- key made every song look identical and the rounded/composited art never
-- refreshed on a track change. artUrl changes per track, so it does.
local roundingKey = nil -- "artUrl|pct" currently being/last processed
local roundedFor = nil -- "artUrl|pct" the current ROUND_PATH content matches

local coverBarPending = nil -- "artUrl|pct|bucket" currently baking
local coverBarLastKey = nil -- "artUrl|pct|bucket" the current COVER_BAR_PATH content matches
local coverBarArtReady = nil -- "artUrl|pct" for which at least one composite has been baked
local standaloneReady = {} -- [bucket] = true once cache/bar-standalone-{bucket}.png exists
local standalonePending = {} -- [bucket] = true while generating

local function shQuote(s: string): string
  return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- utf8.len/offset find character boundaries so truncation/windowing never
-- cuts a multi-byte character in half.
local function utf8Sub(s: string, charCount: number): string
  if charCount <= 0 then
    return ""
  end
  local len = utf8.len(s)
  if not len or charCount >= len then
    return s
  end
  local offset = utf8.offset(s, charCount + 1)
  if not offset then
    return s
  end
  return s:sub(1, offset - 1)
end

-- `length` characters starting at 0-indexed `startChar`.
local function utf8Window(s: string, startChar: number, length: number): string
  local total = utf8.len(s)
  if not total then
    return s
  end
  if startChar >= total then
    return ""
  end
  local startByte = utf8.offset(s, startChar + 1) or (#s + 1)
  local endCharIdx = math.min(startChar + length, total)
  local endByte = utf8.offset(s, endCharIdx + 1)
  if endByte then
    return s:sub(startByte, endByte - 1)
  end
  return s:sub(startByte)
end

-- Returns compact/expand width in characters, expand clamped to be no
-- smaller than compact (a user could otherwise set expand < compact, which
-- would make hovering shrink the text instead of growing it).
local function widthRange(): (number, number)
  local compactLen = barWidget.getConfig("compact_width") or 20
  local expandLen = barWidget.getConfig("expand_width") or 40
  return compactLen, math.max(compactLen, expandLen)
end

-- Browser MPRIS (Firefox et al) doesn't populate mpris:artUrl for web video,
-- but does expose the page URL -- for YouTube specifically that's enough to
-- build a thumbnail URL via its stable, unauthenticated thumbnail CDN.
local function youtubeThumbFromPageUrl(pageUrl: string): string?
  local id = string.match(pageUrl, "[?&]v=([%w_%-]+)")
  if not id then
    id = string.match(pageUrl, "youtu%.be/([%w_%-]+)")
  end
  if not id then
    return nil
  end
  return `https://i.ytimg.com/vi/{id}/hqdefault.jpg`
end

local function pollMedia()
  noctalia.runAsync(
    `sh {shQuote(PICK_PLAYER_SCRIPT)}`,
    function(result)
      local out = result.stdout or ""
      -- title is last/greedy since it's the only field likely to contain
      -- stray characters; the others are safe to split on "|".
      local status, a, url, pos, len, pageUrl, t =
        string.match(out, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.-)%s*$")
      if not status or status == "" then
        hasMedia = false
        return
      end
      local resolvedArtUrl = url or ""
      if resolvedArtUrl == "" and pageUrl and pageUrl ~= "" then
        resolvedArtUrl = youtubeThumbFromPageUrl(pageUrl) or ""
      end
      -- Reset the marquee position on a real track change so it doesn't
      -- keep scrolling from the middle of the previous title.
      if hasMedia and (a ~= artist or t ~= title) then
        scrollOffset = 0
      end
      hasMedia = true
      playing = status == "Playing"
      artist = a or ""
      title = t or ""
      artUrl = resolvedArtUrl
      position = tonumber(pos) or 0
      length = tonumber(len) or 0
    end,
    1500
  )
end

local function fullText(): string
  if artist ~= "" then
    return `{artist} - {title}`
  end
  return title
end

-- Returns a local file path for the current cover art, or nil if there isn't
-- one (yet). Downloads remote art once per track and caches it; only ever
-- returns a path once the file backing it is actually ready to read.
local function resolveRawCoverPath(): string?
  if artUrl == "" then
    return nil
  end

  local localPath = string.match(artUrl, "^file://(.+)$")
  if localPath then
    return noctalia.string.urlDecode(localPath)
  end

  if string.match(artUrl, "^https?://") then
    if artUrl ~= lastRequestedArtUrl then
      lastRequestedArtUrl = artUrl
      noctalia.download(artUrl, DOWNLOAD_PATH, function(ok)
        if ok then
          downloadedArtUrl = artUrl
        end
      end)
    end
    if downloadedArtUrl == artUrl then
      return DOWNLOAD_PATH
    end
  end

  return nil
end

-- Wraps resolveRawCoverPath with a rounded-rectangle mask pass (async, once
-- per raw source + rounding amount) so the widget only ever displays the
-- rounded copy. Falls back to the unrounded raw art if ImageMagick isn't
-- installed. pct is 0 (square) to 100 (fully circular, radius = half size --
-- roundRectangle degrades to a circle once the corner radius reaches that).
local function resolveCoverPath(pct: number): string?
  local raw = resolveRawCoverPath()
  if not raw then
    return nil
  end
  if not MAGICK_AVAILABLE or pct <= 0 then
    return raw
  end

  local key = `{artUrl}|{pct}`
  if roundedFor == key then
    return ROUND_PATH
  end

  if roundingKey ~= key then
    roundingKey = key
    local radius = math.floor((pct / 100) * (ROUND_SIZE / 2) + 0.5)
    local cmd = string.format(
      "%s %s -resize %dx%d^ -gravity center -extent %dx%d "
        .. "\\( -size %dx%d xc:black -fill white -draw \"roundRectangle 0,0,%d,%d,%d,%d\" \\) "
        .. "-alpha off -compose CopyOpacity -composite %s",
      MAGICK_CMD,
      shQuote(raw),
      ROUND_SIZE,
      ROUND_SIZE,
      ROUND_SIZE,
      ROUND_SIZE,
      ROUND_SIZE,
      ROUND_SIZE,
      ROUND_SIZE - 1,
      ROUND_SIZE - 1,
      radius,
      radius,
      shQuote(ROUND_PATH)
    )
    noctalia.runAsync(cmd, function(result)
      if result.exitCode == 0 then
        roundedFor = key
      end
    end)
  end

  return nil
end

-- 0..FILL_STEPS bucket for the current playback position, or 0 if unknown.
local function fillBucket(): number
  if not hasMedia or length <= 0 then
    return 0
  end
  local frac = math.max(0, math.min(1, position / length))
  return math.floor(frac * FILL_STEPS + 0.5)
end

-- roundRectangle with a radius bigger than half the rect just renders as a
-- fully rounded pill, so no clamping needed for the small-fill edge cases.
local function barDrawCmd(fillColor: string, x1: number, y1: number, x2: number, y2: number, r: number): string
  return string.format(" -fill %s -draw \"roundRectangle %d,%d,%d,%d,%d,%d\"", fillColor, x1, y1, x2, y2, r, r)
end

-- Composites the (already rounded) cover art and a progress pill side by side
-- into one image, so both can share the widget's single image slot without
-- the bar sitting on top of the art. Returns COVER_BAR_PATH once at least one
-- composite exists for the current art (subsequent bucket changes overwrite
-- that same file in place -- setImage watch=true reloads it, so the widget's
-- width never jitters), or the plain art path until the first bake lands.
local function resolveCoverWithBar(pct: number, bucket: number): string?
  local base = resolveCoverPath(pct)
  if not base then
    return nil
  end
  if not MAGICK_AVAILABLE then
    return base
  end

  local artKey = `{artUrl}|{pct}`
  local fullKey = `{artKey}|{bucket}`

  -- (Re)bake whenever the displayed bucket/art isn't the one on disk.
  if coverBarLastKey ~= fullKey and coverBarPending ~= fullKey then
    coverBarPending = fullKey
    local barX = ROUND_SIZE + COMBO_GAP
    local filledW = math.floor((bucket / FILL_STEPS) * COMBO_BAR_W + 0.5)
    local top = math.floor((ROUND_SIZE - COMBO_BAR_H) / 2)
    local bottom = top + COMBO_BAR_H - 1
    local r = math.floor(COMBO_BAR_H / 2)

    local cmd = string.format("%s %s -background none -gravity West -extent %dx%d", MAGICK_CMD, shQuote(base), COMBO_CANVAS_W, ROUND_SIZE)
      .. barDrawCmd("\"rgba(255,255,255,0.30)\"", barX, top, barX + COMBO_BAR_W - 1, bottom, r)
      .. (filledW > 0 and barDrawCmd("white", barX, top, barX + filledW - 1, bottom, r) or "")
      .. " "
      .. shQuote(COVER_BAR_PATH)

    noctalia.runAsync(cmd, function(result)
      coverBarPending = nil
      if result.exitCode == 0 then
        coverBarLastKey = fullKey
        coverBarArtReady = artKey
      end
    end)
  end

  if coverBarArtReady == artKey then
    return COVER_BAR_PATH
  end
  return base
end

-- Standalone flat pill bar for when cover art is off, shown in place of the
-- play/pause glyph. Purely a function of the fill bucket (not the track), so
-- each of the FILL_STEPS possible images only ever needs generating once.
local function resolveStandaloneBar(bucket: number): string?
  local path = `{CACHE_DIR}/bar-standalone-{bucket}.png`
  if standaloneReady[bucket] then
    return path
  end
  if not MAGICK_AVAILABLE then
    return nil
  end

  if not standalonePending[bucket] then
    standalonePending[bucket] = true
    local filledW = math.floor((bucket / FILL_STEPS) * STANDALONE_BAR_W + 0.5)
    local r = math.floor(STANDALONE_BAR_H / 2)

    local cmd = string.format("%s -size %dx%d xc:none", MAGICK_CMD, STANDALONE_BAR_W, STANDALONE_BAR_H)
      .. barDrawCmd("\"rgba(255,255,255,0.28)\"", 0, 0, STANDALONE_BAR_W - 1, STANDALONE_BAR_H - 1, r)
      .. (filledW > 0 and barDrawCmd("white", 0, 0, filledW - 1, STANDALONE_BAR_H - 1, r) or "")
      .. " "
      .. shQuote(path)

    noctalia.runAsync(cmd, function(result)
      standalonePending[bucket] = false
      if result.exitCode == 0 then
        standaloneReady[bucket] = true
      end
    end)
  end

  return nil
end

local function render()
  if not hasMedia then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)
  -- Never touch font here -- Noctalia already gives every widget (native or
  -- plugin) a per-widget Font setting in its own settings panel
  -- (Widget::labelFontFamily), applied at build time. The progress bar is an
  -- image now, not text, so it never needs (or fights over) a font.

  local barEnabled = barWidget.getConfig("show_progress_bar") ~= false
  local coverEnabled = barWidget.getConfig("show_cover_art") ~= false
  local coverSize = barWidget.getConfig("cover_size") or COVER_SIZE_DEFAULT
  local roundPct = barWidget.getConfig("corner_rounding") or 100
  local barActive = barEnabled and hasMedia and length > 0
  local bucket = fillBucket()

  local imagePath = nil
  if coverEnabled then
    imagePath = barActive and resolveCoverWithBar(roundPct, bucket) or resolveCoverPath(roundPct)
  end

  if imagePath == COVER_BAR_PATH then
    -- art + bar side by side: the composite is COMBO_CANVAS_W wide at
    -- ROUND_SIZE tall, displayed at cover_size tall and proportionally wide.
    local dispW = math.floor(coverSize * (COMBO_CANVAS_W / ROUND_SIZE) + 0.5)
    barWidget.setImage(imagePath, true, dispW, coverSize)
  elseif imagePath then
    barWidget.setImage(imagePath, true, coverSize) -- plain square art
  elseif barActive then
    local barPath = resolveStandaloneBar(bucket)
    if barPath then
      local dispW = math.floor(coverSize * STANDALONE_DISP_SCALE + 0.5)
      local dispH = math.floor(dispW * (STANDALONE_BAR_H / STANDALONE_BAR_W) + 0.5)
      barWidget.setImage(barPath, true, dispW, dispH)
    else
      barWidget.setGlyph(playing and "player-play-filled" or "player-pause-filled")
    end
  else
    barWidget.setGlyph(playing and "player-play-filled" or "player-pause-filled")
  end

  local full = fullText()
  local compactLen, expandLen = widthRange()
  local fullLen = utf8.len(full) or #full
  local width = math.floor(compactLen + (expandLen - compactLen) * progress + 0.5)

  if fullLen <= width then
    barWidget.setText(full)
  elseif hovering then
    local loop = full .. "   "
    local loopLen = utf8.len(loop) or #loop
    local start = scrollOffset % loopLen
    local window = utf8Window(loop .. full, start, width)
    barWidget.setText(window)
  else
    barWidget.setText(`{utf8Sub(full, math.max(width - 3, 1))}...`)
  end
end

local function step()
  if math.abs(progress - target) >= 0.01 then
    progress = progress + (target - progress) * EASE
    noctalia.setUpdateInterval(ANIM_INTERVAL)
    render()
    return
  end
  progress = target

  local full = fullText()
  local compactLen, expandLen = widthRange()
  local fullLen = utf8.len(full) or #full
  local width = math.floor(compactLen + (expandLen - compactLen) * progress + 0.5)
  local needsScroll = hovering and hasMedia and fullLen > width

  if needsScroll then
    scrollOffset += 1
    ticksSincePoll += 1
    if ticksSincePoll >= SCROLL_POLL_EVERY then
      ticksSincePoll = 0
      pollMedia()
    end
    noctalia.setUpdateInterval(SCROLL_INTERVAL)
    render()
  else
    ticksSincePoll = 0
    noctalia.setUpdateInterval(IDLE_INTERVAL)
    pollMedia()
    render()
  end
end

function update()
  step()
end

function onHover(isHovering: boolean)
  hovering = isHovering
  target = isHovering and 1.0 or 0.0
  if isHovering then
    scrollOffset = 0
  end
  step()
end

function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center media")
end

function onRightClick()
  noctalia.runAsync("playerctl play-pause")
end
