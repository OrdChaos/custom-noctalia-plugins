--!nonstrict
-- Network Layer service.
--
-- The service is the only entry that talks HTTP to the Mihomo external
-- controller. It publishes one namespace, "network.*", and accepts commands
-- through "network.command". Panel and widget are pure subscribers.
--
-- Deliberately absent (kept out of the network layer):
--   proxy mode switches, controller profiles, connection lists, group
--   reordering, shortcuts. Those belong to other layers.

local DEFAULT_TEST_URL = "https://www.gstatic.com/generate_204"
local GROUPS_REFRESH_EVERY = 2
local STREAM_RETRY_EVERY = 5
local PROXIES_INLINE_DECODE_LIMIT = 65536

-- Host DNS mode state (no custom CLI; plugin writes the mode file directly).
local DNS_MODE_FILE = "/var/lib/guixcfg-dns/mode"
local DNS_APPLIED_FILE = "/run/guixcfg-dns/applied"
local DNS_STATUS_FILE = "/run/guixcfg-dns/status"

local settings = {
  host = "127.0.0.1",
  port = 9090,
  secret = "",
  use_https = false,
  insecure = false,
  test_url = "",
  interval = 2,
}

local function log(msg)
  noctalia.log("[network-layer/service] " .. tostring(msg))
end

