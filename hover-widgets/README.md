# Hover Widgets

One Noctalia plugin containing nine compact bar widgets. Each widget can be added independently and has its own settings; hover animations reveal extra details without permanently taking up bar space.

![Live compact and expanded widget previews](screenshot.jpg)

## Plugin

| Field | Value |
| --- | --- |
| ID | `pulser/hover-widgets` |
| Entries | Bar widgets: `clock`, `volume`, `cpu`, `ram`, `temp`, `net-down`, `net-up`, `media`, `active-window` |

## Requirements

Noctalia 5.2.0 or later (plugin API 32), on Linux. Commands declared by this bundle: `noctalia`, `wpctl`, `playerctl`, `sh`, and `wlrctl`. The clock and basic system monitors don't invoke the specialised commands; volume uses `wpctl`, media uses `playerctl` and `sh`, and active-window uses `wlrctl`. Because dependencies are declared at plugin scope, missing tools can be reported even if you only use another widget.

Optional `magick` or `convert` (ImageMagick) renders volume frames and rounded media artwork; those widgets have glyph/text fallback. Optional `nvidia-smi` provides NVIDIA temperature. `wlrctl` requires wlr-foreign-toplevel-management-v1 support from the compositor. CPU temperature currently targets Intel coretemp; power needs readable Intel RAPL. See Notes for other hardware limits.

## Usage

Enable **Hover Widgets** in Settings → Plugins once. Add any of its entries independently in Settings → Bar; adding the bundle does not add all nine automatically. Each widget instance has its own settings.

| Entry | Display name | Widget type |
| --- | --- | --- |
| `clock` | Hover Clock | `pulser/hover-widgets:clock` |
| `volume` | Hover Volume | `pulser/hover-widgets:volume` |
| `cpu` | Hover CPU Monitor | `pulser/hover-widgets:cpu` |
| `ram` | Hover Memory Monitor | `pulser/hover-widgets:ram` |
| `temp` | Hover Temperature Monitor | `pulser/hover-widgets:temp` |
| `net-down` | Hover Download Monitor | `pulser/hover-widgets:net-down` |
| `net-up` | Hover Upload Monitor | `pulser/hover-widgets:net-up` |
| `media` | Mini Media | `pulser/hover-widgets:media` |
| `active-window` | Hover Active Window | `pulser/hover-widgets:active-window` |

### Hover Clock (`clock`)

Hover to reveal the full weekday, ordinal date, month and seconds. Uses local time and a 12-hour clock. The ordinal suffix is English; weekday and month names follow the locale.


### Hover Volume (`volume`)

Hover to reveal the volume slider. Scroll up/down to adjust output volume, left-click to open the Audio Control Center, and right-click to toggle mute. The revealed slider is a visual indicator; use the Audio panel for dragging.


### Hover CPU Monitor (`cpu`)

Hover to reveal CPU frequency and package power when available. Left-click opens the System Control Center.


### Hover Memory Monitor (`ram`)

Hover to reveal used/total memory and the percentage. Left-click opens the System Control Center.


### Hover Temperature Monitor (`temp`)

Hover to reveal enabled supplementary sensors. Left-click opens the System Control Center.


### Hover Download Monitor (`net-down`)

Shows receive throughput. Hover expands the reading. Set Hide completely to false to retain a hover target while idle. Left-click opens the System Control Center.


### Hover Upload Monitor (`net-up`)

Shows transmit throughput. Hover expands the reading. Set Hide completely to false to retain a hover target while idle. Left-click opens the System Control Center.


### Mini Media (`media`)

Hover to expand artist/title and scroll long text. Left-click toggles play/pause, right-click opens the Media Control Center. Scroll up for the previous track and down for the next track. Hidden when no player is available.


### Hover Active Window (`active-window`)

Hover to expand the title and icon; long titles scroll. Hidden when no window is focused. Requires a compositor exposing wlr-foreign-toplevel-management-v1.


## Settings

Settings below belong to the named widget entry, not to the whole bundle. The clock has no plugin-specific settings.

### Hover Volume (`volume`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `bar_color` | `select` | `primary` | Theme colour role used for the filled bar and knob. Choices: `primary`, `onsurface`, `secondary`, `tertiary`, `hover`, `error`. |
| `slider_width` | `int` | `90` | On-screen width of the slider image. Height scales with it. Measured in pixels. |
| `scroll_step` | `int` | `5` | How much one scroll notch changes the volume. Percentage points per scroll action. |
| `invert_scroll` | `bool` | `false` | By default scroll up raises the volume. Turn this on if it feels backwards. |
| `show_percent` | `bool` | `true` | Show the numeric volume (or "muted") as text beside the slider. |


### Hover CPU Monitor (`cpu`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `gauge` | `bool` | `true` | Compact display: gauge bar (on) or plain percentage (off) |


### Hover Memory Monitor (`ram`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `gauge` | `bool` | `true` | Compact display: gauge bar (on) or plain percentage (off) |
| `amount_first` | `bool` | `false` | On: shows used GB by default, revealing the percentage and total on hover. Off: shows the percentage by default, revealing used/total GB on hover. |


### Hover Temperature Monitor (`temp`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_gpu` | `bool` | `true` | Show GPU temp on hover |
| `show_nvme` | `bool` | `false` | Show hottest NVMe temp on hover |
| `show_ram` | `bool` | `false` | Show RAM (DIMM) temp on hover |
| `show_hottest_core` | `bool` | `false` | Show hottest CPU core on hover |


### Hover Download Monitor (`net-down`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `threshold_kbps` | `int` | `1024` | Hide entirely below this; hovering always shows it. 1024 = 1 MB/s |
| `compact_units` | `bool` | `true` | 34K/1.2M instead of 34KB/s/1.2MB/s while not hovering |
| `hide_completely` | `bool` | `true` | On: vanishes below the idle threshold. Off: icon stays, only the number hides |


