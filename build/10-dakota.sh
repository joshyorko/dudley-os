#!/usr/bin/env bash
set -euo pipefail

for command in bootc ujust podman rsync jq dconf glib-compile-schemas; do
    command -v "${command}" >/dev/null
done

copy_tree() {
    local source="$1"
    local destination="$2"
    shift 2

    [[ -d "${source}" ]] || return 0
    install -d -m 0755 "${destination}"
    rsync -a "$@" "${source}/" "${destination}/"
}

copy_file() {
    local source="$1"
    local destination="$2"

    [[ -f "${source}" ]] || return 0
    install -D -m 0644 "${source}" "${destination}"
}

copy_executable() {
    local source="$1"
    local destination="$2"

    [[ -f "${source}" ]] || return 0
    install -D -m 0755 "${source}" "${destination}"
}

copy_tree /ctx/oci/dsb-common/shared/usr/share/ublue-os/just /usr/share/ublue-os/just

copy_tree /ctx/oci/dsb-common/dudley/etc/dconf /etc/dconf
copy_tree /ctx/oci/dsb-common/dudley/etc/flatpak/preinstall.d /etc/flatpak/preinstall.d
copy_file /ctx/oci/dsb-common/dudley/etc/skel/.config/Code/User/settings.json /etc/skel/.config/Code/User/settings.json
copy_file "/ctx/oci/dsb-common/dudley/etc/skel/.config/Code - Insiders/User/settings.json" "/etc/skel/.config/Code - Insiders/User/settings.json"
copy_file /ctx/oci/dsb-common/dudley/etc/xdg/autostart/dudley-random-wallpaper.desktop /etc/xdg/autostart/dudley-random-wallpaper.desktop
copy_executable /ctx/oci/dsb-common/dudley/usr/bin/dudley-build-info /usr/bin/dudley-build-info
copy_executable /ctx/oci/dsb-common/dudley/usr/bin/dudley-random-wallpaper /usr/bin/dudley-random-wallpaper
copy_executable /ctx/oci/dsb-common/dudley/usr/bin/dudley-theme /usr/bin/dudley-theme
copy_executable /ctx/oci/dsb-common/dudley/usr/bin/dudley-wallpaper /usr/bin/dudley-wallpaper
copy_tree /ctx/oci/dsb-common/dudley/usr/lib/dudley_theme /usr/lib/dudley_theme --exclude=__pycache__
copy_tree /ctx/oci/dsb-common/dudley/usr/share/backgrounds/dudley /usr/share/backgrounds/dudley
copy_tree /ctx/oci/dsb-common/dudley/usr/share/glib-2.0/schemas /usr/share/glib-2.0/schemas
copy_tree /ctx/oci/dsb-common/dudley/usr/share/gnome-background-properties /usr/share/gnome-background-properties
copy_tree /ctx/oci/dsb-common/dudley/usr/share/ublue-os/homebrew /usr/share/ublue-os/homebrew
copy_tree /ctx/oci/dsb-common/dudley/usr/share/ublue-os/just /usr/share/ublue-os/just
copy_tree /ctx/oci/dsb-common/dudley/usr/share/ublue-os/user-setup.hooks.d /usr/share/ublue-os/user-setup.hooks.d \
    --include=20-dudley-vscode-extensions.sh --include=25-dudley-theme.sh --exclude='*'
copy_file /ctx/oci/dsb-common/dudley/usr/share/ublue-os/vscode-extensions.list /usr/share/ublue-os/vscode-extensions.list

copy_tree /ctx/custom/system_files/etc/fonts/conf.d /etc/fonts/conf.d
copy_tree /ctx/custom/system_files/usr/share/glib-2.0/schemas /usr/share/glib-2.0/schemas
copy_tree /ctx/custom/system_files/usr/share/ublue-os/user-setup.hooks.d /usr/share/ublue-os/user-setup.hooks.d

if [[ -d /ctx/custom/ujust ]]; then
    install -d -m 0755 /usr/share/ublue-os/just
    find /ctx/custom/ujust -type f -name '*.just' -print0 | sort -z | xargs -0r cat > /usr/share/ublue-os/just/60-custom.just
fi

glib-compile-schemas /usr/share/glib-2.0/schemas
dconf update

DUDLEY_STREAM=dakota \
BASE_DISTRIBUTION=dakota \
FINAL_IMAGE_REF="${FINAL_IMAGE_REF}" \
BASE_IMAGE_REF="${BASE_IMAGE_REF}" \
SHA_HEAD_SHORT="${SHA_HEAD_SHORT}" \
/ctx/build/20-final-metadata.sh
