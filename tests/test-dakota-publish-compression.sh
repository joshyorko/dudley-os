#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

import yaml

workflow = yaml.safe_load(Path('.github/workflows/build-dakota.yml').read_text())
push_step = next(
    step
    for step in workflow['jobs']['build_push_dakota']['steps']
    if step.get('name') == 'Push To GHCR'
)
assert push_step['with']['compression-format'] == 'zstd', (
    'Dakota composefs images must use standard zstd, not zstd:chunked'
)
PY

echo 'PASS: Dakota images publish with composefs-compatible compression'
