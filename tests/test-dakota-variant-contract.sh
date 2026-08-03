#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

install -d "${TMP_DIR}/shared" "${TMP_DIR}/dudley"
cat > "${TMP_DIR}/shared/60-custom.just" <<'EOF'
import? "60-dudley.just"
EOF
cat > "${TMP_DIR}/dudley/60-dudley.just" <<'EOF'
dudley:
    @echo dudley
EOF

"${ROOT_DIR}/build/install-dakota-just.sh" \
    "${TMP_DIR}/shared" \
    "${TMP_DIR}/dudley" \
    "${ROOT_DIR}/custom/ujust" \
    "${TMP_DIR}/just"

just --justfile "${TMP_DIR}/just/60-custom.just" --list > "${TMP_DIR}/just-list"
grep -Fq 'dudley' "${TMP_DIR}/just-list"
grep -Fq 'dudley-dakota' "${TMP_DIR}/just-list"
if grep -Fq 'configure-podman-docker' "${TMP_DIR}/just-list"; then
    echo 'FAIL: Dakota must not configure Podman as Docker' >&2
    exit 1
fi
grep -Fq 'install-default-apps' "${TMP_DIR}/just-list"

install -d "${TMP_DIR}/ujust-bin"
cat > "${TMP_DIR}/ujust-bin/ujust" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DUDLEY_UJUST_LOG}"
if [[ "$*" == 'bluefin-cli' ]]; then
    printf '%s\n' 'source /usr/share/ublue-os/bling/bling.sh' >> "${HOME}/.zshrc"
    printf '%s\n' '/usr/share/ublue-os/homebrew/cli.Brewfile' >> "${DUDLEY_BREW_LOG}"
fi
EOF
chmod +x "${TMP_DIR}/ujust-bin/ujust"
install -d "${TMP_DIR}/dakota-home"
printf '%s\n' '# Dakota user configuration' > "${TMP_DIR}/dakota-home/.zshrc"
DUDLEY_UJUST_LOG="${TMP_DIR}/ujust.log" \
DUDLEY_BREW_LOG="${TMP_DIR}/brew.log" \
HOME="${TMP_DIR}/dakota-home" \
PATH="${TMP_DIR}/ujust-bin:/usr/bin:/bin" \
    just --justfile "${TMP_DIR}/just/60-custom.just" dudley-dakota
if grep -Fxq 'bluefin-cli' "${TMP_DIR}/ujust.log"; then
    echo 'FAIL: Dakota setup must not invoke Bluefin CLI or terminal bling' >&2
    exit 1
fi
test "$(cat "${TMP_DIR}/ujust.log")" = 'dudley dx'
test "$(cat "${TMP_DIR}/dakota-home/.zshrc")" = '# Dakota user configuration'
test ! -e "${TMP_DIR}/brew.log"
if grep -Fq 'brew unlink podman' "${TMP_DIR}/just/60-custom.just"; then
    echo 'FAIL: Dakota must not mask Podman provenance with a Homebrew unlink workaround' >&2
    exit 1
fi

install -d \
    "${TMP_DIR}/docker-migration-home/.config/environment.d" \
    "${TMP_DIR}/docker-migration-bin"
printf 'DOCKER_HOST=unix:///run/user/1000/podman/podman.sock\n' > \
    "${TMP_DIR}/docker-migration-home/.config/environment.d/60-dudley-podman-docker.conf"
cat > "${TMP_DIR}/docker-migration-bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DUDLEY_SYSTEMCTL_LOG}"
EOF
chmod +x "${TMP_DIR}/docker-migration-bin/systemctl"
HOME="${TMP_DIR}/docker-migration-home" \
DUDLEY_SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log" \
PATH="${TMP_DIR}/docker-migration-bin:/usr/bin:/bin" \
    "${ROOT_DIR}/custom/dakota/usr/share/ublue-os/user-setup.hooks.d/18-dudley-docker-engine.sh"
test ! -e "${TMP_DIR}/docker-migration-home/.config/environment.d/60-dudley-podman-docker.conf"
grep -Fxq -- '--user daemon-reload' "${TMP_DIR}/systemctl.log"
grep -Fxq -- '--user unset-environment DOCKER_HOST' "${TMP_DIR}/systemctl.log"

install -d \
    "${TMP_DIR}/docker-source/usr/local/bin" \
    "${TMP_DIR}/docker-source/usr/local/libexec/docker/cli-plugins"
for command in containerd containerd-shim-runc-v2 ctr docker docker-init docker-proxy dockerd runc; do
    printf '#!/usr/bin/env bash\nprintf "%s-real-docker\\n"\n' "${command}" > \
        "${TMP_DIR}/docker-source/usr/local/bin/${command}"
    chmod +x "${TMP_DIR}/docker-source/usr/local/bin/${command}"
