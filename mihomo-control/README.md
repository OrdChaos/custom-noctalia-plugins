# Mihomo Control

Monitor and control a Mihomo (Clash Meta) instance right from the Noctalia
bar: live traffic, proxy mode, proxy-group selection, latency tests and active
connections. It talks to the Mihomo external controller, which can run on this
machine (`127.0.0.1`) or on a remote host — just configure the IP, port and
secret.

## Plugin

| Field   | Value                       |
| ------- | --------------------------- |
| ID      | `mdj2812/mihomo-control`    |
| Entries | Bar widget: `widget`; panels: `panel`, `panel-attached`; service: `service`; shortcut: `mode` |

## Requirements

- Network access to the Mihomo external controller (local or remote)
- On `PATH` (declared in `plugin.toml` `dependencies`):
  - `jq` — project oversized `/connections` and `/proxies` API responses during polling

## Compatibility

The pinned Noctalia 5.3.0 supports plugin API **3–34**. This build declares
`plugin_api = 9` (upstream 0.2.0's level) and keeps the pre-43 palette roles
(`surface_variant`, `outline`), so it loads there with the same visuals.
Upstream 0.2.1's `plugin_api = 43` is rejected by 5.3.0.

## Usage

Add the **Mihomo Control** widget from the Add-widget picker. It is an
icon-only status item rendered through Noctalia's standard status-icon
pipeline (same size, color and behavior as the other bar icons). It shows
the Tabler **route** glyph only when the whole Mihomo TUN path is confirmed
up — the controller is reachable **and** TUN mode is enabled — and the
**route-off** glyph otherwise (offline, unreachable, TUN off, or status not
yet confirmed). No color or animation signals the state; the glyph itself is
the difference. Hover it for the connection status, live download and upload
rates, connection count and each proxy group's current selection. Left-click
the widget to toggle the control panel using the configured **Panel
placement**. Both variants can also be opened directly:

```sh
noctalia msg panel-toggle mdj2812/mihomo-control:panel
noctalia msg panel-toggle mdj2812/mihomo-control:panel-attached
```

The first command opens the centered floating panel; the second opens the
variant attached to the bar.

The panel lets you switch the proxy mode (rule / global / direct), toggle the
runtime **TUN** status, update all HTTP (remote-subscription) proxy providers
with **Update subscriptions**, restart the core, refresh the status, and manage
every proxy group. Use the **Server** dropdown to switch between saved
controller profiles (host, port, secret, TLS). **Manage** edits the active
profile; profiles and per-server proxy-group order are stored in the plugin
data directory. Right-click the refresh button to reload the whole plugin;
left-click only re-polls the controller. Each group card lists all of its
members with their latency — sourced from mihomo's health checks and refreshed
by the group's **Test latency** button. Each card also shows an overall latency
(the selected member's, or the best tested one) right in its subtitle, visible
without expanding. Member lists are collapsed by default; click a group header
to expand it. Click a member to select it; the current selection is marked with
a dot. Use **Test all** next to the Proxy groups heading to run a latency test
on every group at once. Drag a card by its ☰ grip over another card to reorder
the groups. The nearest insertion gap opens to preview the resulting layout
before drop. The custom display order survives controller polling and plugin
restarts.

Add the **Mihomo: Rule** shortcut from Settings → Control Center shortcuts to
quickly toggle between rule and global mode.

Before the widget shows anything, enable the plugin's `service` entry — it owns
all communication with the external controller and streams the traffic data.

## Settings

| Setting             | Type    | Default      | Description                                                                 |
| ------------------- | ------- | ------------ | --------------------------------------------------------------------------- |
| Host                | string  | `127.0.0.1`  | Hostname or IP of the Mihomo external controller.                           |
| Port                | string  | `9090`       | Port of the Mihomo external controller.                                     |
| Secret              | string  | *(empty)*    | `secret` from your Mihomo config; empty when authentication is disabled.    |
| HTTPS               | bool    | off          | Use `https://` (external-controller-tls or a TLS reverse proxy).            |
| Allow insecure TLS  | bool    | off          | Skip certificate verification for self-signed TLS controllers.              |
| Test URL            | string  | `https://www.gstatic.com/generate_204` | URL used for latency tests; empty uses each group's configured test URL. |
| Refresh interval    | int     | `2`          | Seconds between status polls (1–60); traffic rates stream in real time.     |
| Panel placement     | select  | `floating`   | Open the control panel centered on screen or attached to the bar widget.    |

## IPC

The service exposes two IPC events for scripting and debugging:

```sh
noctalia msg plugin mdj2812/mihomo-control:service all refresh
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"mode","mode":"global"}'
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"tun","enabled":false}'
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"update_subscriptions"}'
```

`refresh` re-polls version, config, connections and proxy groups. `cmd` accepts
the same command tables the panel sends (`mode`, `select`, `delay_test`,
`delay_test_all`, `reorder_group`, `restart`, `close_connections`, `refresh`,
`select_server`, `save_server`, `delete_server`, `tun`, `update_subscriptions`).
`self-test` runs in-process checks for group ordering, traffic dedup helpers,
and watchdog interval setup; results are published to `mihomo.self_test`.

## Testing

Offline unit tests (plain Lua, no running shell required):

```sh
cd mihomo-control
lua tests/group_order_test.lua   # Lua 5.2+; upstream smoke.sh uses lua5.4
noctalia plugins lint .
```

Full smoke test (adds live IPC when Noctalia is running):

```sh
./mihomo-control/tests/smoke.sh
```

Runtime self-test against the loaded service:

```sh
noctalia msg plugin mdj2812/mihomo-control:service all self-test
```

## Notes

- The plugin talks HTTP to the configured external controller and shells out to
  `jq` to project oversized `/connections` and `/proxies` responses so polling
  stays within Noctalia's Luau CPU budget. It also runs `noctalia msg plugins
  disable` / `enable` when the panel refresh button is right-clicked. It writes
  server profiles and per-server proxy-group display order (group names, never
  the secret) to its Noctalia plugin data directory. Reordering does not modify
  the Mihomo configuration.
- The bar widget is icon-only and uses Noctalia's standard glyph pipeline:
  Tabler **route** when the controller is reachable **and** TUN mode is enabled,
  **route-off** otherwise. It does not tint or animate the glyph, and it has no
  widget-label or icon-size/color settings in this custom build.
- **TUN** is a runtime toggle only: the panel reads `tun.enable` from
  `GET /configs` and writes it back with `PATCH /configs`. The declarative
  Mihomo config file is never edited, so a restart after a `guix system
  reconfigure` restores the config's own `tun.enable` value.
- **Update subscriptions** enumerates `/providers/proxies` and calls
  `PUT /providers/proxies/<name>` only for HTTP (remote-subscription)
  providers; file/inline providers are skipped. Provider names are
  percent-encoded in the path. The button is disabled while a pass is in
  flight, and a failure on one provider does not stop the remaining ones.
- The traffic rate uses mihomo's streaming `GET /traffic` endpoint; status,
  connections and proxy groups are polled every refresh interval.
- The secret is stored in your Noctalia config and sent as the standard
  `Authorization: Bearer <secret>` header. It is sent in plain text unless
  HTTPS is enabled — use HTTPS for remote controllers.
- **Restart** posts to `/restart`, which re-executes the core; the plugin
  reconnects automatically once it is back. There is no API endpoint that
  stops the core — switching the mode to `direct` is the closest equivalent.
- A latency test where every node fails is reported as *all nodes timed out*:
  mihomo answers the delay endpoint with HTTP 504 in that case. If that keeps
  happening, set **Test URL** to an endpoint your network can reach.

## Development

- `service.luau` — headless API backend, publishes `mihomo.*` state.
- `group_logic.luau` — pure helpers for group ordering, server profiles and
  traffic dedup (unit-tested).
- `widget.luau` — icon-only bar widget (glyph + tooltip).
- `panel.luau` — control panel (server profiles, TUN toggle, subscription update).
- `shortcut.luau` — rule/global mode toggle.
- `translations/` — user-facing strings.
