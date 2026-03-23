###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: dudley-os
#
# IMPORTANT: Change "dudley-os" above to your desired project name.
# This name should be used consistently throughout the repository in:
#   - Justfile: export image_name := env("IMAGE_NAME", "your-name-here")
#   - README.md: # your-name-here (title)
#   - artifacthub-repo.yml: repositoryID: your-name-here
#   - custom/ujust/README.md: localhost/your-name-here:stable (in bootc switch example)
#
# The project name defined here is the single source of truth for your
# custom image's identity. When changing it, update all references above
# to maintain consistency.
###############################################################################

###############################################################################
# MULTI-STAGE BUILD ARCHITECTURE
###############################################################################
# This Containerfile follows a thin-product layering pattern. Dudley inherits
# from Bluefin DX directly, then applies DSB shared/product layers on top:
#
# 1. Context Stage (ctx) - Combines resources from:
#    - Local build scripts and custom files
#    - DSB shared OCI layer
#    - Dudley product OCI layer
#
# 2. Base Image:
#    - `ghcr.io/ublue-os/bluefin-dx:latest` (Bluefin GNOME + DX userland)
#
# See: https://docs.projectbluefin.io/contributing/ for architecture diagram
###############################################################################

# Context stage - combine local and imported OCI container resources
FROM scratch AS ctx

COPY build /build
COPY custom /custom
# Shared DSB organisation layer – product-agnostic configs consumed by all DSB images
COPY --from=ghcr.io/joshyorko/dsb-common:latest /system_files/shared /oci/dsb-common/shared
COPY --from=ghcr.io/joshyorko/dsb-common:latest /system_files/dudley /oci/dsb-common/dudley

# Base Image - inherit Bluefin DX directly so Bluefin userland, shell, MOTD,
# image metadata, and developer tooling stay internally consistent.
FROM ghcr.io/ublue-os/bluefin-dx:latest@sha256:c5cd234aa491c908beaf1626f5091f27a3e644722b5530a9265fe39008d5f187

# Dudley product-specific build args
ARG SHA_HEAD_SHORT="unknown"
ARG VSCODE_REFRESH_TOKEN="static"

## Alternative base images (uncomment to use):
# FROM ghcr.io/ublue-os/bluefin:latest
# FROM ghcr.io/ublue-os/base-main:latest    
# FROM quay.io/centos-bootc/centos-bootc:stream10

## Alternative GNOME OS base image (uncomment to use):
# FROM quay.io/gnome_infrastructure/gnome-build-meta:gnomeos-nightly

### /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## Make modifications desired in your image and install packages by modifying the build scripts.
## The following RUN directive mounts the ctx stage which includes:
##   - Local build scripts from /build
##   - Local custom files from /custom
##   - Files from dsb-common at /oci/dsb-common/shared and /oci/dsb-common/dudley
## `build/10-build.sh` applies these layers in order:
##   1. dsb-common/shared
##   2. dsb-common/dudley
##   3. local dudley-os product files
## Final assembly invokes the shared Dudley VS Code Insiders installer asset
## from dsb-common rather than keeping the install logic inline here.
## Scripts are run in numerical order (10-build.sh, 20-example.sh, etc.)

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    echo "[dudley-vscode] Refresh token: ${VSCODE_REFRESH_TOKEN}" && \
    /ctx/build/10-build.sh
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
