# devcontainer-starter

A portable development container for FastAPI + Vue projects, designed to run on macOS with Colima as the Docker runtime.

## What's included

| Tool | Purpose |
| ------ | --------- |
| Python 3.12 + uv | Backend runtime and dependency management |
| Node 20 | Frontend build tooling |
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

```text
.devcontainer/
├── devcontainer.json
├── Dockerfile
├── init-host-certs.sh
├── post-create.sh
└── config/
    ├── bin/
    │   └── snaps         # Browse/restore working-tree snapshots
    ├── zsh/              # Shell config (bundled into container)
    └── claude/           # Claude Code settings and CLAUDE.md
        ├── hooks/        # Safety-net verifier (see "Git safety" below)
        └── merge-hooks.jq
ghostty/
└── config                # Host-side Ghostty terminal config
.gitignore                # Ignores extracted host CA certs, secrets, build artifacts
GIT-SAFETY.md             # How the git safety net works
INSTRUCTIONS.md           # Full setup walkthrough
MANAGING.md               # Multi-instance management guide
README.md                 # This file
```

## Git safety

Coding agents rewrite git history as a routine step. When they do it over a dirty tree,
every uncommitted change to a tracked file is **destroyed silently and unrecoverably** —
that work was never a git object, so there is no reflog entry and `git fsck` will not find
it. This has cost real projects hours of work.

**Nothing here blocks a command.** There is no guard hook and no blocked-command list.
A blocklist has to enumerate every spelling of every dangerous command, which makes it both
too broad (the last one blocked `rm -rf ./dist` and `docker image prune -a`) and too narrow
(it never saw `git reset --hard` invoked from a script). What ships instead:

| Layer | What it does |
| --- | --- |
| **Snapshots** | Uncommitted tracked changes are checkpointed to `refs/snapshots/` before every git command and on every prompt. Run `snaps` to list, `snaps restore <ref>` to get work back. Recovery, not prevention. |
| **Briefing** | The bundled `CLAUDE.md` and a SessionStart hook both state the rules and say plainly that nothing will refuse a destructive command. |
| **Verifier** | Runs the real snapshot hook against a throwaway dirty repo at every session start and shouts if no snapshot appears — a snapshot hook that has stopped working is otherwise indistinguishable from a clean tree. |

Snapshots and the briefing ship in the
[kokko-safety](https://github.com/kokko-ng/kokko-cmds) plugin, which `post-create.sh`
installs. The verifier stays in this repo precisely so that a failed plugin install cannot
leave you unprotected without knowing it.

Untracked files are never snapshotted, so `git clean` has no recovery path at all.

Plus `gc.reflogExpire=never` and `gc.pruneExpire=never`, so git stops deleting the objects
recovery depends on.

```bash
snaps                 # list snapshots, newest first
snaps show <ref>      # what's in it
snaps restore <ref>   # put it back
```

See [GIT-SAFETY.md](GIT-SAFETY.md) for the design and for why there is no guard.

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
cp -r path/to/devcontainer-starter/.devcontainer .

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

The default roster is the `kokko-ng` plugins across
[kokko-cmds](https://github.com/kokko-ng/kokko-cmds) and
[kokko-janitor](https://github.com/kokko-ng/kokko-janitor). Edit `enabledPlugins` to change
it; a plugin set to `false` is never installed.

## Updating a running container

Bundled config changes — `CLAUDE.md`, `settings.json`, the git safety hooks, `snaps`, zsh
config, the plugin roster — can be re-applied in place, with no rebuild:

```bash
bash .devcontainer/post-create.sh --config-only
```

`/devcontainer-update` (from `kokko-env` in
[kokko-cmds](https://github.com/kokko-ng/kokko-cmds)) does the whole job: diff this
project's `.devcontainer/` against the latest upstream, update the files, run the refresh,
and report what still needs a rebuild. Dockerfile and `devcontainer.json`
`features`/`containerEnv`/`runArgs` changes always need one.

## Caveats

- The devcontainer assumes a **FastAPI + Vue** project layout (`src/` for Python, `ui/` for Vue). Adjust `PYTHONPATH` and the frontend install path if your layout differs.
- Shell config (zsh) and Claude Code settings are bundled in `.devcontainer/config/` — no host dotfiles are read.
- Optional mounts for `~/.azure` and `~/.claude` are commented out in `devcontainer.json`. Uncomment them to persist credentials and Claude state across rebuilds.

See [INSTRUCTIONS.md](INSTRUCTIONS.md) for a full setup walkthrough and [MANAGING.md](MANAGING.md) for running multiple instances.

## Development

```bash
bash scripts/test-merge-hooks.sh      # the settings.json merge program
bash scripts/check-plugin-roster.sh   # every enabled plugin resolves
bash scripts/check-docs.sh            # documentation matches the repo
shellcheck --severity=warning .devcontainer/*.sh .devcontainer/config/claude/hooks/*.sh
markdownlint '**/*.md'
```

CI runs all of the above on every push, plus a weekly `devcontainer build` to
catch upstream drift in the feature images. See [CHANGELOG.md](CHANGELOG.md).
