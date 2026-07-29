# Dudley Operator README Rewrite

## Goal

Replace the current template-style README with an operator-first guide for
Josh's personal Dudley daily driver. The result must still give another bootc
user enough context to evaluate and run Dudley safely.

The README must state plainly that Dudley is a Project Bluefin variant. It must
credit the upstream images, desktop and userland contract, and shared
Project Bluefin build/publish actions without duplicating Bluefin's own
documentation.

## Audience

Primary:

- Josh operating, switching, updating, testing, and maintaining Dudley

Secondary:

- an experienced Bluefin or bootc user evaluating the image
- a contributor changing Dudley-specific assembly or shared payload

This is not a generic bootc template tutorial.

## Positioning

The opening description will use this hierarchy:

1. Project Bluefin supplies the upstream operating-system foundation.
2. `dsb-common` supplies reusable DSB and Dudley payload.
3. `dudley-os` performs final product assembly, validation, publication, and
   stream-specific identity.

Stable and NVIDIA inherit Project Bluefin directly and add Dudley's DX-style
runtime, applications, configuration, and branding. Dakota is a separate,
experimental file-only overlay on Project Bluefin Dakota and must not claim
Stable/NVIDIA parity.

No contributor badge or personal upstream-contribution claim will be added.

## Main README Structure

### 1. Identity and hero

- `dudley-os` title
- one short operator-focused description
- existing golden-bedroom hero
- concise attribution callout linking to:
  - Project Bluefin
  - Project Bluefin documentation
  - Project Bluefin Actions
  - Universal Blue
  - bootc

### 2. Choose a stream

Keep the Stable, NVIDIA, and Dakota release cards. Each stream gets:

- intended machine/use case
- canonical image reference
- signed `bootc switch` command
- stability or qualification status

Dakota remains explicitly experimental and carries the physical
boot/update/rollback qualification boundary.

### 3. Daily operation

Provide only commands that are useful after installation:

- inspect the current deployment
- update the current stream
- reboot into an update
- switch between canonical Dudley streams
- roll back when needed

Where Bluefin already documents the behavior, link upstream instead of
recreating a long tutorial.

### 4. What Dudley adds

Use a compact ownership table:

| Layer | Owns |
| --- | --- |
| Project Bluefin | base images, desktop/userland contract, upstream bootc integration, shared build/publish actions |
| `dsb-common` | shared DSB defaults, Dudley wallpapers, Brewfiles, Flatpak declarations, VS Code payload, shared hooks and recipes |
| `dudley-os` | stream assembly, DX-style runtime layer, Chrome image install, final metadata, validation, publishing, local product glue |

Follow the table with a short list of meaningful Dudley operator differences,
not an exhaustive package inventory.

### 5. Stream architecture

Show the three base-image relationships and the copy order:

1. Project Bluefin stream base
2. `dsb-common/shared`
3. `dsb-common/dudley`
4. local `dudley-os` assembly

Explain that Dakota uses a narrower allowlisted file overlay and excludes the
Fedora/RPM/DNF, Chrome RPM, Docker, and libvirt host payload.

### 6. Build, trust, and release

State the current facts once:

- Renovate-managed digest pins
- Project Bluefin Actions for runner setup, preflight, push, keyless signing,
  and provenance
- Stable, NVIDIA, and Dakota publication from `main`
- SBOM publication is intentionally disabled
- canonical image tags
- cosign verification example

Remove the generic production checklist and rechunking tutorial.

### 7. Local verification

Keep a compact command block for:

- dependency installation when card tooling is needed
- `just test`
- deterministic card verification
- local image build
- VM image path

Link detailed or infrequent workflows to supporting docs.

### 8. Repository map and links

End with a small table linking to the files and repositories an operator or
maintainer actually needs:

- `Containerfile`
- `Containerfile.dakota`
- `build/`
- `.github/workflows/`
- `cards/`
- `dsb-common`
- Project Bluefin documentation

## Supporting Documentation

Move durable detail out of the README:

- `docs/operations.md`
  - local image and VM workflows
  - Dagger helper path
  - release and verification commands
- `docs/maintenance.md`
  - ownership boundaries
  - dependency updates and Renovate
  - workflow and validation map
  - where packages, Flatpaks, Brewfiles, hooks, and metadata belong
- `docs/history/dudleys-second-bedroom-migration.md`
  - the existing legacy migration table and retirement decisions

Delete stale generic template-renaming and GitHub Actions onboarding
instructions. Dudley is an established product repository, not a blank
template. Users wanting their own Bluefin variant should be directed to
Project Bluefin's current documentation.

## Content Rules

- Credit Project Bluefin before describing Dudley customization.
- Do not describe upstream Bluefin features as Dudley inventions.
- Do not copy long upstream tutorials.
- Do not claim Dakota parity or physical qualification.
- Do not claim SBOM publication while it remains disabled.
- Keep switch commands canonical and signature-policy enforced.
- Preserve all six stream card references required by the card contract tests.
- Prefer operator outcomes over implementation chronology.

## Verification

- `XDG_RUNTIME_DIR=/tmp just test`
- `npm run cards:check`
- Markdown link and local-path review
- `git diff --check`
- focused review that every architecture and ownership claim is backed by the
  current Containerfiles, build scripts, or workflows

## Success Criteria

- The README becomes substantially shorter and easier to scan.
- A reader understands within the first screen that Dudley is built directly
  on Project Bluefin.
- Josh can find stream, update, rollback, verification, and build commands
  without reading template material.
- Another Bluefin/bootc user can assess the image and its experimental boundary.
- Project Bluefin, `dsb-common`, and `dudley-os` ownership are unambiguous.
- Detailed maintenance and historical material remains available without
  dominating the main README.
