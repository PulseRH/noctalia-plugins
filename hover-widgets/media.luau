--!nonstrict
-- Now-playing via playerctl/MPRIS. Compact/expand width (in characters) are
-- settings below; hovering animates from one to the other, but only actually
-- grows if the text is longer than the compact width -- a short title just
-- stays put. If it's still too long even at the expanded width while
-- hovering, it scrolls as a marquee instead of truncating. Left-click toggles
-- play/pause; right-click opens the media panel.

local COVER_SIZE_DEFAULT = 20 -- px, square cover-art icon in place of the play/pause glyph

-- Progress graphics use native rounded shapes at their configured width and
-- thickness. Cover art uses native ui.image rounding.

-- Same open/close tuning as the clock/volume/sysmon widgets: 0.16 @ 16ms.
local EASE = 0.16
local ANIM_INTERVAL = 16
local SCROLL_INTERVAL = 150 -- ms per marquee character step
local IDLE_INTERVAL = 500 -- ms poll cadence when settled and not scrolling
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

local mediaPollPending, missedMediaPolls = false, 0
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
local classicBarWidth = 0
local renderedSeekValue = nil
local hoveredControl = nil
local hoverLeaveMs = 0
local backgroundSeekX, backgroundSeekOffset, backgroundSeekWidth, backgroundWidth = nil, 0, 0, 0
local function trackKey() return `{activePlayer}|{artist}|{title}|{length}` end

-- Cover art is only ever a local file (barWidget.setImage has no network
-- fetcher), so http(s) art (Spotify etc.) gets downloaded once per track into
-- a cache file and reused; file:// art (most local players) is used directly.
local DATA_DIR = noctalia.pluginDataDir() or noctalia.expandPath("~/.cache/noctalia-plugins/media-mini")
local CACHE_DIR = `{DATA_DIR}/cache/media-mini`
noctalia.mkdirAll(CACHE_DIR)

-- playerctl with no -p picks a player by its own internal ordering, not by
-- who's actually playing -- confirmed it can land on a paused/stale player
-- (e.g. a YouTube tab that navigated away, leaving stale MPRIS metadata)
-- over a genuinely Playing one. pick-player.sh checks all players' status
-- first and prefers one that's actually Playing.
local PICK_PLAYER_SCRIPT = `{noctalia.pluginDir()}/pick-player.sh`

-- URL-keyed files survive reloads and album/track changes. Each request writes
-- its own file, so late completions cannot overwrite another track's artwork.
local coverDownloads = {}
local function coverKey(value)
  local a, b = 0, 0
  for i = 1, #value do
    a = (a * 31 + string.byte(value, i)) % 4294967296
    b = (b * 131 + string.byte(value, i)) % 4294967296
  end
  return string.format("%08x%08x", a, b)
end

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

local function acceptMediaResult(result)
  mediaPollPending = false
  local out = result.stdout or ""
  -- title is last/greedy since it's the only field likely to contain
  -- stray characters; the others are safe to split on "|".
  local selected, status, a, url, pos, len, pageUrl, t =
    string.match(out, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.-)%s*$")
  if result.exitCode ~= 0 or not status or status == "" or selected == "" then
    missedMediaPolls += 1
    -- A seek/track switch can briefly invalidate metadata. Require several
    -- consecutive misses before hiding, instead of flashing out on one read.
    if missedMediaPolls >= 6 then
      hasMedia = false
      seekDraft, seekPlayer, seekTrack = nil, nil, nil
      if render then render() end
    end
    return
  end
  missedMediaPolls = 0
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
end

local function pollMedia()
  if mediaPollPending then return end
  mediaPollPending = true
  noctalia.runAsync(`sh {shQuote(PICK_PLAYER_SCRIPT)}`, acceptMediaResult, 1500)
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
  if artUrl == "" then return nil end
  local localPath = string.match(artUrl, "^file://(.+)$")
  if localPath then return noctalia.string.urlDecode(localPath) end
  if not string.match(artUrl, "^https?://") then return nil end
  local path = `{CACHE_DIR}/{coverKey(artUrl)}.img`
  if not coverDownloads[artUrl] and noctalia.fileExists(path) then return path end
  if not coverDownloads[artUrl] then
    local requestedUrl = artUrl
    coverDownloads[requestedUrl] = true
    noctalia.download(requestedUrl, path, function(ok)
      coverDownloads[requestedUrl] = nil
      if ok and render then render() end
    end)
  end
  return nil
