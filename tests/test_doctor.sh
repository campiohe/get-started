#!/usr/bin/env bash
# doctor.sh must scope itself to the active profile and report drift.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fails=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; fails=$((fails + 1)); }

echo "== doctor.sh =="

if grep -q 'MODULES\[@\]' doctor.sh; then
    pass "doctor.sh scopes checks to the profile's modules"
else
    fail "doctor.sh scopes checks to the profile's modules"
fi

if grep -q 'module_active' doctor.sh; then
    pass "doctor.sh has a module_active helper"
else
    fail "doctor.sh has a module_active helper"
fi

if grep -q 'want="${CLANG_VERSION' doctor.sh; then
    pass "doctor.sh compares clang against the profile"
else
    fail "doctor.sh compares clang against the profile"
fi

if grep -q 'gitconfig.local' doctor.sh; then
    pass "doctor.sh checks the generated identity file"
else
    fail "doctor.sh checks the generated identity file"
fi

if grep -q 'vscode-extensions\.txt' doctor.sh; then
    fail "doctor.sh still reads the deleted vscode-extensions.txt"
else
    pass "doctor.sh reads the extension list from the profile"
fi

bash -n doctor.sh && pass "bash -n doctor.sh" || fail "bash -n doctor.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
out="$(PROFILE_NAME=ci-headless ./doctor.sh 2>&1 || true)"
case "$out" in
    *ci-headless*) pass "doctor.sh names the active profile" ;;
    *) fail "doctor.sh names the active profile" ;;
esac
case "$out" in
    *arm-none-eabi*) fail "doctor.sh must skip embedded checks under ci-headless" ;;
    *) pass "doctor.sh skips embedded checks under ci-headless" ;;
esac

[ "$fails" -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "all doctor checks passed"
