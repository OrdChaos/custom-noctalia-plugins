--!nonstrict
-- Network Layer panel.
--
-- One Mihomo card, no nested cards: the top half is a two-column control
-- surface, the bottom half is a two-column policy-group grid. A future DNS
-- card is the only sibling of the Mihomo card.

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
  return delay > 0 and `{delay} ms` or noctalia.tr("panel.timeout")
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
    color = "on_surface",
  })
end

local function status_text()
  local status = snapshot.connection.status
  if status == "online" then
    return noctalia.tr("panel.connected")
  end
  if status == "connecting" then
    return noctalia.tr("panel.connecting")
  end
  return noctalia.tr("panel.offline")
end

local MODES = {
  { value = "direct", key = "panel.mode_direct", glyph = "arrow-up-right" },
  { value = "rule", key = "panel.mode_rule", glyph = "route" },
  { value = "global", key = "panel.mode_global", glyph = "world" },
}

-- Same visual idea as Control Center -> Power -> power profile: one
-- equal-width segmented row on a Surface lane, not a dropdown.
local function mode_selector(online)
  local current = tostring(snapshot.config.mode or "rule")
  local buttons = {}
  for _, mode in ipairs(MODES) do
    local selected = current == mode.value
    table.insert(buttons, ui.button({
      text = noctalia.tr(mode.key),
      glyph = mode.glyph,
      variant = selected and "primary" or "ghost",
      controlSize = "sm",
      flexGrow = 1,
      enabled = online,
      onClick = function()
        send_command({ op = "mode", mode = mode.value })
      end,
    }))
  end
  return ui.column({ gap = 6 }, {
    section_title(noctalia.tr("panel.mode")),
    ui.row({
      gap = 2,
      padding = 2,
      fill = "surface",
      radius = 6,
    }, buttons),
  })
end

local function traffic_controls()
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
      ui.label({ text = `{noctalia.tr("panel.down_total")}  {format_total(traffic.downTotal)}`, color = "on_surface_variant", fontSize = 11 }),
      ui.label({ text = `{noctalia.tr("panel.up_total")}  {format_total(traffic.upTotal)}`, color = "on_surface_variant", fontSize = 11 }),
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
      height = 48,
    }))
  end
  return ui.column({ gap = 6, flexGrow = 1 }, children)
end

local function controls_column(online)
  local updating = snapshot.subscriptions.updating == true
  return ui.column({ gap = 8, flexGrow = 1 }, {
    ui.label({
      text = `{snapshot.connection.host or "—"}:{snapshot.connection.port or "—"}`,
      fontSize = 11,
      color = "on_surface_variant",
    }),
    ui.row({ align = "center", justify = "space_between", gap = 12 }, {
      ui.label({ text = noctalia.tr("panel.tun"), fontSize = 12 }),
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
        variant = "default",
        controlSize = "sm",
        flexGrow = 1,
        enabled = online and not updating,
        onClick = function()
          send_command({ op = "update_subscriptions" })
        end,
      }),
      ui.button({
        text = noctalia.tr("panel.restart"),
        variant = "default",
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

local function group_cell(group, online)
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

  local delay = group_latency(group)
  local children = {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = group.name, fontSize = 12, fontWeight = "medium", flexGrow = 1 }),
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

  if group.type == "Selector" and #group.members > 0 then
    table.insert(children, ui.select({
      key = `group-{group.name}`,
      options = options,
      selectedIndex = selected,
      controlSize = "sm",
      enabled = online,
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
      fontSize = 11,
    }))
  end

  return ui.column({ gap = 4, flexGrow = 1 }, children)
end

local function groups_grid(online)
  local testing = snapshot.testing.active == true
  local children = {
    ui.row({ align = "center", justify = "space_between" }, {
      section_title(noctalia.tr("panel.groups")),
      ui.button({
        text = testing and noctalia.tr("panel.testing") or noctalia.tr("panel.test_all"),
        variant = "default",
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
      fontSize = 11,
    }))
    return ui.column({ gap = 8 }, children)
  end

  local row = {}
  for index, group in ipairs(snapshot.groups) do
    table.insert(row, group_cell(group, online))
    if #row == 2 or index == #snapshot.groups then
      if #row == 1 then
        table.insert(row, ui.column({ flexGrow = 1 }))
      end
      table.insert(children, ui.row({ gap = 14, align = "start" }, row))
      row = {}
    end
  end
  return ui.column({ gap = 10 }, children)
end

local function mihomo_card(online)
  local conn = snapshot.connection
  local version = tostring(conn.version or "")
  local error_text = tostring(conn.error or "")
  local status = status_text()
  if not online and error_text ~= "" then
    status = `{status} · {error_text}`
  end

  return ui.column({
    fill = "surface_container",
    radius = 12,
    padding = 12,
    gap = 10,
  }, {
    ui.row({ align = "center", gap = 8 }, {
      section_title("Mihomo"),
      ui.glyph({
        name = online and "route" or "route-off",
        size = 14,
        color = online and "primary" or "error",
      }),
      ui.label({ text = status, fontSize = 12, color = online and "on_surface" or "error" }),
      ui.label({
        text = version ~= "" and version or "—",
        fontSize = 11,
        color = "on_surface_variant",
        flexGrow = 1,
        textAlign = "end",
      }),
    }),
    mode_selector(online),
    ui.row({ gap = 16, align = "start" }, {
      controls_column(online),
      traffic_controls(),
    }),
    groups_grid(online),
  })
end

-- DNS extension hook. Return a native card (sibling of the Mihomo card) from
-- here when the DNS layer is added; the panel body already has the slot.
local function dns_controls()
  return nil
end

function render()
  local online = snapshot.connection.status == "online"
  local body = { mihomo_card(online) }
  local dns = dns_controls()
  if dns ~= nil then
    table.insert(body, dns)
  end

  panel.render(ui.column({ flexGrow = 1, gap = 8, padding = 8 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = noctalia.tr("panel.title"), fontSize = 15, fontWeight = "bold", flexGrow = 1 }),
      ui.button({
        glyph = "close",
        variant = "ghost",
        onClick = function()
          panel.close()
        end,
      }),
    }),
    ui.scroll({ flexGrow = 1, gap = 10 }, body),
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
