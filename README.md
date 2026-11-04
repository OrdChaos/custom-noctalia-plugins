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

## Upstream base

This build tracks upstream **0.2.1** (`mihomo-control/` in
[`noctalia-dev/community-plugins`](https://github.com/noctalia-dev/community-plugins),
2026-10-26). The 0.2.x line brought:

- **Multi-server controller profiles** — the panel has a **Server** dropdown,
  profiles and per-server proxy-group order live in `servers.json`, and
  **Manage** edits the active profile.
- **`jq`-projected polling** — oversized `/connections` and `/proxies`
  responses are projected through `jq` so polling stays inside Noctalia's Luau
  CPU budget. `jq` is now a declared `plugin.toml` dependency and must be on
  `PATH`.
- **Hard reload** — right-click the panel refresh button to disable/enable the
  plugin; left-click only re-polls the controller.
- **Plugin API 43** — theme-role rename (`surface_container`,
  `outline_variant`); requires Noctalia 5.4.0 or newer.

Upstream lives in a monorepo; this repository is a standalone path/git source,
so tracking upstream is a manual replay:

1. copy `mihomo-control/` from the upstream repo;
2. re-apply the custom changes below (they are small and localized);
3. `noctalia plugins lint .` and `lua tests/group_order_test.lua`.

## Differences from upstream 0.2.1

- **TUN runtime toggle** — the panel's control row gains a `TUN` switch that
  reads the live `tun.enable` value from `GET /configs` and flips it via
  `PATCH /configs` (`{"tun": {"enable": true|false}}`). It is a runtime toggle
  only; the declarative Mihomo config file is never touched.
- **Update subscriptions** — a panel button that enumerates
  `/providers/proxies` and updates every HTTP (remote-subscription) provider via
  `PUT /providers/proxies/<name>`. File/inline providers are skipped, provider
  names are percent-encoded, and a summary notification reports the
  success/failure counts. The button is disabled while a pass is running.
- **Icon-only status widget** — the bar item is a fixed-size icon rendered
  through Noctalia's standard status-icon pipeline: the Tabler `route` glyph
  when the Mihomo TUN path is confirmed up (controller reachable + TUN on),
  `route-off` otherwise (fail-closed). No rates, no colors, no width changes.
- **No widget presentation settings** — the upstream `label_content`,
  `icon_size`, `icon_color_mode` and `icon_color` settings are removed from
  `plugin.toml`/translations; only `panel_placement` remains.
- Everything else (multi-server profiles, mode switching, restart, proxy
  groups, latency tests, traffic stream, shortcut, `jq` projection, hard
  reload) is unchanged from upstream 0.2.1.

Version is `0.2.3` in both `plugin.toml` and `catalog.toml` (upstream 0.2.1 +
custom patch). Noctalia only accepts strict `MAJOR.MINOR.PATCH` versions (no
pre-release suffixes), so a `0.2.1-ordchaos.1` style string would be rejected.

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

It must show `mdj2812/mihomo-control [custom-noctalia-plugins] 0.2.3` — the
source name in brackets proves the local copy won. If it still says
`[community]`, check that the path source was added and is enabled.

### Removing the dev source

```sh
noctalia msg plugins disable mdj2812/mihomo-control   # optional: stop using it
noctalia msg plugins source remove custom-noctalia-plugins
```

With the source removed and the plugin still enabled, the plugin falls back to
the built-in community copy (0.2.1) under the same ID.

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
lua tests/group_order_test.lua   # Lua 5.2+; upstream smoke.sh uses lua5.4
```

Live smoke test while Noctalia is running (adds IPC checks; needs `jq` on
`PATH`):

```sh
./mihomo-control/tests/smoke.sh
```

New commands can also be driven directly over IPC:

```sh
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"tun","enabled":true}'
noctalia msg plugin mdj2812/mihomo-control:service all cmd '{"op":"update_subscriptions"}'
```
