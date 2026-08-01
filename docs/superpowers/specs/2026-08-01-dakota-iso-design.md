# Dakota ISO One-Command Build Design

## Goal

Provide one obvious Bluefin-host command, `just build-dakota-iso`, that builds the local Dakota container image and then creates an installer ISO which installs the Dakota stream.

## Design

- Add `just build-dakota` as the reusable container-only entry point. It builds `Containerfile.dakota` as `localhost/dudley-os:dakota` using the base image pin already declared by the Containerfile.
- Add `just build-dakota-iso` as the end-to-end entry point. It invokes `build-dakota`, makes the resulting image available to rootful Podman through the existing `_rootful_load_image` path, and invokes bootc-image-builder with the Dakota installer configuration.
- Add `iso/dakota.toml`, matching the existing installer configuration except that its post-install bootc target is `ghcr.io/joshyorko/dudley-os:dakota`.
- Keep the existing Stable `build-iso` behavior unchanged.
- Write the generated installer to the existing `output/bootiso/install.iso` path.

## Error Handling

The recipe stops on container build, rootful image transfer, or bootc-image-builder failure. It clears the mismatched `SSH_ASKPASS` environment variable before using the repository's existing sudo handling, avoiding the broken graphical askpass path while preserving an interactive sudo prompt.

## Verification

- Extend `tests/test-dakota-variant-contract.sh` first so it requires the two recipes, the dedicated config, the Dakota image target, and the one-command dependency.
- Confirm the new assertion fails before implementation.
- Run the focused Dakota contract test after implementation.
- Run `just --list`, Justfile formatting validation, TOML parsing, `git diff --check`, and the repository test suite.

## Documentation

Document `just build-dakota-iso` as the supported local Dakota installer command and retain the experimental qualification warning.
