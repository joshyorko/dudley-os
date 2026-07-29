# Dudley Dakota Stream and Release Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a third signed `ghcr.io/joshyorko/dudley-os:dakota` bootc stream and add three approved Dudley raptors with six reproducible light/dark README cards, entirely inside `dudley-os`.

**Architecture:** Stable and NVIDIA keep the existing Project Bluefin Containerfile path. Dakota receives a separate digest-pinned `Containerfile.dakota` and file-only build script because upstream Dakota lacks dnf5/RPM and must not execute Fedora package layering. A pinned local Node/Satori/Resvg pipeline renders committed release cards from a three-stream manifest and normalized transparent raptor assets.

**Tech Stack:** bootc Containerfiles, Bash, GitHub Actions YAML, Renovate regex managers, Just, Node.js 20+, Satori 0.28.0, Resvg 2.6.2, Fontsource Inter 5.2.8, pngjs 7.0.0.

## Global Constraints

- All image, workflow, test, card, mascot, and documentation work stays in `dudley-os`.
- Do not read, edit, build, reference, or depend on `dudley-factory`.
- Canonical user-facing refs are exactly `ghcr.io/joshyorko/dudley-os:stable`, `ghcr.io/joshyorko/dudley-os:nvidia`, and `ghcr.io/joshyorko/dudley-os:dakota`; existing NVIDIA compatibility aliases remain published but are not card or switch targets.
- Do not document `latest` as a switch target.
- Stable and NVIDIA behavior and tag families remain unchanged.
- Dakota uses `ghcr.io/projectbluefin/dakota:stable@sha256:5989c44875101aaf8928f36360c8434f90ca485cb67d07ec07d7196c44a61f6c`, with future digest updates owned by Renovate.
- Dakota assembly is file-only: no dnf5, dnf, rpm, Chrome RPM, Fedora DX restoration, Docker service setup, or libvirt setup.
- Dakota metadata preserves inherited GNOME OS identity and must not claim Fedora is its base distribution.
- Cards contain exactly `stable`, `nvidia`, and `dakota`, use the approved matching raptor, and render to exactly 1600 by 600 pixels.
- Dakota remains labeled experimental until real boot, update, rollback, and switch-back tests are recorded.
- Tasks 1 and 2 may run in parallel by explicit user request because their write sets are disjoint.
- Workers must not modify `Justfile`, `README.md`, `build/20-final-metadata.sh`, `tests/test-final-metadata.sh`, or this spec/plan.
- Workers do not commit or push. Repository policy requires root to obtain explicit confirmation immediately before implementation commits and any push.

---

## File Structure

### Dakota lane

- `Containerfile.dakota` — Dakota-only OCI assembly entrypoint.
- `build/10-dakota.sh` — explicit file-only Dudley compatibility overlay.
- `.github/workflows/build-dakota.yml` — Dakota build, tag, publish, sign, and provenance lane.
- `.github/renovate.json5` — tracks the Dakota digest pin.
- `tests/test-dakota-variant-contract.sh` — guards the separate base/build/tag/security contract.

### Card lane

- `package.json` and `package-lock.json` — exact local generator dependency graph.
- `cards/streams.json` — checked-in three-stream card content.
- `scripts/generate-card-images.mjs` — deterministic generate/check/cache CLI.
- `scripts/lib/card-template.mjs` — 800-by-300 Satori element tree.
- `static/img/characters/{stable,nvidia,dakota}.png` — normalized approved transparent raptors.
- `static/img/cards/{stable,nvidia,dakota}-{light,dark}.png` — six committed 1600-by-600 cards.
- `static/img/cards/card-hashes.json` — content hashes for all three streams.
- `tests/test-card-assets.mjs` — manifest, alpha, dimensions, output, and README-path contracts.

### Root integration

- `Justfile` — controlled Containerfile selector plus Dakota/card test recipes.
- `build/20-final-metadata.sh` — stream-aware, distribution-truthful shared metadata.
- `tests/test-final-metadata.sh` — existing Bluefin fixture plus a Dakota fixture.
- `.github/workflows/validate-cards.yml` — reproducibility validation without mutation.
- `tests/test-publish-workflow-contract.sh` — includes the Dakota publish/sign lane.
- `README.md` — three-card stream catalog and signed bootc commands.

