#!/usr/bin/env bash
set -euo pipefail

for command in bootc ujust podman python3 jq dconf glib-compile-schemas; do
    if ! command -v "${command}" >/dev/null; then
        echo "Missing required Dakota build command: ${command}" >&2
        exit 1
    fi
done

copy_tree() {
    local source="$1"
    local destination="$2"
    shift 2

    [[ -d "${source}" ]] || return 0
    install -d -m 0755 "${destination}"
    cp -a "$@" "${source}/." "${destination}/"
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

python3 /ctx/oci/dsb-common/scripts/install-payload.py \
    --profile dakota \
    --contract /ctx/oci/dsb-common/contract/dudley-payload.v1.json \
    --dest /

for required in \
    /etc/profile.d/umotd.sh \
    /etc/ublue-os/tags.json \
    /etc/umotd/config.json \
    /usr/libexec/dudley/ensure-homebrew \
    /usr/share/dudley/terminal-contract.json \
    /usr/share/dudley/terminal/ghostty.conf; do
    if [[ ! -e "${required}" ]]; then
        echo "Missing required Dakota payload path: ${required}" >&2
        exit 1
    fi
done

copy_tree /ctx/custom/system_files/etc/fonts/conf.d /etc/fonts/conf.d
copy_tree /ctx/custom/system_files/usr/share/glib-2.0/schemas /usr/share/glib-2.0/schemas
copy_tree /ctx/custom/system_files/usr/share/ublue-os/user-setup.hooks.d /usr/share/ublue-os/user-setup.hooks.d
copy_file /ctx/custom/dakota/etc/dconf/db/distro.d/99-dudley-terminal-keybindings \
    /etc/dconf/db/distro.d/99-dudley-terminal-keybindings
install -D -m 0644 /usr/share/dudley/terminal/ghostty.conf /etc/ghostty/config
cat /ctx/custom/dakota/etc/ghostty/config >> /etc/ghostty/config
copy_executable \
    /ctx/custom/dakota/usr/share/ublue-os/user-setup.hooks.d/18-dudley-docker-engine.sh \
    /usr/share/ublue-os/user-setup.hooks.d/18-dudley-docker-engine.sh
/ctx/build/install-dakota-just.sh \
    /ctx/oci/dsb-common/system_files/shared/usr/share/ublue-os/just \
    /ctx/oci/dsb-common/system_files/dudley/usr/share/ublue-os/just \
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

DUDLEY_STREAM=dakota /ctx/build/18-parity-acceptance.sh
