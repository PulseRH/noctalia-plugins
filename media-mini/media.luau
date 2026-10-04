--!nonstrict
-- Now-playing via playerctl/MPRIS. Compact/expand width (in characters) are
-- settings below; hovering animates from one to the other, but only actually
-- grows if the text is longer than the compact width -- a short title just
-- stays put. If it's still too long even at the expanded width while
-- hovering, it scrolls as a marquee instead of truncating. Left-click toggles
-- play/pause; right-click opens the media panel.

local COVER_SIZE_DEFAULT = 20 -- px, square cover-art icon in place of the play/pause glyph
local ROUND_SIZE = 128 -- px, fixed processing canvas the mask is rendered at before downscale

-- Progress graphics use native rounded shapes at their configured width and
-- thickness. Cover art remains separate so resizing never distorts it.
local COMBO_GAP = 16 -- gap relative to the 128px artwork processing canvas

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
local activePlayer = ""
local artist = ""
local title = ""
local artUrl = ""
local position = 0
local length = 0
local seekDraft, seekPlayer, seekTrack = nil, nil, nil
local render
local function trackKey() return `{activePlayer}|{artist}|{title}|{length}` end

-- Cover art is only ever a local file (barWidget.setImage has no network
-- fetcher), so http(s) art (Spotify etc.) gets downloaded once per track into
-- a cache file and reused; file:// art (most local players) is used directly.
local DATA_DIR = noctalia.pluginDataDir() or noctalia.expandPath("~/.cache/noctalia-plugins/media-mini")
local CACHE_DIR = `{DATA_DIR}/cache/media-mini`
local DOWNLOAD_PATH = `{CACHE_DIR}/cover-src.jpg`
local ROUND_PATH = `{CACHE_DIR}/cover-round.png`
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

