#!/usr/bin/env bash

set -euo pipefail

root="${THEME_PLATFORM_ROOT:-}"
theme_default="${root}/etc/dudley/theme-default"
theme_enrollment="${root}/etc/dudley/theme-enrollment"
themes_dir="${root}/usr/share/dudley/themes"
schema_dir="${root}/usr/share/glib-2.0/schemas"

if [[ ! -f "${theme_default}" ]]; then
    echo "ERROR: missing Dudley theme selection: ${theme_default}" >&2
    exit 1
fi

if [[ ! -f "${theme_enrollment}" ]]; then
    echo "ERROR: missing Dudley theme enrollment policy: ${theme_enrollment}" >&2
    exit 1
fi

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
rpm -q gnome-shell gnome-shell-extension-user-theme

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

echo "Validated Dudley theme ${theme_id} with enrollment policy ${enrollment}"
