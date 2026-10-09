# Setup

The install commands are in the [README](../README.md#install). This page covers what
they need and how sign-ins work.

## Prerequisites

| Tool | Needed for |
|---|---|
| `colima`, `docker` | The VM and the Docker CLI. Do not start Colima yourself: `dev` sizes it |
| `devcontainer` | The Dev Containers CLI (`brew install devcontainer` or `npm install -g @devcontainers/cli`) |
| `uv` | `dev new` runs cookiecutter through `uvx` |
| `gh`, `jq` | Sign-in copying and settings sync |
| Claude Code | `dev auth` runs `claude setup-token` on the Mac; `dev` copies its version and theme |
| Ghostty (optional) | `dev -t` / `dev -w`. This repo's `ghostty/config` can be linked to `~/.config/ghostty/config` |
| VS Code (optional) | `dev code`; needs the `code` command on PATH |
| Azure CLI (optional) | Lets `dev` copy the Mac's `az login` into containers |

Keep projects out of iCloud, OneDrive and Dropbox folders (`~/Documents` and
`~/Desktop` are often synced); the sync service creates conflict copies like
`name 2.ext`. `~/code` is fine.

## Sign-ins

Sign-ins live in Docker volumes that every devcontainer shares (with the default
`cache_volume_scope=shared`), so a new project or a rebuild needs none.

| CLI | Source |
|---|---|
| gh, git over https | The Mac's `gh auth token` |
| Copilot CLI | Reuses the gh sign-in |
| Azure CLI | The Mac's `~/.azure` token cache; `az login --use-device-code` in the container if the Mac has none |
| Claude Code | A year-long `claude setup-token` token, kept in the macOS Keychain |

Run `dev auth` once per Mac. It starts the named project's container, copies the gh and
Azure sign-ins from the Mac (or runs the interactive login when the Mac has none), and
creates the Claude Code token: `claude setup-token` opens the browser once, and `dev`
reads the token from its output or asks you to paste it. `dev auth --claude` replaces
the token.

After that, every `dev` start fills whatever a container is missing and names what is
still not signed in. With `cache_volume_scope=per-project`, run `dev auth` in each
project. How the credentials are protected: [security.md](security.md#credentials).

## Without `dev`

Open the project in VS Code and accept "Reopen in Container". Sign in by hand once:
`gh auth login -w`, `az login --use-device-code`, and `claude setup-token` with the
token saved to `~/.config/claude-auth/oauth-token`. The container then gets the
`container_memory_limit` cap instead of one sized for the Mac.
