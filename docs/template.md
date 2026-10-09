# Template

## Options

Pass these as `dev new NAME key=value` or to `cookiecutter`. Invalid answers are rejected
before anything is written.

| Option | Default | Effect |
|---|---|---|
| `project_name` | `My Project` | Headings; the slug derives from it |
| `python_version` | `3.14` | Base image (`3.13`, `3.12`). Only `3.14` is digest-pinned |
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

## Plugin roster

`kokko-ng` installs kokko-git, kokko-viz, kokko-infra, kokko-ai-config,
kokko-notifications, kokko-validation and kokko-env from
[kokko-skills](https://github.com/kokko-ng/kokko-skills), and theme-sync from
[kokko-claude-mods](https://github.com/kokko-ng/kokko-claude-mods). They refresh at most
once a day. Set a plugin to `false` in `enabledPlugins` in
`.devcontainer/config/claude/settings.json` to never install it. `KOKKO_PLUGIN_REFRESH=1`
forces a refresh, `KOKKO_SKIP_PLUGINS=1` skips it.

## The generated project

Besides `.devcontainer/`, a project gets `DEVCONTAINER.md` (its tools, volumes and what
to change where), `CLAUDE.md` (instructions for Claude Code), a `.gitignore`, the quality
gate below, and a starter package and test to replace. Provisioning runs `uv sync`,
installs frontend dependencies and the pre-commit hooks, and copies `.env.example` to
`.env`. Every start re-applies the bundled config, the firewall and the sudo lock. Logs:
`/tmp/post-create.log`, `/tmp/post-start.log`.

## Quality gate

`.pre-commit-config.yaml` runs on commit (gitleaks, ruff, mypy `--strict`, vulture,
deptry, file length, pytest with 95% coverage, the frontend's checks, commitizen) and on
push (Trivy). `.github/workflows/ci.yml` re-runs it. `scripts/hooks/check_strictness.py`
fails if a threshold in `pyproject.toml` is loosened. Commit the `uv.lock` the first
`uv sync` writes: the hooks run with `uv run --frozen`.

## Using the template directly

For an existing project, generate elsewhere and copy in, answering with the project's
real layout:

```bash
uvx cookiecutter gh:kokko-ng/kokko-devcontainer -o /tmp
cp -r /tmp/<slug>/.devcontainer ~/code/your-project/
cp /tmp/<slug>/CLAUDE.md ~/code/your-project/       # or merge into yours
cat /tmp/<slug>/.gitignore >> ~/code/your-project/.gitignore
```

Merge the quality gate files in by hand. For a pinned release, add `--checkout v<VERSION>`,
or run `/devcontainer-update --ref v<VERSION>` in an existing project.
