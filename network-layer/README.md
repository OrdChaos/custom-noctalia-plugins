# Network Layer

A native Noctalia network layer for the bar and a control panel.

It is intentionally narrower than `mihomo-control`:

- controller connection status, version and endpoint
- direct / proxy / global mode selector
- TUN on/off
- update HTTP subscriptions
- restart Mihomo
- policy-group selection
- per-group and all-group latency tests
- live traffic with an optional graph
- bar icon reflecting controller connection state

It does **not** include controller profiles, connection lists, group reordering
or shortcuts. DNS controls are reserved as a separate extension hook inside
the panel.

## UI

The panel uses Noctalia's own `ui.*` vocabulary only: one native Mihomo card,
a segmented mode row, labels, toggles, buttons, selects, a graph and one
scroll container. Traffic and policy groups live inside the same card; there
are no nested cards. The mode selector follows Control Center's power-profile
segmented control rather than a dropdown. The widget uses the standard
status-icon pipeline (`route` / `route-off`).

The panel is a subscriber. All HTTP work belongs to `service.luau`, which
publishes one `network.*` state namespace. Actions flow back through
`network.command`.

## Settings

| Setting              | Default     | Meaning                                      |
| -------------------- | ----------- | -------------------------------------------- |
| Controller host      | `127.0.0.1` | Mihomo external controller host               |
| Controller port      | `9090`      | Mihomo external controller port               |
| Controller secret    | empty       | `Authorization: Bearer` secret                |
| Use HTTPS            | off         | HTTPS controller                              |
| Allow insecure TLS   | off         | Skip certificate verification                 |
| Latency test URL     | gstatic 204 | URL used for latency tests                    |
| Refresh interval     | 2 s         | Controller poll interval                      |
| Panel placement      | attached    | Attached to the bar, or floating              |

`jq` is used only to project oversized `/proxies` responses inside the
service's CPU budget.

## DNS extension point

`panel.luau` has a single `dns_controls()` function near the bottom. Returning
a native card from it inserts the DNS card as a sibling of the Mihomo card;
returning `nil` keeps the current network-only surface. The future DNS layer
should publish its own state and own its controls; this panel does not
pre-empt it.

## Mihomo assumptions

The plugin is transport-agnostic: it talks to the external controller over
HTTP(S). The current host configuration uses `redir-host`; this plugin does not
toggle fake-IP or DNS ownership. See the host architecture docs for the
redir-host / fake-ip decision.

## Development

```sh
noctalia plugins lint .
noctalia msg plugins source add network-layer-dev path "$PWD"
noctalia msg plugins enable ordchaos/network-layer
```

Add the **Network Layer** widget from the Add-widget picker, and open the panel
from the widget. There are no committed data assertions or hardcoded
controller/group fixtures; runtime behavior is exercised against the real
controller.
