#!/usr/bin/env bash
# The tracked dotfiles must carry no identity, and the generated include
# files must supply it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fails=0
pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; fails=$((fails + 1)); }

echo "== dotfiles =="

if grep -q '^\[user\]' dotfiles/.gitconfig; then
    fail "tracked .gitconfig must not contain a [user] section"
else
    pass "tracked .gitconfig has no [user] section"
fi

if grep -q 'gitconfig.local' dotfiles/.gitconfig; then
    pass "tracked .gitconfig includes ~/.gitconfig.local"
else
    fail "tracked .gitconfig includes ~/.gitconfig.local"
fi

if grep -qiE '(cosme|gabriel|campiotti|@gmail|@example)' dotfiles/.gitconfig; then
    fail "tracked .gitconfig still names a person"
else
    pass "tracked .gitconfig names nobody"
fi

if grep -qE '^plugins=\(git ' dotfiles/.zshrc; then
    fail ".zshrc must not hardcode a plugin list"
else
    pass ".zshrc does not hardcode a plugin list"
fi

if grep -q 'profile-env.zsh' dotfiles/.zshrc; then
    pass ".zshrc sources the generated profile-env.zsh"
else
    fail ".zshrc sources the generated profile-env.zsh"
fi

# A missing generated file must still leave a usable shell.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if ! command -v zsh >/dev/null 2>&1; then
    pass ".zshrc parse check skipped (zsh not installed)"
elif HOME="$tmp" zsh -n dotfiles/.zshrc 2>/dev/null; then
    pass ".zshrc parses with no generated file present"
else
    fail ".zshrc parses with no generated file present"
fi

if grep -q 'ZSH_PLUGINS' dotfiles/.zshrc && \
   grep -qE 'ZSH_PLUGINS=.*git' dotfiles/.zshrc; then
    pass ".zshrc defaults ZSH_PLUGINS before sourcing"
else
    fail ".zshrc defaults ZSH_PLUGINS before sourcing"
fi

if [ -f dotfiles/mise-config.toml ]; then
    fail "dotfiles/mise-config.toml should be gone (it is profile data now)"
else
    pass "dotfiles/mise-config.toml is gone"
fi

# The generated files must carry the profile. Run the real module against a
# scratch HOME; it only writes under $HOME.
home="$tmp/home"; mkdir -p "$home"
if HOME="$home" PROFILE_NAME=wsl-dev bash scripts/99-dotfiles.sh >/dev/null 2>&1; then
    pass "99-dotfiles runs against a scratch HOME"
else
    fail "99-dotfiles runs against a scratch HOME"
fi
case "$(cat "$home/.gitconfig.local" 2>/dev/null)" in
    *"name = Henrique Campiotti"*) pass "generated gitconfig carries the identity" ;;
    *) fail "generated gitconfig carries the identity" ;; esac
if command -v git >/dev/null && \
   [ "$(git config --file "$home/.gitconfig.local" user.email)" = "henrique.campiotti.marques@gmail.com" ]; then
    pass "generated gitconfig parses as git config"
else
    fail "generated gitconfig parses as git config"
fi
if command -v zsh >/dev/null 2>&1; then
    got="$(zsh -c "source '$home/.config/profile-env.zsh'; print -r -- \$ZSH_PLUGINS")"
    case "$got" in
        "git fzf "*"zsh-bat web-search") pass "generated zsh-env carries the plugin list" ;;
        *) fail "generated zsh-env carries the plugin list (got '$got')" ;; esac
else
    pass "zsh-env check skipped (zsh not installed)"
fi

# 90-claude merges CLAUDE_SETTINGS over the tracked settings.json with jq.
if command -v jq >/dev/null 2>&1; then
    settings="$(PROFILE_NAME=wsl-dev bash -c 'source lib.sh; echo "$CLAUDE_SETTINGS"')"
    cmd="$(grep -o "jq -S -s '[^']*'" scripts/90-claude.sh)"
    merged="$(eval "$cmd dotfiles/.claude/settings.json -" <<<"$settings")"
    if [ "$(jq -r .model <<<"$merged")" = opus ] && \
       [ "$(jq 'keys | length' <<<"$merged")" -gt 2 ]; then
        pass "claude settings merge keeps the tracked keys and adds the profile's"
    else
        fail "claude settings merge keeps the tracked keys and adds the profile's"
    fi
else
    pass "claude settings merge check skipped (jq not installed)"
fi

[ "$fails" -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "all dotfile checks passed"