### Hover Upload Monitor (`net-up`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `threshold_kbps` | `int` | `1024` | Hide entirely below this; hovering always shows it. 1024 = 1 MB/s |
| `compact_units` | `bool` | `true` | 34K/1.2M instead of 34KB/s/1.2MB/s while not hovering |
| `hide_completely` | `bool` | `true` | On: vanishes below the idle threshold. Off: icon stays, only the number hides |


### Mini Media (`media`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_cover_art` | `bool` | `true` | Replace the play/pause icon with the track's (rounded) cover art when available. |
| `show_progress_bar` | `bool` | `true` | Show a playback-position bar next to the icon. It's a rendered image (not text), so it never affects the widget's Font setting -- when cover art is on, the bar sits beside the art; when off, it replaces the play/pause glyph. |
| `compact_width` | `int` | `20` | Text width when not hovering. The text only actually shrinks to this if it's longer -- a short title just stays put. Measured in characters. |
| `expand_width` | `int` | `40` | Text width while hovering. If the title is still longer than this, it scrolls as a marquee instead of growing further. Measured in characters. |
| `cover_size` | `int` | `20` | Size of the cover art icon in place of the play/pause glyph. Measured in pixels. |
| `corner_rounding` | `int` | `100` | 0 = square corners, 100 = fully circular. Percentage, 0–100. |


### Hover Active Window (`active-window`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `compact_width` | `int` | `20` | Text width when not hovering. The title only actually shrinks to this if it's longer -- a short title just stays put. Measured in characters. |
| `expand_width` | `int` | `40` | Text width while hovering. If the title is still longer than this, it scrolls as a marquee instead of growing further. Measured in characters. |
| `icon_size` | `int` | `20` | Per-app icon size when compact (not hovering). Only affects the real app icon -- the generic fallback glyph (shown when no icon can be resolved) is a fixed size, since the plugin API doesn't expose glyph sizing. Measured in pixels. |
| `icon_size_hover` | `int` | `28` | Per-app icon size while hovering; animates between this and the compact size along with the text width. Measured in pixels. |


## Notes

All entries are independent Luau runtimes. Media and volume caches are separated into `cache/media-mini` and `cache/volume-hover` beneath this plugin's persistent data directory, with a user-cache fallback. Helper scripts ship with the plugin. No remote code is downloaded or executed.

### Hover Clock

Reads the clock through Noctalia. No network calls or filesystem writes. No subprocesses.


### Hover Volume

Runs wpctl to query and adjust the default PipeWire sink, and noctalia for panel and mute actions. Optional magick or convert renders local images into the plugin data directory. No network access. The packaged Noctalia Tabler font is used when found; otherwise a native glyph is shown.


### Hover CPU Monitor

Reads /proc/stat, CPU0 cpufreq, and Intel RAPL energy counters in /sys. No filesystem writes or network access. Launches noctalia only on click. Power requires readable Intel RAPL counters; it is omitted on unsupported hardware. Frequency is CPU0, not an all-core average.


### Hover Memory Monitor

Reads /proc/meminfo and calculates used memory from MemTotal minus MemAvailable. Values labeled GB are binary GiB. No network or filesystem writes. Launches noctalia only on click.


### Hover Temperature Monitor

Reads Linux hwmon names, labels and temperatures under /sys/class/hwmon. Supports Intel coretemp CPU sensors, NVMe composite sensors and spd5118 DIMMs. Optional nvidia-smi queries NVIDIA GPU temperature on hover. Unsupported or inaccessible readings are omitted; missing CPU temperature displays --°C. No network or filesystem writes. Launches noctalia on click.


### Hover Download Monitor

Reads interface counters from /proc/net/dev. No network requests or filesystem writes. Aggregates non-loopback interfaces; bridge, VPN and physical interfaces can double-count the same traffic. Threshold is KiB/s; KB/s and MB/s labels represent binary units. Launches noctalia only on click.


### Hover Upload Monitor

Reads interface counters from /proc/net/dev. No network requests or filesystem writes. Aggregates non-loopback interfaces; bridge, VPN and physical interfaces can double-count the same traffic. Threshold is KiB/s; KB/s and MB/s labels represent binary units. Launches noctalia only on click.


### Mini Media

Runs the shipped pick-player.sh through sh; it uses playerctl to prefer a Playing MPRIS player. Playback controls target the same selected player that supplies the displayed metadata. Optional magick or convert rounds/composites cover art and progress images. Remote HTTP(S) artwork is downloaded using Noctalia; missing YouTube artwork may request i.ytimg.com thumbnails. Requests disclose your IP and the requested artwork/video id to that host. Local file:// artwork is read directly. Cache images are written only under the plugin data directory. No remote code is executed.


### Hover Active Window

Runs wlrctl to read the focused app id and window title. App icons resolve through Noctalia’s native desktop-entry/icon-theme resolver. No network calls, filesystem writes or external image-processing helper. Window titles can contain private information; consider this before sharing screenshots.


## Migration from separate plugins

The previous entries used different plugin IDs. Replace each old bar widget with the corresponding `pulser/hover-widgets:<entry>` listed above. Reapply your preferred settings to the new instance. After replacement, disable the separate plugin. No automatic migration or removal is performed.

## License

MIT.

## Native panel actions

Clock left-click opens the Control Center Calendar page, matching the native clock. Volume opens Audio, system monitors open System, and media right-click opens Media. These are native widget actions, so panel placement follows Noctalia’s positioning settings and retains the originating widget anchor. Per-instance action settings can override these defaults.
