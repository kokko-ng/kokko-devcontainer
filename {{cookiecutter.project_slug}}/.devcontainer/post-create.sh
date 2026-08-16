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

# The Claude CLI installs to ~/.local/bin, which is NOT on PATH during
# postCreateCommand itself (only interactive shells add it) — without this the
# plugin bootstrap below silently skips on the very first build.
export PATH="$HOME/.local/bin:$PATH"

# Resolve the bundled config directory relative to this script so it works
# regardless of the workspace folder name.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_CONFIG_DIR="$SCRIPT_DIR/config"
CLAUDE_DIR="$HOME/.claude"
BUNDLED_CLAUDE_DIR="$BUNDLED_CONFIG_DIR/claude"

# Failed provisioning steps are recorded here instead of killing the build —
# one transient npm/curl failure must not abort the whole container.
PROVISION_STATUS="$HOME/.devcontainer-provision-status"

# Provisioning toggles and paths. These are set in devcontainer.json's
# containerEnv from the answers given when this project was generated from the
# cookiecutter template; the defaults below are what a bare `bash
# post-create.sh` (no devcontainer, e.g. a plain `docker run`) gets. Keeping
# them as environment variables rather than templating this script is what lets
# the file stay shellcheck-clean and testable without a rendering step.
INSTALL_COPILOT_CLI="${DEVCONTAINER_INSTALL_COPILOT_CLI:-1}"
INSTALL_PLAYWRIGHT="${DEVCONTAINER_INSTALL_PLAYWRIGHT:-1}"
FRONTEND_DIR="${DEVCONTAINER_FRONTEND_DIR:-ui}"

# =====================
# Retry / degrade helpers
# =====================
retry() {
    local name="$1" attempt
    shift
    for attempt in 1 2 3; do
        "$@" && return 0
        echo "  attempt $attempt/3 failed: $name"
        [[ $attempt -lt 3 ]] && sleep $((attempt * 5))
    done
    return 1
}

# step <name> <cmd...> — run with retry; on final failure warn loudly and
# record the step in $PROVISION_STATUS rather than dying under set -e.
step() {
    local name="$1"; shift
    if retry "$name" "$@"; then
        return 0
    fi
    echo "  WARNING: step '$name' failed after 3 attempts — continuing without it."
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) FAILED: $name" >> "$PROVISION_STATUS"
    return 0
}

provision_summary() {
    echo ""
    if [[ -s "$PROVISION_STATUS" ]]; then
        echo "=== WARNING: some provisioning steps FAILED ==="
        sed 's/^/  /' "$PROVISION_STATUS"
        echo "  Fix connectivity and re-run: bash .devcontainer/post-create.sh"
    else
        echo "=== All provisioning steps completed ==="
    fi
}

# =====================
# Named-volume mount points
# =====================
# Docker creates named-volume mount points root-owned on first use; make the
# cache and history volumes writable by the container user.
fix_volume_ownership() {
    local d
    for d in "$HOME/.cache/uv" "$HOME/.npm" "$HOME/.cache/ms-playwright" /commandhistory; do
        [[ -d "$d" && ! -w "$d" ]] || continue
        sudo chown "$(id -u):$(id -g)" "$d" 2>/dev/null || \
            echo "  WARNING: $d is not writable and could not be chowned"
    done
}

# =====================
# Shell config (zsh aliases from dotfiles)
# =====================
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_zsh_plugin() {
    local repo="$1" name="$2" tag="${3:-}"
    local dest="$ZSH_CUSTOM_DIR/plugins/$name"
    if [[ -d "$dest/.git" ]]; then
        echo "  $name already present, skipping"
    elif [[ -n "$tag" ]]; then
        rm -rf "$dest"
        step "zsh-plugin-$name" git clone --depth=1 --branch "$tag" "$repo" "$dest"
    else
        rm -rf "$dest"
        step "zsh-plugin-$name" git clone --depth=1 "$repo" "$dest"
    fi
}

