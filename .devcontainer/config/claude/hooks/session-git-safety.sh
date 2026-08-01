#!/usr/bin/env bash
# session-git-safety.sh — state the git safety contract at session start.
#
# The bundled CLAUDE.md carries the same rules, but post-create.sh will not
# overwrite a CLAUDE.md that a host mount already provides — so in exactly the
# setup a long-running user is most likely to have, the advisory layer would
# silently vanish. This hook does not depend on any file the user might replace.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    # Distinguish "not a repo" (fine, stay silent) from "git refuses to
    # operate" (dubious ownership on a host-uid bind mount). In the latter
    # case BOTH safety layers are silently non-functional — the snapshot
    # hook's git calls fail identically — so say so at session start instead
    # of letting the broken state be discovered after data loss.
    err=$(git rev-parse --git-dir 2>&1 >/dev/null || true)
    if printf '%s' "$err" | grep -qi 'dubious ownership'; then
        jq -n '{
            hookSpecificOutput: {
                hookEventName: "SessionStart",
                additionalContext: "WARNING: git reports \"dubious ownership\" for this workspace (it is owned by a different uid than the container user). The git safety layer is NON-FUNCTIONAL: nothing is being snapshotted and the guard cannot verify tree state (it will fail closed). Fix before any git work: git config --global --add safe.directory <workspace>, then verify `snaps` works."
            }
        }'
    fi
    exit 0
fi

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
