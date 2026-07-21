# noctalia-plugins

A small collection of Noctalia v5 bar widget plugins.

## Install

1. In Noctalia: **Settings → Plugins → Add source**
2. Add this repo's URL as a git source
3. Enable whichever plugin(s) you want, then add their widget from the bar's Add-widget picker

Or via CLI:

```
noctalia msg plugins source add pulser-plugins git https://github.com/PulseRH/noctalia-plugins
noctalia msg plugins enable pulser/clock-hover
```

## Plugins

- **clock-hover** — Compact clock that expands to a full weekday/date/time on hover, with an animated open/close reveal.
- **volume-hover** — Persistent speaker glyph (Tabler icon, struck-through when muted) with a solid rounded slider + percentage that reveals to its right on hover with an animated open/close. Scroll over the widget to change volume, left-click opens the audio panel, right-click toggles mute. Bar is baked in the theme colour (needs ImageMagick).
- **sysmon-cpu** — Compact gauge bar or plain percentage; hover shows percent, clock speed, and package wattage (Intel RAPL).
- **sysmon-ram** — Compact gauge bar or plain percentage; hover shows percent and used/total GB (auto-detected).
- **sysmon-temp** — CPU package temperature always shown; hover can also show GPU, hottest NVMe, RAM (DIMM), and hottest CPU core, each toggleable.
- **sysmon-net-down** / **sysmon-net-up** — Auto-detects the busiest network interface. Hides entirely below a configurable idle threshold; hovering always shows it.
- **media-mini** — Now-playing via playerctl/MPRIS, preferring whichever player is actually Playing over a paused/stale one (e.g. a YouTube tab that navigated away, leaving dead MPRIS metadata behind), with rounded cover art (downloaded/cached for remote art, used directly for local files, falls back to a YouTube thumbnail when a browser's MPRIS doesn't expose real art; rounding needs ImageMagick) and an image-rendered playback-progress bar — beside the art when cover art is on, or in place of the play/pause glyph when it's off. Both are on by default and can be turned off in the widget's settings, which also expose compact/expand text width, cover size, and rounding amount. Scrolls as a marquee if still too long even expanded, and keeps polling while scrolling so a track change is never missed. Left-click toggles play/pause, right-click opens the media panel, and scrolling over the widget skips tracks (scroll up = previous, scroll down = next).
- **active-window-hover** — Focused window's title via `wlrctl` (wlr-foreign-toplevel-management, compositor-agnostic), with the real per-app icon (resolved from its `.desktop` entry + icon theme, rasterized/cached via ImageMagick) in place of a generic glyph when one can be found. Compact/expand text width and icon size are all configurable settings, animating between them on hover; scrolls as a marquee if still too long even expanded. Hidden entirely when nothing is focused.

All widgets share the same open/close animation timing (60fps ease) and use UTF-8-safe character reveal so multi-byte glyphs never get cut mid-character during the animation.

## Caveats

- **Requires a recent noctalia v5 build** — these target plugin API 5 (`plugin_api = 5` in each manifest, and settings use translation keys under `translations/`). On older builds they won't load; use the [`pre-plugin-api5`](https://github.com/PulseRH/noctalia-plugins/releases/tag/pre-plugin-api5) tag for the last version that runs on pre-API-5 noctalia.
- As of the mid-2026 builds the plugin bridge forwards **`onScroll`** to bar widgets (per [noctalia-dev/noctalia#3428](https://github.com/noctalia-dev/noctalia/pull/3428)), so widgets can react to the scroll wheel (volume-hover changes volume, media-mini skips tracks). It still does **not** forward pointer *position* to `onClick`/`onRightClick`, so a click can't tell where inside the widget it landed — no drag/seek, and no multiple hit-tested buttons within one widget. Bar widgets get only left-click, right-click, scroll, and hover.
- `sysmon-cpu`'s wattage reading requires Intel RAPL (`/sys/class/powercap/intel-rapl:0`); no AMD equivalent is wired up.
- `sysmon-temp`'s optional GPU reading shells out to `nvidia-smi`; no AMD/Intel GPU temp source is wired up.
- `media-mini`'s progress bar and rounded cover art are both baked with `magick`/`convert` (ImageMagick) — the bar is a rendered image (not text), so it's always a flat solid fill and never touches the widget's Font setting, and cover art gets a rounded-rectangle alpha mask. Bar widgets expose only `setText`/`setGlyph`/`setImage`/`setColor`/etc. (no rect/opacity primitive), and the single image slot is why art and bar are composited side by side into one image. Position is bucketed into a handful of discrete fill levels so only a few bar images ever get generated/cached. Without ImageMagick, the bar is disabled and art is shown unrounded.
- `active-window-hover` requires `wlrctl` (e.g. `dnf install wlrctl`/AUR `wlrctl`) and a compositor that implements `wlr-foreign-toplevel-management-v1` (confirmed working under driftwm; should work under sway, Hyprland, river, etc. too since it's the standard protocol, not compositor-specific code). Per-app icon lookup also needs `magick`/`convert`; falls back to a generic window glyph for apps with no matching `.desktop` entry/icon (e.g. internal windows with no installed launcher) or if ImageMagick is missing.

## License

MIT
