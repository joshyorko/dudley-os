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
  "image-flavor": "main",
  "base-image-name": "silverblue",
  "fedora-version": "44"
}
JSON

cat >"$OS_RELEASE_FILE" <<'EOF'
VERSION_ID=44
VARIANT_ID=bluefin
NAME="Bluefin"
PRETTY_NAME="Bluefin"
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
	BASE_IMAGE_REF="ghcr.io/projectbluefin/bluefin:stable@sha256:abc123" \
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
assert_json '."image-flavor"' "main"
assert_json '."base-image-name"' "silverblue"
assert_json '."base-image-ref"' "ghcr.io/projectbluefin/bluefin:stable@sha256:abc123"
assert_json '.stream' "stable"
assert_json '."base-distribution"' "bluefin"

metadata_keys="$(jq -r 'keys_unsorted | join(",")' "$IMAGE_INFO_PATH")"
expected_metadata_keys='image-flavor,base-image-name,fedora-version,image-name,image-vendor,image-ref,image-tag,base-image-ref,stream,base-distribution'
if [[ "$metadata_keys" != "$expected_metadata_keys" ]]; then
	echo "FAIL: Bluefin metadata key order changed: $metadata_keys" >&2
	exit 1
fi

if ! grep -q '^VARIANT_ID="bluefin"$' "$OS_RELEASE_FILE"; then
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

DAKOTA_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR" "$DAKOTA_DIR"' EXIT
DAKOTA_MANIFEST_PATH="$DAKOTA_DIR/etc/dudley/build-manifest.json"
DAKOTA_IMAGE_INFO_PATH="$DAKOTA_DIR/usr/share/ublue-os/image-info.json"
DAKOTA_OS_RELEASE_FILE="$DAKOTA_DIR/usr/lib/os-release"
mkdir -p "$(dirname "$DAKOTA_MANIFEST_PATH")" "$(dirname "$DAKOTA_IMAGE_INFO_PATH")" "$(dirname "$DAKOTA_OS_RELEASE_FILE")"

cat >"$DAKOTA_IMAGE_INFO_PATH" <<'JSON'
{
  "image-flavor": "main",
  "base-image-name": "dakota",
  "fedora-version": "44"
}
JSON

cat >"$DAKOTA_OS_RELEASE_FILE" <<'EOF'
ID=dakota
ID_LIKE="gnomeos"
VERSION_ID=46
VARIANT_ID=dakota
NAME="Dakota"
PRETTY_NAME="Dakota"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/projectbluefin/dakota"
IMAGE_TAG="latest"
EOF

DUDLEY_STREAM=dakota \
	BASE_DISTRIBUTION=dakota \
	FINAL_IMAGE_REF=ghcr.io/joshyorko/dudley-os:dakota \
	BASE_IMAGE_REF=ghcr.io/projectbluefin/dakota:stable@sha256:abc123 \
	MANIFEST_PATH="$DAKOTA_MANIFEST_PATH" \
	IMAGE_INFO_PATH="$DAKOTA_IMAGE_INFO_PATH" \
	OS_RELEASE_FILE="$DAKOTA_OS_RELEASE_FILE" \
	WALLPAPER_HOOK="$DAKOTA_DIR/missing-wallpaper-hook" \
	VSCODE_HOOK="$DAKOTA_DIR/missing-vscode-hook" \
	DUDLEY_BUILD_INFO_CMD=/usr/bin/true \
	bash build/20-final-metadata.sh

for expected in 'ID=dakota' 'ID_LIKE="gnomeos"' 'VERSION_ID=46' 'VARIANT_ID="dakota"'; do
	grep -Fxq "$expected" "$DAKOTA_OS_RELEASE_FILE" || { echo "FAIL: Dakota inherited os-release value changed: $expected" >&2; exit 1; }
done
grep -Fxq 'IMAGE_REF="ostree-image-signed:docker://ghcr.io/joshyorko/dudley-os"' "$DAKOTA_OS_RELEASE_FILE"
grep -Fxq 'IMAGE_TAG="dakota"' "$DAKOTA_OS_RELEASE_FILE"
jq -e '."image-name" == "dudley-os" and ."image-tag" == "dakota" and ."image-flavor" == "dakota" and .stream == "dakota" and ."base-distribution" == "dakota" and ."base-image-ref" == "ghcr.io/projectbluefin/dakota:stable@sha256:abc123" and has("fedora-version") | not' "$DAKOTA_IMAGE_INFO_PATH" >/dev/null

echo "PASS: Dudley final metadata preserves Project Bluefin runtime contracts"
