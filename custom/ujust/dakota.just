# Dakota-native Dudley setup

[group('Apps')]
dudley-dakota:
    #!/usr/bin/env bash
    set -euo pipefail
    ujust bluefin-cli
    ujust dudley dx
    if brew list --versions podman >/dev/null 2>&1; then
        brew unlink podman
    fi
