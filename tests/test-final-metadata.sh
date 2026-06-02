#!/usr/bin/env bash
# Test Dudley final metadata contracts used by Bluefin runtime recipes.

set -euo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

MANIFEST_PATH="$TEST_DIR/etc/dudley/build-manifest.json"
IMAGE_INFO_PATH="$TEST_DIR/usr/share/ublue-os/image-info.json"
OS_RELEASE_FILE="$TEST_DIR/usr/lib/os-release"
WALLPAPER_HOOK="$TEST_DIR/usr/share/ublue-os/user-setup.hooks.d/10-wallpaper-enforcement.sh"
WALLPAPER_DIR="$TEST_DIR/usr/share/backgrounds/dudley"
VSCODE_HOOK="$TEST_DIR/usr/share/ublue-os/user-setup.hooks.d/20-dudley-vscode-extensions.sh"
VSCODE_EXTENSIONS_LIST="$TEST_DIR/usr/share/ublue-os/vscode-extensions.list"
CODE_SETTINGS="$TEST_DIR/etc/skel/.config/Code/User/settings.json"
CODE_INSIDERS_SETTINGS="$TEST_DIR/etc/skel/.config/Code - Insiders/User/settings.json"
mkdir -p \
	"$(dirname "$MANIFEST_PATH")" \
	"$(dirname "$IMAGE_INFO_PATH")" \
	"$(dirname "$OS_RELEASE_FILE")" \
	"$(dirname "$WALLPAPER_HOOK")" \
	"$WALLPAPER_DIR" \
	"$(dirname "$VSCODE_HOOK")" \
	"$(dirname "$VSCODE_EXTENSIONS_LIST")" \
	"$(dirname "$CODE_SETTINGS")" \
	"$(dirname "$CODE_INSIDERS_SETTINGS")"

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

cat >"$WALLPAPER_HOOK" <<'EOF'
#!/usr/bin/env bash
hook_version="old-wallpaper"
EOF
chmod +x "$WALLPAPER_HOOK"
touch "$WALLPAPER_DIR/dudley.png"

cat >"$VSCODE_HOOK" <<'EOF'
#!/usr/bin/env bash
hook_version="old-vscode"
EOF
chmod +x "$VSCODE_HOOK"
cat >"$VSCODE_EXTENSIONS_LIST" <<'EOF'
# ignored comment
ms-vscode-remote.remote-containers
ms-azuretools.vscode-containers
EOF
cat >"$CODE_SETTINGS" <<'JSON'
{"window.titleBarStyle":"custom"}
JSON
cat >"$CODE_INSIDERS_SETTINGS" <<'JSON'
{"update.mode":"none"}
JSON

FINAL_IMAGE_REF="ghcr.io/joshyorko/dudley-os:stable" \
	BASE_IMAGE_REF="ghcr.io/ublue-os/bluefin-dx:stable@sha256:abc123" \
	SHA_HEAD_SHORT="abc1234" \
	MANIFEST_PATH="$MANIFEST_PATH" \
	IMAGE_INFO_PATH="$IMAGE_INFO_PATH" \
	OS_RELEASE_FILE="$OS_RELEASE_FILE" \
	WALLPAPER_HOOK="$WALLPAPER_HOOK" \
	WALLPAPER_DIR="$WALLPAPER_DIR" \
	VSCODE_HOOK="$VSCODE_HOOK" \
	VSCODE_EXTENSIONS_LIST="$VSCODE_EXTENSIONS_LIST" \
	VSCODE_CODE_SETTINGS="$CODE_SETTINGS" \
	VSCODE_INSIDERS_SETTINGS="$CODE_INSIDERS_SETTINGS" \
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
assert_json '."base-image-ref"' "ghcr.io/ublue-os/bluefin-dx:stable@sha256:abc123"

if ! grep -q '^VARIANT_ID="bluefin-dx"$' "$OS_RELEASE_FILE"; then
	echo "FAIL: os-release VARIANT_ID did not preserve inherited base variant" >&2
	exit 1
fi

if ! grep -q '^IMAGE_ID="dudley-os"$' "$OS_RELEASE_FILE"; then
	echo "FAIL: os-release IMAGE_ID was not stamped" >&2
	exit 1
fi

wallpaper_version="$(jq -r '.hooks.wallpaper.version' "$MANIFEST_PATH")"
vscode_version="$(jq -r '.hooks["vscode-extensions"].version' "$MANIFEST_PATH")"

if [[ ! "$wallpaper_version" =~ ^[a-f0-9]{8}$ ]]; then
	echo "FAIL: wallpaper hook version was not content hashed" >&2
	exit 1
fi

if [[ ! "$vscode_version" =~ ^[a-f0-9]{8}$ ]]; then
	echo "FAIL: VS Code hook version was not content hashed" >&2
	exit 1
fi

if ! grep -Fxq "hook_version=\"$wallpaper_version\"" "$WALLPAPER_HOOK"; then
	echo "FAIL: wallpaper hook was not stamped with content hash" >&2
	exit 1
fi

if ! grep -Fxq "hook_version=\"$vscode_version\"" "$VSCODE_HOOK"; then
	echo "FAIL: VS Code hook was not stamped with content hash" >&2
	exit 1
fi

jq -e --arg path "$CODE_SETTINGS" '.hooks["vscode-extensions"].dependencies | index($path)' "$MANIFEST_PATH" >/dev/null
jq -e --arg path "$CODE_INSIDERS_SETTINGS" '.hooks["vscode-extensions"].dependencies | index($path)' "$MANIFEST_PATH" >/dev/null
jq -e '.hooks["vscode-extensions"].metadata.extension_count == 2' "$MANIFEST_PATH" >/dev/null

echo "PASS: Dudley final metadata preserves Bluefin DX runtime contracts"
