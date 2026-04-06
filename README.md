# devcontainer-starter

A portable development container for FastAPI + Vue projects, designed to run on macOS with Colima as the Docker runtime.

## What's included

| Tool | Purpose |
|------|---------|
| Python 3.12 + uv | Backend runtime and dependency management |
| Node 20 | Frontend build tooling |
| Azure CLI | Azure resource management |
| GitHub CLI | Repository and PR workflows |
| Claude Code | AI coding assistant (native binary via `claude.ai/install.sh`) |
| zsh + oh-my-zsh | Shell with autosuggestions and syntax highlighting |
| Docker-in-Docker | Container builds inside the devcontainer |

Ports `8000` (FastAPI) and `5173` (Vite) are forwarded automatically.

## Repo structure

```
.devcontainer/
├── devcontainer.json
├── Dockerfile
├── init-host-certs.sh
├── post-create.sh
└── config/
    ├── zsh/          # Shell config (bundled into container)
    ├── claude/       # Claude Code settings and CLAUDE.md
ghostty/
└── config            # Host-side Ghostty terminal config
```

## Quick start

```bash
# 1. Install prerequisites (see INSTRUCTIONS.md for detail)
brew install colima devcontainer
brew install --cask ghostty

# 2. Start Colima
colima start --cpu 4 --memory 8

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

## Caveats

- The devcontainer assumes a **FastAPI + Vue** project layout (`src/` for Python, `src/frontend/` for Vue). Adjust `PYTHONPATH` and the frontend install path if your layout differs.
- Shell config (zsh) and Claude Code settings are bundled in `.devcontainer/config/` — no host dotfiles are read.
- Optional mounts for `~/.azure` and `~/.claude` are commented out in `devcontainer.json`. Uncomment them to persist credentials and Claude state across rebuilds.

See [INSTRUCTIONS.md](INSTRUCTIONS.md) for a full walkthrough.
