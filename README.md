# dudley-os

A custom bootc operating system image for the DSB organisation, built on the lessons from [Universal Blue](https://universal-blue.org/) and [Bluefin](https://projectbluefin.io). It is designed to be a **thin product image** that consumes shared configuration from [`dsb-common`](https://github.com/joshyorko/dsb-common) and adds Dudley-specific branding and tooling on top.

This image uses the **multi-stage build architecture** from @projectbluefin/distroless, combining resources from multiple OCI containers for modularity and maintainability. See the [Architecture](#architecture) section below for details.

**Unlike previous templates, you are not modifying Bluefin and making changes.**: You are assembling your own Bluefin in the same exact way that Bluefin, Aurora, and Bluefin LTS are built. This keeps the image-agnostic and desktop things we love about Bluefin in @projectbluefin/common, and the organisation-wide things in `dsb-common`.

> Be the one who moves, not the one who is moved.

## What Makes Dudley Different?

Here are the changes from the base image (`ghcr.io/ublue-os/silverblue-main`). Dudley is assembled from:

### Shared Organisation Layer (dsb-common)
- **`ghcr.io/joshyorko/dsb-common:latest`** is consumed as an OCI layer at build time through the finalized contract paths:
  - `/system_files/shared`
  - `/system_files/dudley`
- Dudley wallpapers now come from `dsb-common` at `/system_files/dudley/usr/share/backgrounds/dudley`.

### Product-specific Additions (this repo)
- Dudley final-assembly logic in `Containerfile` and `build/10-build.sh`
- Dudley-specific ujust wiring in `custom/ujust/`
- Dudley-only first-login hooks and VS Code Insiders substrate glue in `custom/system_files/` and `build/10-build.sh`

### Configuration Changes
- `podman.socket` enabled by default for rootless container workflows

*Last updated: 2026-03-23*

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
| `build_files/developer/vscode-insiders.sh` | still owned by `dudley-os` | Preserved as substrate-specific build glue in `build/10-build.sh`, with `Justfile`/`Containerfile` cache busting so `just build` refreshes the latest Insiders RPM |
| `build_files/user-hooks/10-wallpaper-enforcement.sh` | still owned by `dudley-os` | Preserved as a first-login hook that consumes the shared Dudley wallpaper directory and prefers the shared `dudley-random-wallpaper` runtime when present |
| `build_files/user-hooks/20-vscode-extensions.sh` | still owned by `dudley-os` | Preserved as a first-login VS Code Insiders extension installer that activates the shared Dudley extension list when present |
| Product-specific package/config logic in `Containerfile`, `Justfile`, `packages.json`, and `build_files/` | mixed | Dudley opinion/data moved to `dsb-common`; final assembly/build glue remains in this repo; the monolithic `packages.json` manifest is intentionally dropped in favor of thin-repo assembly logic |

### Build System
- Automated builds via GitHub Actions on every commit
- Awesome self hosted Renovate setup that keeps all your images and actions up to date.
- Automatic cleanup of old images (90+ days) to keep it tidy
- Pull request workflow - test changes before merging to main
  - PRs build and validate before merge
  - `main` branch builds `:stable` images
- Validates your files on pull requests so you never break a build:
  - Brewfile, Justfile, ShellCheck, Renovate config, and it'll even check to make sure the flatpak you add exists on FlatHub
- Production Grade Features
  - Container signing and SBOM Generation
  - See checklist below to enable these as they take some manual configuration

### Homebrew Integration
- Dudley’s shipped Brewfiles are expected from the `dsb-common` Dudley layer at `/usr/share/ublue-os/homebrew/`
- Includes curated collections: development tools, fonts, CLI utilities. Go nuts.
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
6. `.github/workflows/clean.yml` (line 23): `packages: your-repo-name`

### 3. Enable GitHub Actions

- Go to the "Actions" tab in your repository
- Click "I understand my workflows, go ahead and enable them"

Your first build will start automatically! 

Note: Image signing is disabled by default. Your images will build successfully without any signing keys. Once you're ready for production, see "Optional: Enable Image Signing" below.

### 4. Customize Your Image

Choose your base image in `Containerfile` (line 23):
```dockerfile
FROM ghcr.io/ublue-os/bluefin:stable
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

## Optional: Enable Image Signing

Image signing is disabled by default to let you start building immediately. However, signing is strongly recommended for production use.

### Why Sign Images?

- Verify image authenticity and integrity
- Prevent tampering and supply chain attacks
- Required for some enterprise/security-focused deployments
- Industry best practice for production images

### Setup Instructions

1. Generate signing keys:
```bash
cosign generate-key-pair
```

This creates two files:
- `cosign.key` (private key) - Keep this secret
- `cosign.pub` (public key) - Commit this to your repository

2. Add the private key to GitHub Secrets:
   - Copy the entire contents of `cosign.key`
   - Go to your repository on GitHub
   - Navigate to Settings → Secrets and variables → Actions ([GitHub docs](https://docs.github.com/en/actions/security-guides/encrypted-secrets#creating-encrypted-secrets-for-a-repository))
   - Click "New repository secret"
   - Name: `SIGNING_SECRET`
   - Value: Paste the entire contents of `cosign.key`
   - Click "Add secret"

3. Replace the contents of `cosign.pub` with your public key:
   - Open `cosign.pub` in your repository
   - Replace the placeholder with your actual public key
   - Commit and push the change

4. Enable signing in the workflow:
   - Edit `.github/workflows/build.yml`
   - Find the "OPTIONAL: Image Signing with Cosign" section.
   - Uncomment the steps to install Cosign and sign the image (remove the `#` from the beginning of each line in that section).
   - Commit and push the change

5. Your next build will produce signed images!

Important: Never commit `cosign.key` to the repository. It's already in `.gitignore`.

## Love Your Image? Let's Go to Production

Ready to take your custom OS to production? Enable these features for enhanced security, reliability, and performance:

### Production Checklist

- [ ] **Enable Image Signing** (Recommended)
  - Provides cryptographic verification of your images
  - Prevents tampering and ensures authenticity
  - See "Optional: Enable Image Signing" section above for setup instructions
  - Status: **Disabled by default** to allow immediate testing

- [ ] **Enable SBOM Attestation** (Recommended)
  - Generates Software Bill of Materials for supply chain security
  - Provides transparency about what's in your image
  - Requires image signing to be enabled first
  - To enable:
    1. First complete image signing setup above
    2. Edit `.github/workflows/build.yml`
    3. Find the "OPTIONAL: SBOM Attestation" section around line 232
    4. Uncomment the "Add SBOM Attestation" step
    5. Commit and push
  - Status: **Disabled by default** (requires signing first)

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

### After Enabling Production Features

Your workflow will:
- Sign all images with your key
- Generate and attach SBOMs
- Provide full supply chain transparency

Users can verify your images with:
```bash
cosign verify --key cosign.pub ghcr.io/joshyorko/dudley-os:stable
```

## Detailed Guides

- [Homebrew/Brewfiles](custom/brew/README.md) - Runtime package management
- [Flatpak Preinstall](custom/flatpaks/README.md) - GUI application setup
- [ujust Commands](custom/ujust/README.md) - User convenience commands
- [Build Scripts](build/README.md) - Build-time customization

## Architecture

This template follows the **multi-stage build architecture** from @projectbluefin/distroless, as documented in the [Bluefin Contributing Guide](https://docs.projectbluefin.io/contributing/).

### Multi-Stage Build Pattern

**Stage 1: Context (ctx)** - Combines resources from multiple sources:
- Local build scripts (`/build`)
- Local custom files (`/custom`)
- **@projectbluefin/common** - Desktop configuration shared with Aurora
- **@projectbluefin/branding** - Branding assets
- **@ublue-os/artwork** - Artwork shared with Aurora and Bazzite
- **@ublue-os/brew** - Homebrew integration
- **dsb-common** (`ghcr.io/joshyorko/dsb-common:latest`) - Shared DSB organisation layer

**Stage 2: Base Image** - Default options:
- `ghcr.io/ublue-os/silverblue-main:latest` (Fedora-based, default)
- `quay.io/centos-bootc/centos-bootc:stream10` (CentOS-based alternative)

### Benefits of This Architecture

- **Modularity**: Compose your image from reusable OCI containers
- **Maintainability**: Update shared components independently
- **Reproducibility**: Renovate automatically updates OCI tags to SHA digests
- **Consistency**: Share components across Bluefin, Aurora, and custom images
- **Thin product images**: Common organisation config lives in `dsb-common`; product repos only contain what's unique

### OCI Container Resources

The Containerfile imports files from these OCI containers at build time:

```dockerfile
COPY --from=ghcr.io/projectbluefin/common:latest /system_files /oci/common
COPY --from=ghcr.io/ublue-os/brew:latest         /system_files /oci/brew
COPY --from=ghcr.io/joshyorko/dsb-common:latest  /system_files/shared /oci/dsb-common/shared
COPY --from=ghcr.io/joshyorko/dsb-common:latest  /system_files/dudley /oci/dsb-common/dudley
```

Your build scripts can access these files at:
- `/ctx/oci/common/` - Shared desktop configuration
- `/ctx/oci/brew/` - Homebrew integration files
- `/ctx/oci/dsb-common/shared/` - DSB organisation-wide shared files
- `/ctx/oci/dsb-common/dudley/` - Dudley-specific shared-layer content
- `/ctx/custom/system_files/` - Dudley product-only files that stay in this repo

The build order in `build/10-build.sh` is:
1. **dsb-common/shared** (organisation-wide baseline)
2. **projectbluefin/common** (`shared`, then `bluefin`)
3. **dsb-common/dudley** (Dudley shared-layer content such as wallpapers)
4. **Local dudley-os product files** (this repo – first-login hooks, VS Code Insiders substrate glue, and local final-assembly wiring)

**Note**: Renovate automatically updates `:latest` tags to SHA digests for reproducible builds.

The `just build` flow also passes a `VSCODE_REFRESH_TOKEN` build arg so the Dudley-only VS Code Insiders install step stays fresh without moving that substrate-specific glue into `dsb-common`.

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
- Optional SBOM generation (Software Bill of Materials) for supply chain transparency
- Optional image signing with cosign for cryptographic verification
- Automated security updates via Renovate
- Build provenance tracking

These security features are disabled by default to allow immediate testing. When you're ready for production, see the "Love Your Image? Let's Go to Production" section above to enable them.
