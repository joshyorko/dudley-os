#!/usr/bin/env bash

set -euo pipefail

root_path() {
    local root="${1:-/}"
    local path="$2"

    if [[ "${root}" == "/" ]]; then
        printf '%s\n' "${path}"
    else
        printf '%s/%s\n' "${root%/}" "${path#/}"
    fi
}

prepare_google_chrome_opt_layout() {
    local root="${1:-/}"
    local opt_path
    local opt_google_path
    local var_opt_path
    local var_opt_google_path
    local immutable_google_path
    local tmpfiles_dir

    opt_path="$(root_path "${root}" "/opt")"
    opt_google_path="$(root_path "${root}" "/opt/google")"
    var_opt_path="$(root_path "${root}" "/var/opt")"
    var_opt_google_path="$(root_path "${root}" "/var/opt/google")"
    immutable_google_path="$(root_path "${root}" "/usr/lib/opt/google")"
    tmpfiles_dir="$(root_path "${root}" "/usr/lib/tmpfiles.d")"

    if [[ -L "${opt_path}" ]]; then
        echo "[dudley-google-chrome] Preparing /opt/google layout for symlinked /opt"
        mkdir -p "${var_opt_path}" "${immutable_google_path}"

        if [[ -e "${var_opt_google_path}" && ! -L "${var_opt_google_path}" ]]; then
            echo "[dudley-google-chrome] Removing pre-existing /var/opt/google"
            rm -rf "${var_opt_google_path}"
        fi

        ln -snf ../../usr/lib/opt/google "${var_opt_google_path}"
        mkdir -p "${tmpfiles_dir}"
        printf 'L /var/opt/google - - - - ../../usr/lib/opt/google\n' > "${tmpfiles_dir}/dudley-google-chrome.conf"
    elif [[ -e "${opt_google_path}" || -L "${opt_google_path}" ]]; then
        echo "[dudley-google-chrome] Removing pre-existing /opt/google"
        rm -rf "${opt_google_path}"
    fi
}

disable_google_chrome_repo() {
    local root="${1:-/}"
    local repo_path

    repo_path="$(root_path "${root}" "/etc/yum.repos.d/google-chrome.repo")"

    if [[ -f "${repo_path}" ]]; then
        echo "[dudley-google-chrome] Disabling Google Chrome repository after build-time install"
        sed -i -E 's/^[[:space:]]*enabled[[:space:]]*=.*/enabled=0/' "${repo_path}"
    fi
}

cleanup_google_chrome_install_state() {
    local root="${1:-/}"

    rm -rf "$(root_path "${root}" "/run/dnf")"
    rm -f "$(root_path "${root}" "/var/lib/dnf/system-repo.lock")"
}

install_google_chrome() {
    if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
        echo "[dudley-google-chrome] Missing /etc/yum.repos.d/google-chrome.repo from dsb-common" >&2
        exit 1
    fi

    prepare_google_chrome_opt_layout "/"

    if command -v dnf5 >/dev/null 2>&1; then
        dnf5 install -y google-chrome-stable
    else
        dnf install -y google-chrome-stable
    fi

    disable_google_chrome_repo "/"
    cleanup_google_chrome_install_state "/"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    install_google_chrome "$@"
fi
