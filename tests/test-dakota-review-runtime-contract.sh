#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

installer="${ROOT_DIR}/build/install-dakota-review-runtime.sh"

if [[ ! -f "${installer}" ]]; then
    echo "FAIL: build/install-dakota-review-runtime.sh is missing" >&2
    exit 1
fi

grep -Fq 'dnf5 install -y crun-krun e2fsprogs gocryptfs' "${installer}"
if grep -Eq '(^|[[:space:]])(dnf|yum|rpm-ostree)([[:space:]]|$)' "${installer}"; then
    echo "FAIL: the Review host runtime installer must use dnf5 exclusively" >&2
    exit 1
fi

grep -Fq 'COPY build/install-dakota-review-runtime.sh /build/install-dakota-review-runtime.sh' \
    "${ROOT_DIR}/Containerfile.dakota"
grep -Fq '/ctx/build/install-dakota-review-runtime.sh' "${ROOT_DIR}/build/10-dakota.sh"

# apptainer and squashfuse belong to the bluefin-review-dev Homebrew formula, so the
# image-side installer must not claim ownership of them.
for application in apptainer squashfuse; do
    if grep -Fq "${application}" "${installer}"; then
        echo "FAIL: installer must not reference ${application}" >&2
        exit 1
    fi
done

fixture="${TMP_DIR}/root"
bin="${TMP_DIR}/bin"
mkdir -p "${bin}"

cat > "${bin}/dnf5" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DUDLEY_DNF_LOG}"
EOF
chmod +x "${bin}/dnf5"
for stub in rpm krun fuse2fs gocryptfs; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${bin}/${stub}"
    chmod +x "${bin}/${stub}"
done

DUDLEY_ROOT="${fixture}" \
DUDLEY_DNF_LOG="${TMP_DIR}/dnf5.log" \
PATH="${bin}:/usr/bin:/bin" \
    bash "${installer}"

grep -Fxq 'install -y crun-krun e2fsprogs gocryptfs' "${TMP_DIR}/dnf5.log"

conf="${fixture}/etc/containers/containers.conf.d/50-dudley-krun.conf"
test -f "${conf}"
grep -Fq '[engine.runtimes]' "${conf}"
grep -Fq 'krun = ["/usr/bin/krun"]' "${conf}"
if grep -Eq '^[[:space:]]*runtime[[:space:]]*=' "${conf}"; then
    echo "FAIL: the krun registration must not change the default OCI runtime" >&2
    exit 1
fi

# A host without fuse2fs cannot mount the Review EXT3 fallback, so the installer must fail.
negative_bin="${TMP_DIR}/negative-bin"
mkdir -p "${negative_bin}"
for stub in rpm krun gocryptfs; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${negative_bin}/${stub}"
    chmod +x "${negative_bin}/${stub}"
done
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${negative_bin}/dnf5"
chmod +x "${negative_bin}/dnf5"
for tool in bash install cat; do
    ln -s "$(type -P "${tool}")" "${negative_bin}/${tool}"
done

if env \
    PATH="${negative_bin}" \
    DUDLEY_ROOT="${TMP_DIR}/negative-root" \
    DUDLEY_DNF_LOG="${TMP_DIR}/negative-dnf5.log" \
    "$(type -P bash)" "${installer}" > "${TMP_DIR}/negative.out" 2>&1; then
    echo "FAIL: installer must fail when fuse2fs is unavailable" >&2
    exit 1
fi
grep -Fq 'Missing fuse2fs' "${TMP_DIR}/negative.out"

echo 'PASS: Dakota installs the Bluefin Review host runtime contract'
