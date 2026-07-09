--!nonstrict
-- Now-playing via playerctl/MPRIS. Compact width is 20 chars; hovering
-- animates open to 40 chars, but only actually grows if the text is longer
-- than 20 -- a short title just stays put. If the text is still too long even
-- at 40 chars while hovering, it scrolls as a marquee instead of truncating.
-- Left-click opens the media panel, right-click toggles play/pause (matches
-- the native Media widget's own click/right-click split).

local COMPACT_LEN = 20
local EXPAND_LEN = 40
local COVER_SIZE = 20 -- px, square cover-art icon in place of the play/pause glyph
local BAR_LEN = 8 -- characters in the inline playback-progress bar

-- Same open/close tuning as the clock/volume/sysmon widgets: 0.16 @ 16ms.
local EASE = 0.16
local ANIM_INTERVAL = 16
local SCROLL_INTERVAL = 400 -- ms per marquee character step
local IDLE_INTERVAL = 1000 -- ms poll cadence when settled and not scrolling

local hovering = false
local progress = 0.0 -- 0 = compact (20), 1 = expanded (40)
local target = 0.0
local scrollOffset = 0

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
local COVER_PATH = `{CACHE_DIR}/cover.jpg`
noctalia.mkdirAll(CACHE_DIR)

local lastRequestedArtUrl = nil
local downloadedArtUrl = nil

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

local function pollMedia()
  noctalia.runAsync(
    "playerctl metadata --format '{{status}}|{{artist}}|{{mpris:artUrl}}|{{position}}|{{mpris:length}}|{{title}}' 2>/dev/null",
    function(result)
      local out = result.stdout or ""
      -- title is last/greedy since it's the only field likely to contain
      -- stray characters; the others are safe to split on "|".
      local status, a, url, pos, len, t =
        string.match(out, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.-)%s*$")
      if not status or status == "" then
        hasMedia = false
        return
      end
      hasMedia = true
      playing = status == "Playing"
      artist = a or ""
      title = t or ""
      artUrl = url or ""
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
local function resolveCoverPath(): string?
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
      noctalia.download(artUrl, COVER_PATH, function(ok)
        if ok then
          downloadedArtUrl = artUrl
        end
      end)
    end
    if downloadedArtUrl == artUrl then
      return COVER_PATH
    end
  end

  return nil
end

-- A short block-character bar (needs the monospace font to line up/render;
-- see setFont below) reflecting playback position -- the closest available
-- stand-in for a background progress fill, since bar widgets have no
-- rect/opacity primitive to paint one behind the text.
local function progressBar(): string
  if not hasMedia or length <= 0 then
    return ""
  end
  local frac = math.max(0, math.min(1, position / length))
  local filled = math.floor(frac * BAR_LEN + 0.5)
  return string.rep("█", filled) .. string.rep("░", BAR_LEN - filled) .. " "
end

local function render()
  if not hasMedia then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)
  -- Block-bar and glyph/cover-art text share one label, so the whole run
  -- has to be one font -- monospace (unlike Adwaita Sans) has the bar
  -- characters, and covers artist/title fine too.
  barWidget.setFont("monospace")

  local coverPath = resolveCoverPath()
  if coverPath then
    barWidget.setImage(coverPath, true, COVER_SIZE)
  else
    barWidget.setGlyph(playing and "player-play-filled" or "player-pause-filled")
  end

  local bar = progressBar()
  local full = fullText()
  local fullLen = utf8.len(full) or #full
  local width = math.floor(COMPACT_LEN + (EXPAND_LEN - COMPACT_LEN) * progress + 0.5)

  if fullLen <= width then
    barWidget.setText(bar .. full)
  elseif hovering then
    local loop = full .. "   "
    local loopLen = utf8.len(loop) or #loop
    local start = scrollOffset % loopLen
    local window = utf8Window(loop .. full, start, width)
    barWidget.setText(bar .. window)
  else
    barWidget.setText(`{bar}{utf8Sub(full, math.max(width - 3, 1))}...`)
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
  local fullLen = utf8.len(full) or #full
  local width = math.floor(COMPACT_LEN + (EXPAND_LEN - COMPACT_LEN) * progress + 0.5)
  local needsScroll = hovering and hasMedia and fullLen > width

  if needsScroll then
    scrollOffset += 1
    noctalia.setUpdateInterval(SCROLL_INTERVAL)
    render()
  else
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
