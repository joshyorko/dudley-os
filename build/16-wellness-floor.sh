#!/usr/bin/env bash

set -euo pipefail

root="${THEME_PLATFORM_ROOT:-}"
theme_default="${root}/etc/dudley/theme-default"
theme_enrollment="${root}/etc/dudley/theme-enrollment"
themes_dir="${root}/usr/share/dudley/themes"
schema_dir="${root}/usr/share/glib-2.0/schemas"
gdm_profile="${root}/etc/dconf/profile/gdm"
gdm_branding="${root}/etc/dconf/db/gdm.d/01-dudley-branding"
plymouth_theme_id="dudley-wellness-floor"
plymouth_theme_dir="${root}/usr/share/plymouth/themes/${plymouth_theme_id}"

if [[ ! -f "${theme_default}" ]]; then
    echo "ERROR: missing Dudley theme selection: ${theme_default}" >&2
    exit 1
fi

if [[ ! -f "${theme_enrollment}" ]]; then
    echo "ERROR: missing Dudley theme enrollment policy: ${theme_enrollment}" >&2
    exit 1
fi

for branding_file in \
    "${gdm_profile}" \
    "${gdm_branding}" \
    "${plymouth_theme_dir}/${plymouth_theme_id}.plymouth" \
    "${plymouth_theme_dir}/${plymouth_theme_id}.script" \
    "${plymouth_theme_dir}/background.png"; do
    if [[ ! -f "${branding_file}" ]]; then
        echo "ERROR: missing Dudley static branding file: ${branding_file}" >&2
        exit 1
    fi
done

theme_id="$(tr -d '[:space:]' <"${theme_default}")"
enrollment="$(tr -d '[:space:]' <"${theme_enrollment}")"
manifest="${themes_dir}/${theme_id}/manifest.json"

if [[ ! "${theme_id}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "ERROR: invalid Dudley theme id: ${theme_id}" >&2
    exit 1
fi

case "${enrollment}" in
    default-off|pristine-only) ;;
    *)
        echo "ERROR: invalid Dudley theme enrollment policy: ${enrollment}" >&2
        exit 1
        ;;
esac

dnf5 install -y gnome-shell-extension-user-theme
dnf5 install -y plymouth-plugin-script
rpm -q gnome-shell gnome-shell-extension-user-theme
rpm -q plymouth-plugin-script

python3 - "${manifest}" "${theme_id}" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
theme_id = sys.argv[2]

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"ERROR: invalid Dudley theme manifest {manifest_path}: {error}")

if manifest.get("schema_version") != 2:
    raise SystemExit("ERROR: Dudley theme manifest must use schema version 2")
if manifest.get("id") != theme_id:
    raise SystemExit("ERROR: Dudley theme manifest id does not match theme-default")

platform = manifest.get("platform", {})
if platform.get("desktop") != "gnome":
    raise SystemExit("ERROR: selected Dudley theme is not GNOME compatible")
if "bluefin" not in platform.get("profiles", []):
    raise SystemExit("ERROR: selected Dudley theme does not support Bluefin")
PY

dconf update
glib-compile-schemas "${schema_dir}"

plymouth-set-default-theme "${plymouth_theme_id}"

shopt -s nullglob
initramfs_images=("${root}"/usr/lib/modules/*/initramfs.img)
shopt -u nullglob

if [[ "${#initramfs_images[@]}" -eq 0 ]]; then
    echo "ERROR: no initramfs image is available for Dudley Plymouth validation" >&2
    exit 1
fi

for initramfs_image in "${initramfs_images[@]}"; do
    kernel_version="$(basename "$(dirname "${initramfs_image}")")"
    dracut --force "${initramfs_image}" "${kernel_version}"
    initramfs_listing="$(lsinitrd "${initramfs_image}")"
    for plymouth_asset in \
        "usr/share/plymouth/themes/${plymouth_theme_id}/${plymouth_theme_id}.plymouth" \
        "usr/share/plymouth/themes/${plymouth_theme_id}/${plymouth_theme_id}.script" \
        "usr/share/plymouth/themes/${plymouth_theme_id}/background.png"; do
        if ! grep -Fq "${plymouth_asset}" <<<"${initramfs_listing}"; then
            echo "ERROR: initramfs is missing Dudley Plymouth asset: ${plymouth_asset}" >&2
            exit 1
        fi
    done
done

echo "Validated Dudley theme ${theme_id} with enrollment policy ${enrollment}"
