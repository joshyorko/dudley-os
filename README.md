# dudley-os

A custom bootc operating system image for the DSB organisation, built on the lessons from [Universal Blue](https://universal-blue.org/) and [Bluefin](https://projectbluefin.io). It is designed to be a **thin product image** that consumes shared configuration from [`dsb-common`](https://github.com/joshyorko/dsb-common) and adds Dudley-specific branding and tooling on top.

This image uses a **thin-product multi-stage build**. Dudley inherits the full Bluefin DX base image, then layers in DSB shared configuration plus Dudley-specific payloads on top. See the [Architecture](#architecture) section below for details.

**Dudley now inherits Bluefin DX directly instead of reconstructing Bluefin from Silverblue plus partial layers.** This keeps Bluefin's terminal defaults, image metadata, MOTD tooling, and DX userland intact while still letting `dsb-common` and Dudley apply their opinionated changes.

> Be the one who moves, not the one who is moved.

## What Makes Dudley Different?

Here are the changes from the base image (`ghcr.io/ublue-os/bluefin-dx`). Dudley is assembled from:

### Shared Organisation Layer (dsb-common)
- **`ghcr.io/joshyorko/dsb-common:latest`** is consumed as an OCI layer at build time through the finalized contract paths:
  - `/system_files/shared`
  - `/system_files/dudley`
- Dudley wallpapers now come from `dsb-common` at `/system_files/dudley/usr/share/backgrounds/dudley`.
- Dudley's Google Chrome RPM repository definition now comes from `dsb-common` at `/system_files/dudley/etc/yum.repos.d/google-chrome.repo`.
- Dudley VS Code Insiders assets now come from `dsb-common`, including:
  - `/usr/share/ublue-os/homebrew/dudley-dev.Brewfile`
  - `/usr/share/ublue-os/vscode-extensions.list`
  - `/usr/share/ublue-os/user-setup.hooks.d/20-dudley-vscode-extensions.sh`

### Product-specific Additions (this repo)
- Dudley final-assembly logic in `Containerfile` and `build/10-build.sh`
- Google Chrome is baked into the final image from the shared Dudley RPM repository definition in `dsb-common`; final assembly disables the repo after install so Chrome updates remain image-build controlled
- Dudley final-image metadata generation for `/etc/dudley/build-manifest.json` and `/usr/share/ublue-os/image-info.json`
- Dudley-specific ujust wiring in `custom/ujust/`, delegated to the shared `dsb-common` Dudley runtime commands for Brewfile setup
- Dudley-only local wallpaper enforcement glue in `custom/system_files/`
- Nvidia build workflow based on `ghcr.io/ublue-os/bluefin-dx-nvidia:latest` and published as `ghcr.io/joshyorko/dudley-os:nvidia-latest` plus compatibility tags

### Configuration Changes
- `podman.socket` enabled by default for rootless container workflows
- Stale inherited Bazaar RPM launcher/appstream metadata is removed during final assembly while preserving Bluefin's Flatpak Bazaar preinstall contract, so GNOME does not see duplicate Bazaar entries and Bazaar remains installed
- GLib schemas are compiled after applying the shared Dudley layer so background defaults from `dsb-common` are active in the final image
- First-login setup hooks are stamped with content-derived versions so wallpaper and VS Code payload updates rerun cleanly
- Final runtime image identity is stamped as `ghcr.io/joshyorko/dudley-os:*` so Dudley MOTD/build reporting stays product-correct

*Last updated: 2026-07-06*

---

## What's Included

### Dudley migration checklist

The migration from [`joshyorko/dudleys-second-bedroom`](https://github.com/joshyorko/dudleys-second-bedroom/tree/main) was explicitly audited so Dudley behavior is either preserved here, moved into `dsb-common`, or intentionally retired:

| Legacy area | Status | Dudley-os outcome |
| --- | --- | --- |
| `custom_wallpapers/` | now owned by `dsb-common` | Dudley wallpapers are consumed from `/system_files/dudley/usr/share/backgrounds/dudley`; no local wallpaper assets are kept here |
| `system_files/` shared defaults, Dudley opinion payloads, and runtime wallpaper randomizer files | now owned by `dsb-common` | Shared defaults plus Dudley data payloads are consumed from the shared OCI layer before local product glue |
| `brew/` (`dudley-cli`, `dudley-dev`, `dudley-fonts`, `dudley-k8s`) | now owned by `dsb-common` | Dudley Homebrew manifests are consumed from `dsb-common/dudley/usr/share/ublue-os/homebrew/` rather than local `custom/brew/` data |
| `flatpaks/` | now owned by `dsb-common` | Dudley Flatpak declarative payload is consumed from `dsb-common/dudley/etc/flatpak/preinstall.d/` rather than local `custom/flatpaks/` data |
| `vscode-extensions.list` | now owned by `dsb-common` | Dudley extension payload is consumed from `dsb-common/dudley/usr/share/ublue-os/vscode-extensions.list` |
| `build_files/developer/vscode-insiders.sh` | retired | VS Code Insiders is now a Homebrew cask opinion in `dsb-common` and installs through the Dudley dev Brewfile rather than final image assembly |
| `build_files/user-hooks/10-wallpaper-enforcement.sh` | still owned by `dudley-os` | Preserved as a first-login hook that consumes the shared Dudley wallpaper directory and prefers the shared `dudley-random-wallpaper` runtime when present |
| `build_files/user-hooks/20-vscode-extensions.sh` | now owned by `dsb-common` | Dudley now relies on the shared hook asset at `/usr/share/ublue-os/user-setup.hooks.d/20-dudley-vscode-extensions.sh` and keeps no local duplicate |
| Product-specific package/config logic in `Containerfile`, `Justfile`, `packages.json`, and `build_files/` | mixed | Dudley opinion/data moved to `dsb-common`; final assembly/build glue remains in this repo; the monolithic `packages.json` manifest is intentionally dropped in favor of thin-repo assembly logic. Google Chrome is the current product-level baked package and is installed here using the shared Dudley repo definition from `dsb-common` |

### Build System
- Automated builds via GitHub Actions on every commit
- Dudley Bot self-hosted Renovate runs from GitHub Actions to keep images and actions current
- Automatic cleanup of old images (90+ days) to keep it tidy
- Pull request workflow - test changes before merging to main
  - PRs build and validate before merge
  - `main` branch builds `:stable` images
- Validates your files on pull requests so you never break a build:
  - Justfile, ShellCheck, Renovate config, and final image build checks run here
  - Brewfile and Flatpak payload validation runs in `dsb-common`, where that payload now lives
- Production Grade Features
  - Keyless container signing and GitHub provenance attestations run on `main` publishes
  - CI SBOM publishing is disabled to keep personal image builds fast
- GPU Variant
  - `.github/workflows/build-nvidia.yml` runs on pull requests, main pushes, and GitHub Actions `workflow_dispatch`
  - Pull requests build the Nvidia variant without publishing; main/default-branch publishes, signs, and attests it
  - Publishes Nvidia builds to GHCR with `nvidia`, `nvidia-latest`, `latest-nvidia`, `nvidia-stable`, `stable-nvidia`, and dated Nvidia tags
  - Uses the upstream Bluefin DX Nvidia `latest` image as the base so Nvidia kernel/akmods support stays aligned with Bluefin

### Dudley Bot Renovate

Dependency updates are handled by the central `joshyorko/renovate-config` runner. Repo-specific matching and grouping lives in `.github/renovate.json5`; do not add a repo-local Renovate workflow unless the runner model changes again. The central bot token must be able to read Dependabot/vulnerability alerts and write workflow files so Renovate can update `.github/workflows/**`.

### Homebrew Integration
- Dudley’s shipped Brewfiles are expected from the `dsb-common` Dudley layer at `/usr/share/ublue-os/homebrew/`
- Includes curated collections: CLI utilities, development tools, IDE/editor tools, fonts, Kubernetes tools, and opt-in AI/agent tools. Go nuts.
- Users install packages at runtime with `brew bundle`, aliased to premade `ujust commands`
- See [custom/brew/README.md](custom/brew/README.md) for details

### Flatpak Support
- Dudley’s shipped Flatpak declarative payload is expected from the `dsb-common` Dudley layer at `/etc/flatpak/preinstall.d/`
- Automatically installed on first boot after user setup
- See [custom/flatpaks/README.md](custom/flatpaks/README.md) for details

### ujust Commands
- User-friendly command shortcuts via `ujust`
- Pre-configured examples for app installation and system maintenance for you to customize
- See [custom/ujust/README.md](custom/ujust/README.md) for details

### Build Scripts
- Modular numbered scripts (10-, 20-, 30-) run in order
- Example scripts included for third-party repositories and desktop replacement
- Helper functions for safe COPR usage
- See [build/README.md](build/README.md) for details

## Quick Start

### 1. Create Your Repository

Click "Use this template" to create a new repository from this template.

### 2. Rename the Project

The project name `dudley-os` is already set in all required files. If you fork this for a different product, change it in these 6 files:

1. `Containerfile` (line 4): `# Name: your-repo-name`
2. `Justfile` (line 1): `export image_name := env("IMAGE_NAME", "your-repo-name")`
3. `README.md` (line 1): `# your-repo-name`
4. `artifacthub-repo.yml` (line 5): `repositoryID: your-repo-name`
5. `custom/ujust/README.md` (~line 175): `localhost/your-repo-name:stable`
6. `.github/workflows/clean.yml`: `packages: your-repo-name`

### 3. Enable GitHub Actions

- Go to the "Actions" tab in your repository
- Click "I understand my workflows, go ahead and enable them"

Your first build will start automatically! 

Note: CI publishing uses keyless signing through GitHub Actions OIDC. No cosign private key is needed for the main publish workflow.

### 4. Customize Your Image

Choose your base image in `Containerfile`:
```dockerfile
FROM ghcr.io/ublue-os/bluefin-dx:stable@sha256:...
```

Add your packages in `build/10-build.sh`:
```bash
dnf5 install -y package-name
```

Customize your apps:
- Update Dudley Brewfiles in `dsb-common` under `system_files/dudley/usr/share/ublue-os/homebrew/` ([local guide](custom/brew/README.md))
- Update Dudley Flatpaks in `dsb-common` under `system_files/dudley/etc/flatpak/preinstall.d/` ([local guide](custom/flatpaks/README.md))
- Add ujust commands in `custom/ujust/` ([guide](custom/ujust/README.md))

### 5. Development Workflow

All changes should be made via pull requests:

1. Open a pull request on GitHub with the change you want.
3. The PR will automatically trigger:
   - Build validation
   - Brewfile, Flatpak, Justfile, and shellcheck validation
   - Test image build
4. Once checks pass, merge the PR
5. Merging triggers publishes a `:stable` image

### 6. Deploy Your Image

Switch to your image:
```bash
sudo bootc switch ghcr.io/joshyorko/dudley-os:stable
sudo systemctl reboot
```

## Image Signing and Provenance

Main-branch CI publishes use keyless cosign signing through GitHub Actions OIDC and push GitHub provenance attestations. SBOM generation is disabled in this personal image workflow to avoid spending hosted runner time rescanning a bootc image whose base layers already come from Universal Blue.

### Why Sign Images?

- Verify image authenticity and integrity
- Prevent tampering and supply chain attacks
- Required for some enterprise/security-focused deployments
- Industry best practice for production images

### Verification

Users can verify the published image with the repository's GitHub Actions OIDC identity:

```bash
cosign verify \
  --certificate-identity-regexp "https://github.com/joshyorko/dudley-os/" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/joshyorko/dudley-os:stable
```

The repo-local Dagger release path can still use key-based signing for ad hoc registries when `--signing-key` is provided.

## Love Your Image? Let's Go to Production

Ready to take your custom OS to production? Keep these gates healthy for security, reliability, and performance:

### Production Checklist

- [x] **Enable Image Signing**
  - Provides cryptographic verification of your images
  - Prevents tampering and ensures authenticity
  - Status: **Enabled for main publishes** through keyless GitHub Actions OIDC signing

- [x] **Enable Build Provenance**
  - Publishes GitHub build provenance attestations for the pushed image
  - Provides transparency about how the image was built
  - Status: **Enabled for main publishes** through `projectbluefin/actions/bootc-build/sign-and-publish`

- [ ] **Enable CI SBOM Publishing**
  - Generates Software Bill of Materials for supply chain security
  - Status: **Disabled intentionally** to keep personal image builds fast

- [ ] **Enable Image Rechunking** (Recommended)
  - Optimizes bootc image layers for better update performance
  - Reduces update sizes by 5-10x
  - Improves download resumability with evenly sized layers
  - To enable:
    1. Edit `.github/workflows/build.yml`
    2. Find the "Build Image" step
    3. Add a rechunk step after the build (see example below)
  - Status: **Not enabled by default** (optional optimization)

#### Adding Image Rechunking

After building your bootc image, add a rechunk step before pushing to the registry. Here's an example based on the workflow used by [zirconium-dev/zirconium](https://github.com/zirconium-dev/zirconium):

```yaml
- name: Build image
  id: build
  run: sudo podman build -t "${IMAGE_NAME}:${DEFAULT_TAG}" -f ./Containerfile .

- name: Rechunk Image
  run: |
    sudo podman run --rm --privileged \
      -v /var/lib/containers:/var/lib/containers \
      --entrypoint /usr/libexec/bootc-base-imagectl \
      "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" \
      rechunk --max-layers 96 \
      "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" \
      "localhost/${IMAGE_NAME}:${DEFAULT_TAG}"

- name: Push to Registry
  run: sudo podman push "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" "${IMAGE_REGISTRY}/${IMAGE_NAME}:${DEFAULT_TAG}"
```

Alternative approach using a temporary tag for clarity:

```yaml
- name: Rechunk Image
  run: |
    sudo podman run --rm --privileged \
      -v /var/lib/containers:/var/lib/containers \
      --entrypoint /usr/libexec/bootc-base-imagectl \
      "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" \
      rechunk --max-layers 67 \
      "localhost/${IMAGE_NAME}:${DEFAULT_TAG}" \
      "localhost/${IMAGE_NAME}:${DEFAULT_TAG}-rechunked"
    
    # Tag the rechunked image with the original tag
    sudo podman tag "localhost/${IMAGE_NAME}:${DEFAULT_TAG}-rechunked" "localhost/${IMAGE_NAME}:${DEFAULT_TAG}"
    sudo podman rmi "localhost/${IMAGE_NAME}:${DEFAULT_TAG}-rechunked"
```

**Parameters:**
- `--max-layers`: Maximum number of layers for the rechunked image (typically 67 for optimal balance)
- The first image reference is the source (input)
- The second image reference is the destination (output)
  - When using the same reference for both, the image is rechunked in-place
  - You can also use different tags (e.g., `-rechunked` suffix) and then retag if preferred

**References:**
- [CoreOS rpm-ostree build-chunked-oci documentation](https://coreos.github.io/rpm-ostree/build-chunked-oci/)
- [bootc documentation](https://containers.github.io/bootc/)

### Production Publish Features

Your workflow will:
- Sign published images keylessly with cosign
- Generate and attach SBOMs
- Publish GitHub provenance attestations

Users can verify your images with:
```bash
cosign verify \
  --certificate-identity-regexp "https://github.com/joshyorko/dudley-os/" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/joshyorko/dudley-os:stable
```

## Detailed Guides

- [Homebrew/Brewfiles](custom/brew/README.md) - Runtime package management
- [Flatpak Preinstall](custom/flatpaks/README.md) - GUI application setup
- [ujust Commands](custom/ujust/README.md) - User convenience commands
- [Build Scripts](build/README.md) - Build-time customization

## Architecture

This template now follows a **thin-product Bluefin layering model**. Dudley starts from Bluefin DX directly, then applies DSB shared and Dudley-specific layers during the build.

### Multi-Stage Build Pattern

**Stage 1: Context (ctx)** - Combines resources from multiple sources:
- Local build scripts (`/build`)
- Local custom files (`/custom`)
- **dsb-common** (`ghcr.io/joshyorko/dsb-common:latest`) - Shared DSB organisation layer

**Stage 2: Base Image** - Default:
- `ghcr.io/ublue-os/bluefin-dx:stable` (Bluefin GNOME + DX userland)

### Benefits of This Architecture

- **Modularity**: Compose your image from reusable OCI containers
- **Maintainability**: Update shared components independently
- **Reproducibility**: Renovate automatically updates OCI tags to SHA digests
- **Consistency**: Keep Bluefin's shipped userland intact instead of partially rebuilding it
- **Thin product images**: Common organisation config lives in `dsb-common`; product repos only contain what's unique

### OCI Container Resources

The Containerfile imports files from these OCI containers at build time:

```dockerfile
COPY --from=ghcr.io/joshyorko/dsb-common:latest  /system_files/shared /oci/dsb-common/shared
COPY --from=ghcr.io/joshyorko/dsb-common:latest  /system_files/dudley /oci/dsb-common/dudley
```

Your build scripts can access these files at:
- `/ctx/oci/dsb-common/shared/` - DSB organisation-wide shared files
- `/ctx/oci/dsb-common/dudley/` - Dudley-specific shared-layer content
- `/ctx/custom/system_files/` - Dudley product-only files that stay in this repo

The build order in `build/10-build.sh` is:
1. **dsb-common/shared** (organisation-wide baseline)
2. **dsb-common/dudley** (Dudley shared-layer content such as wallpapers)
3. **Local dudley-os product files** (this repo – remaining local wallpaper glue and final assembly wiring)

**Note**: Renovate automatically updates `:latest` tags to SHA digests for reproducible builds.

VS Code Insiders is installed at runtime through the Dudley dev Brewfile from `dsb-common`; final image assembly no longer downloads or installs the editor RPM.

## Image Publishing

Images are automatically built and pushed to the GitHub Container Registry on every push to `main`:

```
ghcr.io/joshyorko/dudley-os:stable
ghcr.io/joshyorko/dudley-os:stable.YYYYMMDD
ghcr.io/joshyorko/dudley-os:YYYYMMDD
```

Pull requests build a test image tagged `:pr-<number>` but **do not** push to the registry.

To deploy on a running bootc system:

```bash
sudo bootc switch ghcr.io/joshyorko/dudley-os:stable
sudo systemctl reboot
```

## Local Testing

Test your changes before pushing:

```bash
just build              # Build container image locally
just build-qcow2        # Build QCOW2 VM disk image
just run-vm-qcow2       # Launch image in a browser-based VM
```

### Local Dagger Helpers

The repo-local Dagger module is for local and ad hoc portable runs. GitHub
Actions keeps its separate workflow in `.github/workflows/build.yml`; CI does
not call Dagger.

```bash
dagger functions
dagger call metadata
dagger call release --publish=false
```

Shortcuts are available through `just`:

```bash
just dagger-metadata
just dagger-build
just dagger-release-dry-run
just dagger-publish-local
just dagger-release
```

Run the local release path against GHCR after authenticating with a token:

```bash
dagger call release \
  --registry ghcr.io/joshyorko \
  --registry-username "$GITHUB_ACTOR" \
  --registry-password env:GITHUB_TOKEN \
  --signing-key env:SIGNING_SECRET \
  --signing-password env:SIGNING_PASSWORD \
  --source-uri https://github.com/joshyorko/dudley-os
```

Try another registry without code changes:

```bash
dagger call release --registry registry.gitlab.com/group --publish=false
dagger call release --registry localhost:5000 --sign=false --attest=false
```

The Dagger module exposes `metadata`, `build`, `publish`, `sbom`,
`attest-sbom`, `attest-provenance`, `sign`, and `release`. It uses Buildah
from `quay.io/buildah/stable:v1.41`, builds this repo's Docker-format
`Containerfile`, keeps the pinned Bluefin base image and pinned `dsb-common`
OCI resource from the Containerfile, applies the OCI labels, plans `stable`,
`stable.YYYYMMDD`, and `YYYYMMDD` tags, generates a Trivy SPDX JSON SBOM, and
can use cosign for key-based signing and SBOM/SLSA provenance attestations when
`--signing-key` is provided. Loopback registries (`localhost`, `127.0.0.1`, and
`[::1]`) publish with `--tls-verify=false`; all other registries use TLS
verification.

Full workflow:

```bash
just build && just build-qcow2 && just run-vm-qcow2
```

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion](https://github.com/bootc-dev/bootc/discussions)

## Learn More

- [Universal Blue Documentation](https://universal-blue.org/)
- [bootc Documentation](https://containers.github.io/bootc/)
- [Video Tutorial by TesterTech](https://www.youtube.com/watch?v=IxBl11Zmq5wE)

## Security

This template provides security features for production use:
- SBOM generation (Software Bill of Materials) for supply chain transparency
- Keyless image signing with cosign for cryptographic verification
- Automated security updates via Renovate
- Build provenance tracking
