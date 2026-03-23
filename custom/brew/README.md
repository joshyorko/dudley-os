# Homebrew Integration

This directory contains example Brewfile declarations for finpilot-style repos.

For `dudley-os`, the shipped Dudley Brewfile payload is expected to come from `dsb-common` under `system_files/dudley/usr/share/ublue-os/homebrew/` and arrive in the image at `/usr/share/ublue-os/homebrew/`.

## What are Brewfiles?

Brewfiles are Homebrew's way of declaring packages in a declarative format. They allow you to specify which packages, taps, and casks you want installed.

## How It Works

1. **During Build (general finpilot pattern)**: Brewfiles can be copied to `/usr/share/ublue-os/homebrew/` in the image
2. **After Installation**: Users install packages by running `brew bundle` commands
3. **User Experience**: Declarative package management via Homebrew

## Usage

### Adding Brewfiles to Your Image

1. In Dudley, update the Dudley payload in `dsb-common`
2. Add your desired packages using Brewfile syntax
3. Build your image - the Dudley layer provides the Brewfiles at `/usr/share/ublue-os/homebrew/`

**Current Dudley payload files live in `dsb-common`:**
- `dudley-cli.Brewfile`
- `dudley-dev.Brewfile`
- `dudley-fonts.Brewfile`
- `dudley-k8s.Brewfile`

### Installing Packages from Brewfiles

After booting into your custom image, install packages with:

```bash
brew bundle --file /usr/share/ublue-os/homebrew/dudley-cli.Brewfile
```

Or use the convenient ujust commands defined in [`custom/ujust/custom-apps.just`](../ujust/custom-apps.just):
```bash
ujust install-default-apps
ujust install-dev-tools
ujust install-fonts
```

## File Format

Brewfiles use Ruby syntax:

```ruby
# Add a tap (third-party repository)
tap "homebrew/cask"

# Install a formula (CLI tool)
brew "bat"
brew "eza"
brew "ripgrep"

# Install a cask (GUI application, macOS only)
cask "visual-studio-code"
```

## Customization

For Dudley, update the payload files in `dsb-common`:
- `dudley-cli.Brewfile`
- `dudley-dev.Brewfile`
- `dudley-fonts.Brewfile`
- `dudley-k8s.Brewfile`

When you add or rename Dudley Brewfiles, update the corresponding glue commands in [`custom/ujust/custom-apps.just`](../ujust/custom-apps.just) so the runtime install shortcuts continue to point at the layered files.

## Resources

- [Homebrew Documentation](https://docs.brew.sh/)
- [Brewfile Documentation](https://github.com/Homebrew/homebrew-bundle)
- [Bluefin Homebrew Guide](https://docs.projectbluefin.io/administration#homebrew)
