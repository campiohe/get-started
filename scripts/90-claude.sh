#!/usr/bin/env bash
# Claude Code CLI plus its configuration.
# profile: CLAUDE_SETTINGS
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

log "Claude Code"
if have claude || [ -x "$HOME/.local/bin/claude" ]; then
    info "claude already installed"
else
    curl -fsSL https://claude.ai/install.sh | bash
fi

log "Claude Code configuration"
have jq || apt_install jq
mkdir -p "$HOME/.claude"
for f in statusline.py CLAUDE.md; do
    backup "$HOME/.claude/$f"
    cp "$REPO_DIR/dotfiles/.claude/$f" "$HOME/.claude/$f"
done
chmod +x "$HOME/.claude/statusline.py"

# settings.json is the tracked file with the profile's CLAUDE_SETTINGS merged
# over it (jq's * merges objects recursively), so a scenario can change the
# model without forking the file.
backup "$HOME/.claude/settings.json"
jq -S -s '.[0] * .[1]' "$REPO_DIR/dotfiles/.claude/settings.json" - \
    <<<"$CLAUDE_SETTINGS" > "$HOME/.claude/settings.json.new"
mv "$HOME/.claude/settings.json.new" "$HOME/.claude/settings.json"
info "settings.json merged from profile '$PROFILE_NAME'"
warn "Authenticate on first launch by running: claude"
