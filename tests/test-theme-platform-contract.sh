#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINERFILE="${ROOT_DIR}/Containerfile"
ASSEMBLY="${ROOT_DIR}/build/10-build.sh"
INSTALLER="${ROOT_DIR}/build/16-wellness-floor.sh"
THEME_DEFAULT="${ROOT_DIR}/custom/system_files/etc/dudley/theme-default"
THEME_ENROLLMENT="${ROOT_DIR}/custom/system_files/etc/dudley/theme-enrollment"
GDM_PROFILE="${ROOT_DIR}/custom/system_files/etc/dconf/profile/gdm"
GDM_BRANDING="${ROOT_DIR}/custom/system_files/etc/dconf/db/gdm.d/01-dudley-branding"
PLYMOUTH_THEME_DIR="${ROOT_DIR}/custom/system_files/usr/share/plymouth/themes/dudley-wellness-floor"
PLYMOUTH_DESCRIPTOR="${PLYMOUTH_THEME_DIR}/dudley-wellness-floor.plymouth"
PLYMOUTH_SCRIPT="${PLYMOUTH_THEME_DIR}/dudley-wellness-floor.script"
PLYMOUTH_BACKGROUND="${PLYMOUTH_THEME_DIR}/background.png"
JUSTFILE="${ROOT_DIR}/Justfile"
README="${ROOT_DIR}/README.md"

for required_file in \
    "${INSTALLER}" \
    "${THEME_DEFAULT}" \
    "${THEME_ENROLLMENT}" \
    "${GDM_PROFILE}" \
    "${GDM_BRANDING}" \
    "${PLYMOUTH_DESCRIPTOR}" \
    "${PLYMOUTH_SCRIPT}" \
    "${PLYMOUTH_BACKGROUND}"; do
    if [[ ! -f "${required_file}" ]]; then
        echo "FAIL: missing Wellness Floor product file ${required_file#"${ROOT_DIR}/"}" >&2
        exit 1
    fi
done

for expected_profile_entry in \
    'user-db:user' \
    'system-db:gdm' \
    'file-db:/usr/share/gdm/greeter-dconf-defaults'; do
    if ! grep -Fxq "${expected_profile_entry}" "${GDM_PROFILE}"; then
        echo "FAIL: GDM profile is missing ${expected_profile_entry}" >&2
        exit 1
    fi
done

for expected_branding_entry in \
    '[org/gnome/login-screen]' \
    'banner-message-enable=true' \
    "banner-message-text='Dudley OS · Wellness Floor'"; do
    if ! grep -Fxq "${expected_branding_entry}" "${GDM_BRANDING}"; then
        echo "FAIL: GDM branding is missing ${expected_branding_entry}" >&2
        exit 1
    fi
done

for expected_descriptor_entry in \
    'ModuleName=script' \
    'ImageDir=/usr/share/plymouth/themes/dudley-wellness-floor' \
    'ScriptFile=/usr/share/plymouth/themes/dudley-wellness-floor/dudley-wellness-floor.script'; do
    if ! grep -Fxq "${expected_descriptor_entry}" "${PLYMOUTH_DESCRIPTOR}"; then
        echo "FAIL: Plymouth descriptor is missing ${expected_descriptor_entry}" >&2
        exit 1
    fi
done

for expected_script_entry in \
    'Image("background.png")' \
    'Plymouth.SetBootProgressFunction' \
    'Window.GetWidth()' \
    'Window.GetHeight()'; do
    if ! grep -Fq "${expected_script_entry}" "${PLYMOUTH_SCRIPT}"; then
        echo "FAIL: Plymouth script is missing ${expected_script_entry}" >&2
        exit 1
    fi
done

# Original Dudley-owned source:
# dsb-common/system_files/dudley/usr/share/dudley/themes/wellness-floor/wallpapers/wellness-room.png
if [[ "$(sha256sum "${PLYMOUTH_BACKGROUND}" | awk '{print $1}')" != \
    '481ed6ee2e23bd444a9b323040dd1ad81ae75258ae041fad409e6c88110fef8d' ]]; then
    echo "FAIL: Plymouth background does not match the Dudley-owned Wellness Floor asset" >&2
    exit 1
