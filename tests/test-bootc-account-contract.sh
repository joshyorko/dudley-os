#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT_DIR}/build/bootc-accounts.sh"
INSTALLER="${ROOT_DIR}/build/15-dx.sh"

if [[ ! -f "${HELPER}" ]]; then
    echo "FAIL: missing bootc system-account promotion helper" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${HELPER}"

test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
mkdir -p "${test_root}/etc" "${test_root}/usr/lib"

cat >"${test_root}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
qemu:x:107:107:qemu user:/:/usr/sbin/nologin
libvirtdbus:x:951:951:Libvirt D-Bus bridge:/:/usr/sbin/nologin
kdlocpanda:x:1000:1000:Josh:/var/home/kdlocpanda:/bin/zsh
EOF

cat >"${test_root}/usr/lib/passwd" <<'EOF'
bin:x:1:1:bin:/bin:/usr/sbin/nologin
EOF

cat >"${test_root}/etc/group" <<'EOF'
root:x:0:
qemu:x:107:
libvirt:x:952:
docker:x:950:
kdlocpanda:x:1000:
EOF

cat >"${test_root}/usr/lib/group" <<'EOF'
bin:x:1:
EOF

promote_bootc_system_accounts "${test_root}"
promote_bootc_system_accounts "${test_root}"

for account in qemu libvirtdbus; do
    if [[ "$(grep -c "^${account}:" "${test_root}/usr/lib/passwd")" -ne 1 ]]; then
        echo "FAIL: ${account} must be promoted exactly once to /usr/lib/passwd" >&2
        exit 1
    fi
    if grep -q "^${account}:" "${test_root}/etc/passwd"; then
        echo "FAIL: ${account} must not remain in /etc/passwd" >&2
        exit 1
    fi
done

for group in qemu libvirt docker; do
    if [[ "$(grep -c "^${group}:" "${test_root}/usr/lib/group")" -ne 1 ]]; then
        echo "FAIL: ${group} must be promoted exactly once to /usr/lib/group" >&2
        exit 1
    fi
    if grep -q "^${group}:" "${test_root}/etc/group"; then
        echo "FAIL: ${group} must not remain in /etc/group" >&2
        exit 1
    fi
done

grep -q '^root:' "${test_root}/etc/passwd"
grep -q '^kdlocpanda:' "${test_root}/etc/passwd"
grep -q '^root:' "${test_root}/etc/group"
grep -q '^kdlocpanda:' "${test_root}/etc/group"

for required in \
    'source /ctx/build/bootc-accounts.sh' \
    'getent group plugdev' \
    'groupadd --system plugdev' \
    'promote_bootc_system_accounts /'; do
    if ! grep -Fq "${required}" "${INSTALLER}"; then
        echo "FAIL: DX installation must run bootc account promotion (${required})" >&2
        exit 1
    fi
done

echo "PASS: late-installed DX accounts remain available after bootc upgrades"
