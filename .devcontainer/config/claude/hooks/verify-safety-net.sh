#!/usr/bin/env bash
# verify-safety-net.sh — prove the snapshot safety net is actually installed and
# working, at the start of every session.
#
# WHY THIS EXISTS
# ---------------
# There is no longer any deterministic guard: nothing refuses a destructive
# command. The snapshot layer is therefore the *only* mechanism standing between
# an agent's rebase and permanently lost work, which makes it far more important
# that it be verified rather than assumed.
#
# It ships in the kokko-safety plugin, installed by `claude plugin install`,
# which needs network and a signed-in CLI — and bootstrap_claude_plugins is
# deliberately allowed to fail so a transient outage cannot break the container
# build. This hook closes that gap: it is delivered by settings.json (which
# post-create merges unconditionally, with no network involved), so it runs even
# when the plugin install did not.
#
# A BEHAVIOURAL canary, not a file-exists check. A snapshot hook whose jq
# dependency is missing, or whose git invocation fails, exits 0 and prints
# nothing — indistinguishable from a clean tree. So this builds a throwaway
# repository with a known dirty file, runs the real hook against it, and checks
# that a ref actually appeared under refs/snapshots/ containing the change.
# Anything less would pass while protecting nothing.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

warn() {
    jq -n --arg c "$1" '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $c
        }
    }'
    exit 0
}

ADVICE="Until this is fixed there is NO recovery path for uncommitted work, and nothing blocks
destructive commands either:
- Do NOT run rebase, reset, checkout, restore, stash or clean against a dirty tree.
- Commit before any operation that rewrites the working tree. Commits are the only
  protection currently available.
- Tell the user the safety net is down."

# The plugin install path is not a stable contract, so search for the hook
# rather than assuming a location.
snapshot_hook=""
for root in "$HOME/.claude/plugins" "$HOME/.claude"; do
    [[ -d "$root" ]] || continue
    snapshot_hook="$(find "$root" -maxdepth 6 -type f -name 'git-snapshot.sh' -path '*kokko-safety*' 2>/dev/null | head -1)"
    [[ -n "$snapshot_hook" ]] && break
done

if [[ -z "$snapshot_hook" ]]; then
    warn "GIT SNAPSHOT SAFETY NET IS DOWN.

The kokko-safety plugin is not installed, so git-snapshot.sh is NOT running. Uncommitted
changes to tracked files are NOT being checkpointed to refs/snapshots/.

$ADVICE

Fix with:  claude plugin install kokko-safety@kokko-ng-kokko-cmds
       or:  bash .devcontainer/post-create.sh --config-only"
fi

# Behavioural canary in a throwaway repo, so the user's own repository is never
# touched and the result does not depend on the current tree being dirty.
canary_dir="$(mktemp -d 2>/dev/null)" || exit 0
trap 'rm -rf "$canary_dir"' EXIT

canary_failed=""
{
    git -C "$canary_dir" init -q \
        && git -C "$canary_dir" config user.email safety@example.com \
        && git -C "$canary_dir" config user.name "Safety Canary" \
        && git -C "$canary_dir" config commit.gpgsign false \
        && printf 'baseline\n' > "$canary_dir/canary.txt" \
        && git -C "$canary_dir" add canary.txt \
        && git -C "$canary_dir" commit -qm baseline
} >/dev/null 2>&1 || canary_failed="setup"

if [[ -z "$canary_failed" ]]; then
    printf 'CANARY-UNCOMMITTED-LINE\n' >> "$canary_dir/canary.txt"

    # Run the real hook, from inside the canary repo, exactly as Claude Code
    # would on a user turn.
    ( cd "$canary_dir" && printf '{"hook_event_name":"UserPromptSubmit"}' \
        | bash "$snapshot_hook" ) >/dev/null 2>&1 || true

    ref="$(git -C "$canary_dir" for-each-ref --format='%(refname)' refs/snapshots/ 2>/dev/null | head -1)"
    if [[ -z "$ref" ]]; then
        canary_failed="no ref was created under refs/snapshots/"
    elif ! git -C "$canary_dir" stash show -p "$ref" 2>/dev/null | grep -q 'CANARY-UNCOMMITTED-LINE'; then
        canary_failed="a ref was created but does not contain the uncommitted change"
    fi
fi

if [[ -n "$canary_failed" && "$canary_failed" != "setup" ]]; then
    warn "GIT SNAPSHOT SAFETY NET IS INSTALLED BUT NOT WORKING.

Found the hook at:
  $snapshot_hook

It was run against a throwaway repository with one uncommitted tracked change, and
$canary_failed. Likely causes: jq missing from the hook's environment, or git refusing to
operate (\"dubious ownership\" on a bind-mounted workspace owned by a different uid).

$ADVICE

Reinstall with:  claude plugin update kokko-safety@kokko-ng-kokko-cmds
If git reports dubious ownership: git config --global --add safe.directory <workspace>"
fi

# Working, or the canary itself could not be set up (no git, read-only /tmp) --
# in which case saying nothing beats crying wolf. A hook that reports success on
# every session start is noise; the work-loss briefing comes from the plugin's
# session-context hook.
exit 0
