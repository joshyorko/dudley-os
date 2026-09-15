#!/usr/bin/env bash
set -euo pipefail

root="${DUDLEY_ROOT:-}"

root_path() {
    printf '%s%s\n' "${root}" "$1"
}

dnf5 install -y crun-krun e2fsprogs gocryptfs

containers_conf_dir="$(root_path /etc/containers/containers.conf.d)"
install -d -m 0755 "${containers_conf_dir}"
cat > "${containers_conf_dir}/50-dudley-krun.conf" <<'EOF'
# Bluefin Review selects the OCI runtime by name (podman run --runtime=krun) when
# a libkrun boundary is available. Podman resolves such a name only through this
# [engine.runtimes] table, never from PATH, so the crun-krun binary is registered
# here. No default runtime is set: the image default OCI runtime is unchanged.
[engine.runtimes]
krun = ["/usr/bin/krun"]
EOF

for package in crun-krun e2fsprogs gocryptfs; do
    if ! rpm -q "${package}" >/dev/null; then
        echo "Missing ${package}: required Fedora package for the Bluefin Review host runtime" >&2
        exit 1
    fi
done

for command in krun fuse2fs gocryptfs; do
    if ! command -v "${command}" >/dev/null; then
        echo "Missing ${command}: required host command for the Bluefin Review runtime" >&2
        exit 1
    fi
done

if ! krun --version >/dev/null; then
    echo "Broken krun: installed Bluefin Review runtime is not runnable" >&2
    exit 1
fi

echo "Installed Bluefin Review host runtime: krun runtime registration, fuse2fs, gocryptfs"
