#!/usr/bin/env bash
set -euo pipefail

source_dir="$1"
destination_dir="$2"

install -d -m 0755 "${destination_dir}"
for hook in \
    12-dudley-desktop-parity.sh \
    15-dudley-bazaar-launcher.sh \
    20-dudley-vscode-extensions.sh; do
    if [[ -f "${source_dir}/${hook}" ]]; then
        install -m 0755 "${source_dir}/${hook}" "${destination_dir}/${hook}"
    fi
done
