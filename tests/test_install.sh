#!/usr/bin/env bash
# install.sh argument handling and profile selection. Nothing here installs
# anything: every path exercised is --list*, --help or --dry-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fails=0
ACTIVE=".active-profile"
saved=""
[ -f "$ACTIVE" ] && saved="$(cat "$ACTIVE")"
restore() {
    if [ -n "$saved" ]; then printf '%s\n' "$saved" > "$ACTIVE"; else rm -f "$ACTIVE"; fi
}
trap restore EXIT

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; fails=$((fails + 1)); }
contains() { # label haystack needle
    case "$2" in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3')" ;; esac
}
lacks() {
    case "$2" in *"$3"*) fail "$1 (unexpected '$3')" ;; *) pass "$1" ;; esac
}

echo "== install.sh =="

out="$(./install.sh --list-profiles 2>&1)"
contains "--list-profiles shows ci-headless"  "$out" "ci-headless"
contains "--list-profiles shows wsl-dev"      "$out" "wsl-dev"
contains "--list-profiles shows descriptions" "$out" "Rust and Node"

out="$(./install.sh --list 2>&1)"
contains "--list shows a module"       "$out" "embedded"
contains "--list shows a description" "$out" "ARM cross-toolchain"

rm -f "$ACTIVE"
if ./install.sh --dry-run >/dev/null 2>&1; then
    fail "no profile and no .active-profile must be an error"
else
    pass "no profile and no .active-profile is an error"
fi
out="$(./install.sh --dry-run 2>&1 || true)"
contains "the error lists the profiles" "$out" "wsl-dev"

out="$(./install.sh --profile wsl-dev --dry-run 2>&1)"
contains "--dry-run reports the profile"  "$out" "wsl-dev"
contains "--dry-run plans rust"           "$out" "50-rust.sh"
lacks    "--dry-run omits embedded"       "$out" "30-embedded.sh"
lacks    "--dry-run omits disabled latex" "$out" "80-latex.sh"
contains "--dry-run says nothing ran"     "$out" "dry run"

if [ "$(cat "$ACTIVE")" = "wsl-dev" ]; then
    pass "--profile is remembered in .active-profile"
else
    fail "--profile is remembered in .active-profile"
fi

out="$(./install.sh --dry-run 2>&1)"
contains "the remembered profile is reused" "$out" "wsl-dev"

out="$(./install.sh --dry-run --only cpp 2>&1)"
contains "--only keeps cpp"      "$out" "20-cpp.sh"
lacks    "--only drops rust"     "$out" "50-rust.sh"

out="$(./install.sh --dry-run --skip rust 2>&1)"
lacks    "--skip drops rust"     "$out" "50-rust.sh"
contains "--skip keeps cpp"      "$out" "20-cpp.sh"

out="$(./install.sh --dry-run --only latex 2>&1 || true)"
lacks "--only cannot enable a module the profile disabled" "$out" "80-latex.sh"

if ./install.sh --profile no-such-profile --dry-run >/dev/null 2>&1; then
    fail "an unknown profile must be an error"
else
    pass "an unknown profile is an error"
fi

cp profiles/ci-headless.sh profiles/zz-broken-test.sh
echo 'CLANG_VERSON=21' >> profiles/zz-broken-test.sh
out="$(./install.sh --profile zz-broken-test --dry-run 2>&1 || true)"
rm -f profiles/zz-broken-test.sh
contains "a profile with a typo is refused before anything runs" "$out" "CLANG_VERSON"
lacks    "a refused profile plans nothing" "$out" "plan:"

if [ "$(cat "$ACTIVE")" = "wsl-dev" ]; then
    pass ".active-profile is untouched by a failed selection"
else
    fail ".active-profile is untouched by a failed selection"
fi

out="$(./install.sh --help 2>&1)"
contains "--help documents --profile" "$out" "--profile"
contains "--help documents --dry-run" "$out" "--dry-run"

[ "$fails" -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "all install.sh checks passed"
