# CLAUDE.md — working ON this repo

This file is for agents (and humans) changing kokko-devcontainer itself. The bundled
`.devcontainer/config/claude/CLAUDE.md` is a different file — it is what gets installed
INTO containers.

## Tests

```bash
bash tests/merge-settings-tests.sh
```

One script, no framework — needs only bash and jq. It exercises the settings pipeline:
`merge-settings.jq` (user hooks and choices preserved, retired git-safety wiring
stripped, the acceptEdits → auto migration, idempotency) and `prune-roster.jq` (bundle
drops are pruned unless user-overridden). CI runs it on every push.

**The settings pipeline and its tests move together.** Any change to
`merge-settings.jq`, `prune-roster.jq`, or the settings-handling functions in
`post-create.sh` gets a test in the same commit. The merge runs unattended on every
container start against a settings.json the user may have edited — an untested merge
rule is how user settings get eaten.

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
shellcheck --severity=info .devcontainer/post-create.sh \
    .devcontainer/init-host-certs.sh tests/merge-settings-tests.sh
```

## Layout — what runs where

| Path | Role |
|---|---|
| `.devcontainer/config/claude/settings.json` | Bundled Claude Code defaults: Auto permission mode + plugin roster |
| `.devcontainer/config/claude/merge-settings.jq` | Merges bundled settings/roster into a live settings.json (idempotent, preserves user settings, strips retired hook wiring) |
| `.devcontainer/config/claude/prune-roster.jq` | Removes roster entries the bundle dropped, unless user-overridden |
| `.devcontainer/post-create.sh` | Provisioning; `--config-only` re-applies bundled config in place |