install_zsh_plugins() {
    echo "=== Installing zsh plugins ==="
    # Pinned to release tags so a rebuild cannot silently pick up an untested
    # HEAD. Dependabot cannot see these pins — check for newer tags manually
    # (git ls-remote --tags <repo>); see MANAGING.md -> Pin audit.
    clone_zsh_plugin https://github.com/zsh-users/zsh-autosuggestions zsh-autosuggestions v0.7.1
    clone_zsh_plugin https://github.com/zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting 0.8.0
}

install_claude_cli() {
    echo "=== Installing Claude Code CLI ==="
    # The Dockerfile now bakes the binary into the image, so this normally
    # just reports the existing install. It stays as a fallback for images
    # built before that layer existed.
    if command -v claude >/dev/null 2>&1; then
        echo "  Claude Code already installed at $(command -v claude)"
    else
        step "claude-cli" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
    fi
}

install_copilot_cli() {
    if [[ "$INSTALL_COPILOT_CLI" != "1" ]]; then
        echo "=== Skipping GitHub Copilot CLI (DEVCONTAINER_INSTALL_COPILOT_CLI=$INSTALL_COPILOT_CLI) ==="
        return 0
    fi
    echo "=== Installing GitHub Copilot CLI ==="
    # Published as @github/copilot on npm. The devcontainer Node feature creates
    # a user-writable global prefix, so no sudo is needed.
    if command -v copilot >/dev/null 2>&1; then
        echo "  Copilot CLI already installed at $(command -v copilot)"
    elif command -v npm >/dev/null 2>&1; then
        step "copilot-cli" npm install -g @github/copilot
    else
        echo "  npm not available — skipping Copilot CLI install"
    fi
}

install_playwright_cli() {
    if [[ "$INSTALL_PLAYWRIGHT" != "1" ]]; then
        echo "=== Skipping Playwright CLI (DEVCONTAINER_INSTALL_PLAYWRIGHT=$INSTALL_PLAYWRIGHT) ==="
        return 0
    fi
    echo "=== Installing Playwright CLI ==="
    # https://playwright.dev/agent-cli/installation
    if ! command -v npm >/dev/null 2>&1 && ! command -v playwright-cli >/dev/null 2>&1; then
        echo "  npm not available — skipping Playwright CLI install"
        return 0
    fi
    if command -v playwright-cli >/dev/null 2>&1; then
        echo "  Playwright CLI already installed at $(command -v playwright-cli)"
    else
        # Pinned (was @latest). Dependabot cannot see this pin — bump it
        # manually (npm view @playwright/cli version); see MANAGING.md -> Pin audit.
        step "playwright-cli" npm install -g @playwright/cli@0.1.17
    fi
    command -v playwright-cli >/dev/null 2>&1 || return 0
    # Browsers persist in the pw-browsers named volume (PLAYWRIGHT_BROWSERS_PATH,
    # see devcontainer.json), so the expensive --with-deps download only runs
    # when the volume is still empty — first creation pays, rebuilds are fast.
    local browsers_dir="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
    if [[ -d "$browsers_dir" && -n "$(ls -A "$browsers_dir" 2>/dev/null)" ]]; then
        echo "  Playwright browsers already present in $browsers_dir — skipping download"
    else
        step "playwright-browsers" playwright-cli install-browser --with-deps
    fi
    step "playwright-skills" playwright-cli install --skills
}

configure_claude() {
    echo "=== Configuring Claude Code ==="
    mkdir -p "$CLAUDE_DIR"
    # Copy bundled settings unless a host mount already provides one. The
    # bundled file contains no machine-specific paths, so it is used verbatim.
    if [[ ! -f "$CLAUDE_DIR/settings.json" && -f "$BUNDLED_CLAUDE_DIR/settings.json" ]]; then
        cp "$BUNDLED_CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json"
        echo "  Copied bundled settings.json"
    fi
    refresh_claude_md
}

