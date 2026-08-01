# Live Release Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the existing Dudley stream cards with a live bottom telemetry rail sourced from GitHub Actions and GHCR after every main-branch image build.

**Architecture:** Keep stream identity and manual qualification in `cards/streams.json`, normalize GitHub workflow and `skopeo inspect` results into versioned JSON records, and render those records through the existing Satori/Resvg card pipeline. A dedicated `workflow_run` workflow builds a complete static Pages artifact containing six card PNGs and three machine-readable status files; failed builds retain last-known-good publication metadata.

**Tech Stack:** Node.js 24 ESM, native `fetch`, `node:test`, Satori, Resvg, PNGJS, `skopeo inspect`, GitHub Actions, GitHub Pages.

## Global Constraints

- Preserve the current Dudley mascot artwork, typography, colors, stream copy, image references, and light/dark variants.
- Render exactly four telemetry cells: `BUILD`, `PUBLISHED`, `DIGEST`, and `QUALIFICATION`.
- Stable and NVIDIA qualification is `Daily driver`; Dakota qualification is `Experimental`.
- A failed or cancelled build changes only the build state; it does not erase last-successful publication metadata.
- Dakota is complete only when `dakota` and `dakota-nvidia` report the same non-empty OCI revision.
- Never infer runtime qualification from build success.
- Never commit generated release status to `main`.
- Keep all third-party GitHub Actions pinned by full commit SHA.
- Use `dnf5` only for image build scripts; CI runs on Ubuntu and may install `skopeo` with `apt-get`.
- Ask Josh immediately before every commit and before any push.
- Do not push directly to `main`; implementation remains on `patchraptor/live-release-cards` and is published through a PR.

## File Structure

- `cards/streams.json`: existing visual identity plus a nested `status` configuration for qualification, workflow filename, and ordered image references.
- `scripts/lib/release-status.mjs`: status record schema, validation, Dakota pair logic, fallback selection, and display formatting; no network or filesystem access.
- `scripts/lib/status-collector.mjs`: dependency-injected orchestration that collects all stream records.
- `scripts/collect-release-status.mjs`: CLI adapter for GitHub REST, Pages fallback JSON, `skopeo`, and filesystem output.
- `scripts/lib/card-template.mjs`: existing visual card plus the telemetry rail.
- `scripts/generate-card-images.mjs`: deterministic fallback rendering and optional live status/output directories.
- `scripts/validate-pages-output.mjs`: validates the complete deployable directory.
- `tests/fixtures/status/*.json`: fixed valid, failed, and incomplete records.
- `tests/test-release-status.mjs`: pure status contract tests.
- `tests/test-status-collector.mjs`: collection orchestration tests with injected adapters.
- `tests/test-card-assets.mjs`: visual structure, dimensions, manifest, and README regression tests.
- `tests/test-pages-output.mjs`: deployable artifact contract tests.
- `.github/workflows/update-release-cards.yml`: collection, rendering, validation, and Pages deployment.
- `.github/workflows/validate-cards.yml`: PR validation coverage for every new card/status file.
- `README.md`: live Pages image URLs and per-stream workflow links.

---

### Task 1: Define the stream status contract

