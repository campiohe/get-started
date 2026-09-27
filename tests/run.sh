#!/usr/bin/env bash
# Run the whole suite: every shell test, then shellcheck.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for suite in tests/test_*.sh; do
    [ -x "$suite" ] || continue
    echo "== $suite =="
    "$suite"
done

if command -v shellcheck >/dev/null 2>&1; then
    echo "== shellcheck =="
    # warning and above. The info level is almost all SC2015 (`a && b || c`),
    # which is the deliberate idiom throughout doctor.sh upstream.
    shellcheck --severity=warning install.sh lib.sh doctor.sh scripts/*.sh \
        profiles/*.sh tests/*.sh
else
    echo "== shellcheck not installed, skipping =="
fi
