# {{ cookiecutter.project_name }} — devcontainer

Generated from [kokko-devcontainer](https://github.com/kokko-ng/kokko-devcontainer).
Container name: `{{ cookiecutter.__container_name }}`.

## Starting it

Host setup (Colima, the devcontainer CLI, `dev` on PATH) is in the upstream
[README](https://github.com/kokko-ng/kokko-devcontainer#install) and
[setup docs](https://github.com/kokko-ng/kokko-devcontainer/blob/main/docs/setup.md).

```bash
dev                 # start Colima and the container if needed, then a shell in it
dev claude          # ... Claude Code, signed in, Auto mode
dev code            # ... VS Code attached to the container
dev -t              # ... in a new Ghostty tab (-w for a window)
dev rebuild         # recreate the container after Dockerfile or devcontainer.json edits
dev guide           # everything else
```

Run these inside this folder, or name the project from anywhere:
`dev claude {{ cookiecutter.project_slug }}`. `dev` also brings the container's Claude
Code up to the Mac's version and theme. Without `dev`, run `code .` and accept "Reopen in
Container".
{%- if cookiecutter.network_firewall == "on" %}

With the firewall on, set `"remote.downloadExtensionsLocally": true` in your VS Code user
settings so extensions download on the Mac.
{%- endif %}

## What is installed

| Tool | Purpose |
|------|---------|
| Python {{ cookiecutter.python_version }} + uv | Backend runtime and dependencies |
| Node {{ cookiecutter.node_version }} | Frontend tooling |
| GitHub CLI | Repository and PR workflows |
| Claude Code | Native binary in the image, auto-update off; `dev` matches the Mac's version |
| pre-commit, shellcheck, jq | Hooks the bundled `CLAUDE.md` requires; shell linting |
| zsh + oh-my-zsh + Starship | Shell (`als` lists the aliases) |
{%- if cookiecutter.include_azure_cli == "yes" %}
| Azure CLI | Azure resource management |
{%- endif %}
{%- if cookiecutter.include_azure_sql_driver == "yes" %}
| ODBC Driver 18 | Azure SQL via pyodbc |
{%- endif %}
{%- if cookiecutter.include_copilot_cli == "yes" %}
| GitHub Copilot CLI | `copilot` |
{%- endif %}
{%- if cookiecutter.include_playwright == "yes" %}
| Playwright CLI + Chromium | Browser automation for agents (`playwright-cli`) |
{%- endif %}
{%- if cookiecutter.include_docker_in_docker == "yes" %}
| Docker-in-Docker | Container builds inside the devcontainer |

Docker-in-Docker runs the container **privileged**: an agent here has, in effect, root on
the Colima VM, including other projects' containers and volumes. Its image store is a
volume `docker system df` does not count; prune it from inside with
`docker system prune -a`.
{%- endif %}

## Layout

| Setting | Value | Where |
|---|---|---|
| Python source (`PYTHONPATH`) | `{{ cookiecutter.backend_src_dir }}/` | `containerEnv` |
| Frontend root | `{{ cookiecutter.frontend_dir }}/` | `DEVCONTAINER_FRONTEND_DIR` |
| Ports | `{{ cookiecutter.backend_port }}`, `{{ cookiecutter.frontend_port }}` | `forwardPorts` |
| Memory cap | 1 GB under the Colima VM with `dev`, else `{{ cookiecutter.container_memory_limit }}` | `runArgs` |

Provisioning runs `uv sync` when `pyproject.toml` exists and installs frontend
dependencies when `{{ cookiecutter.frontend_dir }}/` exists. Its log is
`/tmp/post-create.log`; failed steps are listed in `~/.devcontainer-provision-status`
and shown at the start of each Claude Code session.

## Quality gate

`.pre-commit-config.yaml` is a strict gate, installed on provision for three stages:

- **Commit:** gitleaks, file hygiene, shellcheck, ruff (lint, format, bandit rules,
  complexity at most 8, docstrings), mypy `--strict` (no `Any` in production code),
  vulture, deptry, file length (400 lines, tests 500), every test asserts something,
  pytest with coverage at least 95%, Markdown links, the frontend's `typecheck`, `lint`
  and `test` scripts once `{{ cookiecutter.frontend_dir }}/package.json` exists,
  actionlint and zizmor; commitizen checks the message (Conventional Commits).
- **Push:** Trivy, through a local `trivy` or Docker; inside the container it skips.
- **CI** (`.github/workflows/ci.yml`): every commit-stage hook on every file, every
  commit message, and the Trivy scan.

`scripts/hooks/check_strictness.py` fails if a threshold in `pyproject.toml` is
loosened. The Python hooks run through `uv run --frozen`, so commit the `uv.lock` the
first `uv sync` writes. The starter package in `{{ cookiecutter.backend_src_dir }}/{{ cookiecutter.__package_name }}/` is
there so the gate has code to check; replace it.

## Volumes

| Volume | Holds |
|---|---|
| `{{ cookiecutter.project_slug }}-claude-config` | Claude Code plugins, settings, history (this project only) |
| `{{ cookiecutter.__volume_prefix }}-gh-config` | gh sign-in, also used by git and Copilot |
| `{{ cookiecutter.__volume_prefix }}-claude-auth` | Claude Code token |
{%- if cookiecutter.include_azure_cli == "yes" %}
| `{{ cookiecutter.__volume_prefix }}-azure-config` | Azure CLI sign-in |
{%- endif %}
| `{{ cookiecutter.__volume_prefix }}-uv-cache`, `-npm-cache`, `-zsh-history` | Caches and shell history |
{%- if cookiecutter.include_playwright == "yes" %}
| `{% if cookiecutter.cache_volume_scope == "per-project" %}{{ cookiecutter.project_slug }}-pw-browsers{% else %}pw-browsers{% endif %}` | Playwright browsers |
{%- endif %}

{% if cookiecutter.cache_volume_scope == "shared" -%}
Sign-in and cache volumes are shared with every project on this Mac, so you sign in once
(`dev auth`), not per project or rebuild.
{%- else -%}
Sign-in and cache volumes belong to this project only; run `dev auth` here once.
{%- endif %} Nothing is bind-mounted from the host.

## Security

- **Auto mode.** Claude Code's classifier approves safe tool calls.
- **Policy.** `/etc/claude-code/managed-settings.json` (from
  `.devcontainer/config/claude/managed-settings.json`, baked into the image) denies
  force-push, `git reflog expire`, `git gc --prune`, Azure `delete`/`purge`, Docker volume
  removal, `gh repo delete`, `gh api ... DELETE` and reading or printing tokens, and
  disables bypass mode. Rules match command text: a floor, not a boundary.
{%- if cookiecutter.network_firewall == "on" %}
- **Firewall.** Outbound traffic reaches only the hosts in
  `.devcontainer/firewall/allowed-domains.txt` plus GitHub's ranges; `localhost` is
  unaffected. Other hosts fail at once with "No route to host". Add your project's hosts (one
  exact name per line), then `dev rebuild`. `sudo devcontainer-firewall` re-resolves
  addresses.
{%- else %}
- **Firewall.** Off (`network_firewall: off`); outbound traffic is open. Set
  `DEVCONTAINER_FIREWALL` to `1` and add the `NET_ADMIN`/`NET_RAW` capabilities to
  `runArgs` to turn it on.
{%- endif %}
{%- if cookiecutter.agent_sudo == "yes" %}
- **Sudo.** Kept (`agent_sudo: yes`), so anything in the container can change the policy
  and the firewall. Set `DEVCONTAINER_AGENT_SUDO` to `0` and rebuild to remove it.
{%- else %}
- **No sudo.** Provisioning removes it, so nothing in the container can change the policy
  or the firewall. Use `dev root` on the host for a root shell.
{%- endif %}
- **Git.** Reflog and prune never expire, so committed work is recoverable.

## Commit authorship

{% if cookiecutter.git_user_name -%}
Commits here, yours and Claude Code's, are authored as
`{{ cookiecutter.git_user_name }} <{{ cookiecutter.git_user_email }}>`.
{%- else -%}
Commits here, yours and Claude Code's, are authored as your Mac's git identity, recorded
by `init-host-identity.sh` before each build.
{%- endif %}
It is set on first provision only, so a change made inside the container survives
rebuilds.

Claude Code's `Co-Authored-By` trailer and PR footer are **off** (`attribution` in
`~/.claude/settings.json` is empty strings).

## Claude Code plugins

{% if cookiecutter.claude_plugin_roster == "none" -%}
The roster is empty. Add marketplaces and plugins to
`.devcontainer/config/claude/settings.json`, then run
`bash .devcontainer/post-create.sh --config-only`.
{%- else -%}
The `kokko-ng` roster: kokko-git, kokko-viz, kokko-infra, kokko-ai-config,
kokko-notifications, kokko-validation and kokko-env from
[kokko-skills](https://github.com/kokko-ng/kokko-skills), and theme-sync from
[kokko-claude-mods](https://github.com/kokko-ng/kokko-claude-mods). Set a plugin to
`false` in `enabledPlugins` to never install it.
{%- endif %}

Plugins refresh at most once a day; `KOKKO_PLUGIN_REFRESH=1` forces it.

## Changing things

| Change | Where | Then |
|---|---|---|
| Copilot, Playwright, frontend dir, sudo, firewall | `DEVCONTAINER_*` in `devcontainer.json` `containerEnv` | `dev rebuild` |
| Ports, memory cap, features, mounts | `devcontainer.json` | `dev rebuild` |
| Image, ODBC driver, Claude Code fallback version | `Dockerfile` | `dev rebuild` |
| Policy, firewall allowlist | `.devcontainer/config/claude/managed-settings.json`, `.devcontainer/firewall/allowed-domains.txt` | `dev rebuild` |
| Claude settings, roster, `CLAUDE.md`, zsh | `.devcontainer/config/` | Next start, or `bash .devcontainer/post-create.sh --config-only` |

`/devcontainer-update` (kokko-env plugin) pulls the latest template into this project
and says what needs a rebuild.
{% if cookiecutter.python_version != "3.14" %}
## Pinning the base image

Only Python 3.14 has a digest in the template, so this `Dockerfile` uses
`python:{{ cookiecutter.python_version }}-bookworm` by tag. To pin it:

```bash
docker pull mcr.microsoft.com/devcontainers/python:{{ cookiecutter.python_version }}-bookworm
docker images --digests mcr.microsoft.com/devcontainers/python
```

Then append `@sha256:<digest>` to the `FROM` line.
{% endif -%}
