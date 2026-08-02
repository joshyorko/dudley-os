#!/usr/bin/env bash
set -euo pipefail

source_root="$1"
destination_root="${2:-/}"

chrome_source="${source_root%/}/opt/google/chrome"
chrome_destination="${destination_root%/}/usr/lib/opt/google/chrome"

test -x "${chrome_source}/google-chrome"
install -d -m 0755 \
    "${chrome_destination}" \
    "${destination_root%/}/usr/bin" \
    "${destination_root%/}/usr/lib/tmpfiles.d" \
    "${destination_root%/}/var/opt"
rsync -a "${chrome_source}/" "${chrome_destination}/"

for relative_path in \
    usr/share/appdata \
    usr/share/applications \
    usr/share/gnome-control-center/default-apps \
    usr/share/icons \
    usr/share/man/man1; do
    if [[ -d "${source_root%/}/${relative_path}" ]]; then
        install -d -m 0755 "${destination_root%/}/${relative_path}"
        rsync -a \
            "${source_root%/}/${relative_path}/" \
            "${destination_root%/}/${relative_path}/"
    fi
done

for command in xdg-desktop-menu xdg-icon-resource xdg-mime xdg-settings; do
    if [[ -x "${source_root%/}/usr/bin/${command}" ]]; then
        install -m 0755 \
            "${source_root%/}/usr/bin/${command}" \
            "${destination_root%/}/usr/bin/${command}"
    fi
done

for size in 16 24 32 48 64 128 256; do
    install -D -m 0644 \
        "${chrome_source}/product_logo_${size}.png" \
        "${destination_root%/}/usr/share/icons/hicolor/${size}x${size}/apps/google-chrome.png"
done

gtk-update-icon-cache -f -t \
    "${destination_root%/}/usr/share/icons/hicolor"

ln -snf /opt/google/chrome/google-chrome \
    "${destination_root%/}/usr/bin/google-chrome"
ln -snf /opt/google/chrome/google-chrome \
    "${destination_root%/}/usr/bin/google-chrome-stable"
ln -snf ../../usr/lib/opt/google "${destination_root%/}/var/opt/google"
printf 'L /var/opt/google - - - - ../../usr/lib/opt/google\n' > \
    "${destination_root%/}/usr/lib/tmpfiles.d/dudley-google-chrome.conf"