---

### Task 1: Add the Dakota Assembly and Publish Lane

**Files:**
- Create: `Containerfile.dakota`
- Create: `build/10-dakota.sh`
- Create: `.github/workflows/build-dakota.yml`
- Modify: `.github/renovate.json5`
- Create: `tests/test-dakota-variant-contract.sh`

**Interfaces:**
- Consumes: `BASE_IMAGE_REF`, `FINAL_IMAGE_REF`, `SHA_HEAD_SHORT`, the pinned `dsb-common` OCI paths, and the existing `build/20-final-metadata.sh`.
- Produces: a local image built with `CONTAINERFILE=./Containerfile.dakota DEFAULT_TAG=dakota`, plus a CI lane whose canonical output is `ghcr.io/joshyorko/dudley-os:dakota`.

- [ ] **Step 1: Write the failing Dakota contract test**

Create `tests/test-dakota-variant-contract.sh` with `#!/usr/bin/env bash` and
`set -euo pipefail`. The test must assert:

```bash
grep -Eq '^ARG BASE_IMAGE_REF="ghcr\.io/projectbluefin/dakota:stable@sha256:[a-f0-9]{64}"$' Containerfile.dakota
grep -Fq '/ctx/build/10-dakota.sh' Containerfile.dakota
grep -Fq 'RUN bootc container lint' Containerfile.dakota
! grep -Eq '10-build\.sh|15-dx\.sh|google-chrome|dnf5[[:space:]]|rpm-ostree' Containerfile.dakota build/10-dakota.sh
grep -Fq 'DEFAULT_TAG: "dakota"' .github/workflows/build-dakota.yml
grep -Fq 'CONTAINERFILE=./Containerfile.dakota' .github/workflows/build-dakota.yml
grep -Fq 'ghcr.io/projectbluefin/dakota:stable@sha256:' .github/workflows/build-dakota.yml
grep -Fq 'projectbluefin/actions/bootc-build/sign-and-publish@' .github/workflows/build-dakota.yml
grep -Fq 'type=raw,value=dakota' .github/workflows/build-dakota.yml
grep -Fq 'type=sha' .github/workflows/build-dakota.yml
```

Also parse the workflow with Python `yaml.safe_load`, assert the Dakota
Containerfile is covered by a Renovate custom manager, and print one PASS line.

- [ ] **Step 2: Run the focused test and confirm the missing lane fails**

Run:

```bash
bash tests/test-dakota-variant-contract.sh
```

Expected: non-zero because `Containerfile.dakota` or the workflow does not yet
exist.

- [ ] **Step 3: Add the separate Dakota Containerfile**

Create a two-stage Containerfile with this contract:

```dockerfile
ARG BASE_IMAGE_REF="ghcr.io/projectbluefin/dakota:stable@sha256:5989c44875101aaf8928f36360c8434f90ca485cb67d07ec07d7196c44a61f6c"

FROM scratch AS ctx
COPY build/10-dakota.sh /build/10-dakota.sh
COPY build/20-final-metadata.sh /build/20-final-metadata.sh
COPY custom/ujust /custom/ujust
COPY custom/system_files/etc/fonts/conf.d/60-dudley-monospace.conf /custom/system_files/etc/fonts/conf.d/60-dudley-monospace.conf
COPY custom/system_files/usr/share/glib-2.0/schemas/zz1-dudley-terminal.gschema.override /custom/system_files/usr/share/glib-2.0/schemas/zz1-dudley-terminal.gschema.override
COPY custom/system_files/usr/share/ublue-os/user-setup.hooks.d/10-wallpaper-enforcement.sh /custom/system_files/usr/share/ublue-os/user-setup.hooks.d/10-wallpaper-enforcement.sh
COPY --from=ghcr.io/joshyorko/dsb-common:latest@sha256:86a8a04466af9c87fc2ae5676488951d70c3007f7c1ed5d4adb596eb5ab9f987 /system_files/shared /oci/dsb-common/shared
COPY --from=ghcr.io/joshyorko/dsb-common:latest@sha256:86a8a04466af9c87fc2ae5676488951d70c3007f7c1ed5d4adb596eb5ab9f987 /system_files/dudley /oci/dsb-common/dudley

FROM ${BASE_IMAGE_REF}
ARG BASE_IMAGE_REF
ARG FINAL_IMAGE_REF="ghcr.io/joshyorko/dudley-os:dakota"
ARG SHA_HEAD_SHORT="unknown"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-dakota.sh

RUN bootc container lint
```

