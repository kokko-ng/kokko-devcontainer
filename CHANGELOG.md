# Changelog

## Unreleased

### Git safety moved into the kokko-safety plugin

`git-snapshot.sh`, `guard-git.sh` and `session-git-safety.sh` now ship in
[kokko-safety](https://github.com/kokko-ng/kokko-cmds) instead of this repo, so
they are versioned, covered by a test suite, and usable outside this container.
`kokko-safety` was previously set to `false` in the bundled roster, which meant
this container ran two overlapping safety systems and had the larger one
switched off.

The trade-off is that the hooks now arrive via `claude plugin install`, which
needs network and a signed-in CLI, and `post-create.sh` deliberately continues
when that fails. Three things close that gap:

- **`verify-safety-net.sh`** — a new SessionStart hook that stays in this repo,
  wired by the bundled `settings.json` (which is merged with no network
  involved). It locates the plugin's guard, feeds it `git clean -fd`, and
  confirms the answer is `deny`. If the plugin is missing or broken it tells
  Claude the safety net is down and every git command must be treated as
  unguarded. A behavioural canary, not a file-exists check: a guard whose regex
  broke would pass the latter and protect nothing.
- **A loud provisioning summary.** A failed plugin install used to print one
  warning into the middle of a 300-line log. Failures are now collected and
  reprinted as a block at the very end, with `kokko-safety` called out
  separately — everything else missing costs a slash command, that one costs
  uncommitted work.
- **`scripts/check-plugin-roster.sh`** in CI, which resolves every enabled
  plugin against the live marketplace manifests. A plugin renamed in
  `kokko-cmds` previously broke this repo with nothing anywhere connecting the
  two.

`merge-hooks.jq` force-enables `kokko-safety` on merge. It normally defers to a
user's explicit `false`, but that particular `false` is almost certainly this
bundle's own former default, and deferring to it would silently downgrade every
existing container from protected to unprotected on the next config refresh.

`post-create.sh` also removes the three superseded hook files from
`~/.claude/hooks/` — `merge-hooks.jq` unwires them, but the files themselves
would otherwise linger as dead scripts that read as protection.

### CI

This repo had none, despite shipping a ~400-line provisioning script, a jq
program that rewrites the user's live `settings.json`, and a plugin roster that
nothing verified. Added:

- shellcheck and a parse check over every script, including `snaps`.
- JSONC validation of `devcontainer.json` (which permits comments, so plain jq
  cannot read it) and JSON validation of the bundled `settings.json`.
- `scripts/test-merge-hooks.sh` — 19 assertions on the jq merge program. Its two
  required properties, preserving the user's own hooks and being idempotent, are
  exactly the kind that hold until someone edits the program and whose failure is
  silent: a lost user hook looks like a user who never added one.
- `scripts/check-docs.sh` — asserts every repo path named in the four top-level
  documents exists, and that a short list of load-bearing claims still holds. It
  caught `GIT-SAFETY.md` describing hooks that had just moved.
- `scripts/check-plugin-roster.sh`, also triggered by a `repository_dispatch`
  from a `kokko-cmds` release.
- A weekly `devcontainer build` smoke test, so upstream drift in the Microsoft
  feature images surfaces before it interrupts a task.
- markdownlint over all documentation.

### Documentation

- `GIT-SAFETY.md` rewritten around the three layers and the new file locations.
- `INSTRUCTIONS.md` no longer claims 9 of 10 plugins are enabled with
  `kokko-safety` off.
- `README.md` describes the verifier layer.
