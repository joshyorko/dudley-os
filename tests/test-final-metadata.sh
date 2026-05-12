#!/usr/bin/env bash
# Test Dudley final metadata contracts used by Bluefin runtime recipes.

set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

MANIFEST_PATH="$TEST_DIR/etc/dudley/build-manifest.json"
IMAGE_INFO_PATH="$TEST_DIR/usr/share/ublue-os/image-info.json"
OS_RELEASE_FILE="$TEST_DIR/usr/lib/os-release"
mkdir -p "$(dirname "$MANIFEST_PATH")" "$(dirname "$IMAGE_INFO_PATH")" "$(dirname "$OS_RELEASE_FILE")"

cat >"$IMAGE_INFO_PATH" <<'JSON'
{
  "image-flavor": "dx",
  "base-image-name": "bluefin-dx",
  "fedora-version": "44"
}
JSON

cat >"$OS_RELEASE_FILE" <<'EOF'
VERSION_ID=44
VARIANT_ID=bluefin-dx
NAME="Bluefin"
PRETTY_NAME="Bluefin DX"
EOF

FINAL_IMAGE_REF="ghcr.io/joshyorko/dudley-os:stable" \
	BASE_IMAGE_REF="ghcr.io/ublue-os/bluefin-dx:latest@sha256:abc123" \
	SHA_HEAD_SHORT="abc1234" \
	MANIFEST_PATH="$MANIFEST_PATH" \
	IMAGE_INFO_PATH="$IMAGE_INFO_PATH" \
	OS_RELEASE_FILE="$OS_RELEASE_FILE" \
	WALLPAPER_HOOK="$TEST_DIR/missing-wallpaper-hook" \
	WALLPAPER_DIR="$TEST_DIR/missing-wallpaper-dir" \
	VSCODE_HOOK="$TEST_DIR/missing-vscode-hook" \
	VSCODE_EXTENSIONS_LIST="$TEST_DIR/missing-vscode-extensions.list" \
	DUDLEY_BUILD_INFO_CMD="/usr/bin/true" \
	bash build/20-final-metadata.sh

assert_json() {
	local query="$1"
	local expected="$2"
	local actual

	actual="$(jq -r "$query" "$IMAGE_INFO_PATH")"
	if [[ "$actual" != "$expected" ]]; then
		echo "FAIL: $query expected '$expected', got '$actual'" >&2
		exit 1
	fi
}

assert_json '."image-name"' "dudley-os"
assert_json '."image-vendor"' "joshyorko"
assert_json '."image-ref"' "ostree-image-signed:docker://ghcr.io/joshyorko/dudley-os"
assert_json '."image-tag"' "stable"
assert_json '."image-flavor"' "dx"
assert_json '."base-image-name"' "bluefin-dx"
assert_json '."base-image-ref"' "ghcr.io/ublue-os/bluefin-dx:latest@sha256:abc123"

if ! grep -q '^VARIANT_ID="bluefin-dx"$' "$OS_RELEASE_FILE"; then
	echo "FAIL: os-release VARIANT_ID did not preserve inherited base variant" >&2
	exit 1
fi

if ! grep -q '^IMAGE_ID="dudley-os"$' "$OS_RELEASE_FILE"; then
	echo "FAIL: os-release IMAGE_ID was not stamped" >&2
	exit 1
fi

echo "PASS: Dudley final metadata preserves Bluefin DX runtime contracts"
