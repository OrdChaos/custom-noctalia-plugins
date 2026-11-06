--!nonstrict
-- Network Layer panel.
--
-- Native Noctalia controls only: labels, separators, toggles, buttons,
-- selects, a graph, and one scroll container. There are no custom card
-- backgrounds or hand-rolled status chips.
--
-- The panel is a pure subscriber: all HTTP work lives in service.luau.
-- DNS controls are intentionally left to a single extension hook at the
-- bottom of the rendered body (see dns_controls below).

local PLUGIN_ID = "ordchaos/network-layer"
local TRAFFIC_HISTORY = 60

local snapshot = {
  connection = {},
  config = {},
  traffic = {},
  groups = {},
  subscriptions = {},
  testing = {},
}

local traffic_open = false
local down_history = {}
local up_history = {}

local function send_command(cmd)
  cmd.seq = math.floor(os.clock() * 1000000)
  noctalia.state.set("network.command", cmd)
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

local function format_total(bytes)
  local value = tonumber(bytes) or 0
  if value >= 1024 * 1024 * 1024 then
    return string.format("%.2f GB", value / (1024 * 1024 * 1024))
  end
  if value >= 1024 * 1024 then
    return string.format("%.1f MB", value / (1024 * 1024))
  end
  if value >= 1024 then
    return string.format("%.1f KB", value / 1024)
  end
  return string.format("%d B", value)
end

local function latency_text(delay)
  if delay == nil then
    return noctalia.tr("panel.untested")
  end
  if delay > 0 then
    return `{delay} ms`
  end
  return noctalia.tr("panel.timeout")
end

local function latency_color(delay)
  if delay == nil then
    return "on_surface_variant"
  end
  if delay > 0 then
    return delay <= 300 and "primary" or (delay <= 800 and "warning" or "error")
  end
  return "error"
end

local function group_latency(group)
  if group.now ~= nil then
    for _, member in ipairs(group.members) do
      if member.name == group.now and member.delay ~= nil then
        return member.delay
      end
    end
  end
  local best = nil
  local tested = false
  for _, member in ipairs(group.members) do
    if member.delay ~= nil then
      tested = true
      if member.delay > 0 and (best == nil or member.delay < best) then
        best = member.delay
      end
    end
  end
  if best ~= nil then
    return best
  end
  return tested and 0 or nil
end

local function record_traffic()
  local down = tonumber(snapshot.traffic.down) or 0
  local up = tonumber(snapshot.traffic.up) or 0
  local last = #down_history
  if last == 0 or down_history[last] ~= down or up_history[last] ~= up then
    table.insert(down_history, down)
    table.insert(up_history, up)
    if #down_history > TRAFFIC_HISTORY then
      table.remove(down_history, 1)
      table.remove(up_history, 1)
    end
  end
end

local function normalized(values, peak)
  local out = {}
  for index, value in ipairs(values) do
    out[index] = peak > 0 and value / peak or 0
  end
  return out
end

local function refresh_snapshot()
  snapshot.connection = noctalia.state.get("network.connection") or snapshot.connection
  snapshot.config = noctalia.state.get("network.config") or snapshot.config
  snapshot.traffic = noctalia.state.get("network.traffic") or snapshot.traffic
  snapshot.groups = noctalia.state.get("network.groups") or snapshot.groups
  snapshot.subscriptions = noctalia.state.get("network.subscriptions") or snapshot.subscriptions
  snapshot.testing = noctalia.state.get("network.testing") or snapshot.testing
  record_traffic()
end

local function section_title(text)
  return ui.label({
    text = text,
    fontSize = 12,
    fontWeight = "bold",
    color = "on_surface_variant",
  })
end

local function kv_row(label, value)
  return ui.row({
    align = "center",
    justify = "space_between",
    gap = 12,
  }, {
    ui.label({ text = label, color = "on_surface_variant", fontSize = 12 }),
    ui.label({ text = value, fontSize = 12 }),
  })
end

local function connection_label()
  local status = snapshot.connection.status
  if status == "online" then
    return noctalia.tr("panel.connected")
  end
  if status == "connecting" then
    return noctalia.tr("panel.connecting")
  end
  return noctalia.tr("panel.offline")
