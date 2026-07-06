#!/usr/bin/env bash
# Test that Dudley keeps Bluefin's Bazaar Flatpak preinstall contract while
# removing only duplicate RPM launcher payload.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="${ROOT_DIR}/build/10-build.sh"

if grep -Eq 'dnf5? +-y +remove +bazaar|dnf5? +remove +-y +bazaar' "${BUILD_SCRIPT}"; then
    echo "FAIL: build must not remove the Bazaar RPM package; it can own the Flatpak preinstall file" >&2
    exit 1
fi

if ! grep -Fq '/usr/share/applications/io.github.kolunmi.Bazaar.desktop' "${BUILD_SCRIPT}"; then
    echo "FAIL: build must remove the stale RPM Bazaar desktop launcher to avoid duplicates" >&2
    exit 1
fi

if ! grep -Fq '/usr/share/metainfo/io.github.kolunmi.Bazaar.metainfo.xml' "${BUILD_SCRIPT}"; then
    echo "FAIL: build must remove stale RPM Bazaar appstream metadata to avoid duplicates" >&2
    exit 1
fi

for required in \
    'mkdir -p /usr/share/flatpak/preinstall.d' \
    'cat >/usr/share/flatpak/preinstall.d/bazaar.preinstall' \
    '[Flatpak Preinstall io.github.kolunmi.Bazaar]' \
    'Branch=stable' \
    'IsRuntime=false'; do
    if ! grep -Fq "${required}" "${BUILD_SCRIPT}"; then
        echo "FAIL: build must preserve Bazaar Flatpak preinstall contract (${required})" >&2
        exit 1
    fi
done

echo "PASS: Bazaar Flatpak stays preinstalled while stale RPM launcher duplicates are removed"
