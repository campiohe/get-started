#!/usr/bin/env bash
# Shared helpers for all install modules.

set -euo pipefail

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'

log()  { printf '%s==>%s %s\n' "$GREEN$BOLD" "$RESET" "$*"; }
info() { printf '%s  ->%s %s\n' "$DIM" "$RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%s[fail]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

# Root of the repo, regardless of where the script is invoked from.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- modules ----------------------------------------------------------------
# A module is a script named scripts/NN-name.sh. The number is the run order,
# the name is what profiles and --only/--skip use, and line 2 is a
# "# description" comment. A "# profile: VAR ..." line names the profile
# variables the module reads; those lines are also the full list of variables
# a profile may set.
module_files() { printf '%s\n' "$REPO_DIR"/scripts/[0-9][0-9]-*.sh; }
module_name()  { local f="${1##*/}"; f="${f#[0-9][0-9]-}"; echo "${f%.sh}"; }
module_desc()  { sed -n '2s/^# *//p' "$1"; }
module_needs() { sed -n 's/^# profile: *//p' "$1"; }
module_file()  { # name -> path, or nothing
    local f
    for f in "$REPO_DIR"/scripts/[0-9][0-9]-"$1".sh; do [ -f "$f" ] && echo "$f"; done
}

# --- profile ----------------------------------------------------------------
# A profile is profiles/<name>.sh: plain bash variables, one self-contained
# file per setup. install.sh exports PROFILE_NAME; a module run on its own
# (`bash scripts/20-cpp.sh`) falls back to the remembered .active-profile.
# PROFILE_NAME set but empty means "no profile", which listing relies on.
PROFILE_NAME="${PROFILE_NAME-$(cat "$REPO_DIR/.active-profile" 2>/dev/null || true)}"

profile_file()  { echo "$REPO_DIR/profiles/$1.sh"; }
profile_names() { local f; for f in "$REPO_DIR"/profiles/*.sh; do [ -f "$f" ] && basename "$f" .sh; done; }

# Variables a profile file assigns, found by sourcing it in a clean shell.
profile_defines() {
    env -i bash --noprofile --norc -c '
        __before="$(compgen -v)"
        source "$1" >/dev/null || exit 1
        comm -13 <(printf "%s\n" "$__before" | sort) <(compgen -v | sort) | grep -vxE "__before|_|PIPESTATUS|BASH_.*|COLUMNS|LINES"
    ' _ "$1"
}

# Everything a profile may set: DESCRIPTION, MODULES and every module's needs.
profile_vocabulary() {
    echo DESCRIPTION; echo MODULES
    local f; while read -r f; do module_needs "$f"; done < <(module_files) | tr ' ' '\n'
}

# Die unless the loaded profile sets every variable this module reads.
profile_check_needs() { # script
    local var
    for var in $(module_needs "$1"); do
        declare -p "$var" >/dev/null 2>&1 && continue
        [ -n "$PROFILE_NAME" ] || die "$(module_name "$1") needs a profile. Select one first: ./install.sh --profile NAME"
        die "profile '$PROFILE_NAME' does not set $var, which module $(module_name "$1") needs"
    done
}

# The whole profile, checked before install.sh does anything: no unknown
# variables (typos fail loudly), every module exists, every module's needs met.
profile_validate() {
    local file var name unknown=()
    file="$(profile_file "$PROFILE_NAME")"
    local known; known="$(profile_vocabulary | sort -u)"
    while read -r var; do
        [ -n "$var" ] || continue
        grep -qx "$var" <<<"$known" || unknown+=("$var")
    done < <(profile_defines "$file")
    [ ${#unknown[@]} -eq 0 ] || die "profile '$PROFILE_NAME' sets unknown variable(s): ${unknown[*]}"
    declare -p DESCRIPTION >/dev/null 2>&1 || die "profile '$PROFILE_NAME' does not set DESCRIPTION"
    declare -p MODULES >/dev/null 2>&1 || die "profile '$PROFILE_NAME' does not set MODULES"
    for name in "${MODULES[@]}"; do
        [ -n "$(module_file "$name")" ] || die "profile '$PROFILE_NAME' enables unknown module '$name'. Known: $(while read -r f; do module_name "$f"; done < <(module_files) | tr '\n' ' ')"
        profile_check_needs "$(module_file "$name")"
    done
}

if [ -n "$PROFILE_NAME" ]; then
    [ -f "$(profile_file "$PROFILE_NAME")" ] \
        || die "no such profile: '$PROFILE_NAME'. Available: $(profile_names | tr '\n' ' ')"
    # A value exported by the caller beats the profile, e.g.
    # CLANG_VERSION=21 ./install.sh --only cpp
    __env_overrides=()
    for __v in CLANG_VERSION TIMEZONE; do
        [ -n "${!__v:-}" ] && __env_overrides+=("$__v=${!__v}")
    done
    # shellcheck source=/dev/null
    source "$(profile_file "$PROFILE_NAME")"
    for __kv in "${__env_overrides[@]}"; do printf -v "${__kv%%=*}" '%s' "${__kv#*=}"; done
    unset __v __kv __env_overrides
fi

# A module sourcing this file gets its own needs checked, so running one on
# its own without a profile says what to do instead of dying on an unbound
# variable several lines later.
case "${BASH_SOURCE[1]:-}" in
    scripts/[0-9][0-9]-*.sh|*/scripts/[0-9][0-9]-*.sh) profile_check_needs "${BASH_SOURCE[1]}" ;;
esac

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# True if the command exists on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# True if the apt package is installed.
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'; }

# True if apt knows of a candidate for this package.
pkg_available() { [ "$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')" != "(none)" ] \
                  && [ -n "$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}')" ]; }

APT_UPDATED=0
apt_update_once() {
    [ "$APT_UPDATED" -eq 1 ] && return 0
    log "Updating apt index"
    sudo apt-get update -qq
    APT_UPDATED=1
}

# Install only the packages that are missing. Never fails the run on one bad name.
apt_install() {
    local missing=()
    for p in "$@"; do
        pkg_installed "$p" || missing+=("$p")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        info "already installed: $*"
        return 0
    fi
    apt_update_once
    info "installing: ${missing[*]}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
}

# Clone a git repo, or pull if it is already there.
clone_or_pull() {
    local url="$1" dest="$2"
    if [ -d "$dest/.git" ]; then
        info "updating $(basename "$dest")"
        git -C "$dest" pull --quiet --ff-only || warn "could not fast-forward $dest"
    else
        info "cloning $(basename "$dest")"
        git clone --quiet --depth=1 "$url" "$dest"
    fi
}

# Back up a file/dir before overwriting it, once per run.
backup() {
    local target="$1"
    [ -e "$target" ] || return 0
    local stamp="${BACKUP_STAMP:-$(date +%Y%m%d-%H%M%S)}"
    local dest="$HOME/.get-started-backup/$stamp"
    mkdir -p "$dest/$(dirname "${target#"$HOME"/}")"
    cp -a "$target" "$dest/${target#"$HOME"/}"
    info "backed up $target -> $dest/${target#"$HOME"/}"
}

# Best-effort detection of the Windows user name from inside WSL.
# Echoes the name on success; returns 1 if it cannot be determined.
detect_win_user() {
    is_wsl || return 1
    local u="" candidates

    # cmd.exe is the cheapest (~65ms). It warns about the UNC cwd on stderr,
    # which is harmless; /D skips any AutoRun command.
    if have cmd.exe; then
        u="$(cmd.exe /D /C 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')"
    fi

    # Slower (~350ms) but works if cmd.exe is unavailable.
    if [ -z "$u" ] && have powershell.exe; then
        u="$(powershell.exe -NoProfile -Command '$env:USERNAME' 2>/dev/null | tr -d '\r\n')"
    fi

    # Last resort, only trusted when exactly one real profile exists.
    if [ -z "$u" ] && [ -d /mnt/c/Users ]; then
        candidates="$(/bin/ls -1 /mnt/c/Users 2>/dev/null \
            | grep -viE '^(public|default|default user|all users|desktop\.ini)$' || true)"
        [ "$(printf '%s\n' "$candidates" | grep -c .)" -eq 1 ] && u="$candidates"
    fi

    [ -n "$u" ] && [ -d "/mnt/c/Users/$u" ] || return 1
    printf '%s\n' "$u"
}
