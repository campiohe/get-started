#!/usr/bin/env bash
# shellcheck disable=SC2034  # every variable here is read by a module script
#
# A profile is the whole setup in one file: nothing is inherited and nothing
# is layered on top. It is plain bash, sourced by lib.sh. Which variables a
# module reads is on the "# profile:" line of its script; setting anything
# else is an error, so a typo fails instead of doing nothing.

DESCRIPTION="Python, C++, Rust and Node workstation on WSL2"

# Order is irrelevant; modules run in their scripts' number order.
MODULES=(sudo locale base shell cpp python rust docker github claude vscode
         dotfiles)

# identity, locale: 02-locale, 70-github, 99-dotfiles
GIT_NAME="Henrique Campiotti"
GIT_EMAIL=henrique.campiotti.marques@gmail.com
TIMEZONE=America/Sao_Paulo
LOCALES=(en_US.UTF-8 pt_BR.UTF-8)

# 05-base: packages on top of the fixed bootstrap set
EXTRA_PACKAGES=(neovim)

# 10-shell, 99-dotfiles
ZSH_THEME=robbyrussell
ZSH_PLUGINS=(
    git
    fzf
    fzf-tab
    fast-syntax-highlighting
    zsh-autosuggestions
    command-not-found
    extract
    sudo
    zsh-bat
    web-search
)
# Plugins that are not oh-my-zsh built-ins need a clone source.
declare -A ZSH_PLUGIN_SOURCES=(
    [fzf-tab]=https://github.com/Aloxaf/fzf-tab.git
    [fast-syntax-highlighting]=https://github.com/zdharma-continuum/fast-syntax-highlighting.git
    [zsh-autosuggestions]=https://github.com/zsh-users/zsh-autosuggestions.git
    [zsh-bat]=https://github.com/fdellwing/zsh-bat.git
)
NERD_FONT=FiraCode
STARSHIP=true
# Node comes from mise.
declare -A MISE_TOOLS=([node]=latest)

# 20-cpp
CLANG_VERSION=22

# 40-python
PIPX_TOOLS=(ruff uv tldr)

# 70-github
GIT_PROTOCOL=ssh

# 90-claude: merged over dotfiles/.claude/settings.json
CLAUDE_SETTINGS='{"tui": "fullscreen", "model": "opus"}'

# 95-vscode
VSCODE_EXTENSIONS=(
    bierner.github-markdown-preview
    bierner.markdown-checkbox
    bierner.markdown-emoji
    bierner.markdown-footnotes
    bierner.markdown-mermaid
    bierner.markdown-preview-github-styles
    bierner.markdown-yaml-preamble
    charliermarsh.ruff
    cschlosser.doxdocgen
    cweijan.dbclient-jdbc
    cweijan.vscode-postgresql-client2
    davidanson.vscode-markdownlint
    eamodio.gitlens
    github.vscode-pull-request-github
    llvm-vs-code-extensions.vscode-clangd
    mhutchie.git-graph
    ms-python.debugpy
    ms-python.python
    ms-python.vscode-pylance
    ms-python.vscode-python-envs
    ms-toolsai.jupyter
    ms-toolsai.jupyter-keymap
    ms-toolsai.jupyter-renderers
    ms-toolsai.vscode-jupyter-cell-tags
    ms-toolsai.vscode-jupyter-slideshow
    ms-vscode.cmake-tools
    ms-vscode.cpp-devtools
    ms-vscode.cpptools
    ms-vscode.cpptools-extension-pack
    ms-vscode.cpptools-themes
    ms-vsliveshare.vsliveshare
    redhat.vscode-xml
    redhat.vscode-yaml
    seatonjiang.gitmoji-vscode
    streetsidesoftware.code-spell-checker
    streetsidesoftware.code-spell-checker-portuguese-brazilian
    twxs.cmake
    xaver.clang-format
    yahyabatulu.vscode-markdown-alert
)
