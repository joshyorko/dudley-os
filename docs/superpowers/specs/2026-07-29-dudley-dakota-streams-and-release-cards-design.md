# Dudley Dakota Stream and Release Cards Design

Date: 2026-07-29
Status: Approved for implementation

## Summary

Dudley will publish three sibling bootc streams from this repository:

1. **Dudley Stable** — `ghcr.io/joshyorko/dudley-os:stable`
2. **Dudley NVIDIA** — `ghcr.io/joshyorko/dudley-os:nvidia`
3. **Dudley Dakota** — `ghcr.io/joshyorko/dudley-os:dakota`

All three images, all three raptor assets, all six light/dark release cards,
their workflows, tests, and documentation belong in `dudley-os`.
`dudley-factory` is not part of this design and must not be read, changed,
built, or referenced by the implementation.

Stable and NVIDIA keep their existing Project Bluefin production paths.
Dakota is a new sibling stream built by applying a deliberately limited,
file-only Dudley overlay to upstream Project Bluefin Dakota. It is not Fedora
44, does not use Fedora package layering, and does not share the normal Dudley
build script.

## Confirmed Decisions

- The public image repository remains `ghcr.io/joshyorko/dudley-os`.
- The canonical user-facing stream tags are exactly `stable`, `nvidia`, and
  `dakota`. Existing NVIDIA compatibility aliases remain published but are not
  used by cards or switch instructions.
- `latest` is not a documented switch target.
- Dakota is based on a digest-pinned
  `ghcr.io/projectbluefin/dakota:stable`.
- The initial Dakota stream is experimental and must not be described as a
  proven daily driver until boot, update, rollback, and switch-back have been
  exercised on real hardware.
- Each stream has its own approved Dudley raptor.
- Cards follow Project Bluefin's compact 800-by-300 visual language, but use
  original Dudley characters and text.
- Generated card PNGs are committed and displayed directly in `README.md`.

## Goals

- Make Dakota a real, signed Dudley stream that can be switched to with bootc.
- Keep Stable and NVIDIA unchanged as dependable fallbacks.
- Let Dakota expose the practical differences of a distroless GNOME OS system
  without pretending Fedora packages or Bluefin DX components exist.
- Preserve compatible Dudley appearance, wallpapers, Flatpak declarations,
  Homebrew manifests, user commands, and product metadata.
- Give Stable, NVIDIA, and Dakota distinct, related visual identities.
- Make the six README cards reproducible from checked-in inputs.
- Add focused contracts that fail when stream names, bases, tags, metadata,
  assets, or README links drift.

## Non-goals

- Move any work to `dudley-factory`.
- Build Dakota with BuildStream inside this repository.
- Treat Dakota's Fedora platform marker as proof that Dakota is Fedora-based.
- Run `dnf5`, `dnf`, `rpm`, or Chrome RPM installation in the Dakota path.
- Recreate Bluefin's Fedora DX package set in Dakota.
- Add a Dakota NVIDIA stream in this milestone.
- Change the current Stable or NVIDIA base-image and tag contracts.
- Call a successful container build proof of boot, update, rollback, NVIDIA
  support, or daily-driver readiness.
- Automatically publish generated card updates from CI.

## Repository Ownership

`dudley-os` owns:

- the existing `Containerfile` for Stable and NVIDIA
- the new `Containerfile.dakota`
- `build/10-dakota.sh`
- the existing shared final-metadata script
- all three build workflows
- all stream contract tests
- the card generator and its pinned Node dependencies
- the three normalized raptor PNGs
- the six generated card PNGs
- the README stream catalog

`dsb-common` remains the existing pinned OCI input for reusable Dudley payload.
Using that input does not move image ownership out of this repository.
The Dakota build consumes only a compatibility-safe subset of it.

`dudley-factory` has no role.

## Stream Architecture

| Stream | Base | Assembly | Public tag |
| --- | --- | --- | --- |
| Stable | `ghcr.io/projectbluefin/bluefin:stable@sha256:...` | existing `Containerfile` and `build/10-build.sh` | `stable` |
| NVIDIA | `ghcr.io/projectbluefin/bluefin-nvidia:stable@sha256:...` | existing `Containerfile` and `build/10-build.sh` | `nvidia` |
| Dakota | `ghcr.io/projectbluefin/dakota:stable@sha256:5989c44875101aaf8928f36360c8434f90ca485cb67d07ec07d7196c44a61f6c` | `Containerfile.dakota` and `build/10-dakota.sh` | `dakota` |

The Dakota digest above was verified from GHCR on 2026-07-29. Renovate owns
future digest refreshes; tests validate the repository, `stable` channel, and
64-character digest shape rather than freezing this historical digest forever.

## Dakota Base Contract

Live inspection of `ghcr.io/projectbluefin/dakota:stable` established:

- present: bootc, ujust, Podman, rsync, jq, dconf/GLib tooling, and systemd
- absent: dnf5, RPM, Docker, and a Homebrew executable

