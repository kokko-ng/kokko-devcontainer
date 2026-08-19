# {{ cookiecutter.project_name }} — devcontainer

Generated from [kokko-devcontainer](https://github.com/kokko-ng/kokko-devcontainer).
Container name: `{{ cookiecutter.__container_name }}`.

## What is installed

| Tool | Purpose |
|------|---------|
| Python {{ cookiecutter.python_version }} + uv | Backend runtime and dependency management |
| Node {{ cookiecutter.node_version }} | Frontend build tooling |
| GitHub CLI | Repository and PR workflows |
| Claude Code | AI coding assistant (native binary, baked into the image) |
| zsh + oh-my-zsh | Shell with autosuggestions and syntax highlighting |
{%- if cookiecutter.include_azure_cli == "yes" %}
| Azure CLI | Azure resource management |
{%- endif %}
{%- if cookiecutter.include_azure_sql_driver == "yes" %}
| ODBC Driver 18 (msodbcsql18) | Azure SQL connectivity via pyodbc |
{%- endif %}
{%- if cookiecutter.include_copilot_cli == "yes" %}
| GitHub Copilot CLI | `copilot` binary, installed via `npm i -g @github/copilot` |
{%- endif %}
{%- if cookiecutter.include_playwright == "yes" %}
| Playwright CLI + Chromium | Browser automation for coding agents (`playwright-cli`) |
{%- endif %}
{%- if cookiecutter.include_docker_in_docker == "yes" %}
| Docker-in-Docker | Container builds inside the devcontainer |
{%- endif %}

{% if cookiecutter.include_docker_in_docker == "yes" -%}
Docker-in-Docker keeps its own image store in a volume that grows unnoticed —
`docker system df` does not count it. Prune it periodically from inside the
container with `docker system prune -a`.
{%- endif %}

## Layout this assumes

| Setting | Value | Where |
|---|---|---|
| Python source (`PYTHONPATH`) | `{{ cookiecutter.backend_src_dir }}/` | `devcontainer.json` -> `containerEnv` |
| Frontend package root | `{{ cookiecutter.frontend_dir }}/` | `devcontainer.json` -> `DEVCONTAINER_FRONTEND_DIR` |
| Backend port | `{{ cookiecutter.backend_port }}` | `devcontainer.json` -> `forwardPorts` |
| Frontend port | `{{ cookiecutter.frontend_port }}` | `devcontainer.json` -> `forwardPorts` |

`post-create.sh` runs `uv sync` when a `pyproject.toml` exists and installs
frontend dependencies when `{{ cookiecutter.frontend_dir }}/` exists. Neither is required — the
container comes up either way.

## Starting it

```bash
code .                                   # then accept "Reopen in Container"

# — or — without VS Code
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```

Host prerequisites (Colima, the devcontainer CLI, Ghostty) are covered in the
upstream [INSTRUCTIONS.md](https://github.com/kokko-ng/kokko-devcontainer/blob/main/INSTRUCTIONS.md).

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
| Azure CLI, Docker-in-Docker | `features` in `devcontainer.json`, then rebuild |
| ODBC driver | the apt layer in `Dockerfile`, then rebuild |
| Claude settings, plugin roster, `CLAUDE.md`, zsh config | edit under `.devcontainer/config/`, then `bash .devcontainer/post-create.sh --config-only` |

Rebuild: `devcontainer up --workspace-folder . --remove-existing-container`.

## Git identity

{% if cookiecutter.git_user_name and cookiecutter.git_user_email -%}
`post-create.sh` configures the git author identity on first provision:

```
{{ cookiecutter.git_user_name }} <{{ cookiecutter.git_user_email }}>
```

It only writes when the key is unset, so if you change the identity inside the
container it survives the next rebuild. To change it:

```bash
git config --global user.name "..."
git config --global user.email "..."
```
{%- else -%}
No git author identity is configured — the `git_user_name` and `git_user_email`
template answers were left empty, and the template does not guess who you are.
Commits will fail until you set one:

```bash
git config --global user.name "<your-github-username>"
git config --global user.email "<your-work-email>"
```

Re-render with those two answers filled in to have `post-create.sh` do it for you.
{%- endif %}

Do not derive these from `gh api`: `.name` is the GitHub display name rather than
the username, and the primary address is the `users.noreply.github.com` one
whenever the real address is kept private.

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
([kokko-cmds](https://github.com/kokko-ng/kokko-cmds),
[kokko-janitor](https://github.com/kokko-ng/kokko-janitor)). A plugin set to
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
built-in classifier decides which tool calls run without a prompt. Git
recoverability rests on git itself — `post-create.sh` sets `gc.reflogExpire`,
`gc.reflogExpireUnreachable`, and `gc.pruneExpire` to `never`, so committed work
is always recoverable from the reflog.

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

Bundled config changes — `CLAUDE.md`, `settings.json`, zsh config, the plugin
roster — re-apply in place with no rebuild:

```bash
bash .devcontainer/post-create.sh --config-only
```

`Dockerfile`, `devcontainer.json` `features`/`containerEnv`/`runArgs` changes
always need a rebuild.
