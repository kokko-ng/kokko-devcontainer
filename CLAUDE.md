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
`merge-settings.jq`, `prune-roster.jq`, the bundled `settings.json`,
`managed-settings.json`, the hook script under `config/claude/hooks/`, or the
settings-handling functions in `post-create.sh` gets a test in
`merge-settings-tests.sh` in the same commit. The merge runs unattended on every
container start against a settings.json the user may have edited — an untested merge
rule is how user settings get eaten.

**The prompts and their tests move together.** Any new or changed key in
`cookiecutter.json`, and any change to the hooks, gets an assertion in
`template-tests.sh` in the same commit. An option that nothing renders against is an
option that silently stops working.

## Where Jinja is allowed

| Carries Jinja | Deliberately Jinja-free |
|---|---|
| `devcontainer.json`, `Dockerfile`, all Markdown (including the generated `CLAUDE.md`), the cookiecutter hooks | `post-create.sh`, `init-host-certs.sh`, `*.jq`, the bundled `settings.json` and `managed-settings.json`, `config/claude/hooks/*.sh`, the zsh config, the generated `.gitignore` |

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

What sits around auto mode, and where each piece lives:

- **Policy** the user must not be able to override — the deny list (force-push, Azure
  delete, volume prune, ...) and the bypass-mode lock — is `managed-settings.json`,
  which `post-create.sh` installs to `/etc/claude-code/managed-settings.json`. It is
  never merged; it is replaced whole. Do not put policy into the bundled `settings.json`,
  where the merge lets the user win, and do not put user-overridable defaults into
  managed settings, where they cannot.
- **Defaults** the user may override — auto mode, the Bash tool limits in `env`, the
  sandbox block (shipped `enabled: false`), the plugin roster — are the bundled
  `settings.json`, merged additively per key.
- **The one bundled hook** is `SessionStart` only and purely informational (it prints
  the provisioning ledger). `merge-settings.jq` wires it in when absent and never
  duplicates it. It is not a guard layer and must not grow into one.
- **Docker-in-Docker** defaults to `no` because the feature runs the container
  privileged; keep that default.

## Shellcheck

CI and pre-commit both run at `--severity=info` — keep them aligned. Locally:

```bash
shellcheck --severity=info \
    "{{cookiecutter.project_slug}}/.devcontainer/post-create.sh" \
    "{{cookiecutter.project_slug}}/.devcontainer/init-host-certs.sh" \
    "{{cookiecutter.project_slug}}/.devcontainer/config/claude/hooks/session-provision-status.sh" \
    tests/merge-settings-tests.sh tests/template-tests.sh
```

## Layout — what runs where

| Path | Role |
|---|---|
| `cookiecutter.json` | Prompts, defaults, and the unrendered-copy list |
| `hooks/pre_gen_project.py` | Rejects invalid answers before anything is written |
| `hooks/post_gen_project.py` | Trims the Claude plugin roster; prints next steps |
| `{{cookiecutter.project_slug}}/DEVCONTAINER.md` | Generated per-project documentation |
| `{{cookiecutter.project_slug}}/CLAUDE.md` | Generated project instructions for Claude Code: layout, verification commands, container facts |
| `{{cookiecutter.project_slug}}/.gitignore` | Generated; keeps what the container creates (`.env`, Claude worktrees, Playwright artifacts) out of git |
| `{{cookiecutter.project_slug}}/.devcontainer/devcontainer.json` | Templated container definition; also publishes the `DEVCONTAINER_*` toggles |
| `{{cookiecutter.project_slug}}/.devcontainer/Dockerfile` | Templated image (base image, optional ODBC layer) |
| `.../config/claude/settings.json` | Bundled Claude Code defaults: Auto permission mode, Bash tool limits, sandbox (off), SessionStart hook wiring, plugin roster |
| `.../config/claude/managed-settings.json` | Policy, installed to `/etc/claude-code/`: the deny list and the bypass-mode lock |
| `.../config/claude/hooks/session-provision-status.sh` | SessionStart hook: prints failed provisioning steps into the session |
| `.../config/claude/merge-settings.jq` | Merges bundled settings/roster into a live settings.json (idempotent, preserves user settings, strips retired hook wiring) |
| `.../config/claude/prune-roster.jq` | Removes roster entries the bundle dropped, unless user-overridden |
| `.../post-create.sh` | Provisioning; `--config-only` re-applies bundled config (settings, policy, hook, CLAUDE.md, zsh) in place |
| `ghostty/config` | Host-side terminal config; not part of the template payload |
