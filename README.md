# custom-noctalia-plugins

A minimal Noctalia plugin source containing a single plugin:
[`mdj2812/mihomo-control`](./mihomo-control/) — a modified fork of the
`mihomo-control` plugin from
[`noctalia-dev/community-plugins`](https://github.com/noctalia-dev/community-plugins).

This repository is **not** a fork of the whole community-plugins repo. It ships
only the one plugin directory plus the `catalog.toml` index a Noctalia source
needs, so it can be used as a standalone path or git source.

> **Attribution.** The original plugin was written by
> [mdj2812](https://github.com/mdj2812) and released under the MIT License.
> This fork keeps the original plugin ID (`mdj2812/mihomo-control`), author
> metadata and license notice. See [LICENSE](./LICENSE) and
> [mihomo-control/README.md](./mihomo-control/README.md) for the upstream
> documentation, which is retained.

## Differences from upstream 0.1.3

- **TUN runtime toggle** — the panel's control row gains a `TUN` switch that
  reads the live `tun.enable` value from `GET /configs` and flips it via
  `PATCH /configs` (`{"tun": {"enable": true|false}}`). It is a runtime toggle
  only; the declarative Mihomo config file is never touched.
- **Update subscriptions** — a panel button that updates every HTTP
  (remote-subscription) proxy provider via `PUT /providers/proxies/<name>`.
  File/inline providers are skipped, provider names are percent-encoded, and a
  summary notification reports the success/failure counts.
- **Text-only bar widget** — the bar capsule shows only the configured label
  (mode by default), no icon; the icon size/color settings are removed.
- Everything else (mode switching, restart, proxy groups, latency tests,
  traffic stream, shortcut) is unchanged from upstream.

Version is bumped to `0.1.7` in both `plugin.toml` and `catalog.toml`.
Noctalia only accepts strict `MAJOR.MINOR.PATCH` versions (no pre-release
suffixes), so a `0.1.3-ordchaos.1` style string would be rejected.

## Repository layout

```text
.
├── catalog.toml          # plugin source index ([[plugin]] rows)
├── LICENSE               # MIT — original author + fork modifications
├── README.md             # this file
└── mihomo-control/       # the plugin (see its README.md for usage/settings)
```

## Local development install (path source)

From the root of this repository:

```sh
noctalia msg plugins source add custom-noctalia-plugins path "$PWD"
noctalia msg plugins enable mdj2812/mihomo-control
```

`source add` requires the syntax `<name> <git|path> <location>`; the source
name is arbitrary but must be unique.

### Source precedence

The built-in `official` and `community` sources are lowest precedence.
User-added sources override them for the same plugin ID (later config entries
override earlier ones; a drop-in under the shell's local data dir overrides
everything). Keeping the original ID `mdj2812/mihomo-control` is therefore
intentional: this path source shadows the community source's copy of the same
plugin without touching any other plugin.

### Verifying the local copy is loaded

```sh
noctalia msg plugins list | grep mihomo
```

It must show `mdj2812/mihomo-control [custom-noctalia-plugins] 0.1.7` — the source
name in brackets proves the local copy won. If it still says `[community]`,
check that the path source was added and is enabled.

### Removing the dev source

```sh
noctalia msg plugins disable mdj2812/mihomo-control   # optional: stop using it
noctalia msg plugins source remove custom-noctalia-plugins
```

With the source removed and the plugin still enabled, the plugin falls back to
the built-in community copy (0.1.3) under the same ID.

### Hot reload

- `.luau` entry scripts and modules they `require()` (e.g.
  `service.luau`, `panel.luau`, `group_logic.luau`) are file-watched: saving a
  file reloads that entry live. No re-enable needed.
- `plugin.toml`, `catalog.toml`, `translations/*.json` and asset changes are
  not hot-reloaded — run
  `noctalia msg plugins disable mdj2812/mihomo-control` +
  `noctalia msg plugins enable mdj2812/mihomo-control` after changing them.
  (A translation edit also takes effect after the entry script that uses it
  is reloaded, e.g. by touching the `.luau` file.)

## Using this repository as a git source

After pushing to GitHub (or any git host):

```sh
noctalia msg plugins source add custom-noctalia-plugins git https://github.com/OrdChaos/custom-noctalia-plugins
noctalia msg plugins enable mdj2812/mihomo-control
```

Requirements for a git source:

- `catalog.toml` at the repository root (required — git sources are read via
  `git show`, not by scanning the working tree);
- one directory per plugin directly under the root, each with its own
  `plugin.toml`.

After pushing new commits:

```sh
noctalia msg plugins update custom-noctalia-plugins
```

The git source is cached locally by Noctalia; `update` fetches the new HEAD,
re-exports the plugin, and re-scans manifests.

## Testing

Offline (no running Mihomo required):

```sh
cd mihomo-control
noctalia plugins lint .          # manifest/code cross-check (parses the Luau)
lua5.4 tests/group_order_test.lua
```

Live smoke test while Noctalia is running (adds IPC checks):

```sh
./mihomo-control/tests/smoke.sh
```

New commands can also be driven directly over IPC:

```sh
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"tun","enabled":true}'
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"update_subscriptions"}'
```
