# Live Release Cards Design

## Goal

Turn the existing Stable, NVIDIA, and Dakota README cards into compact operational summaries that update after each main-branch image workflow. Preserve the current Dudley artwork, typography, colors, stream copy, image references, and light/dark variants.

Each card adds a bottom telemetry rail with:

- latest build state
- last successful publication date
- short image digest
- manually maintained qualification state

A failed or cancelled build must remain visible without implying that the last successfully published image disappeared.

## Non-goals

- Do not create a request-time rendering service.
- Do not commit generated release status to `main`.
- Do not infer runtime qualification from a successful build.
- Do not replace the current Dudley card art or mascot assets.
- Do not make Dakota appear equivalent to the Stable or NVIDIA daily-driver streams.

## User experience

The existing 800-pixel-wide card remains the visual source. Its canvas grows vertically to add a full-width telemetry rail beneath the current content. The rail uses four fixed cells so all streams scan consistently:

| Field | Value source | Example |
| --- | --- | --- |
| Build | Latest main-branch workflow run | `Passing`, `Failed`, `Cancelled`, `Running` |
| Published | OCI creation metadata for the current successful tag | `Aug 1, 2026` |
| Digest | Registry digest for the current successful tag | `7cc91e2f` |
| Qualification | Manual stream configuration | `Daily driver`, `Experimental` |

Build state controls the status color. Passing is green, failed is red, and cancelled or running is amber. Published metadata is independent from build state and always describes the last successful image.

The initial qualification values are:

- Stable: `Daily driver`
- NVIDIA: `Daily driver`
- Dakota: `Experimental`

The README continues using `<picture>` elements for light/dark selection. The image URLs move from committed PNGs to the GitHub Pages deployment. Each card links to its corresponding GitHub Actions workflow for investigation.

## Architecture

### Status collection

A new release-card workflow runs on `workflow_run` completion for:

- `Build container image`
- `Build Nvidia container image`
- `Build Dakota container image`

The trigger is restricted to the default branch. A shared concurrency group serializes card publication and allows a newer run to supersede an older pending update.

On every invocation, the workflow rebuilds the complete status view rather than patching only the triggering stream. It queries GitHub Actions for the latest default-branch run of each build workflow and inspects the public GHCR tags:

- `ghcr.io/joshyorko/dudley-os:stable`
- `ghcr.io/joshyorko/dudley-os:nvidia`
- `ghcr.io/joshyorko/dudley-os:dakota`
- `ghcr.io/joshyorko/dudley-os:dakota-nvidia`

The collector writes one normalized record per displayed stream:

```json
{
  "stream": "stable",
  "build": {
    "state": "completed",
    "conclusion": "success",
    "runUrl": "https://github.com/joshyorko/dudley-os/actions/runs/123"
  },
  "published": {
    "at": "2026-08-01T16:30:00Z",
    "digest": "sha256:7cc91e2f...",
    "imageRef": "ghcr.io/joshyorko/dudley-os:stable"
  },
  "qualification": "Daily driver",
  "checkedAt": "2026-08-01T16:35:00Z"
}
```

The renderer consumes normalized records and never performs network access. This keeps card output deterministic and makes every visual state testable with fixtures.

### Manual stream data

`cards/streams.json` remains the source for title, description, image reference, tag, accent, mascot, and switch command. It gains the qualification field and the workflow/tag identifiers required by the collector. Qualification changes remain normal reviewed repository changes.

### Dakota pair contract

Dakota is one displayed stream backed by two published images. Its build state comes from the Dakota matrix workflow. The collector inspects both `dakota` and `dakota-nvidia`.

If the workflow fails or only one member of the pair reflects the newest successful publication, the card reports `Pair incomplete`. It retains the previous complete pair's publication date and uses the primary `dakota` digest in the compact digest cell. The machine-readable Dakota JSON includes metadata for both image references.

Before inspection, the collector reads the currently deployed Dakota status JSON from Pages when available. That record is the last-known-complete fallback if a later matrix run publishes only one image. On the first deployment, an incomplete pair has no publication date or digest and says `Pair incomplete` rather than presenting partial metadata as a valid release.

### Rendering and publication

The existing Satori/Resvg generator is extended to accept a status directory. It renders:

- `stable-light.png`
- `stable-dark.png`
- `nvidia-light.png`
- `nvidia-dark.png`
- `dakota-light.png`
- `dakota-dark.png`

The Pages artifact also includes the three normalized status JSON records. GitHub Pages is deployed through GitHub Actions using the repository `GITHUB_TOKEN`, Pages permissions, and OIDC. No long-lived deployment secret or status commit is required.

GitHub Pages must be enabled once with GitHub Actions as its source before the first deployment. That repository setting is an explicit rollout step, not something the build workflows silently mutate.

The current committed cards remain deterministic design fixtures and local fallbacks. Live README images come from the Pages deployment.

## Failure handling

- A failed build displays `Failed`; published date and digest remain from the current GHCR tag.
- A cancelled build displays `Cancelled`; published date and digest remain unchanged.
- A running latest workflow displays `Running` until a completion event triggers another refresh.
- An incomplete Dakota pair displays `Pair incomplete` and retains the previous complete pair metadata.
- A GitHub API or GHCR inspection failure stops the update before deployment. The last successful Pages deployment remains available.
- Invalid or incomplete normalized JSON fails rendering rather than producing a misleading card.
- A Pages deployment failure leaves the previous deployment serving unchanged assets.

GitHub's README image proxy may cache Pages images for several minutes. The Pages assets and JSON are authoritative immediately after deployment; the rendered README may lag briefly.

## Security and permissions

The status workflow receives only the permissions needed to read repository state and deploy Pages. Registry inspection uses public GHCR metadata. The workflow does not execute code from pull requests and does not expose secrets to pull-request contexts.

All third-party actions remain digest-pinned and Renovate-managed according to repository policy.

## Verification

Automated tests cover:

- success, failure, cancellation, and running build states
- failed builds retaining the last successful publication date and digest
- all three manual qualification values
- complete and incomplete Dakota image pairs
- required normalized JSON fields and invalid-record rejection
- deterministic light/dark rendering for all streams
- preservation of the current Dudley mascot, typography, colors, and stream identity
- a Pages artifact containing six cards and three status records
- README URLs and workflow links for every stream

Repository verification before implementation commits includes:

```bash
npm ci
XDG_RUNTIME_DIR=/tmp just test
npm run test:cards
npm run cards:check
just --list
git diff --check
```

Modified shell files receive ShellCheck validation, and modified YAML files receive safe-load validation before commit.

## Acceptance criteria

1. Each README stream card shows the four approved telemetry fields in a bottom rail without replacing the existing card design.
2. A main-branch build completion refreshes the Pages assets for all streams.
3. A failed build is visible while the last successful image date and digest remain visible.
4. Stable and NVIDIA show `Daily driver`; Dakota shows `Experimental`.
5. Dakota reports an incomplete paired publication explicitly.
6. Generated status JSON is published alongside the card images for operators and agents.
7. The workflow never commits generated status to `main` and needs no long-lived secret.
