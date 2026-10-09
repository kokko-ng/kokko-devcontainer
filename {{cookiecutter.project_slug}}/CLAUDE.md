# {{ cookiecutter.project_name }}

Project notes for Claude Code. The container-wide rules live in `~/.claude/CLAUDE.md`
(installed from `.devcontainer/config/claude/CLAUDE.md`); this file covers what is
specific to this project and to the container it runs in. Keep it accurate when the
layout or the verification commands change — it is the first thing an agent reads.

## Layout

| What | Where |
|---|---|
| Python backend | `{{ cookiecutter.backend_src_dir }}/` — on `PYTHONPATH`; run everything through `uv run` |
| Frontend | `{{ cookiecutter.frontend_dir }}/` — Node {{ cookiecutter.node_version }}; use `npm --prefix {{ cookiecutter.frontend_dir }} ...` from the repo root |
| Backend port | {{ cookiecutter.backend_port }} |
| Frontend dev server | {{ cookiecutter.frontend_port }} |

## Verify before claiming done

Run the gate, and fix what fails rather than reporting it:

```bash
pre-commit run --all-files          # every commit-stage hook, as CI runs it
uv run pytest                       # backend tests alone
npm --prefix {{ cookiecutter.frontend_dir }} run build   # frontend production build, once it exists
```

Long commands are fine here: the Bash tool waits 10 minutes by default and up to 30
when you ask for it, so run the full suite instead of a subset.

## Quality gate

`.pre-commit-config.yaml` runs at commit (secrets, hygiene, shellcheck, ruff, mypy
`--strict` with no `Any` in production code, vulture, deptry, file length, test
assertions, pytest with coverage at least 95%, Markdown links, the frontend's
`typecheck`/`lint`/`test` scripts, actionlint, zizmor), checks the commit message
(Conventional Commits, `type(scope): subject`), and runs Trivy before a push. CI runs
the same hooks on every file, checks every commit message, and runs Trivy.

- Never bypass it: no `--no-verify`, no `SKIP=`. Fix the code, not the gate.
- Do not loosen a setting in `pyproject.toml` to pass; `check_strictness.py` fails if
  you do. No `# noqa`, `# type: ignore` or coverage pragma unless the finding is a
  genuine false positive, with the reason on the same line.
- Code that only a test calls is dead code to vulture: wire it in or delete it.
- Python tools run through `uv run --frozen`: after `uv add`, commit `uv.lock` too.
- A test asserts behaviour that matters; never write one only to raise coverage.

## This is a devcontainer

- The workspace is a bind mount from macOS. It is usually case-insensitive: two paths
  that differ only in case are the same file, so a case-only rename needs an
  intermediate name. Large trees (`node_modules`, `.venv`) are slower here than on a
  native disk.
- Provisioning output is in `/tmp/post-create.log`. Steps that failed are listed in
  `~/.devcontainer-provision-status`, and a SessionStart hook shows you that file when
  it is non-empty. `bash .devcontainer/post-create.sh` re-runs provisioning;
  `bash .devcontainer/post-create.sh --config-only` re-applies the bundled Claude and
  shell config in seconds.
- Available: Python {{ cookiecutter.python_version }} + uv, Node {{ cookiecutter.node_version }}, gh, pre-commit, shellcheck, jq
  {%- if cookiecutter.include_azure_cli == "yes" %}, az{% endif %}
  {%- if cookiecutter.include_docker_in_docker == "yes" %}, docker (a nested daemon — the container runs privileged for it, so treat the whole VM as in scope){% endif %}
  {%- if cookiecutter.include_playwright == "yes" %}, playwright-cli with Chromium{% endif %}
  {%- if cookiecutter.include_copilot_cli == "yes" %}, copilot{% endif %}.
  Host CA certificates are trusted, so `curl`, `pip` and `npm` work behind a corporate
  proxy.
- Temporary files, scratch scripts and test artifacts go in `/tmp`, not the repo.

## Permissions

Claude Code runs in Auto mode. A managed deny list in
`/etc/claude-code/managed-settings.json` blocks the irreversible operations: force-push,
`git reflog expire`, Azure `delete` and `purge`, Docker volume pruning, `gh repo delete`.
A denied command was denied on purpose — report it and ask, do not look for another
spelling of the same operation. Bypass mode is disabled.
{%- if cookiecutter.agent_sudo == "yes" %} The container user keeps passwordless sudo.
{%- elif cookiecutter.network_firewall == "on" %} There is no sudo beyond
`sudo devcontainer-firewall`.
{%- else %} There is no sudo.{% endif %}
{%- if cookiecutter.network_firewall == "on" %} An outbound
firewall limits the container to the hosts in `.devcontainer/firewall/allowed-domains.txt`;
"No route to host" for anything else is the firewall — name the host and let the user
add it.{% endif %}

## Git

- The author identity is preconfigured (the template's answers, or the host's own git
  identity); commit as it, never as yourself.
- {% if cookiecutter.claude_attribution == "yes" -%}
  Claude Code adds its own `Co-Authored-By` trailer; do not add another by hand.
  {%- elif cookiecutter.claude_attribution == "host" -%}
  Whether Claude Code adds its `Co-Authored-By` trailer follows `attribution` in
  `~/.claude/settings.json`; never add one by hand.
  {%- else -%}
  Claude Code's `Co-Authored-By` trailer is switched off for this project; do not add
  one by hand.
  {%- endif %}
- The reflog never expires, so committed work is always recoverable — commit early and
  often.
- `safe.directory` is `*` in this container, so git works in the bind-mounted workspace
  and in worktrees. Worktrees created with `claude --worktree` live in
  `.claude/worktrees/` and are gitignored.
- pre-commit is installed in the image and its hooks are installed on provision (see
  "Quality gate").
