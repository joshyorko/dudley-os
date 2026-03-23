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
copy_layer "dsb-common dudley" "/ctx/oci/dsb-common/dudley"
copy_layer "local dudley-os product files" "/ctx/custom/system_files"

echo "::endgroup::"

echo "::group:: Wire local Dudley assembly glue"

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just

echo "::endgroup::"

echo "::group:: Install Packages"

# Invoke the shared Dudley installer layered in from dsb-common.
/usr/libexec/dudley/install-vscode-insiders.sh

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
# Example: systemctl mask unwanted-service

echo "::endgroup::"

echo "Custom build complete!"
