#!/usr/bin/env bash
# Module scripts must read the profile rather than hardcoding lists. These
# are static checks: nothing is installed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fails=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; fails=$((fails + 1)); }
reads() { # label file var
    if grep -q "$3" "$2"; then pass "$1"; else fail "$1 (no $3 in $2)"; fi
}
lacks() { # label file pattern
    if grep -qE "$3" "$2"; then fail "$1 (found /$3/ in $2)"; else pass "$1"; fi
}

echo "== modules read the profile =="

reads "02-locale reads the timezone"  scripts/02-locale.sh TIMEZONE
reads "02-locale reads the locales"   scripts/02-locale.sh LOCALES

reads "10-shell reads the plugin list"    scripts/10-shell.sh ZSH_PLUGINS
reads "10-shell reads the plugin sources" scripts/10-shell.sh ZSH_PLUGIN_SOURCES
reads "10-shell reads the nerd font"      scripts/10-shell.sh NERD_FONT
reads "10-shell reads the starship flag"  scripts/10-shell.sh STARSHIP
reads "10-shell generates the mise config" scripts/10-shell.sh MISE_TOOLS
lacks "10-shell no longer hardcodes clone urls" scripts/10-shell.sh 'clone_or_pull https://'
lacks "10-shell no longer copies mise-config.toml" scripts/10-shell.sh 'mise-config\.toml'

reads "20-cpp reads the clang version" scripts/20-cpp.sh CLANG_VERSION

reads "40-python reads the pipx tools" scripts/40-python.sh PIPX_TOOLS
lacks "40-python no longer hardcodes the tool list" scripts/40-python.sh 'for tool in ruff'

reads "05-base reads extra packages" scripts/05-base.sh EXTRA_PACKAGES
if grep -qE '^ +ca-certificates curl' scripts/05-base.sh; then
    pass "05-base still hardcodes the bootstrap packages"
else
    fail "05-base must keep hardcoding the bootstrap packages a profile cannot remove"
fi

reads "30-embedded reads the groups" scripts/30-embedded.sh EMBEDDED_GROUPS
lacks "30-embedded no longer hardcodes the groups" scripts/30-embedded.sh \
    'for grp in dialout plugdev'

reads "70-github reads the git protocol" scripts/70-github.sh GIT_PROTOCOL
lacks "70-github no longer forces https" scripts/70-github.sh \
    'git_protocol https'
reads "70-github sets the identity from the profile" scripts/70-github.sh \
    GIT_EMAIL

reads "90-claude merges settings from the profile" scripts/90-claude.sh CLAUDE_SETTINGS
lacks "90-claude no longer copies settings.json verbatim" scripts/90-claude.sh \
    'for f in settings.json'

reads "95-vscode reads the extension list" scripts/95-vscode.sh VSCODE_EXTENSIONS
lacks "95-vscode no longer reads the txt file" scripts/95-vscode.sh \
    'vscode-extensions\.txt'

if [ -f vscode-extensions.txt ]; then
    fail "vscode-extensions.txt should be gone (it is profile data now)"
else
    pass "vscode-extensions.txt is gone"
fi

echo "== every profile variable a module reads is on its # profile: line =="
for f in scripts/*.sh; do
    needs=" $(sed -n 's/^# profile: *//p' "$f") "
    for var in DESCRIPTION MODULES GIT_NAME GIT_EMAIL TIMEZONE LOCALES EXTRA_PACKAGES \
               ZSH_THEME ZSH_PLUGINS ZSH_PLUGIN_SOURCES NERD_FONT STARSHIP MISE_TOOLS \
               CLANG_VERSION EMBEDDED_GROUPS PIPX_TOOLS GIT_PROTOCOL CLAUDE_SETTINGS \
               VSCODE_EXTENSIONS; do
        grep -qE "\\\$\{?!?$var\b" "$f" || continue
        case "$needs" in *" $var "*) ;; *) fail "$f reads $var but its # profile: line omits it"; continue ;; esac
    done
done
pass "checked # profile: lines against the variables each module reads"

echo "== no Python left in the install path =="
if grep -rlE 'python3 .*lib/profile|lib/profile' install.sh lib.sh doctor.sh scripts; then
    fail "something still calls lib/profile"
else
    pass "nothing calls lib/profile"
fi

echo "== every module still parses =="
for f in scripts/*.sh; do
    if bash -n "$f"; then pass "bash -n $f"; else fail "bash -n $f"; fi
done

[ "$fails" -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "all module checks passed"
