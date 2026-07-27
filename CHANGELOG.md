# Changelog

## Unreleased

### All deterministic command blocking removed

The `kokko-safety` guards are gone upstream (kokko-cmds 5.0.0), and this repo's
documentation and tooling follow. **No command is blocked or prompted anywhere in
this container any more.** `CLAUDE_GIT_GUARD` and its siblings no longer exist,
because there is nothing to override.

What remains, and why it is enough to work with:

- **`refs/snapshots/`** — the snapshot layer, unchanged. It is now the *only*
  mechanism between an agent's rebase and permanently lost work.
- **`snaps`** — unchanged, still installed onto PATH by `post-create.sh`.
- **The briefing** — the bundled `CLAUDE.md` keeps every work-loss rule and now
  opens by stating that *nothing stops you*: no guard hook, no blocked-command
  list, no confirmation prompt. It also spells out that snapshots are a recovery
  mechanism rather than a control, that they cover tracked changes only, and that
  `git clean` therefore has no recovery path at all.

Changed:

- **`verify-safety-net.sh` now verifies the snapshot layer** instead of the guard.
  Its old canary fed `git clean -fd` to `guard-git.sh` and checked for a `deny`;
  that hook no longer exists. It now builds a throwaway repository with one known
  uncommitted line, runs the real `git-snapshot.sh` against it, and confirms a ref
  appeared under `refs/snapshots/` containing that line. This matters more than it
  did before: a snapshot hook whose `jq` is missing, or whose git calls fail on a
  bind-mount ownership refusal, exits 0 and prints nothing — indistinguishable
  from a clean tree.
- **`merge-hooks.jq`** still force-enables `kokko-safety`, with the reasoning
  updated: the stale `false` it corrects would now disable the last remaining
  safety mechanism rather than a set of noisy guards.
- **`GIT-SAFETY.md`** rewritten. It no longer lists blocked commands; it explains
  why a blocklist is the wrong shape — too broad (the last revision had to be
  taught that `docker image prune -a`, the command this repo's own disk warning
  recommends, is not destructive, and that `git stash create` is what the snapshot
  layer is built on) and too narrow (a `git reset --hard` from inside a script or
  a Python subprocess was always invisible to it).
- **`README.md`** describes snapshots, briefing and verifier rather than
  snapshots, guard and verifier.

Added to `scripts/check-docs.sh`:

- No document except `GIT-SAFETY.md` may mention a `CLAUDE_*_GUARD` override, a
  `guard-*.sh` hook, or `dangerous-patterns` — promising a control that does not
  exist is worse than documenting nothing.
- `CLAUDE.md` must state that nothing blocks, and must not claim commands are
  blocked.

Added to `scripts/test-merge-hooks.sh` (now 23 assertions): the bundled
`settings.json` must wire no `PreToolUse` hook at all, and exactly one hook
overall. A `PreToolUse` entry reappearing would mean a guard had crept back in.

### Git safety moved into the kokko-safety plugin

`git-snapshot.sh`, `guard-git.sh` and `session-git-safety.sh` now ship in
[kokko-safety](https://github.com/kokko-ng/kokko-cmds) instead of this repo, so
they are versioned, covered by a test suite, and usable outside this container.
`kokko-safety` was previously set to `false` in the bundled roster, which meant
this container ran two overlapping safety systems and had the larger one
switched off. (The guards that motivated moving them have since been removed
entirely — see above.)

The trade-off is that the hooks now arrive via `claude plugin install`, which
needs network and a signed-in CLI, and `post-create.sh` deliberately continues
when that fails. Three things close that gap:

- **`verify-safety-net.sh`** — a new SessionStart hook that stays in this repo,
  wired by the bundled `settings.json` (which is merged with no network
  involved). See the section above for what it checks.
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
