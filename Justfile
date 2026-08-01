export image_name := env("IMAGE_NAME", "dudley-os")
export default_tag := env("DEFAULT_TAG", "stable")
export containerfile := env("CONTAINERFILE", "./Containerfile")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest@sha256:2b52843ea2bfda73b0a08d97e76b734393b1d3a804681b9fabb26723bd3a2f0b")
export dagger_registry := env("DAGGER_REGISTRY", "ghcr.io/joshyorko")
export dagger_local_registry := env("LOCAL_REGISTRY", "localhost:5000")
export dagger_registry_username := env("REGISTRY_USERNAME", "")
export dagger_registry_password_env := env("REGISTRY_PASSWORD_ENV", "REGISTRY_PASSWORD")
export dagger_signing_key_env := env("SIGNING_KEY_ENV", "SIGNING_SECRET")
export dagger_signing_password_env := env("SIGNING_PASSWORD_ENV", "SIGNING_PASSWORD")
export source_uri := env("SOURCE_URI", "https://github.com/joshyorko/dudley-os")
just := just_executable()

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Run unit tests
[group('Test')]
test-unit:
    #!/usr/bin/bash
    set -euo pipefail
    bash tests/test-base-image-contract.sh
    bash tests/test-bazaar-flatpak-contract.sh
    bash tests/test-bootc-account-contract.sh
    bash tests/test-dx-runtime-contract.sh
    bash tests/test-google-chrome-layout.sh
    bash tests/test-final-metadata.sh
    bash tests/test-dakota-variant-contract.sh
    bash tests/test-nvidia-variant-contract.sh
    bash tests/test-publish-workflow-contract.sh
    npm run test:cards

# Run validation and unit tests
[group('Test')]
test: check test-unit

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -f output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: $image_name).
#   $tag - The tag for the image (default: $default_tag).
#
# The script constructs the version string using the tag and the current date.
# If the git working directory is clean, it also includes the short SHA of the current HEAD.
#
# just build $target_image $tag
#
# Example usage:
#   just build aurora lts
#
# This will build an image 'aurora:lts' with DX and GDX enabled.
#

# Build the image using the specified parameters
build $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail

    BUILD_ARGS=()
    FINAL_IMAGE_REF="${METADATA_IMAGE:-ghcr.io/joshyorko/${image_name}}:${tag}"

    if [[ -n "${GITHUB_SHA:-}" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=${GITHUB_SHA:0:7}")
    elif git rev-parse --git-dir >/dev/null 2>&1; then
        GIT_SHA=$(git rev-parse --short HEAD)
        if [[ -n "$(git status -s)" ]]; then
            GIT_SHA="${GIT_SHA}-dirty"
        fi
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=${GIT_SHA}")
    fi

    if [[ -n "${BASE_IMAGE_REF:-}" ]]; then
        BUILD_ARGS+=("--build-arg" "BASE_IMAGE_REF=${BASE_IMAGE_REF}")
    fi

    BUILD_ARGS+=("--build-arg" "FINAL_IMAGE_REF=${FINAL_IMAGE_REF}")
    BUILD_ARGS+=("--build-arg" "VSCODE_REFRESH_TOKEN=$(date -u +%Y%m%d%H%M%S)")

    LABEL_ARGS=()
    while IFS= read -r label; do
        if [[ -n "${label}" ]]; then
            LABEL_ARGS+=("--label" "${label}")
        fi
    done <<< "${OCI_LABELS:-}"

    if [[ "${BUILD_FORMAT:-}" == "docker" ]]; then
        BUILD_ARGS+=("--format" "docker")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        "${LABEL_ARGS[@]}" \
        --pull=newer \
        --file "{{ containerfile }}" \
        --tag "${target_image}:${tag}" \
        .

# Build the experimental Dakota container image
[group('Image')]
build-dakota:
    #!/usr/bin/env bash
    set -euo pipefail

    CONTAINERFILE=./Containerfile.dakota "{{ just }}" build "dudley-os" "dakota"

# Build the Dakota container image and its correctly targeted installer ISO
[group('Build Virtal Machine Image')]
build-dakota-iso: build-dakota
    env -u SSH_ASKPASS {{ just }} _build-bib localhost/dudley-os dakota iso iso/dakota.toml

# Build the image for GitHub Actions in rootful container storage
[group('Image')]
build-ghcr $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "${UID}" -gt "0" ]]; then
        echo "Must run with sudo or as root."
        exit 1
    fi

    BUILD_FORMAT=docker "{{ just }}" build "${target_image}" "${tag}"

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    # Try to resolve the image tag using podman inspect
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            # If the image ID is not found or different from user, copy the image from user podman to root podman
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # If the image is not found, pull it from the repository
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: iso/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 iso/disk.toml
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)

    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}"

    mkdir -p output
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: iso/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 iso/disk.toml
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "iso/disk.toml")

