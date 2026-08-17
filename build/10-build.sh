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

echo "::group:: Compile desktop defaults"

if command -v dconf >/dev/null 2>&1; then
    dconf update || echo "WARNING: dconf update failed"
else
    echo "WARNING: dconf command not found, skipping dconf database update"
fi

if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas /usr/share/glib-2.0/schemas
else
    echo "WARNING: glib-compile-schemas command not found, skipping GLib schema compilation"
fi

echo "::endgroup::"

echo "::group:: Install Packages"

# Google Chrome is baked into the final product image. The repo definition is
# supplied by dsb-common so all Dudley consumers use the same RPM source.
/ctx/build/google-chrome.sh

# Bluefin used to ship a fallback Bazaar RPM before Bazaar became a system
# Flatpak preinstall. If an inherited base still has that RPM, do not remove the
# package: the RPM can own /usr/share/flatpak/preinstall.d/bazaar.preinstall,
# and removing it causes Bazaar to disappear on upgrades. Remove only the stale
# RPM launcher/appstream metadata so GNOME does not show a duplicate beside the
# Flatpak launcher.
rm -f \
    /usr/share/applications/io.github.kolunmi.Bazaar.desktop \
    /usr/share/metainfo/io.github.kolunmi.Bazaar.metainfo.xml \
    /usr/share/appdata/io.github.kolunmi.Bazaar.appdata.xml

# Keep Bluefin's Flatpak preinstall contract explicit for inherited bases and
# Nvidia variants. Removing this file makes flatpak-preinstall uninstall Bazaar
# from user systems.
mkdir -p /usr/share/flatpak/preinstall.d
cat >/usr/share/flatpak/preinstall.d/bazaar.preinstall <<'EOF'
# NEVER REMOVE THIS FILE
# THIS WILL REMOVE BAZAAR FROM EVERYONES SYSTEMS IF WE REMOVE THIS

[Flatpak Preinstall io.github.kolunmi.Bazaar]
Branch=stable
IsRuntime=false
EOF

# Project Bluefin no longer publishes a separate DX image. Restore Dudley's
# established DX package, service, group, virtualization, and container
# contract explicitly on top of the canonical Project Bluefin base.
/ctx/build/15-dx.sh

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
# Example: systemctl mask unwanted-service

echo "::endgroup::"

echo "::group:: Dudley final metadata"

/ctx/build/20-final-metadata.sh

DUDLEY_STREAM="${DUDLEY_STREAM:-stable}" /ctx/build/18-parity-acceptance.sh

echo "::endgroup::"

echo "Custom build complete!"