**Files:**
- Modify: `cards/streams.json`
- Create: `scripts/lib/release-status.mjs`
- Create: `tests/test-release-status.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: existing stream objects from `cards/streams.json`.
- Produces: `validateStreamConfig(name, stream)`, `normalizeWorkflowRun(run)`, `parseImageInspection(imageRef, line)`, `buildStatusRecord(input)`, `validateStatusRecord(record)`, and `formatCardStatus(record)`.
- `buildStatusRecord(input)` accepts `{ name, stream, run, images, previous, checkedAt }` and returns the JSON record documented in the approved design.

- [ ] **Step 1: Add failing domain tests**

Create tests with fixed values, including these assertions:

```js
test('failed workflow retains the current successful image metadata', () => {
  const record = buildStatusRecord({
    name: 'stable',
    stream: streams.stable,
    run: { status: 'completed', conclusion: 'failure', html_url: 'https://github.test/runs/10' },
    images: [{
      imageRef: 'ghcr.io/joshyorko/dudley-os:stable',
      digest: `sha256:${'a'.repeat(64)}`,
      at: '2026-08-01T16:30:00Z',
      revision: '9dea5f79a23d18691de954da7fdd7e502ba31e02',
    }],
    previous: undefined,
    checkedAt: '2026-08-01T16:35:00Z',
  });

  assert.equal(record.build.conclusion, 'failure');
  assert.equal(record.published.digest, `sha256:${'a'.repeat(64)}`);
  assert.equal(formatCardStatus(record).buildLabel, 'Failed');
});
```

Also test:

- invalid qualification, workflow filename, digest, timestamp, or image reference throws
- queued/in-progress workflow maps to `Running`
- cancelled workflow maps to `Cancelled`
- successful workflow maps to `Passing`
- a complete Dakota pair requires identical revisions
- an incomplete Dakota pair uses `previous.published` and maps to `Pair incomplete`
- a first-run incomplete pair has `published.at === null` and `published.digest === null`
- digest display removes `sha256:` and returns the first eight hexadecimal characters

- [ ] **Step 2: Run the domain test and verify failure**

Run:

```bash
npm run test:status
```

Expected: FAIL because `scripts/lib/release-status.mjs` and the `test:status` package script do not exist.

- [ ] **Step 3: Extend each stream with exact status configuration**

Add this nested shape while retaining every existing field:

```json
"status": {
  "qualification": "Daily driver",
  "workflowFile": "build.yml",
  "imageRefs": ["ghcr.io/joshyorko/dudley-os:stable"]
}
```

Use `build-nvidia.yml` and the `nvidia` image for NVIDIA. Use `build-dakota.yml`, `dakota` first, and `dakota-nvidia` second for Dakota; set Dakota qualification to `Experimental`.

- [ ] **Step 4: Implement the pure status module**

Use this record shape consistently:

```js
{
  schemaVersion: 1,
  stream: 'stable',
  build: {
    state: 'completed',
    conclusion: 'success',
    runUrl: 'https://github.test/runs/10'
  },
  published: {
    state: 'complete',
    at: '2026-08-01T16:30:00Z',
    digest: 'sha256:...',
    imageRef: 'ghcr.io/joshyorko/dudley-os:stable',
    images: [{ imageRef: '...', digest: 'sha256:...', at: '...', revision: '...' }]
  },
  qualification: 'Daily driver',
  checkedAt: '2026-08-01T16:35:00Z'
}
```

`published.state` is `complete` or `pair_incomplete`. `formatCardStatus(record)` returns:

```js
{
  buildLabel: 'Passing',
  buildTone: 'success',
  publishedLabel: 'Aug 1, 2026',
  digestLabel: '7cc91e2f',
  qualificationLabel: 'Daily driver'
}
```

Return `Not published` and `—` when the first Dakota pair is incomplete and no fallback exists. Use `Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' })` for dates.

- [ ] **Step 5: Add package scripts and run the focused tests**

Add:

```json
"test:status": "node --test tests/test-release-status.mjs"
```

Run:

```bash
npm run test:status
```

Expected: PASS.

- [ ] **Step 6: Request commit confirmation, then commit the status contract**

```bash
git add cards/streams.json scripts/lib/release-status.mjs tests/test-release-status.mjs package.json
git commit -m "feat(cards): define release status contract"
```

---

### Task 2: Collect GitHub and GHCR status

