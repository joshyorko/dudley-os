#!/usr/bin/env bash
# Test default Project Bluefin base image ref used by local builds.

set -euo pipefail

containerfile="${1:-Containerfile}"
renovate_file=".github/renovate.json5"
metadata_script="build/20-final-metadata.sh"
base_image_ref="$(
	sed -n 's/^ARG BASE_IMAGE_REF="\([^"]*\)"$/\1/p' "$containerfile"
)"
base_image_pattern='^ghcr\.io/projectbluefin/bluefin:stable@sha256:[0-9a-f]{64}$'

if [[ ! "$base_image_ref" =~ $base_image_pattern ]]; then
	echo "FAIL: Containerfile must default to the canonical Project Bluefin stable image pinned by SHA-256 digest" >&2
	echo "Found: ${base_image_ref:-<missing>}" >&2
	exit 1
fi

if grep -Fq "bluefin:stable:latest" "$containerfile"; then
	echo "FAIL: Containerfile must not use malformed bluefin:stable:latest ref" >&2
	exit 1
fi

if ! grep -Fq 'BASE_IMAGE_REF:-ghcr.io/projectbluefin/bluefin:stable' "$metadata_script"; then
	echo "FAIL: final metadata fallback must use the canonical Project Bluefin stable image" >&2
	exit 1
fi

for required in \
	'"/^Containerfile$/"' \
	'BASE_IMAGE_REF=' \
	'ghcr\\.io\\/projectbluefin\\/bluefin'
do
	if ! grep -Fq "$required" "$renovate_file"; then
		echo "FAIL: Renovate must track the pinned Project Bluefin base image ref ($required)" >&2
		exit 1
	fi
done

echo "PASS: Containerfile defaults to the canonical pinned Project Bluefin stable image"
