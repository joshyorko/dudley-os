# Dakota-native Dudley setup

[group('Apps')]
dudley-dakota:
    #!/usr/bin/env bash
    set -euo pipefail
    ujust dudley
    echo "Run 'ujust dx-group', then log out and back in, to enable non-root Docker access."
