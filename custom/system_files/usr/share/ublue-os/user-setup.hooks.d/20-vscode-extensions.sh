#!/usr/bin/env bash
set -euo pipefail

hook_version="2026-03-23"
if [[ -r /usr/lib/ublue/setup-services/libsetup.sh ]]; then
    # shellcheck source=/dev/null
    source /usr/lib/ublue/setup-services/libsetup.sh
    if [[ "$(version-script vscode-extensions "${hook_version}")" == "skip" ]]; then
        exit 0
    fi
fi

# The Dudley extension payload is expected to be layered in by dsb-common.
command -v code-insiders >/dev/null 2>&1 || exit 0

extensions_list="/usr/share/ublue-os/vscode-extensions.list"
[[ -f "${extensions_list}" ]] || exit 0

mkdir -p "${HOME}/.config"
user_data_dir="${HOME}/.config/Code - Insiders"
mkdir -p "${user_data_dir}"

while IFS= read -r extension || [[ -n "${extension}" ]]; do
    [[ -z "${extension}" || "${extension}" =~ ^# ]] && continue

    extension="$(echo "${extension}" | xargs)"
    [[ -n "${extension}" ]] || continue

    code-insiders \
        --install-extension "${extension}" \
        --force \
        --user-data-dir "${user_data_dir}" \
        --no-sandbox || \
        echo "Failed to install VS Code Insiders extension: ${extension}" >&2
done < "${extensions_list}"