end


function onMediaControlHover(state, key)
  if state == "true" then hoveredControl = key
  elseif hoveredControl == key then hoveredControl = nil end
  onHover(state == "true")
end
local function playbackButton(key, glyph, action, tooltip, size, reveal)
  reveal = reveal or 1
  local highlighted = hoveredControl == key
  local glyphSize = (key == "pause" or key == "playback") and math.min(20, size) or math.min(16, size - 4)
  return ui.row({key = key, width = size * reveal, height = size, align = "center", justify = "center", radius = 5,
    fill = highlighted and "primary/0.2" or "#00000000", onClick = action, onHover = "onMediaControlHover", tooltip = tooltip}, {
    ui.glyph({name = glyph, size = glyphSize * reveal, color = highlighted and "primary" or "on_surface"}),
  })
end
function onMediaInlineHover(state)
  onHover(state == "true")
end
function onPlaybackClick()
  if activePlayer ~= "" then noctalia.runAsync({"playerctl", "-p", activePlayer, "play-pause"}) end
end
function onPreviousClick()
  if activePlayer ~= "" then noctalia.runAsync({"playerctl", "-p", activePlayer, "previous"}, function() pollMedia() end) end
end
function onNextClick()
  if activePlayer ~= "" then noctalia.runAsync({"playerctl", "-p", activePlayer, "next"}, function() pollMedia() end) end
end
function onClassicDragChange(value)
  if length <= 0 or classicBarWidth <= 4 then return end
  local requested = tonumber(value) or 0
  if renderedSeekValue ~= nil and math.abs(requested - renderedSeekValue) < 0.000001 then return end
  local raw = requested
  local fraction = raw <= 0 and 0 or raw >= 1 and 1 or (2 + raw * (classicBarWidth - 4)) / classicBarWidth
  onSeekChange(tostring(fraction * length / 1000000))
end
function onNativeSeekChange(value)
  if renderedSeekValue ~= nil and math.abs((tonumber(value) or 0) - renderedSeekValue) < 0.000001 then return end
  onSeekChange(tostring((tonumber(value) or 0) * length / 1000000))
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
function onBackgroundSeekMove(x)
  local localX = tonumber(x)
  backgroundSeekX = localX and (backgroundSeekOffset + localX * backgroundSeekWidth) / math.max(1, backgroundWidth) or nil
  onHover(true)
end
function onBackgroundBarMove(x)
  backgroundSeekX = tonumber(x)
  onHover(true)
end
function onBackgroundSeekLeave()
  backgroundSeekX = nil
  onHover(false)
end
function onBackgroundSeekClick()
  if backgroundSeekX == nil or backgroundWidth <= 0 or length <= 0 then return end
  local fraction = math.max(0, math.min(1, backgroundSeekX))
  onSeekChange(tostring(fraction * length / 1000000))
  onSeekRelease()