**Files:**
- Create: `scripts/lib/status-collector.mjs`
- Create: `scripts/collect-release-status.mjs`
- Create: `tests/test-status-collector.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: Task 1's stream configuration and `buildStatusRecord(input)`.
- Produces: `collectAllStatuses({ streams, getWorkflowRun, inspectImage, getPreviousStatus, now })` returning an object keyed by stream; CLI writes `<output>/<stream>.json`.
- CLI environment: `GITHUB_TOKEN`, `GITHUB_REPOSITORY`, `GITHUB_REF_NAME`, `STATUS_OUTPUT_DIR`, and optional `STATUS_FALLBACK_BASE_URL`.

- [ ] **Step 1: Write failing collector orchestration tests**

Use injected fakes and assert all three workflow files and four ordered image references are requested:

```js
const records = await collectAllStatuses({
  streams,
  getWorkflowRun: async (workflowFile) => runs[workflowFile],
  inspectImage: async (imageRef) => images[imageRef],
  getPreviousStatus: async (name) => previous[name],
  now: () => new Date('2026-08-01T16:35:00Z'),
});

assert.deepEqual(Object.keys(records).sort(), ['dakota', 'nvidia', 'stable']);
assert.equal(records.dakota.published.images.length, 2);
```

Also prove a thrown GitHub or `skopeo` adapter error rejects the entire collection so incomplete cards cannot deploy.

- [ ] **Step 2: Run the collector test and verify failure**

Run:

```bash
node --test tests/test-status-collector.mjs
```

Expected: FAIL because `status-collector.mjs` does not exist.

- [ ] **Step 3: Implement dependency-injected collection**

In `scripts/lib/status-collector.mjs`, iterate `Object.entries(streams)`, await one workflow lookup, inspect every configured image in order, fetch the optional previous record, and call `buildStatusRecord`. Do not catch required adapter errors in this module.

- [ ] **Step 4: Implement the CLI adapters**

The GitHub adapter calls:

```text
GET https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflowFile}/runs?branch={branch}&per_page=1
```

Send `Authorization: Bearer ${GITHUB_TOKEN}`, `Accept: application/vnd.github+json`, and `X-GitHub-Api-Version: 2022-11-28`. Reject non-2xx responses and reject an empty `workflow_runs` array.

The GHCR adapter runs exactly:

```bash
skopeo inspect --no-tags \
  --format '{{.Digest}}|{{index .Labels "org.opencontainers.image.created"}}|{{index .Labels "org.opencontainers.image.revision"}}' \
  docker://ghcr.io/joshyorko/dudley-os:stable
