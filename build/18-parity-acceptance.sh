#!/usr/bin/env bash
set -euo pipefail

stream="${DUDLEY_STREAM:?DUDLEY_STREAM is required}"
root="${DUDLEY_ROOT:-}"
runtime_contract="${DUDLEY_RUNTIME_CONTRACT:-/ctx/contract/dudley-runtime.v1.json}"

if [[ -n "${BASE_IMAGE_REF:-}" ]]; then
    jq -e --arg stream "${stream}" --arg base "${BASE_IMAGE_REF}" \
        '.streams[$stream].accepted_base_refs | index($base) != null' \
        "${runtime_contract}" >/dev/null
fi

root_path() {
    printf '%s%s\n' "${root}" "$1"
}

for command in jq ujust umotd; do
    command -v "${command}" >/dev/null
done

for required in \
    /etc/ublue-os/tags.json \
    /etc/umotd/config.json \
    /usr/libexec/dudley/ensure-homebrew \
    /usr/share/dudley/terminal-contract.json \
    /usr/share/ublue-os/just/60-dudley.just; do
    test -e "$(root_path "${required}")"
done

contract="$(root_path /usr/share/dudley/terminal-contract.json)"
jq -e '
    .defaults.initial_size.columns == 120 and
    .defaults.initial_size.rows == 40 and
    .defaults.font.family == "JetBrains Mono" and
    .defaults.font.size == 16
' "${contract}" >/dev/null
jq -e 'any(.commands[]; .cmd == "umotd toggle")' \
    "$(root_path /etc/umotd/config.json)" >/dev/null

acceptance_home="$(mktemp -d)"
trap 'rm -rf "${acceptance_home}"' EXIT

HOME="${acceptance_home}" ujust --list > "${acceptance_home}/ujust-list"
available_recipes="$(awk '{print $1}' "${acceptance_home}/ujust-list")"
while IFS= read -r recipe; do
    grep -Fxq "${recipe}" <<< "${available_recipes}"
done < <(jq -r --arg stream "${stream}" '.streams[$stream].required_ujust[]' "${runtime_contract}")
dudley_list="$(HOME="${acceptance_home}" ujust dudley list)"
grep -Fq 'Available Dudley Brewfiles:' <<< "${dudley_list}"

# shellcheck disable=SC1090
source "$(root_path /usr/libexec/dudley/ensure-homebrew)"
acceptance_brew_bin="${acceptance_home}/brew/bin"
install -d -m 0755 "${acceptance_brew_bin}"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "${acceptance_brew_bin}/brew"
chmod 0755 "${acceptance_brew_bin}/brew"
(
    export HOME="${acceptance_home}"
    export DUDLEY_BREW_BIN="${acceptance_brew_bin}"
    ensure_dudley_brew
    command -v brew >/dev/null
)

motd="$(HOME="${acceptance_home}" umotd)"
grep -q '[^[:space:]]' <<< "${motd}"

case "${stream}" in
    dakota|dakota-nvidia)
        ghostty="$(root_path /etc/ghostty/config)"
        for setting in \
            'font-family = JetBrains Mono' \
            'font-size = 16' \
            'window-width = 120' \
            'window-height = 40' \
            'command = /home/linuxbrew/.linuxbrew/bin/zsh' \
            'shell-integration = zsh'; do
            grep -Fq "${setting}" "${ghostty}"
        done
        ! grep -Fq 'ujust bluefin-cli' "$(root_path /etc/umotd/config.json)"
        ;;
    stable|nvidia)
        test -e "$(root_path /etc/profile.d/umotd.sh)"
        ptyxis="$(root_path /usr/share/dudley/terminal/ptyxis.dconf)"
        grep -Fq "font-name='JetBrains Mono 16'" "${ptyxis}"
        grep -Fq "palette='catppuccin-dynamic'" "${ptyxis}"
        ;;
    *)
        echo "Unsupported Dudley stream: ${stream}" >&2
        exit 1
        ;;
esac

echo "PASS: ${stream} satisfies the assembled Dudley parity contract"
