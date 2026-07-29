# Dudley Operator README Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the template-heavy README with a concise operator guide that credits Project Bluefin accurately and moves durable detail into focused supporting documents.

**Architecture:** The README becomes the operator entrypoint: identity, upstream foundation, stream choice, daily bootc operations, ownership, trust, and local verification. Three supporting documents own infrequent operational detail, repository maintenance, and migration history. Existing card assets and canonical switch commands remain unchanged.

**Tech Stack:** GitHub-flavored Markdown, HTML `<picture>` elements, Node.js `node:test`, existing `just` validation, bootc CLI.

## Global Constraints

- State that Dudley is a personal Project Bluefin variant within the first screen.
- Credit Project Bluefin base images and Project Bluefin Actions before describing Dudley additions.
- Do not add a contributor badge or upstream-contribution claim.
- Do not duplicate long Bluefin or bootc tutorials.
- Keep all Stable, NVIDIA, and Dakota light/dark card references.
- Keep canonical signed switch commands for `:stable`, `:nvidia`, and `:dakota`.
- Keep Dakota explicitly experimental; do not claim physical boot, update, rollback, switch-back, Secure Boot, or daily-driver qualification.
- State that CI SBOM publication is disabled.
- Remove generic template-renaming, GitHub Actions onboarding, production-checklist, and rechunking instructions.
- Do not modify image assembly, workflows, package manifests, or generated card assets.

---

### Task 1: Extract durable supporting documentation

**Files:**
- Create: `docs/operations.md`
- Create: `docs/maintenance.md`
- Create: `docs/history/dudleys-second-bedroom-migration.md`
- Source: `README.md`
- Source: `Justfile`
- Source: `.github/workflows/build.yml`
- Source: `.github/workflows/build-nvidia.yml`
- Source: `.github/workflows/build-dakota.yml`

**Interfaces:**
- Consumes: existing `just` recipe names, publish workflow behavior, and the legacy migration table from `README.md`
- Produces: stable targets for README links: `docs/operations.md`, `docs/maintenance.md`, and `docs/history/dudleys-second-bedroom-migration.md`

- [ ] **Step 1: Create the operator runbook**

Create `docs/operations.md` with this structure:

```markdown
# Dudley Operations

## Inspect and update
## Switch streams
## Roll back
## Build locally
## Build and run a VM
## Dagger helpers
## Verify a published image
```

Use the verified commands:

```bash
bootc status
sudo bootc upgrade
sudo systemctl reboot
sudo bootc rollback --apply
just build
just build-qcow2
just run-vm-qcow2
just dagger-test
```

Include all three canonical switch commands with
`--enforce-container-sigpolicy`. Explain that Dakota remains experimental.

- [ ] **Step 2: Create the maintainer guide**

Create `docs/maintenance.md` with:

```markdown
# Dudley Maintenance

## Ownership boundaries
## Where changes belong
## Stream build inputs
## Validation workflows
## Renovate and digest pins
## Publishing, signing, and provenance
## Supporting repositories and upstream documentation
```

The ownership table must distinguish Project Bluefin, `dsb-common`, and
`dudley-os`. Document that Project Bluefin Actions supplies runner setup,
preflight, push, signing, and provenance steps. Document that main publishing
is keyless and that SBOM publication is disabled.

- [ ] **Step 3: Preserve migration history**

Create `docs/history/dudleys-second-bedroom-migration.md`. Move the current
legacy migration table from `README.md` without changing its ownership
decisions. Add a short introduction explaining that the document is historical
and not an operator setup guide.

- [ ] **Step 4: Validate supporting documents**

Run:

```bash
test -f docs/operations.md
test -f docs/maintenance.md
test -f docs/history/dudleys-second-bedroom-migration.md
grep -Fq 'sudo bootc rollback --apply' docs/operations.md
grep -Fq 'Project Bluefin Actions' docs/maintenance.md
grep -Fq 'dudleys-second-bedroom' docs/history/dudleys-second-bedroom-migration.md
git diff --check
```

Expected: every command exits successfully.

---

### Task 2: Add an operator README contract

**Files:**
- Modify: `tests/test-card-assets.mjs`
- Test: `tests/test-card-assets.mjs`

**Interfaces:**
- Consumes: supporting-document paths created by Task 1
- Produces: a regression test that protects upstream attribution, operator links, stream cards, and removed template content

- [ ] **Step 1: Add the failing README structure test**

Append this test to `tests/test-card-assets.mjs`:

```javascript
test('README is operator-first and credits its upstream foundation', async () => {
  const readme = await readFile(path.join(root, 'README.md'), 'utf8');
  for (const required of [
    'Project Bluefin',
    'https://docs.projectbluefin.io',
    'https://github.com/projectbluefin/actions',
    'docs/operations.md',
    'docs/maintenance.md',
    'docs/history/dudleys-second-bedroom-migration.md',
    'bootc status',
    'sudo bootc upgrade',
    'sudo bootc rollback --apply',
  ]) {
    assert.ok(readme.includes(required), `README omits ${required}`);
  }

  for (const removed of [
    'Create Your Repository',
    'Rename the Project',
    "Love Your Image? Let's Go to Production",
    'Adding Image Rechunking',
  ]) {
    assert.ok(!readme.includes(removed), `README retains stale section: ${removed}`);
  }
});
```

- [ ] **Step 2: Verify the contract fails against the current README**

Run:

```bash
npm run test:cards
```

Expected: FAIL because the current README lacks the supporting-doc links and
daily-operation commands.

---

### Task 3: Rewrite README as the operator entrypoint