Do not add package-manager or normal Dudley build invocations.

- [ ] **Step 4: Implement the file-only Dakota overlay**

Create `build/10-dakota.sh` with `#!/usr/bin/env bash` and
`set -euo pipefail`.

The script must:

1. require `bootc`, `ujust`, `podman`, `rsync`, `jq`, `dconf`, and
   `glib-compile-schemas`;
2. use a `copy_tree SOURCE DEST [rsync args...]` helper that skips missing
   optional source directories;
3. copy only:
   - shared `/usr/share/ublue-os/just/`
   - Dudley dconf, Flatpak preinstall, XDG wallpaper autostart, `/usr/bin`
     Dudley commands, `usr/lib/dudley_theme` without `__pycache__`, wallpapers,
     GLib schemas, GNOME background metadata, Homebrew declarations, Dudley
     just recipes, `update.just`, hooks `20-dudley-vscode-extensions.sh` and
     `25-dudley-theme.sh`, and `vscode-extensions.list`;
   - the four local product paths listed in `Containerfile.dakota`;
4. never copy the Google Chrome repo, Bluefin panel-parity hook, Bazaar cleanup
   hook, local Docker/libvirt/VFIO/Bazaar host files, or any package payload;
5. run `glib-compile-schemas /usr/share/glib-2.0/schemas` and `dconf update`;
6. invoke:

```bash
DUDLEY_STREAM=dakota \
BASE_DISTRIBUTION=dakota \
FINAL_IMAGE_REF="${FINAL_IMAGE_REF}" \
BASE_IMAGE_REF="${BASE_IMAGE_REF}" \
SHA_HEAD_SHORT="${SHA_HEAD_SHORT}" \
/ctx/build/20-final-metadata.sh
```

- [ ] **Step 5: Add the Dakota build/publish/sign workflow**

Copy the structure and pinned action versions from
`.github/workflows/build-nvidia.yml`, then make these exact Dakota choices:

```yaml
env:
  IMAGE_REGISTRY: ghcr.io/${{ github.repository_owner }}
  IMAGE_NAME: "${{ github.event.repository.name }}"
  DEFAULT_TAG: "dakota"
  DAKOTA_BASE_IMAGE_REF: "ghcr.io/projectbluefin/dakota:stable@sha256:5989c44875101aaf8928f36360c8434f90ca485cb67d07ec07d7196c44a61f6c"
```

Metadata tags must include:

```yaml
type=raw,value=dakota
type=raw,value=dakota.{{date 'YYYYMMDD'}}
type=raw,value={{date 'YYYYMMDD'}}-dakota
type=ref,event=pr,prefix=dakota-pr-
type=sha,prefix=dakota-sha-
```

The build step must export:

```bash
CONTAINERFILE=./Containerfile.dakota
BASE_IMAGE_REF="${DAKOTA_BASE_IMAGE_REF}"
METADATA_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAME}"
FINAL_IMAGE_REF="${IMAGE_REGISTRY}/${IMAGE_NAME}:dakota"
```

and invoke `sudo -E "$(command -v just)" build-ghcr "${IMAGE_NAME}" "${DEFAULT_TAG}"`.
Keep the existing PR-no-publish condition, permissions, keyless signing, and
provenance behavior. Point the OCI source label at `Containerfile.dakota`.

- [ ] **Step 6: Add Renovate coverage for the Dakota pin**

Extend the Containerfile base-image custom manager so it matches both
`Containerfile` and `Containerfile.dakota`, and add a Dakota-specific match for:

```text
ARG BASE_IMAGE_REF="ghcr.io/projectbluefin/dakota:stable@sha256:..."
```

Keep `datasourceTemplate: "docker"` and `versioningTemplate: "docker"`.

- [ ] **Step 7: Run focused validation**

Run:

```bash
shellcheck build/10-dakota.sh tests/test-dakota-variant-contract.sh
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-dakota.yml'))"
bash tests/test-dakota-variant-contract.sh
bash tests/test-base-image-contract.sh
bash tests/test-nvidia-variant-contract.sh
git diff --check -- Containerfile.dakota build/10-dakota.sh .github/workflows/build-dakota.yml .github/renovate.json5 tests/test-dakota-variant-contract.sh
```

