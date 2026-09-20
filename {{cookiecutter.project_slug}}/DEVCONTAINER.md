# {{ cookiecutter.project_name }} — devcontainer

Generated from [kokko-devcontainer](https://github.com/kokko-ng/kokko-devcontainer).
Container name: `{{ cookiecutter.__container_name }}`.

## What is installed

| Tool | Purpose |
|------|---------|
| Python {{ cookiecutter.python_version }} + uv | Backend runtime and dependency management |
| Node {{ cookiecutter.node_version }} | Frontend build tooling |
| GitHub CLI | Repository and PR workflows |
| Claude Code | AI coding assistant (native binary, pinned and baked into the image; auto-update off) |
| pre-commit + shellcheck | The hooks the bundled `CLAUDE.md` makes mandatory, and a linter for the shell agents write |
| bubblewrap + socat | Linux dependencies of Claude Code's Bash sandbox (on — see [Permission model](#permission-model)) |
| zsh + oh-my-zsh | Shell with autosuggestions and syntax highlighting |
{%- if cookiecutter.include_azure_cli == "yes" %}
| Azure CLI | Azure resource management |
{%- endif %}
{%- if cookiecutter.include_azure_sql_driver == "yes" %}
| ODBC Driver 18 (msodbcsql18) | Azure SQL connectivity via pyodbc |
{%- endif %}
{%- if cookiecutter.include_copilot_cli == "yes" %}
| GitHub Copilot CLI | `copilot` binary, installed via `npm i -g @github/copilot@<pinned>` |
{%- endif %}
{%- if cookiecutter.include_playwright == "yes" %}
| Playwright CLI + Chromium | Browser automation for coding agents (`playwright-cli`) |
{%- endif %}
{%- if cookiecutter.include_docker_in_docker == "yes" %}
| Docker-in-Docker | Container builds inside the devcontainer. **Runs the container privileged** — see below |

Docker-in-Docker requires a privileged container. An agent running in it without
prompts then has, in effect, root on the Colima VM — every other project's containers
and volumes are within reach — so decide deliberately what runs here unattended. Its
image store also lives in a volume that grows unnoticed: `docker system df` does not
count it. Prune it periodically from inside the container with `docker system prune -a`.
{%- endif %}

## Layout this assumes

| Setting | Value | Where |
|---|---|---|
| Python source (`PYTHONPATH`) | `{{ cookiecutter.backend_src_dir }}/` | `devcontainer.json` -> `containerEnv` |
| Frontend package root | `{{ cookiecutter.frontend_dir }}/` | `devcontainer.json` -> `DEVCONTAINER_FRONTEND_DIR` |
| Backend port | `{{ cookiecutter.backend_port }}` | `devcontainer.json` -> `forwardPorts` |
| Frontend port | `{{ cookiecutter.frontend_port }}` | `devcontainer.json` -> `forwardPorts` |
| Container memory cap | `{{ cookiecutter.container_memory_limit }}` | `devcontainer.json` -> `runArgs` (`--memory`, `--memory-swap`) |

`post-create.sh` runs `uv sync` when a `pyproject.toml` exists and installs
frontend dependencies when `{{ cookiecutter.frontend_dir }}/` exists. Neither is required — the
container comes up either way.

The memory cap is per container: a runaway process gets killed inside this container
instead of taking the whole Colima VM (and every other project) down. Keep it below the
VM's own `--memory`.

## Starting it

```bash
code .                                   # then accept "Reopen in Container"

# — or — without VS Code
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```

Host prerequisites (Colima, the devcontainer CLI, Ghostty) are covered in the
upstream [INSTRUCTIONS.md](https://github.com/kokko-ng/kokko-devcontainer/blob/main/INSTRUCTIONS.md).

## What persists across rebuilds

| Volume | Holds | Scope |
|---|---|---|
| `{{ cookiecutter.project_slug }}-claude-config` | Claude Code login, installed plugins, session transcripts, auto-memory | Always this project only. `post-create.sh` merges this project's bundled settings and plugin roster into the `settings.json` inside it on every start, and two projects sharing one file would undo each other's roster |
| `{{ cookiecutter.__volume_prefix }}-gh-config` | `gh auth login` | Follows `cache_volume_scope` |
| `{{ cookiecutter.__volume_prefix }}-uv-cache`, `-npm-cache`, `-zsh-history` | Package caches and shell history | Follows `cache_volume_scope` |
{%- if cookiecutter.include_playwright == "yes" %}
| `{% if cookiecutter.cache_volume_scope == "per-project" %}{{ cookiecutter.project_slug }}-pw-browsers{% else %}pw-browsers{% endif %}` | Playwright browsers | Follows `cache_volume_scope` |
{%- endif %}

So you sign in to `claude` and `gh` once per project, not once per rebuild. Nothing but
the workspace itself is bind-mounted from the host: host credential directories
(`~/.ssh`, `~/.azure`, the host's own `~/.claude`) stay outside, because everything
reachable inside the container is reachable by an agent running without prompts. Sign
in from inside the container instead, with the narrowest identity that does the job:
for `gh`, a fine-grained token limited to this project's repositories (see
[Permission model](#permission-model)).
{%- if cookiecutter.include_azure_cli == "yes" %}
A commented-out named volume for an in-container `az login` is in `devcontainer.json`;
use a least-privilege identity for it, since every agent session then carries it.
{%- endif %}

## Commit authorship

{% if cookiecutter.git_user_name -%}
Every commit made in this container, by you or by Claude Code, is authored as
`{{ cookiecutter.git_user_name }} <{{ cookiecutter.git_user_email }}>`. `post-create.sh` sets `user.name` and
`user.email` on first provision and never overwrites a value that is already set, so a
change you make inside the container survives rebuilds.
{%- else -%}
No git identity was given to the template, so `post-create.sh` leaves `user.name` and
`user.email` alone. Set them inside the container before the first commit.
{%- endif %}

Claude Code's own signature, the `Co-Authored-By` trailer on commits and the footer on
pull requests, is **{% if cookiecutter.claude_attribution == "yes" %}on{% else %}off{% endif %}** for this project (`claude_attribution`).
To change it later, edit or remove `attribution` in `~/.claude/settings.json` inside the
container: the bundled default only applies where that key is absent, so a rebuild
does not undo the change.

## Changing what gets installed

Some answers are baked into the image and need a rebuild; some are plain
environment variables you can flip in `devcontainer.json` and rebuild; the
bundled config can be re-applied with no rebuild at all.

| Change | How |
|---|---|
| Copilot CLI on/off | `DEVCONTAINER_INSTALL_COPILOT_CLI` in `containerEnv`, then rebuild |
| Playwright CLI on/off | `DEVCONTAINER_INSTALL_PLAYWRIGHT` in `containerEnv`, then rebuild |
| Frontend directory | `DEVCONTAINER_FRONTEND_DIR` in `containerEnv`, then rebuild |
| Python source path | `PYTHONPATH` in `containerEnv`, then rebuild |
| Forwarded ports | `forwardPorts` in `devcontainer.json`, then rebuild |
| Memory cap, PID limit | `runArgs` in `devcontainer.json`, then rebuild |
| Azure CLI, Docker-in-Docker | `features` in `devcontainer.json`, then rebuild |
| ODBC driver | the apt layer in `Dockerfile`, then rebuild |
| Claude Code version | the `install.sh \| bash -s <version>` line in `Dockerfile`, then rebuild (`cu` installs the latest release until then) |
| System packages (apt) | the apt layer in `Dockerfile`, then rebuild — the container has no sudo after provisioning |
| Claude settings, plugin roster, `CLAUDE.md`, the SessionStart hook, zsh config | edit under `.devcontainer/config/`, then `bash .devcontainer/post-create.sh --config-only` |
| Sandbox allowlist and writable paths | `sandbox` in `.devcontainer/config/claude/settings.json`, then `--config-only` (or your own `~/.claude/settings.json`) |
| Permission policy (deny list, bypass lock, sandbox on/off) | `.devcontainer/config/claude/managed-settings.json`, then rebuild — it is baked into the image, and the container has no sudo to replace it in place |
| Keep sudo in the container | `DEVCONTAINER_KEEP_SUDO` in `containerEnv`, then rebuild |

Rebuild: `devcontainer up --workspace-folder . --remove-existing-container`.

## Claude Code plugins

`post-create.sh` registers every marketplace in `extraKnownMarketplaces` and
installs every plugin set to `true` in `enabledPlugins`, both read from
`.devcontainer/config/claude/settings.json`. `enabledPlugins` on its own only
*enables* a plugin that is already installed, so without this step a fresh
container comes up with an empty plugin directory.

{% if cookiecutter.claude_plugin_roster == "none" -%}
This project was generated with an empty roster — add your own marketplaces and
plugins to `settings.json`, then run `bash .devcontainer/post-create.sh --config-only`.
{%- else -%}
This project ships the `kokko-ng` roster
([kokko-skills](https://github.com/kokko-ng/kokko-skills),
[kokko-janitor-skill](https://github.com/kokko-ng/kokko-janitor-skill)). A plugin set to
`false` is never installed.
{%- endif %}

The bootstrap reads the **merged** `~/.claude/settings.json`, so a plugin you
disable locally stays disabled. Its network calls run at most once per 24 hours
(stamp: `~/.claude/.plugin-bootstrap-stamp`):

| Variable | Effect |
|---|---|
| `KOKKO_PLUGIN_REFRESH=1` | Force a marketplace/plugin refresh now, ignoring the 24h stamp |
| `KOKKO_SKIP_PLUGINS=1` | Skip the plugin bootstrap entirely (used by CI) |

## Permission model

Claude Code runs in **Auto mode** (`permissions.defaultMode: "auto"`): the
built-in classifier decides which tool calls run without a prompt. Four things sit
around it.

**A deny floor.** `.devcontainer/config/claude/managed-settings.json` is baked into
the image at `/etc/claude-code/managed-settings.json`, where Claude Code applies it
above every user and project setting. It denies force-push in every spelling
(`--force`, `-f`, `+refspec`), `git reflog expire` and `git gc --prune`, Azure `delete`
and `purge`, Docker volume pruning, `gh repo delete` and `gh api ... DELETE`, and edits
to `devcontainer.json` and the `init-host-*.sh` scripts (see below); and it disables
bypass mode (`--dangerously-skip-permissions`). A Bash deny rule matches the command as
Claude writes it — including inside `&&` chains, pipes and subshells — but not a
different program that does the same thing, so it is a floor, not a security boundary.
The boundary is the next two items. Changing the policy is a rebuild: the container
has no sudo to replace the file in place, which is the point.

**The Bash sandbox, on.** The switch (`sandbox.enabled`) is in the policy file, where
Claude Code enforces it over every user setting, so `/sandbox off` does not hold. The
configuration is in the bundled `settings.json` and is yours to widen:
`enableWeakerNestedSandbox` (the container has no user namespaces), `docker *` excluded,
writes allowed in the workspace, `/tmp` and the tool caches, and a network allowlist —
git, npm and PyPI{% if cookiecutter.include_azure_cli == "yes" %}, the Azure endpoints{% endif %}{% if cookiecutter.include_playwright == "yes" %}, the Playwright download CDN{% endif %}.
Add your proxy and the APIs the project develops against to
`sandbox.network.allowedDomains`, in the bundle or in `~/.claude/settings.json`. A
blocked host or path shows up in the command's output as a sandbox denial, not as a
silent failure — add the endpoint rather than guess.

**No sudo after provisioning.** `post-create.sh` removes the container user's
passwordless sudo as its last step (`keep_container_sudo` was
**{{ cookiecutter.keep_container_sudo }}**{% if cookiecutter.keep_container_sudo == "yes" %} — so this container KEEPS sudo, and an agent in it can become root{% endif %}).
Without it an agent cannot become root, rewrite the policy file, or install packages;
a system package is a `Dockerfile` line and a rebuild.
{%- if cookiecutter.keep_container_sudo == "no" and cookiecutter.include_playwright == "no" and cookiecutter.include_docker_in_docker == "no" %}
Nothing at run time needs sudo either, so the container runs with
`--security-opt=no-new-privileges`: setuid binaries are inert from the first process.
{%- endif %}

**The workspace is the container definition.** The project directory is the one bind
mount, and it holds `devcontainer.json` (mounts, `runArgs`, a possible `--privileged`)
and the `init-host-*.sh` scripts that `initializeCommand` runs *on the host*, as you,
before every build. The deny list keeps Claude Code's Edit tool away from those files,
but a shell redirect is not an Edit, so the control is yours: review every diff under
`.devcontainer/` before you rebuild, never rebuild from a branch you have not read, and
put the directory under a CODEOWNERS rule or branch protection where this repository
lives. `.git/hooks` and `.pre-commit-config.yaml` deserve the same look if you run git
on the host.

What this contains, and what it does not: an agent that makes mistakes is contained —
its writes stay in the workspace and the caches, its network stays on the allowlist,
its git history is recoverable, and it cannot become root. An agent that intends harm
still holds everything the workspace and the in-container logins can reach. `gh auth
token` prints the GitHub token and nothing stops `curl` against the API with it, so
sign `gh` in with a fine-grained token limited to this project's repositories
(`gh auth login --with-token`), with an expiry, not your broadest personal token{% if cookiecutter.include_azure_cli == "yes" %}; the same for `az login`{% endif %}.

Git recoverability rests on git itself — `gc.reflogExpire`,
`gc.reflogExpireUnreachable` and `gc.pruneExpire` are `never`, so committed work is
always recoverable — and `safe.directory` is `*`, so git works in the bind-mounted
workspace and in the worktrees `claude --worktree` creates under `.claude/worktrees/`.

## Agent instructions

Two files reach Claude Code: `~/.claude/CLAUDE.md` (installed from
`.devcontainer/config/claude/CLAUDE.md`, the container-wide rules) and this project's
`CLAUDE.md` at the repo root (layout, verification commands, container facts). Keep the
project one accurate — it is the first thing an agent reads. A `SessionStart` hook
prints any provisioning step that failed into the session, so a broken `uv sync` is
the first thing an agent learns rather than something it discovers mid-task. The Bash
tool's timeout is raised to 10 minutes by default and 30 on request, so full test
suites and installs finish instead of being backgrounded.

{% if cookiecutter.python_version != "3.14" -%}
## Pinning the base image

The upstream template only carries a digest for its default Python (3.14), so
this `Dockerfile` names `python:{{ cookiecutter.python_version }}-bookworm` by tag with no digest — the
build is not reproducible until you pin it:

```bash
docker pull mcr.microsoft.com/devcontainers/python:{{ cookiecutter.python_version }}-bookworm
docker images --digests mcr.microsoft.com/devcontainers/python
```

Then append `@sha256:<digest>` to the `FROM` line.

{% endif -%}
## Updating

Bundled config changes — `CLAUDE.md`, `settings.json`, `managed-settings.json`, the
SessionStart hook, zsh config, the plugin roster — re-apply in place with no rebuild:

```bash
bash .devcontainer/post-create.sh --config-only
```

`Dockerfile` (including the Claude Code version pin) and `devcontainer.json`
`features`/`containerEnv`/`runArgs`/`mounts` changes always need a rebuild.
