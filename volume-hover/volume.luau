--!nonstrict
-- Classic rounded track and circular knob, drawn at their actual dimensions.
-- Audio writes are serialized and coalesced; old reads cannot undo a new click.
local SINK = "@DEFAULT_AUDIO_SINK@"
local vol, muted = 0.5, false
local hovering, progress, target = false, 0, 0
local pointerX, trackWidth = nil, 0
local generation = 0
local wantedVolume, wantedMute = nil, nil
local writePending, pollPending = false, false
local pollElapsed = 300
local render, poll, flush
local function clamp(v, low, high) return math.max(low, math.min(high, v)) end
local function number(key, default)
  local value = noctalia.getConfig(key)
  return type(value) == "number" and value or default
end
local function boolean(key, default)
  local value = noctalia.getConfig(key)
  return type(value) == "boolean" and value or default
end
local function thickness() return clamp(number("slider_thickness", 12), 4, 24) end
local function colour()
  local role = tostring(noctalia.getConfig("bar_color") or "primary")
  return role == "onsurface" and "on_surface" or role
end
poll = function()
  if pollPending or writePending or wantedVolume ~= nil or wantedMute ~= nil then return end
  pollPending = true
  local readGeneration = generation
  noctalia.runAsync({"wpctl", "get-volume", SINK}, function(result)
    pollPending = false
    if readGeneration ~= generation or writePending or wantedVolume ~= nil or wantedMute ~= nil then
      poll()
      return
    end
    local value = string.match(result.stdout or "", "Volume:%s*([%d%.]+)")
    if result.exitCode == 0 and value then
      vol = tonumber(value) or vol
      muted = string.find(result.stdout or "", "MUTED") ~= nil
      render()
    end
  end, 3000)
end
flush = function()
  if writePending then return end
  local command = nil
  if wantedMute ~= nil then
    command = {"wpctl", "set-mute", SINK, wantedMute and "1" or "0"}
    wantedMute = nil
  elseif wantedVolume ~= nil then
    command = {"wpctl", "set-volume", "-l", "1.0", SINK, tostring(wantedVolume)}
    wantedVolume = nil
  end
  if command == nil then poll(); return end
  writePending = true
  noctalia.runAsync(command, function(result)
    writePending = false
    if result.exitCode ~= 0 then barWidget.setTooltip("Audio change failed; refreshing actual volume") end
    flush()
  end, 3000)
end
local function requestVolume(value)
  vol = clamp(value, 0, 1)
  wantedVolume = vol
  generation += 1
  render()
  flush()
end
function onVolumeDrag(value)
  local requested = tonumber(value)
  if requested then requestVolume(requested) end
end
function onVolumeDragEnd() flush() end
function onSpeakerClick()
  muted = not muted
  wantedMute = muted
  generation += 1
  render()
  flush()
end
function onInlineHover(state) onHover(state == "true") end
function onVolumeBarMove(x)
  pointerX = tonumber(x)
  if not hovering then onHover(true) end
end
function onVolumeBarLeave()
  pointerX = nil
  onHover(false)
end
function onVolumeBarClick()
  if pointerX == nil or trackWidth <= 0 then return end
  local radius = thickness() * 0.75
  requestVolume((pointerX * trackWidth - radius) / math.max(1, trackWidth - radius * 2))
end
render = function()
  local color = colour()
  local glyph = muted and "volume-off" or (vol < 0.4 and "volume-2" or "volume")
  local icon = ui.glyph({key = "speaker", name = glyph, size = 20, color = color})
  local speakerClick = nil
  if noctalia.getConfig("icon_click") ~= "panel" then speakerClick = "onSpeakerClick" end
  local speaker = ui.row({key = "speaker-target", width = 24, height = 24, align = "center",
    onHover = "onInlineHover",
    onClick = speakerClick}, {icon})
  local children = {speaker}
  trackWidth = 0
  local draggingEnabled = boolean("drag_enabled", false)
  if progress > 0.01 or draggingEnabled then
    trackWidth = math.max(thickness() * 2, clamp(number("slider_width", 90), 40, 300) * (draggingEnabled and 1 or progress))
    local h = thickness()
    local diameter = h * 1.5
    local knobStart = clamp(vol, 0, 1) * (trackWidth - diameter)
    -- Full-width layers overlap. The knob is sized independently of bar width,
    -- so its radius remains circular at every configured aspect ratio.
    local knob = ui.row({key = "knob-layer", gap = 0, width = trackWidth, height = diameter, align = "center"}, {
      ui.box({width = knobStart, height = 1, fill = "#00000000"}),
      ui.box({key = "knob", width = diameter, height = diameter, radius = diameter / 2, fill = color}),
      ui.box({width = math.max(0, trackWidth - diameter - knobStart), height = 1, fill = "#00000000"}),
    })
    local layers = {
      ui.progress({key = "classic-track", width = trackWidth, height = h, radius = h / 2,
        progress = clamp(vol, 0, 1), fill = color, track = color .. "/0.23"}),
      knob,
    }
    if draggingEnabled then
      table.insert(layers, ui.slider({key = "volume-drag", width = trackWidth, height = diameter,
        min = 0, max = 1, step = 0.01, value = clamp(vol, 0, 1), opacity = 0,
        onChange = "onVolumeDrag", onDragEnd = "onVolumeDragEnd"}))
    else
      table.insert(layers, ui.graph({key = "volume-pointer", width = trackWidth, height = diameter, values = {0, 0},
        color = "#00000000", lineWidth = 0, fillOpacity = 0,
        onPointerMove = "onVolumeBarMove", onPointerLeave = "onVolumeBarLeave"}))
    end
    table.insert(children, ui.row({key = "volume-hit", width = trackWidth, height = diameter,
      gap = -trackWidth, align = "center", opacity = muted and 0.65 or 1,
      onClick = "onVolumeBarClick"}, layers))
  end
  if boolean("show_percent", true) then
    table.insert(children, ui.label({key = "percentage", text = muted and "muted" or `{math.floor(vol * 100 + 0.5)}%`}))
  end
  barWidget.render((barWidget.isVertical() and ui.column or ui.row)({gap = 6, align = "center",
    onHover = "onInlineHover"}, children))
end
local function step()
  local interval = 300
  if math.abs(progress - target) > 0.01 then
    progress += (target - progress) * 0.16
    interval = 16
  else progress = target end
  render()
  noctalia.setUpdateInterval(interval)
  pollElapsed += interval
  if pollElapsed >= 300 then pollElapsed = 0; poll() end
end
function update() step() end
function onHover(value)
  hovering = value
  target = value and 1 or 0
  step()
end
function onConfigChanged() render() end
function onScroll(axis, steps)
  local n = tonumber(steps) or 0
  if axis ~= "vertical" or n == 0 then return end
  local up = n < 0
  if boolean("invert_scroll", false) then up = not up end
  requestVolume(vol + (up and 1 or -1) * math.abs(n) * clamp(number("scroll_step", 5), 1, 25) / 100)
end
