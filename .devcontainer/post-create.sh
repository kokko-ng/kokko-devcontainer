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

# =====================
# Git safety net (see .devcontainer/config/claude/CLAUDE.md)
# =====================
# Deliberately NOT gated on "unless a file already exists", unlike the two
# copies above. The hooks are the enforcement layer, and the setup most likely
# to skip them -- a host-mounted ~/.claude -- is exactly the setup where a
# long-lived project has work worth protecting. Always refresh them, and merge
# the hook wiring into whatever settings.json is present rather than replacing
# it, so a user's own settings survive.
echo "=== Installing git safety hooks ==="
if [[ -d "$BUNDLED_CLAUDE_DIR/hooks" ]]; then
    mkdir -p "$CLAUDE_DIR/hooks"
    cp "$BUNDLED_CLAUDE_DIR"/hooks/*.sh "$CLAUDE_DIR/hooks/"
    chmod +x "$CLAUDE_DIR"/hooks/*.sh
    echo "  Installed: $(cd "$CLAUDE_DIR/hooks" && echo *.sh)"
fi

if [[ -f "$BUNDLED_CONFIG_DIR/bin/snaps" ]]; then
    mkdir -p "$HOME/.local/bin"
    if sudo install -m 0755 "$BUNDLED_CONFIG_DIR/bin/snaps" /usr/local/bin/snaps 2>/dev/null \
        || install -m 0755 "$BUNDLED_CONFIG_DIR/bin/snaps" "$HOME/.local/bin/snaps" 2>/dev/null; then
        echo "  Installed 'snaps' (list/show/diff/restore working-tree snapshots)"
    else
        echo "  WARNING: could not install the 'snaps' helper onto PATH"
    fi
fi

# Splice the hook wiring into the live settings.json. See merge-hooks.jq: this
# preserves the user's own hooks and is safe to re-run on every rebuild.
if command -v jq >/dev/null 2>&1 \
    && [[ -f "$BUNDLED_CLAUDE_DIR/settings.json" && -f "$CLAUDE_DIR/settings.json" ]]; then
    if jq -e . "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
        cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak"
        if jq -s -f "$BUNDLED_CLAUDE_DIR/merge-hooks.jq" \
            "$CLAUDE_DIR/settings.json" "$BUNDLED_CLAUDE_DIR/settings.json" \
            > "$CLAUDE_DIR/settings.json.tmp" 2>/dev/null \
            && jq -e . "$CLAUDE_DIR/settings.json.tmp" >/dev/null 2>&1; then
            mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
            echo "  Merged git safety hooks and plugin roster into settings.json (backup: settings.json.bak)"
        else
            rm -f "$CLAUDE_DIR/settings.json.tmp"
            echo "  WARNING: hook merge failed — settings.json left unchanged."
        fi
    else
        echo "  WARNING: settings.json is not valid JSON — leaving it alone."
        echo "           Add the 'hooks' block from $BUNDLED_CLAUDE_DIR/settings.json by hand."
    fi
fi

# Never expire the reflog or prune unreachable objects. The default 90/30-day
# windows quietly delete the very objects a recovery depends on -- including the
# snapshots' parents. Disk is cheaper than the work.
echo "=== Configuring git for recoverability ==="
# Bind-mounted workspaces are owned by the HOST uid, not the container user.
# Without safe.directory git refuses every command with "detected dubious
# ownership" -- which also silently kills the snapshot hook (its git calls
# fail, so nothing is ever checkpointed and the safety net protects nothing).
# postCreateCommand runs with the workspace folder as cwd, so $PWD is right.
git config --global --add safe.directory "$PWD"
echo "  safe.directory: $PWD"
git config --global gc.reflogExpire never
git config --global gc.reflogExpireUnreachable never
git config --global gc.pruneExpire never
git config --global rerere.enabled true
echo "  reflog retention: never expire; unreachable objects: never pruned"

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
# `uv sync` above installs only the default dependency groups. A project can
# declare playwright in a non-default group (or not at all), in which case
# `uv run playwright` aborts with "Failed to spawn: playwright" and takes the
# whole postCreateCommand down with it. Probe the synced environment first.
if [[ -f pyproject.toml ]] && uv run python -c "import playwright" >/dev/null 2>&1; then
    echo "=== Installing Playwright Chromium ==="
    uv run playwright install --with-deps chromium || \
        echo "  WARNING: playwright install failed — browsers not provisioned"
elif [[ -f pyproject.toml ]]; then
    echo "=== Skipping Playwright Chromium (playwright not in the synced environment) ==="
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

# =====================
# Colima VM disk check
# =====================
# Runs last so the warning is the final thing on screen.
#
# A full Colima disk kills the Docker daemon with no usable error (`colima
# status` still reports healthy), so warn early. See MANAGING.md.
#
# Inside a container `df /` reports the VM's disk, so this measures the right
# thing. Must never fail the build -- hence the guards and the `|| true`.
check_vm_disk() {
    local pct avail
    pct="$(df -P / 2>/dev/null | awk 'NR==2 {sub(/%/,"",$5); print $5}')"
    avail="$(df -Ph / 2>/dev/null | awk 'NR==2 {print $4}')"

    [[ "$pct" =~ ^[0-9]+$ ]] || return 0
    (( pct >= 80 )) || return 0

    echo "=== WARNING: Colima VM disk is ${pct}% full (${avail} free) ==="
    echo ""
    echo "  This is shared by every container on this machine. At 100% the"
    echo "  Docker daemon dies and colima reports no useful error."
    echo ""
    echo "  Reclaim now (safe -- keeps your volumes and running containers):"
    echo ""
    echo "    docker image prune -a"
    echo ""
    echo "  Do NOT use 'docker system prune --volumes': it also deletes the"
    echo "  docker-in-docker, Claude Code and VS Code state volumes."
    echo ""
    echo "  See MANAGING.md -> Disk management."
    echo ""
}
check_vm_disk || true
