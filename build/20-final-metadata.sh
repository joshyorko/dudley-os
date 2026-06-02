#!/usr/bin/env bash

set -euo pipefail

final_image_ref="${FINAL_IMAGE_REF:-ghcr.io/joshyorko/dudley-os:stable}"
base_image_ref="${BASE_IMAGE_REF:-ghcr.io/ublue-os/bluefin-dx:stable}"
git_commit="${SHA_HEAD_SHORT:-unknown}"

manifest_path="${MANIFEST_PATH:-/etc/dudley/build-manifest.json}"
image_info_path="${IMAGE_INFO_PATH:-/usr/share/ublue-os/image-info.json}"
os_release_path="${OS_RELEASE_FILE:-/usr/lib/os-release}"
dudley_build_info_cmd="${DUDLEY_BUILD_INFO_CMD:-/usr/bin/dudley-build-info}"
repo_url="https://github.com/joshyorko/dudley-os"
support_url="${repo_url}/issues"

parse_image_ref() {
    local image_ref="$1"
    local image_without_transport="${image_ref#ostree-image-signed:docker://}"
    image_without_transport="${image_without_transport#docker://}"

    local registry_and_path="${image_without_transport%@*}"
    local registry="${registry_and_path%%/*}"
    local path_without_registry="${registry_and_path#*/}"

    local vendor="${path_without_registry%%/*}"
    local name_and_tag="${path_without_registry#*/}"
    local image_name="${name_and_tag%%[:@]*}"
    local image_tag="stable"

    if [[ "${name_and_tag}" == *:* ]]; then
        image_tag="${name_and_tag##*:}"
    fi

    printf '%s\n%s\n%s\n%s\n' "${registry}" "${vendor}" "${image_name}" "${image_tag}"
}

compute_content_hash() {
    local files=("$@")

    [[ "${#files[@]}" -gt 0 ]] || return 1

    local sorted_files=()
    mapfile -t sorted_files < <(printf '%s\n' "${files[@]}" | sort)
    cat "${sorted_files[@]}" | sha256sum | cut -c1-8
}

stamp_hook_version() {
    local hook_path="$1"
    local version_hash="$2"

    if grep -qE '^hook_version="' "${hook_path}"; then
        sed -i -E "s/^hook_version=\"[^\"]*\"/hook_version=\"${version_hash}\"/" "${hook_path}"
    else
        echo "WARNING: ${hook_path} does not declare hook_version"
    fi
}

manifest_add_hook() {
    local manifest_json="$1"
    local hook_name="$2"
    local version_hash="$3"
    local dependencies_json="$4"
    local metadata_json="$5"

    jq \
        --arg hook "${hook_name}" \
        --arg version "${version_hash}" \
        --argjson dependencies "${dependencies_json}" \
        --argjson metadata "${metadata_json}" \
        '.hooks[$hook] = {
            version: $version,
            dependencies: $dependencies,
            metadata: $metadata
        }' <<<"${manifest_json}"
}

build_manifest() {
    local build_date
    build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local manifest
    manifest="$(
        jq -n \
            --arg version "1.0.0" \
            --arg date "${build_date}" \
            --arg image "${final_image_ref}" \
            --arg base "${base_image_ref}" \
            --arg commit "${git_commit}" \
            '{
                version: $version,
                build: {
                    date: $date,
                    image: $image,
                    base: $base,
                    commit: $commit
                },
                hooks: {}
            }'
    )"

    local wallpaper_hook="${WALLPAPER_HOOK:-/usr/share/ublue-os/user-setup.hooks.d/10-wallpaper-enforcement.sh}"
    local wallpaper_dir="${WALLPAPER_DIR:-/usr/share/backgrounds/dudley}"
    if [[ -f "${wallpaper_hook}" ]]; then
        local wallpaper_inputs=("${wallpaper_hook}")
        local wallpaper_count=0

        if [[ -d "${wallpaper_dir}" ]]; then
            mapfile -t wallpaper_files < <(find "${wallpaper_dir}" -maxdepth 1 -type f | sort)
            if [[ "${#wallpaper_files[@]}" -gt 0 ]]; then
                wallpaper_inputs+=("${wallpaper_files[@]}")
                wallpaper_count="${#wallpaper_files[@]}"
            fi
        fi

        local wallpaper_hash
        wallpaper_hash="$(compute_content_hash "${wallpaper_inputs[@]}")"
        stamp_hook_version "${wallpaper_hook}" "${wallpaper_hash}"
        local wallpaper_deps
        wallpaper_deps="$(printf '%s\n' "${wallpaper_inputs[@]}" | jq -R . | jq -s .)"
        local wallpaper_meta
        wallpaper_meta="$(jq -n --argjson wallpaper_count "${wallpaper_count}" '{wallpaper_count: $wallpaper_count, changed: true}')"

        manifest="$(manifest_add_hook "${manifest}" "wallpaper" "${wallpaper_hash}" "${wallpaper_deps}" "${wallpaper_meta}")"
    fi

    local vscode_hook="${VSCODE_HOOK:-/usr/share/ublue-os/user-setup.hooks.d/20-dudley-vscode-extensions.sh}"
    local vscode_list="${VSCODE_EXTENSIONS_LIST:-/usr/share/ublue-os/vscode-extensions.list}"
    if [[ -f "${vscode_hook}" ]]; then
        local vscode_inputs=("${vscode_hook}")
        local extension_count=0

        if [[ -f "${vscode_list}" ]]; then
            vscode_inputs+=("${vscode_list}")
            extension_count="$(grep -v '^[[:space:]]*#' "${vscode_list}" | grep -c -v '^[[:space:]]*$' || true)"
        fi
        local vscode_settings
        for vscode_settings in \
            "${VSCODE_CODE_SETTINGS:-/etc/skel/.config/Code/User/settings.json}" \
            "${VSCODE_INSIDERS_SETTINGS:-/etc/skel/.config/Code - Insiders/User/settings.json}"; do
            if [[ -f "${vscode_settings}" ]]; then
                vscode_inputs+=("${vscode_settings}")
            fi
        done

        local vscode_hash
        vscode_hash="$(compute_content_hash "${vscode_inputs[@]}")"
        stamp_hook_version "${vscode_hook}" "${vscode_hash}"
        local vscode_deps
        vscode_deps="$(printf '%s\n' "${vscode_inputs[@]}" | jq -R . | jq -s .)"
        local vscode_meta
        vscode_meta="$(jq -n --argjson extension_count "${extension_count}" '{extension_count: $extension_count, changed: true}')"

        manifest="$(manifest_add_hook "${manifest}" "vscode-extensions" "${vscode_hash}" "${vscode_deps}" "${vscode_meta}")"
    fi

    install -d -m 0755 "$(dirname "${manifest_path}")"
    jq . <<<"${manifest}" > "${manifest_path}"
    chmod 0644 "${manifest_path}"
}