**Files:**
- Modify: `README.md`
- Test: `tests/test-card-assets.mjs`

**Interfaces:**
- Consumes: supporting-document paths from Task 1 and the test contract from Task 2
- Produces: the operator-first README

- [ ] **Step 1: Replace the README information architecture**

Rewrite `README.md` using exactly these top-level sections:

```markdown
# dudley-os
## Choose a stream
## Daily operation
## What Dudley adds
## Architecture
## Build, trust, and release
## Local verification
## Repository map
## Upstream and supporting projects
```

The opening paragraph must say that Dudley is Josh's personal Project Bluefin
variant. Keep the golden-bedroom hero immediately after the opening.

Add a short upstream-foundation callout linking to:

- `https://projectbluefin.io`
- `https://docs.projectbluefin.io`
- `https://github.com/projectbluefin/actions`
- `https://universal-blue.org`
- `https://containers.github.io/bootc/`

- [ ] **Step 2: Preserve the stream cards and canonical commands**

Keep the existing `<picture>` blocks for:

```text
static/img/cards/stable-light.png
static/img/cards/stable-dark.png
static/img/cards/nvidia-light.png
static/img/cards/nvidia-dark.png
static/img/cards/dakota-light.png
static/img/cards/dakota-dark.png
```

Keep these commands verbatim:

```bash
sudo bootc switch ghcr.io/joshyorko/dudley-os:stable --enforce-container-sigpolicy
sudo bootc switch ghcr.io/joshyorko/dudley-os:nvidia --enforce-container-sigpolicy
sudo bootc switch ghcr.io/joshyorko/dudley-os:dakota --enforce-container-sigpolicy
```

- [ ] **Step 3: Add concise daily operation guidance**

Include:

```bash
bootc status
sudo bootc upgrade
sudo systemctl reboot
sudo bootc rollback --apply
```

Link to `docs/operations.md` for the full runbook and to Project Bluefin docs
for upstream behavior.

- [ ] **Step 4: Add ownership and architecture**

Include this ownership table:

```markdown
| Layer | Responsibility |
| --- | --- |
| Project Bluefin | Base images, desktop and userland contract, bootc integration, and shared build/publish actions |
| `dsb-common` | Shared DSB defaults plus Dudley wallpapers, Brewfiles, Flatpak declarations, VS Code payload, hooks, and recipes |
| `dudley-os` | Stream assembly, DX-style runtime additions, Chrome image install, final metadata, validation, publishing, and local product glue |
```

Describe the copy order:

1. Project Bluefin stream base
2. `dsb-common/shared`
3. `dsb-common/dudley`
4. local `dudley-os` assembly

State that Dakota uses an allowlisted file overlay and excludes Fedora/RPM/DNF,
Chrome RPM, Docker, and libvirt host payload.

- [ ] **Step 5: Consolidate release and verification facts**

State once that:

- Renovate pins image and action dependencies by digest.
- Project Bluefin Actions handles runner setup, preflight, image push, keyless
  signing, and GitHub provenance.
- `main` publishes Stable, NVIDIA, and Dakota.
- CI SBOM publication is disabled.

Keep one `cosign verify` example for the Stable image.

- [ ] **Step 6: Link supporting docs**

Link:

```markdown
- [Operator runbook](docs/operations.md)
- [Maintenance and ownership](docs/maintenance.md)
- [Legacy migration record](docs/history/dudleys-second-bedroom-migration.md)
```

Remove the old template onboarding, production checklist, rechunking tutorial,
duplicated publishing sections, and duplicated architecture prose.

- [ ] **Step 7: Run focused tests**

Run:

```bash
npm run test:cards
npm run cards:check
git diff --check
```

Expected: PASS.

---

### Task 4: Integrated review and full verification

**Files:**
- Review: `README.md`
- Review: `docs/operations.md`
- Review: `docs/maintenance.md`
- Review: `docs/history/dudleys-second-bedroom-migration.md`
- Review: `tests/test-card-assets.mjs`

**Interfaces:**
- Consumes: all prior task outputs
- Produces: a review-ready documentation change with verified links and truthful attribution

- [ ] **Step 1: Review every attribution claim against repository evidence**

Check:

```bash
grep -F 'ghcr.io/projectbluefin/bluefin:stable' Containerfile
grep -F 'ghcr.io/projectbluefin/bluefin-nvidia:stable' .github/workflows/build-nvidia.yml
grep -F 'ghcr.io/projectbluefin/dakota:stable' Containerfile.dakota
grep -R -F 'projectbluefin/actions/bootc-build/' .github/workflows/build*.yml
```

Expected: each documented upstream relationship has repository evidence.

- [ ] **Step 2: Run the full validation suite**

Run:

```bash
npm ci
XDG_RUNTIME_DIR=/tmp just test
npm run cards:check
just --list
git diff --check
```

Expected: PASS with no generated card drift.

- [ ] **Step 3: Inspect final scope**

Run:

```bash
git status --short
git diff --stat
git diff -- README.md docs/ tests/test-card-assets.mjs
```

Expected: only the README rewrite, three supporting documents, test contract,
design spec, and implementation plan are in scope.

- [ ] **Step 4: Commit the implementation**

After user confirmation required by repository policy:

```bash
git add README.md docs/operations.md docs/maintenance.md \
  docs/history/dudleys-second-bedroom-migration.md \
  tests/test-card-assets.mjs \
  docs/superpowers/plans/2026-07-29-operator-readme-rewrite.md
git commit -m "docs: rewrite README for Dudley operators"
```
