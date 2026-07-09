--!nonstrict
-- Now-playing via playerctl/MPRIS. Compact width is 20 chars; hovering
-- animates open to 40 chars, but only actually grows if the text is longer
-- than 20 -- a short title just stays put. If the text is still too long even
-- at 40 chars while hovering, it scrolls as a marquee instead of truncating.
-- Left-click opens the media panel, right-click toggles play/pause (matches
-- the native Media widget's own click/right-click split).

local COMPACT_LEN = 20
local EXPAND_LEN = 40

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
    "playerctl metadata --format '{{status}}|{{artist}}|{{title}}' 2>/dev/null",
    function(result)
      local out = result.stdout or ""
      local status, a, t = string.match(out, "^([^|]*)|([^|]*)|(.-)%s*$")
      if not status or status == "" then
        hasMedia = false
        return
      end
      hasMedia = true
      playing = status == "Playing"
      artist = a or ""
      title = t or ""
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

local function render()
  if not hasMedia then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)
  barWidget.setFont("Adwaita Sans")
  barWidget.setGlyph(playing and "player-play-filled" or "player-pause-filled")

  local full = fullText()
  local fullLen = utf8.len(full) or #full
  local width = math.floor(COMPACT_LEN + (EXPAND_LEN - COMPACT_LEN) * progress + 0.5)

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
