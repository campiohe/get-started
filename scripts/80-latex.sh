#!/usr/bin/env bash
# LaTeX: TeX Live (large download, ~2 GB).
# Skip it with: ./install.sh --skip latex
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

log "TeX Live (this is a large download)"
apt_install texlive-latex-extra texlive-fonts-extra