Expected: all pass. Write the report file with changed paths, commands, results,
and anything that still requires a real boot. Do not commit.

---

### Task 2: Add the Approved Raptors and Deterministic Card Generator

**Files:**
- Create: `package.json`
- Create: `package-lock.json`
- Create: `cards/streams.json`
- Create: `scripts/generate-card-images.mjs`
- Create: `scripts/lib/card-template.mjs`
- Create: `static/img/characters/stable.png`
- Create: `static/img/characters/nvidia.png`
- Create: `static/img/characters/dakota.png`
- Create: `static/img/cards/stable-light.png`
- Create: `static/img/cards/stable-dark.png`
- Create: `static/img/cards/nvidia-light.png`
- Create: `static/img/cards/nvidia-dark.png`
- Create: `static/img/cards/dakota-light.png`
- Create: `static/img/cards/dakota-dark.png`
- Create: `static/img/cards/card-hashes.json`
- Create: `tests/test-card-assets.mjs`

**Interfaces:**
- Consumes: the three approved concept PNGs and exact public refs from Global Constraints.
- Produces: `npm run cards`, `npm run cards:check`, a three-stream manifest, three transparent character PNGs, and six deterministic 1600-by-600 card PNGs.

- [ ] **Step 1: Add the failing card contract test**

Create a Node test using `node:test`, `node:assert/strict`, and `pngjs`.
It must:

- assert manifest keys are exactly `["dakota", "nvidia", "stable"]` after sort;
- assert each entry has `title`, `description`, `imageRef`, `tag`, `accent`,
  `mascot`, and `switchCommand`;
- assert refs and tags are the exact three public refs;
- decode each character PNG and assert RGBA, width/height greater than zero,
  and alpha 0 in all four corners;
- decode all six cards and assert width 1600 and height 600;
- assert both light and dark output exist for every stream;
- assert `card-hashes.json` has exactly the same three keys.

- [ ] **Step 2: Create the pinned Node package**

Use this exact dependency graph:

```json
{
  "name": "dudley-release-cards",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "cards": "node scripts/generate-card-images.mjs",
    "cards:check": "node scripts/generate-card-images.mjs --check",
    "test:cards": "node --test tests/test-card-assets.mjs"
  },
  "devDependencies": {
    "@fontsource/inter": "5.2.8",
    "@resvg/resvg-js": "2.6.2",
    "pngjs": "7.0.0",
    "satori": "0.28.0"
  }
}
```

Run `npm install --package-lock-only` to create the lockfile, then `npm ci`.

- [ ] **Step 3: Normalize the three approved concepts**

Use these exact approved sources:

```text
Stable: /var/home/kdlocpanda/.codex/generated_images/019fae30-27a4-74e2-bcad-11098dc044db/call_jUh5LBeGYL46OQb3OdnOL2JO.png
NVIDIA: /var/home/kdlocpanda/.codex/generated_images/019fae30-27a4-74e2-bcad-11098dc044db/call_K1LsEoO7dagCq71Q7UIR38cX.png
Dakota: /var/home/kdlocpanda/.codex/generated_images/019fae30-27a4-74e2-bcad-11098dc044db/call_dlmONAGKfFfvHemT5DHK6jqG.png
```

Use ImageMagick only for mechanical normalization of the already approved art:

```bash
magick INPUT -alpha on -fuzz 6% -transparent white -trim +repage \
  -resize '430x330>' -gravity center -background none -extent 512x384 OUTPUT
```

Write the outputs to `static/img/characters/{stable,nvidia,dakota}.png`.
Inspect them and reduce fuzz if any cream body or eye detail becomes
transparent. Do not redraw or restyle the approved characters.

- [ ] **Step 4: Add the exact stream manifest**

Create `cards/streams.json` with exactly:

