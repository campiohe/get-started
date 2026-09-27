#!/usr/bin/env bash
#
# Verify what install.sh was supposed to set up. Read-only: changes nothing.
# Exit status is non-zero if any check failed.
#
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
set +e +o pipefail  # a failing check must report, not abort

CLANG_VERSION="${CLANG_VERSION:-22}"
PASS=0; FAIL=0; WARN=0

# True when the active profile enables this module. With no profile, check
# everything rather than nothing - a doctor that skips silently is useless.
module_active() {
    [ -z "${PROFILE_NAME:-}" ] && return 0
    local wanted="$1" name
    for name in "${MODULES[@]}"; do
        [ "$name" = "$wanted" ] && return 0
    done
    return 1
}

section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }
ok()   { printf '  %s✔%s %s\n' "$GREEN"  "$RESET" "$1"; PASS=$((PASS+1)); }
bad()  { printf '  %s✘%s %s\n' "$RED"    "$RESET" "$1"; FAIL=$((FAIL+1)); }
meh()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; WARN=$((WARN+1)); }

# check_cmd <command> [version-flag]
check_cmd() {
    local c="$1" flag="${2:---version}" v
    if have "$c"; then
        v="$("$c" $flag 2>/dev/null | head -1 | cut -c1-60)"
        ok "$(printf '%-18s %s' "$c" "${v:-present}")"
    else
        bad "$(printf '%-18s %s' "$c" 'not on PATH')"
    fi
}

check_pkg()  { pkg_installed "$1" && ok "$(printf '%-34s %s' "$1" 'installed')" || bad "$(printf '%-34s %s' "$1" 'missing')"; }
check_file() { [ -e "$1" ] && ok "${1/#$HOME/\~}" || bad "${1/#$HOME/\~} missing"; }
check_dir()  { [ -d "$1" ] && ok "${1/#$HOME/\~}" || bad "${1/#$HOME/\~} missing"; }
check_group(){ id -nG "$USER" | tr ' ' '\n' | grep -qx "$1" && ok "member of group $1" || bad "not in group $1 (re-login after install?)"; }

printf '%sget-started doctor%s  -  %s%s\n' "$BOLD" "$RESET" "$(. /etc/os-release && echo "$PRETTY_NAME")" "$(is_wsl && echo ' (WSL)')"

if [ -n "${PROFILE_NAME:-}" ]; then
    printf 'profile: %s%s%s\n' "$BOLD" "$PROFILE_NAME" "$RESET"
else
    meh "no profile resolved; checking everything. Run ./install.sh --profile NAME first."
fi

if module_active sudo; then
    section "sudo"
    # `sudo -n true` alone is a false positive when credentials are merely cached,
    # so check that the sudoers drop-in actually exists.
    if sudo -n test -f "/etc/sudoers.d/99-$(id -un)-nopasswd" 2>/dev/null; then
        ok "/etc/sudoers.d/99-$(id -un)-nopasswd present"
    elif sudo -n true 2>/dev/null; then
        meh "sudo is not prompting, but the drop-in is absent (cached credentials?)"
    else
        meh "passwordless sudo not configured (module skipped?)"
    fi
else
    section "sudo"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active locale; then
    section "locale & timezone"
    tz="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null)"
    [ -n "$tz" ] && ok "timezone $tz  ($(date))" || bad "timezone not set"
    if locale -a 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '-' | grep -qx "$(echo "${LOCALE:-en_US.UTF-8}" | tr 'A-Z' 'a-z' | tr -d '-')"; then
        ok "locale ${LOCALE:-en_US.UTF-8} generated"
    else
        bad "locale ${LOCALE:-en_US.UTF-8} not generated (LANG=${LANG:-unset})"
    fi
else
    section "locale"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active base; then
    section "base tools"
    for c in nala aptitude fzf croc w3m; do check_cmd "$c"; done
    have bat && ok "$(printf '%-18s %s' bat "$(bat --version 2>/dev/null | head -1)")" \
             || { have batcat && meh "only 'batcat' exists; ~/.local/bin/bat symlink missing" || bad "bat/batcat missing"; }