# Bundled CLAUDE.md updates must reach existing containers, but never at the
# cost of clobbering a user's edits. (settings.json needs no such treatment:
# the jq merge handles it.) Hash tracking: the bundled file's sha256 is
# stamped at copy time, and later runs overwrite the live file only while its
# hash still equals the stamp — i.e. the user never touched it.
refresh_claude_md() {
    local bundled="$BUNDLED_CLAUDE_DIR/CLAUDE.md"
    local live="$CLAUDE_DIR/CLAUDE.md"
    local stamp="$CLAUDE_DIR/.claude-md.bundled-sha256"
    [[ -f "$bundled" ]] || return 0
    local bundled_sha live_sha stored_sha
    bundled_sha=$(sha256sum "$bundled" | awk '{print $1}')
    if [[ ! -f "$live" ]]; then
        cp "$bundled" "$live"
        printf '%s\n' "$bundled_sha" > "$stamp"
        echo "  Copied bundled CLAUDE.md"
        return 0
    fi
    live_sha=$(sha256sum "$live" | awk '{print $1}')
    stored_sha=$(cat "$stamp" 2>/dev/null || true)
    if [[ "$live_sha" == "$bundled_sha" ]]; then
        # Already current — just make sure the stamp exists for next time.
        printf '%s\n' "$bundled_sha" > "$stamp"
    elif [[ "$live_sha" == "$stored_sha" ]]; then
        # Byte-identical to what a previous run installed: the user never
        # edited it, so the newer bundle can replace it safely.
        cp "$bundled" "$live"
        printf '%s\n' "$bundled_sha" > "$stamp"
        echo "  Refreshed CLAUDE.md from the bundle (previous copy was unmodified)"
    else
        # User-edited, or predates hash tracking: hands off, tell them how to
        # reconcile instead.
        echo "  NOTE: ~/.claude/CLAUDE.md differs from the bundle and was left alone. Compare with: diff '$bundled' '$live'"
    fi
}

# =====================
# Retired git safety layer — cleanup
# =====================
# Earlier bundles installed PreToolUse/SessionStart git hooks (guard-git.sh,
# git-snapshot.sh, session-git-safety.sh, lib-git-target.sh) plus the `snaps`
# CLI, and enabled the kokko-safety plugin. Claude Code's built-in Auto
# permission mode (permissions.defaultMode = "auto") replaced all of it.
# Containers provisioned by those bundles still carry the files on disk and
# the hook wiring in their settings.json — remove the files here, and let the
# settings merge below strip the wiring. Idempotent: a quiet no-op once
# nothing is left. Only the four bundled scripts are touched; a user's own
# hooks in ~/.claude/hooks/ are not.
retire_git_safety_layer() {
    local f removed=0
    for f in guard-git.sh git-snapshot.sh session-git-safety.sh lib-git-target.sh; do
        if [[ -e "$CLAUDE_DIR/hooks/$f" ]]; then
            rm -f "$CLAUDE_DIR/hooks/$f"
            removed=1
        fi
    done
    for f in /usr/local/bin/snaps "$HOME/.local/bin/snaps"; do
        [[ -e "$f" ]] || continue
        if sudo rm -f "$f" 2>/dev/null || rm -f "$f" 2>/dev/null; then
            removed=1
        else
            echo "  WARNING: could not remove retired helper $f"
        fi
    done
    # The kokko-safety plugin was the same layer; the roster prune disables
    # it, but an installed copy would otherwise linger on disk.
    if [[ "${KOKKO_SKIP_PLUGINS:-}" != "1" ]] && command -v claude >/dev/null 2>&1; then
        if claude plugin uninstall kokko-safety@kokko-ng-kokko-cmds >/dev/null 2>&1; then
            removed=1
        fi
    fi
    if [[ "$removed" -eq 1 ]]; then
        echo "=== Removed the retired git safety layer (hooks, snaps, kokko-safety) ==="
        echo "    Leftover refs/snapshots/* in project repos are inert; see MANAGING.md to prune them."
    fi
}