```json
{
  "stable": {
    "title": "Dudley Stable",
    "description": "Bluefin-based daily driver",
    "imageRef": "ghcr.io/joshyorko/dudley-os:stable",
    "tag": "stable",
    "accent": "#587384",
    "mascot": "static/img/characters/stable.png",
    "switchCommand": "sudo bootc switch ghcr.io/joshyorko/dudley-os:stable --enforce-container-sigpolicy"
  },
  "nvidia": {
    "title": "Dudley NVIDIA",
    "description": "Bluefin-based NVIDIA daily driver",
    "imageRef": "ghcr.io/joshyorko/dudley-os:nvidia",
    "tag": "nvidia",
    "accent": "#6f8f67",
    "mascot": "static/img/characters/nvidia.png",
    "switchCommand": "sudo bootc switch ghcr.io/joshyorko/dudley-os:nvidia --enforce-container-sigpolicy"
  },
  "dakota": {
    "title": "Dudley Dakota",
    "description": "Experimental distroless GNOME OS stream",
    "imageRef": "ghcr.io/joshyorko/dudley-os:dakota",
    "tag": "dakota",
    "accent": "#9a745f",
    "mascot": "static/img/characters/dakota.png",
    "switchCommand": "sudo bootc switch ghcr.io/joshyorko/dudley-os:dakota --enforce-container-sigpolicy"
  }
}
```

- [ ] **Step 5: Implement the compact Satori template**

Export `W = 800`, `H = 300`, and:

```js
export function renderCard(stream, theme, mascotDataUri)
```

Use a plain Satori element tree, not JSX. Keep the background, border, text,
accent stripe, tag pill, image ref, and role label inside the card. Position
the raptor on the right at no more than 210 CSS pixels square. Define explicit
light and dark palettes; stream accent colors come from the manifest.

- [ ] **Step 6: Implement deterministic generate/check behavior**

`scripts/generate-card-images.mjs` must:

- load Inter 400 and 700 WOFF files from the pinned Fontsource package;
- validate the manifest and mascot paths;
- hash the canonical stream JSON, mascot bytes, both font files, generator
  source, and template source with SHA-256;
- render light and dark SVGs through Satori and 2x PNGs through Resvg;
- write outputs and `card-hashes.json` in normal mode;
- in `--check` mode, render into `mkdtempSync(join(tmpdir(), "dudley-cards-"))`,
  compare generated bytes and hashes with committed files, and remove only that
  temporary directory;
- exit non-zero with the stale/missing paths when any output differs.

- [ ] **Step 7: Generate and validate the assets**

Run:

```bash
npm run cards
npm run test:cards
npm run cards:check
git diff --check -- package.json package-lock.json cards scripts static/img tests/test-card-assets.mjs
```

Expected: three transparent character assets, six 1600-by-600 cards, matching
hashes, and a byte-clean check. Write the report file with changed paths,
commands, results, and visual concerns. Do not commit.

---

### Task 3: Integrate Stream Selection, Metadata, Cards, and Documentation

**Files:**
- Modify: `Justfile`
- Modify: `build/20-final-metadata.sh`
- Modify: `tests/test-final-metadata.sh`
- Create: `.github/workflows/validate-cards.yml`
- Modify: `tests/test-publish-workflow-contract.sh`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-07-29-dudley-dakota-streams-and-release-cards-design.md`

**Interfaces:**
- Consumes: `Containerfile.dakota`, `build/10-dakota.sh`, `.github/workflows/build-dakota.yml`, `npm run cards:check`, and all card paths from Tasks 1 and 2.
- Produces: one documented/tested repo interface for building all three streams and validating their cards.

- [ ] **Step 1: Add failing cross-stream integration assertions**

Extend `tests/test-final-metadata.sh` with a second isolated fixture whose
initial os-release contains Dakota/GNOME OS identity values. Invoke:

```bash
DUDLEY_STREAM=dakota \
BASE_DISTRIBUTION=dakota \
FINAL_IMAGE_REF=ghcr.io/joshyorko/dudley-os:dakota \
BASE_IMAGE_REF=ghcr.io/projectbluefin/dakota:stable@sha256:abc123 \
bash build/20-final-metadata.sh
```

Assert final image/tag/base/stream are Dakota, inherited `ID`, `ID_LIKE`,
`VERSION_ID`, and `VARIANT_ID` remain unchanged, and generated image-info does
not describe Fedora as the base distribution.

Extend `tests/test-publish-workflow-contract.sh` to require the Dakota workflow,
its keyless signing/provenance action, and PR-no-publish boundary.

- [ ] **Step 2: Make the Justfile Containerfile-selectable**

Add:

```just
export containerfile := env("CONTAINERFILE", "./Containerfile")
```

Replace only the hardcoded build argument:

```text
--file ./Containerfile
```

with:

```text
--file "{{containerfile}}"
```

Add `tests/test-dakota-variant-contract.sh` and `npm run test:cards` to
`test-unit`. Add:

```just
[group('Cards')]
cards:
    npm run cards

