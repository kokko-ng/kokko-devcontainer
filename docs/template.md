# Template

## Options

Pass these as `dev new NAME key=value` or to `cookiecutter`. Invalid answers (such as
a bad slug, an absolute or `..` path, a port outside 1024-65535) are rejected before
anything is written.

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

The `kokko-ng` roster installs these Claude Code plugins on first start, and refreshes
them at most once a day after:

| Marketplace | Plugins |
|---|---|
| [kokko-skills](https://github.com/kokko-ng/kokko-skills) | kokko-git, kokko-viz, kokko-infra, kokko-ai-config, kokko-notifications, kokko-validation, kokko-env |
| [kokko-claude-mods](https://github.com/kokko-ng/kokko-claude-mods) | theme-sync |

Edit `enabledPlugins` in `.devcontainer/config/claude/settings.json`; `false` means never
installed. `KOKKO_PLUGIN_REFRESH=1` forces a refresh, `KOKKO_SKIP_PLUGINS=1` skips it.
Code quality is enforced by each repo's pre-commit config, not a plugin;
kokko-code-quality and kokko-janitor are uninstalled from existing containers on their
next start.

## The generated project

| Path | Holds |
|---|---|
| `.devcontainer/` | The container: `devcontainer.json`, `Dockerfile`, `post-create.sh`, the firewall, bundled config under `config/` |
| `DEVCONTAINER.md` | This project's container: tools, volumes, security, what to change where |
| `CLAUDE.md` | Instructions for Claude Code: layout, verification commands, container facts |
| `.gitignore` | Keeps `.env`, Claude worktrees and Playwright artifacts out of git |
| `.pre-commit-config.yaml`, `pyproject.toml`, `scripts/hooks/`, `.github/workflows/ci.yml` | The quality gate, its thresholds, its check scripts, and the CI that re-runs it |
| `<backend_src_dir>/<package>/`, `tests/` | A starter package and test, so the gate has code to check; replace them |

On create, provisioning installs the tools, applies the bundled config, runs `uv sync`
when `pyproject.toml` exists, installs frontend dependencies when the frontend folder
exists, installs pre-commit hooks when `.pre-commit-config.yaml` exists, and copies
`.env.example` to `.env` when there is no `.env`. On every start it re-applies the bundled config (settings
merge, policy, plugins, git, zsh), the firewall and the sudo lock. The logs are
`/tmp/post-create.log` and `/tmp/post-start.log`; failed steps are listed at the start of
each Claude Code session.

## Quality gate

Provisioning installs the pre-commit hooks for three stages:

- **Commit:** gitleaks, file hygiene, shellcheck, ruff (with bandit rules, complexity
  and docstrings), mypy `--strict`, vulture, deptry, file length, test assertions,
  pytest with at least 95% coverage, Markdown links, the frontend's `typecheck`, `lint`
  and `test` scripts once it has a `package.json`, actionlint and zizmor. Commitizen
  checks the message (Conventional Commits).
- **Push:** Trivy, through a local `trivy` or Docker; it skips inside the container.
- **CI:** every commit-stage hook on every file, every commit message, and Trivy.

`scripts/hooks/check_strictness.py` fails if a threshold in `pyproject.toml` is
loosened. The Python hooks run through `uv run --frozen`, so commit the `uv.lock` the
first `uv sync` writes. The project's `DEVCONTAINER.md` has the exact limits.

## Using the template directly

Into an existing project, generate elsewhere and copy in. Answer the prompts with the
project's real layout (source dir, frontend dir, ports).

```bash
uvx cookiecutter gh:kokko-ng/kokko-devcontainer -o /tmp
cp -r /tmp/<slug>/.devcontainer ~/code/your-project/
cp /tmp/<slug>/CLAUDE.md ~/code/your-project/       # or merge into yours
cat /tmp/<slug>/.gitignore >> ~/code/your-project/.gitignore
```

The quality gate files (above) can be copied the same way and merged by hand.

A pinned release: `uvx cookiecutter gh:kokko-ng/kokko-devcontainer --checkout v<VERSION>`,
or `/devcontainer-update --ref v<VERSION>` in an existing project.
