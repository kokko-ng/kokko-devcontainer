# CLAUDE.md

Global instructions for Claude Code across all projects.

---

## Protecting uncommitted work — read this before touching git

Uncommitted changes to **tracked** files are the most fragile thing in any repo.
`rebase`, `reset`, `checkout <ref> -- <path>`, `restore`, `stash` and `clean` overwrite
them with **no prompt and no confirmation**. And they are unrecoverable: work that was
never committed was never a git object, so there is no reflog entry, no dangling blob,
and `git fsck` will not find it. It is simply gone.

This has destroyed hours of real work on projects using this container, more than once,
always the same way: an agent rewrote history while uncommitted work sat in the tree.

Two automatic safety nets run in this container. **Neither is an excuse to be casual.**

### 1. Snapshots (`snaps`)

Before any git command, and on every prompt, uncommitted tracked changes are checkpointed
to `refs/snapshots/<timestamp>` — real git commits that survive every destructive command.

```sh
snaps                    # list snapshots, newest first
snaps show <ref>         # what does this snapshot contain?
snaps diff <ref>         # how does it differ from the tree right now?
snaps restore <ref>      # apply it back (refuses if the tree is dirty)
```

If work disappears, **look here first** — before conducting any archaeology, and before
telling the user it is lost. Snapshots cover tracked changes only; untracked files are
not captured, because the destructive commands do not touch untracked paths (`git clean`
is the exception, which is why it is blocked outright).

### 2. The git guard

Destructive git commands are **blocked against a dirty tree** and allowed against a clean
one. So a rebase on a clean tree just works; the same rebase with uncommitted changes
present is refused.

**If the guard blocks you, it is right and you are wrong.** Do not look for a way around
it. Commit the work — commits are cheap, reversible and visible — then retry. If you
genuinely believe the block is wrong, **stop and ask the user**. The override exists for
humans, not for you.

### Rules that hold regardless of the safety nets

- **Check the tree before your first edit:** `git status --short --untracked-files=no`.
  Not empty and not yours? **Stop and ask.** Never tidy, stash, or assume it is junk.
- **Commit before anything that rewrites history**, and before any build that packages the
  working tree (`docker build`, `az acr build`, and similar build-from-context tools ship
  what is on disk, **not** what is in HEAD — so deploying uncommitted work silently
  diverges the deployed artifact from git history).
  If it is good enough to build an image from, it is good enough to commit first.
- **Stage explicit file paths**, never `git add .`. Be careful with directory
  adds (`git add src/`): they also stage any UNTRACKED files inside the
  directory, which has swept scratch files into commits before. When untracked
  files live near what you are committing, name the files individually.
- **Check which branch you are on** — `git rev-parse --abbrev-ref HEAD`. Never assume `main`.
- **Use `cp` to back up and restore files**, never `git checkout -- <path>`.
- **A rejected push is usually correct.** Report it and stop; do not work around it.
- **Push only when the user asks.** Never on your own initiative.
- **Pass these rules on to any subagent you spawn** that may touch git. Subagents inherit
  the hooks, but not your judgement — and several past incidents came from an agent
  following a workflow that listed "rebase and push" as a routine step.

If you catch yourself reasoning toward *"I'll just rebase quickly"* or *"I'll stash this
first"* — that is precisely the thought that preceded every incident. Stop and ask.

---

## Communication Style

- Never use emojis in any communication, code, comments, or documentation
- Maintain a concise, professional tone in all interactions
- Provide direct, clear technical communication without unnecessary elaboration
- Focus on facts and technical accuracy over conversational language

## Context Window

Your context window will be automatically compacted as it approaches its limit. Do not stop tasks early due to token budget concerns. Always be persistent and autonomous, completing tasks fully regardless of context remaining.

## Testing and Development Files

All testing artifacts, temporary files, and development scripts should be placed in `/tmp` to maintain repository cleanliness:

- Development scripts and experiments
- Temporary output files
- Test artifacts and logs
- Mock data generators

## Process Management

**NEVER use `pkill`, `killall`, or broad process termination commands.** These can crash unrelated Mac applications. Instead:

- Ask the user to manually restart services if needed
- Use specific process IDs with `kill` only for processes you started
