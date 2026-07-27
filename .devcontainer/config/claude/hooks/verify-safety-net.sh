#!/usr/bin/env bash
# verify-safety-net.sh — prove the git safety net is actually installed and
# working, at the start of every session.
#
# WHY THIS EXISTS
# ---------------
# The safety hooks used to live in this repo and were installed unconditionally
# by post-create.sh. They now ship in the kokko-safety plugin, which is better
# in every way except one: `claude plugin install` needs network and a
# signed-in CLI, and bootstrap_claude_plugins is deliberately allowed to fail so
# a transient outage cannot break the container build.
#
# That trade would be unacceptable on its own. "A safety net that fails silently
# is worse than none, because everyone assumes it is working" is the principle
# the whole git-safety design rests on. So this hook closes the gap: it is
# delivered by settings.json (which post-create merges unconditionally, with no
# network involved), and it checks the plugin-delivered guard both EXISTS and
# DENIES a known-destructive command.
#
# A behavioural canary, not a file-exists check: a guard whose regex broke, or
# whose lib/ failed to install, would pass the latter and protect nothing.
# `git clean -fd` is the canary because guard-git.sh denies it unconditionally,
# with no dependence on the current directory being a repo or the tree being
# dirty.
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

# The plugin install path is not a stable contract, so search for the guard
# rather than assuming a location.
guard=""
for root in "$HOME/.claude/plugins" "$HOME/.claude"; do
    [[ -d "$root" ]] || continue
    guard="$(find "$root" -maxdepth 6 -type f -name 'guard-git.sh' -path '*kokko-safety*' 2>/dev/null | head -1)"
    [[ -n "$guard" ]] && break
done

if [[ -z "$guard" ]]; then
    warn "GIT SAFETY NET IS DOWN.

The kokko-safety plugin is not installed, so guard-git.sh and git-snapshot.sh are NOT running.
Uncommitted changes to tracked files are NOT being checkpointed, and destructive git commands
are NOT being blocked.

Until this is fixed, treat every git command as unguarded:
- Do NOT run rebase, reset, checkout -f, restore, stash or clean against a dirty tree.
- Commit before any operation that rewrites the working tree.
- Tell the user the safety net is down.

Fix with:  claude plugin install kokko-safety@kokko-ng-kokko-cmds
       or:  bash .devcontainer/post-create.sh --config-only"
fi

# Behavioural canary. `git clean -fd` must come back denied.
canary_out="$(jq -n '{
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    tool_input: {command: "git clean -fd"}
}' | KOKKO_SOUNDS=off bash "$guard" 2>/dev/null || true)"

decision="$(printf '%s' "$canary_out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")"

if [[ "$decision" != "deny" ]]; then
    warn "GIT SAFETY NET IS INSTALLED BUT NOT WORKING.

Found the guard at:
  $guard

It was asked to judge \`git clean -fd\`, which it must always deny, and returned
'${decision:-no decision}' instead. Something is broken -- a missing hooks/lib/ directory, a
malformed pattern file, or a jq that is not on PATH inside the hook's environment.

Destructive git commands are NOT reliably blocked. Treat every git command as unguarded and
tell the user. Reinstall with:

  claude plugin update kokko-safety@kokko-ng-kokko-cmds"
fi

# Working. Say nothing: a hook that reports success on every session start is
# noise, and the safety briefing itself comes from the plugin's session-context
# hook.
exit 0
