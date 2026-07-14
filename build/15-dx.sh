#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source /ctx/build/bootc-accounts.sh
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Restore Dudley DX runtime"

FEDORA_DX_PACKAGES=(
    android-tools
    bcc
    bpftop
    bpftrace
    cascadia-code-fonts
    cockpit-bridge
    cockpit-machines
    cockpit-networkmanager
    cockpit-ostree
    cockpit-podman
    cockpit-selinux
    cockpit-storaged
    cockpit-system
    container-selinux
    dbus-x11
    edk2-ovmf
    flatpak-builder
    git-subtree
    git-svn
    incus
    incus-agent
    iotop-c
    jetbrains-mono-fonts-all
    libvirt
    libvirt-nss
    lxc
    nicstat
    numactl
    osbuild-selinux
    7zip
    7zip-standalone
    podman-compose
    podman-machine
    podman-tui
    qemu
    qemu-char-spice
    qemu-device-display-virtio-gpu
    qemu-device-display-virtio-vga
    qemu-device-usb-redirect
    qemu-img
    qemu-system-x86-core
    qemu-user-binfmt
    qemu-user-static
    sysprof
    tiptop
    trace-cmd
    udica
    util-linux-script
    virt-manager
    virt-v2v
    virt-viewer
    wtype
    ydotool
)

# Package providers differ between the standard and Nvidia base repositories.
# Install the capability and validate the stable command instead of requiring
# one provider RPM name.
FEDORA_DX_CAPABILITIES=(
    genisoimage
)

DOCKER_PACKAGES=(
    containerd.io
    docker-buildx-plugin
    docker-ce
    docker-ce-cli
    docker-ce-rootless-extras
    docker-compose-plugin
    docker-model-plugin
)

AMD_DX_PACKAGES=(
    rocm-hip
    rocm-opencl
    rocm-smi
    rocminfo
)

cleanup_third_party_repos() {
    rm -f /etc/yum.repos.d/docker-ce.repo
    rm -f /etc/yum.repos.d/vscode.repo
}

trap cleanup_third_party_repos EXIT

dnf5 install -y "${FEDORA_DX_PACKAGES[@]}" "${FEDORA_DX_CAPABILITIES[@]}"
copr_install_isolated "che/nerd-fonts" nerd-fonts

if ! command -v nvidia-smi >/dev/null 2>&1; then
    dnf5 install -y "${AMD_DX_PACKAGES[@]}"
fi

dnf5 config-manager addrepo \
    --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sed -i -E 's/^[[:space:]]*enabled[[:space:]]*=.*/enabled=0/' \
    /etc/yum.repos.d/docker-ce.repo
dnf5 install -y --enablerepo=docker-ce-stable "${DOCKER_PACKAGES[@]}"

tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=0
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
dnf5 install -y --enablerepo=code code

cleanup_third_party_repos
trap - EXIT

# Project Bluefin's non-DX base does not define the plugdev group expected by
# inherited U2F and keyboard udev rules.
getent group plugdev >/dev/null || groupadd --system plugdev

# RPMs installed on top of an already-finalized bootc base add service accounts
# under /etc. Promote them to the immutable account database so upgrades retain
# the host's /etc while still resolving qemu, libvirt, Docker, and related users.
promote_bootc_system_accounts /

systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable libvirtd.socket
systemctl enable libvirt-workaround.service
systemctl enable dudley-dx-groups.service

fc-cache -f
fc-match -f '%{family}\n' monospace | grep -Fq 'JetBrains Mono' || {
    echo "Dudley generic monospace font did not resolve to JetBrains Mono" >&2
    exit 1
}

for package in "${FEDORA_DX_PACKAGES[@]}" "${DOCKER_PACKAGES[@]}" code; do
    rpm -q "${package}" >/dev/null || {
        echo "Missing Dudley DX package: ${package}" >&2
        exit 1
    }
done

rpm -q nerd-fonts >/dev/null || {
    echo "Missing Dudley DX package: nerd-fonts" >&2
    exit 1
}

for command in docker podman code incus mkisofs virt-manager; do
    command -v "${command}" >/dev/null || {
        echo "Missing Dudley DX command: ${command}" >&2
        exit 1
    }
done

for path in \
    /usr/bin/ujust \
    /usr/share/ublue-os/just/default.just \
    /usr/share/ublue-os/homebrew/cli.Brewfile \
    /usr/lib/systemd/user/bluefin-dynamic-wallpaper.service \
    /usr/lib/systemd/user/io.github.kolunmi.Bazaar.service \
    /etc/umotd/config.json \
    /usr/share/flatpak/preinstall.d/bazaar.preinstall; do
    test -e "${path}" || {
        echo "Missing Project Bluefin runtime contract: ${path}" >&2
        exit 1
    }
done

for required_link in \
    https://issues.projectbluefin.io/ \
    https://ask.projectbluefin.io/ \
    https://docs.projectbluefin.io/; do
    grep -Fq "${required_link}" /etc/umotd/config.json || {
        echo "Missing Project Bluefin umotd link: ${required_link}" >&2
        exit 1
    }
done

if command -v nvidia-smi >/dev/null 2>&1; then
    command -v nvidia-smi >/dev/null
    command -v nvidia-settings >/dev/null
    command -v nvidia-ctk >/dev/null
    command -v nvidia-cdi-hook >/dev/null
    command -v nvidia-container-runtime >/dev/null
    test -f /etc/nvidia-container-runtime/config.toml
    test -f /etc/systemd/system/nvidia-cdi-refresh.path
    test -f /etc/systemd/system/nvidia-cdi-refresh.service
    find /usr/lib/modules -type f -name 'nvidia.ko*' -print -quit | grep -q .
else
    for package in "${AMD_DX_PACKAGES[@]}"; do
        rpm -q "${package}" >/dev/null || {
            echo "Missing Dudley AMD DX package: ${package}" >&2
            exit 1
        }
    done
fi

echo "::endgroup::"