[group('Cards')]
cards-check:
    npm run cards:check
```

- [ ] **Step 3: Make final metadata stream-aware**

Add defaults:

```bash
dudley_stream="${DUDLEY_STREAM:-stable}"
base_distribution="${BASE_DISTRIBUTION:-bluefin}"
```

Write `"stream": $dudley_stream` and
`"base-distribution": $base_distribution` into image-info.

For `base_distribution=dakota`:

- force `image-flavor` to `dakota`;
- do not synthesize or retain a `fedora-version` field;
- preserve inherited `ID`, `ID_LIKE`, `VERSION_ID`, and `VARIANT_ID`;
- continue stamping Dudley `NAME`, `PRETTY_NAME`, URLs, `IMAGE_ID`,
  `IMAGE_VERSION`, and `BUILD_ID`.

For Bluefin, preserve the existing metadata output byte-for-byte except for the
new truthful stream/base-distribution keys.

- [ ] **Step 4: Add the card validation workflow**

Create `.github/workflows/validate-cards.yml` with checkout, setup-node 20,
`npm ci`, `npm run test:cards`, and `npm run cards:check`. Trigger on pull
requests and pushes to `main` when any of these change:

```text
package.json
package-lock.json
cards/**
scripts/generate-card-images.mjs
scripts/lib/card-template.mjs
static/img/characters/**
static/img/cards/**
tests/test-card-assets.mjs
README.md
.github/workflows/validate-cards.yml
```

Use read-only contents permission. Do not add commit or push permissions.

- [ ] **Step 5: Add the three-card README stream catalog**

Insert `## Dudley Streams` after the introductory product-difference section and
before detailed build documentation. Use one `<picture>` per stream:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="static/img/cards/STREAM-dark.png">
  <img src="static/img/cards/STREAM-light.png" alt="Dudley STREAM release card" width="800">
</picture>
```

Under each card, include the exact signed switch command from
`cards/streams.json`. Describe Stable and NVIDIA as the established fallbacks.
Describe Dakota as the experimental distroless GNOME OS path intended for
daily-driver qualification, and explicitly state that boot/update/rollback
proof is still required.

Update the existing “What Makes this Raptor Different?” section and current date
only where necessary to explain the third stream without claiming Dakota has
Fedora/Chrome/DX parity.

- [ ] **Step 6: Run focused integration validation**

Run:

```bash
shellcheck build/10-dakota.sh build/20-final-metadata.sh tests/test-dakota-variant-contract.sh tests/test-final-metadata.sh tests/test-publish-workflow-contract.sh
python3 -c "import yaml; [yaml.safe_load(open(path)) for path in ['.github/workflows/build-dakota.yml', '.github/workflows/validate-cards.yml']]"
just --list
bash tests/test-final-metadata.sh
bash tests/test-publish-workflow-contract.sh
npm run test:cards
npm run cards:check
```

Expected: all pass.

- [ ] **Step 7: Run the complete repository validation**

Run:

```bash
XDG_RUNTIME_DIR=/tmp just test
git diff --check
git status --short
```

If host time and storage permit, run:

```bash
CONTAINERFILE=./Containerfile.dakota \
BASE_IMAGE_REF=ghcr.io/projectbluefin/dakota:stable@sha256:5989c44875101aaf8928f36360c8434f90ca485cb67d07ec07d7196c44a61f6c \
DEFAULT_TAG=dakota \
just build dudley-os dakota
```

Report a skipped image build as skipped. Do not infer boot, update, rollback, or
switch-back results from container lint/build success.

- [ ] **Step 8: Obtain commit and push confirmation**

Present the exact changed-file list, validation ledger, and any unrun real-system
qualification. Ask for explicit confirmation before committing. Use a
Conventional Commit message such as:

```text
feat: add Dakota stream and Dudley release cards
```

Do not push or publish until the user separately authorizes it.
