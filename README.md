# dudley-os

Dudley is Josh's personal [Project Bluefin](https://projectbluefin.io) variant: a bootc operating-system image that keeps Bluefin's desktop and userland contract while adding Dudley-specific defaults, tools, and release streams.

<p align="center">
  <a href="static/img/dudley-os-clever-girl-golden-bedroom.png">
    <img src="static/img/dudley-os-clever-girl-golden-bedroom.png" alt="Dudley OS Clever Girl in the Golden Bedroom" width="800">
  </a>
</p>

> **Upstream foundation:** Dudley is built on [Project Bluefin](https://projectbluefin.io) and its [documentation](https://docs.projectbluefin.io), published with [Project Bluefin Actions](https://github.com/projectbluefin/actions), and grounded in the [Universal Blue](https://universal-blue.org) and [bootc](https://containers.github.io/bootc/) ecosystems.

## Choose a stream

Stable is the general daily-driver stream.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="static/img/cards/stable-dark.png">
  <img src="static/img/cards/stable-light.png" alt="Dudley stable release card" width="800">
</picture>

```bash
sudo bootc switch ghcr.io/joshyorko/dudley-os:stable --enforce-container-sigpolicy
```

NVIDIA is the daily-driver stream for systems that need Project Bluefin's NVIDIA runtime.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="static/img/cards/nvidia-dark.png">
  <img src="static/img/cards/nvidia-light.png" alt="Dudley nvidia release card" width="800">
</picture>

```bash
sudo bootc switch ghcr.io/joshyorko/dudley-os:nvidia --enforce-container-sigpolicy
```

Dakota is experimental. It is a narrow file-only overlay and still requires boot, update, and rollback qualification before daily-driver use.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="static/img/cards/dakota-dark.png">
  <img src="static/img/cards/dakota-light.png" alt="Dudley dakota release card" width="800">
</picture>

```bash
sudo bootc switch ghcr.io/joshyorko/dudley-os:dakota --enforce-container-sigpolicy
```

## Daily operation

Inspect the active deployment, stage an update, and reboot into it:

```bash
bootc status
sudo bootc upgrade
sudo systemctl reboot
```

If the new deployment is unsuitable, apply the previous deployment:

```bash
sudo bootc rollback --apply
```

See the [operator runbook](docs/operations.md) for stream switching, VM workflows, and image verification. Project Bluefin's [documentation](https://docs.projectbluefin.io) is the source for inherited upstream behavior.

## What Dudley adds

Stable and NVIDIA add the Dudley product layer while retaining their Project Bluefin bases:

- shared DSB defaults and Dudley payload from `dsb-common`
- Dudley wallpapers, runtime Brewfiles, Flatpak declarations, VS Code payload, hooks, and recipes
- DX-style container, virtualization, and developer runtime additions
- Google Chrome installed into the image
- Dudley identity, metadata, validation, publishing, and local product glue

Dakota deliberately carries less. It uses an allowlisted file overlay and excludes Fedora/RPM/DNF, Chrome RPM, Docker, and libvirt host payload.

## Architecture

| Layer | Responsibility |
| --- | --- |
| Project Bluefin | Base images, desktop and userland contract, bootc integration, and shared build/publish actions |
| `dsb-common` | Shared DSB defaults plus Dudley wallpapers, Brewfiles, Flatpak declarations, VS Code payload, hooks, and recipes |
| `dudley-os` | Stream assembly, DX-style runtime additions, Chrome image install, final metadata, validation, publishing, and local product glue |

Stable and NVIDIA are assembled in this order:

1. Project Bluefin stream base
2. `dsb-common/shared`
3. `dsb-common/dudley`
4. local `dudley-os` assembly

Dakota uses the same ownership boundaries but applies only its allowlisted file overlay to the Project Bluefin Dakota base. Detailed change-placement and stream-input guidance lives in [Maintenance and ownership](docs/maintenance.md).

## Build, trust, and release

Renovate pins image and action dependencies by digest. Project Bluefin Actions handles runner setup, preflight, image push, keyless signing, and GitHub provenance. Pushes to `main` publish Stable, NVIDIA, and Dakota. CI SBOM publication is disabled.

Verify the published Stable image against this repository's GitHub Actions OIDC identity:

```bash
cosign verify \
  --certificate-identity-regexp "https://github.com/joshyorko/dudley-os/" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/joshyorko/dudley-os:stable
```

## Local verification

Run the repository checks before opening a pull request:

```bash
npm ci
just test
npm run test:cards
npm run cards:check
```

Build and exercise a local VM when an image-level change needs runtime proof:

```bash
just build
just build-qcow2
just run-vm-qcow2
```

Build the experimental Dakota container and its correctly targeted installer ISO in one command:

```bash
just build-dakota-iso
```

The installer is written to `output/bootiso/install.iso`. Dakota still requires boot, update, and rollback qualification before daily-driver use.

## Repository map

| Path | Purpose |
| --- | --- |
| `Containerfile` | Stable and NVIDIA final image assembly |
| `Containerfile.dakota` | Experimental Dakota allowlisted overlay |
| `build/` | Build-time product assembly and validation |
| `custom/` | Dudley-only product files and ujust wiring |
| `.github/workflows/` | Stream validation and publication |
| `tests/` | Image, workflow, and documentation contracts |
| `docs/` | Operator, maintenance, and historical detail |

Supporting documents:

- [Operator runbook](docs/operations.md)
- [Maintenance and ownership](docs/maintenance.md)
- [Legacy migration record](docs/history/dudleys-second-bedroom-migration.md)

## Upstream and supporting projects

- [Project Bluefin](https://projectbluefin.io) provides Dudley's base images and inherited desktop experience.
- [Project Bluefin documentation](https://docs.projectbluefin.io) documents the upstream operating model.
- [Project Bluefin Actions](https://github.com/projectbluefin/actions) provides Dudley's shared build, publish, signing, and provenance actions.
- [`dsb-common`](https://github.com/joshyorko/dsb-common) owns reusable DSB and Dudley payload.
- [Universal Blue](https://universal-blue.org) is the broader image ecosystem.
- [bootc](https://containers.github.io/bootc/) provides the transactional image-based operating-system model.
