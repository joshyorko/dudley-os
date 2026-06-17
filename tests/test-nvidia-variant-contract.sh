#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/build-nvidia.yml"
JUSTFILE="${ROOT_DIR}/Justfile"

if [[ ! -f "${WORKFLOW}" ]]; then
    echo "FAIL: missing manual Nvidia build workflow" >&2
    exit 1
fi

if ! grep -q '^  workflow_dispatch:$' "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow must be manually dispatched" >&2
    exit 1
fi

for automatic_trigger in 'pull_request:' 'push:' 'schedule:' 'merge_group:'; do
    if grep -q "^  ${automatic_trigger}" "${WORKFLOW}"; then
        echo "FAIL: Nvidia workflow must not automatically trigger ${automatic_trigger}" >&2
        exit 1
    fi
done

if ! grep -q 'NVIDIA_BASE_IMAGE_REF: "ghcr.io/ublue-os/bluefin-dx-nvidia:stable@sha256:1b1a65e0c8ac9718ecaa326c73568c0fe48f589165cdf3f6768911e5ae86d9cd"' "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow must pin Bluefin DX Nvidia stable base image" >&2
    exit 1
fi

for tag in \
    'type=raw,value=nvidia' \
    'type=raw,value=nvidia-latest' \
    'type=raw,value=latest-nvidia' \
    'type=raw,value=nvidia-stable' \
    "type=raw,value=nvidia.{{date 'YYYYMMDD'}}" \
    "type=raw,value=nvidia-latest.{{date 'YYYYMMDD'}}" \
    "type=raw,value=latest-nvidia.{{date 'YYYYMMDD'}}"; do
    if ! grep -q "${tag}" "${WORKFLOW}"; then
        echo "FAIL: Nvidia workflow missing expected tag ${tag}" >&2
        exit 1
    fi
done

if ! grep -Fq "certificate-identity-regexp: '^https://github\\.com/joshyorko/dudley-os/\\.github/workflows/build-nvidia\\.yml@refs/heads/main$'" "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow signing identity must match build-nvidia.yml" >&2
    exit 1
fi

if ! grep -Fq "BASE_IMAGE_REF=\"\${NVIDIA_BASE_IMAGE_REF}\" \\" "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow must pass Nvidia base image into build" >&2
    exit 1
fi

if ! grep -Fq "METADATA_IMAGE=\"\${IMAGE_REGISTRY}/\${IMAGE_NAME}\" \\" "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow must pass canonical image ref into build metadata" >&2
    exit 1
fi

# shellcheck disable=SC2016
if ! grep -q 'if \[\[ -n "${BASE_IMAGE_REF:-}" \]\]; then' "${JUSTFILE}"; then
    echo "FAIL: Justfile build must forward BASE_IMAGE_REF when set" >&2
    exit 1
fi

# shellcheck disable=SC2016
if ! grep -q 'BUILD_ARGS+=("--build-arg" "BASE_IMAGE_REF=${BASE_IMAGE_REF}")' "${JUSTFILE}"; then
    echo "FAIL: Justfile build must add BASE_IMAGE_REF as a build arg" >&2
    exit 1
fi

echo "PASS: Nvidia variant workflow is manual, pinned, tagged, signed, and GPU-base aware"
