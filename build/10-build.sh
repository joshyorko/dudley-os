#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -eoux pipefail for strict error handling and debugging.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

echo "::group:: Copy Shared Files from dsb-common"

# Copy shared organisation-wide files from the dsb-common OCI layer.
# These are applied first so product-specific customisations below can
# override anything they need to.
if [[ -d /ctx/oci/dsb-common ]]; then
    # Just files
    if compgen -G "/ctx/oci/dsb-common/usr/share/ublue-os/just/*" > /dev/null 2>&1; then
        mkdir -p /usr/share/ublue-os/just/
        cp -r /ctx/oci/dsb-common/usr/share/ublue-os/just/* /usr/share/ublue-os/just/
    fi
    # Brewfiles
    if compgen -G "/ctx/oci/dsb-common/usr/share/ublue-os/homebrew/*.Brewfile" > /dev/null 2>&1; then
        mkdir -p /usr/share/ublue-os/homebrew/
        cp /ctx/oci/dsb-common/usr/share/ublue-os/homebrew/*.Brewfile /usr/share/ublue-os/homebrew/
    fi
    # Flatpak preinstall files
    if compgen -G "/ctx/oci/dsb-common/etc/flatpak/preinstall.d/*.preinstall" > /dev/null 2>&1; then
        mkdir -p /etc/flatpak/preinstall.d/
        cp /ctx/oci/dsb-common/etc/flatpak/preinstall.d/*.preinstall /etc/flatpak/preinstall.d/
    fi
    # Any other top-level system_files content
    if [[ -d /ctx/oci/dsb-common/etc ]] || [[ -d /ctx/oci/dsb-common/usr ]]; then
        rsync -a --exclude='usr/share/ublue-os/just' \
                 --exclude='usr/share/ublue-os/homebrew' \
                 --exclude='etc/flatpak/preinstall.d' \
                 /ctx/oci/dsb-common/ / || true
    fi
fi

echo "::endgroup::"

echo "::group:: Copy Bluefin Config from Common"

# Copy just files from @projectbluefin/common (includes 00-entry.just which imports 60-custom.just)
mkdir -p /usr/share/ublue-os/just/
shopt -s nullglob
cp -r /ctx/oci/common/bluefin/usr/share/ublue-os/just/* /usr/share/ublue-os/just/
shopt -u nullglob

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /etc/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /etc/flatpak/preinstall.d/

echo "::endgroup::"

echo "::group:: Install Packages"

# Install packages using dnf5
# Example: dnf5 install -y tmux

# Example using COPR with isolated pattern:
# copr_install_isolated "ublue-os/staging" package-name

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
# Example: systemctl mask unwanted-service

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Custom build complete!"
