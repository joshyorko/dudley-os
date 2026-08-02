#!/usr/bin/env bash
set -euo pipefail

source_root="$1"
destination_root="${2:-/}"

docker_bin_source="${source_root%/}/usr/local/bin"
plugin_source="${source_root%/}/usr/local/libexec/docker/cli-plugins"
bin_destination="${destination_root%/}/usr/bin"
plugin_destination="${destination_root%/}/usr/libexec/docker/cli-plugins"
systemd_destination="${destination_root%/}/usr/lib/systemd/system"

install -d -m 0755 \
    "${bin_destination}" \
    "${plugin_destination}" \
    "${systemd_destination}" \
    "${destination_root%/}/usr/lib/sysusers.d"

for command in containerd containerd-shim-runc-v2 ctr docker docker-init docker-proxy dockerd runc; do
    test -x "${docker_bin_source}/${command}"
    install -m 0755 "${docker_bin_source}/${command}" "${bin_destination}/${command}"
done

for plugin in docker-buildx docker-compose; do
    test -x "${plugin_source}/${plugin}"
    install -m 0755 "${plugin_source}/${plugin}" "${plugin_destination}/${plugin}"
done

cat > "${systemd_destination}/docker.service" <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com/go/systemd/
After=network-online.target nss-lookup.target docker.socket firewalld.service time-set.target
Wants=network-online.target
Requires=docker.socket

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H fd://
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
Restart=always
RestartSec=2
StartLimitBurst=3
StartLimitIntervalSec=60s
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

cat > "${systemd_destination}/docker.socket" <<'EOF'
[Unit]
Description=Docker Socket for the API

[Socket]
ListenStream=/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

printf 'g docker - -\n' > \
    "${destination_root%/}/usr/lib/sysusers.d/dudley-docker.conf"
