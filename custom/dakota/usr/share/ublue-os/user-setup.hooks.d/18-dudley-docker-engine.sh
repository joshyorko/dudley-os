#!/usr/bin/env bash
set -euo pipefail

rm -f "${HOME}/.config/environment.d/60-dudley-podman-docker.conf"
systemctl --user daemon-reload
systemctl --user unset-environment DOCKER_HOST
