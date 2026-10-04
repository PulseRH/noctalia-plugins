--!nonstrict
-- Volume: a persistent speaker glyph (Tabler, struck-through when muted) with a
-- solid rounded slider that reveals to its right on hover, animating open/close
-- with the same eased timing as the other hover widgets. Scroll changes volume,
-- click the speaker/bar to toggle mute; label/padding and right-click open Audio. Speaker + bar are baked
-- together into one image (a bar widget has a single glyph-or-image slot), so
-- reveal frames are pre-baked and swapped per animation step. Needs ImageMagick;
-- without it, falls back to a plain glyph + percentage.

local SINK = "@DEFAULT_AUDIO_SINK@"
local TABLER = nil
local dataDirs = (noctalia.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share")
for dir in string.gmatch(dataDirs, "[^:]+") do
  local candidate = `{dir}/noctalia/assets/fonts/noctalia-tabler.ttf`
  if noctalia.fileExists(candidate) then TABLER = candidate; break end
end
local function shQuote(value: string): string
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end
-- Tabler codepoints as UTF-8: volume(EB51) volume-2(EB4F) volume-off(F1C3)
local GLYPH = { hi = "\xEE\xAD\x91", lo = "\xEE\xAD\x8F", off = "\xEF\x87\x83" }

-- ── bake geometry (canvas px; displayed scaled down) ─────────────────────────
local CANVAS_H = 56
local SPK_AREA = 52 -- left region holding the speaker glyph
local BAR_FULL = 200 -- full bar reveal width
local FULL_W = SPK_AREA + BAR_FULL -- 252
local KNOB_R = 18
local BX1 = SPK_AREA + KNOB_R -- 70   knob travel left
local BX2 = FULL_W - KNOB_R -- 234  knob travel right
local TRACK_Y = 28
local TRK_Y1, TRK_Y2 = TRACK_Y - 5, TRACK_Y + 5 -- thin empty track
local FIL_Y1, FIL_Y2 = TRACK_Y - 12, TRACK_Y + 12 -- thick fill
local KNOB_BOT = TRACK_Y + KNOB_R
local OPEN_STEPS = 8 -- reveal animation levels
local FILL_STEPS = 40 -- volume buckets

-- ── animation (matches clock-hover feel) ─────────────────────────────────────
local EASE = 0.16
local ANIM_INTERVAL = 16
local IDLE_INTERVAL = 900
local POLL_MS = 700

local DATA_DIR = noctalia.pluginDataDir() or noctalia.expandPath("~/.cache/noctalia-plugins/volume-hover")
local CACHE_DIR = `{DATA_DIR}/cache/volume-hover`
-- ── state ────────────────────────────────────────────────────────────────────
local vol, muted = 0.5, false
local render, poll
local hovering = false
local progress, target = 0.0, 0.0
local pollAccum = POLL_MS
local curColor = "ffb4a5"
local MAGICK = nil
local ready = {} -- path -> true (baked/on-disk)
local pending = {} -- path -> true (bake in flight)
local lastPath, lastDispW, lastDispH = nil, 0, 0

local function clamp(x, lo, hi)
  if x < lo then return lo elseif x > hi then return hi end
  return x
end
local function round(x) return math.floor(x + 0.5) end

local function cfgNumber(key, default)
  local v = noctalia.getConfig(key)
  if type(v) == "number" then return v end
  return default
end
local function cfgBool(key, default)
  local v = noctalia.getConfig(key)
  if type(v) == "boolean" then return v end
  return default
end

local function scale() return clamp(cfgNumber("slider_width", 90), 40, 240) / BAR_FULL end
local function iconState()
  if muted then return "off" elseif vol < 0.4 then return "lo" else return "hi" end
end
local function bucketFor(v) return clamp(round(v * FILL_STEPS), 0, FILL_STEPS) end

local function refreshColor()
  local role = tostring(noctalia.getConfig("bar_color") or "primary"):lower()
  if role == "onsurface" then role = "on_surface" end
  local color = noctalia.getColor(role) or noctalia.getColor("primary") or "#ffb4a5"
  curColor = string.gsub(color, "#", "")
end

-- ── frame identity ────────────────────────────────────────────────────────────
-- os == 0 is the resting speaker-only frame (no bar; depends on colour+icon).
-- os >= 1 reveals the bar for the current volume bucket.
local function revealW(os) return SPK_AREA + round(os / OPEN_STEPS * BAR_FULL) end
local function restPath(ic) return `{CACHE_DIR}/spk-{curColor}-{ic}.png` end
local function revPath(bucket, os) return `{CACHE_DIR}/rev-{curColor}-{if muted then "m" else "n"}-{bucket}-{os}.png` end

local function speakerCmd(out, w, ic)
  local spkA = if ic == "off" then "B0" else "FF"
  return `{MAGICK} -size {w}x{CANVAS_H} xc:none -font {shQuote(TABLER)} -pointsize 40`
    .. ` -fill '#{curColor}{spkA}' -gravity West -annotate +8+0 '{GLYPH[ic]}' {shQuote(out)}`
end

local function revealCmd(out, os, bucket)
  local w = revealW(os)
  local ic = iconState()
  local frac = bucket / FILL_STEPS
  local knobX = round(BX1 + frac * (BX2 - BX1))
  local C = `#{curColor}`
  local spkA = if muted then "B0" else "FF"
  local trackA = if muted then "24" else "3A"
  local fillA = if muted then "8C" else "FF"
  local knobA = if muted then "B0" else "FF"
  local fillPart = ""
  if knobX > BX1 + 6 then
    fillPart = ` -fill '{C}{fillA}' -draw 'roundRectangle {BX1},{FIL_Y1} {knobX},{FIL_Y2} 12,12'`
  end
  return `{MAGICK} -size {w}x{CANVAS_H} xc:none`
    .. ` -font {shQuote(TABLER)} -pointsize 40 -fill '{C}{spkA}' -gravity West -annotate +8+0 '{GLYPH[ic]}'`
    .. ` -gravity NorthWest`
    .. ` -fill '{C}{trackA}' -draw 'roundRectangle {BX1},{TRK_Y1} {BX2},{TRK_Y2} 5,5'`
    .. fillPart
    .. ` -fill '{C}{knobA}' -draw 'circle {knobX},{TRACK_Y} {knobX},{KNOB_BOT}'`
    .. ` {shQuote(out)}`
end

local function bake(path, cmd)
  if ready[path] or pending[path] then return end
  if noctalia.fileExists(path) then ready[path] = true; return end
  pending[path] = true
  noctalia.runAsync(cmd, function(_r)
    pending[path] = nil; ready[path] = _r.exitCode == 0 and noctalia.fileExists(path)
    if ready[path] and render then render() end
  end, 4000)
end

-- Pre-bake every reveal frame for the current bucket so the hover animation is
-- smooth (magick is too slow to bake per 16ms frame).
local function prebake(bucket)
  bake(restPath(iconState()), speakerCmd(restPath(iconState()), SPK_AREA, iconState()))
  for os = 1, OPEN_STEPS do
    local p = revPath(bucket, os)
    bake(p, revealCmd(p, os, bucket))
  end
end

-- ── render ────────────────────────────────────────────────────────────────────
function onSpeakerClick()
  muted = not muted
  render()
  noctalia.runAsync({"wpctl", "set-mute", SINK, "toggle"}, function() poll() end, 1500)
end
function onInlineHover(state)
  onHover(state == "true")
end
local classicPointerX = nil
local classicBarWidth = 0
function onVolumeBarMove(x)
  classicPointerX = tonumber(x)
  if not hovering then onHover(true) end
end
function onVolumeBarLeave()
  classicPointerX = nil
  onHover(false)
end
function onVolumeBarClick()
  if classicPointerX == nil or classicBarWidth <= 0 then return end
  -- Account for the original knob's half-width at each end of its travel.
  local value = clamp((classicPointerX * classicBarWidth / scale() - KNOB_R) / (BAR_FULL - 2 * KNOB_R), 0, 1)
  vol = value
  render()
  noctalia.runAsync({"wpctl", "set-volume", "-l", "1.0", SINK, tostring(value)}, function() poll() end, 1500)
end
local function drawClassic(path, width, height)
  local children = {}
  local click = if noctalia.getConfig("icon_click") == "panel" then nil else "onSpeakerClick"
  if path then
    local speakerWidth = round(SPK_AREA * scale())
    classicBarWidth = math.max(0, width - speakerWidth)
    local layers = {ui.image({key = "speaker-bar", path = path, width = width, height = height,
      onClick = click, onHover = "onInlineHover"})}
    if classicBarWidth > 0 then
      -- Transparent graph supplies normalized pointer coordinates; an overlap
      -- row puts its hit area exactly over the existing raster bar, leaving the
      -- speaker as its own click target. Neither control changes the artwork.
      table.insert(layers, ui.row({key = "volume-hit", width = classicBarWidth, height = height,
        onClick = "onVolumeBarClick"}, {
        ui.graph({key = "volume-pointer", width = classicBarWidth, height = height, values = {0, 0},
          color = "#00000000", lineWidth = 0, fillOpacity = 0,
          onPointerMove = "onVolumeBarMove", onPointerLeave = "onVolumeBarLeave"}),
      }))
    end
    table.insert(children, ui.row({key = "classic-volume", gap = -classicBarWidth, align = "center"}, layers))
  elseif click then
    table.insert(children, ui.button({key = "speaker", glyph = if muted then "volume-off" elseif vol < 0.4 then "volume-2" else "volume",
      glyphSize = 20, width = 24, height = 24, variant = "ghost", onClick = click, onHover = "onInlineHover"}))
  else
    table.insert(children, ui.glyph({key = "speaker", name = if muted then "volume-off" elseif vol < 0.4 then "volume-2" else "volume", size = 20}))
  end
  if cfgBool("show_percent", true) then
    table.insert(children, ui.label({key = "percentage", text = if muted then "muted" else `{round(vol * 100)}%`}))
  end
  barWidget.setTooltip(if muted then "Muted" else `Volume {round(vol * 100)}%`)
  barWidget.render((barWidget.isVertical() and ui.column or ui.row)({gap = 6, align = "center", onHover = "onInlineHover"}, children))
end

render = function()
  if not MAGICK then
    drawClassic(nil, 0, 0)
    return
  end

  local sc = scale()
  local dispH = round(CANVAS_H * sc)
  local os = clamp(round(progress * OPEN_STEPS), 0, OPEN_STEPS)
  local bucket = bucketFor(vol)

  local path, w
  if os == 0 then
    local ic = iconState()
    path, w = restPath(ic), SPK_AREA
    bake(path, speakerCmd(path, SPK_AREA, ic))
  else
    path, w = revPath(bucket, os), revealW(os)
    if not ready[path] and not noctalia.fileExists(path) then
      prebake(bucket)
    end
  end

  if ready[path] or noctalia.fileExists(path) then
    ready[path] = true
    local dispW = round(w * sc)
    drawClassic(path, dispW, dispH)
    lastPath, lastDispW, lastDispH = path, dispW, dispH
  elseif lastPath then
    drawClassic(lastPath, lastDispW, lastDispH) -- hold last frame until bake lands
  else
    drawClassic(nil, 0, 0)
  end
end

-- ── volume plumbing ──────────────────────────────────────────────────────────
local function applyResult(result)
  local volStr = string.match(result.stdout, "Volume:%s*([%d%.]+)")
  if volStr then
    vol = tonumber(volStr) or vol
    muted = string.find(result.stdout, "MUTED") ~= nil
    render()
  end
end
poll = function() noctalia.runAsync(`wpctl get-volume {SINK}`, applyResult, 1500) end

local function adjust(up)
  local step = round(clamp(cfgNumber("scroll_step", 5), 1, 25))
  noctalia.runAsync(`wpctl set-volume {SINK} {step}%{if up then "+" else "-"} -l 1.0`,
    function(_r) poll() end, 1500)
end

-- ── animation loop ────────────────────────────────────────────────────────────
local function step()
  local interval
  if math.abs(progress - target) < 0.01 then
    progress = target
    interval = IDLE_INTERVAL
  else
    progress = progress + (target - progress) * EASE
    interval = ANIM_INTERVAL
  end
  noctalia.setUpdateInterval(interval)
  render()
  pollAccum += interval
  if pollAccum >= POLL_MS then pollAccum = 0; poll() end
end

function update()
  if MAGICK == nil then
    if TABLER and noctalia.commandExists("magick") then MAGICK = "magick"
    elseif TABLER and noctalia.commandExists("convert") then MAGICK = "convert"
    else MAGICK = false end
    noctalia.mkdirAll(CACHE_DIR)
    refreshColor()
  end
  step()
end

function onHover(isHovering)
  hovering = isHovering
  target = if isHovering then 1.0 else 0.0
  if isHovering and MAGICK then prebake(bucketFor(vol)) end
  step()
end

function onConfigChanged()
  refreshColor()
  ready = {}
  render()
end

function onScroll(axis, steps)
  local n = tonumber(steps) or 0
  if axis ~= "vertical" or n == 0 then return end
  local up = n < 0
  if cfgBool("invert_scroll", false) then up = not up end
  adjust(up)
end