end
render = function()
  barWidget.setVisible(hasMedia)
  if not hasMedia then return end
  local coverSize = noctalia.getConfig("cover_size") or COVER_SIZE_DEFAULT
  local showBar = noctalia.getConfig("show_progress_bar") ~= false and length > 0
  local background = noctalia.getConfig("progress_layout") == "background" and showBar and not barWidget.isVertical()
  local controlsReveal = noctalia.getConfig("show_controls") == true
    and (noctalia.getConfig("controls_on_hover") == true and progress or 1) or 0
  local controls = controlsReveal > 0.01
  local barColor = tostring(noctalia.getConfig("bar_color") or "on_surface")
  local flat = noctalia.getConfig("point_style") == "flat"
  local compact = math.max(24, math.min(300, noctalia.getConfig("progress_width") or 35))
  local expanded = math.max(compact, math.min(500, noctalia.getConfig("progress_expand_width") or 35))
  local classicDrag = noctalia.getConfig("progress_style") == "classic_drag"
  local interactive = noctalia.getConfig("progress_style") == "interactive"
  local barWidth = classicDrag and expanded or compact + (expanded - compact) * progress
  local barHeight = math.max(4, math.min(24, noctalia.getConfig("progress_thickness") or 8))
  local inputHeight = 38
  local fraction = math.max(0, math.min(1, length > 0 and (seekDraft or position / 1000000) * 1000000 / length or 0))
  local bgCompact = math.max(120, math.min(700, noctalia.getConfig("background_width") or 260))
  local bgExpanded = math.max(bgCompact, math.min(1000, noctalia.getConfig("background_expand_width") or 420))
  local bgWidth = bgCompact + (bgExpanded - bgCompact) * progress
  local bgHeight = math.max(16, math.min(40, noctalia.getConfig("background_height") or 22))
  local children = {}
  local cover = nil
  if noctalia.getConfig("show_cover_art") ~= false then cover = resolveRawCoverPath() end
  if cover then
    table.insert(children, ui.image({key = "cover", path = cover, width = coverSize, height = coverSize,
      radius = coverSize * math.max(0, math.min(100, noctalia.getConfig("corner_rounding") or 100)) / 200, fit = "cover",
      onClick = "onPlaybackClick", onHover = "onMediaInlineHover"}))
  else
    table.insert(children, playbackButton("playback", playing and "player-pause-filled" or "player-play-filled",
      "onPlaybackClick", "Play / pause", coverSize + 4))
  end
  if controls then
    table.insert(children, ui.row({key = "controls", width = 60 * controlsReveal, gap = 0, align = "center", opacity = controlsReveal}, {
      playbackButton("previous", "player-skip-back-filled", "onPreviousClick", "Previous", 20, controlsReveal),
      playbackButton("pause", playing and "player-pause-filled" or "player-play-filled", "onPlaybackClick", "Play / pause", 20, controlsReveal),
      playbackButton("next", "player-skip-forward-filled", "onNextClick", "Next", 20, controlsReveal),
    }))
  end
  if showBar and not background then
    classicBarWidth = barWidth
    if interactive then
      renderedSeekValue = fraction
      table.insert(children, ui.row({key = "song-progress-wrapper", width = barWidth, height = inputHeight, align = "center"}, {
        ui.slider({key = "song-progress", flexGrow = 1, controlSize = "md", min = 0, max = 1, step = 0,
          value = renderedSeekValue, onChange = "onNativeSeekChange", onDragEnd = "onSeekRelease"}),
      }))
    else
      local filledWidth = barWidth * fraction
      local layers = {
        ui.row({key = "classic-track-layer", width = barWidth, height = inputHeight, align = "center"}, {
          ui.box({key = "classic-track", width = barWidth, height = barHeight, radius = barHeight / 2, fill = barColor .. "/0.28"}),
        }),
        ui.row({key = "classic-fill-layer", width = barWidth, height = inputHeight, gap = 0, align = "center"}, flat and {
          ui.progress({key = "flat-fill", width = barWidth, height = barHeight, radius = barHeight / 2,
            progress = fraction, fill = barColor, track = "#00000000"}),
        } or {
          ui.box({key = "classic-fill", width = filledWidth, height = barHeight, radius = flat and 0 or math.min(barHeight, filledWidth) / 2, fill = barColor}),
          ui.box({width = barWidth - filledWidth, height = 1, fill = "#00000000"}),
        }),
      }
      if classicDrag then
        renderedSeekValue = math.max(0, math.min(1, (filledWidth - 2) / (barWidth - 4)))
        table.insert(layers, ui.row({key = "classic-drag-wrapper", width = barWidth, height = inputHeight, align = "center"}, {
          ui.slider({key = "classic-drag", flexGrow = 1, controlSize = "md", min = 0, max = 1, step = 0,
            value = renderedSeekValue, opacity = 0,
            onChange = "onClassicDragChange", onDragEnd = "onSeekRelease"}),
        }))
      else
        table.insert(layers, ui.graph({key = "classic-seek-pointer", width = barWidth, height = inputHeight, values = {0, 0},
          color = "#00000000", lineWidth = 0, fillOpacity = 0,
          onPointerMove = "onClassicSeekMove", onPointerLeave = "onClassicSeekLeave"}))
      end
      table.insert(children, ui.row({key = "classic-progress-hit", width = barWidth, height = inputHeight, gap = -barWidth, align = "center",
        onClick = "onClassicSeekClick"}, layers))
    end
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
  if background then
    -- Character limits belong to the inline layout. Background text uses its
    -- actual remaining width, including space freed by hidden controls.
    text = full
    -- The title/progress area seeks. Artwork and control targets stay above
    -- the background and keep their own playback actions.
    backgroundWidth = bgWidth
    backgroundSeekOffset = 8 + (cover and coverSize or coverSize + 4) + 6 + (controls and (60 * controlsReveal + 6) or 0)
    backgroundSeekWidth = math.max(1, bgWidth - backgroundSeekOffset - 8)
    if hovering and fullLen * 7 > backgroundSeekWidth then
      local loop = full .. "   "
      text = utf8Window(loop .. full, scrollOffset % (utf8.len(loop) or #loop), fullLen)
    end
    table.insert(children, ui.row({key = "background-seek-hit", width = backgroundSeekWidth, height = inputHeight,
      gap = -backgroundSeekWidth, align = "center", onClick = "onBackgroundSeekClick", tooltip = "Click progress to seek"}, {
      ui.row({key = "background-title-layer", width = backgroundSeekWidth, height = inputHeight, align = "center"}, {
        ui.label({key = "title", text = text, maxLines = 1, maxWidth = backgroundSeekWidth}),
      }),
      ui.graph({key = "background-seek-pointer", width = backgroundSeekWidth, height = inputHeight, values = {0, 0},
        color = "#00000000", lineWidth = 0, fillOpacity = 0,
        onPointerMove = "onBackgroundSeekMove", onPointerLeave = "onBackgroundSeekLeave"}),
    }))
    barWidget.render(ui.row({key = "media-background", width = bgWidth, height = inputHeight, gap = -bgWidth, align = "center", onHover = "onMediaInlineHover", onClick = "onBackgroundSeekClick"}, {
      ui.row({key = "background-track-layer", width = bgWidth, height = inputHeight, align = "center"}, {
        ui.box({width = bgWidth, height = bgHeight, radius = bgHeight / 2, fill = "primary/0.12"}),
      }),
      ui.row({key = "background-fill-layer", width = bgWidth, height = inputHeight, gap = 0, align = "center"}, flat and {
        ui.progress({width = bgWidth, height = bgHeight, radius = bgHeight / 2, progress = fraction, fill = "primary/0.3", track = "#00000000"}),
      } or {
        ui.box({width = bgWidth * fraction, height = bgHeight, radius = flat and 0 or math.min(bgHeight, bgWidth * fraction) / 2, fill = "primary/0.3"}),
        ui.box({width = bgWidth * (1 - fraction), height = 1, fill = "#00000000"}),
      }),
      ui.graph({key = "background-wide-pointer", width = bgWidth, height = inputHeight, values = {0, 0},
        color = "#00000000", lineWidth = 0, fillOpacity = 0,
        onPointerMove = "onBackgroundBarMove", onPointerLeave = "onBackgroundSeekLeave"}),
      ui.row({key = "media-foreground", width = bgWidth, height = inputHeight, gap = 6, paddingH = 8, align = "center"}, children),
    }))
  else
    table.insert(children, ui.label({key = "title", text = text, maxLines = 1}))
    barWidget.render((barWidget.isVertical() and ui.column or ui.row)({gap = 6, align = "center", onHover = "onMediaInlineHover"}, children))
  end
end

local function step()
  if hoverLeaveMs > 0 then
    hoverLeaveMs = math.max(0, hoverLeaveMs - ANIM_INTERVAL)
    if hoverLeaveMs == 0 then hovering, target = false, 0 end
    noctalia.setUpdateInterval(ANIM_INTERVAL)
    render()
    return
  end
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
  local overflowing = noctalia.getConfig("progress_layout") == "background" and not barWidget.isVertical()
    and fullLen * 7 > backgroundSeekWidth or noctalia.getConfig("progress_layout") ~= "background" and fullLen > width
  local needsScroll = hovering and hasMedia and overflowing

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
  if isHovering then
    if not hovering then scrollOffset = 0 end
    hovering, target, hoverLeaveMs = true, 1, 0
  else
    -- Noctalia reports leaves between neighbouring child targets. Keep the
    -- current expansion until a short grace period confirms a real exit.
    hoverLeaveMs = 120
    noctalia.setUpdateInterval(ANIM_INTERVAL)
    return
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