fi

if [[ "$(<"${THEME_DEFAULT}")" != "wellness-floor" ]]; then
    echo "FAIL: the selected Dudley theme must be wellness-floor" >&2
    exit 1
fi

if [[ "$(<"${THEME_ENROLLMENT}")" != "default-off" ]]; then
    echo "FAIL: Wellness Floor enrollment must remain default-off until VM acceptance" >&2
    exit 1
fi

if ! grep -Fq '/ctx/build/16-wellness-floor.sh' "${ASSEMBLY}"; then
    echo "FAIL: final image assembly must run the Wellness Floor system integration" >&2
    exit 1
fi

mapfile -t dsb_common_refs < <(
    grep -oE 'ghcr\.io/joshyorko/dsb-common:latest@sha256:[0-9a-f]{64}' "${CONTAINERFILE}"
)
if [[ "${#dsb_common_refs[@]}" -ne 2 ]]; then
    echo "FAIL: both dsb-common payload copies must use immutable sha256 refs" >&2
    exit 1
fi
if [[ "${dsb_common_refs[0]}" != "${dsb_common_refs[1]}" ]]; then
    echo "FAIL: shared and Dudley payload copies must use the same dsb-common digest" >&2
    exit 1
fi

if ! grep -Fq 'bash tests/test-theme-platform-contract.sh' "${JUSTFILE}"; then
    echo "FAIL: just test-unit must run the Wellness Floor product contract" >&2
    exit 1
fi

for required_doc in \
    'dudley-theme status --json' \
    'dudley-theme set wellness-floor' \
    'ujust dudley-theme set wellness-floor' \
    'default-off' \
    'per-user live session' \
    'image-owned static'; do
    if ! grep -Fq "${required_doc}" "${README}"; then
        echo "FAIL: README is missing Wellness Floor guidance: ${required_doc}" >&2
        exit 1
    fi
done

test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

mkdir -p \
    "${test_root}/bin" \
    "${test_root}/image/etc/dudley" \
    "${test_root}/image/etc/dconf/profile" \
    "${test_root}/image/etc/dconf/db/gdm.d" \
    "${test_root}/image/usr/lib/modules/test-kernel" \
    "${test_root}/image/usr/share/dudley/themes/wellness-floor" \
    "${test_root}/image/usr/share/glib-2.0/schemas" \
    "${test_root}/image/usr/share/plymouth/themes"

cp "${THEME_DEFAULT}" "${test_root}/image/etc/dudley/theme-default"
cp "${THEME_ENROLLMENT}" "${test_root}/image/etc/dudley/theme-enrollment"
cp "${GDM_PROFILE}" "${test_root}/image/etc/dconf/profile/gdm"
cp "${GDM_BRANDING}" "${test_root}/image/etc/dconf/db/gdm.d/01-dudley-branding"
cp -a "${PLYMOUTH_THEME_DIR}" "${test_root}/image/usr/share/plymouth/themes/"
touch "${test_root}/image/usr/lib/modules/test-kernel/initramfs.img"

cat >"${test_root}/image/usr/share/dudley/themes/wellness-floor/manifest.json" <<'EOF'
{
  "schema_version": 2,
  "id": "wellness-floor",
  "platform": {
    "desktop": "gnome",
    "profiles": ["bluefin", "ubuntu"]
  }
}
EOF

cat >"${test_root}/bin/dnf5" <<'EOF'
#!/usr/bin/env bash
printf 'dnf5 %s\n' "$*" >>"${THEME_PLATFORM_TEST_LOG}"
EOF

cat >"${test_root}/bin/rpm" <<'EOF'
#!/usr/bin/env bash
printf 'rpm %s\n' "$*" >>"${THEME_PLATFORM_TEST_LOG}"
EOF

cat >"${test_root}/bin/dconf" <<'EOF'
#!/usr/bin/env bash
printf 'dconf %s\n' "$*" >>"${THEME_PLATFORM_TEST_LOG}"
EOF

