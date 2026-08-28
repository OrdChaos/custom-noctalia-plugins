--!nonstrict
-- Mihomo Control — bar widget.
--
-- Shows a text-only label (proxy mode by default, or the configured widget
-- label) from the service's shared state — no icon. Left click toggles the
-- control panel; the tooltip holds the connection status, mode, totals,
-- connection count and the current selection of every proxy group.

local PLUGIN_ID = "mdj2812/mihomo-control"

-- Hover mode: the panel opens from the capsule after a short settle and
-- closes again once the pointer has left both the capsule and the panel.
local HOVER_SETTLE = 0.25 -- seconds of continuous hover before opening
local HOVER_CLOSE_GRACE = 0.7 -- seconds after leaving capsule+panel before closing
local HOVER_TICK_MS = 50 -- fast update tick while a hover timer is running

local function hover_mode_active()
  return noctalia.getConfig("panel_placement") == "hover"
end

local function panel_id()
  local placement = noctalia.getConfig("panel_placement")
  if placement == "attached" or placement == "hover" then
    return PLUGIN_ID .. ":panel-attached"
  end
  return PLUGIN_ID .. ":panel"
end

-- Hover-mode bookkeeping. `hovering` tracks the pointer over the capsule
-- (onHover), `panel_open`/`panel_hovered` mirror the panel's own state
-- (published by panel.luau), and `opening`/`closing` guard the async gap
-- between a togglePanel call and the state change it produces.
local hovering = false
local panel_open = false
local panel_hovered = false
local opening = false
local closing = false
local suppress_hover_open = false
local hover_elapsed = 0
local close_grace = 0
local last_tick = 0

local function apply_tick_rate(timers_active)
  noctalia.setUpdateInterval(timers_active and HOVER_TICK_MS or 1000)
end

local function format_rate(bytes_per_second)
  local value = tonumber(bytes_per_second) or 0
  if value >= 1024 * 1024 * 1024 then
    return string.format("%.2f GB/s", value / (1024 * 1024 * 1024))
  end
  if value >= 1024 * 1024 then
    return string.format("%.1f MB/s", value / (1024 * 1024))
  end
  if value >= 1024 then
    return string.format("%.1f KB/s", value / 1024)
  end
  return string.format("%d B/s", value)
end

local function group_latency(group)
  if group.now and group.now ~= "" then
    for _, member in ipairs(type(group.members) == "table" and group.members or {}) do
      if member.name == group.now and member.delay ~= nil then
        return tonumber(member.delay)
      end
    end
  end

  local best = nil
  local any_tested = false
  for _, member in ipairs(type(group.members) == "table" and group.members or {}) do
    local delay = tonumber(member.delay)
    if delay ~= nil then
      any_tested = true
      if delay > 0 and (best == nil or delay < best) then
        best = delay
      end
    end
  end
  if best ~= nil then
    return best
  end
  return any_tested and 0 or nil
end

local function first_visible_group(groups)
  for _, group in ipairs(type(groups) == "table" and groups or {}) do
    if group.hidden ~= true then
      return group
    end
  end
  return nil
end

local function configured_label(mode, traffic, connections, groups)
  local content = noctalia.getConfig("label_content") or "mode"
  if content == "none" then
    return nil
  end
  if content == "download" then
    return `▼ {format_rate(traffic.down)}`
  end
  if content == "upload" then
    return `▲ {format_rate(traffic.up)}`
  end
  if content == "traffic" then
    return `▼ {format_rate(traffic.down)}  ▲ {format_rate(traffic.up)}`
  end
  if content == "connections" then
    return noctalia.tr("widget.connections_short", {
      count = math.max(0, math.floor(tonumber(connections.count) or 0)),
    })
  end
  if content == "proxy" then
    local group = first_visible_group(groups)
    local selected = group and tostring(group.now or "") or ""
    return selected ~= "" and selected or "—"
  end
  if content == "latency" then
    local group = first_visible_group(groups)
    local delay = group and group_latency(group) or nil
    if delay == nil then
      return "— ms"
    end
    if delay <= 0 then
      return noctalia.tr("widget.latency_timeout")
    end
    return `{math.floor(delay)} ms`
  end
  return mode
end

