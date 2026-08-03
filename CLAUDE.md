# CLAUDE.md — working ON this repo

This file is for agents (and humans) changing kokko-devcontainer itself. The bundled
`.devcontainer/config/claude/CLAUDE.md` is a different file — it is what gets installed
INTO containers.

## Tests

```bash
bash tests/guard-git-tests.sh
```

One script, ~150 assertions, no framework — needs only bash, jq, git. It feeds real hook
payloads through the actual hook scripts and checks deny/allow decisions, merge semantics,
and the snaps roundtrip. CI runs it on every push.

**Hooks and tests move together.** Any change to a file under
`.devcontainer/config/claude/hooks/` or to `merge-hooks.jq` / `prune-roster.jq` gets a
test in the same commit: a denial test for every new deny rule, a benign look-alike allow
where one exists, and a regression test for every bypass fixed. An untested guard rule is
how bypasses come back.

## Shellcheck

CI and pre-commit both run at `--severity=info` — keep them aligned. Locally:

```bash
shellcheck --severity=info .devcontainer/post-create.sh \
    .devcontainer/config/bin/snaps .devcontainer/config/claude/hooks/*.sh \
    tests/guard-git-tests.sh
```

## Layout — what runs where

| Path | Role |
|---|---|
| `.devcontainer/config/claude/hooks/guard-git.sh` | PreToolUse hook: denies destructive git (dirty-gated + always-deny) |
| `.devcontainer/config/claude/hooks/git-snapshot.sh` | PreToolUse/UserPromptSubmit hook: checkpoints tracked changes to `refs/snapshots/` |
| `.devcontainer/config/claude/hooks/session-git-safety.sh` | SessionStart hook: states the safety contract |
| `.devcontainer/config/claude/hooks/lib-git-target.sh` | **Not a hook.** Shared target-repo resolution, sourced by guard and snapshot — the two must never disagree about which repo a command touches. Fixes to target parsing go here, once |
| `.devcontainer/config/claude/merge-hooks.jq` | Splices hook wiring + roster into a live settings.json (idempotent, preserves user hooks) |
| `.devcontainer/config/claude/prune-roster.jq` | Removes roster entries the bundle dropped, unless user-overridden |
| `.devcontainer/config/bin/snaps` | Human CLI over the snapshot refs |
| `.devcontainer/post-create.sh` | Provisioning; `--config-only` re-applies bundled config in place |

`post-create.sh` copies `hooks/*.sh` into `~/.claude/hooks/` — a new file in that
directory ships automatically, but only registered hooks belong in the bundled
`settings.json`.

## The one document that matters

Read [GIT-SAFETY.md](GIT-SAFETY.md) before touching anything in `hooks/`. It explains why
the guard denies instead of asks, why rules are dirty-gated, and which recovery commands
must stay reachable. Changes that make the guard noisier on routine commands get it
switched off — that failure mode is documented there and it is the one to avoid.