# Merge the bundled settings into the live settings.json. See
# merge-settings.jq: this preserves the user's own settings and hooks, strips
# the retired git-safety hook wiring, and is safe to re-run on every rebuild.
merge_claude_settings() {
    # jq is a hard dependency of the settings pipeline: the merge, the roster
    # prune, and the plugin bootstrap all parse settings.json with it. A
    # container without jq is misconfigured — say so and stop.
    if ! command -v jq >/dev/null 2>&1; then
        echo "" >&2
        echo "FATAL: jq is not installed, and the settings merge and plugin bootstrap" >&2
        echo "       cannot work without it. jq is installed by the Dockerfile —" >&2
        echo "       rebuild the container, or run: sudo apt-get update && sudo apt-get install -y jq" >&2
        echo "" >&2
        exit 1
    fi
    if [[ -f "$BUNDLED_CLAUDE_DIR/settings.json" && -f "$CLAUDE_DIR/settings.json" ]]; then
        if jq -e . "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
            # Timestamped backups; keep the 5 most recent.
            local bak
            bak="$CLAUDE_DIR/settings.json.bak.$(date -u +%Y%m%dT%H%M%SZ)"
            cp "$CLAUDE_DIR/settings.json" "$bak"
            # shellcheck disable=SC2012  # our own timestamped names: safe for ls
            ls -1t "$CLAUDE_DIR"/settings.json.bak.* 2>/dev/null | tail -n +6 | xargs -r rm -f --
            if jq -s -f "$BUNDLED_CLAUDE_DIR/merge-settings.jq" \
                "$CLAUDE_DIR/settings.json" "$BUNDLED_CLAUDE_DIR/settings.json" \
                > "$CLAUDE_DIR/settings.json.tmp" 2>/dev/null \
                && jq -e . "$CLAUDE_DIR/settings.json.tmp" >/dev/null 2>&1; then
                mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
                echo "  Merged bundled settings and plugin roster into settings.json (backup: $(basename "$bak"))"
                prune_removed_roster_entries
            else
                rm -f "$CLAUDE_DIR/settings.json.tmp"
                echo "  WARNING: settings merge failed — settings.json left unchanged."
            fi
        else
            echo "  WARNING: settings.json is not valid JSON — leaving it alone."
            echo "           Compare it against $BUNDLED_CLAUDE_DIR/settings.json by hand."
        fi
    fi
}

