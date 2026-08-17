#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fixture="${TMP_DIR}/root"
bin="${TMP_DIR}/bin"
mkdir -p \
    "${fixture}/etc/profile.d" \
    "${fixture}/etc/ublue-os" \
    "${fixture}/etc/umotd" \
    "${fixture}/usr/libexec/dudley" \
    "${fixture}/usr/share/dudley/terminal" \
    "${fixture}/usr/share/ublue-os/just" \
    "${bin}"

cat > "${fixture}/usr/libexec/dudley/ensure-homebrew" <<'EOF'
ensure_dudley_brew() {
    if [[ -n "${DUDLEY_BREW_BIN:-}" && -x "${DUDLEY_BREW_BIN}/brew" ]]; then
        PATH="${DUDLEY_BREW_BIN}:${PATH}"
        export PATH
    fi
    command -v brew >/dev/null
}
EOF
cat > "${fixture}/usr/share/dudley/terminal-contract.json" <<'EOF'
{"defaults":{"initial_size":{"columns":120,"rows":40},"font":{"family":"JetBrains Mono","size":16}}}
EOF
cat > "${fixture}/usr/share/dudley/terminal/ghostty.conf" <<'EOF'
font-family = JetBrains Mono
font-size = 16
window-width = 120
window-height = 40
EOF
printf '%s\n' '#!/usr/bin/env bash' > "${fixture}/etc/profile.d/umotd.sh"
printf '%s\n' '{}' > "${fixture}/etc/ublue-os/tags.json"
printf '%s\n' '{"commands":[{"cmd":"umotd toggle"}]}' > "${fixture}/etc/umotd/config.json"
printf '%s\n' 'dudley:' > "${fixture}/usr/share/ublue-os/just/60-dudley.just"
cat > "${TMP_DIR}/runtime-contract.json" <<'EOF'
{"streams":{"dakota":{"required_ujust":["dudley"]},"stable":{"required_ujust":["dudley"]}}}
EOF

cat > "${bin}/ujust" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "--list" ]]; then
    printf '%s\n' 'dudley'
elif [[ "$*" == "dudley list" ]]; then
    printf '%s\n' 'Available Dudley Brewfiles:'
    for ((line = 0; line < 20000; line++)); do
        printf '%s\n' 'additional Brewfile output'
    done
elif [[ "$*" == "bluefin-cli" ]]; then
    : > "${BOOTSTRAP_MARKER:?}"
    mkdir -p "${HOME}/.linuxbrew/bin"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${HOME}/.linuxbrew/bin/brew"
    chmod +x "${HOME}/.linuxbrew/bin/brew"
else
    exit 2
fi
EOF
cat > "${bin}/umotd" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'Dudley MOTD'
EOF
chmod +x "${bin}/ujust" "${bin}/umotd"

mkdir -p "${fixture}/etc/ghostty"
cat "${fixture}/usr/share/dudley/terminal/ghostty.conf" > "${fixture}/etc/ghostty/config"
printf '%s\n' \
    'command = /home/linuxbrew/.linuxbrew/bin/zsh' \
    'shell-integration = zsh' >> "${fixture}/etc/ghostty/config"

DUDLEY_ROOT="${fixture}" \
DUDLEY_STREAM=dakota \
BOOTSTRAP_MARKER="${TMP_DIR}/bootstrap-attempted" \
DUDLEY_RUNTIME_CONTRACT="${TMP_DIR}/runtime-contract.json" \
PATH="${bin}:/usr/bin:/bin" \
    bash "${ROOT_DIR}/build/18-parity-acceptance.sh"
if [[ -e "${TMP_DIR}/bootstrap-attempted" ]]; then
    echo 'FAIL: parity acceptance attempted interactive Homebrew bootstrap' >&2
    exit 1
fi

mkdir -p "${fixture}/etc/dconf/db/distro.d" "${fixture}/usr/share/dudley/terminal"
printf "%s\n" "font-name='JetBrains Mono 16'" "palette='catppuccin-dynamic'" > \
    "${fixture}/usr/share/dudley/terminal/ptyxis.dconf"
printf '%s\n' "default-columns=120" "default-rows=40" > \
    "${fixture}/etc/dconf/db/distro.d/98-dudley-ptyxis"

DUDLEY_ROOT="${fixture}" \
DUDLEY_STREAM=stable \
BOOTSTRAP_MARKER="${TMP_DIR}/bootstrap-attempted" \
DUDLEY_RUNTIME_CONTRACT="${TMP_DIR}/runtime-contract.json" \
PATH="${bin}:/usr/bin:/bin" \
    bash "${ROOT_DIR}/build/18-parity-acceptance.sh"

cat > "${TMP_DIR}/missing-recipe-contract.json" <<'EOF'
{"streams":{"stable":{"required_ujust":["dudley","missing-recipe"]}}}
EOF
if DUDLEY_ROOT="${fixture}" \
    DUDLEY_STREAM=stable \
    DUDLEY_RUNTIME_CONTRACT="${TMP_DIR}/missing-recipe-contract.json" \
    PATH="${bin}:/usr/bin:/bin" \
    bash "${ROOT_DIR}/build/18-parity-acceptance.sh" >/dev/null 2>&1; then
    echo 'FAIL: parity acceptance ignored a missing required ujust recipe' >&2
    exit 1
fi

grep -Fq '/ctx/build/18-parity-acceptance.sh' "${ROOT_DIR}/build/10-build.sh"
grep -Fq '/ctx/build/18-parity-acceptance.sh' "${ROOT_DIR}/build/10-dakota.sh"
grep -Fq 'COPY build/18-parity-acceptance.sh /build/18-parity-acceptance.sh' \
    "${ROOT_DIR}/Containerfile.dakota"