```

Use `execFileSync` with an argument array, split the single output line on `|`, then pass it to `parseImageInspection`. Do not invoke a shell.

The fallback adapter fetches `${STATUS_FALLBACK_BASE_URL}/${name}.json`. Treat HTTP 404 as no previous record. Reject other non-2xx responses. Validate successful fallback JSON before using it.

Write records with stable formatting using `${JSON.stringify(record, null, 2)}\n`. Accept output paths only inside the repository root or `/tmp`; reject every other destination.

- [ ] **Step 5: Add and run the collector package test**

Extend `test:status`:

```json
"test:status": "node --test tests/test-release-status.mjs tests/test-status-collector.mjs"
```

Run:

```bash
npm run test:status
```

Expected: PASS without network or registry access.

- [ ] **Step 6: Smoke-test the CLI against live public metadata without writing repo files**

Run on the Bluefin host:

```bash
STATUS_OUTPUT_DIR=/tmp/dudley-release-status \
GITHUB_TOKEN="$(gh auth token)" \
GITHUB_REPOSITORY=joshyorko/dudley-os \
GITHUB_REF_NAME=main \
node scripts/collect-release-status.mjs
```

Expected: three valid JSON files in `/tmp/dudley-release-status`; Dakota contains two inspected image entries. Do not print the token.

- [ ] **Step 7: Request commit confirmation, then commit the collector**

```bash
git add scripts/lib/status-collector.mjs scripts/collect-release-status.mjs tests/test-status-collector.mjs package.json
git commit -m "feat(cards): collect live release status"
```

---

### Task 3: Render the bottom telemetry rail

**Files:**
- Create: `tests/fixtures/status/stable.json`
- Create: `tests/fixtures/status/nvidia.json`
- Create: `tests/fixtures/status/dakota.json`
- Modify: `scripts/lib/card-template.mjs`
- Modify: `scripts/generate-card-images.mjs`
- Modify: `tests/test-card-assets.mjs`
- Modify: `static/img/cards/stable-light.png`
- Modify: `static/img/cards/stable-dark.png`
- Modify: `static/img/cards/nvidia-light.png`
- Modify: `static/img/cards/nvidia-dark.png`
- Modify: `static/img/cards/dakota-light.png`
- Modify: `static/img/cards/dakota-dark.png`
- Modify: `static/img/cards/card-hashes.json`

**Interfaces:**
- Consumes: Task 1's validated status records and `formatCardStatus(record)`.
- Produces: `renderCard(stream, theme, mascotDataUri, status)` at logical size `800x380`; PNG output remains rendered at 2x (`1600x760`).
- Generator CLI supports `--check`, `--status-dir <path>`, and `--output-dir <path>`.

- [ ] **Step 1: Add failing telemetry and dimension tests**

Update the expected stream keys to include `status`. Add fixture-based assertions that the rendered element tree contains:

```js
for (const label of ['BUILD', 'PUBLISHED', 'DIGEST', 'QUALIFICATION']) {
  assert.ok(elementWithText(card, label));
}
assert.ok(elementWithText(card, 'Failed'));
assert.ok(elementWithText(card, 'Daily driver'));
```

Change generated PNG expectations from `1600x600` to `1600x760`. Add a structural assertion that the existing title, description, tag, image reference, and mascot remain present above the rail.

- [ ] **Step 2: Run the card test and verify failure**

Run:

```bash
npm run test:cards
```

Expected: FAIL on the new manifest keys, missing telemetry labels, and old image height.

- [ ] **Step 3: Extend the template without redesigning the existing 300-pixel card body**

Set:

```js
export const W = 800;
export const ART_H = 300;
export const STATUS_H = 80;
export const H = ART_H + STATUS_H;
```

Keep the existing art body styles and content unchanged inside a fixed `ART_H` container. Append a four-column status rail. Use uppercase 11-pixel muted labels and 13-pixel bold values. Map `success`, `danger`, and `warning` tones to theme-safe green, red, and amber value colors; keep the rail background consistent with the approved dark telemetry mockup in both themes.

- [ ] **Step 4: Add deterministic generator arguments and fallback records**

Parse arguments without a new dependency. Reject unknown flags, missing flag values, status directories missing any stream JSON, and output directories outside the repository or `/tmp`.

When `--status-dir` is omitted, generate a deterministic unavailable record per stream:

- build label: `Unavailable`
- published label: `Not published`
- digest label: `—`
- configured manual qualification remains visible

This fallback is used only for committed design fixtures and `cards:check`; Pages rendering always supplies live status JSON.

- [ ] **Step 5: Regenerate and verify the committed design fixtures**

Run:

```bash
npm run cards
npm run test:cards
npm run cards:check
```

Expected: all commands PASS; all six PNGs are `1600x760`; the actual Dudley mascot assets remain unchanged.

- [ ] **Step 6: Render live fixtures to a temporary Pages-style directory**

Run:

```bash
node scripts/generate-card-images.mjs \
  --status-dir tests/fixtures/status \
  --output-dir /tmp/dudley-pages/cards
