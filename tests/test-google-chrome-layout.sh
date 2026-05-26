#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=build/google-chrome.sh
source "${ROOT_DIR}/build/google-chrome.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

assert_symlink_target() {
    local path="$1"
    local expected="$2"
    local actual

    if [[ ! -L "${path}" ]]; then
        echo "FAIL: ${path} is not a symlink" >&2
        exit 1
    fi

    actual="$(readlink "${path}")"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "FAIL: ${path} expected target ${expected}, got ${actual}" >&2
        exit 1
    fi
}

symlinked_root="${TEST_DIR}/symlinked-opt"
mkdir -p "${symlinked_root}/var/opt" "${symlinked_root}/usr/lib"
ln -s var/opt "${symlinked_root}/opt"
mkdir -p "${symlinked_root}/var/opt/google"

prepare_google_chrome_opt_layout "${symlinked_root}"

if [[ ! -d "${symlinked_root}/usr/lib/opt/google" ]]; then
    echo "FAIL: immutable Chrome target was not created" >&2
    exit 1
fi
assert_symlink_target "${symlinked_root}/var/opt/google" "../../usr/lib/opt/google"
if ! grep -Fxq 'L /var/opt/google - - - - ../../usr/lib/opt/google' "${symlinked_root}/usr/lib/tmpfiles.d/dudley-google-chrome.conf"; then
    echo "FAIL: tmpfiles rule was not written" >&2
    exit 1
fi

plain_root="${TEST_DIR}/plain-opt"
mkdir -p "${plain_root}/opt/google" "${plain_root}/usr/lib"

prepare_google_chrome_opt_layout "${plain_root}"

if [[ -e "${plain_root}/opt/google" || -L "${plain_root}/opt/google" ]]; then
    echo "FAIL: stale /opt/google was not removed for immutable /opt layout" >&2
    exit 1
fi

repo_root="${TEST_DIR}/repo-disable"
mkdir -p "${repo_root}/etc/yum.repos.d"
cat >"${repo_root}/etc/yum.repos.d/google-chrome.repo" <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

disable_google_chrome_repo "${repo_root}"

if grep -q '^enabled=1$' "${repo_root}/etc/yum.repos.d/google-chrome.repo"; then
    echo "FAIL: Google Chrome repo was left enabled after build-time install" >&2
    exit 1
fi
if ! grep -q '^enabled=0$' "${repo_root}/etc/yum.repos.d/google-chrome.repo"; then
    echo "FAIL: Google Chrome repo was not disabled" >&2
    exit 1
fi

cleanup_root="${TEST_DIR}/install-cleanup"
mkdir -p "${cleanup_root}/run/dnf" "${cleanup_root}/var/lib/dnf"
touch "${cleanup_root}/run/dnf/state" "${cleanup_root}/var/lib/dnf/system-repo.lock"

cleanup_google_chrome_install_state "${cleanup_root}"

if [[ -e "${cleanup_root}/run/dnf" ]]; then
    echo "FAIL: transient /run/dnf state was not removed" >&2
    exit 1
fi
if [[ -e "${cleanup_root}/var/lib/dnf/system-repo.lock" ]]; then
    echo "FAIL: transient DNF system-repo.lock was not removed" >&2
    exit 1
fi

echo "PASS: Google Chrome install layout and cleanup are prepared correctly"
