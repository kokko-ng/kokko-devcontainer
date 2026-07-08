#!/usr/bin/env bash
set -euo pipefail

# Resolve the bundled config directory relative to this script so it works
# regardless of the workspace folder name.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_CONFIG_DIR="$SCRIPT_DIR/config"

# =====================
# Shell config (zsh aliases from dotfiles)
# =====================
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_zsh_plugin() {
    local repo="$1" name="$2"
    local dest="$ZSH_CUSTOM_DIR/plugins/$name"
    if [[ -d "$dest/.git" ]]; then
        echo "  $name already present, skipping"
    else
        rm -rf "$dest"
        git clone --depth=1 "$repo" "$dest"
    fi
}
echo "=== Installing zsh plugins ==="
clone_zsh_plugin https://github.com/zsh-users/zsh-autosuggestions zsh-autosuggestions
clone_zsh_plugin https://github.com/zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting

echo "=== Installing Claude Code CLI ==="
if command -v claude >/dev/null 2>&1; then
    echo "  Claude Code already installed at $(command -v claude)"
else
    curl -fsSL https://claude.ai/install.sh | bash
fi

echo "=== Installing GitHub Copilot CLI ==="
# Published as @github/copilot on npm. The devcontainer Node feature creates a
# user-writable global prefix, so no sudo is needed.
if command -v copilot >/dev/null 2>&1; then
    echo "  Copilot CLI already installed at $(command -v copilot)"
elif command -v npm >/dev/null 2>&1; then
    npm install -g @github/copilot
else
    echo "  npm not available — skipping Copilot CLI install"
fi

echo "=== Installing Playwright CLI ==="
# https://playwright.dev/agent-cli/installation
if command -v playwright-cli >/dev/null 2>&1; then
    echo "  Playwright CLI already installed at $(command -v playwright-cli)"
elif command -v npm >/dev/null 2>&1; then
    npm install -g @playwright/cli@latest
    playwright-cli install-browser --with-deps
    playwright-cli install --skills
else
    echo "  npm not available — skipping Playwright CLI install"
fi

echo "=== Configuring Claude Code ==="
CLAUDE_DIR="/home/vscode/.claude"
BUNDLED_CLAUDE_DIR="$BUNDLED_CONFIG_DIR/claude"
mkdir -p "$CLAUDE_DIR"
# Copy bundled settings unless a host mount already provides one
if [[ ! -f "$CLAUDE_DIR/settings.json" && -f "$BUNDLED_CLAUDE_DIR/settings.json" ]]; then
    cp "$BUNDLED_CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json"
    echo "  Copied bundled settings.json"
fi
if [[ ! -f "$CLAUDE_DIR/CLAUDE.md" && -f "$BUNDLED_CLAUDE_DIR/CLAUDE.md" ]]; then
    cp "$BUNDLED_CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    echo "  Copied bundled CLAUDE.md"
fi

echo "=== Claude plugin paths ==="
# The Dockerfile creates /Users/<host_user> -> /home/vscode so macOS
# absolute paths in installed_plugins.json resolve inside the container.
ls -la /Users/ 2>/dev/null || true

echo "=== Setting up shell config ==="
DOTFILES_DIR="/home/vscode/.dotfiles"
BUNDLED_ZSH_DIR="$BUNDLED_CONFIG_DIR/zsh"
if [[ -d "$DOTFILES_DIR/zsh" ]]; then
    mkdir -p /home/vscode/.config
    ln -sfn "$DOTFILES_DIR/zsh" /home/vscode/.config/zsh
elif [[ -d "$BUNDLED_ZSH_DIR" ]]; then
    mkdir -p /home/vscode/.config
    ln -sfn "$BUNDLED_ZSH_DIR" /home/vscode/.config/zsh
fi
if [[ -f "$DOTFILES_DIR/.zshrc" ]]; then
    ln -sfn "$DOTFILES_DIR/.zshrc" /home/vscode/.zshrc
elif [[ -f "$BUNDLED_ZSH_DIR/.zshrc" ]]; then
    ln -sfn "$BUNDLED_ZSH_DIR/.zshrc" /home/vscode/.zshrc
fi

# =====================
# Python dependencies
# =====================
if [[ -f pyproject.toml ]]; then
    echo "=== Installing Python dependencies ==="
    uv sync
else
    echo "=== Skipping Python dependencies (no pyproject.toml) ==="
fi

# =====================
# Playwright Chromium
# =====================
if [[ -f pyproject.toml ]]; then
    echo "=== Installing Playwright Chromium ==="
    uv run playwright install --with-deps chromium
else
    echo "=== Skipping Playwright (no pyproject.toml) ==="
fi

# =====================
# Frontend dependencies
# =====================
if [[ -d ui ]]; then
    echo "=== Installing frontend dependencies ==="
    cd ui && npm ci --legacy-peer-deps && cd ..
else
    echo "=== Skipping frontend dependencies (no ui/ directory) ==="
fi

# =====================
# Pre-commit hooks
# =====================
if [[ -f .pre-commit-config.yaml ]]; then
    echo "=== Installing pre-commit hooks ==="
    uv run pre-commit install 2>/dev/null || true
else
    echo "=== Skipping pre-commit hooks (no config found) ==="
fi

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
