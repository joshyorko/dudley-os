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
copy_executable /ctx/oci/dsb-common/dudley/usr/libexec/dudley/configure-homebrew-no-ask /usr/libexec/dudley/configure-homebrew-no-ask
copy_tree /ctx/oci/dsb-common/dudley/usr/share/backgrounds/dudley /usr/share/backgrounds/dudley
copy_tree /ctx/oci/dsb-common/dudley/usr/share/glib-2.0/schemas /usr/share/glib-2.0/schemas
copy_tree /ctx/oci/dsb-common/dudley/usr/share/gnome-background-properties /usr/share/gnome-background-properties
copy_tree /ctx/oci/dsb-common/dudley/usr/share/ublue-os/homebrew /usr/share/ublue-os/homebrew
copy_file /ctx/oci/dsb-common/dudley/usr/share/ublue-os/vscode-extensions.list /usr/share/ublue-os/vscode-extensions.list

copy_tree /ctx/custom/system_files/etc/fonts/conf.d /etc/fonts/conf.d
copy_tree /ctx/custom/system_files/usr/share/glib-2.0/schemas /usr/share/glib-2.0/schemas
copy_tree /ctx/custom/system_files/usr/share/ublue-os/user-setup.hooks.d /usr/share/ublue-os/user-setup.hooks.d
copy_file /ctx/custom/dakota/etc/dconf/db/distro.d/99-dudley-terminal-keybindings \
    /etc/dconf/db/distro.d/99-dudley-terminal-keybindings
copy_file /ctx/custom/dakota/etc/ghostty/config /etc/ghostty/config
copy_executable \
    /ctx/custom/dakota/usr/share/ublue-os/user-setup.hooks.d/18-dudley-docker-engine.sh \
    /usr/share/ublue-os/user-setup.hooks.d/18-dudley-docker-engine.sh
/ctx/build/install-dakota-hooks.sh \
    /ctx/oci/dsb-common/dudley/usr/share/ublue-os/user-setup.hooks.d \
    /usr/share/ublue-os/user-setup.hooks.d

/ctx/build/install-dakota-just.sh \
    /ctx/oci/dsb-common/shared/usr/share/ublue-os/just \
    /ctx/oci/dsb-common/dudley/usr/share/ublue-os/just \
    /ctx/custom/ujust \
    /usr/share/ublue-os/just

/ctx/build/install-dakota-chrome.sh /ctx/oci/google-chrome /
/ctx/build/install-dakota-docker.sh /ctx/oci/docker /

systemctl enable docker.socket

glib-compile-schemas /usr/share/glib-2.0/schemas
dconf update

DUDLEY_STREAM=dakota \
BASE_DISTRIBUTION=dakota \
FINAL_IMAGE_REF="${FINAL_IMAGE_REF}" \
BASE_IMAGE_REF="${BASE_IMAGE_REF}" \
SHA_HEAD_SHORT="${SHA_HEAD_SHORT}" \
/ctx/build/20-final-metadata.sh