```

Expected: six PNGs with `Passing`, `Failed`, and `Pair incomplete` represented by the fixtures.

- [ ] **Step 7: Request commit confirmation, then commit the renderer**

```bash
git add scripts/lib/card-template.mjs scripts/generate-card-images.mjs tests/fixtures/status tests/test-card-assets.mjs static/img/cards
git commit -m "feat(cards): render live telemetry rail"
```

---

### Task 4: Build and deploy the Pages artifact

**Files:**
- Create: `scripts/validate-pages-output.mjs`
- Create: `tests/test-pages-output.mjs`
- Create: `.github/workflows/update-release-cards.yml`
- Modify: `.github/workflows/validate-cards.yml`
- Modify: `package.json`

**Interfaces:**
- Consumes: Task 2 CLI output in `public/status` and Task 3 renderer output in `public/cards`.
- Produces: a validated `public/` directory containing six PNGs and `status/{stable,nvidia,dakota}.json`.
- Workflow may run by `workflow_dispatch` or completion of any of the three named build workflows on `main`.

- [ ] **Step 1: Write a failing Pages artifact contract test**

Create a temporary directory, populate the required files, and assert `validatePagesOutput(root)` rejects:

- a missing PNG
- a missing status JSON file
- a status file whose `stream` does not match its filename
- a PNG not sized `1600x760`
- an unexpected extra stream status record

It must accept exactly six cards plus three valid records.

- [ ] **Step 2: Run the Pages test and verify failure**

Run:

```bash
node --test tests/test-pages-output.mjs
```

Expected: FAIL because `validate-pages-output.mjs` does not exist.

- [ ] **Step 3: Implement and expose artifact validation**

Export `validatePagesOutput(root)` and add a CLI main guard. Reuse `validateStatusRecord`; use PNGJS for dimensions. Do not accept symlinks or paths outside the supplied root.

Add package scripts:

```json
"cards:live": "node scripts/generate-card-images.mjs --status-dir public/status --output-dir public/cards",
"cards:pages-check": "node scripts/validate-pages-output.mjs public",
"test:cards": "node --test tests/test-card-assets.mjs tests/test-release-status.mjs tests/test-status-collector.mjs tests/test-pages-output.mjs"
```

- [ ] **Step 4: Create the pinned Pages workflow**

Use these exact triggers and permissions:

```yaml
name: Update release cards

on:
  workflow_dispatch:
  workflow_run:
    workflows:
      - Build container image
      - Build Nvidia container image
      - Build Dakota container image
    branches: [main]
    types: [completed]

permissions:
  actions: read
  contents: read
  pages: write
  id-token: write

concurrency:
  group: release-cards
  cancel-in-progress: true
```

Use `ubuntu-24.04`, a `github-pages` environment, and these pinned actions:

```yaml
actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7
actions/configure-pages@45bfe0192ca1faeb007ade9deae92b16b8254a0d # v6.0.0
actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9 # v5.0.0
actions/deploy-pages@cd2ce8fcbc39b97be8ca5fce6e763baed58fa128 # v5.0.0
```

Steps are checkout, Node 24 setup with npm cache, `npm ci`, `sudo apt-get update`, `sudo apt-get install -y skopeo`, collection into `public/status`, `npm run cards:live`, `npm run cards:pages-check`, configure Pages, upload `public`, and deploy.

Set collector environment exactly:

```yaml
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
GITHUB_REPOSITORY: ${{ github.repository }}
GITHUB_REF_NAME: ${{ github.event.repository.default_branch }}
STATUS_OUTPUT_DIR: public/status
STATUS_FALLBACK_BASE_URL: https://joshyorko.github.io/dudley-os/status
```

- [ ] **Step 5: Extend PR validation paths and commands**

Add the new status scripts, tests, fixtures, plan workflow, and `package.json` to `.github/workflows/validate-cards.yml` path filters. Keep `npm ci`, `npm run test:cards`, and `npm run cards:check` as its validation commands.

- [ ] **Step 6: Validate JavaScript, YAML, and the artifact contract**

Run:

```bash
npm run test:cards
npm run cards:check
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/update-release-cards.yml'))"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/validate-cards.yml'))"
git diff --check
```

Expected: PASS.

- [ ] **Step 7: Request commit confirmation, then commit Pages publication**

```bash
git add scripts/validate-pages-output.mjs tests/test-pages-output.mjs .github/workflows/update-release-cards.yml .github/workflows/validate-cards.yml package.json
git commit -m "ci(cards): publish live cards to Pages"
```

---

### Task 5: Point the README at verified live cards

**Files:**
- Modify: `README.md`
- Modify: `tests/test-card-assets.mjs`

**Interfaces:**
- Consumes: Pages URLs created by Task 4.
- Produces: operator-facing live cards whose entire image links to the stream's workflow.

- [ ] **Step 1: Write failing README integration assertions**

For each stream, assert the README contains both Pages theme URLs and the workflow URL. Exact mappings:

```js
const liveCards = {
  stable: 'build.yml',
  nvidia: 'build-nvidia.yml',
  dakota: 'build-dakota.yml',
};
```

Pages base URL is `https://joshyorko.github.io/dudley-os/cards/`. Workflow base URL is `https://github.com/joshyorko/dudley-os/actions/workflows/`.

