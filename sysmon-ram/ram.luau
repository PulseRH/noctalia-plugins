--!nonstrict
-- RAM: compact gauge glyph + percent (gauge toggleable in widget settings).
-- Hover adds used/total in GB (total auto-detected, not hardcoded).

local pct = 0.0
local usedGb = 0.0
local totalGb = 0.0

local progress = 0.0 -- 0 = closed, 1 = fully open
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

local function update_meminfo()
  local info = noctalia.readFile("/proc/meminfo")
  if not info then
    return
  end
  local totalKb = tonumber(string.match(info, "MemTotal:%s*(%d+)"))
  local availKb = tonumber(string.match(info, "MemAvailable:%s*(%d+)"))
  if not totalKb or not availKb then
    return
  end
  local usedKb = totalKb - availKb
  pct = usedKb / totalKb * 100
  usedGb = usedKb / 1024 / 1024
  totalGb = totalKb / 1024 / 1024
end

-- Real vertical block-element glyphs (▁..█), each one grows from the bottom
-- like an actual gauge -- confirmed present in the system monospace font
-- (Noto Sans Mono), unlike Adwaita Sans which lacks this whole block.
local BLOCKS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

local function gaugeChar(v: number): string
  local idx = math.floor(v / 100 * #BLOCKS + 0.5)
  if idx < 1 then
    idx = 1
  elseif idx > #BLOCKS then
    idx = #BLOCKS
  end
  return BLOCKS[idx]
end

local function render()
  barWidget.setGlyph("memory")
  local pctText = `{math.floor(pct + 0.5)}%`
  local useGauge = barWidget.getConfig("gauge")

  if useGauge ~= false then
    barWidget.setFont("monospace")
  else
    barWidget.setFont("Adwaita Sans")
  end

  local parts = {}
  if useGauge ~= false then
    parts[#parts + 1] = gaugeChar(pct)
  end
  parts[#parts + 1] = pctText
  local base = table.concat(parts, " ")

  local extra = `{string.format("%.1f", usedGb)}/{math.floor(totalGb + 0.5)}GB`
  local revealLen = math.floor(utf8.len(extra) * progress + 0.5)
  if revealLen > 0 then
    barWidget.setText(`{base} {utf8Sub(extra, revealLen)}`)
  else
    barWidget.setText(base)
  end
end

local function step()
  if math.abs(progress - target) < 0.01 then
    progress = target
    noctalia.setUpdateInterval(IDLE_INTERVAL)
    update_meminfo()
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
  target = isHovering and 1.0 or 0.0
  step()
end

function onClick()
  noctalia.runAsync("noctalia msg panel-toggle control-center system")
end
