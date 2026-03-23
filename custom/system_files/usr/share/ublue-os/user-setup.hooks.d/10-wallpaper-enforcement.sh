#!/usr/bin/env bash
set -euo pipefail

randomizer_cmd="$(command -v dudley-random-wallpaper || true)"
if [[ -z "${randomizer_cmd}" && -x /usr/local/bin/dudley-random-wallpaper ]]; then
    randomizer_cmd="/usr/local/bin/dudley-random-wallpaper"
fi

if [[ -x "${randomizer_cmd}" ]]; then
    "${randomizer_cmd}" || true
    exit 0
fi

command -v gsettings >/dev/null 2>&1 || exit 0

wallpaper_dir="/usr/share/backgrounds/dudley"
[[ -d "${wallpaper_dir}" ]] || exit 0

mapfile -d '' wallpapers < <(
    find "${wallpaper_dir}" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
        -print0
)

(( ${#wallpapers[@]} > 0 )) || exit 0

selected_wallpaper="${wallpapers[$((RANDOM % ${#wallpapers[@]}))]}"
selected_uri="file://${selected_wallpaper}"

gsettings set org.gnome.desktop.background picture-uri "${selected_uri}" || true
gsettings set org.gnome.desktop.background picture-uri-dark "${selected_uri}" || true
