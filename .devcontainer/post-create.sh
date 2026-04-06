#!/usr/bin/env bash
set -euo pipefail

# =====================
# Shell config (zsh aliases from dotfiles)
# =====================
echo "=== Installing zsh plugins ==="
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

echo "=== Installing Claude Code CLI ==="
npm install -g @anthropic-ai/claude-code

echo "=== Claude plugin paths ==="
# The Dockerfile creates /Users/<host_user> -> /home/vscode so macOS
# absolute paths in installed_plugins.json resolve inside the container.
ls -la /Users/ 2>/dev/null || true

echo "=== Setting up shell config ==="
DOTFILES_DIR="/home/vscode/.dotfiles"
if [[ -d "$DOTFILES_DIR/zsh" ]]; then
    mkdir -p /home/vscode/.config
    ln -sfn "$DOTFILES_DIR/zsh" /home/vscode/.config/zsh
fi
if [[ -f "$DOTFILES_DIR/.zshrc" ]]; then
    ln -sfn "$DOTFILES_DIR/.zshrc" /home/vscode/.zshrc
fi

# =====================
# Python dependencies
# =====================
echo "=== Installing Python dependencies ==="
uv sync

# =====================
# Playwright Chromium
# =====================
echo "=== Installing Playwright Chromium ==="
uv run playwright install --with-deps chromium

# =====================
# Frontend dependencies
# =====================
echo "=== Installing frontend dependencies ==="
cd ui && npm ci --legacy-peer-deps && cd ..

# =====================
# Pre-commit hooks
# =====================
echo "=== Installing pre-commit hooks ==="
uv run pre-commit install 2>/dev/null || true

# =====================
# .env file
# =====================
if [[ ! -f .env ]]; then
    cp .env.example .env 2>/dev/null && echo "Created .env from .env.example" || true
fi

# =====================
# Done
# =====================
echo ""
echo "=== Dev container ready ==="
echo ""
echo "  Backend:   uv run uvicorn api.main:app --reload --host 0.0.0.0"
echo "  Frontend:  cd ui && npm run dev"
echo "  Claude:    claude"
echo "  Azure:     az account show"
echo ""