These facts create a hard architecture boundary. The existing
`build/10-build.sh`, Chrome RPM installation, Fedora DX restoration, Docker
service setup, libvirt workarounds, and package-manager cleanup must not run in
the Dakota build.

### `Containerfile.dakota`

The Dakota Containerfile:

- imports the same pinned `dsb-common` shared and Dudley OCI payload used by the
  product
- copies only the Dakota build scripts and compatible local files into its
  context stage
- inherits the digest-pinned Dakota `stable` image
- accepts `BASE_IMAGE_REF`, `FINAL_IMAGE_REF`, and `SHA_HEAD_SHORT`
- runs only `build/10-dakota.sh`
- finishes with `bootc container lint`

The normal `Containerfile` remains unchanged except for cross-stream interfaces
that are truly shared.

### `build/10-dakota.sh`

The Dakota build script is file-only. It must never call a package manager.

It copies these reusable Dudley areas when present:

- dconf and GLib schema overrides
- Flatpak preinstall declarations
- wallpapers and GNOME background metadata
- Dudley theme, wallpaper, and build-info commands and their libraries
- Homebrew manifests as optional user-space declarations
- Dudley ujust recipes
- compatible first-login hooks and VS Code extension declarations
- the shared organization ujust payload

It explicitly excludes:

- `etc/yum.repos.d/**`
- the Bluefin top-panel parity hook
- Chrome RPM setup
- Fedora DX package restoration
- Docker and libvirt service/config payload
- VFIO/dracut payload
- Bazaar host services and helpers

The only local product files copied into Dakota are:

- `custom/system_files/etc/fonts/conf.d/60-dudley-monospace.conf`
- `custom/system_files/usr/share/glib-2.0/schemas/zz1-dudley-terminal.gschema.override`
- `custom/system_files/usr/share/ublue-os/user-setup.hooks.d/10-wallpaper-enforcement.sh`
- `custom/ujust/*.just`

The script validates its required commands, updates GLib schemas and dconf when
their compilers are available, applies final metadata, and fails if forbidden
RPM/package-manager logic appears in the Dakota path.

Homebrew manifests are intentionally present even though the pristine Dakota
base does not include `brew`. Dudley commands already report that absence
clearly. Installing or supplying a user-space Homebrew runtime is a later
parity step, not something this image fakes.

## Metadata Contract

`build/20-final-metadata.sh` remains the shared final identity writer.
It gains explicit stream/base-distribution inputs so Dakota metadata is
truthful:

- `DUDLEY_STREAM=stable|nvidia|dakota`
- `BASE_DISTRIBUTION=bluefin|dakota`

For Stable and NVIDIA, behavior remains unchanged.

For Dakota, metadata must:

- name the final image `ghcr.io/joshyorko/dudley-os:dakota`
- record the pinned upstream Dakota base reference
- set the Dudley image tag/version to `dakota`
- preserve inherited Dakota `ID`, `ID_LIKE`, `VERSION_ID`, and `VARIANT_ID`
- set Dudley `NAME`, `PRETTY_NAME`, support URLs, `IMAGE_ID`, `IMAGE_VERSION`,
  and `BUILD_ID`
- set the Dudley image flavor/stream to `dakota`
- avoid asserting that Fedora is Dakota's base distribution

The build manifest remains available through `dudley-build-info`.

## Build and Publish Workflow

`.github/workflows/build-dakota.yml` mirrors the security and publication
boundary of the existing workflows:

- run on pull requests, pushes to `main`, and manual dispatch
- build pull requests without publishing
- publish only from the default branch or an explicit manual publish input
- pass `CONTAINERFILE=./Containerfile.dakota`
- pass the pinned `DAKOTA_BASE_IMAGE_REF`
- pass `FINAL_IMAGE_REF=ghcr.io/joshyorko/dudley-os:dakota`
- publish `dakota`, `dakota.YYYYMMDD`, `YYYYMMDD-dakota`, and SHA/PR test tags
- use the existing keyless OIDC signing and provenance action
- use `Containerfile.dakota` in source metadata

The existing Stable and NVIDIA workflows keep their current behavior and tag
families. The NVIDIA card uses the already published `nvidia` alias even though
the workflow's build-time default tag remains `nvidia-latest`.

Renovate gains a dedicated manager for the Dakota base pin in
`Containerfile.dakota`.

## Local Build Interface

The Justfile gains a controlled Containerfile selector:

```text
CONTAINERFILE=./Containerfile.dakota \
BASE_IMAGE_REF=ghcr.io/projectbluefin/dakota:stable@sha256:... \
DEFAULT_TAG=dakota \
just build
```

The default remains `./Containerfile`, so existing Stable and NVIDIA invocations
do not change.

## Release-Card System

### Approved characters

The approved concepts are:

- Stable: slate navy, cream, muted rust, and a faded teal neck accent
- NVIDIA: charcoal and pale gray with restrained muted green accents
- Dakota: dusty sandstone and cream with faded copper and aubergine accents

All three use rough ink outlines, flat desaturated color, sparse feather lines,
small natural eyes, and compact silhouettes that remain readable at card scale.

