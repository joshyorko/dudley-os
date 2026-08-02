#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/skill-drift.yml"

# These are literal GitHub Actions and shell expressions in the workflow.
# shellcheck disable=SC2016
grep -Fq 'PR_AUTHOR: ${{ github.event.pull_request.user.login }}' "${WORKFLOW}"
# shellcheck disable=SC2016
grep -Fq 'if [[ "${PR_AUTHOR}" == "patchraptor[bot]" ]]; then' "${WORKFLOW}"
grep -Fq 'Patchraptor dependency update; documentation gate not applicable.' "${WORKFLOW}"
grep -Fq 'Implementation changed without a matching documentation update.' "${WORKFLOW}"

echo "PASS: skill drift exempts only Patchraptor while retaining the documentation gate"