else
    section "base"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active shell; then
    section "shell"
    [ "$(getent passwd "$USER" | cut -d: -f7)" = "$(command -v zsh)" ] && ok "zsh is the login shell" || bad "login shell is $(getent passwd "$USER" | cut -d: -f7), not zsh"
    check_dir "$HOME/.oh-my-zsh"
    for p in "${ZSH_PLUGINS[@]:-}"; do
        # Built-ins ship with oh-my-zsh; only the cloned ones have a directory.
        [ -n "${ZSH_PLUGIN_SOURCES[$p]:-}" ] || continue
        check_dir "$HOME/.oh-my-zsh/custom/plugins/$p"
    done
    for c in starship zoxide mise eza; do check_cmd "$c"; done
    font="${NERD_FONT:-FiraCode}"
    compgen -G "$HOME/.local/share/fonts/${font}NerdFont*" >/dev/null && ok "$font Nerd Font installed" || bad "$font Nerd Font missing"
    [ -f "$HOME/.config/starship.toml" ] && ok "starship.toml present" || meh "no starship.toml (using starship defaults)"
else
    section "shell"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active cpp; then
    section "C/C++ (clang $CLANG_VERSION)"
    for c in cmake ninja gdb doxygen dot; do check_cmd "$c"; done
    for c in clang clang++ clangd clang-format clang-tidy; do
        if have "$c"; then
            v="$("$c" --version 2>/dev/null | grep -oE 'version [0-9]+' | head -1 | awk '{print $2}')"
            if [ "$v" = "$CLANG_VERSION" ]; then ok "$(printf '%-18s version %s' "$c" "$v")"
            else meh "$(printf '%-18s version %s (expected %s)' "$c" "${v:-?}" "$CLANG_VERSION")"; fi
        else
            bad "$(printf '%-18s %s' "$c" 'not on PATH')"
        fi
    done
    have run-clang-tidy && ok "run-clang-tidy on PATH (projects call it unversioned)" || bad "run-clang-tidy not on PATH"
else
    section "cpp"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active embedded; then
    section "embedded"
    check_cmd arm-none-eabi-gcc
    check_cmd arm-none-eabi-g++
    check_cmd gdb-multiarch
    check_pkg libstdc++-arm-none-eabi-newlib
    check_pkg libnewlib-arm-none-eabi
    for c in openocd st-info dfu-util; do check_cmd "$c"; done
    for g in "${EMBEDDED_GROUPS[@]:-dialout plugdev}"; do check_group "$g"; done
else
    section "embedded"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active python; then
    section "python"
    check_cmd python3
    check_cmd pipx
    for c in "${PIPX_TOOLS[@]:-}"; do [ -n "$c" ] && check_cmd "$c"; done
else
    section "python"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active rust; then
    section "rust"
    for c in rustc cargo rustup; do check_cmd "$c"; done
    "$HOME/.cargo/bin/rustup" component list --installed 2>/dev/null | grep -q rust-analyzer && ok "rust-analyzer component" || meh "rust-analyzer component missing"
else
    section "rust"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active docker; then
    section "docker"
    check_cmd docker
    check_group docker
    if docker info >/dev/null 2>&1; then ok "docker daemon reachable"
    else bad "cannot talk to the docker daemon (needs re-login, or systemd not running)"; fi
    docker compose version >/dev/null 2>&1 && ok "docker compose plugin" || bad "docker compose plugin missing"
else
    section "docker"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active github; then
    section "github"
    check_cmd gh
    gh auth status >/dev/null 2>&1 && ok "gh authenticated as $(gh api user --jq .login 2>/dev/null)" || bad "gh not authenticated"
    check_file "$HOME/.ssh/id_ed25519"
    # github always exits 1 here ("does not provide shell access"), so the banner has
    # to be captured and matched separately -- piping into grep would report failure
    # under the `pipefail` inherited from lib.sh.
    ssh_banner="$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -T git@github.com 2>&1)"
    if printf '%s' "$ssh_banner" | grep -q 'successfully authenticated'; then
        ok "SSH key authenticates to github.com"
    else
        bad "SSH key does not authenticate to github.com"
    fi
else
    section "github"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active latex; then
    section "latex"
    check_cmd pdflatex