local downloadPending = false
local lastRequestedArtUrl = nil
local downloadedArtUrl = nil
-- Cache keys are keyed on artUrl (the art's identity), NOT the file path:
-- downloaded art always lands at the same cover-src.jpg path, so a path-based
-- key made every song look identical and the rounded/composited art never
-- refreshed on a track change. artUrl changes per track, so it does.
local roundingKey = nil -- "artUrl|pct" currently being/last processed
local roundedFor = nil -- "artUrl|pct" the current ROUND_PATH content matches

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
  local compactLen = noctalia.getConfig("compact_width") or 20
  local expandLen = noctalia.getConfig("expand_width") or 40
  return compactLen, math.max(compactLen, expandLen)
end

-- Browser MPRIS (Firefox et al) doesn't populate mpris:artUrl for web video,
-- but does expose the page URL -- for YouTube specifically that's enough to
-- build a thumbnail URL via its stable, unauthenticated thumbnail CDN.
local function youtubeThumbFromPageUrl(pageUrl: string): string?
  if not string.match(pageUrl, "^https?://[%w%.%-]*youtube%.com/")
    and not string.match(pageUrl, "^https?://youtu%.be/") then return nil end
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
      local selected, status, a, url, pos, len, pageUrl, t =
        string.match(out, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.-)%s*$")
      if not status or status == "" then
        hasMedia = false
        seekDraft, seekPlayer, seekTrack = nil, nil, nil
        if render then render() end
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
      activePlayer = selected or ""
      playing = status == "Playing"
      artist = a or ""
      title = t or ""
      artUrl = resolvedArtUrl
      position = tonumber(pos) or 0
      length = tonumber(len) or 0
      if seekDraft ~= nil and seekTrack ~= trackKey() then seekDraft, seekPlayer, seekTrack = nil, nil, nil end
      if render then render() end
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
    if artUrl ~= lastRequestedArtUrl and not downloadPending then
      local requestedUrl = artUrl
      lastRequestedArtUrl = requestedUrl
      downloadPending = true
      noctalia.download(requestedUrl, DOWNLOAD_PATH, function(ok)
        downloadPending = false
        if ok then downloadedArtUrl = requestedUrl
        else lastRequestedArtUrl = nil end
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

function onMediaInlineHover(state)
  onHover(state == "true")
end
function onPlaybackClick()
  if activePlayer ~= "" then noctalia.runAsync({"playerctl", "-p", activePlayer, "play-pause"}) end
end
function onSeekChange(value)
  if length <= 0 or activePlayer == "" then return end
  if seekDraft == nil then seekPlayer, seekTrack = activePlayer, trackKey() end
  seekDraft = math.max(0, math.min(length / 1000000, tonumber(value) or 0))
  if render then render() end
end
function onSeekRelease()
  if seekDraft == nil then return end
  local value, player, track = seekDraft, seekPlayer, seekTrack
  seekDraft, seekPlayer, seekTrack = nil, nil, nil
  if player ~= activePlayer or track ~= trackKey() then return end
  position = value * 1000000
  noctalia.runAsync({"playerctl", "-p", player, "position", tostring(value)}, function(result)
    if result.exitCode ~= 0 then barWidget.setTooltip("This player could not seek to that position") end
    pollMedia()
  end, 1500)
  render()
end
local classicSeekX = nil
function onClassicSeekMove(x)
  classicSeekX = tonumber(x)
  if not hovering then onHover(true) end
end
function onClassicSeekLeave()
  classicSeekX = nil
  onHover(false)
end
function onClassicSeekClick()
  if classicSeekX == nil or length <= 0 then return end
  onSeekChange(tostring(math.max(0, math.min(1, classicSeekX)) * length / 1000000))
  onSeekRelease()
end
render = function()
  barWidget.setVisible(hasMedia)
  if not hasMedia then return end
  local coverSize = noctalia.getConfig("cover_size") or COVER_SIZE_DEFAULT
  local children = {}
  if noctalia.getConfig("progress_style") == "interactive" then
  local imagePath = nil
  if noctalia.getConfig("show_cover_art") ~= false then
    imagePath = resolveCoverPath(noctalia.getConfig("corner_rounding") or 100)
  end
  if imagePath then
    table.insert(children, ui.image({key = "cover", path = imagePath, width = coverSize, height = coverSize,
      fit = "cover", onClick = "onPlaybackClick", onHover = "onMediaInlineHover", tooltip = "Play / pause"}))
  else
    table.insert(children, ui.button({key = "playback", glyph = playing and "player-pause-filled" or "player-play-filled",
      glyphSize = coverSize, width = coverSize + 4, height = coverSize + 4,
      variant = "ghost", onClick = "onPlaybackClick", onHover = "onMediaInlineHover", tooltip = "Play / pause"}))
  end
  if noctalia.getConfig("show_progress_bar") ~= false and length > 0 then
    local compact = math.max(24, math.min(300, noctalia.getConfig("progress_width") or 35))
    local expanded = math.max(compact, math.min(500, noctalia.getConfig("progress_expand_width") or 35))
    table.insert(children, ui.slider({key = "song-progress", min = 0, max = length / 1000000, step = 1,
      value = seekDraft or math.max(0, math.min(length, position)) / 1000000,
      width = compact + (expanded - compact) * progress, height = math.max(4, math.min(24, noctalia.getConfig("progress_thickness") or 8)), controlSize = "sm",
      onChange = "onSeekChange", onDragEnd = "onSeekRelease"}))
  end
  else
    local showBar = noctalia.getConfig("show_progress_bar") ~= false and length > 0
    local compact = math.max(24, math.min(300, noctalia.getConfig("progress_width") or 35))
    local expanded = math.max(compact, math.min(500, noctalia.getConfig("progress_expand_width") or 35))
    local classicDrag = noctalia.getConfig("progress_style") == "classic_drag"
    local barWidth = classicDrag and expanded or compact + (expanded - compact) * progress
    local roundPct = noctalia.getConfig("corner_rounding") or 100
    local cover = nil
    if noctalia.getConfig("show_cover_art") ~= false then cover = resolveCoverPath(roundPct) end
    local parts = {}
    if cover then
      table.insert(parts, ui.image({key = "cover", path = cover, width = coverSize, height = coverSize,
        onClick = "onPlaybackClick", onHover = "onMediaInlineHover"}))
    end
    if showBar then
      local barHeight = math.max(4, math.min(24, noctalia.getConfig("progress_thickness") or 8))
      local filledWidth = barWidth * math.max(0, math.min(1, (seekDraft or position / 1000000) * 1000000 / length))
      local inputHeight = 38
      table.insert(parts, ui.row({key = "classic-progress-hit", height = inputHeight, gap = -barWidth, align = "center",
        onClick = "onClassicSeekClick"}, {
        ui.row({key = "classic-track-layer", width = barWidth, height = inputHeight, align = "center"}, {
          ui.box({key = "classic-track", width = barWidth, height = barHeight, radius = barHeight / 2, fill = "#ffffff47"}),
        }),
        ui.row({key = "classic-fill-layer", width = barWidth, height = inputHeight, gap = 0, align = "center"}, {
          ui.box({key = "classic-fill", width = filledWidth, height = barHeight, radius = math.min(barHeight, filledWidth) / 2, fill = "#ffffff"}),
          ui.box({width = barWidth - filledWidth, height = 1, fill = "#00000000"}),
        }),
        classicDrag and ui.slider({key = "classic-drag", width = barWidth, height = inputHeight,
          min = 0, max = length / 1000000, step = 1, value = seekDraft or position / 1000000, opacity = 0,
          onChange = "onSeekChange", onDragEnd = "onSeekRelease"})
        or ui.graph({key = "classic-seek-pointer", width = barWidth, height = inputHeight, values = {0, 0},
          color = "#00000000", lineWidth = 0, fillOpacity = 0,
          onPointerMove = "onClassicSeekMove", onPointerLeave = "onClassicSeekLeave"}),
      }))
    end
    if #parts == 0 then
      table.insert(parts, ui.glyph({name = playing and "player-play-filled" or "player-pause-filled", size = coverSize}))
    end
    table.insert(children, (barWidget.isVertical() and ui.column or ui.row)({key = "classic-art-progress",
      gap = coverSize * COMBO_GAP / ROUND_SIZE, align = "center"}, parts))
  end
  local full = fullText()
  local compactLen, expandLen = widthRange()
  local fullLen = utf8.len(full) or #full
  local width = math.floor(compactLen + (expandLen - compactLen) * progress + 0.5)
  local text = full
  if fullLen > width then
    if hovering then
      local loop = full .. "   "
      text = utf8Window(loop .. full, scrollOffset % (utf8.len(loop) or #loop), width)
    else text = `{utf8Sub(full, math.max(width - 3, 1))}...` end
  end
  table.insert(children, ui.label({key = "title", text = text}))
  barWidget.render((barWidget.isVertical() and ui.column or ui.row)({gap = 6, align = "center", onHover = "onMediaInlineHover"}, children))
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
  if activePlayer ~= "" then noctalia.runAsync({"playerctl", "-p", activePlayer, "play-pause"}) end
end

function onRightClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center media")
end

-- Scroll to skip tracks. Host calls onScroll(axis, steps): axis "vertical"/
-- "horizontal", steps signed whole detents (negative = scroll up on Wayland).
function onScroll(axis, steps)
  local n = tonumber(steps) or 0
  if axis ~= "vertical" or n == 0 then
    return
  end
  if n < 0 then
    if activePlayer ~= "" then noctalia.runAsync({"playerctl", "-p", activePlayer, "previous"}) end
  else
    if activePlayer ~= "" then noctalia.runAsync({"playerctl", "-p", activePlayer, "next"}) end
  end
end
