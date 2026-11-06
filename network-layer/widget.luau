--!nonstrict
-- Network Layer bar widget.
--
-- Icon-only status item rendered through Noctalia's standard status-icon
-- pipeline. The glyph describes the controller connection, not the TUN
-- toggle: route when connected, route-off otherwise.

local PLUGIN_ID = "ordchaos/network-layer"

local function panel_id()
  if noctalia.getConfig("panel_mode") == "floating" then
    return PLUGIN_ID .. ":panel"
  end
  return PLUGIN_ID .. ":panel-attached"
end

local function format_rate(bytes_per_second)
  local value = tonumber(bytes_per_second) or 0
  if value >= 1024 * 1024 then
    return string.format("%.1f MB/s", value / (1024 * 1024))
  end
  if value >= 1024 then
    return string.format("%.1f KB/s", value / 1024)
  end
  return string.format("%d B/s", value)
end

local function status_text(conn)
  if conn.status == "online" then
    return noctalia.tr("widget.online")
  end
  if conn.status == "connecting" then
    return noctalia.tr("widget.connecting")
  end
  return noctalia.tr("widget.offline")
end

local function render()
  local conn = noctalia.state.get("network.connection") or {}
  local config = noctalia.state.get("network.config") or {}
  local traffic = noctalia.state.get("network.traffic") or {}
  local online = conn.status == "online"

  local active = online and config.tunEnabled == true
  barWidget.setGlyph(active and "route" or "route-off")

  local endpoint = `{conn.host or "—"}:{conn.port or "—"}`
  local status = status_text(conn)
  if not online and tostring(conn.error or "") ~= "" then
    status = `{status} · {conn.error}`
  end

  local tooltip = {
    { key = noctalia.tr("panel.title"), value = status },
    { key = noctalia.tr("panel.endpoint"), value = endpoint },
  }
  if tostring(conn.version or "") ~= "" then
    table.insert(tooltip, { key = noctalia.tr("panel.version"), value = conn.version })
  end
  table.insert(tooltip, {
    key = noctalia.tr("panel.tun"),
    value = config.tunEnabled == true and noctalia.tr("widget.tun_on") or noctalia.tr("widget.tun_off"),
  })
  table.insert(tooltip, { key = noctalia.tr("widget.down"), value = format_rate(traffic.down) })
  table.insert(tooltip, { key = noctalia.tr("widget.up"), value = format_rate(traffic.up) })
  barWidget.setTooltip(tooltip)
end

for _, key in {
  "network.connection",
  "network.config",
  "network.traffic",
} do
  noctalia.state.watch(key, function()
    render()
  end)
end

function onClick()
  noctalia.togglePanel(panel_id())
end

function onConfigChanged()
  render()
end

render()
