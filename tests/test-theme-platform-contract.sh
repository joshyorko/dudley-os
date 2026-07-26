#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINERFILE="${ROOT_DIR}/Containerfile"
ASSEMBLY="${ROOT_DIR}/build/10-build.sh"
INSTALLER="${ROOT_DIR}/build/16-wellness-floor.sh"
THEME_DEFAULT="${ROOT_DIR}/custom/system_files/etc/dudley/theme-default"
THEME_ENROLLMENT="${ROOT_DIR}/custom/system_files/etc/dudley/theme-enrollment"
JUSTFILE="${ROOT_DIR}/Justfile"
README="${ROOT_DIR}/README.md"

for required_file in \
    "${INSTALLER}" \
    "${THEME_DEFAULT}" \
    "${THEME_ENROLLMENT}"; do
    if [[ ! -f "${required_file}" ]]; then
        echo "FAIL: missing Wellness Floor product file ${required_file#"${ROOT_DIR}/"}" >&2
        exit 1
    fi
done

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
    "${test_root}/image/usr/share/dudley/themes/wellness-floor" \
    "${test_root}/image/usr/share/glib-2.0/schemas"

cp "${THEME_DEFAULT}" "${test_root}/image/etc/dudley/theme-default"
cp "${THEME_ENROLLMENT}" "${test_root}/image/etc/dudley/theme-enrollment"

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

chmod +x "${test_root}/bin/"*
export THEME_PLATFORM_TEST_LOG="${test_root}/commands.log"

PATH="${test_root}/bin:${PATH}" \
    THEME_PLATFORM_ROOT="${test_root}/image" \
    bash "${INSTALLER}"

for expected_command in \
    'dnf5 install -y gnome-shell-extension-user-theme' \
    'rpm -q gnome-shell gnome-shell-extension-user-theme' \
    'dconf update' \
    "glib-compile-schemas ${test_root}/image/usr/share/glib-2.0/schemas"; do
    if ! grep -Fxq "${expected_command}" "${THEME_PLATFORM_TEST_LOG}"; then
        echo "FAIL: system integration did not run: ${expected_command}" >&2
        exit 1
    fi
done

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
