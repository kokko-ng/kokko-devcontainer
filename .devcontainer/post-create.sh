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
mkdir -p "$HOME/.config"
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
# Playwright MCP — inject --no-sandbox for container environments
#
# The container drops all Linux capabilities (--cap-drop=ALL), so Chromium
# cannot use its kernel namespace sandbox. The Playwright MCP must be told
# to launch the browser with --no-sandbox.
#
# The Claude Code playwright plugin ships a .mcp.json that starts the MCP
# server. The plugin cache is populated when Claude Code first downloads the
# plugin, so the paths below may not exist yet. We pre-seed the 'unknown'
# fallback path (always used as a fallback) and patch any versioned paths
# that already exist.
#
# Chromium itself is installed in the Dockerfile and symlinked to the path
# the Playwright MCP expects: /opt/google/chrome/chrome.
# =====================
echo "=== Configuring Playwright MCP for container (--no-sandbox) ==="
_playwright_mcp_json() {
    cat <<'EOF'
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest", "--headless", "--no-sandbox"]
  }
}
EOF
}

# Pre-seed the 'unknown' fallback slot so it is ready before first claude run
_unknown_cfg="$HOME/.claude/plugins/cache/claude-plugins-official/playwright/unknown/.mcp.json"
mkdir -p "$(dirname "$_unknown_cfg")"
_playwright_mcp_json > "$_unknown_cfg"

# Patch any versioned slots that already exist (e.g. from a mounted .claude)
find "$HOME/.claude/plugins/cache/claude-plugins-official/playwright" \
    -name ".mcp.json" ! -path "*/unknown/*" 2>/dev/null \
    | while read -r cfg; do
        _playwright_mcp_json > "$cfg"
        echo "  Patched: $cfg"
    done


# =====================
# Python dependencies
# Only runs if a pyproject.toml exists at the workspace root.
# =====================
if [[ -f pyproject.toml ]]; then
    echo "=== Installing Python dependencies ==="
    uv sync
else
    echo "=== Skipping Python dependencies (no pyproject.toml found) ==="
fi

# =====================
# Frontend dependencies
# Only runs if src/frontend/package.json exists.
# =====================
if [[ -f src/frontend/package.json ]]; then
    echo "=== Installing frontend dependencies ==="
    cd src/frontend && npm ci --legacy-peer-deps && cd ../..
else
    echo "=== Skipping frontend dependencies (no src/frontend/package.json found) ==="
fi

# =====================
# Pre-commit hooks
# Only runs if .pre-commit-config.yaml exists.
# =====================
if [[ -f .pre-commit-config.yaml ]]; then
    echo "=== Installing pre-commit hooks ==="
    uv run pre-commit install 2>/dev/null || true
fi

# =====================
# .env file
# Only copies if .env.example exists.
# =====================
if [[ ! -f .env && -f .env.example ]]; then
    cp .env.example .env
    echo "Created .env from .env.example"
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
