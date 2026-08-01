# Git safety

How this container stops an agent from destroying your uncommitted work, and how to get it
back if something does.

---

## The problem

`git rebase`, `reset`, `checkout <ref> -- <path>`, `restore`, `stash` and `clean` all
overwrite tracked files with **no prompt and no confirmation**.

For *committed* work that is survivable — the reflog has it. For **uncommitted** work it is
terminal. Changes sitting in the working tree were never turned into a git object, so:

- there is no reflog entry,
- there is no dangling blob,
- `git fsck` will not find it,
- and no amount of expertise will bring it back.

It is simply gone.

This is not hypothetical. On projects using this container it has happened repeatedly, and
always the same way: an agent rewrote history while uncommitted work sat in the tree.
Rebase-and-push is a *documented, routine step* in many agent workflows — so the agent is
not being reckless, and it will not hesitate. One recovery only succeeded because the work
had been deployed and could be dug back out of container images. That was luck.

The lesson: **an instruction not to do it is not a control.** Written rules had already
been in place. They were followed right up until the moment an agent's own workflow said
"now rebase".

---

## The two layers

### 1. Snapshots — `refs/snapshots/`

`.devcontainer/config/claude/hooks/git-snapshot.sh` runs before every git command and on
every prompt. If the tree has uncommitted tracked changes, it checkpoints them to
`refs/snapshots/<timestamp>-<oid>`.

The mechanism is `git stash create`, which builds a commit from the current changes
**without touching the working tree, the index, or the stash ref**. Pointing a ref at that
commit turns your uncommitted work into a first-class git object — which means it now
survives every destructive command, because those commands only destroy things that were
never objects in the first place.

This layer does not need to predict anything. It doesn't matter whether the destruction
comes from `git reset`, a shell script, a Python subprocess, or a command nobody thought
to add to a blocklist — the work is already safe before any of it runs.

```bash
snaps                    # list, newest first
snaps show <ref>         # what does this snapshot contain?
snaps diff <ref>         # how does it differ from the tree right now?
snaps restore <ref>      # apply it back (refuses if the tree is dirty)
snaps restore --into-branch <name> <ref>
                         # park the snapshot on a new branch — works even
                         # when the tree is dirty (the post-incident case)
```

**Scope:** tracked changes only. Untracked files are not captured, because
rebase/reset/checkout never touch untracked paths. `git clean` is the exception — which is
why it is blocked outright rather than dirty-gated.

The most recent 200 snapshots are kept; identical trees are de-duplicated, so a burst of
git commands does not produce a burst of refs.

### 2. The guard — `guard-git.sh`

A `PreToolUse` hook that **denies** destructive git commands. It matches `git` behind
wrapper commands (`sudo git`, `env git`, `command git`, `time`, `nohup`, `xargs`, `nice`,
`stdbuf`), behind `VAR=val` prefixes, and by absolute path (`/usr/bin/git`).

The dirty check runs against the repository the command **actually targets**: a leading
`cd <dir> &&`, a `git -C <dir>`, or a `--git-dir=<dir>` is resolved and checked there. If a
destructive command's repository cannot be resolved at all (the hook's cwd is not a repo
and the command names none), the guard **fails closed** and denies with an explanation.

**Denied only while the tree is dirty** (allowed on a clean tree, where the reflog has you
covered):

| Command | Why |
|---|---|
| `git rebase` | The one that caused every real incident |
| `git reset --hard` / `--merge` / `--keep` | Discards tracked changes (index-only resets are allowed) |
| `git checkout <ref> -- <path>`, `git checkout .` | Silently overwrites that file |
| `git checkout -f` / `git switch --discard-changes` | Forced overwrite |
| `git restore` | Overwrites from another revision (`--staged` without `--worktree` is allowed) |
| `git stash` (incl. `push`, `pop`) | Easy to forget to pop; load-bearing in past incidents |
| `git branch -f` | Silent ref clobber |

**Always denied**, tree state irrelevant:

| Command | Why |
|---|---|
| `git clean` (every form except a dry run) | Deletes untracked files — the one thing snapshots *don't* cover. `git clean --force` and long/short flag mixes are all caught |
| `git add .` / `-A` / `--all` | Stages build output, secrets, scratch files. One incident staged 4,648 files |
| `git push` with a force flag **anywhere** among its args (`-f`, `--force`, `--force-with-lease`), and the `+refspec` form (`git push origin +main`) | Rewrites the shared remote |
| `git filter-branch` / `filter-repo` | Destroys objects *and* the snapshot refs |
| `git reflog expire/delete`, `git gc --prune`, `git prune` | Destroys the recovery path itself |
| `git stash drop` / `clear` | Permanently deletes stashed work |

**Explicitly allowed — even on a dirty tree.** A conflicted rebase *is* a dirty tree, so
the commands that get you out of trouble must stay reachable, or the guard traps you
inside the very state it exists to prevent:

| Command | Why it is safe |
|---|---|
| `git rebase --abort` / `--continue` / `--skip` / `--quit` | The only exits from a conflicted rebase |
| `git reset` with no mode flag, `--soft`, `--mixed` | Index-only — never touches the working tree |
| `git restore --staged <path>` (without `--worktree`/`-W`) | Unstages; index-only |
| `git stash list` / `show` | Read-only inspection |
| `git stash apply` | The snapshot recovery path itself (`git stash apply refs/snapshots/...`) |
| `git clean -n` / `--dry-run` (dry-run flag first) | Prints, deletes nothing |