local function safe_call(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    log(label .. " failed: " .. tostring(err))
  end
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function decode(body)
  local ok, data = pcall(noctalia.json.decode, body)
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

local function success(res)
  return res ~= nil and res.ok == true and res.status >= 200 and res.status < 300
end

local function base_url()
  local scheme = settings.use_https and "https" or "http"
  return `{scheme}://{settings.host}:{settings.port}`
end

local function auth_headers()
  if settings.secret == "" then
    return {}
  end
  return { `Authorization: Bearer {settings.secret}` }
end

local function json_headers()
  local headers = { "Content-Type: application/json" }
  for _, header in ipairs(auth_headers()) do
    table.insert(headers, header)
  end
  return headers
end

local function request(method, path, headers, body, on_done)
  local req = {
    url = base_url() .. path,
    method = method,
    headers = headers,
  }
  if body ~= nil then
    req.body = noctalia.json.encode(body)
  end
  if settings.insecure then
    req.allow_insecure_tls = true
  end
  noctalia.http(req, function(res)
    safe_call("http " .. method .. " " .. path, function()
      on_done(res or { ok = false, status = 0 })
    end)
  end)
end

local function reload_settings()
  local host = noctalia.getConfig("host")
  local port = noctalia.getConfig("port")
  local secret = noctalia.getConfig("secret")
  local test_url = noctalia.getConfig("test_url")
  local interval = tonumber(noctalia.getConfig("refresh_interval")) or 2

  settings.host = type(host) == "string" and host ~= "" and host or "127.0.0.1"
  local port_number = tonumber(port)
  settings.port = (type(port_number) == "number" and port_number >= 1 and port_number <= 65535)
      and math.floor(port_number)
    or 9090
  settings.secret = type(secret) == "string" and secret or ""
  settings.use_https = noctalia.getConfig("use_https") == true
  settings.insecure = noctalia.getConfig("allow_insecure_tls") == true
  settings.test_url = type(test_url) == "string" and noctalia.string.trim(test_url) or ""
  settings.interval = math.max(1, math.min(60, interval))
end

-- ── Published state ──────────────────────────────────────────────────────────

local state = {
  connection = {
    status = "connecting",
    host = settings.host,
    port = settings.port,
    version = "",
    meta = false,
    error = "",
  },
  config = { mode = "rule", tunEnabled = false },
  traffic = { up = 0, down = 0, upTotal = 0, downTotal = 0 },
  groups = {},
  subscriptions = { updating = false },
  testing = { active = false, group = "" },
  dns = { mode = "fixed", applied = "", status = "unknown" },
}

local function publish(key)
  noctalia.state.set("network." .. key, state[key])
end

local function publish_all()
  publish("connection")
  publish("config")
  publish("traffic")
  publish("groups")
  publish("subscriptions")
  publish("testing")
  publish("dns")
end


local function read_dns_file(path)
  local text, err = noctalia.readFile(path)
  if type(text) ~= "string" then
    return nil, err
  end
  return noctalia.string.trim(text)
end

local function poll_dns_state()
  local mode_raw = read_dns_file(DNS_MODE_FILE)
  local applied_raw = read_dns_file(DNS_APPLIED_FILE)
  local status_raw = read_dns_file(DNS_STATUS_FILE)

  local mode = mode_raw == "dhcp" and "dhcp" or "fixed"
  local applied = applied_raw == "dhcp" and "dhcp" or (applied_raw == "fixed" and "fixed" or "")
  local status = status_raw or "unknown"
  local next_state = { mode = mode, applied = applied, status = status }
  local current = state.dns
  if current == nil
      or current.mode ~= next_state.mode
      or current.applied ~= next_state.applied
      or current.status ~= next_state.status then
    state.dns = next_state
    publish("dns")
  end
end

local function set_online()
  local changed = state.connection.status ~= "online" or state.connection.error ~= ""
  state.connection.status = "online"
  state.connection.error = ""
  state.connection.host = settings.host
  state.connection.port = settings.port
  if changed then
    publish("connection")
  end
end

local function set_offline(reason)
  local changed = state.connection.status ~= "offline"
      or state.connection.error ~= (reason or "")
  state.connection.status = "offline"
  state.connection.error = reason or ""
  state.connection.host = settings.host
  state.connection.port = settings.port
  if changed then
    publish("connection")
  end
end

-- ── Groups ──────────────────────────────────────────────────────────────────

local PROXIES_JQ = [[
def last_delay:
  if ((.history // []) | length) > 0 then .history[-1].delay else null end;
.proxies as $p | {
  delays: (
    $p | to_entries
    | map(select((.value | last_delay) != null) | {key: .key, value: (.value | last_delay)})
    | from_entries
  ),
  groups: (
    $p | to_entries
    | map(select(.value.all != null) | {
        name: .key,
        type: (.value.type // ""),
        now: .value.now,
        hidden: (.value.hidden == true),
        testUrl: (if (.value.testUrl | type) == "string" then .value.testUrl else null end),
        members: .value.all
      })
  )
}
]]

local function default_test_url()
  return settings.test_url ~= "" and settings.test_url or DEFAULT_TEST_URL
end

-- Proxy-provider members are not present in /proxies, so their last latency
-- would be lost on every group poll. Keep the test result in the service.
local delay_cache = {}

local function apply_cached_delays(groups)
  for _, group in ipairs(groups) do
    local cached = delay_cache[group.name]
    if type(cached) == "table" then
      for _, member in ipairs(group.members) do
        if member.delay == nil and cached[member.name] ~= nil then
          member.delay = cached[member.name]
        end
      end
    end
  end
  return groups
end

local function build_groups(slim)
  local groups = {}
  if type(slim) ~= "table" or type(slim.groups) ~= "table" then
    return groups
  end
  local delays = type(slim.delays) == "table" and slim.delays or {}
  for _, item in ipairs(slim.groups) do
    if type(item) == "table" and type(item.name) == "string" and item.hidden ~= true then
      local members = {}
      for _, member_name in ipairs(type(item.members) == "table" and item.members or {}) do
        local member = tostring(member_name)
        table.insert(members, {
          name = member,
          delay = delays[member],
        })
      end
      table.insert(groups, {
        name = item.name,
        type = tostring(item.type or ""),
        now = item.now ~= nil and tostring(item.now) or nil,
        testUrl = type(item.testUrl) == "string" and item.testUrl or default_test_url(),
        members = members,
      })
    end
  end
  table.sort(groups, function(a, b)
    return a.name < b.name
  end)
  return apply_cached_delays(groups)
end

local function build_groups_from_proxies(proxies)
  local groups = {}
  if type(proxies) ~= "table" then
    return groups
  end
  for raw_name, info in pairs(proxies) do
    if type(info) == "table" and type(info.all) == "table" and info.hidden ~= true then
      local members = {}
      for _, member_name in ipairs(info.all) do
        local member = tostring(member_name)
        local proxy = proxies[member]
        local delay = nil
        if type(proxy) == "table" and type(proxy.history) == "table" and #proxy.history > 0 then
          local last = proxy.history[#proxy.history]
          if type(last) == "table" and last.delay ~= nil then
            delay = tonumber(last.delay)
          end
        end
        table.insert(members, { name = member, delay = delay })
      end
      table.insert(groups, {
        name = tostring(raw_name),
        type = tostring(info.type or ""),
        now = info.now ~= nil and tostring(info.now) or nil,
        testUrl = type(info.testUrl) == "string" and info.testUrl or default_test_url(),
        members = members,
      })
    end
  end
  table.sort(groups, function(a, b)
    return a.name < b.name
  end)
  return apply_cached_delays(groups)
end

local function publish_groups(groups)
  state.groups = groups
  publish("groups")
end

local function find_group(name)
  for _, group in ipairs(state.groups) do
    if group.name == name then
      return group
    end
  end
  return nil
end

local function apply_group_delays(group_name, by_name, timeout)
  local cache = delay_cache[group_name] or {}
  for _, group in ipairs(state.groups) do
    if group.name == group_name then
      for _, member in ipairs(group.members) do
        local delay = by_name[member.name]
        if delay ~= nil then
          member.delay = delay
          cache[member.name] = delay
        elseif timeout then
          member.delay = 0
          cache[member.name] = 0
        end
      end
    end
  end
  delay_cache[group_name] = cache
  publish("groups")
end

-- ── Polling ─────────────────────────────────────────────────────────────────

local function poll_version()
  request("GET", "/version", auth_headers(), nil, function(res)
    if not success(res) then
      local reason = "connection failed"
      if res.status == 401 then
        reason = "unauthorized"
      elseif res.status > 0 then
        reason = `HTTP {res.status}`
      end
      set_offline(reason)
      return
    end
    local data = decode(res.body)
    if data then
      state.connection.version = tostring(data.version or ""):gsub("^v", "")
      state.connection.meta = data.meta == true
      set_online()
    end
  end)
end

local function poll_configs()
  request("GET", "/configs", auth_headers(), nil, function(res)
    if not success(res) then
      return
    end
    local data = decode(res.body)
    if not data then
      return
    end
    local tun = data.tun
    state.config.tunEnabled = type(tun) == "table" and tun.enable == true
    if type(data.mode) == "string" then
      state.config.mode = data.mode
    end
    publish("config")
  end)
end

local proxies_pending = false

local function poll_proxies()
  request("GET", "/proxies", auth_headers(), nil, function(res)
    if not success(res) then
      return
    end
    local body = res.body or ""
    local function consume(data)
      if type(data) == "table" then
        publish_groups(build_groups(data))
      end
    end

    if #body <= PROXIES_INLINE_DECODE_LIMIT then
      local data = decode(body)
      if data ~= nil and type(data.proxies) == "table" then
        publish_groups(build_groups_from_proxies(data.proxies))
      end
      return
    end
    if proxies_pending then
      return
    end
    local dir = noctalia.pluginDataDir()
    if dir == nil then
      return
    end
    local path = dir .. "/proxies-poll.json"
    if not noctalia.writeFile(path, body) then
      log("cannot cache /proxies body")
      return
    end
    proxies_pending = true
    local cmd = "jq -c "
      .. shell_quote(PROXIES_JQ)
      .. " "
      .. shell_quote(path)
    noctalia.runAsync(cmd, function(result)
      proxies_pending = false
      safe_call("proxies jq", function()
        if result == nil or result.exitCode ~= 0 then
          log("jq /proxies failed: " .. tostring(result and result.stderr or "no result"))
          return
        end
        consume(decode(result.stdout or ""))
      end)
    end, 30000)
  end)
end

-- ── Traffic stream ──────────────────────────────────────────────────────────

local traffic_stream = nil
local traffic_epoch = 0
local stream_attempt_tick = -100

local function stop_traffic_stream()
  traffic_epoch += 1
  if traffic_stream ~= nil then
    traffic_stream.stop()
    traffic_stream = nil
  end
end

local function start_traffic_stream()
  if traffic_stream ~= nil then
    return
  end
  local epoch = traffic_epoch
  local stream = noctalia.httpStream(
    {
      url = base_url() .. "/traffic",
      headers = auth_headers(),
      allow_insecure_tls = settings.insecure,
    },
    function(line)
      safe_call("traffic stream", function()
        if epoch ~= traffic_epoch or line == "" then
          return
        end
        local data = decode(line)
        if not data then
          return
        end
        local current = state.traffic
        local next_values = {
          up = tonumber(data.up) or current.up,
          down = tonumber(data.down) or current.down,
          upTotal = tonumber(data.upTotal) or current.upTotal,
          downTotal = tonumber(data.downTotal) or current.downTotal,
        }
        if next_values.up == current.up
            and next_values.down == current.down
            and next_values.upTotal == current.upTotal
            and next_values.downTotal == current.downTotal then
          return
        end
        state.traffic = next_values
        publish("traffic")
      end)
    end,
    function(result)
      if epoch ~= traffic_epoch then
        return
      end
      traffic_stream = nil
      if result == nil or not result.ok then
        stream_attempt_tick = -1
      end
    end
  )
  if stream == nil then
    stream_attempt_tick = -1
    return
  end
  traffic_stream = stream
end

-- ── Commands ────────────────────────────────────────────────────────────────

local last_cmd_seq = 0

local function finish_testing()
  state.testing = { active = false, group = "" }
  publish("testing")
  publish("dns")
end

local function resolve_leaf(group_name)
  local current = group_name
  local seen = {}
  while current ~= nil and seen[current] ~= true do
    seen[current] = true
    local group = find_group(current)
    if group == nil then
      return nil
    end
    local selected = group.now
    if selected == nil or selected == "" then
      return nil
    end
    local child = find_group(selected)
    if child == nil then
      local delay = nil
      for _, member in ipairs(group.members) do
        if member.name == selected then
          delay = member.delay
          break
        end
      end
      return selected, delay
    end
    current = selected
  end
  return nil
end

local function notify_group_result(group_name)
  local group = find_group(group_name)
  if group == nil or group.now == nil or group.now == "" then
    return
  end
  local selected = group.now
  local delay = nil
  for _, member in ipairs(group.members) do
    if member.name == selected then
      delay = member.delay
      break
    end
  end
  local parts = { group_name, selected }
  if delay ~= nil then
    table.insert(parts, delay > 0 and `{delay} ms` or noctalia.tr("notify.delay_timeout_value"))
  end
  noctalia.notify(
    noctalia.tr("notify.delay_done"),
    noctalia.tr("notify.delay_selected", { selection = table.concat(parts, " - ") })
  )
end

local function notify_result(group_name, include_group)
  local leaf, delay = resolve_leaf(group_name)
  if leaf == nil then
    return
  end
  local parts = {}
  if include_group then
    table.insert(parts, group_name)
  end
  table.insert(parts, leaf)
  if delay ~= nil then
    table.insert(parts, delay > 0 and `{delay} ms` or noctalia.tr("notify.delay_timeout_value"))
  end
  noctalia.notify(
    noctalia.tr("notify.delay_done"),
    noctalia.tr("notify.delay_selected", { selection = table.concat(parts, " - ") })
  )
end

local function active_root()
  local mode = tostring(state.config.mode or "rule")
  local preferred = mode == "global" and "GLOBAL" or (mode == "direct" and "DIRECT" or "PROXY")
  if find_group(preferred) ~= nil then
    return preferred
  end
  if preferred == "PROXY" and find_group("GLOBAL") ~= nil then
    return "GLOBAL"
  end
  if #state.groups > 0 then
    return state.groups[1].name
  end
  return nil
end

local function notify_all_result()
  local root = active_root()
  if root ~= nil then
    notify_result(root, false)
  end
end

local function run_delay_test(group_name, opts)
  local options = opts or {}
  local group = find_group(group_name)
  if group == nil or #group.members == 0 then
    if options.on_done then
      options.on_done()
    end
    return
  end
  if not options.internal then
    if state.testing.active then
      return
    end
    state.testing = { active = true, group = group_name }
    publish("testing")
  publish("dns")
  end

  local test_url = settings.test_url ~= ""
      and settings.test_url
    or (group.testUrl ~= "" and group.testUrl or DEFAULT_TEST_URL)
  local path = "/group/"
    .. noctalia.string.urlEncode(group_name)
    .. "/delay?url="
    .. noctalia.string.urlEncode(test_url)
    .. "&timeout=5000"

  request("GET", path, auth_headers(), nil, function(res)
    if res.status == 504 then
      apply_group_delays(group_name, {}, true)
    elseif success(res) then
      local data = decode(res.body)
      if data then
        local by_name = {}
        for name, delay in pairs(data) do
          by_name[tostring(name)] = tonumber(delay)
        end
        apply_group_delays(group_name, by_name, false)
      end
    end
    if not options.internal then
      finish_testing()
      notify_group_result(group_name)
    end
    if options.on_done then
      options.on_done()
    end
  end)
end

local function test_all_groups()
  if state.testing.active or #state.groups == 0 then
    return
  end
  state.testing = { active = true, group = "*" }
  publish("testing")
  publish("dns")

  local names = {}
  for _, group in ipairs(state.groups) do
    if #group.members > 0 then
      table.insert(names, group.name)
    end
  end

  local index = 1
  local function next_group()
    if index > #names then
      finish_testing()
      notify_all_result()
      return
    end
    local name = names[index]
    index += 1
    run_delay_test(name, { internal = true, on_done = next_group })
  end
  next_group()
end

local function update_subscriptions()
  if state.subscriptions.updating then
    return
  end
  state.subscriptions.updating = true
  publish("subscriptions")

  local function finish()
    state.subscriptions.updating = false
    publish("subscriptions")
    poll_proxies()
  end

  request("GET", "/providers/proxies", auth_headers(), nil, function(res)
    if not success(res) then
      finish()
      return
    end
    local data = decode(res.body)
    local providers = data and data.providers or nil
    local names = {}
    if type(providers) == "table" then
      for name, provider in pairs(providers) do
        if type(provider) == "table" and provider.vehicleType == "HTTP" then
          table.insert(names, tostring(name))
        end
      end
      table.sort(names)
    end
    if #names == 0 then
      finish()
      return
    end

    local index = 1
    local function next_provider()
      if index > #names then
        finish()
        return
      end
      local name = names[index]
      index += 1
      request(
        "PUT",
        "/providers/proxies/" .. noctalia.string.urlEncode(name),
        auth_headers(),
        nil,
        function()
          next_provider()
        end
      )
    end
    next_provider()
  end)
end

local function handle_command(cmd)
  local op = cmd.op
  if op == "refresh" then
    poll_version()
    poll_configs()
    poll_proxies()
    return
  end
  if op == "dns_mode" then
    local mode = tostring(cmd.mode or "")
    if mode ~= "fixed" and mode ~= "dhcp" then
      return
    end
    -- No custom CLI: the plugin writes the host mode file directly. The
    -- root applier validates it and switches SmartDNS.
    local ok, err = noctalia.writeFile(DNS_MODE_FILE, mode .. "\n")
    if ok then
      state.dns = { mode = mode, applied = state.dns.applied, status = "pending" }
      publish("dns")
    else
      state.dns = {
        mode = state.dns.mode,
        applied = state.dns.applied,
        status = "error: " .. tostring(err or "write failed"),
      }
      publish("dns")
    end
    poll_dns_state()
    return
  end
  if op == "tun" then
    local enabled = cmd.enabled == true
    request("PATCH", "/configs", json_headers(), { tun = { enable = enabled } }, function(res)
      if success(res) then
        state.config.tunEnabled = enabled
        publish("config")
      end
      poll_configs()
    end)
    return
  end
  if op == "mode" then
    local mode = tostring(cmd.mode or "")
    if mode ~= "rule" and mode ~= "global" and mode ~= "direct" then
      return
    end
    request("PATCH", "/configs", json_headers(), { mode = mode }, function(res)
      if success(res) then
        state.config.mode = mode
        publish("config")
      end
      poll_configs()
    end)
    return
  end
  if op == "update_subscriptions" then
    update_subscriptions()
    return
  end
  if op == "restart" then
    state.connection.status = "connecting"
    state.connection.error = ""
    publish("connection")
    request("POST", "/restart", auth_headers(), nil, function()
      poll_version()
    end)
    return
  end
  if op == "select" then
    local group = tostring(cmd.group or "")
    local proxy = tostring(cmd.proxy or "")
    if group == "" or proxy == "" then
      return
    end
    request(
      "PUT",
      "/proxies/" .. noctalia.string.urlEncode(group),
      json_headers(),
      { name = proxy },
      function(res)
        if success(res) then
          local current = find_group(group)
          if current ~= nil then
            current.now = proxy
            publish("groups")
          end
        end
      end
    )
    return
  end
  if op == "test_group" then
    run_delay_test(tostring(cmd.group or ""))
    return
  end
  if op == "test_all" then
    test_all_groups()
    return
  end
end

-- ── Entry point ─────────────────────────────────────────────────────────────

local tick = 0

function update()
  safe_call("update", function()
    tick += 1
    poll_version()
    poll_configs()
    poll_dns_state()
    if tick % GROUPS_REFRESH_EVERY == 0 then
      poll_proxies()
    end
    if traffic_stream == nil and tick - stream_attempt_tick >= STREAM_RETRY_EVERY then
      stream_attempt_tick = tick
      start_traffic_stream()
    end
  end)
end

function onConfigChanged()
  safe_call("config changed", function()
    reload_settings()
    delay_cache = {}
    noctalia.setUpdateInterval(settings.interval * 1000)
    state.connection.host = settings.host
    state.connection.port = settings.port
    state.connection.status = "connecting"
    state.connection.version = ""
    state.connection.error = ""
    publish("connection")
    stop_traffic_stream()
    stream_attempt_tick = -1
    poll_version()
    poll_configs()
    poll_dns_state()
    poll_proxies()
  end)
end

function onIpc(event, payload)
  safe_call("ipc " .. tostring(event), function()
    if event == "refresh" then
      poll_version()
      poll_dns_state()
      poll_configs()
      poll_proxies()
    elseif event == "cmd" and payload ~= nil then
      local ok, cmd = pcall(noctalia.json.decode, payload)
      if ok and type(cmd) == "table" then
        handle_command(cmd)
      end
    end
  end)
end

function onExit()
  stop_traffic_stream()
end

noctalia.state.watch("network.command", function(cmd)
  safe_call("command", function()
    if type(cmd) ~= "table" then
      return
    end
    local seq = tonumber(cmd.seq) or 0
    if seq <= last_cmd_seq then
      return
    end
    last_cmd_seq = seq
    handle_command(cmd)
  end)
end)

reload_settings()
noctalia.setUpdateInterval(settings.interval * 1000)
poll_dns_state()
state.connection.host = settings.host
state.connection.port = settings.port
publish_all()
poll_version()
poll_configs()
poll_proxies()
start_traffic_stream()
