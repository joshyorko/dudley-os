#!/usr/bin/env bash

set -euo pipefail

final_image_ref="${FINAL_IMAGE_REF:-ghcr.io/joshyorko/dudley-os:stable}"
base_image_ref="${BASE_IMAGE_REF:-ghcr.io/ublue-os/bluefin-dx:latest}"
git_commit="${SHA_HEAD_SHORT:-unknown}"

manifest_path="/etc/dudley/build-manifest.json"
image_info_path="/usr/share/ublue-os/image-info.json"
os_release_path="/usr/lib/os-release"
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

    local wallpaper_hook="/usr/share/ublue-os/user-setup.hooks.d/10-wallpaper-enforcement.sh"
    if [[ -f "${wallpaper_hook}" ]]; then
        local wallpaper_inputs=("${wallpaper_hook}")
        local wallpaper_count=0

        if [[ -d /usr/share/backgrounds/dudley ]]; then
            mapfile -t wallpaper_files < <(find /usr/share/backgrounds/dudley -maxdepth 1 -type f | sort)
            if [[ "${#wallpaper_files[@]}" -gt 0 ]]; then
                wallpaper_inputs+=("${wallpaper_files[@]}")
                wallpaper_count="${#wallpaper_files[@]}"
            fi
        fi

        local wallpaper_hash
        wallpaper_hash="$(compute_content_hash "${wallpaper_inputs[@]}")"
        local wallpaper_deps
        wallpaper_deps="$(printf '%s\n' "${wallpaper_inputs[@]}" | jq -R . | jq -s .)"
        local wallpaper_meta
        wallpaper_meta="$(jq -n --argjson wallpaper_count "${wallpaper_count}" '{wallpaper_count: $wallpaper_count, changed: true}')"

        manifest="$(manifest_add_hook "${manifest}" "wallpaper" "${wallpaper_hash}" "${wallpaper_deps}" "${wallpaper_meta}")"
    fi

    local vscode_hook="/usr/share/ublue-os/user-setup.hooks.d/20-dudley-vscode-extensions.sh"
    local vscode_list="/usr/share/ublue-os/vscode-extensions.list"
    if [[ -f "${vscode_hook}" ]]; then
        local vscode_inputs=("${vscode_hook}")
        local extension_count=0

        if [[ -f "${vscode_list}" ]]; then
            vscode_inputs+=("${vscode_list}")
            extension_count="$(grep -v '^[[:space:]]*#' "${vscode_list}" | grep -c -v '^[[:space:]]*$' || true)"
        fi

        local vscode_hash
        vscode_hash="$(compute_content_hash "${vscode_inputs[@]}")"
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
        # shellcheck disable=SC1091
        fedora_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")"
    fi

    local image_flavor="dx"
    local existing_image_info='{}'
    if [[ -f "${image_info_path}" ]]; then
        existing_image_info="$(cat "${image_info_path}")"
        image_flavor="$(jq -r '."image-flavor" // "dx"' "${image_info_path}")"
    fi

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
        sed -i "s/^VARIANT_ID=.*/VARIANT_ID=${image_name}/" "${os_release_path}"
        sed -i 's/^NAME=.*/NAME="Dudley OS"/' "${os_release_path}"
        sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"Dudley OS (${image_tag})\"/" "${os_release_path}"
        sed -i "s|^HOME_URL=.*|HOME_URL=\"${repo_url}\"|" "${os_release_path}"
        sed -i "s|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL=\"${repo_url}\"|" "${os_release_path}"
        sed -i "s|^SUPPORT_URL=.*|SUPPORT_URL=\"${support_url}\"|" "${os_release_path}"
        sed -i "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"${support_url}\"|" "${os_release_path}"

        if grep -q '^IMAGE_ID=' "${os_release_path}"; then
            sed -i "s/^IMAGE_ID=.*/IMAGE_ID=\"${image_name}\"/" "${os_release_path}"
        else
            echo "IMAGE_ID=\"${image_name}\"" >> "${os_release_path}"
        fi

        if grep -q '^IMAGE_VERSION=' "${os_release_path}"; then
            sed -i "s/^IMAGE_VERSION=.*/IMAGE_VERSION=\"${image_tag}\"/" "${os_release_path}"
        else
            echo "IMAGE_VERSION=\"${image_tag}\"" >> "${os_release_path}"
        fi

        if grep -q '^BUILD_ID=' "${os_release_path}"; then
            sed -i "s/^BUILD_ID=.*/BUILD_ID=\"${git_commit}\"/" "${os_release_path}"
        else
            echo "BUILD_ID=\"${git_commit}\"" >> "${os_release_path}"
        fi
    fi
}

build_manifest
stamp_image_identity

jq -e '.build.image and .build.base and .build.commit' "${manifest_path}" >/dev/null
/usr/bin/dudley-build-info --json >/dev/null
jq -e '."image-name" == "dudley-os" and ."image-vendor" == "joshyorko"' "${image_info_path}" >/dev/null
