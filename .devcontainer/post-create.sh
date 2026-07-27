#!/usr/bin/env bash
set -euo pipefail

# Two modes:
#
#   post-create.sh                 Full provision. Run once by postCreateCommand.
#   post-create.sh --config-only   Re-apply the bundled config only, in place,
#                                  in a container that is already running. Skips
#                                  every tool install and every project
#                                  dependency step, so it is fast and safe to
#                                  re-run. This is what /devcontainer-update
#                                  calls after pulling newer config files, and
#                                  it is why the script is a set of functions
#                                  rather than one long sequence.
#
# Anything that only takes effect at image build time (Dockerfile, the
# `features` and `containerEnv` blocks of devcontainer.json, runArgs) cannot be
# applied by --config-only. Those still need a rebuild.

MODE="full"
case "${1:-}" in
    --config-only) MODE="config" ;;
    "") ;;
    *)
        echo "usage: post-create.sh [--config-only]" >&2
        exit 2
        ;;
esac

# Resolve the bundled config directory relative to this script so it works
# regardless of the workspace folder name.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_CONFIG_DIR="$SCRIPT_DIR/config"
CLAUDE_DIR="/home/vscode/.claude"
BUNDLED_CLAUDE_DIR="$BUNDLED_CONFIG_DIR/claude"

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

install_zsh_plugins() {
    echo "=== Installing zsh plugins ==="
    clone_zsh_plugin https://github.com/zsh-users/zsh-autosuggestions zsh-autosuggestions
    clone_zsh_plugin https://github.com/zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting
}

install_claude_cli() {
    echo "=== Installing Claude Code CLI ==="
    if command -v claude >/dev/null 2>&1; then
        echo "  Claude Code already installed at $(command -v claude)"
    else
        curl -fsSL https://claude.ai/install.sh | bash
    fi
}

install_copilot_cli() {
    echo "=== Installing GitHub Copilot CLI ==="
    # Published as @github/copilot on npm. The devcontainer Node feature creates
    # a user-writable global prefix, so no sudo is needed.
    if command -v copilot >/dev/null 2>&1; then
        echo "  Copilot CLI already installed at $(command -v copilot)"
    elif command -v npm >/dev/null 2>&1; then
        npm install -g @github/copilot
    else
        echo "  npm not available — skipping Copilot CLI install"
    fi
}

install_playwright_cli() {
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
}

configure_claude() {
    echo "=== Configuring Claude Code ==="
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
}

# =====================
# Git safety net (see .devcontainer/config/claude/CLAUDE.md)
# =====================
# Deliberately NOT gated on "unless a file already exists", unlike the two
# copies above. The hooks are the enforcement layer, and the setup most likely
# to skip them -- a host-mounted ~/.claude -- is exactly the setup where a
# long-lived project has work worth protecting. Always refresh them, and merge
# the hook wiring into whatever settings.json is present rather than replacing
# it, so a user's own settings survive.
install_git_safety_hooks() {
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
}

# Splice the hook wiring into the live settings.json. See merge-hooks.jq: this
# preserves the user's own hooks and is safe to re-run on every rebuild.
merge_claude_settings() {
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
}

