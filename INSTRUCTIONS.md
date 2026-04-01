# Devcontainer Setup — Comprehensive Guide

A step-by-step guide to setting up a reproducible development environment on macOS using Ghostty, Colima, the devcontainer CLI, and VS Code Remote Containers.

---

## Table of contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Install Homebrew](#install-homebrew)
4. [Install Ghostty](#install-ghostty)
5. [Install and configure Colima](#install-and-configure-colima)
6. [Install the devcontainer CLI](#install-the-devcontainer-cli)
7. [Using the devcontainer](#using-the-devcontainer)
8. [Devcontainer structure explained](#devcontainer-structure-explained)
9. [Bundled config](#bundled-config)
10. [Optional mounts](#optional-mounts)
11. [Caveats and known issues](#caveats-and-known-issues)
12. [Customisation](#customisation)

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

Ghostty stores its configuration at `~/.config/ghostty/config`. A minimal example:

```
font-family = "JetBrains Mono"
font-size = 14
theme = dark
```

---

## Install and configure Colima

Colima provides the Docker runtime (and optionally containerd). It replaces Docker Desktop.

### Install

```bash
brew install colima docker docker-compose
```

### Start Colima

```bash
colima start --cpu 4 --memory 8 --disk 60
```

Adjust `--cpu` and `--memory` to suit your machine. 4 CPUs and 8 GB RAM is a reasonable baseline for a FastAPI + Vue project with hot reload.

### Auto-start at login

```bash
brew services start colima
```

### Verify Docker is working

```bash
docker info | head -5
```

You should see output referencing the Colima context. If Docker cannot connect, check that Colima is running:

```bash
colima status
```

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
npm install -g @devcontainers/cli
```

Or, if you prefer to avoid a global npm install, use `npx` on each invocation:

```bash
npx @devcontainers/cli up --workspace-folder .
```

Verify:

```bash
devcontainer --version
```

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

```
.devcontainer/
├── devcontainer.json   # Container definition and VS Code settings
├── Dockerfile          # Base image and system-level dependencies
└── post-create.sh      # Runs once after the container is created
```

### Dockerfile

```dockerfile
FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

RUN pip install --no-cache-dir uv
```

The base image (`mcr.microsoft.com/devcontainers/python`) is maintained by Microsoft and includes git, curl, the `vscode` user, and oh-my-zsh. `uv` is the Python package manager used instead of pip/Poetry.

Additional tools (Node, Azure CLI, GitHub CLI, Docker-in-Docker, zsh) are added via **devcontainer features** in `devcontainer.json` rather than the Dockerfile. Features are composable, versioned, and reusable across projects.

### devcontainer.json

Key sections:

| Section | Purpose |
|---------|---------|
| `build` | Points to the Dockerfile |
| `features` | Installs composable tooling layers |
| `containerEnv` | Environment variables set inside the container |
| `postCreateCommand` | Script run once after first build |
| `forwardPorts` | Ports exposed from the container to the host |
| `runArgs` | Docker run flags — the defaults drop all capabilities except `NET_BIND_SERVICE` for a hardened container |
| `customizations.vscode` | Extensions and settings applied when opening in VS Code |

`PYTHONPATH` is set to `${containerWorkspaceFolder}/src`, which resolves at runtime to `/workspaces/<your-repo-name>/src`. Adjust this if your project's source layout differs.

### post-create.sh

Runs once after the container is first created. It:

1. Installs zsh plugins (autosuggestions, syntax highlighting).
2. Symlinks bundled zsh config (`config/zsh/`) to `~/.config/zsh` and `~/.zshrc`.
3. Installs Claude Code via the native binary installer (`curl -fsSL https://claude.ai/install.sh | bash`).
4. Copies bundled Claude config (`config/claude/`) to `~/.claude/`.
6. Runs `uv sync` to install Python dependencies from `pyproject.toml`.
7. Runs `npm ci` in `src/frontend` to install frontend dependencies.
8. Installs pre-commit hooks.
9. Copies `.env.example` to `.env` if no `.env` exists.

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
| `ccc` | `claude --permission-mode bypassPermissions` | Claude without permission prompts |
| `cccc` | `claude --permission-mode bypassPermissions --continue` | Claude, continuing last session |
| `cu` | `curl -fsSL https://claude.ai/install.sh \| bash` | Update Claude Code to latest |

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
| Vue/Vite frontend lives in `src/frontend/` | `cd src/frontend` in `post-create.sh` |

If your project uses a different layout, update these two locations before building.

### Colima socket path in CI or other tools

Some tools (BuildKit, Testcontainers, etc.) look for the Docker socket at `/var/run/docker.sock`. Colima does not create this symlink by default. You can add one:

```bash
sudo ln -sf $HOME/.colima/default/docker.sock /var/run/docker.sock
```

Or use the `DOCKER_HOST` environment variable as described in the [Colima section](#install-and-configure-colima).

### Docker-in-Docker vs Docker-outside-of-Docker

The devcontainer uses the **Docker-in-Docker** feature, which runs a separate Docker daemon inside the container. This is the safest isolation model. As a trade-off, images built inside the container are not shared with the host's Docker cache and are discarded when the container is removed.

If you need to share the host Docker socket (Docker-outside-of-Docker), replace the `docker-in-docker` feature with a socket mount:

```jsonc
"mounts": [
  "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
]
```

### First build time

The initial `devcontainer up` downloads the base image (~1 GB) and runs `post-create.sh`. On a fast connection, expect 3–8 minutes. Subsequent starts from the cached image take a few seconds.

### Apple Silicon compatibility

All images referenced here (`mcr.microsoft.com/devcontainers/python`, devcontainer features) publish `linux/arm64` variants. Colima defaults to the native architecture, so no emulation is required on Apple Silicon.

---

## Customisation

### Adding Python packages

Add packages to `pyproject.toml` and run `uv sync` (or let the next container build handle it).

### Adding npm packages

Add packages to `src/frontend/package.json` and run `npm install` inside the frontend directory.

### Adding VS Code extensions

Add extension IDs to the `customizations.vscode.extensions` array in `devcontainer.json` and rebuild the container.

### Changing the Python version

Update the base image tag in `Dockerfile`:

```dockerfile
FROM mcr.microsoft.com/devcontainers/python:3.13-bookworm
```

Available tags: [mcr.microsoft.com/devcontainers/python](https://mcr.microsoft.com/v2/devcontainers/python/tags/list).

### Changing the Node version

Update the `version` in the Node feature:

```jsonc
"ghcr.io/devcontainers/features/node:1": {
  "version": "22"
}
```

### Persisting shell customisations

The `post-create.sh` script configures oh-my-zsh plugins inline, so no dotfiles need to be mounted from the host. To add aliases or custom configuration, append to `~/.zshrc` at the end of `post-create.sh`:

```bash
echo 'alias ll="ls -la"' >> ~/.zshrc
echo 'alias be="uv run"' >> ~/.zshrc
```

These changes persist for the lifetime of the container but are lost on a full rebuild. For permanent customisation, add the lines to `post-create.sh` itself.