The normalized production assets are transparent PNGs:

```text
static/img/characters/stable.png
static/img/characters/nvidia.png
static/img/characters/dakota.png
```

Normalization must preserve the approved drawings, remove only the off-white
background, retain soft feather edges, use a consistent transparent canvas,
and leave transparent corners. Tests reject missing alpha or opaque corners.

### Generator

The local Node generator follows Project Bluefin's Satori/Resvg pattern:

```text
package.json
package-lock.json
cards/streams.json
scripts/generate-card-images.mjs
scripts/lib/card-template.mjs
static/img/characters/
static/img/cards/
tests/test-card-assets.mjs
```

Requirements:

- Satori renders an 800-by-300 CSS-pixel card to SVG.
- Resvg renders a 1600-by-600 PNG.
- Inter is loaded from a pinned Fontsource package.
- `cards/streams.json` contains exactly `stable`, `nvidia`, and `dakota`.
- Each entry contains its title, description, image reference, public tag,
  accent color, mascot path, and switch command.
- A content hash includes the stream entry, mascot bytes, font bytes, and
  template/generator source.
- `npm run cards` regenerates all six committed outputs.
- `npm run cards:check` regenerates to a temporary directory and fails on any
  byte difference.

Committed outputs:

```text
static/img/cards/stable-light.png
static/img/cards/stable-dark.png
static/img/cards/nvidia-light.png
static/img/cards/nvidia-dark.png
static/img/cards/dakota-light.png
static/img/cards/dakota-dark.png
```

Cards are release identity panels, not detailed posters. Each shows the stream
name, a concise role label, its public tag/ref, and its matching raptor.

### Card validation workflow

`.github/workflows/validate-cards.yml`:

- runs when card sources, assets, dependencies, README, or the workflow change
- installs the pinned Node dependency graph with `npm ci`
- runs `npm run cards:check`
- runs the focused card asset tests
- never commits or pushes generated files

## README Stream Catalog

Add `Dudley Streams` near the top of `README.md`.

Each stream uses a `<picture>` element with its light PNG as the default and its
dark PNG selected by `prefers-color-scheme: dark`. Each card is displayed at
800 pixels wide and followed by its exact signed-image switch command:

```text
sudo bootc switch ghcr.io/joshyorko/dudley-os:stable --enforce-container-sigpolicy
sudo bootc switch ghcr.io/joshyorko/dudley-os:nvidia --enforce-container-sigpolicy
sudo bootc switch ghcr.io/joshyorko/dudley-os:dakota --enforce-container-sigpolicy
```

Dakota is labeled experimental. The copy may say it is intended to become a
daily-driver option, but must not claim that real boot, update, rollback, or
switch-back qualification has already passed.

## Qualification Matrix

Container build success is only build evidence.

Before Dakota is promoted as a proven daily driver, record:

```text
dudley-os:stable
  -> dudley-os:dakota
  -> boot and desktop login
  -> bootc update within Dakota
  -> bootc rollback within Dakota
  -> switch back to dudley-os:stable
```

Verify user/home and `/var` data, network connections, Flatpak state, Podman
state, GNOME session behavior, Secure Boot expectations, and the bootc
deployment list before and after the cycle.

NVIDIA remains a separate fallback path:

```text
dudley-os:stable <-> dudley-os:nvidia
```

This milestone does not claim Dakota NVIDIA support.

## Validation

- shellcheck every modified shell script
- parse every modified workflow as YAML
- run `just --list`
- run existing Stable and NVIDIA tests unchanged
- run the new Dakota contract test
- run final-metadata tests for Bluefin and Dakota inputs
- verify the Dakota workflow uses `Containerfile.dakota`, the pinned upstream
  repository/channel, the `dakota` tag family, signing, and provenance
- verify no Dakota build file invokes dnf, rpm, Chrome RPM, Docker, or libvirt
  setup
- verify all three character PNGs have alpha and transparent corners
- regenerate all six cards and require a byte-clean check
- verify all cards are exactly 1600 by 600
- verify README references every light/dark card and exact stream command
- run `git diff --check`
- build the Dakota container locally when host time and storage permit

No report may upgrade build validation into an unrun boot/update/rollback
claim.

## Acceptance Criteria

- No build, workflow, README, card manifest, or runtime path references or
  depends on `dudley-factory`; this design's scope exclusion is the only
  permitted mention.
- Stable and NVIDIA behavior remains unchanged.
- `ghcr.io/joshyorko/dudley-os:dakota` has its own build, publish, sign, and
  contract-test path in this repository.
- Dakota assembly is file-only and contains no Fedora package-management path.
- Dakota metadata names Dakota truthfully and preserves inherited GNOME OS
  identity fields.
- Stable, NVIDIA, and Dakota each have their approved original Dudley raptor.
- Six deterministic light/dark card PNGs are committed.
- README embeds the six cards and the three exact switch commands.
- CI detects Dakota contract drift and stale card outputs.
- Dakota remains labeled experimental until real qualification evidence exists.
