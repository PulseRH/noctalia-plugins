--!nonstrict
-- Volume: a persistent speaker glyph (Tabler, struck-through when muted) with a
-- solid rounded slider that reveals to its right on hover, animating open/close
-- with the same eased timing as the other hover widgets. Scroll changes volume,
-- left-click opens the audio panel, right-click mutes. Speaker + bar are baked
-- together into one image (a bar widget has a single glyph-or-image slot), so
-- reveal frames are pre-baked and swapped per animation step. Needs ImageMagick;
-- without it, falls back to a plain glyph + percentage.

local SINK = "@DEFAULT_AUDIO_SINK@"
local TABLER = "/usr/share/noctalia/assets/fonts/tabler.ttf"
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

local CACHE_DIR = noctalia.expandPath("~/.cache/noctalia-plugins/volume")
local COLORS_JSON = "~/.config/noctalia/colors.json"
local ROLE_KEYS = {
  primary = "mPrimary", secondary = "mSecondary", tertiary = "mTertiary",
  error = "mError", onsurface = "mOnSurface", surface = "mSurface", hover = "mHover",
}

-- ── state ────────────────────────────────────────────────────────────────────
local vol, muted = 0.5, false
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
  local key = ROLE_KEYS[role] or "mPrimary"
  local txt = noctalia.readFile(COLORS_JSON)
  if txt then
    local t = noctalia.json.decode(txt)
    if t and type(t[key]) == "string" then curColor = (t[key]:gsub("#", "")) end
  end
end

-- ── frame identity ────────────────────────────────────────────────────────────
-- os == 0 is the resting speaker-only frame (no bar; depends on colour+icon).
-- os >= 1 reveals the bar for the current volume bucket.
local function revealW(os) return SPK_AREA + round(os / OPEN_STEPS * BAR_FULL) end
local function restPath(ic) return `{CACHE_DIR}/spk-{curColor}-{ic}.png` end
local function revPath(bucket, os) return `{CACHE_DIR}/rev-{curColor}-{if muted then "m" else "n"}-{bucket}-{os}.png` end

local function speakerCmd(out, w, ic)
  local spkA = if ic == "off" then "B0" else "FF"
  return `{MAGICK} -size {w}x{CANVAS_H} xc:none -font '{TABLER}' -pointsize 40`
    .. ` -fill '#{curColor}{spkA}' -gravity West -annotate +8+0 '{GLYPH[ic]}' '{out}'`
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
    .. ` -font '{TABLER}' -pointsize 40 -fill '{C}{spkA}' -gravity West -annotate +8+0 '{GLYPH[ic]}'`
    .. ` -gravity NorthWest`
    .. ` -fill '{C}{trackA}' -draw 'roundRectangle {BX1},{TRK_Y1} {BX2},{TRK_Y2} 5,5'`
    .. fillPart
    .. ` -fill '{C}{knobA}' -draw 'circle {knobX},{TRACK_Y} {knobX},{KNOB_BOT}'`
    .. ` '{out}'`
end

local function bake(path, cmd)
  if ready[path] or pending[path] then return end
  if noctalia.fileExists(path) then ready[path] = true; return end
  pending[path] = true
  noctalia.runAsync(cmd, function(_r)
    pending[path] = nil; ready[path] = true
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
local function setLabel()
  if cfgBool("show_percent", true) then
    barWidget.setText(if muted then "muted" else `{round(vol * 100)}%`)
  else
    barWidget.setText("")
  end
  barWidget.setTooltip(if muted then "Muted" else `Volume {round(vol * 100)}%`)
end

local function render()
  setLabel()
  if not MAGICK then
    barWidget.setGlyph(if muted then "volume-mute" elseif vol < 0.4 then "volume-low" else "volume-high")
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
    barWidget.setImage(path, false, dispW, dispH)
    lastPath, lastDispW, lastDispH = path, dispW, dispH
  elseif lastPath then
    barWidget.setImage(lastPath, false, lastDispW, lastDispH) -- hold last frame until bake lands
  else
    barWidget.setGlyph(if muted then "volume-mute" elseif vol < 0.4 then "volume-low" else "volume-high")
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
local function poll() noctalia.runAsync(`wpctl get-volume {SINK}`, applyResult, 1500) end

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
    if noctalia.commandExists("magick") then MAGICK = "magick"
    elseif noctalia.commandExists("convert") then MAGICK = "convert"
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

function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center audio", nil, 1500)
end

function onRightClick()
  noctalia.runAsync("noctalia msg volume-mute", function(_r) poll() end, 1500)
end
