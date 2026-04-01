#!/usr/bin/env bash
set -euo pipefail

# =====================
# Shell config (bundled from .devcontainer/config/zsh)
# =====================
echo "=== Installing zsh plugins ==="
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

echo "=== Setting up zsh config ==="
DOTFILES_ZSH="$(pwd)/.devcontainer/config/zsh"
mkdir -p "$HOME/.config/zsh"
ln -sfn "$DOTFILES_ZSH" "$HOME/.config/zsh"
ln -sfn "$DOTFILES_ZSH/.zshrc" "$HOME/.zshrc"

# =====================
# Claude Code (native binary — no Node/npm required)
# =====================
echo "=== Installing Claude Code CLI ==="
curl -fsSL https://claude.ai/install.sh | bash

echo "=== Setting up Claude config ==="
mkdir -p "$HOME/.claude"
cp "$(pwd)/.devcontainer/config/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
# Only write settings.json if one doesn't already exist (e.g. from a mount)
if [[ ! -f "$HOME/.claude/settings.json" ]]; then
    cp "$(pwd)/.devcontainer/config/claude/settings.json" "$HOME/.claude/settings.json"
fi


# =====================
# Python dependencies
# Requires a pyproject.toml / uv.lock at the workspace root.
# =====================
echo "=== Installing Python dependencies ==="
uv sync

# =====================
# Frontend dependencies
# Assumes frontend source lives at src/frontend.
# Adjust the path if your project layout differs.
# =====================
echo "=== Installing frontend dependencies ==="
cd src/frontend && npm ci --legacy-peer-deps && cd ../..

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
echo "  Backend:   uv run uvicorn backend.main:app --reload --app-dir src --host 0.0.0.0"
echo "  Frontend:  cd src/frontend && npm run dev"
echo "  Claude:    claude  (or: ccc / cccc)"
echo "  Azure:     az login  (if .azure not mounted)"
echo ""
