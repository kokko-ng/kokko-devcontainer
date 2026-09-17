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

Run whichever of these the project defines, and fix what fails rather than reporting it:

```bash
# Lint and formatting
uv run ruff check . && uv run ruff format --check .
# Backend tests
uv run pytest
# Frontend lint, tests, production build
npm --prefix {{ cookiecutter.frontend_dir }} run lint
npm --prefix {{ cookiecutter.frontend_dir }} test
npm --prefix {{ cookiecutter.frontend_dir }} run build
# The hooks that gate every commit
pre-commit run --files <changed files>
```

Long commands are fine here: the Bash tool waits 10 minutes by default and up to 30
when you ask for it, so run the full suite instead of a subset.

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

## Git

- The author identity is preconfigured. The reflog never expires, so committed work is
  always recoverable — commit early and often.
- `safe.directory` is `*` in this container, so git works in the bind-mounted workspace
  and in worktrees. Worktrees created with `claude --worktree` live in
  `.claude/worktrees/` and are gitignored.
- pre-commit is installed in the image and its hooks are installed on provision. Never
  bypass them.