else
    section "latex"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active claude; then
    section "claude"
    check_cmd claude
    for f in settings.json statusline.py CLAUDE.md; do check_file "$HOME/.claude/$f"; done
else
    section "claude"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active vscode; then
    section "vscode"
    if have code; then
        wanted=("${VSCODE_EXTENSIONS[@]:-}")
        installed="$(code --list-extensions 2>/dev/null | tr 'A-Z' 'a-z')"
        got=$(printf '%s\n' "$installed" | grep -c .)
        missing=()
        for ext in "${wanted[@]}"; do
            [ -n "$ext" ] || continue
            printf '%s\n' "$installed" | grep -qx "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" \
                || missing+=("$ext")
        done
        if [ ${#missing[@]} -eq 0 ]; then
            ok "all ${#wanted[@]} extensions from the profile installed ($got total)"
        else
            meh "missing extensions: ${missing[*]}"
        fi
    else
        meh "'code' CLI not on PATH - extensions unchecked"
    fi
    check_file "$HOME/.vscode-server/data/Machine/settings.json"
else
    section "vscode"
    info "not in profile '$PROFILE_NAME', skipped"
fi

if module_active dotfiles; then
    section "dotfiles"
    for f in .zshrc .zshenv .gitconfig .gitignore_global; do check_file "$HOME/$f"; done
    check_file "$HOME/.config/clangd/config.yaml"
    if is_wsl; then
        if [ -f "$HOME/.config/wsl-env.zsh" ] && grep -q '^export WIN_HOME=' "$HOME/.config/wsl-env.zsh"; then
            wh="$(. "$HOME/.config/wsl-env.zsh" 2>/dev/null && echo "$WIN_HOME")"
            [ -d "$wh" ] && ok "wsl-env.zsh -> WIN_HOME=$wh" || bad "wsl-env.zsh points at $wh, which does not exist"
        else
            # shellcheck disable=SC2088  # a message, not a path
            bad "~/.config/wsl-env.zsh missing (cube/cmonitor aliases will not be set)"
        fi
    fi
    for kv in init.defaultBranch=main push.autoSetupRemote=true pull.rebase=true rerere.enabled=true merge.conflictStyle=zdiff3; do
        k="${kv%%=*}"; want="${kv#*=}"; got="$(git config --global --get "$k" 2>/dev/null)"
        [ "$got" = "$want" ] && ok "git $k = $got" || bad "git $k = ${got:-unset} (expected $want)"
    done
    [ -n "$(git config --global user.email 2>/dev/null)" ] && ok "git identity: $(git config --global user.name) <$(git config --global user.email)>" || bad "git identity unset"
else
    section "dotfiles"
    info "not in profile '$PROFILE_NAME', skipped"
fi

section "profile drift"

if module_active cpp && have clang; then
    want="${CLANG_VERSION:-}"
    got="$(clang --version | sed -n '1s/.*version \([0-9]*\).*/\1/p')"
    if [ -n "$want" ] && [ "$want" != "$got" ]; then
        meh "clang is $got but the profile asks for $want"
    else
        ok "clang $got matches the profile"
    fi
fi

if [ -f "$HOME/.gitconfig.local" ]; then
    got_name="$(git config --file "$HOME/.gitconfig.local" user.name 2>/dev/null)"
    if [ -n "${GIT_NAME:-}" ] && [ "$got_name" != "$GIT_NAME" ]; then
        # shellcheck disable=SC2088  # a message, not a path
        meh "~/.gitconfig.local says '$got_name' but the profile says '$GIT_NAME'"
        meh "  fix with: ./install.sh --only dotfiles"
    else
        ok "git identity matches the profile"
    fi
else
    # shellcheck disable=SC2088  # a message, not a path
    bad "~/.gitconfig.local is missing; run ./install.sh --only dotfiles"
fi

printf '\n%s========================================%s\n' "$BOLD" "$RESET"
printf '%s%d passed%s  %s%d warnings%s  %s%d failed%s\n' \
    "$GREEN" "$PASS" "$RESET" "$YELLOW" "$WARN" "$RESET" "$RED" "$FAIL" "$RESET"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
