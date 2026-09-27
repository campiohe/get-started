#!/usr/bin/env bash
# lib.sh loads a profile, checks it, and discovers the modules. Each case runs
# in a throwaway copy of the repo so it can add broken profiles freely.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fails=0
check() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ok   $label"
    else
        echo "  FAIL $label: expected '$expected', got '$actual'"
        fails=$((fails + 1))
    fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r lib.sh scripts profiles "$tmp/"
in_repo() { (cd "$tmp" && env -u PROFILE_NAME -u CLANG_VERSION -u TIMEZONE bash -c "$1" 2>&1) || true; }
outcome() { (cd "$tmp" && env -u PROFILE_NAME -u CLANG_VERSION -u TIMEZONE bash -c "$1") >/dev/null 2>&1 && echo passed || echo failed; }

echo "== lib.sh modules =="

check "modules come from scripts/, in number order" \
    "sudo locale base shell cpp embedded python rust docker github latex claude vscode dotfiles" \
    "$(in_repo 'PROFILE_NAME=""; source lib.sh; while read -r f; do module_name "$f"; done < <(module_files) | xargs')"
check "the description is line 2 of the script" "Timezone and locale." \
    "$(in_repo 'PROFILE_NAME=""; source lib.sh; module_desc scripts/02-locale.sh')"
check "a module's needs are its # profile: line" "CLANG_VERSION" \
    "$(in_repo 'PROFILE_NAME=""; source lib.sh; module_needs scripts/20-cpp.sh')"
check "module_file finds a script by name" "scripts/20-cpp.sh" \
    "$(in_repo 'PROFILE_NAME=""; source lib.sh; module_file cpp' | sed "s|^$tmp/||")"

echo "== lib.sh profile loading =="

check "PROFILE_NAME selects the profile" "Henrique Campiotti" \
    "$(in_repo 'PROFILE_NAME=wsl-dev; source lib.sh; echo "$GIT_NAME"')"
echo ci-headless > "$tmp/.active-profile"
check ".active-profile is the fallback" "ci" \
    "$(in_repo 'source lib.sh; echo "$GIT_NAME"')"
check "an empty PROFILE_NAME means no profile" "none" \
    "$(in_repo 'PROFILE_NAME=""; source lib.sh; echo "${GIT_NAME:-none}"')"
rm "$tmp/.active-profile"
check "no profile at all is not an error" "none" \
    "$(in_repo 'source lib.sh; echo "${GIT_NAME:-none}"')"
check "associative arrays survive loading" "https://github.com/fdellwing/zsh-bat.git" \
    "$(in_repo 'PROFILE_NAME=wsl-dev; source lib.sh; echo "${ZSH_PLUGIN_SOURCES[zsh-bat]}"')"
check "an exported CLANG_VERSION beats the profile" "21" \
    "$(in_repo 'export CLANG_VERSION=21 PROFILE_NAME=wsl-dev; source lib.sh; echo "$CLANG_VERSION"')"
check "an unknown profile fails" "failed" \
    "$(outcome 'PROFILE_NAME=nope; source lib.sh')"

echo "== lib.sh profile validation =="

check "committed profiles validate" "passed passed" \
    "$(outcome 'PROFILE_NAME=wsl-dev; source lib.sh; profile_validate') $(outcome 'PROFILE_NAME=ci-headless; source lib.sh; profile_validate')"

write_profile() { cp profiles/ci-headless.sh "$tmp/profiles/t.sh"; printf '%s\n' "$@" >> "$tmp/profiles/t.sh"; }

write_profile 'CLANG_VERSON=21'
out="$(in_repo 'PROFILE_NAME=t; source lib.sh; profile_validate')"
check "a misspelt variable is an error naming it" "yes" \
    "$(grep -q 'CLANG_VERSON' <<<"$out" && echo yes || echo "no: $out")"

write_profile 'MODULES+=(kubernetes)'
check "an unknown module is an error" "failed" \
    "$(outcome 'PROFILE_NAME=t; source lib.sh; profile_validate')"

write_profile 'MODULES+=(cpp)'
out="$(in_repo 'PROFILE_NAME=t; source lib.sh; profile_validate')"
check "enabling a module without its variables names what is missing" "yes" \
    "$(grep -q 'CLANG_VERSION' <<<"$out" && echo yes || echo "no: $out")"

write_profile 'unset DESCRIPTION'
check "a profile without DESCRIPTION is an error" "failed" \
    "$(outcome 'PROFILE_NAME=t; source lib.sh; profile_validate')"
rm "$tmp/profiles/t.sh"

echo "== modules check their own needs =="

for module in scripts/10-shell.sh scripts/90-claude.sh scripts/99-dotfiles.sh; do
    check "$module refuses to run without a profile" "failed" \
        "$(outcome "bash $module")"
done
out="$(in_repo 'PROFILE_NAME=ci-headless bash scripts/20-cpp.sh')"
check "a module refuses a profile missing its variables" "yes" \
    "$(grep -q "does not set CLANG_VERSION" <<<"$out" && echo yes || echo "no: $out")"

[ "$fails" -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "all lib.sh checks passed"
