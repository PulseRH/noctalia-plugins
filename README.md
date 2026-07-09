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
- **volume-hover** — Volume icon + text slider (bar/knob) + percentage. Left/right-click steps volume, middle-click toggles mute.
- **sysmon-cpu** — Compact gauge bar or plain percentage; hover shows percent, clock speed, and package wattage (Intel RAPL).
- **sysmon-ram** — Compact gauge bar or plain percentage; hover shows percent and used/total GB (auto-detected).
- **sysmon-temp** — CPU package temperature always shown; hover can also show GPU, hottest NVMe, RAM (DIMM), and hottest CPU core, each toggleable.
- **sysmon-net-down** / **sysmon-net-up** — Auto-detects the busiest network interface. Hides entirely below a configurable idle threshold; hovering always shows it.
- **media-mini** — Now-playing via playerctl/MPRIS, with rounded cover art (downloaded/cached for remote art, used directly for local files, falls back to a YouTube thumbnail when a browser's MPRIS doesn't expose real art; rounding needs ImageMagick) and an inline block-character playback-progress bar. Both are on by default and can be turned off in the widget's settings, which also expose compact/expand text width, cover size, and rounding amount. Font follows the bar's own per-widget font picker (every widget has one built in) and is only forced to monospace while the progress bar is on, since that needs its block characters. Scrolls as a marquee if still too long even expanded, and keeps polling while scrolling so a track change is never missed. Left-click opens the media panel, right-click toggles play/pause.
- **active-window-hover** — Focused window's title via `wlrctl` (wlr-foreign-toplevel-management, compositor-agnostic), with the real per-app icon (resolved from its `.desktop` entry + icon theme, rasterized/cached via ImageMagick) in place of a generic glyph when one can be found. Compact/expand text width and icon size are all configurable settings, animating between them on hover; scrolls as a marquee if still too long even expanded. Hidden entirely when nothing is focused.

All widgets share the same open/close animation timing (60fps ease) and use UTF-8-safe character reveal so multi-byte glyphs never get cut mid-character during the animation.

## Caveats

- Built and tested against noctalia `v5.0.0~beta1`. The plugin bridge in this version only forwards `onClick`/`onRightClick`/`onMiddleClick`/`onHover` to bar widgets — no scroll wheel or drag/pointer-position events reach plugins, so anything resembling a draggable slider is approximated with click-to-step instead. See [noctalia-dev/noctalia#3340](https://github.com/noctalia-dev/noctalia/issues/3340) (scroll) and [#3339](https://github.com/noctalia-dev/noctalia/issues/3339) (panel anchor position) for the upstream gaps this hits.
- `sysmon-cpu`'s wattage reading requires Intel RAPL (`/sys/class/powercap/intel-rapl:0`); no AMD equivalent is wired up.
- `sysmon-temp`'s optional GPU reading shells out to `nvidia-smi`; no AMD/Intel GPU temp source is wired up.
- `media-mini`'s progress bar is text (block characters), not an actual background fill — bar widgets have no rect/opacity primitive exposed to plugins, only `setText`/`setGlyph`/`setImage`/`setColor`/etc. Rounded cover art shells out to `magick`/`convert` (ImageMagick) to bake a circular alpha mask; if neither is installed, art is shown unrounded instead. The unfilled portion uses `▮` rather than the more obvious `░`, since `░` renders as a dot/checker texture in every font tested here, not a flat tone — that's the glyph's actual designed appearance (a 25%-density dither), not a font quirk. Terminals like Ghostty that draw it looking solid are special-casing box-drawing characters in the terminal's own renderer rather than using the font's glyph at all, which isn't something available to a bar widget's text.
- `active-window-hover` requires `wlrctl` (e.g. `dnf install wlrctl`/AUR `wlrctl`) and a compositor that implements `wlr-foreign-toplevel-management-v1` (confirmed working under driftwm; should work under sway, Hyprland, river, etc. too since it's the standard protocol, not compositor-specific code). Per-app icon lookup also needs `magick`/`convert`; falls back to a generic window glyph for apps with no matching `.desktop` entry/icon (e.g. internal windows with no installed launcher) or if ImageMagick is missing.

## License

MIT
