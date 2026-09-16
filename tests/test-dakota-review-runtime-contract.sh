#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

containerfile="${ROOT_DIR}/Containerfile.dakota"
installer="${ROOT_DIR}/build/install-dakota-review-runtime.sh"

grep -Fq 'AS review-runtime' "${containerfile}"
grep -Fq 'dnf install -y crun-krun e2fsprogs gocryptfs' "${containerfile}"
# shellcheck disable=SC2016
grep -Fq '$1 ~ /^\// { print $1 }' "${containerfile}"
grep -Fq 'COPY --from=review-runtime /review-runtime /oci/review-runtime' "${containerfile}"
grep -Fq '/ctx/build/install-dakota-review-runtime.sh /ctx/oci/review-runtime /' \
    "${ROOT_DIR}/build/10-dakota.sh"

if grep -Eq '(^|[[:space:]])(dnf5?|yum|rpm-ostree)([[:space:]]|$)' "${installer}"; then
    echo "FAIL: the Dakota installer must copy staged files without a package manager" >&2
    exit 1
fi

source_root="${TMP_DIR}/source"
destination_root="${TMP_DIR}/destination"
mkdir -p \
    "${source_root}/usr/lib/dudley-review-runtime/bin" \
    "${source_root}/usr/lib/dudley-review-runtime/lib64"
for command in crun-krun fuse2fs gocryptfs; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > \
        "${source_root}/usr/lib/dudley-review-runtime/bin/${command}"
    chmod +x "${source_root}/usr/lib/dudley-review-runtime/bin/${command}"
done
printf 'runtime library\n' > \
    "${source_root}/usr/lib/dudley-review-runtime/lib64/libreview.so"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > \
    "${source_root}/usr/lib/dudley-review-runtime/lib64/ld-linux-x86-64.so.2"
chmod +x "${source_root}/usr/lib/dudley-review-runtime/lib64/ld-linux-x86-64.so.2"

bash "${installer}" "${source_root}" "${destination_root}"

for command in crun-krun fuse2fs gocryptfs; do
    test -x "${destination_root}/usr/bin/${command}"
done
test -f "${destination_root}/usr/lib/dudley-review-runtime/lib64/libreview.so"

conf="${destination_root}/etc/containers/containers.conf.d/50-dudley-krun.conf"
grep -Fq '[engine.runtimes]' "${conf}"
grep -Fq 'krun = ["/usr/bin/crun-krun"]' "${conf}"
if grep -Eq '^[[:space:]]*runtime[[:space:]]*=' "${conf}"; then
    echo "FAIL: the krun registration must not change the default OCI runtime" >&2
    exit 1
fi

echo 'PASS: Dakota stages the Bluefin Review host runtime without a package manager'
