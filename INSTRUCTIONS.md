# Devcontainer Setup — Comprehensive Guide

A step-by-step guide to setting up a reproducible development environment on macOS using Ghostty, Colima, the devcontainer CLI, and VS Code Remote Containers.

This repo is a [cookiecutter](https://cookiecutter.readthedocs.io/) template: you generate a `.devcontainer/` for your project rather than copying and hand-editing one. [Generate your project](#generate-your-project) covers that step; everything before it is host setup you do once, and everything after it describes the container you end up with.

---

## Table of contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Install Homebrew](#install-homebrew)
4. [Install Ghostty](#install-ghostty)
5. [Install and configure Colima](#install-and-configure-colima)
6. [Install the devcontainer CLI](#install-the-devcontainer-cli)
7. [Generate your project](#generate-your-project)
8. [Using the devcontainer](#using-the-devcontainer)
9. [Devcontainer structure explained](#devcontainer-structure-explained)
10. [Bundled config](#bundled-config)
11. [Optional mounts](#optional-mounts)
12. [Caveats and known issues](#caveats-and-known-issues)
13. [Sign in to CLIs](#sign-in-to-clis)
14. [Regenerating and customising](#regenerating-and-customising)
15. [Customisation](#customisation)

---

## Overview

A **devcontainer** is a Docker container with a fully configured development environment defined in code. The specification is maintained at [containers.dev](https://containers.dev). When you open a project in VS Code with a `.devcontainer/` folder, VS Code offers to reopen the project inside the container, giving every contributor an identical environment regardless of their host machine.

On macOS, Docker requires a Linux VM. **Colima** is a lightweight, open-source alternative to Docker Desktop that runs a Lima-based VM with a Docker-compatible socket. It consumes significantly fewer resources and has no licence restrictions.

**Ghostty** is a fast, GPU-accelerated terminal emulator. It is used here as the host terminal for running Colima and devcontainer CLI commands.

---

## Prerequisites

| Requirement | Minimum version | Notes |
|-------------|----------------|-------|
| macOS | 13 Ventura | Apple Silicon or Intel |
| Homebrew | any | Package manager |
| Colima | 0.7+ | Docker runtime |
| Docker CLI | 25+ | Installed alongside Colima |
| devcontainer CLI | 0.65+ | Runs containers from the terminal |
| cookiecutter | 2.1+ | Generates your `.devcontainer/` from this template |
| Ghostty | 1.0+ | Terminal emulator |
| VS Code | 1.85+ | Optional — CLI-only workflow also documented |

---

## Install Homebrew

If you do not have Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the printed instructions to add Homebrew to your `PATH` (Apple Silicon Macs require an extra step).

Verify:

```bash
brew --version
```

---

## Install Ghostty

Ghostty is distributed as a macOS application via Homebrew Cask:

```bash
brew install --cask ghostty
```

Open Ghostty from your Applications folder or Spotlight. All subsequent terminal commands in this guide should be run in Ghostty.

### Apply the bundled config

This repo includes a Ghostty config at `ghostty/config`. To use it:

```bash
mkdir -p ~/.config/ghostty
cp ghostty/config ~/.config/ghostty/config
```

Or symlink it so changes in the repo are reflected immediately:

```bash
mkdir -p ~/.config/ghostty
ln -sfn "$(pwd)/ghostty/config" ~/.config/ghostty/config
```

Ghostty picks up config changes on restart.

---

## Install and configure Colima

Colima provides the Docker runtime (and optionally containerd). It replaces Docker Desktop.

### Install

```bash
brew install colima docker docker-compose
```

### Start Colima

```bash
colima start --cpu 8 --memory 16 --disk 150 --mount-type virtiofs
```

Adjust `--cpu` and `--memory` to suit your machine. 4 CPUs and 8 GB RAM is a workable baseline for a single FastAPI + Vue project with hot reload; 8 and 16 are comfortable if you run more than one container or build images.

**Do not give the VM more than about half your host RAM.** The allocation is reserved for the VM, not shared back with macOS, so `--memory 16` on a 16 GB machine leaves nothing for the host and pushes it into swap — which reads as the container being slow. On a 16 GB Mac use `--memory 8`; `--memory 16` assumes 32 GB or more.

**`--mount-type virtiofs` is the setting that matters most for speed.** It is already the default on `vmType: vz` in current Colima, so on a fresh install the flag is a no-op — pass it anyway to be explicit. The alternative, `sshfs`, is around 940x slower on small-file writes and makes `dce` unstable, not merely slow.

The flag applies **only when the VM is created**. If you already have a Colima VM, this flag will not change it and Colima will not warn you — check with `colima ssh -- mount | grep /Users` and see [Filesystem performance](MANAGING.md#filesystem-performance-mount-type) for the migration.

**Size `--disk` generously from the start.** Each devcontainer image built from this template is 5-6 GB, every rebuild leaves the previous image behind, and the `docker-in-docker` feature keeps a second, nested image store per container. A 60 GB disk fills up faster than expected, and a full disk takes the Docker daemon down in a way that is hard to diagnose (see [Disk management](MANAGING.md#disk-management)).

Disk is the one setting worth over-provisioning now: the image is sparse, so `--disk 150` only consumes host space as it actually fills, and while Colima can grow a disk later, it cannot shrink one.

### Auto-start at login

```bash
brew services start colima
```

### Verify Docker is working

```bash
docker info | head -5
```

You should see output referencing the Colima context. If Docker cannot connect, check that Colima is running and that its disk is not full:

```bash
colima status        # did the VM boot?
colima ssh -- df -h /   # is the disk full? colima status will NOT tell you
```

A healthy `colima status` is not proof that Docker works: the VM can be running normally while the daemon inside it is dead from a full disk. See [Disk management](MANAGING.md#disk-management).

### Docker socket path

Colima exposes its socket at `$HOME/.colima/default/docker.sock`. Most tools discover it automatically via the Docker context. If a tool requires an explicit `DOCKER_HOST`, set:

```bash
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
```

Add this to your shell profile (`~/.zshrc` or similar) if you need it persistently.

---

## Install the devcontainer CLI

The devcontainer CLI lets you build and enter containers without VS Code:

```bash
brew install devcontainer
```

Verify:

```bash
devcontainer --version
```

---

## Generate your project

```bash
brew install cookiecutter      # or: pipx install cookiecutter
cookiecutter gh:kokko-ng/kokko-devcontainer
```

**Where to run it:** generate (and keep) the project in a folder no cloud sync
service watches — `~/code` is a good home. `~/Documents` and `~/Desktop` are
iCloud-synced whenever "Desktop & Documents Folders" is on, and anything under
`~/Library/CloudStorage` (OneDrive, Dropbox, Google Drive) is always synced;
a synced folder fights the container and litters it with phantom `file 2.ext`
conflict copies (see MANAGING.md, "Cloud-synced folders").

Cookiecutter asks one question per option and writes a directory named after your
`project_slug`, containing `.devcontainer/` and a generated `DEVCONTAINER.md`. Press
Enter to accept any default.

| Prompt | Default | What it changes |
|---|---|---|
| `project_name` | `My Project` | Documentation headings |
| `project_slug` | derived from the name | Generated directory, container name, per-project volume names |
| `python_version` | `3.14` | Base image tag. Only `3.14` carries the digest pin; another version emits a tag-only `FROM` and tells you how to pin it |
| `node_version` | `22` | `node` feature version |
| `backend_src_dir` | `src` | `PYTHONPATH` |
| `frontend_dir` | `ui` | Where `post-create.sh` installs frontend dependencies |
| `backend_port` | `8000` | Forwarded port |
| `frontend_port` | `5173` | Forwarded port |
| `include_azure_cli` | `yes` | The `azure-cli` feature and the optional `~/.azure` mount hint |
| `include_azure_sql_driver` | `yes` | The `msodbcsql18` + `unixodbc-dev` apt layer (pyodbc / Azure SQL) |
| `include_docker_in_docker` | `yes` | The `docker-in-docker` feature and the Docker VS Code extension |
| `include_copilot_cli` | `yes` | Whether `post-create.sh` installs `@github/copilot` |
| `include_playwright` | `yes` | The Playwright CLI, its browser volume, and the Chromium-related `runArgs` |
| `claude_plugin_roster` | `kokko-ng` | `kokko-ng` ships all 10 plugins; `none` ships an empty roster |
| `cache_volume_scope` | `shared` | `shared` reuses one set of cache volumes across projects; `per-project` namespaces them by slug |

Answers are validated before anything is written. A slug that is not lowercase, a port
below 1024, two services on the same port, or a source directory that is absolute or
escapes the workspace all abort generation with an explanation and leave no directory
behind.

### Pinning a template version

```bash
cookiecutter gh:kokko-ng/kokko-devcontainer --checkout v3.0.0
```

Releases are tagged from the `VERSION` file, so `--checkout` pins a project to a
known-good template instead of tracking `main`.

### Adding it to an existing project

Cookiecutter always creates a new directory, so generate elsewhere and move the result
in:

```bash
cookiecutter gh:kokko-ng/kokko-devcontainer -o /tmp
cp -r /tmp/<your-project-slug>/.devcontainer ~/projects/your-project/
```

Give the prompts your project's real layout (`backend_src_dir`, `frontend_dir`, the
ports) so the generated config matches what is already on disk.

### Non-interactive generation

Every answer can be passed on the command line:

```bash
cookiecutter gh:kokko-ng/kokko-devcontainer --no-input \
  project_name="Acme API" backend_src_dir=app frontend_dir=frontend \
  include_azure_cli=no include_playwright=no
```

`cookiecutter --replay gh:kokko-ng/kokko-devcontainer` reuses the answers from your last
run — useful when regenerating after a template update.

---

## Using the devcontainer

### With VS Code

1. Install the **Dev Containers** extension (`ms-vscode-remote.remote-containers`).
2. Open your project folder.
3. VS Code will detect `.devcontainer/devcontainer.json` and show a notification — click **Reopen in Container**.
4. The first build pulls the base image and runs `post-create.sh`. Subsequent opens reuse the cached image.

### With the devcontainer CLI (no VS Code)

Build and start the container:

```bash
devcontainer up --workspace-folder .
```

Open a shell inside the running container:

```bash
devcontainer exec --workspace-folder . zsh
```

Run a one-off command:

```bash
devcontainer exec --workspace-folder . -- uv run pytest
```

Rebuild from scratch (clears the image cache):

```bash
devcontainer up --workspace-folder . --remove-existing-container
```

---

## Devcontainer structure explained

This is what cookiecutter writes into your project.

```
DEVCONTAINER.md         # Generated summary of what you chose and how to change it
.devcontainer/
├── devcontainer.json   # Container definition and VS Code settings
├── Dockerfile          # Base image and system-level dependencies
├── init-host-certs.sh  # Extracts host CA certs (runs before build)
├── post-create.sh      # Runs once after the container is created
├── .gitignore          # Keeps the extracted host CA certs out of git
├── certs/              # Host CA certs extracted by init-host-certs.sh
│                       # (gitignored except .gitkeep)
└── config/
    ├── zsh/              # Bundled shell config (symlinked by post-create.sh)
    └── claude/           # Bundled Claude Code settings and CLAUDE.md
        ├── merge-settings.jq  # Merges bundled settings into an existing settings.json
        └── prune-roster.jq    # Prunes roster entries the bundle no longer ships
```

The `.gitignore` lives inside `.devcontainer/` on purpose: the rule that keeps real host
CA certificates out of git travels with the directory when you copy it into another
project, instead of being something you have to remember to add to a project's root
`.gitignore`.

### Dockerfile

Abridged for readability — comments are condensed and some flags omitted. `.devcontainer/Dockerfile` is the source of truth.

```dockerfile
# Pinned by digest for reproducibility; Dependabot proposes digest bumps
FROM mcr.microsoft.com/devcontainers/python:3.14-bookworm@sha256:...

RUN pip install --no-cache-dir uv==<pinned>

# ODBC Driver 18 for SQL Server (required by pyodbc for Azure SQL),
# jq (required by post-create.sh's settings pipeline), fzf + fd-find for the shell config.
# The Debian release for the MS repo comes from /etc/os-release, so a base
# image bump cannot leave it pointing at the wrong codename.
RUN . /etc/os-release \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/${VERSION_ID}/prod ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc-dev jq fzf fd-find \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Symlink so macOS absolute paths in Claude plugin configs resolve.
# HOST_USER is injected by devcontainer.json (build.args) as ${localEnv:USER}
# so the symlink matches your macOS username automatically.
ARG HOST_USER=vscode
RUN mkdir -p /Users && ln -sfn /home/vscode /Users/${HOST_USER}

# Trust host CA certificates (corporate proxies, etc.)
COPY certs/ /usr/local/share/ca-certificates/host/
RUN update-ca-certificates
```

The base image (`mcr.microsoft.com/devcontainers/python`) is maintained by Microsoft and includes git, curl, the `vscode` user, and oh-my-zsh. Key layers:

- **uv** is the Python package manager used instead of pip/Poetry.
- **ODBC Driver 18** is required by pyodbc for Azure SQL connectivity. Remove this block if you do not use Azure SQL.
- **Chromium** and its system dependencies are installed by `post-create.sh` via `playwright-cli install-browser --with-deps` (the [Playwright CLI](https://playwright.dev/agent-cli/installation)), which provides browser automation capabilities to coding agents.
- **`HOST_USER` ARG** creates a `/Users/<username>` symlink to `/home/vscode` so that macOS absolute paths embedded in Claude plugin configs (e.g. `/Users/<your-mac-user>/.claude/...`) resolve inside the container. The value is auto-injected by `devcontainer.json` from `${localEnv:USER}`, so it matches your host username automatically — no manual edit needed when forking.
- **Host CA certificates** are copied from `certs/` (populated by `init-host-certs.sh` at build time) so that corporate proxy CAs are trusted without disabling SSL verification.

Additional tools (Node, Azure CLI, GitHub CLI, Docker-in-Docker, zsh) are added via **devcontainer features** in `devcontainer.json` rather than the Dockerfile. Features are composable, versioned, and reusable across projects.

### devcontainer.json

Key sections:

| Section | Purpose |
|---------|---------|
| `build` | Points to the Dockerfile |
| `features` | Installs composable tooling layers |
| `containerEnv` | Environment variables set inside the container |
| `initializeCommand` | Runs on the host before build (extracts CA certs) |
| `postCreateCommand` | Script run once after first build |
| `forwardPorts` | Ports exposed from the container to the host |
| `runArgs` | Docker run flags — defaults raise the PID limit to 1024 (needed by Chromium/Playwright). Aggressive container hardening (cap drops, `no-new-privileges`) is intentionally not enabled because it breaks `sudo`, which devcontainer features and many post-create flows rely on. |
| `customizations.vscode` | Extensions and settings applied when opening in VS Code |

`PYTHONPATH` is set to `${containerWorkspaceFolder}/<backend_src_dir>` — `src` unless you answered otherwise — which resolves at runtime to `/workspaces/<your-repo-name>/src`. Edit it in `containerEnv` if your layout changes later.

The `DEVCONTAINER_*` entries in `containerEnv` are the provisioning answers you gave the template, published to the container so `post-create.sh` can read them: `DEVCONTAINER_INSTALL_COPILOT_CLI`, `DEVCONTAINER_INSTALL_PLAYWRIGHT`, and `DEVCONTAINER_FRONTEND_DIR`. Flipping one and rebuilding changes what gets installed without regenerating from the template.

### post-create.sh

Runs once after the container is first created. Steps are idempotent so a rebuild does not fail on already-installed components. It:

1. Installs zsh plugins (autosuggestions, syntax highlighting), pinned to release tags. Skips if already cloned.
2. Installs Claude Code via the native binary installer (`~/.local/bin/claude`). Normally a no-op: the Dockerfile bakes the binary into the image, and this step only fires as a fallback for images built before that layer existed.
3. Installs GitHub Copilot CLI via `npm install -g @github/copilot`, unless `DEVCONTAINER_INSTALL_COPILOT_CLI` is `0`. Skips if `copilot` is already on `PATH`. Uses the user-writable npm prefix set up by the Node feature, so no sudo is required.
4. Installs the [Playwright CLI](https://playwright.dev/agent-cli/installation) via `npm install -g @playwright/cli@<pinned>` (skipped entirely when `DEVCONTAINER_INSTALL_PLAYWRIGHT` is `0`), installs its Chromium browser (`playwright-cli install-browser --with-deps`), and installs agent skills (`playwright-cli install --skills`). The browsers live in the `pw-browsers` named volume (`PLAYWRIGHT_BROWSERS_PATH`), so the download is skipped on every rebuild after the first.
5. Copies bundled Claude config (`config/claude/settings.json` and `CLAUDE.md`) to `~/.claude/`. `settings.json` is only copied when absent (the merge in step 6 keeps it current); `CLAUDE.md` is refreshed from the bundle whenever the live copy is still byte-identical to what a previous run installed (hash-tracked via `~/.claude/.claude-md.bundled-sha256`) — a user-edited copy is left alone with a notice.
6. Removes any leftovers of the retired git safety layer (the guard/snapshot hooks and the `snaps` helper installed by older versions of this template), then merges the bundled settings and plugin roster into the live `settings.json` (`merge-settings.jq` — user-set values always win, and the retired hook wiring is stripped). After the merge, plugins that were *removed* from the bundled roster are pruned from the live settings — unless you overrode their value, in which case your setting wins (`prune-roster.jq`, driven by the `~/.claude/.kokko-bundled-roster.json` snapshot).
7. Installs the Claude Code plugins. Every marketplace in `extraKnownMarketplaces` is registered and every plugin set to `true` in `enabledPlugins` is installed, both read from the **merged** `~/.claude/settings.json` (falling back to the bundle on a first run) — so a plugin you disabled locally is not reinstalled. `enabledPlugins` alone only *enables* a plugin, so without this step a fresh container starts with none of them on disk. Warns and continues on failure — it needs network and a signed-in CLI. Network calls are skipped when the last successful run is under 24h old; `KOKKO_PLUGIN_REFRESH=1` forces a refresh and `KOKKO_SKIP_PLUGINS=1` (used by CI) skips the step entirely.
8. Configures git for recoverability (`safe.directory`, reflog and prune retention, `rerere`).
9. Symlinks bundled zsh config (`config/zsh/`) to `~/.config/zsh` and `~/.zshrc` (prefers dotfiles from `~/.dotfiles` if present).
10. Runs `uv sync` if `pyproject.toml` exists.
11. Installs Playwright Chromium (Python package) if `pyproject.toml` exists **and**
    `uv run python -c "import playwright"` succeeds in the synced environment — a
    `pyproject.toml` that does not actually pull in playwright is skipped.
12. Runs `npm ci --legacy-peer-deps` in `$DEVCONTAINER_FRONTEND_DIR` (`ui/` by default)
    if that directory exists (falls back to `npm install --legacy-peer-deps` when its
    `package-lock.json` is missing, since `npm ci` hard-fails without a lockfile).
13. Installs pre-commit hooks if `.pre-commit-config.yaml` exists, and warns if
    `.git/hooks/pre-commit` is still missing afterwards.
14. Copies `.env.example` to `.env` if no `.env` exists.

Network install steps retry 3 times with backoff; a step that still fails is recorded in
`~/.devcontainer-provision-status` and summarized at the end instead of aborting the
build. Re-run `bash .devcontainer/post-create.sh` after fixing connectivity.

The bundled-config paths are resolved relative to the post-create script itself, so the workspace folder can be named anything.

The script contains no template syntax: every option it needs arrives as an environment variable. That is deliberate — it stays shellcheck-clean, readable, and editable in a generated project without a round-trip through cookiecutter.

#### Refreshing config without a rebuild

Steps 5 to 9 are the bundled config, and they can be re-applied to a container that is already running:

```bash
bash .devcontainer/post-create.sh --config-only
```

That skips every tool install and every project dependency step, so it takes seconds. Use it after pulling newer `.devcontainer/config/` files, or after adding a plugin to the roster.

The `/devcontainer-update` command in [kokko-ng/kokko-cmds](https://github.com/kokko-ng/kokko-cmds) wraps the whole flow: it diffs this project's `.devcontainer/` against the latest upstream, updates the files, runs the refresh, and reports what still needs a rebuild.

What `--config-only` **cannot** apply: the `Dockerfile`, the `features` / `containerEnv` / `runArgs` / `mounts` blocks of `devcontainer.json`, and `init-host-certs.sh` (which runs on the host). Those still need `devcontainer up --remove-existing-container`.

---

## Bundled config

Shell and Claude Code configuration is bundled inside the devcontainer so no host files are read. The structure:

```
.devcontainer/config/
├── zsh/
│   ├── .zshrc           # Entry point — sources integrations and aliases
│   ├── integrations.zsh # oh-my-zsh, fzf, Ghostty shell integration
│   └── aliases.zsh      # Aliases for Claude, devcontainer, etc.
└── claude/
    ├── CLAUDE.md         # Global Claude Code instructions
    └── settings.json     # Claude Code preferences
```

`post-create.sh` symlinks `config/zsh/` into `~/.config/zsh` and `~/.zshrc`, so edits to the bundled files take effect after reopening the shell.

### Aliases

| Alias | Command | Purpose |
|-------|---------|---------|
| `cca` | `claude --permission-mode auto` | Claude in Auto mode (built-in classifier approves safe tool calls) |
| `ccac` | `claude --permission-mode auto --continue` | Claude in Auto mode, continuing last session |
| `cu` | `curl -fsSL https://claude.ai/install.sh \| bash` | Update Claude Code to latest |
| `caat` | `copilot --allow-all-tools --banner` | GitHub Copilot CLI with all tools |
| `azw` | `az account show --query "{user:user.name, subscription:name, tenant:tenantId}" -o table` | Which Azure account, subscription and tenant am I on |
| `ghw` | `gh auth status` | Which GitHub account the CLI is authenticated as |
| `dce` | `devcontainer exec --workspace-folder . zsh` | Open a shell in the running container |
| `dcu` | `devcontainer up --workspace-folder .` | Start the devcontainer |
| `dcur` | `devcontainer up --workspace-folder . --remove-existing-container` | Rebuild the container from scratch |

---

## Optional mounts

The devcontainer does not mount any host directories by default, making it fully portable. You can opt in to mounts by editing `devcontainer.json`:

```jsonc
"mounts": [
  // Persist Azure CLI login across rebuilds
  "source=${localEnv:HOME}/.azure,target=/home/vscode/.azure,type=bind",

  // Persist Claude Code conversation history and plugin configuration
  "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind"
]
```

After adding mounts, rebuild the container for them to take effect.

---

## Caveats and known issues

### Claude Code native installer

Claude Code is installed via Anthropic's native binary installer:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

This produces a standalone binary at `~/.local/bin/claude` with a built-in auto-updater. Node.js is not required to run it. The `cu` alias re-runs the installer to update to the latest version.

### Assumed project layout (FastAPI + Vue)

The devcontainer makes two layout assumptions:

| Assumption | Where to change |
|-----------|----------------|
| Python source lives in `src/` | `PYTHONPATH` in `devcontainer.json` |
| Vue/Vite frontend lives in `ui/` | `cd ui` in `post-create.sh` |

If your project uses a different layout, update these two locations before building.

### `devcontainer up` fails with "Command failed: docker ps"

Docker is not reachable. Usually Colima is simply not running — start it:

```bash
colima start --cpu 8 --memory 16 --disk 150
```

Then retry `devcontainer up`. You can verify Docker is available with:

```bash
docker ps
```

To avoid this on every login, enable Colima as a background service:

```bash
brew services start colima
```

**If Colima says it is already running and Docker still does not work**, do not stop here assuming the VM is fine — the most likely cause is that the VM's disk is full. Check the disk before anything else:

```bash
colima ssh -- df -h /
```

At 100% the Docker daemon is dead even though the VM booted normally, so `colima status` still looks healthy and `colima start` answers `already running, ignoring`. See [Disk management](MANAGING.md#disk-management) for the full symptom list and recovery steps.

### Colima socket path in CI or other tools

Some tools (BuildKit, Testcontainers, etc.) look for the Docker socket at `/var/run/docker.sock`. Colima does not create this symlink by default. You can add one:

```bash
sudo ln -sf $HOME/.colima/default/docker.sock /var/run/docker.sock
```

Or use the `DOCKER_HOST` environment variable as described in the [Colima section](#install-and-configure-colima).

### Docker-in-Docker vs Docker-outside-of-Docker

The devcontainer uses the **Docker-in-Docker** feature, which runs a separate Docker daemon inside the container. This is the safest isolation model: the container cannot touch the host's daemon, and images built inside it are not shared with the host's Docker cache.

**Know where its storage actually goes.** The nested daemon's images live in a **named volume** (`dind-var-lib-docker-*`), one per container. That volume:

- **survives container removal** — rebuilding with `dcur` does *not* reclaim it
- is **not counted by `docker system df`**, which reports only the outer daemon
- is **not reclaimed by `docker image prune`** on the host

So it grows unnoticed until the Colima VM's disk fills, which takes Docker down in a way that is hard to diagnose. This is a real cost, not a theoretical one — but it is manageable if you know it is there. See [Disk management](MANAGING.md#disk-management).

Keeping it in check:

```bash
# INSIDE the devcontainer -- clears the nested store
docker system prune -a

# ON THE HOST -- how big has a nested store become?
docker system df -v | grep dind-var-lib-docker
```

When you retire a project for good, remove the container *and then* its volume by name — removing the container alone leaves the volume behind:

```bash
docker rm <container>
docker volume rm dind-var-lib-docker-<hash>
```

**Alternative: share the host's Docker socket** (Docker-outside-of-Docker). Containers you start become siblings on the Colima daemon rather than nested, so there is no second image store and no hidden volume — images share the host cache and prune normally. The trade-off is weaker isolation: the container gets full control of the host's Docker daemon.

```jsonc
"mounts": [
  "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
]
```

Note that Colima does not create `/var/run/docker.sock` on the host by default; see [Colima socket path](#colima-socket-path-in-ci-or-other-tools) for the symlink.

### Claude Code (and other CLI) colors look wrong — orange renders as maroon

`devcontainer exec` / `docker exec` do not forward the host terminal's environment: inside the container `COLORTERM` is unset and `TERM` is plain `xterm`. Chalk-based CLIs such as Claude Code read those variables to pick a color depth, fall back to 16-color mode, and downsample their true-color UI to the nearest ANSI color — Claude Code's orange becomes ANSI red, which the bundled Ghostty palette (`palette = 1=#590008`) renders as dark maroon.

Two layers fix this:

- `containerEnv` in `devcontainer.json` sets `COLORTERM=truecolor` container-wide.
- The bundled zsh config (`integrations.zsh`) re-exports `COLORTERM` if missing and normalizes `TERM` to `xterm-256color` when it is plain `xterm` or has no terminfo entry in the container.

If colors are still wrong, the container likely predates these settings — rebuild it (`dcur`), then verify inside the container:

```bash
echo "$TERM $COLORTERM"        # expect: xterm-256color truecolor
printf '\e[38;2;217;119;87mtruecolor test\e[0m\n'   # should print in orange
```

### First build time

The initial `devcontainer up` downloads the base image (~1 GB) and runs `post-create.sh`. On a fast connection, expect 3–8 minutes. Subsequent starts from the cached image take a few seconds.

### Apple Silicon compatibility

All images referenced here (`mcr.microsoft.com/devcontainers/python`, devcontainer features) publish `linux/arm64` variants. Colima defaults to the native architecture, so no emulation is required on Apple Silicon.

### The container is very slow, and `dce` keeps dying

Almost always the Colima VM's mount type. Check the ground truth:

```bash
colima ssh -- mount | grep /Users
```

`type fuse.sshfs` is the slow path — around 940x slower than `virtiofs` on small-file writes, enough that `uv sync`, `pytest` and even `git status` crawl, and that Docker's exec sessions time out mid-command and drop you back to the host. `type virtiofs` is what you want.

An existing VM keeps the mount type it was created with, forever, no matter how many times you upgrade Colima or rebuild the container — and `colima start --mount-type virtiofs` will **not** change it, silently. See [Filesystem performance](MANAGING.md#filesystem-performance-mount-type) for the migration, which keeps all your images and containers.

If the mount is already `virtiofs`, check the VM disk (`colima ssh -- df -h /`) — a full disk kills the daemon and exits every container with status 255.

---

## Sign in to CLIs

After entering the container for the first time, authenticate the following CLIs:

### Git identity

Configure your git author identity so commits are attributed correctly:

```bash
git config --global user.name "$(gh api user --jq .name)"
git config --global user.email "$(gh api user/emails --jq '.[] | select(.primary) | .email')"
```

(`gh api user --jq .email` returns the literal string `null` when your email is set to
private on GitHub — the `user/emails` endpoint always has the real primary address.)

This pulls your name and email from your authenticated GitHub account. Verify with:

```bash
git config --global --get user.name
git config --global --get user.email
```

### GitHub CLI

```bash
gh auth login
```

Follow the interactive prompts. Choose **GitHub.com**, **HTTPS**, and authenticate via browser. This also enables `git push/pull` over HTTPS with your GitHub credentials.

### Azure CLI

```bash
az login
```

A browser window opens for Microsoft authentication. Follow the prompts to complete sign-in.

### Claude Code

```bash
claude
```

On first launch Claude Code prompts you to authenticate. Follow the instructions to sign in via browser. Subsequent launches reuse the stored session.

---

## Regenerating and customising

No host-specific edits are ever required — `HOST_USER` is auto-injected from
`${localEnv:USER}` and bundled config paths are resolved relative to the script, so the
workspace folder can be named anything.

Most of what you would once have hand-edited is now a prompt (see
[Generate your project](#generate-your-project)). Two ways to change your mind afterwards:

**Regenerate.** Re-run cookiecutter with different answers and copy the new
`.devcontainer/` over the old one. `cookiecutter --replay gh:kokko-ng/kokko-devcontainer`
starts from your previous answers, so you only change the one that moved. This is the
cleaner route when several options change at once.

**Edit in place.** Everything the prompts control is a plain setting in the generated
files:

| What to change | Where | Applies after |
|---|---|---|
| Copilot CLI on/off | `DEVCONTAINER_INSTALL_COPILOT_CLI` in `devcontainer.json` -> `containerEnv` | Rebuild |
| Playwright CLI on/off | `DEVCONTAINER_INSTALL_PLAYWRIGHT` in `containerEnv` | Rebuild |
| Frontend directory | `DEVCONTAINER_FRONTEND_DIR` in `containerEnv` | Rebuild |
| Python source path | `PYTHONPATH` in `containerEnv` | Rebuild |
| Forwarded ports | `forwardPorts` in `devcontainer.json` | Rebuild |
| Container display name | `name` in `devcontainer.json` | Rebuild |
| Azure CLI, Docker-in-Docker, Node version | `features` in `devcontainer.json` | Rebuild |
| ODBC driver, base image, uv version | `Dockerfile` | Rebuild |
| Cache volume names | `mounts` in `devcontainer.json` | Rebuild |
| Claude Code plugins | `enabledPlugins` / `extraKnownMarketplaces` in `.devcontainer/config/claude/settings.json` | `post-create.sh --config-only` |
| Global Claude instructions | `.devcontainer/config/claude/CLAUDE.md` | `post-create.sh --config-only` |
| Shell aliases and integrations | `.devcontainer/config/zsh/` | New shell |

Rebuild with `devcontainer up --workspace-folder . --remove-existing-container`; the
config-only refresh is `bash .devcontainer/post-create.sh --config-only`.

The provisioning toggles are environment variables rather than template conditionals on
purpose: `post-create.sh` contains no Jinja, so it stays readable, shellcheck-clean, and
editable in a generated project without a template round-trip.


---

## Customisation

### Adding Python packages

Add packages to `pyproject.toml` and run `uv sync` (or let the next container build handle it).

### Adding npm packages

Add packages to `ui/package.json` and run `npm install` inside the `ui/` directory.

### Adding VS Code extensions

Add extension IDs to the `customizations.vscode.extensions` array in `devcontainer.json` and rebuild the container.

### Changing the Python version

Update the base image tag in `Dockerfile`:

```dockerfile
FROM mcr.microsoft.com/devcontainers/python:3.13-bookworm
```

Available tags: [mcr.microsoft.com/devcontainers/python](https://mcr.microsoft.com/v2/devcontainers/python/tags/list).

### Changing the Node version

Update the `version` in the Node feature (the default is `22`):

```jsonc
"ghcr.io/devcontainers/features/node:2": {
  "version": "24"
}
```

### Persisting shell customisations

Shell config is bundled in `.devcontainer/config/zsh/` and symlinked into the container by `post-create.sh`. Edits to those files take effect after reopening the shell and persist across container restarts (but not full rebuilds, since the files live in the workspace).

To add permanent aliases or settings, edit `.devcontainer/config/zsh/aliases.zsh` or `integrations.zsh` directly — changes are committed to the repo and applied on the next rebuild.