- [ ] **Step 2: Run the README test and verify failure**

Run:

```bash
npm run test:cards
```

Expected: FAIL because README still references `static/img/cards/`.

- [ ] **Step 3: Wrap every `<picture>` in its workflow link and switch image sources**

Use this exact structure for Stable and the corresponding filenames/workflows for the other streams:

```html
<a href="https://github.com/joshyorko/dudley-os/actions/workflows/build.yml">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://joshyorko.github.io/dudley-os/cards/stable-dark.png">
    <img src="https://joshyorko.github.io/dudley-os/cards/stable-light.png" alt="Dudley stable release card" width="800">
  </picture>
</a>
```

Do not change switch commands, stream qualification prose, daily operation guidance, architecture, or attribution.

- [ ] **Step 4: Run the complete local verification suite**

Run:

```bash
npm ci
XDG_RUNTIME_DIR=/tmp just test
npm run test:cards
npm run cards:check
just --list
git diff --check
```

Run ShellCheck on any modified shell file and safe-load every modified YAML file. Expected: all checks PASS.

- [ ] **Step 5: Review the final diff for scope and generated assets**

Run:

```bash
git status --short
git diff --stat
git diff -- README.md cards scripts tests .github/workflows package.json static/img/cards
```

Expected: only live-card implementation files are changed; no generated cache, credentials, or output directories are present.

- [ ] **Step 6: Request commit confirmation, then commit README integration**

```bash
git add README.md tests/test-card-assets.mjs
git commit -m "docs: publish live release cards"
```

- [ ] **Step 7: Enable Pages with explicit repository-setting approval**

Before changing repository settings, request Josh's approval. Then enable GitHub Pages with GitHub Actions as its source. Do not dispatch the workflow from the feature branch; GitHub requires the workflow to exist on the default branch for the supported rollout path.

- [ ] **Step 8: Request push confirmation, publish the branch, and open a PR**

```bash
git push -u origin patchraptor/live-release-cards
gh pr create --base main --head patchraptor/live-release-cards --title "feat: add live release cards" --body-file /tmp/dudley-live-cards-pr.md
```

The PR body must separate local verification, Pages enablement, and runtime qualification. Do not claim the cards are deployed before the live Pages URLs return the generated assets.

- [ ] **Step 9: Verify the first post-merge deployment**

After the PR is merged, wait for the three image workflows and the resulting `Update release cards` run. If no build completion triggers it, request mutation approval and dispatch it manually from `main`.

Verify:

```bash
ghx run list --workflow update-release-cards.yml --limit 1
curl -fsS https://joshyorko.github.io/dudley-os/status/stable.json | jq '{stream,build,published,qualification}'
curl -fsSI https://joshyorko.github.io/dudley-os/cards/stable-light.png
```

Expected: workflow success, valid Stable JSON, and HTTP 200 with an image content type. Repeat the JSON and image checks for NVIDIA and Dakota.