local function render()
  local conn = noctalia.state.get("mihomo.connection") or {}
  local config = noctalia.state.get("mihomo.config") or {}
  local traffic = noctalia.state.get("mihomo.traffic") or {}
  local connections = noctalia.state.get("mihomo.connections") or {}
  local groups = noctalia.state.get("mihomo.groups") or {}

  local online = conn.status == "online"
  local mode = noctalia.tr("panel.mode_" .. (config.mode or "rule"))

  -- Text only. When the configured label is "none" there is nothing left to
  -- show, so fall back to the proxy mode instead of an empty capsule.
  local label_text = configured_label(mode, traffic, connections, groups) or mode
  barWidget.setText(label_text)

  local status_value = "Offline"
  if online then
    local version = tostring(conn.version or "")
    status_value = version ~= ""
      and noctalia.tr("widget.status_online_with_version", { version = version })
      or noctalia.tr("widget.status_online_plain")
  elseif conn.status == "connecting" then
    status_value = noctalia.tr("widget.status_connecting")
  elseif tostring(conn.error or "") ~= "" then
    status_value = noctalia.tr("widget.status_offline_with_error", { error = conn.error })
  else
    status_value = noctalia.tr("widget.status_offline_plain")
  end

  local tooltip = {
    { key = noctalia.tr("widget.status"), value = status_value },
    { key = noctalia.tr("widget.mode"), value = noctalia.tr("panel.mode_" .. (config.mode or "rule")) },
    { key = noctalia.tr("widget.down"), value = `▼ {format_rate(traffic.down)}` },
    { key = noctalia.tr("widget.up"), value = `▲ {format_rate(traffic.up)}` },
    { key = noctalia.tr("widget.connections"), value = tostring(connections.count or 0) },
  }
  for _, group in ipairs(type(groups) == "table" and groups or {}) do
    if #tooltip < 14 then
      table.insert(tooltip, {
        key = tostring(group.name or ""),
        value = tostring(group.now or "—"),
      })
    end
  end
  barWidget.setTooltip(tooltip)
end

for _, key in {
  "mihomo.connection",
  "mihomo.config",
  "mihomo.traffic",
  "mihomo.connections",
  "mihomo.groups",
} do
  noctalia.state.watch(key, function(_value)
    render()
  end)
end

function update()
  local now = os.clock()
  local delta = last_tick > 0 and now - last_tick or 0
  last_tick = now

  if hover_mode_active() then
    -- Open: continuous hover over the capsule settles, then the attached
    -- panel appears (it slides out from the bar next to the widget).
    if hovering and not panel_open and not opening and not suppress_hover_open then
      hover_elapsed += delta
      if hover_elapsed >= HOVER_SETTLE then
        hover_elapsed = 0
        opening = true
        noctalia.togglePanel(panel_id())
      end
    else
      hover_elapsed = 0
    end

    -- Close: the pointer has left the capsule and the panel alike; give a
    -- short grace so moving capsule -> panel does not flicker it shut.
    if panel_open and not hovering and not panel_hovered and not closing then
      close_grace += delta
      if close_grace >= HOVER_CLOSE_GRACE then
        close_grace = 0
        closing = true
        noctalia.togglePanel(panel_id())
      end
    else
      close_grace = 0
    end

    apply_tick_rate((hover_elapsed > 0 or close_grace > 0) and not (opening or closing))
  else
    apply_tick_rate(false)
  end

  render()
end

function onHover(entered)
  hovering = entered == true
  if hovering then
    close_grace = 0
    closing = false -- pointer is back on the capsule; cancel an in-flight close
  else
    hover_elapsed = 0
    opening = false -- pointer left before the panel opened; allow a fresh pass
    suppress_hover_open = false
  end
end

function onConfigChanged()
  render()
end

function onClick()
  noctalia.togglePanel(panel_id())
  if hover_mode_active() then
    -- The pointer is still on the capsule after the click; block the hover
    -- opener until it leaves, so click-close does not instantly re-open.
    suppress_hover_open = true
  end
end

noctalia.state.watch("mihomo.panel_open", function(value)
  panel_open = value == true
  if panel_open then
    opening = false
  else
    closing = false
  end
end)

noctalia.state.watch("mihomo.panel_hovered", function(value)
  panel_hovered = value == true
end)

render()
