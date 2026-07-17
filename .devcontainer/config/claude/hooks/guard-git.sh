#!/usr/bin/env bash
# guard-git.sh — block git commands that destroy uncommitted work.
#
# DESIGN: deny, and only when it matters.
#
# "deny", not "ask": agents run unattended under acceptEdits, where an "ask"
# either blocks forever or gets clicked through. Every real incident happened
# because rebase was a documented step in an agent's own workflow — it would
# have answered "yes" to a prompt with total confidence.
#
# "only when it matters": these commands are catastrophic ONLY against a dirty
# tree. On a clean tree a rebase is fully reflog-recoverable, so it is allowed
# through silently. A guard that fires on every routine command is noise, and
# noise gets switched off — which is precisely how the pre-existing safety
# plugin ended up disabled and protecting nothing. This fires rarely, and when
# it fires it is right.
#
# Override (humans only, deliberately verbose and greppable):
#   CLAUDE_GIT_GUARD=off git rebase ...
# Prefer committing. git-snapshot.sh has already checkpointed the tree, so even
# a bypass is recoverable — that is the point of having both layers.
set -uo pipefail

input=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
[[ -n "$cmd" ]] || exit 0

[[ "${CLAUDE_GIT_GUARD:-on}" == "off" ]] && exit 0
printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|(])CLAUDE_GIT_GUARD=off[[:space:]]' && exit 0

deny() {
    jq -n --arg r "$1" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $r
        }
    }'
    exit 0
}

matches() { printf '%s' "$cmd" | grep -qE "$1"; }

# `git` at a COMMAND position — start of a line, or after a shell operator, or
# quoted behind `sh -c`. Anchoring here is not pedantry: an unanchored `git`
# matches inside string literals (`echo "never git reset --hard"`) and, worse,
# inside other words — `digit restore` contains "git restore". A guard that
# cries wolf on documentation gets switched off.
CMDPOS='(^|[;&|(){}]|[[:space:]]-c[[:space:]]+["'"'"']?)[[:space:]]*'

# ...tolerating the global options that legitimately precede a subcommand.
G="${CMDPOS}"'git[[:space:]]+((-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+)[[:space:]]+)*'

RECOVER='Uncommitted tracked changes are present. git-snapshot.sh has checkpointed them (run `snaps`), but do not rely on that: commit the work instead, then retry.'

# ---------------------------------------------------------------------------
# Always denied — destructive regardless of whether the tree is dirty.
# ---------------------------------------------------------------------------

# Destroys UNTRACKED files, which snapshots deliberately do not capture. This is
# the one case with no safety net, so it is denied unconditionally.
matches "${G}clean([[:space:]]+-[a-zA-Z]*[fdx])" && \
    deny "BLOCKED: \`git clean\` deletes untracked files. Snapshots only cover TRACKED changes, so there is no recovery path for this one. Delete specific files with \`rm\` instead, after confirming what they are."

# These destroy the history and the snapshot refs themselves — the safety net.
matches "${G}(filter-branch|filter-repo)" && \
    deny "BLOCKED: history rewriting destroys objects and the refs/snapshots/ safety net. Ask the user first."
matches "${G}reflog[[:space:]]+(expire|delete)" && \
    deny "BLOCKED: the reflog is the recovery path for committed work. Do not expire it."
matches "${G}(gc[[:space:]]+.*--prune|prune([[:space:]]|$))" && \
    deny "BLOCKED: pruning deletes unreachable objects, which is exactly what recovery depends on."
matches "${G}update-ref[[:space:]]+-d[[:space:]]+refs/snapshots" && \
    deny "BLOCKED: refs/snapshots/ is the working-tree safety net. Never delete it by hand."

matches "${G}push[[:space:]]+.*(--force([[:space:]]|=|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$))" && \
    deny "BLOCKED: force-push rewrites the shared remote. Push additively; if a push is rejected, leave it rejected and tell the user."

matches "${G}add[[:space:]]+(\.|-A([[:space:]]|$)|--all([[:space:]]|$))" && \
    deny "BLOCKED: \`git add .\` stages everything, including build output, secrets and scratch files. Stage explicit paths: \`git add src/ docs/\`."

matches "${G}stash[[:space:]]+(drop|clear)" && \
    deny "BLOCKED: this permanently deletes stashed work. Inspect it first (\`git stash list\`, \`git stash show -p\`)."

# ---------------------------------------------------------------------------
# Denied only against a dirty tree — safe and allowed on a clean one.
# ---------------------------------------------------------------------------

git rev-parse --git-dir >/dev/null 2>&1 || exit 0
[[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]] || exit 0

matches "${G}rebase([[:space:]]|$)" && \
    deny "BLOCKED: \`git rebase\` over a dirty tree silently discards every uncommitted change to a tracked file, with no prompt and no way back. $RECOVER"

matches "${G}reset([[:space:]]|$)" && \
    deny "BLOCKED: \`git reset\` over a dirty tree can discard uncommitted tracked changes. $RECOVER"

matches "${G}(checkout|switch)[[:space:]]+.*(-f([[:space:]]|$)|--force([[:space:]]|$)|--discard-changes)" && \
    deny "BLOCKED: a forced checkout/switch overwrites uncommitted tracked changes. $RECOVER"

matches "${G}checkout([[:space:]]+[^[:space:]-][^[:space:]]*)*[[:space:]]+--[[:space:]]" && \
    deny "BLOCKED: \`git checkout <ref> -- <path>\` silently overwrites that file's uncommitted changes. To keep a copy, use \`cp\`. $RECOVER"

matches "${G}checkout[[:space:]]+\.([[:space:]]|$)" && \
    deny "BLOCKED: \`git checkout .\` discards all uncommitted tracked changes. $RECOVER"

matches "${G}restore([[:space:]]|$)" && \
    deny "BLOCKED: \`git restore\` overwrites uncommitted changes from another revision. Use \`cp\` to back up and restore files. $RECOVER"

matches "${G}stash([[:space:]]|$)" && \
    deny "BLOCKED: \`git stash\` was load-bearing in past data-loss incidents and is easy to forget to pop. Commit instead — commits are cheap, reversible, and visible."

matches "${G}branch[[:space:]]+(-f|--force)([[:space:]]|$)" && \
    deny "BLOCKED: \`git branch -f\` silently moves a ref. Ask the user first. $RECOVER"

exit 0
