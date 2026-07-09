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
- **media-mini** — Now-playing via playerctl/MPRIS. Expands from 20 to 40 characters on hover only if needed, scrolls as a marquee if still too long. Left-click opens the media panel, right-click toggles play/pause.

All widgets share the same open/close animation timing (60fps ease) and use UTF-8-safe character reveal so multi-byte glyphs never get cut mid-character during the animation.

## Caveats

- Built and tested against noctalia `v5.0.0~beta1`. The plugin bridge in this version only forwards `onClick`/`onRightClick`/`onMiddleClick`/`onHover` to bar widgets — no scroll wheel or drag/pointer-position events reach plugins, so anything resembling a draggable slider is approximated with click-to-step instead. See [noctalia-dev/noctalia#3340](https://github.com/noctalia-dev/noctalia/issues/3340) (scroll) and [#3339](https://github.com/noctalia-dev/noctalia/issues/3339) (panel anchor position) for the upstream gaps this hits.
- `sysmon-cpu`'s wattage reading requires Intel RAPL (`/sys/class/powercap/intel-rapl:0`); no AMD equivalent is wired up.
- `sysmon-temp`'s optional GPU reading shells out to `nvidia-smi`; no AMD/Intel GPU temp source is wired up.

## License

MIT
