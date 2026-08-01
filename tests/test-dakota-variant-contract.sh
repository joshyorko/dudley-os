#!/usr/bin/env bash
set -euo pipefail

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
! grep -Eq '10-build\.sh|15-dx\.sh|google-chrome|rpm-ostree' Containerfile.dakota build/10-dakota.sh
if sed -E '/^[[:space:]]*#/d; s/[[:space:]]+#.*$//' Containerfile.dakota build/10-dakota.sh |
    grep -Eq '(^|[[:space:];|&/])(dnf|dnf5)([[:space:]]|$)'; then
    echo 'FAIL: Dakota assembly must not invoke dnf or dnf5' >&2
    exit 1
fi
grep -Fq 'DEFAULT_TAG: "dakota"' .github/workflows/build-dakota.yml
grep -Fq 'CONTAINERFILE=./Containerfile.dakota' .github/workflows/build-dakota.yml
grep -Fq 'ghcr.io/projectbluefin/dakota:stable@sha256:' .github/workflows/build-dakota.yml
grep -Fq 'projectbluefin/actions/bootc-build/sign-and-publish@' .github/workflows/build-dakota.yml
grep -Fq 'type=raw,value=dakota' .github/workflows/build-dakota.yml
grep -Fq 'type=sha' .github/workflows/build-dakota.yml

python3 - <<'PY'
import json
import re
import tomllib
from pathlib import Path

import yaml

workflow = yaml.safe_load(Path('.github/workflows/build-dakota.yml').read_text())
assert workflow['env']['DEFAULT_TAG'] == 'dakota'
dakota_iso_path = Path('iso/dakota.toml')
assert dakota_iso_path.is_file(), 'Dakota must have a dedicated installer configuration'
dakota_iso = tomllib.loads(dakota_iso_path.read_text())
kickstart = dakota_iso['customizations']['installer']['kickstart']['contents']
assert 'ghcr.io/joshyorko/dudley-os:dakota' in kickstart
assert 'ghcr.io/joshyorko/dudley-os:stable' not in kickstart
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
PY

dakota_iso_plan=$(just --dry-run build-dakota-iso 2>&1)
grep -Fq 'CONTAINERFILE=./Containerfile.dakota' <<<"${dakota_iso_plan}"
grep -Fq 'build "dudley-os" "dakota"' <<<"${dakota_iso_plan}"
grep -Fq 'env -u SSH_ASKPASS' <<<"${dakota_iso_plan}"
grep -Fq '_build-bib localhost/dudley-os dakota iso iso/dakota.toml' <<<"${dakota_iso_plan}"

echo 'PASS: Dakota variant assembly and publish contract is present'
