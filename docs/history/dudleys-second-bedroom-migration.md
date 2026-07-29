# dudleys-second-bedroom Migration History

This is a historical record of the migration from the legacy
`dudleys-second-bedroom` repository. It preserves the ownership decisions made
during that migration; it is not an operator setup guide.

| Legacy area | Status | Dudley-os outcome |
| --- | --- | --- |
| `custom_wallpapers/` | now owned by `dsb-common` | Dudley wallpapers are consumed from `/system_files/dudley/usr/share/backgrounds/dudley`; no local wallpaper assets are kept here |
| `system_files/` shared defaults, Dudley opinion payloads, and runtime wallpaper randomizer files | now owned by `dsb-common` | Shared defaults plus Dudley data payloads are consumed from the shared OCI layer before local product glue |
| `brew/` (`dudley-cli`, `dudley-dev`, `dudley-fonts`, `dudley-k8s`) | now owned by `dsb-common` | Dudley Homebrew manifests are consumed from `dsb-common/dudley/usr/share/ublue-os/homebrew/` rather than local `custom/brew/` data |
| `flatpaks/` | now owned by `dsb-common` | Dudley Flatpak declarative payload is consumed from `dsb-common/dudley/etc/flatpak/preinstall.d/` rather than local `custom/flatpaks/` data |
| `vscode-extensions.list` | now owned by `dsb-common` | Dudley extension payload is consumed from `dsb-common/dudley/usr/share/ublue-os/vscode-extensions.list` |
| `build_files/developer/vscode-insiders.sh` | retired | VS Code Insiders is now a Homebrew cask opinion in `dsb-common` and installs through the Dudley dev Brewfile rather than final image assembly |
| `build_files/user-hooks/10-wallpaper-enforcement.sh` | still owned by `dudley-os` | Preserved as a first-login hook that consumes the shared Dudley wallpaper directory and prefers the shared `dudley-random-wallpaper` runtime when present |
| `build_files/user-hooks/20-vscode-extensions.sh` | now owned by `dsb-common` | Dudley now relies on the shared hook asset at `/usr/share/ublue-os/user-setup.hooks.d/20-dudley-vscode-extensions.sh` and keeps no local duplicate |
| Product-specific package/config logic in `Containerfile`, `Justfile`, `packages.json`, and `build_files/` | mixed | Dudley opinion/data moved to `dsb-common`; final assembly/build glue remains in this repo; the monolithic `packages.json` manifest is intentionally dropped in favor of thin-repo assembly logic. Google Chrome and the Project Bluefin DX compatibility packages are baked here. |