done
for plugin in docker-buildx docker-compose; do
    printf '#!/usr/bin/env bash\nprintf "%s-real-docker\\n"\n' "${plugin}" > \
        "${TMP_DIR}/docker-source/usr/local/libexec/docker/cli-plugins/${plugin}"
    chmod +x "${TMP_DIR}/docker-source/usr/local/libexec/docker/cli-plugins/${plugin}"
done

"${ROOT_DIR}/build/install-dakota-docker.sh" \
    "${TMP_DIR}/docker-source" \
    "${TMP_DIR}/docker-root"

test "$("${TMP_DIR}/docker-root/usr/bin/docker")" = 'docker-real-docker'
test "$("${TMP_DIR}/docker-root/usr/bin/dockerd")" = 'dockerd-real-docker'
test "$("${TMP_DIR}/docker-root/usr/libexec/docker/cli-plugins/docker-compose")" = \
    'docker-compose-real-docker'
test -f "${TMP_DIR}/docker-root/usr/lib/systemd/system/docker.service"
test -f "${TMP_DIR}/docker-root/usr/lib/systemd/system/docker.socket"
test -f "${TMP_DIR}/docker-root/usr/lib/sysusers.d/dudley-docker.conf"
grep -Fq 'ExecStart=/usr/bin/dockerd' \
    "${TMP_DIR}/docker-root/usr/lib/systemd/system/docker.service"
grep -Fq 'SocketGroup=docker' \
    "${TMP_DIR}/docker-root/usr/lib/systemd/system/docker.socket"
grep -Fxq 'g docker - -' \
    "${TMP_DIR}/docker-root/usr/lib/sysusers.d/dudley-docker.conf"
test ! -e "${ROOT_DIR}/custom/dakota/usr/local/bin/docker"
test ! -e "${ROOT_DIR}/custom/dakota/usr/bin/dudley-podman-docker"
grep -Fq 'for command in bootc ujust podman' "${ROOT_DIR}/build/10-dakota.sh"

install -d "${TMP_DIR}/hooks-source" "${TMP_DIR}/hooks-destination"
for hook in \
    12-dudley-desktop-parity.sh \
    15-dudley-bazaar-launcher.sh \
    20-dudley-vscode-extensions.sh; do
    printf '#!/usr/bin/env bash\n' > "${TMP_DIR}/hooks-source/${hook}"
done
printf '#!/usr/bin/env bash\n' > "${TMP_DIR}/hooks-source/99-fedora-only.sh"
"${ROOT_DIR}/build/install-dakota-hooks.sh" \
    "${TMP_DIR}/hooks-source" \
    "${TMP_DIR}/hooks-destination"
test "$(find "${TMP_DIR}/hooks-destination" -type f | wc -l)" -eq 3
test ! -e "${TMP_DIR}/hooks-destination/99-fedora-only.sh"

install -d "${TMP_DIR}/dconf"
cp "${ROOT_DIR}/custom/dakota/etc/dconf/db/distro.d/99-dudley-terminal-keybindings" \
    "${TMP_DIR}/dconf/99-dudley-terminal-keybindings"
dconf compile "${TMP_DIR}/distro-db" "${TMP_DIR}/dconf"
grep -Fq "custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']" \
    "${TMP_DIR}/dconf/99-dudley-terminal-keybindings"
grep -Fq "name='Terminal'" "${TMP_DIR}/dconf/99-dudley-terminal-keybindings"
grep -Fq "command='/usr/bin/ghostty --gtk-single-instance=true'" \
    "${TMP_DIR}/dconf/99-dudley-terminal-keybindings"
grep -Fq "binding='<Primary><Alt>t'" "${TMP_DIR}/dconf/99-dudley-terminal-keybindings"
if grep -Fq '/usr/bin/ptyxis --new-window' "${TMP_DIR}/dconf/99-dudley-terminal-keybindings"; then
    echo 'FAIL: Dakota terminal shortcut must not invoke Ptyxis' >&2
    exit 1
fi
grep -Fq 'copy_file /ctx/custom/dakota/etc/ghostty/config /etc/ghostty/config' build/10-dakota.sh
grep -Fq 'command = /home/linuxbrew/.linuxbrew/bin/zsh' custom/dakota/etc/ghostty/config
grep -Fq 'shell-integration = zsh' custom/dakota/etc/ghostty/config

install -d \
    "${TMP_DIR}/chrome-source/opt/google/chrome" \
    "${TMP_DIR}/chrome-source/usr/share/applications" \
    "${TMP_DIR}/chrome-source/usr/bin"
