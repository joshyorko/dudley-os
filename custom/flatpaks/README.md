# Flatpak Preinstall Integration

This directory contains example Flatpak preinstall configuration for finpilot-style repos.

For `dudley-os`, the shipped Dudley Flatpak payload is expected to come from `dsb-common` under `system_files/dudley/etc/flatpak/preinstall.d/` and arrive in the image at `/etc/flatpak/preinstall.d/`.

## What is Flatpak Preinstall?

Flatpak preinstall is a feature that allows system administrators to define Flatpak applications that should be installed on first boot. These files are read by the Flatpak system integration and automatically install the specified applications.

## How It Works

1. **During Build (general finpilot pattern)**: Flatpak preinstall files can be copied to `/etc/flatpak/preinstall.d/` in the image
2. **On First Boot**: After user setup completes, the system reads these files and installs the specified Flatpaks
3. **User Experience**: Applications appear automatically after first login

## Important: Installation Timing

**Flatpaks are NOT included in the ISO or container image.** They are downloaded and installed after:
- User completes initial system setup
- Network connection is established
- First boot process runs `flatpak preinstall`

This means:
- The ISO remains small and bootable offline
- Users need an internet connection after installation
- First boot may take longer while Flatpaks download and install
- This is NOT an offline ISO with pre-embedded applications

## File Format

Each file uses the INI format with `[Flatpak Preinstall NAME]` sections:

```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable

[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
```

**Keys:**
- `Install` - (boolean) Whether to install (default: true)
- `Branch` - (string) Branch name (default: "master", commonly "stable")
- `IsRuntime` - (boolean) Whether this is a runtime (default: false for apps)
- `CollectionID` - (string) Collection ID of the remote, if any

See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall

## Usage

### Adding Flatpaks to Your Image

1. In Dudley, update the Dudley payload in `dsb-common`
2. Add Flatpak references in INI format with `[Flatpak Preinstall NAME]` sections
3. Build your image - the Dudley layer provides the files at `/etc/flatpak/preinstall.d/`
4. After user setup completes, Flatpaks will be automatically installed

**Current Dudley payload files live in `dsb-common`:**
- `dudley-default.preinstall`
- `dudley-dx.preinstall`

### Finding Flatpak IDs

To find the ID of a Flatpak:
```bash
flatpak search app-name
```

Or browse Flathub: https://flathub.org/

## Customization

For Dudley, update the payload files in `dsb-common`:
- `dudley-default.preinstall`
- `dudley-dx.preinstall`

Those files are layered in by the `dsb-common/dudley` contract during the build. See [`build/10-build.sh`](../../build/10-build.sh) for the Dudley assembly order.

## Important Notes

- Files must use the `.preinstall` extension
- Comments can be added with `#`
- Empty lines are ignored
- **Flatpaks are downloaded from Flathub on first boot** - not embedded in the image
- **Internet connection required** after installation for Flatpaks to install
- Installation happens automatically after user setup completes
- Users can still uninstall these applications if desired
- First boot will take longer while Flatpaks are being installed

## Resources

- [Flatpak Documentation](https://docs.flatpak.org/)
- [Flatpak Preinstall Reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall)
- [Flathub](https://flathub.org/)
