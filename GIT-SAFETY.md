# Git safety

How to get your uncommitted work back when an agent destroys it.

Note the framing: this container does **not** stop it happening. There is no guard hook and
no blocked-command list — [section 2](#2-there-is-no-guard--and-that-is-deliberate) explains
why. What it does is make the work recoverable, and tell the agent plainly that nothing will
refuse it.

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

## How it works

### 1. Snapshots — `refs/snapshots/`

`git-snapshot.sh`, from the **kokko-safety** plugin, runs before every git command and on
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
```

**Scope:** tracked changes only. Untracked files are not captured, because
rebase/reset/checkout never touch untracked paths. `git clean` is the exception, and since
nothing blocks it either, it is the one destructive command with **no recovery path at
all**. The bundled `CLAUDE.md` tells Claude never to run it.

The most recent 200 snapshots are kept; identical trees are de-duplicated, so a burst of
git commands does not produce a burst of refs.

### 2. There is no guard — and that is deliberate

Earlier versions of this container ran a `PreToolUse` hook that **denied** destructive git
commands, backed by roughly 1,300 regex patterns across git, cloud and shell categories.
It is gone. Nothing is refused; nothing prompts.

A blocklist is the wrong shape for this problem, in both directions at once.

**Too broad.** It has to guess which spellings are dangerous from the command text, and it
guesses wrong constantly. The last revision of it had to be taught that `rm -rf ./dist`,
`rm -rf node_modules`, `sudo apt-get install`, `pip uninstall`, `docker image prune -a`,
`git worktree remove` and `git stash create` are all routine — and it only learned because
a test suite went looking. `docker image prune -a` is the command this repo's own disk
warning tells you to run. `git stash create` is the mechanism the snapshot layer is built
on: the guard was blocking its own safety net.

**Too narrow.** Anything not on the list passes. The same `git reset --hard` invoked from a
shell script, a Makefile target, a `subprocess.run(...)` call or a tool that shells out is
completely invisible to a hook that inspects Bash command strings. A blocklist protects
against the spelling, not the operation.

The first failure mode is the one that actually cost protection. A guard that fires on
routine work gets switched off — and switching it off takes the snapshot layer with it,
because they were the same plugin. That is not hypothetical: this repo previously enabled a
safety plugin that warned on ~30 git patterns via "ask", and it had been **disabled** in
`settings.json`, protecting nothing at the moment it was needed. A control you turn off is
worse than no control, because you think you have one.

So the design is now: **one mechanism that cannot be wrong, plus an explicit briefing.**
The snapshot layer does not need to predict which command is dangerous, or notice that git
was invoked from Python — by the time anything runs, the work is already a git object. What
it cannot do is stop the damage, which is why the bundled `CLAUDE.md` states the rules
directly and says that nothing will refuse them.

### 3. The verifier — `verify-safety-net.sh`

With no guard, snapshots are the *only* mechanism between a rebase and permanently lost
work — so it matters much more that they are verified rather than assumed.

They ship in the [kokko-safety](https://github.com/kokko-ng/kokko-cmds) plugin rather than
in this repo, so they are versioned, tested in CI, and usable outside this container. The
cost is that they arrive via `claude plugin install`, which needs network and a signed-in
CLI — and `post-create.sh` is deliberately allowed to continue when that fails, so a
transient outage cannot break the container build.

That trade would be unacceptable on its own, because a safety net that fails silently is
worse than none. So this repo keeps one small hook that does not depend on the plugin
install succeeding. `verify-safety-net.sh` is wired by the bundled `settings.json` and runs
at every session start.

It is a **behavioural** canary, not a file-exists check: a snapshot hook whose `jq`
dependency is missing, or whose git calls are failing on a bind-mount ownership refusal,
exits 0 and prints nothing — indistinguishable from a clean tree. So the verifier builds a
throwaway repository with one known uncommitted line, runs the real hook against it, and
confirms a ref appeared under `refs/snapshots/` containing that line. If the plugin is
missing, or present but not working, it tells Claude the net is down and that committing is
the only protection available.

### 4. Git config

`post-create.sh` sets, globally:

```ini
gc.reflogExpire           never
gc.reflogExpireUnreachable never
gc.pruneExpire            never
rerere.enabled            true
```

By default git deletes unreachable objects after 30 days and reflog entries after 90 — the
exact objects a recovery needs. Disk is cheaper than the work.

---

## Two design decisions worth knowing

**Recover, don't predict.** A blocklist has to know in advance which command will destroy
your work. A snapshot does not: it makes the work durable before anything runs, so it is
equally effective against `git reset`, a shell script, a Python subprocess, and a command
nobody thought of. One mechanism, no enumeration, no false positives.

**Brief, don't block.** With no guard, the advisory layer *is* the control, so it is
written to be acted on rather than skimmed: it states that nothing will refuse a command,
names the specific commands and the specific checks, and says what to do instead. Two
copies exist so that neither can silently vanish — the bundled `CLAUDE.md`, and the
plugin's `session-context` hook, which does not depend on a file the user might replace
with their own.

---

## Turning it off

There is nothing to bypass — no command is refused, so no override exists. The
`CLAUDE_GIT_GUARD` escape hatch was removed along with the guard.

To disable the snapshots themselves, set `kokko-safety@kokko-ng-kokko-cmds` to `false` in
`~/.claude/settings.json` *after* a config refresh — `merge-hooks.jq` force-enables that one
key on merge, because the value it is correcting was this bundle's own former default rather
than a considered choice.

That leaves nothing at all between an agent and your uncommitted work. Please consider not
doing that.

---

## If work has gone missing

1. **`snaps`** — look here first, before any archaeology, and before concluding it is lost.
   If `snaps` is not on PATH: `git for-each-ref refs/snapshots/`.
2. `snaps show <ref>` to confirm you have the right checkpoint.
3. Commit or park anything currently in the tree, then `snaps restore <ref>`.
4. If it predates the snapshot hooks: check `git fsck --lost-found` and `git reflog` for
   anything that was ever committed. If it was never committed and never snapshotted, it is
   gone — that is exactly the outcome this exists to prevent.

---

## Files

In the **kokko-safety** plugin ([kokko-ng/kokko-cmds](https://github.com/kokko-ng/kokko-cmds)):

| File | Role |
| --- | --- |
| `hooks/git-snapshot.sh` | Checkpoints the tree |
| `hooks/session-context.sh` | States the rules and the project context at session start |

In this repo:

| Path | Role |
| --- | --- |
| `.devcontainer/config/claude/hooks/verify-safety-net.sh` | Proves the snapshot hook is installed and working |
| `.devcontainer/config/claude/settings.json` | Wires the verifier and declares the plugin roster |
| `.devcontainer/config/claude/merge-hooks.jq` | Splices that wiring into an existing `settings.json` |
| `.devcontainer/config/bin/snaps` | Browse/restore snapshots |
| `.devcontainer/config/claude/CLAUDE.md` | The advisory layer |

The verifier is reinstalled on every container rebuild, and the wiring is merged into
`settings.json` rather than overwriting it — so your own hooks and settings survive, and
re-running never stacks duplicates. `scripts/test-merge-hooks.sh` proves both properties.