# =====================
# Claude Code plugins
# =====================
# settings.json only ENABLES plugins -- it does not fetch them. An entry in
# enabledPlugins for a plugin that was never installed is inert, so a fresh
# container came up with an empty plugin directory until someone ran /plugin by
# hand. Install the roster here, driven by the bundled settings.json so the two
# can never drift: every marketplace in extraKnownMarketplaces is registered,
# and every plugin set to `true` in enabledPlugins is installed.
#
# This must never fail the build. The container is perfectly usable without the
# plugins, and this step needs both network and a signed-in CLI.
bootstrap_claude_plugins() {
    echo "=== Installing Claude Code plugins ==="
    local settings="$BUNDLED_CLAUDE_DIR/settings.json"

    if ! command -v claude >/dev/null 2>&1; then
        echo "  claude not on PATH — skipping plugin install"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1 || [[ ! -f "$settings" ]]; then
        echo "  jq or bundled settings.json missing — skipping plugin install"
        return 0
    fi

    local name repo
    while read -r name repo; do
        [[ -n "$name" && -n "$repo" ]] || continue
        # `add` fails when the marketplace is already registered, which is the
        # normal case on a re-run -- fall through to `update` so an existing
        # registration is still refreshed from GitHub.
        if claude plugin marketplace add "$repo" >/dev/null 2>&1; then
            echo "  marketplace added: $name ($repo)"
        elif claude plugin marketplace update "$name" >/dev/null 2>&1; then
            echo "  marketplace updated: $name ($repo)"
        else
            echo "  WARNING: could not add or update marketplace $name ($repo)"
        fi
    done < <(jq -r '
        (.extraKnownMarketplaces // {})
        | to_entries[]
        | select(.value.source.source == "github")
        | "\(.key) \(.value.source.repo)"' "$settings")

    local plugin
    while read -r plugin; do
        [[ -n "$plugin" ]] || continue
        if claude plugin install "$plugin" >/dev/null 2>&1; then
            echo "  installed: $plugin"
        elif claude plugin update "$plugin" >/dev/null 2>&1; then
            echo "  updated: $plugin"
        else
            echo "  WARNING: could not install or update $plugin"
        fi
    done < <(jq -r '
        (.enabledPlugins // {})
        | to_entries[]
        | select(.value == true)
        | .key' "$settings")
}

# Never expire the reflog or prune unreachable objects. The default 90/30-day
# windows quietly delete the very objects a recovery depends on -- including the
# snapshots' parents. Disk is cheaper than the work.
configure_git() {
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
}

report_plugin_paths() {
    echo "=== Claude plugin paths ==="
    # The Dockerfile creates /Users/<host_user> -> /home/vscode so macOS
    # absolute paths in installed_plugins.json resolve inside the container.
    ls -la /Users/ 2>/dev/null || true
}

link_shell_config() {
    echo "=== Setting up shell config ==="
    local dotfiles_dir="/home/vscode/.dotfiles"
    local bundled_zsh_dir="$BUNDLED_CONFIG_DIR/zsh"
    if [[ -d "$dotfiles_dir/zsh" ]]; then
        mkdir -p /home/vscode/.config
        ln -sfn "$dotfiles_dir/zsh" /home/vscode/.config/zsh
    elif [[ -d "$bundled_zsh_dir" ]]; then
        mkdir -p /home/vscode/.config
        ln -sfn "$bundled_zsh_dir" /home/vscode/.config/zsh
    fi
    if [[ -f "$dotfiles_dir/.zshrc" ]]; then
        ln -sfn "$dotfiles_dir/.zshrc" /home/vscode/.zshrc
    elif [[ -f "$bundled_zsh_dir/.zshrc" ]]; then
        ln -sfn "$bundled_zsh_dir/.zshrc" /home/vscode/.zshrc
    fi
}

# =====================
# Python dependencies
# =====================
install_python_deps() {
    if [[ -f pyproject.toml ]]; then
        echo "=== Installing Python dependencies ==="
        uv sync
    else
        echo "=== Skipping Python dependencies (no pyproject.toml) ==="
    fi
}

# =====================
# Playwright Chromium
# =====================
# `uv sync` above installs only the default dependency groups. A project can
# declare playwright in a non-default group (or not at all), in which case
# `uv run playwright` aborts with "Failed to spawn: playwright" and takes the
# whole postCreateCommand down with it. Probe the synced environment first.
install_playwright_browsers() {
    if [[ -f pyproject.toml ]] && uv run python -c "import playwright" >/dev/null 2>&1; then
        echo "=== Installing Playwright Chromium ==="
        uv run playwright install --with-deps chromium || \
            echo "  WARNING: playwright install failed — browsers not provisioned"
    elif [[ -f pyproject.toml ]]; then
        echo "=== Skipping Playwright Chromium (playwright not in the synced environment) ==="
    else
        echo "=== Skipping Playwright (no pyproject.toml) ==="
    fi
}

# =====================
# Frontend dependencies
# =====================
install_frontend_deps() {
    if [[ -d ui ]]; then
        echo "=== Installing frontend dependencies ==="
        (cd ui && npm ci --legacy-peer-deps)
    else
        echo "=== Skipping frontend dependencies (no ui/ directory) ==="
    fi
}

# =====================
# Pre-commit hooks
# =====================
install_precommit_hooks() {
    if [[ -f .pre-commit-config.yaml ]]; then
        echo "=== Installing pre-commit hooks ==="
        uv run pre-commit install 2>/dev/null || true
    else
        echo "=== Skipping pre-commit hooks (no config found) ==="
    fi
}

# =====================
# .env file
# =====================
create_env_file() {
    if [[ ! -f .env ]]; then
        cp .env.example .env 2>/dev/null && echo "Created .env from .env.example" || true
    fi
}

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

# =====================
# Bundled config
# =====================
# Everything whose effect is a file under ~/.claude, ~/.config or ~/.gitconfig.
# Every step here is idempotent, which is what makes --config-only safe to run
# against a live container to pick up newer bundled config without a rebuild.
apply_bundled_config() {
    configure_claude
    install_git_safety_hooks
    merge_claude_settings
    bootstrap_claude_plugins || true
    configure_git
    link_shell_config
}

if [[ "$MODE" == "config" ]]; then
    echo "=== Refreshing bundled config (no rebuild) ==="
    apply_bundled_config
    echo ""
    echo "=== Config refreshed ==="
    echo ""
    echo "  Restart Claude Code (or run /reload-plugins) to pick up plugin changes."
    echo "  Open a new shell to pick up zsh changes."
    echo "  Dockerfile, devcontainer.json features/containerEnv, and runArgs"
    echo "  changes still need a container rebuild."
    echo ""
    exit 0
fi

install_zsh_plugins
install_claude_cli
install_copilot_cli
install_playwright_cli
apply_bundled_config
report_plugin_paths
install_python_deps
install_playwright_browsers
install_frontend_deps
install_precommit_hooks
create_env_file

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

check_vm_disk || true
