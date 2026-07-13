#!/usr/bin/env bash

set -euo pipefail

promote_bootc_account_file() {
    local source_file=$1
    local target_file=$2
    local temp_dir=$3
    local additions
    local retained

    additions="${temp_dir}/$(basename "${target_file}").additions"
    retained="${temp_dir}/$(basename "${source_file}").retained"

    [[ -f "${source_file}" ]] || return 0
    mkdir -p "$(dirname "${target_file}")"
    touch "${target_file}"

    awk -F: '
        FNR == NR { immutable[$1] = 1; next }
        $1 != "root" && $3 ~ /^[0-9]+$/ && $3 > 0 && $3 < 1000 && !($1 in immutable) { print }
    ' "${target_file}" "${source_file}" >"${additions}"

    [[ -s "${additions}" ]] || return 0

    cat "${additions}" >>"${target_file}"
    awk -F: '
        FNR == NR { moved[$1] = 1; next }
        !($1 in moved) { print }
    ' "${additions}" "${source_file}" >"${retained}"
    cat "${retained}" >"${source_file}"
}

promote_bootc_system_accounts() {
    local root=${1:-/}
    local temp_dir

    root=${root%/}
    temp_dir="$(mktemp -d)"

    promote_bootc_account_file \
        "${root}/etc/passwd" \
        "${root}/usr/lib/passwd" \
        "${temp_dir}"
    promote_bootc_account_file \
        "${root}/etc/group" \
        "${root}/usr/lib/group" \
        "${temp_dir}"

    rm -rf "${temp_dir}"
}
