# Dudley Operations

This runbook is for operators of an already-published Dudley image. It covers
the canonical image streams and the local commands that the repository
currently provides.

## Inspect and update

Check the deployed image and bootc state, then stage the next update and
reboot into it:

```bash
bootc status
sudo bootc upgrade
sudo systemctl reboot
```

## Switch streams

Use the canonical stream tag and enforce the configured container signature
policy on every switch:

```bash
sudo bootc switch ghcr.io/joshyorko/dudley-os:stable --enforce-container-sigpolicy
sudo bootc switch ghcr.io/joshyorko/dudley-os:nvidia --enforce-container-sigpolicy
sudo bootc switch ghcr.io/joshyorko/dudley-os:dakota --enforce-container-sigpolicy
```

`stable` is the general Bluefin-based stream. `nvidia` is the Bluefin Nvidia
stream. Dakota is experimental: it is a file-only overlay on Project Bluefin
Dakota and still needs boot, update, and rollback qualification before it is
relied on as a daily driver.

## Finish Dakota setup

Dakota is built from source rather than from Fedora packages. Podman and the
real Docker Engine are both included. Docker uses `/run/docker.sock`; its socket
unit starts `dockerd` on demand. Compose and Buildx are installed as Docker CLI
plugins. Dudley's Brewfiles and just recipes are included in the image.

After first login, initialize the portable developer payload:

```bash
ujust dudley-dakota
```

Native Google Chrome is already baked into the image. The setup command
initializes Dakota's Bluefin CLI and Homebrew environment and installs the
Dudley IDE bundle including VS Code Insiders. Dakota's Ghostty default binds
`Ctrl+Alt+T` to a new Ghostty window and starts Linuxbrew Zsh with Zsh shell
integration; Zsh then loads the user's existing `~/.zshrc`. The first-login migration hook
removes the obsolete
`~/.config/environment.d/60-dudley-podman-docker.conf` redirect and clears
`DOCKER_HOST` from the user manager. Restart existing terminals and agent
processes after upgrading so they inherit the corrected environment.

Enroll the logged-in administrator in Dakota's existing development groups,
then start a new login session:

```bash
ujust dx-group
```

Podman remains the native engine supplied by Dakota. Dudley does not install or
redirect it through Homebrew.

Install every formula and cask currently published by Josh's Homebrew tap:

```bash
ujust dudley tools
```

## Roll back

Apply the previous bootc deployment and reboot:

```bash
sudo bootc rollback --apply
sudo systemctl reboot
```

## Build locally

Build the container image from this checkout:

```bash
just build
```

## Build and run a VM

Build the local image, create a QCOW2 disk image, and open it in the
browser-based VM:

```bash
just build
just build-qcow2
just run-vm-qcow2
```

## Dagger helpers

The repository-local Dagger module is for local and ad hoc portable runs;
GitHub Actions uses its own workflow and does not call Dagger. Inspect the
available functions, test the release planner, or use the checked-in `just`
shortcuts:

```bash
just dagger-functions
just dagger-test
just dagger-metadata
just dagger-build
just dagger-release-dry-run
just dagger-publish-local
just dagger-release
```

The full Dagger release path can use key-based signing for an ad hoc registry
when a signing key is supplied. That is separate from the keyless GitHub
Actions publish path.

## Verify a published image

Verify a published Stable image against the repository's GitHub Actions OIDC
identity:

```bash
cosign verify \
  --certificate-identity-regexp "https://github.com/joshyorko/dudley-os/" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/joshyorko/dudley-os:stable
```
