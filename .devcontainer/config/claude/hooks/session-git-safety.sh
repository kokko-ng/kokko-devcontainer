#!/usr/bin/env bash
# session-git-safety.sh — state the git safety contract at session start.
#
# The bundled CLAUDE.md carries the same rules, but post-create.sh will not
# overwrite a CLAUDE.md that a host mount already provides — so in exactly the
# setup a long-running user is most likely to have, the advisory layer would
# silently vanish. This hook does not depend on any file the user might replace.
set -uo pipefail

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

dirty_note=""
if [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]]; then
    count=$(git status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')
    dirty_note="

ATTENTION: this repo currently has ${count} uncommitted tracked file(s). If that work is not
yours, STOP and ask the user before editing or running any git command. Do not tidy it,
do not stash it, do not assume it is junk."
fi

read -r -d '' CONTEXT <<EOF || true
Git safety (enforced by hooks in this devcontainer):

- Uncommitted changes to TRACKED files are unrecoverable if destroyed: they were never git
  objects, so no reflog entry, no dangling blob, no fsck recovery. rebase/reset/checkout/
  restore/stash/clean overwrite them with no prompt. This has destroyed hours of real work
  on projects using this container.
- Destructive git commands are BLOCKED while the tree is dirty, and allowed while it is
  clean. If you are blocked, the guard is right: commit the work and retry, or ask the
  user. Do not look for a way around it.
- Uncommitted tracked changes are auto-snapshotted to refs/snapshots/. If work seems lost,
  run \`snaps\` FIRST, before any archaeology and before telling the user it is gone.
  \`snaps show|diff|restore <ref>\`.
- Commit before any build that packages the working tree (docker/az acr build ship what is
  on disk, not HEAD). Stage explicit paths, never \`git add .\`. Push only when asked.${dirty_note}
EOF

jq -n --arg c "$CONTEXT" '{
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $c
    }
}'
exit 0
