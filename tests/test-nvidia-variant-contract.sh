#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/build-nvidia.yml"
JUSTFILE="${ROOT_DIR}/Justfile"
RENOVATE_CONFIG="${ROOT_DIR}/.github/renovate.json5"

if [[ ! -f "${WORKFLOW}" ]]; then
    echo "FAIL: missing Nvidia build workflow" >&2
    exit 1
fi

for trigger in 'workflow_dispatch:' 'pull_request:' 'push:'; do
    if ! grep -q "^  ${trigger}" "${WORKFLOW}"; then
        echo "FAIL: Nvidia workflow must support ${trigger}" >&2
        exit 1
    fi
done

for automatic_trigger in 'schedule:' 'merge_group:'; do
    if grep -q "^  ${automatic_trigger}" "${WORKFLOW}"; then
        echo "FAIL: Nvidia workflow must not automatically trigger ${automatic_trigger}" >&2
        exit 1
    fi
done

if grep -Fq "if: github.ref == format('refs/heads/{0}', github.event.repository.default_branch)" "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow build job must run on pull requests, not only the default branch" >&2
    exit 1
fi

publish_guard="if: github.event_name != 'pull_request' && github.ref == format('refs/heads/{0}', github.event.repository.default_branch)"
if [[ "$(grep -Fc "${publish_guard}" "${WORKFLOW}")" -lt 3 ]]; then
    echo "FAIL: Nvidia workflow publish/sign steps must be guarded to the default branch" >&2
    exit 1
fi

if ! grep -q 'DEFAULT_TAG: "nvidia-latest"' "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow default tag must describe the latest Nvidia variant" >&2
    exit 1
fi

if ! grep -q 'NVIDIA_BASE_IMAGE_REF: "ghcr.io/ublue-os/bluefin-dx-nvidia:latest@sha256:1426cf94439e6794bb4539eb80fff979930c6ae0d4b97457158983ece2ac653f"' "${WORKFLOW}"; then
    echo "FAIL: Nvidia workflow must pin Bluefin DX Nvidia latest base image" >&2
    exit 1
fi

if [[ ! -f "${RENOVATE_CONFIG}" ]]; then
    echo "FAIL: missing Renovate config" >&2
    exit 1
fi

for renovate_needle in \
    '"managerFilePatterns": ["/^\\.github\\/workflows\\/build-nvidia\\.yml$/"]' \
    'NVIDIA_BASE_IMAGE_REF' \
    'bluefin-dx-nvidia' \
    '"datasourceTemplate": "docker"'; do
    if ! grep -Fq "${renovate_needle}" "${RENOVATE_CONFIG}"; then
        echo "FAIL: Renovate config must track Nvidia base image refs (${renovate_needle})" >&2
        exit 1
    fi
done

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

echo "PASS: Nvidia variant workflow runs on PR/main, tracks latest, is tagged/signed, and is GPU-base aware"
