--!nonstrict
-- Download speed. Auto-detects the busiest non-loopback interface each poll
-- (adapts if you switch between wired/wifi). Compact hides the number below
-- the configurable idle threshold; hovering always shows it.

local hovering = false
local kbps = 0.0

local progress = 0.0 -- 0 = fully hidden/closed, 1 = fully open
local target = 0.0

-- Same tuning as the clock/volume widgets: 0.16 @ 16ms (~60fps).
local EASE = 0.16
local ANIM_INTERVAL = 16
local IDLE_INTERVAL = 1000

-- utf8.len/offset find character boundaries so a partial reveal never cuts a
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

local prevRx = nil
local prevAt = nil

local function primaryInterfaceStats()
  local dev = noctalia.readFile("/proc/net/dev")
  if not dev then
    return nil
  end
  local bestRx, bestTotal = nil, -1
  for line in string.gmatch(dev, "[^\n]+") do
    local iface, rx, tx = string.match(line, "^%s*([%w_.-]+):%s*(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)")
    if iface and iface ~= "lo" then
      local total = tonumber(rx) + tonumber(tx)
      if total > bestTotal then
        bestTotal = total
        bestRx = tonumber(rx)
      end
    end
  end
  return bestRx
end

local function updateSpeed()
  local rx = primaryInterfaceStats()
  local nowStr = noctalia.formatTime("%s")
  local now = tonumber(nowStr)
  if rx and now and prevRx and prevAt and rx >= prevRx then
    local dt = now - prevAt
    if dt > 0 then
      kbps = (rx - prevRx) / 1024 / dt
    end
  end
  prevRx = rx
  prevAt = now
end

local function speedText(v: number, compact: boolean): string
  if v >= 1024 then
    local unit = compact and "M" or "MB/s"
    return `{string.format("%.1f", v / 1024)}{unit}`
  elseif v >= 1 then
    local unit = compact and "K" or "KB/s"
    return `{string.format("%.0f", v)}{unit}`
  end
  local unit = compact and "B" or "B/s"
  return `{string.format("%.0f", v * 1024)}{unit}`
end

local function computeTarget(): number
  local threshold = barWidget.getConfig("threshold_kbps") or 1024
  return (hovering or kbps >= threshold) and 1.0 or 0.0
end

local function render()
  barWidget.setFont("Adwaita Sans")

  if progress <= 0.001 then
    if barWidget.getConfig("hide_completely") ~= false then
      barWidget.setVisible(false)
    else
      barWidget.setVisible(true)
      barWidget.setGlyph("download-speed")
      barWidget.setText("")
    end
    return
  end

  barWidget.setVisible(true)
  barWidget.setGlyph("download-speed")
  local compact = not hovering and barWidget.getConfig("compact_units") ~= false
  local full = speedText(kbps, compact)
  local revealLen = math.floor(utf8.len(full) * progress + 0.5)
  barWidget.setText(utf8Sub(full, revealLen))
end

local function step()
  target = computeTarget()
  if math.abs(progress - target) < 0.01 then
    progress = target
    noctalia.setUpdateInterval(IDLE_INTERVAL)
    updateSpeed()
    target = computeTarget()
  else
    progress = progress + (target - progress) * EASE
    noctalia.setUpdateInterval(ANIM_INTERVAL)
  end
  render()
end

function update()
  step()
end

function onHover(isHovering: boolean)
  hovering = isHovering
  step()
end

function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center system")
end
