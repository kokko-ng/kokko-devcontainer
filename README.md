# kokko-devcontainer

A [cookiecutter](https://cookiecutter.readthedocs.io/) template for a FastAPI + Vue
devcontainer on macOS with Colima, plus `dev`, a host command that creates, starts,
signs in to and opens those containers. Claude Code runs inside in Auto mode, behind an
outbound firewall, with no sudo.

Every generated project ships a strict quality gate from its first commit: pre-commit
hooks (gitleaks, ruff, mypy strict, vulture, deptry, 95% coverage, file length, the
frontend's checks, commitizen; Trivy before a push), a starter `pyproject.toml` and
package, and a CI workflow that re-runs them. Its `DEVCONTAINER.md` has the details.

## Install

Set up or update with Claude Code: paste the contents of
[prompts/setup.md](prompts/setup.md) (new Mac) or [prompts/update.md](prompts/update.md)
(existing install) into Claude Code, or once the repo is cloned run
`claude "Follow ~/code/kokko-devcontainer/prompts/update.md"`. The manual steps:

```bash
brew install colima docker devcontainer uv gh jq
brew install --cask ghostty                      # optional: dev -t / -w open Ghostty tabs
git clone https://github.com/kokko-ng/kokko-devcontainer.git ~/code/kokko-devcontainer
mkdir -p ~/.local/bin
ln -sfn ~/code/kokko-devcontainer/bin/dev ~/.local/bin/dev   # ~/.local/bin must be on PATH
```

Claude Code must be installed on the Mac (`dev auth` uses it to create the container
token). Optional: `ln -sfn ~/code/kokko-devcontainer/ghostty/config ~/.config/ghostty/config`.

## First project

```bash
dev new demo        # generate ~/code/demo, start its container, open a shell in it
exit
dev auth demo       # once per Mac: sign-ins every devcontainer shares
dev claude demo     # Claude Code in the container, signed in, Auto mode
```

`PROJECT` is a folder under `~/code` or a path. Inside a project folder, leave it out:
in `~/code/demo`, `dev claude` does the same as `dev claude demo` from anywhere. This
holds for every command below that takes `PROJECT`.

The first build takes a few minutes. `dev` shows one live status line with the elapsed
time and the current step (image build step, then setup phase); the full log is in
`$TMPDIR/dev-<project>.log`.

## Commands

| Command | Does |
|---|---|
| `dev [PROJECT] [-- CMD...]` | Start the VM and container if needed, then a shell (or `CMD`) in it |
| `dev claude [PROJECT]` | ... then Claude Code (`--permission-mode auto`) |
| `dev code [PROJECT]` | ... then VS Code attached to the container |
| `dev -t` / `dev -w` | Open in a new Ghostty tab / window (also `dev claude -t`) |
| `dev new NAME [key=value...]` | Generate `~/code/NAME`, `git init` it, open it |
| `dev up [PROJECT]` | Start the container without opening anything |
| `dev auth [--claude] [PROJECT]` | Sign in for every devcontainer; `--claude` makes a new Claude token |
| `dev rebuild [PROJECT]` | Recreate the container (after Dockerfile or devcontainer.json edits) |
| `dev stop [--keep-vm] [PROJECT]` | Stop the container, and Colima when nothing else runs |
| `dev root [PROJECT]` | Root shell in the container |
| `dev theme [light\|dark]` | Set Claude Code's theme in every running devcontainer |
| `dev vm [status\|start\|stop\|resize]` | The Colima VM |
| `dev ls` | List devcontainers |
| `dev guide` | Short walkthrough with this Mac's state |

`dev new` details: the name is lowercased, spaces and underscores become dashes, and
`key=value` pairs are template options (below). An empty folder of that name is reused.
If an interrupted `dev new` already generated the project, it is opened instead of
refused. The template comes from `gh:kokko-ng/kokko-devcontainer` (`main`); set
`DEV_TEMPLATE` to use another source, such as your clone.

## What `dev` does when it opens a container

- Fills missing sign-ins from the Mac (see below).
- Updates the container's Claude Code to the Mac's version if it is older. New images are
  built with the Mac's version (`DEVCONTAINER_CLAUDE_VERSION` -> build arg
  `CLAUDE_CODE_VERSION`); the Dockerfile pin is the fallback.
- Sets the Mac's Claude Code theme and marks onboarding done with the Mac's account
  profile, so `dev claude` opens signed in, with no theme picker and no `/login`.
- Passes `KOKKO_SOUND_EVENTS` from the Mac's Claude Code settings.

`dev theme` with no argument applies the Mac's theme; `light` and `dark` mean the
`-ansi` themes. mac-setup's `tt` calls it. The `theme-sync@kokko-claude-mods` plugin in
the container roster applies the change to open sessions.

## Sign-ins

Sign-ins live in volumes shared by every devcontainer (with `cache_volume_scope=shared`),
so a new project or a rebuild needs none.

| CLI | Source |
|---|---|
| gh, git over https | The Mac's `gh auth token` |
| Copilot CLI | Reuses the gh sign-in |
| Azure CLI | The Mac's `~/.azure` token cache; `az login --use-device-code` if the Mac has none |
| Claude Code | A year-long `claude setup-token` token, kept in the macOS Keychain |

`dev auth` does the interactive part once. Every other `dev` start fills whatever is
missing and says what is still not signed in. Host credential folders are never mounted.
These sign-ins are as powerful as yours; the policy below limits what an agent does with
them.

## Resources

`dev` sizes Colima from the Mac's RAM and caps each container below it.

| Setting | Value |
|---|---|
| VM memory | 3 GB on an 8 GB Mac, 6 GB up to 16 GB, else half the RAM minus 4 GB |
| VM CPUs | Half the cores, 2 to 8 |
| VM disk | 60 GB on an 8 GB Mac, else 100 GB (sparse) |
| Container memory | VM minus 1 GB, at least 2 GB |
| At once | Under 16 GB: one devcontainer (starting one stops the others). Otherwise as many as fit |

- The VM disk never shrinks: an existing larger Colima disk is kept.
- An existing VM keeps its size until `dev vm resize` (which stops running containers).
- Before starting the VM, `dev` asks if macOS has under 25% memory free.
- Overrides, per command or in `~/.zshrc.local`: `DEV_VM_CPUS`, `DEV_VM_MEMORY`,
  `DEV_VM_DISK` (GB), `DEV_ALLOW_MULTIPLE=1`, `DEV_FORCE=1`, `DEV_HOME` (default `~/code`).

## Security model

- **Auto mode.** Claude Code's classifier decides which tool calls run without a prompt.
- **Policy.** `/etc/claude-code/managed-settings.json`, baked into the image, denies
  force-push, `git reflog expire`, `git gc --prune`, Azure `delete`/`purge`, Docker
  volume removal, `gh repo delete`, `gh api ... DELETE`, printing gh/az tokens and
  reading the Claude token, and disables bypass mode. Deny rules match command text, so
  they are a floor, not a boundary.
- **Firewall.** With `network_firewall=on`, iptables limits everything in the container to
  the hosts in `.devcontainer/firewall/allowed-domains.txt` (GitHub, Copilot, Anthropic,
  npm, PyPI, Azure, Playwright, VS Code) plus GitHub's published ranges. `localhost` is
  unaffected. Add your project's hosts to that file and `dev rebuild`. Claude Code's own
  Bash sandbox stays off; it cannot run in an unprivileged container.
- **No sudo.** With `agent_sudo=no`, provisioning removes the user's sudo when done, so
  nothing in the container can change the policy or the firewall. Use `dev root`.
- **Docker-in-Docker** is off by default because it runs the container privileged.

## Template options

Pass these as `dev new NAME key=value` or to `cookiecutter`. Invalid answers are rejected
before anything is written.

| Option | Default | Effect |
|---|---|---|
| `project_name` | `My Project` | Headings; the slug derives from it |
| `python_version` | `3.14` | Base image. Only `3.14` is digest-pinned |
| `node_version` | `22` | Node feature version (`24`, `20`) |
| `backend_src_dir` / `frontend_dir` | `src` / `ui` | `PYTHONPATH`; where frontend deps are installed |
| `backend_port` / `frontend_port` | `8000` / `5173` | Forwarded ports |
| `include_azure_cli` | `yes` | Azure CLI and its sign-in volume |
| `include_azure_sql_driver` | `yes` | ODBC Driver 18 for pyodbc / Azure SQL |
| `include_docker_in_docker` | `no` | Nested Docker; makes the container privileged |
| `include_copilot_cli` | `yes` | GitHub Copilot CLI |
| `include_playwright` | `yes` | Playwright CLI and Chromium |
| `claude_plugin_roster` | `kokko-ng` | The plugins below, or `none` |
| `claude_attribution` | `host` | Claude's commit/PR trailer: copy the Mac's setting, `no`, or `yes` |
| `agent_sudo` | `no` | `yes` keeps passwordless sudo in the container |
| `network_firewall` | `on` | `off` leaves outbound traffic open |
| `cache_volume_scope` | `shared` | `per-project` gives each project its own caches and sign-ins |
| `container_memory_limit` | `5g` | Memory cap when started without `dev` |
| `git_user_name` / `git_user_email` | blank | Commit author; blank uses the Mac's git identity |

## Claude Code plugins

The `kokko-ng` roster installs, on first start and at most once a day after:

| Marketplace | Plugins |
|---|---|
| [kokko-skills](https://github.com/kokko-ng/kokko-skills) | kokko-git, kokko-viz, kokko-infra, kokko-ai-config, kokko-notifications, kokko-validation, kokko-env |
| [kokko-claude-mods](https://github.com/kokko-ng/kokko-claude-mods) | theme-sync |

Edit `enabledPlugins` in `.devcontainer/config/claude/settings.json`; `false` means never
installed. `KOKKO_PLUGIN_REFRESH=1` forces a refresh, `KOKKO_SKIP_PLUGINS=1` skips it. Code
quality is enforced by each repo's pre-commit config, not a plugin; kokko-code-quality
and kokko-janitor are uninstalled from existing containers on their next start.

## Other ways in

- **VS Code alone:** open the project and accept "Reopen in Container". Sign in by hand
  once: `gh auth login -w`, `az login --use-device-code`, and `claude setup-token` with
  the token saved to `~/.config/claude-auth/oauth-token`.
- **Existing project:** generate elsewhere and copy in.

  ```bash
  uvx cookiecutter gh:kokko-ng/kokko-devcontainer -o /tmp
  cp -r /tmp/<slug>/.devcontainer ~/code/your-project/
  cp /tmp/<slug>/CLAUDE.md ~/code/your-project/       # or merge into yours
  cat /tmp/<slug>/.gitignore >> ~/code/your-project/.gitignore
  ```

  The quality gate (`.pre-commit-config.yaml`, `pyproject.toml`, `scripts/hooks/`,
  `.github/workflows/ci.yml`) can be copied the same way and merged by hand.

  Answer the prompts with the project's real layout (source dir, frontend dir, ports).

- **Pinned version:** `uvx cookiecutter gh:kokko-ng/kokko-devcontainer --checkout v5.2.0`.

Keep projects out of iCloud, OneDrive and Dropbox folders (`~/Documents` and `~/Desktop`
are often synced); `~/code` is fine.

## Updating a project

`/devcontainer-update` (kokko-env plugin) diffs `.devcontainer/` against upstream,
updates it and reports what needs a rebuild. Config under `.devcontainer/config/` is
re-applied on every container start, or now with
`bash .devcontainer/post-create.sh --config-only`. Changes to the Dockerfile, the
policy, the firewall allowlist or devcontainer.json need `dev rebuild`.

## More

- Generated projects: `DEVCONTAINER.md` in the project.
- Troubleshooting, disk, pins, releases: [MANAGING.md](MANAGING.md).
- Changing this repo: [CONTRIBUTING.md](CONTRIBUTING.md).
