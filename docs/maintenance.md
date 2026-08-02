# Dudley Maintenance

This guide describes which repository owns each layer of the product image and
how the three published streams are built.

## Ownership boundaries

| Owner | Responsibility |
| --- | --- |
| Project Bluefin | Provides the Stable, Nvidia, and Dakota base images and the inherited platform behavior. |
| `dsb-common` | Owns reusable DSB and Dudley payloads: Brewfiles, Flatpak declarations, wallpapers, shared first-login hooks, the Chrome repository definition, and VS Code extension payloads. |
| `dudley-os` | Owns final product assembly: Containerfiles, copy order, image identity and metadata, baked packages such as Google Chrome, tests, workflows, and Dudley-only local glue. |

`dudleys-second-bedroom` is legacy source material only. Do not revive it for
new Dudley work; move reusable payload to `dsb-common` and retain only final
product assembly in `dudley-os`.

## Where changes belong

| Change | Repository |
| --- | --- |
| Reusable Brewfiles, Flatpak manifests, wallpapers, shared just recipes, Chrome repository definitions, VS Code extension payloads, or shared hooks | `dsb-common` |
| Final image layer order, build-time package installation, final metadata, image-specific tests, or local product glue | `dudley-os` |
| Base-image behavior and upstream platform changes | Project Bluefin |

The Stable and Nvidia product builds copy `dsb-common/shared`, then
`dsb-common/dudley`, then local `dudley-os` product files. Keep that order when
changing final assembly.

## Stream build inputs

| Stream | Workflow | Base and product input |
| --- | --- | --- |
| Stable | `.github/workflows/build.yml` | `Containerfile` on the Project Bluefin Stable base, with the pinned `dsb-common` OCI resource. |
| Nvidia | `.github/workflows/build-nvidia.yml` | `Containerfile` with the workflow's pinned `NVIDIA_BASE_IMAGE_REF` for Project Bluefin Nvidia. |
| Dakota | `.github/workflows/build-dakota.yml` | `Containerfile.dakota` with pinned matrix inputs for matching `dakota` and `dakota-nvidia` file-only overlays. |

Dakota is experimental and does not carry Fedora RPM parity with the Stable and
Nvidia streams. Its product glue maps the Dudley contract to Dakota-native
components: Ghostty, native Podman, the real Docker Engine with Compose and
Buildx copied from a pinned upstream Docker image, signature-verified native
Chrome extracted in a disposable Fedora builder stage, and Homebrew-delivered
developer tools and VS Code Insiders. RPM and DNF do not enter the final Dakota
image.

Publish Dakota images with standard `zstd` compression. Do not use
`zstd:chunked`: Dakota's composefs updater rejects those images with
`Unexpected EOF reading tar entry`.

Installer-media assembly belongs to `joshyorko/dudley-iso`. Keep both Dakota
tags available there: the live environment embeds `dakota-nvidia`, while the
installer selects `dakota` on non-NVIDIA hardware.

## Validation workflows

Pull requests build the image variants without publishing. Default-branch
builds publish only after the workflow's preflight step. Repository validation
also covers the Justfile, ShellCheck, Renovate configuration, and final image
contracts; reusable Brewfile and Flatpak payload validation belongs in
`dsb-common`.

Project Bluefin Actions supplies the runner setup, preflight, push, signing,
and provenance steps used by the three stream workflows.

## Renovate and digest pins

The central `joshyorko/renovate-config` runner manages updates. Keep
repository-specific matching and grouping in `.github/renovate.json5`; do not
add a repository-local Renovate workflow. Renovate updates the pinned OCI
image references and action versions so builds remain reproducible.
Patchraptor dependency PRs pass the skill-drift check without requiring a
documentation-only change; all other implementation PRs retain that gate.

## Publishing, signing, and provenance

On the default branch, each stream workflow pushes to GHCR, signs the image
keylessly through GitHub Actions OIDC, and publishes GitHub provenance
attestations. CI SBOM publication is intentionally disabled
(`generate-sbom: "false"`).

The repository-local Dagger release path is separate from CI and may use
key-based signing for an ad hoc registry when a signing key is provided.

## Supporting repositories and upstream documentation

- [`dsb-common`](https://github.com/joshyorko/dsb-common) contains reusable
  Dudley and DSB payloads.
- [Project Bluefin](https://projectbluefin.io/) documents the inherited base
  images and platform.
- [bootc documentation](https://containers.github.io/bootc/) covers image
  deployment, updates, and rollback behavior.
- [Universal Blue](https://universal-blue.org/) provides broader upstream
  image documentation.
