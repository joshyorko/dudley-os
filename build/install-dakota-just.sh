#!/usr/bin/env bash
set -euo pipefail

shared_source="$1"
dudley_source="$2"
local_source="$3"
destination="$4"

install -d -m 0755 "${destination}"
rsync -a "${shared_source}/" "${destination}/"
rsync -a "${dudley_source}/" "${destination}/"

if [[ -d "${local_source}" ]]; then
    find "${local_source}" -type f -name '*.just' -print0 \
        | sort -z \
        | xargs -0r cat >> "${destination}/60-custom.just"
fi
