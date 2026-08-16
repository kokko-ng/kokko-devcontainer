# CLAUDE.md — working ON this repo

This file is for agents (and humans) changing kokko-devcontainer itself. The bundled
`{{cookiecutter.project_slug}}/.devcontainer/config/claude/CLAUDE.md` is a different file
— it is what gets installed INTO containers.

## This repo is a cookiecutter template

Everything a generated project receives lives under `{{cookiecutter.project_slug}}/`.
There is no `.devcontainer/` at the repo root. To work inside a container, render first:

```bash
cookiecutter . --no-input -o .rendered
```

## Tests

```bash
bash tests/merge-settings-tests.sh   # bash + jq
bash tests/template-tests.sh         # bash + jq + python3 + cookiecutter
```

No framework — two scripts. CI runs both on every push.

**The settings pipeline and its tests move together.** Any change to
`merge-settings.jq`, `prune-roster.jq`, or the settings-handling functions in
`post-create.sh` gets a test in `merge-settings-tests.sh` in the same commit. The merge
runs unattended on every container start against a settings.json the user may have
edited — an untested merge rule is how user settings get eaten.

**The prompts and their tests move together.** Any new or changed key in
`cookiecutter.json`, and any change to the hooks, gets an assertion in
`template-tests.sh` in the same commit. An option that nothing renders against is an
option that silently stops working.

## Where Jinja is allowed

| Carries Jinja | Deliberately Jinja-free |
|---|---|
| `devcontainer.json`, `Dockerfile`, all Markdown, the hooks | `post-create.sh`, `init-host-certs.sh`, `*.jq`, the bundled `settings.json`, the zsh config |

This split is load-bearing, not stylistic. The Jinja-free files stay shellcheck-clean,
`jq`-parseable and directly testable with no rendering step, which is why
`merge-settings-tests.sh` still needs nothing but bash and jq. Do not "simplify" a
`DEVCONTAINER_*` environment toggle into a template conditional.

The mechanism instead: options that `post-create.sh` needs are published as
`DEVCONTAINER_*` variables in `devcontainer.json`'s `containerEnv`, and the script reads
them with defaults (`INSTALL_COPILOT_CLI`, `INSTALL_PLAYWRIGHT`, `FRONTEND_DIR` at the
top of the file). Anything the bundled `settings.json` needs is done as JSON surgery in
`hooks/post_gen_project.py`.

Files listed in `cookiecutter.json`'s `_copy_without_render` are copied byte-for-byte;
`template-tests.sh` asserts that. Add a file there if it might ever contain `{{` or `{%`.

## Permission model

Claude Code runs in **Auto mode** (`permissions.defaultMode: "auto"` in the bundled
settings.json): the built-in classifier decides which tool calls run without a prompt.
There is no bespoke guard/snapshot hook layer any more; do not add PreToolUse git
hooks back without an explicit decision to revisit that. The retired layer's cleanup
lives in `retire_git_safety_layer` (post-create.sh) and the strip/migration clauses of
`merge-settings.jq` — keep those until old containers can be assumed gone.

## Shellcheck

CI and pre-commit both run at `--severity=info` — keep them aligned. Locally:

```bash
shellcheck --severity=info \
    "{{cookiecutter.project_slug}}/.devcontainer/post-create.sh" \
    "{{cookiecutter.project_slug}}/.devcontainer/init-host-certs.sh" \
    tests/merge-settings-tests.sh tests/template-tests.sh
```

## Layout — what runs where

| Path | Role |
|---|---|
| `cookiecutter.json` | Prompts, defaults, and the unrendered-copy list |
| `hooks/pre_gen_project.py` | Rejects invalid answers before anything is written |
| `hooks/post_gen_project.py` | Trims the Claude plugin roster; prints next steps |
| `{{cookiecutter.project_slug}}/DEVCONTAINER.md` | Generated per-project documentation |
| `{{cookiecutter.project_slug}}/.devcontainer/devcontainer.json` | Templated container definition; also publishes the `DEVCONTAINER_*` toggles |
| `{{cookiecutter.project_slug}}/.devcontainer/Dockerfile` | Templated image (base image, optional ODBC layer) |
| `.../config/claude/settings.json` | Bundled Claude Code defaults: Auto permission mode + plugin roster |
| `.../config/claude/merge-settings.jq` | Merges bundled settings/roster into a live settings.json (idempotent, preserves user settings, strips retired hook wiring) |
| `.../config/claude/prune-roster.jq` | Removes roster entries the bundle dropped, unless user-overridden |
| `.../post-create.sh` | Provisioning; `--config-only` re-applies bundled config in place |
| `ghostty/config` | Host-side terminal config; not part of the template payload |