end

local function connection_node()
  local conn = snapshot.connection
  local online = conn.status == "online"
  local version = tostring(conn.version or "")
  local endpoint = `{conn.host or "—"}:{conn.port or "—"}`
  local subtitle = endpoint
  if version ~= "" then
    subtitle = `{subtitle} · {version}`
  end
  if not online and tostring(conn.error or "") ~= "" then
    subtitle = `{subtitle} · {conn.error}`
  end
  return ui.row({ align = "center", gap = 10 }, {
    ui.glyph({
      name = online and "route" or "route-off",
      size = 18,
      color = online and "primary" or "error",
    }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = connection_label(), fontWeight = "medium" }),
      ui.label({ text = subtitle, fontSize = 12, color = "on_surface_variant" }),
    }),
  })
end

local function mihomo_node(online)
  local conn = snapshot.connection
  local version = tostring(conn.version or "")
  local endpoint = `{conn.host or "—"}:{conn.port or "—"}`
  local updating = snapshot.subscriptions.updating == true

  return ui.column({ gap = 10 }, {
    section_title(noctalia.tr("panel.mihomo")),
    kv_row(noctalia.tr("panel.version"), version ~= "" and version or "—"),
    kv_row(noctalia.tr("panel.endpoint"), endpoint),
    ui.row({
      align = "center",
      justify = "space_between",
      gap = 12,
    }, {
      ui.label({ text = noctalia.tr("panel.tun") }),
      ui.toggle({
        checked = snapshot.config.tunEnabled == true,
        enabled = online,
        onChange = function(value)
          send_command({ op = "tun", enabled = value == "true" })
        end,
      }),
    }),
    ui.row({ gap = 8 }, {
      ui.button({
        text = updating and noctalia.tr("panel.updating_subscriptions") or noctalia.tr("panel.update_subscriptions"),
        variant = "secondary",
        controlSize = "sm",
        flexGrow = 1,
        enabled = online and not updating,
        onClick = function()
          send_command({ op = "update_subscriptions" })
        end,
      }),
      ui.button({
        text = noctalia.tr("panel.restart"),
        variant = "outline",
        controlSize = "sm",
        flexGrow = 1,
        enabled = online,
        onClick = function()
          send_command({ op = "restart" })
        end,
      }),
    }),
  })
end

local function traffic_node()
  local traffic = snapshot.traffic
  local down = tonumber(traffic.down) or 0
  local up = tonumber(traffic.up) or 0
  local peak = 1
  for _, value in ipairs(down_history) do
    if value > peak then
      peak = value
    end
  end
  for _, value in ipairs(up_history) do
    if value > peak then
      peak = value
    end
  end

  local children = {
    ui.row({ align = "center", justify = "space_between" }, {
      section_title(noctalia.tr("panel.traffic")),
      ui.button({
        glyph = "chart-line",
        variant = "ghost",
        controlSize = "sm",
        tooltip = traffic_open and noctalia.tr("panel.hide_traffic") or noctalia.tr("panel.traffic"),
        onClick = function()
          traffic_open = not traffic_open
          render()
        end,
      }),
    }),
    ui.row({ justify = "space_between" }, {
      ui.label({ text = `{noctalia.tr("panel.down")}  {format_rate(down)}`, color = "primary", fontSize = 12 }),
      ui.label({ text = `{noctalia.tr("panel.up")}  {format_rate(up)}`, color = "secondary", fontSize = 12 }),
    }),
    ui.row({ justify = "space_between" }, {
      ui.label({ text = `{noctalia.tr("panel.down_total")}  {format_total(traffic.downTotal)}`, color = "on_surface_variant", fontSize = 12 }),
      ui.label({ text = `{noctalia.tr("panel.up_total")}  {format_total(traffic.upTotal)}`, color = "on_surface_variant", fontSize = 12 }),
    }),
  }

  if traffic_open then
    table.insert(children, ui.graph({
      values = normalized(down_history, peak),
      values2 = normalized(up_history, peak),
      color = "primary",
      color2 = "secondary",
      lineWidth = 2,
      fillOpacity = 0.12,
      height = 64,
    }))
  end
  return ui.column({ gap = 8 }, children)
