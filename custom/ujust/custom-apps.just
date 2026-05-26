# vim: set ft=make :
####################
### custom-apps.just
####################
## Example application installation commands
## These are simplified examples adapted from Bluefin

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    @ujust dudley brew cli

# Install development tools via Homebrew
[group('Apps')]
install-dev-tools:
    @ujust dudley brew dev

# Install IDE and editor tools via Homebrew
[group('Apps')]
install-ide-tools:
    @ujust dudley brew ide

# Install AI and agent tools via Homebrew
[group('Apps')]
install-ai-tools:
    @ujust dudley brew ai

# Install fonts via Homebrew
[group('Apps')]
install-fonts:
    @ujust dudley brew fonts

# Install Kubernetes tools via Homebrew
[group('Apps')]
install-k8s-tools:
    @ujust dudley brew k8s

# Install all Brewfiles at once
[group('Apps')]
install-all-brew:
    @ujust dudley brew all

# Shortcut for install-jetbrains-toolbox
[group('Apps')]
jetbrains-toolbox:
    @ujust install-jetbrains-toolbox

# Install a Flatpak application from Flathub
[group('Apps')]
install-flatpak APP_ID:
    #!/usr/bin/bash
    echo "Installing {{ APP_ID }} from Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub {{ APP_ID }}

# Install VS Code and related IDE tooling from the shared Dudley IDE bundle
[group('Apps')]
install-vscode:
    @ujust dudley brew ide

# Example: Install GIMP via Flatpak
[group('Apps')]
install-gimp:
    ujust install-flatpak org.gimp.GIMP
