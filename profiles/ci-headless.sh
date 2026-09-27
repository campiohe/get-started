#!/usr/bin/env bash
# shellcheck disable=SC2034  # every variable here is read by a module script
#
# A profile is the whole setup in one file: nothing is inherited and nothing
# is layered on top. It is plain bash, sourced by lib.sh. Which variables a
# module reads is on the "# profile:" line of its script; setting anything
# else is an error, so a typo fails instead of doing nothing.

DESCRIPTION="Container or CI runner: no GUI, no interactive prompts"

# Order is irrelevant; modules run in their scripts' number order.
MODULES=(sudo locale base shell python github dotfiles)

# identity, locale: 02-locale, 70-github, 99-dotfiles
GIT_NAME=ci
GIT_EMAIL=ci@localhost
TIMEZONE=America/Sao_Paulo
LOCALES=(en_US.UTF-8 pt_BR.UTF-8)

# 05-base: packages on top of the fixed bootstrap set
EXTRA_PACKAGES=()

# 10-shell, 99-dotfiles
ZSH_THEME=robbyrussell
ZSH_PLUGINS=(git)
# Plugins that are not oh-my-zsh built-ins need a clone source.
declare -A ZSH_PLUGIN_SOURCES=()
NERD_FONT=FiraCode
STARSHIP=false
declare -A MISE_TOOLS=([node]=latest)

# 40-python
PIPX_TOOLS=(ruff uv)

# 70-github
GIT_PROTOCOL=ssh