cat > "${TMP_DIR}/chrome-source/opt/google/chrome/google-chrome" <<'EOF'
#!/usr/bin/env bash
echo native-chrome
EOF
chmod +x "${TMP_DIR}/chrome-source/opt/google/chrome/google-chrome"
cat > "${TMP_DIR}/chrome-source/usr/share/applications/google-chrome.desktop" <<'EOF'
[Desktop Entry]
Exec=/usr/bin/google-chrome-stable %U
Icon=google-chrome
EOF
for size in 16 24 32 48 64 128 256; do
    printf 'chrome-icon-%s\n' "${size}" > \
        "${TMP_DIR}/chrome-source/opt/google/chrome/product_logo_${size}.png"
done
for command in xdg-desktop-menu xdg-icon-resource xdg-mime xdg-settings; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > \
        "${TMP_DIR}/chrome-source/usr/bin/${command}"
    chmod +x "${TMP_DIR}/chrome-source/usr/bin/${command}"
done

install -d "${TMP_DIR}/chrome-bin"
cat > "${TMP_DIR}/chrome-bin/gtk-update-icon-cache" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${DUDLEY_ICON_CACHE_LOG}"
EOF
chmod +x "${TMP_DIR}/chrome-bin/gtk-update-icon-cache"

PATH="${TMP_DIR}/chrome-bin:${PATH}" \
DUDLEY_ICON_CACHE_LOG="${TMP_DIR}/icon-cache.log" \
    "${ROOT_DIR}/build/install-dakota-chrome.sh" \
    "${TMP_DIR}/chrome-source" \
    "${TMP_DIR}/chrome-root"

test "$("${TMP_DIR}/chrome-root/usr/lib/opt/google/chrome/google-chrome")" = \
    'native-chrome'
test "$(readlink "${TMP_DIR}/chrome-root/usr/bin/google-chrome-stable")" = \
    '/opt/google/chrome/google-chrome'
test "$(readlink "${TMP_DIR}/chrome-root/var/opt/google")" = \
    '../../usr/lib/opt/google'
test -f "${TMP_DIR}/chrome-root/usr/share/applications/google-chrome.desktop"
for size in 16 24 32 48 64 128 256; do
    grep -Fxq "chrome-icon-${size}" \
        "${TMP_DIR}/chrome-root/usr/share/icons/hicolor/${size}x${size}/apps/google-chrome.png"
done
for command in xdg-desktop-menu xdg-icon-resource xdg-mime xdg-settings; do
    test -x "${TMP_DIR}/chrome-root/usr/bin/${command}"
done
grep -Fxq -- \
    "-f -t ${TMP_DIR}/chrome-root/usr/share/icons/hicolor" \
    "${TMP_DIR}/icon-cache.log"
test ! -e "${ROOT_DIR}/custom/dakota/etc/flatpak/preinstall.d/dudley-dakota.preinstall"

if [[ ! -x build/10-dakota.sh ]]; then
    echo 'FAIL: Dakota assembly script must be executable in the build context' >&2
    exit 1
fi

grep -Eq '^ARG BASE_IMAGE_REF="ghcr\.io/projectbluefin/dakota:stable@sha256:[a-f0-9]{64}"$' Containerfile.dakota
grep -Fq '/ctx/build/10-dakota.sh' Containerfile.dakota
grep -Fq 'RUN bootc container lint' Containerfile.dakota
grep -Fxq 'ARG VSCODE_REFRESH_TOKEN' Containerfile.dakota
grep -Fq 'copy_tree /ctx/oci/dsb-common/dudley/etc/flatpak/preinstall.d /etc/flatpak/preinstall.d' build/10-dakota.sh
grep -Fq 'copy_file /ctx/oci/dsb-common/dudley/etc/skel/.config/Code/User/settings.json /etc/skel/.config/Code/User/settings.json' build/10-dakota.sh
grep -Fq 'copy_file "/ctx/oci/dsb-common/dudley/etc/skel/.config/Code - Insiders/User/settings.json" "/etc/skel/.config/Code - Insiders/User/settings.json"' build/10-dakota.sh
grep -Fq 'copy_executable /ctx/oci/dsb-common/dudley/usr/libexec/dudley/configure-homebrew-no-ask /usr/libexec/dudley/configure-homebrew-no-ask' build/10-dakota.sh
# shellcheck disable=SC2251
! grep -Fq '/ctx/oci/dsb-common/dudley/usr/share/flatpak/preinstall.d' build/10-dakota.sh
# shellcheck disable=SC2251
! grep -Fq '/ctx/oci/dsb-common/dudley/usr/share/ublue-os/update.just' build/10-dakota.sh
# The Dakota variant accepts only these Dudley files; bulk copies would let
# Fedora/Bazaar-only payload leak into the distroless image as dsb-common grows.
if grep -Fq 'copy_tree /ctx/oci/dsb-common/dudley/etc/xdg/autostart /etc/xdg/autostart' build/10-dakota.sh ||
    grep -Fq 'copy_tree /ctx/oci/dsb-common/dudley/usr/bin /usr/bin' build/10-dakota.sh; then
    echo 'FAIL: Dakota assembly must not bulk-copy Dudley autostart or executable payloads' >&2
    exit 1