stamp_image_identity() {
    local registry vendor image_name image_tag
    mapfile -t image_parts < <(parse_image_ref "${final_image_ref}")
    registry="${image_parts[0]}"
    vendor="${image_parts[1]}"
    image_name="${image_parts[2]}"
    image_tag="${image_parts[3]}"

    local base_image_name
    if [[ -f "${image_info_path}" ]]; then
        base_image_name="$(jq -r '."base-image-name" // empty' "${image_info_path}")"
    fi
    if [[ -z "${base_image_name:-}" ]]; then
        base_image_name="${base_image_ref##*/}"
        base_image_name="${base_image_name%%[:@]*}"
    fi

    local fedora_version
    if [[ -f "${image_info_path}" ]]; then
        fedora_version="$(jq -r '."fedora-version" // empty' "${image_info_path}")"
    fi
    if [[ -z "${fedora_version:-}" ]]; then
        # shellcheck source=/dev/null
        fedora_version="$(. "${os_release_path}" && printf '%s' "${VERSION_ID:-unknown}")"
    fi

    local image_flavor="dx"
    local existing_image_info='{}'
    if [[ -f "${image_info_path}" ]]; then
        existing_image_info="$(cat "${image_info_path}")"
        image_flavor="$(jq -r '."image-flavor" // "dx"' "${image_info_path}")"
    fi

    install -d -m 0755 "$(dirname "${image_info_path}")"

    jq \
        --arg image_name "${image_name}" \
        --arg image_flavor "${image_flavor}" \
        --arg image_vendor "${vendor}" \
        --arg image_ref "ostree-image-signed:docker://${registry}/${vendor}/${image_name}" \
        --arg image_tag "${image_tag}" \
        --arg base_image_name "${base_image_name}" \
        --arg fedora_version "${fedora_version}" \
        --arg base_image_ref "${base_image_ref}" \
        '. + {
            "image-name": $image_name,
            "image-flavor": $image_flavor,
            "image-vendor": $image_vendor,
            "image-ref": $image_ref,
            "image-tag": $image_tag,
            "base-image-name": $base_image_name,
            "fedora-version": $fedora_version,
            "base-image-ref": $base_image_ref
        }' <<<"${existing_image_info}" > "${image_info_path}"

    if [[ -f "${os_release_path}" ]]; then
        set_os_release_value "VARIANT_ID" "${base_image_name}"
        set_os_release_value "NAME" "Dudley OS"
        set_os_release_value "PRETTY_NAME" "Dudley OS (${image_tag})"
        set_os_release_value "HOME_URL" "${repo_url}"
        set_os_release_value "DOCUMENTATION_URL" "${repo_url}"
        set_os_release_value "SUPPORT_URL" "${support_url}"
        set_os_release_value "BUG_REPORT_URL" "${support_url}"
        set_os_release_value "IMAGE_ID" "${image_name}"
        set_os_release_value "IMAGE_VERSION" "${image_tag}"
        set_os_release_value "BUILD_ID" "${git_commit}"
    fi
}

set_os_release_value() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "${os_release_path}"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${os_release_path}"
    else
        printf '%s="%s"\n' "${key}" "${value}" >> "${os_release_path}"
    fi
}

build_manifest
stamp_image_identity

jq -e '.build.image and .build.base and .build.commit' "${manifest_path}" >/dev/null
"${dudley_build_info_cmd}" --json >/dev/null
jq -e '."image-name" == "dudley-os" and ."image-vendor" == "joshyorko"' "${image_info_path}" >/dev/null
