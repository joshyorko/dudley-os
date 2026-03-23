#!/usr/bin/env bash
set -euo pipefail

command -v code-insiders >/dev/null 2>&1 || exit 0

extensions_list="/etc/skel/.config/vscode-extensions.list"
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
        --user-data-dir "${user_data_dir}" || \
        echo "Failed to install VS Code Insiders extension: ${extension}" >&2
done < "${extensions_list}"
