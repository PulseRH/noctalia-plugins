#!/bin/sh
# Resolve a focused window's app_id to a cached, fixed-size PNG icon via its
# .desktop entry + icon theme lookup (freedesktop icon-theme-spec, simplified).
# Prints the icon path on stdout and exits 0 on success; exits non-zero with
# no stdout if no desktop entry or icon file could be found.
set -eu

app_id="$1"
dest="$2"
size="$3"

desktop_dirs="$HOME/.local/share/applications /usr/share/applications /usr/local/share/applications /var/lib/flatpak/exports/share/applications $HOME/.local/share/flatpak/exports/share/applications /var/lib/snapd/desktop/applications"

desktop=""
for dir in $desktop_dirs; do
    [ -d "$dir" ] || continue
    match=$(find -L "$dir" -maxdepth 1 -iname "*${app_id}*.desktop" 2>/dev/null | head -1)
    if [ -n "$match" ]; then
        desktop="$match"
        break
    fi
done
[ -n "$desktop" ] || exit 1

icon=$(grep -m1 "^Icon=" "$desktop" | cut -d= -f2-)
[ -n "$icon" ] || exit 1

case "$icon" in
    /*)
        src="$icon"
        ;;
    *)
        icon_dirs="$HOME/.local/share/icons /usr/share/icons /usr/share/pixmaps /var/lib/flatpak/exports/share/icons $HOME/.local/share/flatpak/exports/share/icons"
        src=""

        # Prefer the user's actually-configured icon theme first (e.g. a
        # Papirus/Adwaita variant) over whichever theme `find` happens to
        # traverse into first -- different themes often draw the same app
        # differently (confirmed: hicolor's ghostty icon is not what the
        # user's Papirus-Dark theme -- and thus every native widget -- shows).
        current_theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'\"")
        if [ -n "${current_theme:-}" ]; then
            for sizedir in 128x128 96x96 64x64 48x48 32x32 scalable; do
                for dir in "$HOME/.local/share/icons/$current_theme" "/usr/share/icons/$current_theme"; do
                    [ -d "$dir" ] || continue
                    match=$(find -L "$dir" -path "*/${sizedir}/apps/${icon}.png" -o -path "*/${sizedir}/apps/${icon}.svg" 2>/dev/null | head -1)
                    if [ -n "$match" ]; then
                        src="$match"
                        break 2
                    fi
                done
            done
        fi

        if [ -z "$src" ]; then
            for sizedir in 128x128 96x96 64x64 48x48 32x32 scalable; do
                for dir in $icon_dirs; do
                    [ -d "$dir" ] || continue
                    match=$(find -L "$dir" -path "*/${sizedir}/apps/${icon}.png" -o -path "*/${sizedir}/apps/${icon}.svg" 2>/dev/null | head -1)
                    if [ -n "$match" ]; then
                        src="$match"
                        break 2
                    fi
                done
            done
        fi
        if [ -z "$src" ]; then
            for dir in $icon_dirs; do
                [ -d "$dir" ] || continue
                match=$(find -L "$dir" \( -iname "${icon}.png" -o -iname "${icon}.svg" -o -iname "${icon}.xpm" \) 2>/dev/null | head -1)
                if [ -n "$match" ]; then
                    src="$match"
                    break
                fi
            done
        fi
        ;;
esac
[ -n "$src" ] || exit 1

if command -v magick >/dev/null 2>&1; then
    magick -background none "$src" -resize "${size}x${size}" "$dest" || exit 1
elif command -v convert >/dev/null 2>&1; then
    convert -background none "$src" -resize "${size}x${size}" "$dest" || exit 1
else
    exit 1
fi

printf '%s' "$dest"