fi
grep -Fq 'copy_file /ctx/oci/dsb-common/dudley/etc/xdg/autostart/dudley-random-wallpaper.desktop /etc/xdg/autostart/dudley-random-wallpaper.desktop' build/10-dakota.sh
for command in dudley-build-info dudley-random-wallpaper dudley-theme dudley-wallpaper; do
    grep -Fq "copy_executable /ctx/oci/dsb-common/dudley/usr/bin/${command} /usr/bin/${command}" build/10-dakota.sh
done
# shellcheck disable=SC2251
! grep -Eq '10-build\.sh|15-dx\.sh|rpm-ostree' Containerfile.dakota build/10-dakota.sh
if sed -E '/^[[:space:]]*#/d; s/[[:space:]]+#.*$//' build/10-dakota.sh |
    grep -Eq '(^|[[:space:];|&/])(dnf|dnf5)([[:space:]]|$)'; then
    echo 'FAIL: the final Dakota image assembly must not invoke dnf or dnf5' >&2
    exit 1
fi
grep -Eq '^ARG CHROME_BUILDER_REF="registry\.fedoraproject\.org/fedora:45@sha256:[a-f0-9]{64}"$' Containerfile.dakota
grep -Fq 'rpmkeys --checksig /tmp/google-chrome.rpm' Containerfile.dakota
grep -Fq 'COPY --from=google-chrome /chrome-root /oci/google-chrome' Containerfile.dakota
grep -Fq 'CONTAINERFILE=./Containerfile.dakota' .github/workflows/build-dakota.yml
grep -Fq 'ghcr.io/projectbluefin/dakota:stable@sha256:' .github/workflows/build-dakota.yml
grep -Fq 'ghcr.io/projectbluefin/dakota-nvidia:stable@sha256:' .github/workflows/build-dakota.yml
grep -Fq 'projectbluefin/actions/bootc-build/sign-and-publish@' .github/workflows/build-dakota.yml
# shellcheck disable=SC2016
grep -Fq 'type=raw,value=${{ matrix.tag }}' .github/workflows/build-dakota.yml
grep -Fq 'type=sha' .github/workflows/build-dakota.yml

python3 - <<'PY'
import json
import re
from pathlib import Path

import yaml

workflow = yaml.safe_load(Path('.github/workflows/build-dakota.yml').read_text())
variants = workflow['jobs']['build_push_dakota']['strategy']['matrix']['include']
assert {(item['tag'], item['base_image_ref'].split('@', 1)[0]) for item in variants} == {
    ('dakota', 'ghcr.io/projectbluefin/dakota:stable'),
    ('dakota-nvidia', 'ghcr.io/projectbluefin/dakota-nvidia:stable'),
}
assert not Path('iso/dakota.toml').exists(), (
    'Dakota live-media assembly belongs to joshyorko/dudley-iso'
)
cards_workflow = yaml.safe_load(Path('.github/workflows/validate-cards.yml').read_text())
cards_steps = cards_workflow['jobs']['validate']['steps']
assert cards_steps[0]['uses'] == 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
assert cards_steps[1]['uses'] == 'actions/setup-node@820762786026740c76f36085b0efc47a31fe5020'
renovate = json.loads(Path('.github/renovate.json5').read_text())
assert any(
    any(re.search(pattern.strip('/'), 'Containerfile.dakota') for pattern in manager.get('managerFilePatterns', []))
    and any(
        'ARG BASE_IMAGE_REF=' in match
        and r'(?<depName>ghcr\.io\/projectbluefin\/dakota)' in match
        for match in manager.get('matchStrings', [])
    )
    for manager in renovate['customManagers']
)
assert any(
    any('build-dakota' in pattern for pattern in manager.get('managerFilePatterns', []))
    and any('dakota(?:-nvidia)?' in match for match in manager.get('matchStrings', []))
    for manager in renovate['customManagers']
), 'Renovate must pin both Dakota workflow base images'
PY

if just --list 2>&1 | grep -Fq 'build-dakota-iso'; then
    echo 'FAIL: Dakota ISO assembly belongs to joshyorko/dudley-iso' >&2
    exit 1
fi

echo 'PASS: Dakota variant assembly and publish contract is present'
