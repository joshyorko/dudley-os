# Dakota-native Dudley setup

[group('Apps')]
dudley-dakota:
    #!/usr/bin/env bash
    set -euo pipefail
    ujust bluefin-cli
    ujust dudley dx
