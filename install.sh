#!/usr/bin/env bash
#
# Bootstrap a fresh Ubuntu (WSL2) machine from a declarative profile.
#
#   ./install.sh --profile wsl-dev         select a profile and run it
#   ./install.sh                           re-run the remembered profile
#   ./install.sh --only shell,python       run only those modules
#   ./install.sh --skip latex              run everything except those
#   ./install.sh --dry-run                 print the plan, install nothing
#   ./install.sh --list                    show the modules and exit
#   ./install.sh --list-profiles           show the profiles and exit
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIVE_FILE="$REPO_DIR/.active-profile"

usage() {
    cat <<USAGE
Usage: ./install.sh [--profile NAME] [--only a,b] [--skip a,b] [--dry-run]
                    [--list] [--list-profiles]

  --profile NAME   the profile to install; remembered in .active-profile
  --only a,b       run only these modules (of those the profile enables)
  --skip a,b       run everything the profile enables except these
  --dry-run        print the plan and exit without installing
  --list           list the modules
  --list-profiles  list the available profiles
USAGE
}

ONLY=""; SKIP=""; PROFILE=""; DRY_RUN=0; LIST=""
while [ $# -gt 0 ]; do
    case "$1" in
        --profile) PROFILE="${2:?--profile needs a name}"; shift 2 ;;
        --only)    ONLY="${2:?--only needs a comma-separated list}"; shift 2 ;;
        --skip)    SKIP="${2:?--skip needs a comma-separated list}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --list|-l) LIST=modules; shift ;;
        --list-profiles) LIST=profiles; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown argument: $1 (try --help)" >&2; exit 1 ;;
    esac
done

# Listing needs no profile, so lib.sh is loaded without one.
if [ -n "$LIST" ]; then
    PROFILE_NAME=""
    source "$REPO_DIR/lib.sh"
    if [ "$LIST" = modules ]; then
        echo "Modules:"
        while read -r f; do
            printf '  %-10s %s\n' "$(module_name "$f")" "$(module_desc "$f")"
        done < <(module_files)
    else
        active="$(cat "$ACTIVE_FILE" 2>/dev/null || true)"
        echo "Profiles:"
        for name in $(profile_names); do
            desc="$(bash -c 'source "$1" >/dev/null 2>&1; echo "${DESCRIPTION:-}"' _ "$(profile_file "$name")")"
            printf '  %-14s %s%s\n' "$name" "$desc" "$([ "$name" = "$active" ] && echo '  (active)')"
        done
    fi
    exit 0
fi

# Check the profile before anything else: a bad one must not get as far as sudo.
PROFILE_FROM_FILE=""
if [ -z "$PROFILE" ]; then
    if [ -f "$ACTIVE_FILE" ]; then
        PROFILE="$(cat "$ACTIVE_FILE")"
        PROFILE_FROM_FILE=1
    else
        {
            echo "[fail] no profile selected and no .active-profile."
            echo "Pick one with --profile NAME:"
            for f in "$REPO_DIR"/profiles/*.sh; do echo "  $(basename "$f" .sh)"; done
        } >&2
        exit 1
    fi
fi

export PROFILE_NAME="$PROFILE"
source "$REPO_DIR/lib.sh"
profile_validate

# Remembered only once the profile checked out, so a typo cannot overwrite a
# working selection.
printf '%s\n' "$PROFILE" > "$ACTIVE_FILE"

in_list() { echo ",$2," | grep -q ",$1,"; }

# Run order is the scripts' number order, never the order MODULES lists them.
PLAN=()
while read -r f; do
    name="$(module_name "$f")"
    in_list "$name" "$(IFS=,; echo "${MODULES[*]}")" || continue
    [ -n "$ONLY" ] && ! in_list "$name" "$ONLY" && continue
    [ -n "$SKIP" ] &&   in_list "$name" "$SKIP" && continue
    PLAN+=("$name")
done < <(module_files)

log "profile: $PROFILE${PROFILE_FROM_FILE:+ (from .active-profile)}"
info "plan:    ${PLAN[*]:-(nothing)}"

if [ "$DRY_RUN" -eq 1 ]; then
    for name in "${PLAN[@]}"; do
        printf '  %-10s %s\n' "$name" "scripts/$(basename "$(module_file "$name")")"
    done
    log "dry run: nothing was installed"
    exit 0
fi

[ "$(id -u)" -eq 0 ] && die "Run this as your normal user, not root. sudo is called where needed."
have sudo || die "sudo is required."

# Ask for sudo once up front so the run is not interrupted later.
sudo -v

BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"
export BACKUP_STAMP

log "Starting bootstrap ($(. /etc/os-release && echo "$PRETTY_NAME")$(is_wsl && echo ', WSL'))"

RAN=(); FAILED=()
for name in "${PLAN[@]}"; do
    printf '\n%s========== %s ==========%s\n' "$BOLD" "$name" "$RESET"
    # A failing module should not abort the rest of the bootstrap.
    if bash "$(module_file "$name")"; then
        RAN+=("$name")
    else
        warn "module '$name' failed"
        FAILED+=("$name")
    fi
done

printf '\n%s========== summary ==========%s\n' "$BOLD" "$RESET"
log "profile: $PROFILE"
[ ${#RAN[@]}    -gt 0 ] && log  "ran:     ${RAN[*]}"    || true
[ ${#FAILED[@]} -gt 0 ] && warn "failed:  ${FAILED[*]}" || true

cat <<'NEXT'

Next steps:
  1. Close the terminal and reopen it (or run: exec zsh) to pick up the new shell.
  2. Group changes (docker, dialout, plugdev) need a full WSL restart:
       wsl --shutdown        # from Windows
  3. Authenticate the tools that need it:
       gh auth login
       claude
  4. Install FiraCode Nerd Font on Windows too, and select it in Windows Terminal.
NEXT
