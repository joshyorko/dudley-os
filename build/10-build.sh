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

copy_layer() {
    local layer_name=$1
    local layer_path=$2

    if [[ ! -d "$layer_path" ]]; then
        echo "Skipping ${layer_name}: ${layer_path} not present"
        return 0
    fi

    echo "Applying ${layer_name} from ${layer_path}"
    rsync -a "${layer_path}/" /
}

echo "::group:: Apply OCI and product layers"

copy_layer "dsb-common shared" "/ctx/oci/dsb-common/shared"
copy_layer "projectbluefin/common shared" "/ctx/oci/common/shared"
copy_layer "projectbluefin/common bluefin" "/ctx/oci/common/bluefin"
copy_layer "dsb-common dudley" "/ctx/oci/dsb-common/dudley"
copy_layer "local dudley-os product files" "/ctx/custom/system_files"

echo "::endgroup::"

echo "::group:: Copy local Dudley overlays"

# Enable nullglob for local overlay copy operations
shopt -s nullglob

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp -f /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /etc/flatpak/preinstall.d/
cp -f /ctx/custom/flatpaks/*.preinstall /etc/flatpak/preinstall.d/

echo "::endgroup::"

echo "::group:: Install Packages"

# Dudley product-specific build behavior retained from the legacy monolith:
# install VS Code Insiders so the first-login extension hook has a product
# editor target without moving the logic into dsb-common.
if ! rpm -q code-insiders &>/dev/null; then
    readonly VSCODE_INSIDERS_RPM="/tmp/code-insiders-latest.rpm"
    curl -fsSL -o "${VSCODE_INSIDERS_RPM}" \
        "https://update.code.visualstudio.com/latest/linux-rpm-x64/insider"
    dnf5 install -y --allowerasing "${VSCODE_INSIDERS_RPM}"
    rm -f "${VSCODE_INSIDERS_RPM}"
fi

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
# Example: systemctl mask unwanted-service

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Custom build complete!"
