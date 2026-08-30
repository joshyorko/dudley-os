#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
NVIDIA_WORKFLOW="${ROOT_DIR}/.github/workflows/build-nvidia.yml"
DAKOTA_WORKFLOW="${ROOT_DIR}/.github/workflows/build-dakota.yml"

assert_contains() {
	local file="$1"
	local needle="$2"
	local message="$3"

	if ! grep -Fq "${needle}" "${file}"; then
		echo "FAIL: ${message}" >&2
		exit 1
	fi
}

assert_publish_contract() {
	local workflow="$1"
	local name="$2"

	if [[ ! -f "${workflow}" ]]; then
		echo "FAIL: missing ${name} workflow" >&2
		exit 1
	fi

	assert_contains "${workflow}" 'generate-sbom: "false"' "${name} workflow must skip the sign-and-publish Syft rescan"
	assert_contains "${workflow}" 'push-attestation: "true"' "${name} workflow must keep build provenance attestations enabled"
	if grep -Fq 'anchore/sbom-action/download-syft' "${workflow}"; then
		echo "FAIL: ${name} workflow must not install Syft in publish path" >&2
		exit 1
	fi
	if grep -Fq 'oras attach' "${workflow}"; then
		echo "FAIL: ${name} workflow must not attach SBOMs in publish path" >&2
		exit 1
	fi
}

assert_publish_contract "${MAIN_WORKFLOW}" "main publish"
assert_publish_contract "${NVIDIA_WORKFLOW}" "Nvidia publish"
assert_publish_contract "${DAKOTA_WORKFLOW}" "Dakota publish"

workflow_triggers() {
	awk '
		/^on:$/ { in_on = 1; next }
		in_on && /^[^[:space:]]/ { exit }
		in_on && /^  [[:alnum:]_]+:/ {
			trigger = $1
			sub(/:$/, "", trigger)
			print trigger
		}
	' "$1" | sort
}

main_triggers="$(workflow_triggers "${MAIN_WORKFLOW}")"
nvidia_triggers="$(workflow_triggers "${NVIDIA_WORKFLOW}")"
dakota_triggers="$(workflow_triggers "${DAKOTA_WORKFLOW}")"

if [[ "${main_triggers}" != "workflow_dispatch" ]]; then
	echo "FAIL: Bluefin stable must be manual-only; found: ${main_triggers//$'\n'/, }" >&2
	exit 1
fi
if [[ "${nvidia_triggers}" != "workflow_dispatch" ]]; then
	echo "FAIL: Bluefin Nvidia must be manual-only; found: ${nvidia_triggers//$'\n'/, }" >&2
	exit 1
fi
for required_trigger in pull_request push workflow_dispatch; do
	if ! grep -Fxq "${required_trigger}" <<<"${dakota_triggers}"; then
		echo "FAIL: Dakota automatic builds must remain active; missing ${required_trigger}" >&2
		exit 1
	fi
done

assert_contains "${MAIN_WORKFLOW}" "certificate-identity-regexp: '^https://github\\.com/joshyorko/dudley-os/\\.github/workflows/build\\.yml@refs/heads/main$'" "main publish signing identity must match build.yml"
assert_contains "${NVIDIA_WORKFLOW}" "certificate-identity-regexp: '^https://github\\.com/joshyorko/dudley-os/\\.github/workflows/build-nvidia\\.yml@refs/heads/main$'" "Nvidia publish signing identity must match build-nvidia.yml"
assert_contains "${DAKOTA_WORKFLOW}" "certificate-identity-regexp: '^https://github\\.com/joshyorko/dudley-os/\\.github/workflows/build-dakota\\.yml@refs/heads/main$'" "Dakota publish signing identity must match build-dakota.yml"
assert_contains "${DAKOTA_WORKFLOW}" "if: github.event_name != 'pull_request' && github.ref == format('refs/heads/{0}', github.event.repository.default_branch)" "Dakota workflow must not publish pull request builds"

echo "PASS: publish workflows sign and attest without SBOM work"
