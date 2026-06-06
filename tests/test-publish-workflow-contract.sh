#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_WORKFLOW="${ROOT_DIR}/.github/workflows/build.yml"
NVIDIA_WORKFLOW="${ROOT_DIR}/.github/workflows/build-nvidia.yml"
JUSTFILE="${ROOT_DIR}/Justfile"

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
	assert_contains "${workflow}" 'uses: anchore/sbom-action/download-syft@' "${name} workflow must install Syft for local SBOM generation"
	assert_contains "${workflow}" "sudo -E \"\$(command -v just)\" gen-sbom" "${name} workflow must generate SBOM from the local image"
	assert_contains "${workflow}" 'uses: oras-project/setup-oras@' "${name} workflow must install ORAS to attach the precomputed SBOM"
	assert_contains "${workflow}" "oras attach \\" "${name} workflow must attach the precomputed SBOM as an OCI referrer"
	assert_contains "${workflow}" "cosign sign -y \"\${IMAGE}@\${SBOM_DIGEST}\"" "${name} workflow must sign the attached SBOM"
}

assert_publish_contract "${MAIN_WORKFLOW}" "main publish"
assert_publish_contract "${NVIDIA_WORKFLOW}" "Nvidia publish"

assert_contains "${MAIN_WORKFLOW}" "certificate-identity-regexp: '^https://github\\.com/joshyorko/dudley-os/\\.github/workflows/build\\.yml@refs/heads/main$'" "main publish signing identity must match build.yml"
assert_contains "${NVIDIA_WORKFLOW}" "certificate-identity-regexp: '^https://github\\.com/joshyorko/dudley-os/\\.github/workflows/build-nvidia\\.yml@refs/heads/main$'" "Nvidia publish signing identity must match build-nvidia.yml"
assert_contains "${JUSTFILE}" "gen-sbom \$target_image=image_name \$tag=default_tag \$syft_cmd=\"syft\":" "Justfile must expose the upstream-style gen-sbom primitive"
assert_contains "${JUSTFILE}" 'save --format oci-dir' "gen-sbom must scan an OCI directory instead of rescanning a remote image"
assert_contains "${JUSTFILE}" "\"\${syft_cmd}\" --source-name \"\${target_image}:\${tag}\" \"oci-dir:\${oci_dir}\"" "gen-sbom must pass the local OCI directory to Syft"

echo "PASS: publish workflows sign, attest, and attach locally generated SBOMs"
