# kokko-devcontainer

A [cookiecutter](https://cookiecutter.readthedocs.io/) template for a FastAPI + Vue
devcontainer on macOS with Colima, plus `dev`, a host command that creates, starts,
signs in to and opens those containers. Claude Code runs inside in Auto mode, behind an
outbound firewall, with no sudo.

## Install

With Claude Code: paste [prompts/setup.md](prompts/setup.md) (new Mac) or
[prompts/update.md](prompts/update.md) (existing install) into Claude Code on the Mac, or
once the repo is cloned run `claude "Follow ~/code/kokko-devcontainer/prompts/update.md"`.

By hand:

```bash
brew install colima docker devcontainer uv gh jq
git clone https://github.com/kokko-ng/kokko-devcontainer.git ~/code/kokko-devcontainer
mkdir -p ~/.local/bin
ln -sfn ~/code/kokko-devcontainer/bin/dev ~/.local/bin/dev   # ~/.local/bin must be on PATH
```

Claude Code must be installed on the Mac. Optional tools: [docs/setup.md](docs/setup.md).

## First project

```bash
dev new demo        # generate ~/code/demo, start its container, open a shell in it
exit
dev auth demo       # once per Mac: sign-ins every devcontainer shares
dev claude demo     # Claude Code in the container, signed in, Auto mode
```

Inside `~/code/demo`, leave the project out: `dev claude` does the same.

## Commands

| Command | Does |
|---|---|
| `dev [PROJECT] [-- CMD...]` | Start the VM and container if needed, then a shell (or `CMD`) |
| `dev claude [PROJECT]` | ... then Claude Code in Auto mode |
| `dev code [PROJECT]` | ... then VS Code attached to the container |
| `dev -t` / `dev -w` | Open in a new Ghostty tab / window |
| `dev new NAME [key=value...]` | Generate `~/code/NAME`, `git init` it, open it |
| `dev up [PROJECT]` | Start the container without opening anything |
| `dev auth [--claude] [PROJECT]` | Sign in for every devcontainer |
| `dev rebuild [PROJECT]` | Recreate the container, then open a shell |
| `dev stop [--keep-vm] [PROJECT]` | Stop the container, and Colima when nothing else runs |
| `dev root [PROJECT]` | Root shell in the container |
| `dev theme [light\|dark]` | Set Claude Code's theme in every running devcontainer |
| `dev vm [status\|start\|stop\|resize]` | The Colima VM |
| `dev ls` | List devcontainers |
| `dev guide` | Short walkthrough with this Mac's state |

## Docs

- [Setup](docs/setup.md): prerequisites, sign-ins and `dev auth`.
- [Usage](docs/usage.md): each command in depth, and what `dev` does when it opens a container.
- [Resources](docs/resources.md): VM and container sizing, and how to override it.
- [Security](docs/security.md): Auto mode, the managed policy, the firewall, sudo, credentials.
- [Template](docs/template.md): cookiecutter options, the plugin roster, the generated project.
- [Maintenance](docs/maintenance.md): updating projects, troubleshooting, disk, pin audit.
- [Contributing](docs/CONTRIBUTING.md): tests, linting, releases.

A generated project documents itself in its own `DEVCONTAINER.md`.
