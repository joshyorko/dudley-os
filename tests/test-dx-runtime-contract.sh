#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSEMBLY="${ROOT_DIR}/build/10-build.sh"
INSTALLER="${ROOT_DIR}/build/15-dx.sh"
GROUP_HELPER="${ROOT_DIR}/custom/system_files/usr/libexec/dudley-dx-groups"
GROUP_SERVICE="${ROOT_DIR}/custom/system_files/usr/lib/systemd/system/dudley-dx-groups.service"
TERMINAL_DEFAULTS="${ROOT_DIR}/custom/system_files/usr/share/glib-2.0/schemas/zz1-dudley-terminal.gschema.override"

for required_file in "${INSTALLER}" "${GROUP_HELPER}" "${GROUP_SERVICE}"; do
    if [[ ! -f "${required_file}" ]]; then
        echo "FAIL: missing Dudley DX contract file ${required_file#"${ROOT_DIR}/"}" >&2
        exit 1
    fi
done

if ! grep -Fq '/ctx/build/15-dx.sh' "${ASSEMBLY}"; then
    echo "FAIL: final image assembly must install the Dudley DX layer" >&2
    exit 1
fi

if grep -Eq '(^|[[:space:]])dnf([[:space:]]|$)' "${INSTALLER}"; then
    echo "FAIL: Dudley DX installation must use dnf5 exclusively" >&2
    exit 1
fi

required_packages=(
    android-tools
    bpftrace
    cockpit-machines
    containerd.io
    docker-buildx-plugin
    docker-ce
    docker-ce-cli
    docker-ce-rootless-extras
    docker-compose-plugin
    flatpak-builder
    jetbrains-mono-fonts-all
    libvirt
    podman-compose
    podman-machine
    qemu
    qemu-user-static
    rocm-hip
    rocm-opencl
    virt-manager
    code
)

for package in "${required_packages[@]}"; do
    if ! grep -Fq "${package}" "${INSTALLER}"; then
        echo "FAIL: Dudley DX installer must restore ${package}" >&2
        exit 1
    fi
done

if [[ ! -f "${TERMINAL_DEFAULTS}" ]]; then
    echo "FAIL: missing Dudley terminal defaults" >&2
    exit 1
fi

for required in \
    'font-name="Adwaita Sans 12"' \
    'monospace-font-name="JetBrains Mono 16"'; do
    if ! grep -Fq "${required}" "${TERMINAL_DEFAULTS}"; then
        echo "FAIL: Dudley terminal defaults are missing ${required}" >&2
        exit 1
    fi
done

for package in 7zip 7zip-standalone; do
    if ! grep -Eq "^[[:space:]]+${package}$" "${INSTALLER}"; then
        echo "FAIL: Dudley DX installer must use the Fedora archive package ${package}" >&2
        exit 1
    fi
done

if grep -Eq '^[[:space:]]+p7zip(-plugins)?$' "${INSTALLER}"; then
    echo "FAIL: Dudley DX installer must not validate obsolete p7zip package aliases" >&2
    exit 1
fi

# shellcheck disable=SC2016
for required in \
    'source /ctx/build/copr-helpers.sh' \
    'copr_install_isolated "che/nerd-fonts" nerd-fonts' \
    'rpm -q nerd-fonts' \
    'https://download.docker.com/linux/fedora/docker-ce.repo' \
    'https://packages.microsoft.com/yumrepos/vscode' \
    'systemctl enable docker.socket' \
    'systemctl enable podman.socket' \
    'systemctl enable dudley-dx-groups.service' \
    'rpm -q "${package}"' \
    'command -v nvidia-smi' \
    'command -v nvidia-settings' \
    'command -v nvidia-ctk' \
    'command -v nvidia-cdi-hook' \
    'command -v nvidia-container-runtime' \
    '/etc/systemd/system/nvidia-cdi-refresh.path' \
    '/etc/systemd/system/nvidia-cdi-refresh.service' \
    '/usr/bin/ujust' \
    '/usr/share/ublue-os/just/default.just' \
    '/usr/share/ublue-os/homebrew/cli.Brewfile' \
    '/usr/lib/systemd/user/bluefin-dynamic-wallpaper.service' \
    '/usr/lib/systemd/user/io.github.kolunmi.Bazaar.service' \
    '/usr/share/flatpak/preinstall.d/bazaar.preinstall'; do
    if ! grep -Fq "${required}" "${INSTALLER}"; then
        echo "FAIL: Dudley DX installer is missing runtime validation: ${required}" >&2
        exit 1
    fi
done

for obsolete in \
    'command -v nvidia-container-cli' \
    '/etc/cdi/nvidia.yaml'; do
    if grep -Fq "${obsolete}" "${INSTALLER}"; then
        echo "FAIL: Dudley DX installer must not require the obsolete NVIDIA contract: ${obsolete}" >&2
        exit 1
    fi
done

for repo_file in docker-ce.repo vscode.repo; do
    if ! grep -Fq "rm -f /etc/yum.repos.d/${repo_file}" "${INSTALLER}"; then
        echo "FAIL: Dudley DX installer must remove ${repo_file} after installation" >&2
        exit 1
    fi
done

for group in docker libvirt; do
    if ! grep -Fq "ensure_group ${group}" "${GROUP_HELPER}"; then
        echo "FAIL: Dudley DX group helper must create ${group}" >&2
        exit 1
    fi
done

# shellcheck disable=SC2016
if ! grep -Fq 'usermod -aG "${supplementary_groups}" "${user}"' "${GROUP_HELPER}"; then
    echo "FAIL: Dudley DX group helper must enroll wheel users" >&2
    exit 1
fi

if ! grep -Fq 'ExecStart=/usr/libexec/dudley-dx-groups' "${GROUP_SERVICE}"; then
    echo "FAIL: Dudley DX group service must run the group helper" >&2
    exit 1
fi

echo "PASS: Project Bluefin receives Dudley's complete DX runtime contract"