cat >"${test_root}/bin/glib-compile-schemas" <<'EOF'
#!/usr/bin/env bash
printf 'glib-compile-schemas %s\n' "$*" >>"${THEME_PLATFORM_TEST_LOG}"
EOF

cat >"${test_root}/bin/plymouth-set-default-theme" <<'EOF'
#!/usr/bin/env bash
printf 'plymouth-set-default-theme %s\n' "$*" >>"${THEME_PLATFORM_TEST_LOG}"
EOF

cat >"${test_root}/bin/dracut" <<'EOF'
#!/usr/bin/env bash
printf 'dracut %s\n' "$*" >>"${THEME_PLATFORM_TEST_LOG}"
EOF

cat >"${test_root}/bin/lsinitrd" <<'EOF'
#!/usr/bin/env bash
printf 'lsinitrd %s\n' "$*" >>"${THEME_PLATFORM_TEST_LOG}"
if [[ "${THEME_PLATFORM_TEST_INITRAMFS_COMPLETE:-1}" == "1" ]]; then
    cat <<'CONTENTS'
usr/share/plymouth/themes/dudley-wellness-floor/dudley-wellness-floor.plymouth
usr/share/plymouth/themes/dudley-wellness-floor/dudley-wellness-floor.script
usr/share/plymouth/themes/dudley-wellness-floor/background.png
CONTENTS
fi
EOF

chmod +x "${test_root}/bin/"*
export THEME_PLATFORM_TEST_LOG="${test_root}/commands.log"

PATH="${test_root}/bin:${PATH}" \
    THEME_PLATFORM_ROOT="${test_root}/image" \
    bash "${INSTALLER}"

for expected_command in \
    'dnf5 install -y gnome-shell-extension-user-theme' \
    'dnf5 install -y plymouth-plugin-script' \
    'rpm -q gnome-shell gnome-shell-extension-user-theme' \
    'rpm -q plymouth-plugin-script' \
    'dconf update' \
    "glib-compile-schemas ${test_root}/image/usr/share/glib-2.0/schemas" \
    'plymouth-set-default-theme dudley-wellness-floor' \
    "dracut --force ${test_root}/image/usr/lib/modules/test-kernel/initramfs.img test-kernel" \
    "lsinitrd ${test_root}/image/usr/lib/modules/test-kernel/initramfs.img"; do
    if ! grep -Fxq "${expected_command}" "${THEME_PLATFORM_TEST_LOG}"; then
        echo "FAIL: system integration did not run: ${expected_command}" >&2
        exit 1
    fi
done

if THEME_PLATFORM_TEST_INITRAMFS_COMPLETE=0 \
    PATH="${test_root}/bin:${PATH}" \
    THEME_PLATFORM_ROOT="${test_root}/image" \
    bash "${INSTALLER}" >"${test_root}/incomplete-initramfs.log" 2>&1; then
    echo "FAIL: system integration accepted an initramfs without Dudley Plymouth assets" >&2
    exit 1
fi

if ! grep -Fq 'initramfs is missing Dudley Plymouth asset' \
    "${test_root}/incomplete-initramfs.log"; then
    echo "FAIL: incomplete initramfs failure did not identify the missing Plymouth asset" >&2
    exit 1
fi

python3 - "${test_root}/image/usr/share/dudley/themes/wellness-floor/manifest.json" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["platform"]["desktop"] = "kde"
manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
PY

if PATH="${test_root}/bin:${PATH}" \
    THEME_PLATFORM_ROOT="${test_root}/image" \
    bash "${INSTALLER}" >"${test_root}/incompatible.log" 2>&1; then
    echo "FAIL: system integration accepted a non-GNOME theme manifest" >&2
    exit 1
fi

if ! grep -Fq 'selected Dudley theme is not GNOME compatible' "${test_root}/incompatible.log"; then
    echo "FAIL: incompatible manifest failure did not identify the GNOME boundary" >&2
    exit 1
fi

echo "PASS: Dudley OS integrates the default-off Wellness Floor platform"