end

local function group_node(group, online)
  local testing = snapshot.testing.active == true
  local selected = 0
  local options = {}
  for index, member in ipairs(group.members) do
    local label = member.name
    if member.delay ~= nil then
      label = `{label} · {latency_text(member.delay)}`
    end
    options[index] = label
    if group.now == member.name then
      selected = index - 1
    end
  end

  local selectable = group.type == "Selector" and #group.members > 0
  local delay = group_latency(group)
  local children = {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = group.name, fontWeight = "medium", flexGrow = 1 }),
      ui.label({ text = latency_text(delay), fontSize = 12, color = latency_color(delay) }),
      ui.button({
        glyph = "bolt",
        variant = "ghost",
        controlSize = "sm",
        enabled = online and not testing and #group.members > 0,
        tooltip = noctalia.tr("panel.test"),
        onClick = function()
          send_command({ op = "test_group", group = group.name })
        end,
      }),
    }),
  }

  if selectable then
    table.insert(children, ui.select({
      key = `group-{group.name}`,
      options = options,
      selectedIndex = selected,
      controlSize = "sm",
      enabled = online and not testing,
      onChange = function(index_text)
        local index = (tonumber(index_text) or 0) + 1
        local member = group.members[index]
        if member ~= nil then
          send_command({ op = "select", group = group.name, proxy = member.name })
        end
      end,
    }))
  else
    table.insert(children, ui.label({
      text = group.now ~= nil and group.now or noctalia.tr("panel.no_groups"),
      color = "on_surface_variant",
      fontSize = 12,
    }))
  end

  return ui.column({ gap = 6 }, children)
end

local function groups_node(online)
  local testing = snapshot.testing.active == true
  local children = {
    ui.row({ align = "center", justify = "space_between" }, {
      section_title(noctalia.tr("panel.groups")),
      ui.button({
        text = testing and noctalia.tr("panel.testing") or noctalia.tr("panel.test_all"),
        variant = "secondary",
        controlSize = "sm",
        enabled = online and not testing and #snapshot.groups > 0,
        onClick = function()
          send_command({ op = "test_all" })
        end,
      }),
    }),
  }

  if #snapshot.groups == 0 then
    table.insert(children, ui.label({
      text = noctalia.tr("panel.no_groups"),
      color = "on_surface_variant",
      fontSize = 12,
    }))
    return ui.column({ gap = 10 }, children)
  end

  for index, group in ipairs(snapshot.groups) do
    table.insert(children, group_node(group, online))
    if index < #snapshot.groups then
      table.insert(children, ui.separator({ spacing = 4 }))
    end
  end
  return ui.column({ gap = 10 }, children)
end

-- DNS extension hook. A future DNS section can return a native ui.* subtree
-- from here; the surrounding panel does not need to change. Returning nil
-- keeps the current network-only surface intact.
local function dns_controls()
  return nil
end

function render()
  local online = snapshot.connection.status == "online"
  local body = {
    connection_node(),
    ui.separator({ spacing = 2 }),
    mihomo_node(online),
    ui.separator({ spacing = 2 }),
    traffic_node(),
    ui.separator({ spacing = 2 }),
    groups_node(online),
  }

  local dns = dns_controls()
  if dns ~= nil then
    table.insert(body, ui.separator({ spacing = 2 }))
    table.insert(body, dns)
  end

  panel.render(ui.column({ flexGrow = 1, gap = 14 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = noctalia.tr("panel.title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
      ui.button({
        glyph = "close",
        variant = "ghost",
        onClick = function()
          panel.close()
        end,
      }),
    }),
    ui.scroll({ flexGrow = 1, gap = 14 }, body),
  }))
end

function onOpen()
  refresh_snapshot()
  render()
end

function onConfigChanged()
  refresh_snapshot()
  render()
end

for _, key in {
  "network.connection",
  "network.config",
  "network.traffic",
  "network.groups",
  "network.subscriptions",
  "network.testing",
} do
  noctalia.state.watch(key, function()
    refresh_snapshot()
    render()
  end)
end

refresh_snapshot()
render()
