--!nonstrict
-- Volume: glyph + percentage, with a text "slider" (bar + knob) shown between
-- them only while hovering. Left-click steps volume up, right-click down,
-- middle-click toggles mute. Not actually draggable: the plugin bridge only
-- forwards onClick/onRightClick/onMiddleClick/onHover to bar widgets, never
-- pointer position or drag motion, so a real click-and-drag knob isn't
-- reachable from a plugin -- this fakes the look with block characters.

local SINK = "@DEFAULT_AUDIO_SINK@"
local TRACK_LEN = 10
local STEP = "5%"

local vol = 0.5
local muted = false
local hovering = false

local function glyphFor(v: number, isMuted: boolean): string
  if isMuted or v <= 0.0 then
    return "volume-mute"
  elseif v < 0.4 then
    return "volume-low"
  end
  return "volume-high"
end

local function clamp(x: number, lo: number, hi: number): number
  if x < lo then
    return lo
  elseif x > hi then
    return hi
  end
  return x
end

local function slider(v: number): string
  local knobPos = clamp(math.floor(v * (TRACK_LEN - 1) + 0.5) + 1, 1, TRACK_LEN)
  local leading = string.rep("―", knobPos - 1)
  local trailing = string.rep("―", TRACK_LEN - knobPos)
  return `{leading}●{trailing}`
end

local function render()
  barWidget.setFont("Adwaita Sans")
  barWidget.setGlyph(glyphFor(vol, muted))
  local pct = math.floor(vol * 100 + 0.5)
  if hovering then
    barWidget.setText(`{slider(vol)} {pct}%`)
  else
    barWidget.setText(`{pct}%`)
  end
end

function onHover(isHovering: boolean)
  hovering = isHovering
  render()
end

local function applyResult(result)
  local volStr = string.match(result.stdout, "Volume:%s*([%d%.]+)")
  if volStr then
    vol = tonumber(volStr) or vol
    muted = string.find(result.stdout, "MUTED") ~= nil
    render()
  end
end

local function poll()
  noctalia.runAsync(`wpctl get-volume {SINK}`, applyResult, 1500)
end

function update()
  noctalia.setUpdateInterval(750)
  poll()
end

function onClick()
  noctalia.runAsync(`wpctl set-volume {SINK} {STEP}+ -l 1.0`, function(_result)
    poll()
  end, 1500)
end

function onRightClick()
  noctalia.runAsync(`wpctl set-volume {SINK} {STEP}- -l 1.0`, function(_result)
    poll()
  end, 1500)
end

function onMiddleClick()
  noctalia.runAsync(`wpctl set-mute {SINK} toggle`, function(_result)
    poll()
  end, 1500)
end
