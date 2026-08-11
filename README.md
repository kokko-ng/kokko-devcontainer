# kokko-devcontainer

A portable development container for FastAPI + Vue projects, designed to run on macOS with Colima as the Docker runtime.

## What's included

| Tool | Purpose |
|------|---------|
| Python 3.12 + uv | Backend runtime and dependency management |
| Node 22 | Frontend build tooling |
| Azure CLI | Azure resource management |
| ODBC Driver 18 (msodbcsql18) | Azure SQL connectivity via pyodbc |
| GitHub CLI | Repository and PR workflows |
| Claude Code | AI coding assistant (native binary via `claude.ai/install.sh`), with the `kokko-ng` plugin roster installed automatically |
| GitHub Copilot CLI | `copilot` binary, installed via `npm i -g @github/copilot` |
| zsh + oh-my-zsh | Shell with autosuggestions and syntax highlighting |
| Playwright CLI + Chromium | Browser automation for coding agents (`playwright-cli`) |
| Docker-in-Docker | Container builds inside the devcontainer |

Docker-in-Docker keeps its own image store in a volume that grows unnoticed — `docker system df` does not count it. Prune it periodically from inside the container; see [Disk management](MANAGING.md#disk-management).

Ports `8000` (FastAPI) and `5173` (Vite) are forwarded automatically when opened in VS Code.

The container is portable — `HOST_USER` is auto-injected from your macOS username, and bundled config paths are resolved relative to the script, so the workspace can be named anything.

## Repo structure

```
.devcontainer/
├── devcontainer.json
├── Dockerfile
├── init-host-certs.sh
├── post-create.sh
└── config/
    ├── zsh/              # Shell config (bundled into container)
    └── claude/           # Claude Code settings and CLAUDE.md
        ├── merge-settings.jq  # Merges bundled settings into a live settings.json
        └── prune-roster.jq    # Removes roster entries the bundle dropped
ghostty/
└── config                # Host-side Ghostty terminal config
tests/
└── merge-settings-tests.sh   # Regression tests for the settings pipeline (run in CI)
.github/                  # CI workflow (pre-commit, tests, shellcheck, actionlint,
                          # hadolint, build, gitleaks) + release workflow
.gitignore                # Ignores extracted host CA certs, secrets, build artifacts
VERSION                   # Drives the v<version> tag published by release.yml
CLAUDE.md                 # For agents working ON this repo (tests, layout, rules)
CONTRIBUTING.md           # Test command, pre-commit setup, release flow
INSTRUCTIONS.md           # Full setup walkthrough
MANAGING.md               # Multi-instance management guide
README.md                 # This file
```

## Permission model

Claude Code runs in **Auto mode** (`permissions.defaultMode: "auto"` in the bundled
settings.json, and the `ccc` alias): Claude Code's built-in classifier decides which
tool calls are safe to run without a prompt. There is no bespoke hook layer in front of
git — the guard/snapshot hooks and the `snaps` CLI that earlier versions shipped are
retired, and `post-create.sh` removes their leftovers from containers that still carry
them.

Git recoverability rests on git itself: `gc.reflogExpire`, `gc.reflogExpireUnreachable`
and `gc.pruneExpire` are set to `never`, so committed work is always recoverable from
the reflog.

## Quick start

```bash
# 1. Install prerequisites (see INSTRUCTIONS.md for detail)
brew install colima devcontainer
brew install --cask ghostty

# 2. Start Colima
# --disk is generous on purpose: devcontainer images are 5-6GB each and
# Colima can grow a disk but never shrink it. See MANAGING.md.
colima start --cpu 8 --memory 16 --disk 150

# 3. Clone this repo into your project and open it
cd your-project
cp -r path/to/kokko-devcontainer/.devcontainer .

# 4. Open with VS Code
code .
# Accept the "Reopen in Container" prompt

# — or — use the CLI
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```

## Claude Code plugins

`post-create.sh` registers the marketplaces in `extraKnownMarketplaces` and installs every
plugin set to `true` in `enabledPlugins`, both read from
`.devcontainer/config/claude/settings.json`. `enabledPlugins` on its own only *enables* a
plugin that is already installed, so without this step a fresh container comes up with an
empty plugin directory.

The default roster is all 10 `kokko-ng` plugins across
[kokko-cmds](https://github.com/kokko-ng/kokko-cmds) and
[kokko-janitor](https://github.com/kokko-ng/kokko-janitor). Edit `enabledPlugins` to change
it; a plugin set to `false` is never installed.

The bootstrap reads the **merged** `~/.claude/settings.json`, so a plugin you disable
locally stays disabled. Its network calls run at most once per 24 hours (stamp:
`~/.claude/.plugin-bootstrap-stamp`); two environment variables control it:

| Variable | Effect |
|---|---|
| `KOKKO_PLUGIN_REFRESH=1` | Force a marketplace/plugin refresh now, ignoring the 24h stamp |
| `KOKKO_SKIP_PLUGINS=1` | Skip the plugin bootstrap entirely (used by CI) |

## Updating a running container

Bundled config changes — `CLAUDE.md`, `settings.json`, zsh config, the plugin roster —
can be re-applied in place, with no rebuild:

```bash
bash .devcontainer/post-create.sh --config-only
```

`/devcontainer-update` (from `kokko-env` in
[kokko-cmds](https://github.com/kokko-ng/kokko-cmds)) does the whole job: diff this
project's `.devcontainer/` against the latest upstream, update the files, run the refresh,
and report what still needs a rebuild.

Releases are tagged: the `VERSION` file at the repo root drives a `v<version>` tag and
GitHub release, published automatically once CI passes on `main`. That means
`/devcontainer-update --ref v1.0.0` can pin a project to a known-good version instead of
tracking `main`. Dockerfile and `devcontainer.json`
`features`/`containerEnv`/`runArgs` changes always need one.

## Caveats

- The devcontainer assumes a **FastAPI + Vue** project layout (`src/` for Python, `ui/` for Vue). Adjust `PYTHONPATH` and the frontend install path if your layout differs.
- Shell config (zsh) and Claude Code settings are bundled in `.devcontainer/config/` — no host dotfiles are read.
- Optional mounts for `~/.azure` and `~/.claude` are commented out in `devcontainer.json`. Uncomment them to persist credentials and Claude state across rebuilds.

See [INSTRUCTIONS.md](INSTRUCTIONS.md) for a full setup walkthrough and [MANAGING.md](MANAGING.md) for running multiple instances.
