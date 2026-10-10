# kokko-devcontainer

A [cookiecutter](https://cookiecutter.readthedocs.io/) template for a FastAPI + Vue
devcontainer on macOS with Colima, plus `dev`, a host command that creates, starts,
signs in to and opens those containers. Claude Code runs inside in Auto mode, behind an
outbound firewall, with no sudo. Every generated project ships a strict
[quality gate](docs/template.md#quality-gate) from its first commit.

## Install

With Claude Code on the Mac: paste [prompts/setup.md](prompts/setup.md) (new Mac) or
[prompts/update.md](prompts/update.md) (existing install). By hand:

```bash
brew install colima docker devcontainer uv gh jq
git clone https://github.com/kokko-ng/kokko-devcontainer.git ~/code/kokko-devcontainer
mkdir -p ~/.local/bin
ln -sfn ~/code/kokko-devcontainer/bin/dev ~/.local/bin/dev   # ~/.local/bin must be on PATH
```

Claude Code must be installed on the Mac.

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
| `dev claude` / `dev code` | ... then Claude Code in Auto mode / VS Code attached |
| `dev -t` / `dev -w` | Open in a new Ghostty tab / window |
| `dev new NAME [key=value...]` | Generate `~/code/NAME`, `git init` it, open it |
| `dev up` / `dev rebuild` | Start the container / recreate it, then open a shell |
| `dev auth [--claude]` | Sign in for every devcontainer |
| `dev auth --full [PROJECT]` | Full Claude sign-in for one project (Remote Control) |
| `dev stop [--keep-vm]` | Stop the container, and Colima when nothing else runs |
| `dev root` | Root shell in the container |
| `dev theme [light\|dark]` | Set Claude Code's theme in every running devcontainer |
| `dev vm [status\|start\|stop\|resize]` | The Colima VM |
| `dev ls` / `dev guide` | List devcontainers / walkthrough with this Mac's state |

## Docs

- [Setup](docs/setup.md): prerequisites, sign-ins, `dev auth`.
- [Usage](docs/usage.md): what `dev` does beyond `dev guide`, VM and container sizing.
- [Security](docs/security.md): the managed policy, the firewall, sudo.
- [Template](docs/template.md): options, plugin roster, the generated project, quality gate.
- [Maintenance](docs/maintenance.md): updating projects, troubleshooting, disk, pin audit.
- [Contributing](docs/CONTRIBUTING.md): tests, linting, releases.
