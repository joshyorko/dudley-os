#!/usr/bin/env bash
# Test default Project Bluefin base image ref used by local builds.

set -euo pipefail

containerfile="${1:-Containerfile}"
renovate_file=".github/renovate.json5"
metadata_script="build/20-final-metadata.sh"
expected='ARG BASE_IMAGE_REF="ghcr.io/projectbluefin/bluefin:stable@sha256:a4e485b04df1005fb7e6dbb7c256ec6cf8e1061ddbaaae2163b0b19479c729ab"'

if ! grep -Fxq "$expected" "$containerfile"; then
	echo "FAIL: Containerfile must default to the pinned Project Bluefin stable base image" >&2
	echo "Expected: $expected" >&2
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