# The merge above is ADDITIVE, so a plugin removed from the bundled roster
# would stay enabled in the live settings forever. prune-roster.jq compares
# the new bundle against a snapshot of the PREVIOUS bundle and deletes only
# keys that (a) the old bundle shipped, (b) the new bundle dropped, and
# (c) the user never overrode. The snapshot is then advanced to the new
# bundle so the next run has a baseline.
prune_removed_roster_entries() {
    local roster_snap="$CLAUDE_DIR/.kokko-bundled-roster.json"
    local prune_jq="$BUNDLED_CLAUDE_DIR/prune-roster.jq"
    if [[ -f "$roster_snap" && -f "$prune_jq" ]] \
        && jq -e . "$roster_snap" >/dev/null 2>&1; then
        if jq -s -f "$prune_jq" \
            "$roster_snap" "$BUNDLED_CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json" \
            > "$CLAUDE_DIR/settings.json.tmp" 2>/dev/null \
            && jq -e . "$CLAUDE_DIR/settings.json.tmp" >/dev/null 2>&1; then
            mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
        else
            rm -f "$CLAUDE_DIR/settings.json.tmp"
            echo "  WARNING: roster prune failed — plugins removed from the bundle may stay enabled."
        fi
    fi
    jq '{enabledPlugins: (.enabledPlugins // {}), extraKnownMarketplaces: (.extraKnownMarketplaces // {})}' \
        "$BUNDLED_CLAUDE_DIR/settings.json" > "$roster_snap" 2>/dev/null \
        || echo "  WARNING: could not record the bundled roster snapshot."
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
    # For CI and offline work: skip the whole bootstrap (every call here needs
    # network and a signed-in CLI, so in CI they are all doomed anyway).
    if [[ "${KOKKO_SKIP_PLUGINS:-}" == "1" ]]; then
        echo "  KOKKO_SKIP_PLUGINS=1 — skipping plugin bootstrap entirely"
        return 0
    fi

    # Read the MERGED live settings when present, not the bundle: a plugin the
    # user disabled locally must not be reinstalled on every start. The bundle
    # is only the fallback for a first run where no live file exists yet.
    local settings="$CLAUDE_DIR/settings.json"
    [[ -f "$settings" ]] || settings="$BUNDLED_CLAUDE_DIR/settings.json"

    if ! command -v claude >/dev/null 2>&1; then
        echo "  claude not on PATH — skipping plugin install"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1 || [[ ! -f "$settings" ]]; then
        echo "  jq or settings.json missing — skipping plugin install"
        return 0
    fi

    # This step hits the network (marketplace + plugin fetches) on EVERY
    # container start via postStartCommand. A 24h TTL keeps starts fast and
    # offline-tolerant; KOKKO_PLUGIN_REFRESH=1 forces a refresh now.
    local stamp="$CLAUDE_DIR/.plugin-bootstrap-stamp"
    if [[ "${KOKKO_PLUGIN_REFRESH:-}" != "1" && -f "$stamp" ]]; then
        local now mtime
        now=$(date +%s)
        mtime=$(stat -c %Y "$stamp" 2>/dev/null || echo 0)
        if (( now - mtime < 86400 )); then
            echo "  plugin roster refreshed less than 24h ago — skipping (KOKKO_PLUGIN_REFRESH=1 forces)"
            return 0
        fi
    fi

    local failed=0
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
            failed=1
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
            failed=1
        fi
    done < <(jq -r '
        (.enabledPlugins // {})
        | to_entries[]
        | select(.value == true)
        | .key' "$settings")

    # Stamp only a fully successful run: a partial failure (offline, expired
    # auth) must retry on the next start instead of hiding for 24h.
    if [[ "$failed" -eq 0 ]]; then
        touch "$stamp"
    fi
}

# Never expire the reflog or prune unreachable objects. The default 90/30-day
# windows quietly delete the very objects a recovery may depend on. With no
# guard layer in front of git any more, the reflog IS the recovery story --
# disk is cheaper than the work.
configure_git() {
    echo "=== Configuring git for recoverability ==="
    # Bind-mounted workspaces are owned by the HOST uid, not the container user.
    # Without safe.directory git refuses every command with "detected dubious
    # ownership". The workspace root is derived from this script's own location
    # (the parent of the .devcontainer dir), NOT from $PWD -- a --config-only
    # run invoked from some other directory would otherwise whitelist the wrong
    # path. Guard against re-adding on every run -- --add appends unconditionally.
    local workspace_root
    workspace_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    if git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$workspace_root"; then
        echo "  safe.directory already contains: $workspace_root"
    else
        git config --global --add safe.directory "$workspace_root"
        echo "  safe.directory: $workspace_root"
    fi
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
    local dotfiles_dir="$HOME/.dotfiles"
    local bundled_zsh_dir="$BUNDLED_CONFIG_DIR/zsh"
    if [[ -d "$dotfiles_dir/zsh" ]]; then
        mkdir -p "$HOME/.config"
        ln -sfn "$dotfiles_dir/zsh" "$HOME/.config/zsh"
    elif [[ -d "$bundled_zsh_dir" ]]; then
        mkdir -p "$HOME/.config"
        ln -sfn "$bundled_zsh_dir" "$HOME/.config/zsh"
    fi
    if [[ -f "$dotfiles_dir/.zshrc" ]]; then
        ln -sfn "$dotfiles_dir/.zshrc" "$HOME/.zshrc"
    elif [[ -f "$bundled_zsh_dir/.zshrc" ]]; then
        ln -sfn "$bundled_zsh_dir/.zshrc" "$HOME/.zshrc"
    fi
}

# =====================
# Python dependencies
# =====================
install_python_deps() {
    if [[ -f pyproject.toml ]]; then
        echo "=== Installing Python dependencies ==="
        step "uv-sync" uv sync
    else
        echo "=== Skipping Python dependencies (no pyproject.toml) ==="
    fi
}

# =====================
# Playwright Chromium
# =====================
# This is the PROJECT's playwright (a Python dependency), not the agent CLI
# gated by DEVCONTAINER_INSTALL_PLAYWRIGHT — a project that imports playwright
# needs its browsers regardless of whether the CLI was installed.
#
# `uv sync` above installs only the default dependency groups. A project can
# declare playwright in a non-default group (or not at all), in which case
# `uv run playwright` aborts with "Failed to spawn: playwright" and takes the
# whole postCreateCommand down with it. Probe the synced environment first.
install_playwright_browsers() {
    if [[ -f pyproject.toml ]] && uv run python -c "import playwright" >/dev/null 2>&1; then
        echo "=== Installing Playwright Chromium ==="
        step "playwright-chromium" uv run playwright install --with-deps chromium
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
    if [[ -d "$FRONTEND_DIR" ]]; then
        echo "=== Installing frontend dependencies ($FRONTEND_DIR) ==="
        # The directory name reaches the subshell as an argument, never
        # interpolated into the command string — a path with spaces or shell
        # metacharacters would otherwise be re-parsed by `bash -c`.
        # shellcheck disable=SC2016  # $1 must reach the inner shell unexpanded
        if [[ -f "$FRONTEND_DIR/package-lock.json" ]]; then
            step "frontend-deps" bash -c 'cd "$1" && npm ci --legacy-peer-deps' _ "$FRONTEND_DIR"
        else
            # `npm ci` hard-fails without a lockfile; fall back to install.
            echo "  no $FRONTEND_DIR/package-lock.json — using npm install instead of npm ci"
            step "frontend-deps" bash -c 'cd "$1" && npm install --legacy-peer-deps' _ "$FRONTEND_DIR"
        fi
    else
        echo "=== Skipping frontend dependencies (no $FRONTEND_DIR/ directory) ==="
    fi
}

# =====================
# Pre-commit hooks
# =====================
install_precommit_hooks() {
    if [[ -f .pre-commit-config.yaml ]]; then
        echo "=== Installing pre-commit hooks ==="
        # CLAUDE.md mandates pre-commit, so failures here must be visible —
        # no stderr suppression, and verify the hook actually landed.
        if ! uv run pre-commit install; then
            echo "  WARNING: 'uv run pre-commit install' failed."
        fi
        if [[ ! -f .git/hooks/pre-commit ]]; then
            echo "  WARNING: .git/hooks/pre-commit is missing — the pre-commit config is a"
            echo "           silent no-op. Install it before committing: uv run pre-commit install"
        fi
    else
        echo "=== Skipping pre-commit hooks (no config found) ==="
    fi
}

# =====================
# .env file
# =====================
create_env_file() {
    if [[ ! -f .env ]]; then
        # shellcheck disable=SC2015  # the || true is a deliberate never-fail
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
    retire_git_safety_layer
    merge_claude_settings
    bootstrap_claude_plugins || true
    configure_git
    link_shell_config
}

if [[ "$MODE" == "config" ]]; then
    echo "=== Refreshing bundled config (no rebuild) ==="
    fix_volume_ownership
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

# Full provision: start with a clean failure ledger for this run.
: > "$PROVISION_STATUS"

fix_volume_ownership
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
echo "  Frontend:  cd $FRONTEND_DIR && npm run dev"
echo "  Claude:    claude"
# An `if`, not an AND-list: under `set -e` a false AND-list would end the script.
if command -v az >/dev/null 2>&1; then echo "  Azure:     az account show"; fi
echo ""

provision_summary
check_vm_disk || true