The whitelist composes safely with compound commands: `git rebase --abort && git rebase
main` is still denied, because only the recovery half is exempted.

### 3. Git config

`post-create.sh` sets, globally:

```
gc.reflogExpire           never
gc.reflogExpireUnreachable never
gc.pruneExpire            never
rerere.enabled            true
```

By default git deletes unreachable objects after 30 days and reflog entries after 90 — the
exact objects a recovery needs. Disk is cheaper than the work.

---

## Two design decisions worth knowing

**Deny, not ask.** Agents run unattended under `acceptEdits`. An "ask" either blocks a
long-running task forever or gets clicked through — and every incident involved an agent
that was *confident*, following a workflow that listed the rebase as a normal step. It
would have answered "yes".

**Dirty-gated, not blanket.** These commands are only catastrophic against a dirty tree,
so that is when they are blocked. This is not leniency — it is what keeps the guard alive.
A guard that fires on every routine rebase is noise, and noise gets switched off. That is
not speculation: this repo previously enabled a safety plugin that warned on ~30 git
patterns via "ask", and it had been **disabled** in `settings.json` — protecting nothing at
the moment it was needed. A control you turn off is worse than no control, because you
think you have one.

---

## Override

```bash
CLAUDE_GIT_GUARD=off git rebase main    # per command
```

Deliberately verbose and greppable. It is for **humans**, not agents — the bundled
`CLAUDE.md` tells Claude that a block means commit or ask the user, never work around it.

A bypassed command is **not silent**: the guard emits a `systemMessage` record
("GIT GUARD BYPASSED: ...") into the transcript, so a bypass is visible after the fact
instead of looking identical to a guard that never ran.

Because snapshots run independently of the guard, even an overridden command is still
recoverable. That is the point of having two layers.

**Disabling the layer entirely.** Removing the `hooks` block from `~/.claude/settings.json`
does *not* stick: `post-create.sh` re-merges the hook wiring on every container rebuild
**and** on every container start (`postStartCommand` runs `--config-only`). The real off
switch is the environment variable the script honors:

```jsonc
// devcontainer.json
"containerEnv": { "KOKKO_NO_GIT_HOOKS": "1" }
```

With `KOKKO_NO_GIT_HOOKS=1` set, post-create neither installs the hook scripts nor merges
the wiring. It does not remove entries that are already merged — delete the
`~/.claude/hooks/*` entries from `settings.json` once after setting it. Please consider
not doing any of this.

---

## Known limitations

The guard is a regex over a shell command string, not a shell parser. Residual gaps,
deliberately accepted:

- **Quoted strings containing `(`/`{` before `git`.** The command-position anchor treats
  `(` and `{` as operators, so prose like `echo "see (git reset --hard) docs"` can still
  false-positive **for non-whitelisted patterns**. (`echo "recover with (git stash apply
  ref)"` passes, because `stash apply` is whitelisted.) The cost of a false positive is a
  blocked echo; the cost of loosening the anchor is a missed subshell — the anchor stays.
- **`git clean` dry runs are only recognized with the dry-run flag first** (`git clean -n`,
  `-nd`, `--dry-run`). `git clean -f -n` is denied even though `-n` would win — over-deny,
  by design.
- **Indirection is invisible.** git run from a script, Makefile, or Python subprocess never
  passes through the hook. That is what the snapshot layer is for: it checkpoints on every
  prompt regardless of how the destruction arrives.
- **Restore whitelisting is conservative:** any `--worktree`/`-W` anywhere in the command
  disables the `restore --staged` exemption for the whole command.

## Residual risk — read this if you widen the container's reach

The bundled setup leans hard on this hook layer. The `ccc` alias runs Claude with
`--permission-mode bypassPermissions`, and the bundled `settings.json` sets
`skipDangerousModePermissionPrompt`, so the permission system is **out of the loop** —
PreToolUse hooks are the *only* automated control on git commands. The container also has
docker-in-docker, and the optional `~/.azure` mount hands it live cloud credentials.
Combine all of that and a misbehaving agent is one hook bug away from acting on your
remotes and your cloud. Keep the optional mounts off unless you need them, and treat the
hook layer as a seatbelt, not a roll cage: commits, pushes-on-request-only, and small
blast radii are still the real controls.

---

## If work has gone missing

1. **`snaps`** — look here first, before any archaeology, and before concluding it is lost.
2. `snaps show <ref>` to confirm you have the right checkpoint.
3. Commit or park anything currently in the tree, then `snaps restore <ref>`.
4. If it predates the snapshot hooks: check `git fsck --lost-found` and `git reflog` for
   anything that was ever committed. If it was never committed and never snapshotted, it is
   gone — that is exactly the outcome this exists to prevent.

---

## Files

| Path | Role |
|---|---|
| `.devcontainer/config/claude/hooks/git-snapshot.sh` | Checkpoints the tree |
| `.devcontainer/config/claude/hooks/guard-git.sh` | Blocks destructive commands |
| `.devcontainer/config/claude/hooks/session-git-safety.sh` | States the rules at session start |
| `.devcontainer/config/claude/merge-hooks.jq` | Splices hooks into an existing `settings.json` |
| `.devcontainer/config/bin/snaps` | Browse/restore snapshots |
| `.devcontainer/config/claude/CLAUDE.md` | The advisory layer |
| `tests/guard-git-tests.sh` | Regression table tests for all of the above (run in CI) |

Hooks are reinstalled on every container rebuild, and the wiring is merged into
`settings.json` rather than overwriting it — so your own hooks and settings survive, and
re-running never stacks duplicates.