# Build a RAW virtual machine image
[group('Build Virtal Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "iso/disk.toml")

# Build an ISO virtual machine image
[group('Build Virtal Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "iso" "iso/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "iso/disk.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "iso/disk.toml")

# Rebuild an ISO virtual machine image
[group('Build Virtal Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "iso" "iso/iso.toml")

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Run the VM and open the browser to connect
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "iso/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "iso/disk.toml")

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "iso" "iso/iso.toml")

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

[group('Cards')]
cards:
    npm run cards

[group('Cards')]
cards-check:
    npm run cards:check

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'

# Show repo-local Dagger functions
[group('Dagger')]
dagger-functions:
    dagger functions

# Show Dagger release metadata and tag plan
[group('Dagger')]
dagger-metadata registry=dagger_registry image=image_name stable=default_tag source=source_uri:
    dagger call metadata --registry "{{ registry }}" --image-name "{{ image }}" --stable-tag "{{ stable }}" --source-uri "{{ source }}"

# Run Dagger planner unit tests
[group('Dagger')]
dagger-test:
    docker run --rm -v "$PWD/.dagger:/src" -w /src golang:1.26 go test pipeline_plan.go pipeline_plan_test.go

# Build with Dagger without publishing
[group('Dagger')]
dagger-build registry=dagger_registry image=image_name stable=default_tag:
    dagger call build --registry "{{ registry }}" --image-name "{{ image }}" --stable-tag "{{ stable }}"

# Run the Dagger release planner without publishing
[group('Dagger')]
dagger-release-dry-run registry=dagger_registry image=image_name stable=default_tag source=source_uri:
    dagger call release --registry "{{ registry }}" --image-name "{{ image }}" --stable-tag "{{ stable }}" --source-uri "{{ source }}" --publish=false

# Publish to a local OCI registry without signing or attestations
[group('Dagger')]
dagger-publish-local registry=dagger_local_registry image=image_name stable=default_tag source=source_uri:
    dagger call release --registry "{{ registry }}" --image-name "{{ image }}" --stable-tag "{{ stable }}" --source-uri "{{ source }}" --sign=false --attest=false

# Run the full local Dagger release path. Set REGISTRY_PASSWORD for private registries.
[group('Dagger')]
dagger-release registry=dagger_registry image=image_name stable=default_tag username=dagger_registry_username password_env=dagger_registry_password_env source=source_uri signing_key_env=dagger_signing_key_env signing_password_env=dagger_signing_password_env:
    #!/usr/bin/env bash
    set -euo pipefail

    args=(
        release
        --registry "{{ registry }}"
        --image-name "{{ image }}"
        --stable-tag "{{ stable }}"
        --source-uri "{{ source }}"
    )

    if [[ -n "{{ username }}" ]]; then
        args+=(--registry-username "{{ username }}")
    fi

    password_var="{{ password_env }}"
    if [[ -n "${!password_var:-}" ]]; then
        args+=(--registry-password "env:${password_var}")
    fi

    signing_key_var="{{ signing_key_env }}"
    signing_password_var="{{ signing_password_env }}"
    if [[ -n "${!signing_key_var:-}" ]]; then
        args+=(--signing-key "env:${signing_key_var}")
        if [[ -n "${!signing_password_var:-}" ]]; then
            args+=(--signing-password "env:${signing_password_var}")
        fi
    else
        args+=(--sign=false --attest=false)
    fi

    dagger call "${args[@]}"
