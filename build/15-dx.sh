#!/usr/bin/env bash

set -euo pipefail

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
    edk2-ovmf
    flatpak-builder
    git-subtree
    git-svn
    libvirt
    libvirt-nss
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
    virt-manager
    virt-v2v
    virt-viewer
    ydotool
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

dnf5 install -y "${FEDORA_DX_PACKAGES[@]}"

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

systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable libvirtd.socket
systemctl enable dudley-dx-groups.service

for package in "${FEDORA_DX_PACKAGES[@]}" "${DOCKER_PACKAGES[@]}" code; do
    rpm -q "${package}" >/dev/null || {
        echo "Missing Dudley DX package: ${package}" >&2
        exit 1
    }
done

for command in docker podman code virt-manager; do
    command -v "${command}" >/dev/null || {
        echo "Missing Dudley DX command: ${command}" >&2
        exit 1
    }
done

test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall

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
