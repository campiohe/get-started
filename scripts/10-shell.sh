#!/usr/bin/env bash
# zsh + oh-my-zsh + plugins, starship, zoxide, mise, eza, Nerd Font.
# profile: ZSH_PLUGINS ZSH_PLUGIN_SOURCES STARSHIP MISE_TOOLS NERD_FONT
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

log "zsh"
apt_install zsh

if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
    info "setting zsh as the login shell"
    sudo chsh -s "$(command -v zsh)" "$USER"
else
    info "zsh is already the login shell"
fi

log "oh-my-zsh"
if [ -d "$HOME/.oh-my-zsh" ]; then
    info "oh-my-zsh already present"
else
    # --unattended keeps it from launching zsh and from rewriting .zshrc.
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

log "oh-my-zsh custom plugins"
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
# Clone exactly the intersection of the profile's plugin list and the sources
# it declares. Anything else is assumed to be an oh-my-zsh built-in.
for plugin in "${ZSH_PLUGINS[@]}"; do
    url="${ZSH_PLUGIN_SOURCES[$plugin]:-}"
    if [ -n "$url" ]; then
        clone_or_pull "$url" "$ZSH_CUSTOM/plugins/$plugin"
    else
        info "$plugin: built-in, nothing to clone"
    fi
done

log "starship prompt"
if [ "$STARSHIP" != true ]; then
    info "starship disabled by profile '$PROFILE_NAME'"
elif have starship; then
    info "starship already installed"
else
    curl -fsSL https://starship.rs/install.sh | sudo sh -s -- --yes
fi

# starship works with no config file at all, so only install one if the repo
# actually carries it. Drop a starship.toml into dotfiles/ and it is picked up.
if [ "$STARSHIP" != true ]; then
    :
elif [ -f "$REPO_DIR/dotfiles/starship.toml" ]; then
    mkdir -p "$HOME/.config"
    backup "$HOME/.config/starship.toml"
    cp "$REPO_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
    info "installed ~/.config/starship.toml"
else
    info "no dotfiles/starship.toml in the repo - starship will use its defaults"
fi

log "zoxide"
if have zoxide; then
    info "zoxide already installed"
else
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
fi

log "mise (runtime version manager)"
if have mise || [ -x "$HOME/.local/bin/mise" ]; then
    info "mise already installed"
else
    curl -fsSL https://mise.run | sh
fi
mkdir -p "$HOME/.config/mise"
{
    echo "# Generated from profile '$PROFILE_NAME'. Do not edit; edit the profile."
    echo "[tools]"
    for tool in $(printf '%s\n' "${!MISE_TOOLS[@]}" | sort); do
        printf '%s = "%s"\n' "$tool" "${MISE_TOOLS[$tool]}"
    done
} > "$HOME/.config/mise/config.toml"
info "mise config generated from profile '$PROFILE_NAME'"
"$HOME/.local/bin/mise" install || warn "mise install failed; run it by hand later"

log "eza"
if pkg_available eza; then
    # 26.04 is expected to carry eza in universe; prefer the archive when it does.
    apt_install eza
elif ! have eza; then
    info "eza not in the archive, adding deb.gierens.de"
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    # shellcheck disable=SC2034  # read by apt_update_once in lib.sh
    APT_UPDATED=0
    apt_install eza
else
    info "eza already installed"
fi

FONT_NAME="$NERD_FONT"
log "$FONT_NAME Nerd Font"
FONT_DIR="$HOME/.local/share/fonts"
if compgen -G "$FONT_DIR/${FONT_NAME}NerdFont*" >/dev/null; then
    info "$FONT_NAME Nerd Font already present"
else
    apt_install fontconfig
    mkdir -p "$FONT_DIR"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$FONT_NAME.zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$FONT_NAME.zip"
    unzip -qo "$tmp/$FONT_NAME.zip" -d "$tmp/$FONT_NAME"
    cp "$tmp/$FONT_NAME"/${FONT_NAME}NerdFontMono-*.ttf "$FONT_DIR/"
    rm -rf "$tmp"
    fc-cache -f "$FONT_DIR" >/dev/null
    info "installed $FONT_NAME Nerd Font Mono"
fi

# Note: under WSL this font is only used by Linux programs that render text
# themselves. Windows Terminal and the VS Code UI use whatever Windows has.
