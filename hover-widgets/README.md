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

Optional `magick` or `convert` (ImageMagick) rounds media artwork. Volume and progress graphics are drawn directly and do not need ImageMagick. Optional `nvidia-smi` provides NVIDIA temperature. `wlrctl` requires wlr-foreign-toplevel-management-v1 support from the compositor. CPU temperature currently targets Intel coretemp; power needs readable Intel RAPL. See Notes for other hardware limits.

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

Hover expands the original rounded track and circular knob. Click the speaker to mute/unmute; click the track to set volume. Percentage/padding and right-click open the anchored Audio panel. Speaker click can select Audio instead. Rapid writes are serialized and coalesced; stale reads cannot overwrite a newer request. Width and thickness are independent. Circle colour is separate from the track, defaulting to the native Settings slider colour. Turn Show circle knob off for a plain rounded bar.

Enable dragging to drag the same classic track; it stays expanded in that mode. Volume changes continuously during dragging. This is optional and off by default.


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

Click the rounded classic progress pill to seek. Width and thickness are independent of cover size; the ends remain circular. Choose Classic with dragging to keep the same pill and drag its playhead: the fill previews your target and seeks on release, using expanded width. Interactive uses the native slider appearance. Seeking requires player support.

Cover/title clicks toggle playback; right-click opens Media; scrolling skips tracks. Hover expands the title. Hidden when no player is available.


### Hover Active Window (`active-window`)

Hover to expand the title and icon; long titles scroll. Hidden when no window is focused. Requires a compositor exposing wlr-foreign-toplevel-management-v1.


## Settings

Settings below belong to the named widget entry, not to the whole bundle. The clock has no plugin-specific settings.

### Hover Volume (`volume`)

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_knob` | `bool` | `true` | Show the circular volume handle. Turn off for a plain rounded bar; clicking and dragging still work. |
| `knob_color` | `select` | `on_primary` | Independent knob colour. On-primary matches the knob used by native Settings sliders. |
| `drag_enabled` | `bool` | `false` | Drag to change volume using the classic bar appearance. Keeps the track expanded so it stays available to grab. |
| `slider_thickness` | `int` | `12` | Track thickness, independent of its width. The circular knob is 1.5 times this size. |
| `icon_click` | `select` | `mute` | Click the speaker to toggle mute, or open Audio. Click the expanded track to set volume. Percentage/padding and right-click open Audio. |
| `bar_color` | `select` | `primary` | Theme colour role used for the classic filled track and circular knob. |
| `slider_width` | `int` | `90` | Expanded track width in pixels, independent of thickness and speaker size. |
| `scroll_step` | `int` | `5` | How much one scroll notch changes the volume. |
| `invert_scroll` | `bool` | `false` | By default scroll up raises the volume. Turn this on if it feels backwards. |
| `show_percent` | `bool` | `true` | Show volume percentage or muted. Click this label to open Audio. |


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
| `progress_thickness` | `int` | `8` | Progress bar thickness, independent of cover size and width. Rounded ends stay circular. |
| `progress_style` | `select` | `classic` | Classic supports clicks. Classic with dragging keeps the same pill, uses expanded width, previews while dragging and seeks on release. Interactive uses the native slider appearance. |
| `show_cover_art` | `bool` | `true` | Replace the play/pause icon with the track's (rounded) cover art when available. |
| `show_progress_bar` | `bool` | `true` | Show a playback-position bar next to the icon. It's a rendered image (not text), so it never affects the widget's Font setting -- when cover art is on, the bar sits beside the art; when off, it replaces the play/pause glyph. |
| `compact_width` | `int` | `20` | Text width when not hovering. The text only actually shrinks to this if it's longer -- a short title just stays put. |
| `expand_width` | `int` | `40` | Text width while hovering. If the title is still longer than this, it scrolls as a marquee instead of growing further. |
| `cover_size` | `int` | `20` | Size of the cover art icon in place of the play/pause glyph. |
| `corner_rounding` | `int` | `100` | 0 = square corners, 100 = fully circular. |
| `progress_width` | `int` | `35` | Width of the seek slider in this state. Expanded width is at least the compact width. Set both equal for a fixed length. |
| `progress_expand_width` | `int` | `35` | Width of the seek slider in this state. Expanded width is at least the compact width. Set both equal for a fixed length. |


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

## Version 1.1.0

Original visual styles remain the defaults. Volume has separate speaker, track and label click targets. Media adds configurable compact/expanded progress widths and an opt-in Interactive seek-slider style. Seeking commits on release and targets the displayed player; pending seeks are discarded when its track changes.

## Version 1.2.0

Classic progress bars now accept position clicks without changing their artwork. Volume clicks map onto the original knob travel; media clicks seek the displayed player to the corresponding point in the track. Media refreshes visibility as soon as a metadata query completes.

Version 1.2.1 gives volume immediate click feedback and refreshes the classic knob as soon as its raster frame completes.

## Version 1.3.0

Volume uses a serialized latest-request queue and discards stale polling results. Rounded bars and knobs are drawn at their actual dimensions, with independent width/thickness. Optional dragging keeps classic shapes, using Noctalia pointer capture; volume updates continuously and media seeks on release.

## Version 1.4.0

Adds a separate Circle colour selector (default: on-primary, matching native Settings sliders) and Show circle knob toggle. Drawing and pointer layers share a fixed centre line, so changing thickness keeps the bars vertically aligned in click and drag modes. Track and moving fill ends use rounded shapes.
