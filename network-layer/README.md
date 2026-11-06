# Network Layer

A native Noctalia network layer for the bar and a control panel.

It is intentionally narrower than `mihomo-control`:

- controller connection status, version and endpoint
- direct / proxy / global mode selector
- TUN on/off
- update HTTP subscriptions
- restart Mihomo
- policy-group selection
- per-group and all-group latency tests with completion notifications
- live traffic with an optional graph
- bar icon reflecting controller + TUN state (struck-through otherwise)
- persistent DNS mode selector: fixed DoH vs DHCP DNS

It does **not** include controller profiles, connection lists or group
reordering. DNS mode is the only host-level setting: no domain lists,
no per-connection rules, no custom CLI.

## UI

The panel uses Noctalia's own `ui.*` vocabulary only: sibling cards for
Mihomo, traffic, policy groups and DNS, segmented selectors, labels, toggles,
buttons, selects, a graph and one scroll container. The top row keeps the
Mihomo and traffic cards side by side; DNS and policy groups span the panel
underneath. There are no nested cards.

The panel is a subscriber. All HTTP work belongs to `service.luau`, which
publishes one `network.*` state namespace. Actions flow back through
`network.command`.

## DNS mode

The DNS card writes the host mode file directly:

```text
/var/lib/guixcfg-dns/mode   fixed | dhcp
```

No custom CLI is installed. The root applier watches that file, validates it,
switches `/run/guixcfg-dns/smartdns.conf`, and restarts SmartDNS. The plugin
reads `/run/guixcfg-dns/applied` and `/run/guixcfg-dns/status` for feedback.

- `fixed`: only DoH
- `dhcp`: only NetworkManager dnsmasq/DHCP DNS
- no fallback between the two

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

## Mihomo assumptions

The plugin is transport-agnostic: it talks to the external controller over
HTTP(S). The host now disables Mihomo DNS entirely; SmartDNS supplies real
addresses and Mihomo only carries TUN/proxy/rule traffic. DNS ownership and
mode persistence are host concerns, not the Mihomo controller.

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
