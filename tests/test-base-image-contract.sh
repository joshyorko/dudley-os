#!/usr/bin/env bash
# Test default Bluefin DX base image ref used by local builds.

set -euo pipefail

containerfile="${1:-Containerfile}"
renovate_file=".github/renovate.json5"
expected='ARG BASE_IMAGE_REF="ghcr.io/ublue-os/bluefin-dx:stable@sha256:be12b8959143a9a949458fddff4b023aae6ab26655718a791eb88c1799df59dc"'

if ! grep -Fxq "$expected" "$containerfile"; then
	echo "FAIL: Containerfile must default to the pinned Bluefin DX stable base image" >&2
	echo "Expected: $expected" >&2
	exit 1
fi

if grep -Fq "bluefin-dx:stable:latest" "$containerfile"; then
	echo "FAIL: Containerfile must not use malformed bluefin-dx:stable:latest ref" >&2
	exit 1
fi

for required in \
	'"/^Containerfile$/"' \
	'BASE_IMAGE_REF=' \
	'ghcr\\.io\\/ublue-os\\/bluefin-dx'
do
	if ! grep -Fq "$required" "$renovate_file"; then
		echo "FAIL: Renovate must track the pinned Bluefin DX base image ref ($required)" >&2
		exit 1
	fi
done

echo "PASS: Containerfile defaults to a valid pinned Bluefin DX base image"
