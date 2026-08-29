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
variant attached to the bar (it extends from the bar next to the widget).

The panel lets you switch the proxy mode (rule / global / direct), toggle the
runtime **TUN** status, update all HTTP (remote-subscription) proxy providers
with **Update subscriptions**, restart the server, refresh the status, and
manage every proxy group. Each group card lists all of its members with their
latency — sourced from mihomo's health checks and refreshed by the group's
**Test latency** button. Each card also shows an overall latency (the selected
member's, or the best tested one) right in its subtitle, visible without
expanding. Member lists are collapsed by default; click a group header to
expand it. Click a member to select it; the current selection is marked with a
dot. Use **Test all** next to the Proxy groups heading to run a latency test on
every group at once. Drag a card by its ☰ grip over another card to reorder
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
| Panel placement     | select  | `floating`   | Open the control panel centered on screen or attached to the bar widget.   |

## IPC

The service exposes two IPC events for scripting and debugging:

```sh
noctalia msg plugin mdj2812/mihomo-control:service all refresh
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"mode","mode":"global"}'
```

`refresh` re-polls version, config, connections and proxy groups. `cmd` accepts
the same command tables the panel sends (`mode`, `tun`, `update_subscriptions`,
`select`, `delay_test`, `delay_test_all`, `reorder_group`, `restart`,
`close_connections`, `refresh`).
`self-test` runs in-process checks for group ordering, traffic dedup helpers,
and watchdog interval setup; results are published to `mihomo.self_test`.

## Testing

Offline unit tests (plain Lua, no running shell required):

```sh
cd mihomo-control
lua5.4 tests/group_order_test.lua
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

- The plugin only talks HTTP to the configured external controller. It spawns
  no processes and runs no external commands. It writes only the custom
  proxy-group display order (group names, never the secret) to its Noctalia
  plugin data directory. Reordering does not modify the Mihomo configuration.
- The bar widget is an icon-only status item: the Tabler `route` glyph when the Mihomo TUN path is confirmed up, `route-off` otherwise (fail-closed). Both render in the host's normal foreground color.
- The traffic rate uses mihomo's streaming `GET /traffic` endpoint; status,
  connections and proxy groups are polled every refresh interval.
- The secret is stored in your Noctalia config and sent as the standard
  `Authorization: Bearer <secret>` header. It is sent in plain text unless
  HTTPS is enabled — use HTTPS for remote controllers.
- **Restart** posts to `/restart`, which re-executes the core; the plugin
  reconnects automatically once it is back. There is no API endpoint that
  stops the core — switching the mode to `direct` is the closest equivalent.
- The **TUN** toggle is a runtime switch: it patches the live config
  (`PATCH /configs` with `{"tun": {"enable": ...}}`) and never edits the
  declarative config file. After the PATCH the service re-polls `/configs` so
  the switch always converges on the real runtime state, including on failure.
- **Update subscriptions** enumerates `GET /providers/proxies` and updates
  only providers whose `vehicleType` is `HTTP` (remote subscriptions) via
  `PUT /providers/proxies/<name>`. Provider names are percent-encoded as path
  components, so names with spaces, `#`, `/`, `%` or CJK characters work. A
  failure on one provider does not abort the rest; the result is summarized
  in one notification and the proxy list is refreshed afterwards.
- A latency test where every node fails is reported as *all nodes timed out*:
  mihomo answers the delay endpoint with HTTP 504 in that case. If that keeps
  happening, set **Test URL** to an endpoint your network can reach.

## Development

- `service.luau` — headless API backend, publishes `mihomo.*` state.
- `group_logic.luau` — pure helpers for group ordering and traffic dedup (unit-tested).
- `widget.luau` — icon-only status item (route/route-off glyph + tooltip).
- `panel.luau` — control panel.
- `shortcut.luau` — rule/global mode toggle.
- `translations/` — user-facing strings.
