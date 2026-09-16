#!/usr/bin/env bash
set -euo pipefail

source_root="${1:?review runtime source root is required}"
destination_root="${2:-/}"
runtime_relative="usr/lib/dudley-review-runtime"
runtime_source="${source_root%/}/${runtime_relative}"
runtime_destination="${destination_root%/}/${runtime_relative}"

for command in crun-krun fuse2fs gocryptfs; do
    test -x "${runtime_source}/bin/${command}"
done
test -x "${runtime_source}/lib64/ld-linux-x86-64.so.2"

install -d -m 0755 \
    "${runtime_destination}" \
    "${destination_root%/}/usr/bin" \
    "${destination_root%/}/etc/containers/containers.conf.d"
cp -a "${runtime_source}/." "${runtime_destination}/"

for command in crun-krun fuse2fs gocryptfs; do
    cat > "${destination_root%/}/usr/bin/${command}" <<EOF
#!/usr/bin/env bash
exec /usr/lib/dudley-review-runtime/lib64/ld-linux-x86-64.so.2 \\
    --library-path /usr/lib/dudley-review-runtime/lib64 \\
    /usr/lib/dudley-review-runtime/bin/${command} "\$@"
EOF
    chmod 0755 "${destination_root%/}/usr/bin/${command}"
done

cat > "${destination_root%/}/etc/containers/containers.conf.d/50-dudley-krun.conf" <<'EOF'
# Bluefin Review selects this runtime explicitly with podman --runtime=krun.
[engine.runtimes]
krun = ["/usr/bin/crun-krun"]
EOF

echo "Installed staged Bluefin Review host runtime: crun-krun, fuse2fs, gocryptfs"
