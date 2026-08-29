--!nonstrict
-- Mihomo Control — bar widget.
--
-- Icon-only status item. It shows the Tabler "route" glyph only when the
-- whole Mihomo TUN path is confirmed up (controller reachable AND TUN
-- enabled) and "route-off" otherwise: offline, unreachable, TUN off, or
-- state not yet confirmed all fail closed to "route-off".
--
-- Both glyphs render through the host's standard status-icon pipeline
-- (fixed-size glyph box, foreground color, ink centered in the box), so
-- switching state never changes the layout, and no color or animation is
-- used to signal it.
--
-- Left click toggles the control panel; the tooltip keeps the connection
-- status, mode, rates, connection count and proxy-group selection.

local PLUGIN_ID = "mdj2812/mihomo-control"

local function panel_id()
  if noctalia.getConfig("panel_placement") == "attached" then
    return PLUGIN_ID .. ":panel-attached"
  end
  return PLUGIN_ID .. ":panel"
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

local function render()
  local conn = noctalia.state.get("mihomo.connection") or {}
  local config = noctalia.state.get("mihomo.config") or {}
  local traffic = noctalia.state.get("mihomo.traffic") or {}
  local connections = noctalia.state.get("mihomo.connections") or {}
  local groups = noctalia.state.get("mihomo.groups") or {}

  -- Fail-closed: only a confirmed online controller with TUN enabled shows
  -- "route". While still connecting nothing is confirmed yet, so it shows
  -- "route-off" as well.
  local tun_path_up = conn.status == "online" and config.tunEnabled == true
  barWidget.setGlyph(tun_path_up and "route" or "route-off")

  local online = conn.status == "online"
  local mode = noctalia.tr("panel.mode_" .. (config.mode or "rule"))

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
    { key = noctalia.tr("widget.mode"), value = mode },
    { key = noctalia.tr("widget.down"), value = format_rate(traffic.down) },
    { key = noctalia.tr("widget.up"), value = format_rate(traffic.up) },
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

function onConfigChanged()
  render()
end

function onClick()
  noctalia.togglePanel(panel_id())
end

render()
