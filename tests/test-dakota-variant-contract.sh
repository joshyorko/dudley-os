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
if grep -Fq 'configure-ghostty-zsh' "${TMP_DIR}/just-list"; then
    echo 'FAIL: Dakota must preserve its existing Ghostty/Zsh setup' >&2
    exit 1
fi
grep -Fq 'install-default-apps' "${TMP_DIR}/just-list"

install -d "${TMP_DIR}/ujust-bin"
cat > "${TMP_DIR}/ujust-bin/ujust" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DUDLEY_UJUST_LOG}"
EOF
chmod +x "${TMP_DIR}/ujust-bin/ujust"
DUDLEY_UJUST_LOG="${TMP_DIR}/ujust.log" \
PATH="${TMP_DIR}/ujust-bin:/usr/bin:/bin" \
    just --justfile "${TMP_DIR}/just/60-custom.just" dudley-dakota
grep -Fxq 'bluefin-cli' "${TMP_DIR}/ujust.log"
grep -Fxq 'dudley dx' "${TMP_DIR}/ujust.log"

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
grep -Fq "command='/usr/bin/ghostty --gtk-single-instance=true'" \
    "${TMP_DIR}/dconf/99-dudley-terminal-keybindings"

install -d \
    "${TMP_DIR}/chrome-source/opt/google/chrome" \
    "${TMP_DIR}/chrome-source/usr/share/applications" \
    "${TMP_DIR}/chrome-source/usr/share/icons/hicolor/256x256/apps" \
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
printf 'chrome-icon\n' > \
    "${TMP_DIR}/chrome-source/usr/share/icons/hicolor/256x256/apps/google-chrome.png"
for command in xdg-desktop-menu xdg-icon-resource xdg-mime xdg-settings; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > \
        "${TMP_DIR}/chrome-source/usr/bin/${command}"
    chmod +x "${TMP_DIR}/chrome-source/usr/bin/${command}"
done

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
test -f "${TMP_DIR}/chrome-root/usr/share/icons/hicolor/256x256/apps/google-chrome.png"
for command in xdg-desktop-menu xdg-icon-resource xdg-mime xdg-settings; do
    test -x "${TMP_DIR}/chrome-root/usr/bin/${command}"
done
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
