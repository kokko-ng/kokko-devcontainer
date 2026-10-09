# Setup

Install commands: [README](../README.md#install).

## Prerequisites

| Tool | Needed for |
|---|---|
| `colima`, `docker`, `devcontainer` | The VM, the Docker CLI, the Dev Containers CLI. Do not start Colima yourself: `dev` sizes it |
| `uv`, `gh`, `jq` | `dev new` (cookiecutter via `uvx`), sign-in copying, settings sync |
| Claude Code | `dev auth` runs `claude setup-token` on the Mac; `dev` copies its version and theme |
| Ghostty, VS Code, Azure CLI | Optional: `dev -t`/`-w` (this repo has a `ghostty/config`); `dev code` (`code` on PATH); copying the Mac's `az login` |

Keep projects out of iCloud, OneDrive and Dropbox folders (`~/Documents` and `~/Desktop`
are often synced). `~/code` is fine.

## Sign-ins

Sign-ins live in volumes every devcontainer shares, so a new project or a rebuild needs
none. gh (and Copilot, which reuses it) and Azure are copied from the Mac's own logins.
Claude Code uses a year-long `claude setup-token` token kept in the macOS Keychain.

- `dev auth` once per Mac: copies gh and Azure, or runs their login when the Mac has none,
  and creates the Claude token (one browser sign-in).
- `dev auth --claude` replaces the Claude token, for example when it expires.
- Every other `dev` start fills what a container is missing and names what is not signed
  in. With `cache_volume_scope=per-project`, run `dev auth` in each project.

These sign-ins are as powerful as yours; sign in to Azure as an identity whose rights
you are happy for an agent to use.

## Without `dev`

Open the project in VS Code and accept "Reopen in Container". Sign in by hand once:
`gh auth login -w`, `az login --use-device-code`, and `claude setup-token` with the
token saved to `~/.config/claude-auth/oauth-token`.
