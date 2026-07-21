--!nonstrict
-- Focused window's title via wlrctl (wlr-foreign-toplevel-management protocol --
-- compositor-agnostic, confirmed working under driftwm). Compact/expand width
-- (in characters) are settings below; hovering animates from one to the
-- other, but only actually grows if the title is longer than the compact
-- width. If it's still too long even at the expanded width while hovering,
-- it scrolls as a marquee instead of truncating. Hidden entirely when
-- there's no focused window (e.g. an empty workspace).

-- Icons are rasterized once per app_id at a fixed, generously large size
-- (independent of the icon_size/icon_size_hover settings below) so changing
-- those settings later never needs a re-rasterize -- setImage just downscales
-- the cached file to whatever size is requested each frame.
local ICON_RASTER_SIZE = 64

-- Same open/close tuning as the clock/volume/sysmon/media widgets: 0.16 @ 16ms.
local EASE = 0.16
local ANIM_INTERVAL = 16
local SCROLL_INTERVAL = 150 -- ms per marquee character step
local IDLE_INTERVAL = 1000 -- ms poll cadence when settled and not scrolling

local hovering = false
local progress = 0.0 -- 0 = compact (20), 1 = expanded (40)
local target = 0.0
local scrollOffset = 0

local hasWindow = false
local title = ""
local appId = ""

-- Per-app icon lookup (.desktop entry -> icon theme file, rasterized to a
-- cached PNG) shells out to resolve-icon.sh, since that's a lot of find/case
-- logic that's much more readable as a real shell script than built up as a
-- giant Lua string. Resolved once per app_id for the life of the widget --
-- app icons don't change at runtime.
local CACHE_DIR = `{noctalia.pluginDir()}/cache`
local RESOLVE_SCRIPT = `{noctalia.pluginDir()}/resolve-icon.sh`
noctalia.mkdirAll(CACHE_DIR)

local iconCache = {} -- app_id -> resolved PNG path, or false if not found
local resolving = {} -- app_id -> true while a lookup is in flight

local function shQuote(s: string): string
  return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

local function sanitizeForFilename(s: string): string
  local out = string.gsub(s, "[^%w%.%-]", "_")
  if out == "" then
    return "unknown"
  end
  return out
end

local function resolveIcon(id: string): string?
  local cached = iconCache[id]
  if cached ~= nil then
    if cached == false then
      return nil
    end
    return cached
  end

  if not resolving[id] then
    resolving[id] = true
    local dest = `{CACHE_DIR}/icon-{sanitizeForFilename(id)}.png`
    local cmd = string.format(
      "sh %s %s %s %d",
      shQuote(RESOLVE_SCRIPT),
      shQuote(id),
      shQuote(dest),
      ICON_RASTER_SIZE
    )
    noctalia.runAsync(cmd, function(result)
      resolving[id] = nil
      iconCache[id] = (result.exitCode == 0) and dest or false
    end)
  end

  return nil
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

-- utf8.len/offset find character boundaries so truncation never cuts a
-- multi-byte character in half.
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

-- Returns compact/expand width in characters, expand clamped to be no
-- smaller than compact (a user could otherwise set expand < compact, which
-- would make hovering shrink the text instead of growing it).
local function widthRange(): (number, number)
  local compactLen = noctalia.getConfig("compact_width") or 20
  local expandLen = noctalia.getConfig("expand_width") or 40
  return compactLen, math.max(compactLen, expandLen)
end

local function pollActiveWindow()
  noctalia.runAsync("wlrctl toplevel list state:active 2>/dev/null", function(result)
    local out = result.stdout or ""
    -- "app_id: title" -- app_id never contains ": ", so splitting on the
    -- first occurrence is reliable even if the title itself has a colon.
    local id, t = string.match(out, "^(.-): (.-)%s*$")
    if not t or t == "" then
      hasWindow = false
      return
    end
    hasWindow = true
    title = t
    appId = id or ""
  end)
end

local function render()
  if not hasWindow then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)
  barWidget.setFont("Adwaita Sans")

  local iconPath = appId ~= "" and resolveIcon(appId) or nil
  if iconPath then
    local compactSize = noctalia.getConfig("icon_size") or 20
    local hoverSize = noctalia.getConfig("icon_size_hover") or 28
    local displaySize = math.floor(compactSize + (hoverSize - compactSize) * progress + 0.5)
    barWidget.setImage(iconPath, false, displaySize)
  else
    -- No size control here: the plugin API doesn't expose a glyph-size
    -- setter, only setImage's width/height -- so the generic fallback glyph
    -- stays whatever fixed size the bar's theme uses for every plugin icon.
    barWidget.setGlyph("app-window-filled")
  end

  local compactLen, expandLen = widthRange()
  local fullLen = utf8.len(title) or #title
  local width = math.floor(compactLen + (expandLen - compactLen) * progress + 0.5)

  if fullLen <= width then
    barWidget.setText(title)
  elseif hovering then
    local loop = title .. "   "
    local loopLen = utf8.len(loop) or #loop
    local start = scrollOffset % loopLen
    local window = utf8Window(loop .. title, start, width)
    barWidget.setText(window)
  else
    barWidget.setText(`{utf8Sub(title, math.max(width - 3, 1))}...`)
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

  local compactLen, expandLen = widthRange()
  local fullLen = utf8.len(title) or #title
  local width = math.floor(compactLen + (expandLen - compactLen) * progress + 0.5)
  local needsScroll = hovering and hasWindow and fullLen > width

  if needsScroll then
    scrollOffset += 1
    noctalia.setUpdateInterval(SCROLL_INTERVAL)
    render()
  else
    noctalia.setUpdateInterval(IDLE_INTERVAL)
    pollActiveWindow()
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
