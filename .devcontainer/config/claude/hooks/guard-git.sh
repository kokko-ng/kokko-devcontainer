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
# Recovery commands are whitelisted even on a dirty tree: a conflicted rebase
# IS a dirty tree, so `git rebase --abort/--continue/--skip/--quit`, index-only
# `git reset`, `git restore --staged`, and `git stash list/show/apply` must
# stay reachable or the guard traps the user inside the very state it is meant
# to prevent.
#
# Override (humans only, deliberately verbose and greppable):
#   CLAUDE_GIT_GUARD=off git rebase ...
# A bypass is allowed through, but a loud systemMessage is emitted so the
# bypass is visible in the transcript instead of vanishing silently.
# git-snapshot.sh has already checkpointed the tree, so even a bypass is
# recoverable — that is the point of having both layers.
# shellcheck disable=SC2016  # backticks inside deny messages are literal
set -uo pipefail

input=$(cat 2>/dev/null || true)

# jq is a hard dependency: without it the command string cannot be parsed out
# of the hook payload, and no structured decision can be produced. That must
# fail CLOSED for git-looking input, not silently allow everything — exit 2
# blocks the tool call and feeds stderr back to the agent.
if ! command -v jq >/dev/null 2>&1; then
    if printf '%s' "$input" | grep -q 'git'; then
        echo "guard-git.sh: jq is not installed, so this git command cannot be safety-checked. Failing closed. Install jq (sudo apt-get install -y jq) and retry." >&2
        exit 2
    fi
    exit 0
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
[[ -n "$cmd" ]] || exit 0

# Explicit bypass: allow the command, but leave a loud, greppable record in
# the transcript. A silent bypass looks identical to a guard that never ran.
notice_bypass() {
    jq -n --arg m "$1" '{ systemMessage: $m }'
    exit 0
}
[[ "${CLAUDE_GIT_GUARD:-on}" == "off" ]] && \
    notice_bypass "GIT GUARD BYPASSED: CLAUDE_GIT_GUARD=off is set in the environment. guard-git.sh performed NO safety checks on: $cmd"
printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|(])CLAUDE_GIT_GUARD=off[[:space:]]' && \
    notice_bypass "GIT GUARD BYPASSED: this command sets CLAUDE_GIT_GUARD=off inline. guard-git.sh performed NO safety checks on: $cmd"

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

# ---------------------------------------------------------------------------
# Recovery whitelist — rewrite known-safe recovery invocations so the deny
# regexes below cannot see them. This composes correctly with compound
# commands: `git rebase --abort && git rebase main` keeps its destructive
# half visible and is still denied.
# ---------------------------------------------------------------------------
scmd="$cmd"
# Terminators here (and in the deny patterns below, as $E) include closing
# quotes: a wrapped command ends in one (`sh -lc 'git rebase --abort'`), and
# without it the whitelist misses — or a deny pattern misses — on the quote.
# A conflicted rebase is dirty by definition — the abort/continue/skip/quit
# forms are the ONLY exit from it and destroy nothing that matters.
scmd=$(printf '%s' "$scmd" | sed -E 's/rebase[[:space:]]+--(abort|continue|skip|quit)([[:space:];&|)"'"'"']|$)/__RECOVERY__\2/g')
# stash list/show are read-only; stash apply is the documented snapshot
# recovery path (snaps restore == git stash apply refs/snapshots/...).
scmd=$(printf '%s' "$scmd" | sed -E 's/stash[[:space:]]+(list|show|apply)([[:space:];&|)"'"'"']|$)/__RECOVERY__\2/g')
# restore --staged only touches the index — unless --worktree/-W is also
# present, in which case leave it visible for the restore deny below.
if ! printf '%s' "$scmd" | grep -qE -- '--worktree|(^|[[:space:]])-W([[:space:]]|$)'; then
    scmd=$(printf '%s' "$scmd" | sed -E 's/restore[[:space:]]+--staged([[:space:]]|$)/__RECOVERY__\1/g')
fi
# git clean dry-runs delete nothing. Only the form with -n/--dry-run as the
# first argument is recognized (`git clean -n`, `-nd`, `--dry-run`); putting
# the dry-run flag later still trips the deny, which errs on the safe side.
scmd=$(printf '%s' "$scmd" | sed -E 's/clean[[:space:]]+(-[a-zA-Z]*n[a-zA-Z]*|--dry-run)([[:space:];&|)"'"'"']|$)/__RECOVERY__\2/g')

matches() { printf '%s' "$scmd" | grep -qE "$1"; }

# End-of-token for the deny patterns: whitespace, a shell operator, a closing
# quote (wrapped commands end in one: `sh -lc 'git reset --hard'`), or end of
# string. Without the quotes, the closing quote masked the match.
E='([[:space:];&|)"'"'"']|$)'

# `git` at a COMMAND position — start of a line, after a shell operator,
# quoted behind `sh -c` (including short-option clusters like `sh -lc` /
# `bash -exc`, where the -c rides along with other flags), or behind `eval`.
# Anchoring here is not pedantry: an unanchored `git` matches inside string
# literals (`echo "never git reset --hard"`) and, worse, inside other words —
# `digit restore` contains "git restore". A guard that cries wolf on
# documentation gets switched off.
CMDPOS='(^|[;&|(){}]|[[:space:]]-[a-zA-Z]*c[a-zA-Z]*[[:space:]]+["'"'"']?|(^|[;&|(){}[:space:]])eval[[:space:]]+["'"'"']?)[[:space:]]*'

# Leading wrapper tokens that still end up running git: sudo/env/command/...,
# eval, VAR=val assignments, and their own flags/arguments (`nice -n 10`,
# `sudo -u vscode`). Without this, `sudo git rebase` and `env git reset --hard`
# sailed straight past the anchor. Once the FIRST token is a wrapper or an
# assignment, anything up to the next shell operator may precede git.
# (Quoted eval — `eval "git rebase"` — is handled by CMDPOS above, because the
# quote sits between the wrapper and the git word.)
WRAP='((sudo|env|command|eval|time|nohup|xargs|nice|stdbuf|[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*)[[:space:]]+([^;&|]*[[:space:]])?)?'

# git itself may be invoked by absolute path (`/usr/bin/git rebase`) or with
# the alias-skipping backslash prefix (`\git rebase`).
GITWORD='\\?([^[:space:]]*/)?git[[:space:]]+'

# ...tolerating the global options that legitimately precede a subcommand.
# --git-dir/--work-tree accept both the `=` and the space-separated form.
G="${CMDPOS}${WRAP}${GITWORD}"'((-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir(=|[[:space:]]+)[^[:space:]]+|--work-tree(=|[[:space:]]+)[^[:space:]]+)[[:space:]]+)*'

RECOVER='Uncommitted tracked changes are present. git-snapshot.sh has checkpointed them (run `snaps`), but do not rely on that: commit the work instead, then retry.'

# ---------------------------------------------------------------------------
# Always denied — destructive regardless of whether the tree is dirty.
# ---------------------------------------------------------------------------

# Destroys UNTRACKED files, which snapshots deliberately do not capture. This
# is the one case with no safety net, so every non-dry-run form is denied
# unconditionally (the whitelist above has already hidden `git clean -n` /
# `--dry-run` forms).
matches "${G}clean${E}" && \
    deny "BLOCKED: \`git clean\` deletes untracked files. Snapshots only cover TRACKED changes, so there is no recovery path for this one. A dry run (\`git clean -n\` / \`git clean --dry-run\`, dry-run flag first) is allowed; delete specific files with \`rm\` instead, after confirming what they are."

# These destroy the history and the snapshot refs themselves — the safety net.
matches "${G}(filter-branch|filter-repo)" && \
    deny "BLOCKED: history rewriting destroys objects and the refs/snapshots/ safety net. Ask the user first."
matches "${G}reflog[[:space:]]+(expire|delete)" && \
    deny "BLOCKED: the reflog is the recovery path for committed work. Do not expire it."
matches "${G}(gc[[:space:]]+.*--prune|prune${E})" && \
    deny "BLOCKED: pruning deletes unreachable objects, which is exactly what recovery depends on."
matches "${G}update-ref[[:space:]]+-d[[:space:]]+refs/snapshots" && \
    deny "BLOCKED: refs/snapshots/ is the working-tree safety net. Never delete it by hand."

# A force flag anywhere among push's arguments (not just immediately after
# `push`), plus the `+refspec` force form.
matches "${G}push[^;&|]*[[:space:]](--force[^[:space:];&|]*|-[a-zA-Z]*f[a-zA-Z]*)${E}" && \
    deny "BLOCKED: force-push rewrites the shared remote. Push additively; if a push is rejected, leave it rejected and tell the user."
matches "${G}push[^;&|]*[[:space:]][\"']?\+[^[:space:]]" && \
    deny "BLOCKED: a \`+refspec\` push (\`git push origin +branch\`) is a force-push in disguise. Push additively; if a push is rejected, leave it rejected and tell the user."

# Remote branch deletion, in both spellings. The remote's reflog is not yours
# to recover from, and anyone else tracking the branch loses it too.
matches "${G}push[^;&|]*[[:space:]](--delete|-[a-zA-Z]*d[a-zA-Z]*)${E}" && \
    deny "BLOCKED: \`git push --delete\` removes a branch from the shared remote — for everyone, with no local reflog to recover it from. Ask the user first."
matches "${G}push[^;&|]*[[:space:]][\"']?:[^[:space:]]" && \
    deny "BLOCKED: pushing an empty refspec (\`git push <remote> :<ref>\`) deletes that ref on the shared remote — it is \`push --delete\` in disguise. Ask the user first."

# A force-removed worktree takes its uncommitted (and untracked) changes with
# it — that tree's work was never a git object, so nothing can bring it back.
matches "${G}worktree[[:space:]]+remove[^;&|]*[[:space:]](--force[^[:space:];&|]*|-[a-zA-Z]*f[a-zA-Z]*)${E}" && \
    deny "BLOCKED: \`git worktree remove --force\` deletes the worktree ALONG WITH its uncommitted changes. Plain \`git worktree remove\` is allowed — it refuses when the tree is dirty, which is the point."

# -D (== --delete --force) drops a branch regardless of merge state, and the
# branch's reflog is deleted with it — so the usual recovery path dies too.
matches "${G}branch[^;&|]*[[:space:]](-[a-zA-Z]*D[a-zA-Z]*|--delete[[:space:]]+--force|--force[[:space:]]+--delete)${E}" && \
    deny "BLOCKED: \`git branch -D\` force-deletes a branch AND its reflog — the reflog for a deleted branch is deleted with it, so unmerged commits become unreachable with no easy way back. Use \`git branch -d\`, which refuses on unmerged work; if -d refuses, ask the user."

# The dot must be a COMPLETE argument (`.` or `./`), not a prefix — otherwise
# legitimate dotted paths (`git add .claude/settings.json`, `.gitignore`)
# false-positive as `git add .`.
matches "${G}add[[:space:]]+(\.[/]?${E}|-A${E}|--all${E})" && \
    deny "BLOCKED: \`git add .\` stages everything, including build output, secrets and scratch files. Stage explicit file paths. Note a directory add also sweeps in any UNTRACKED files inside it — prefer naming files."

matches "${G}stash[[:space:]]+(drop|clear)" && \
    deny "BLOCKED: this permanently deletes stashed work. Inspect it first (\`git stash list\`, \`git stash show -p\`)."

# ---------------------------------------------------------------------------
# Denied only against a dirty tree — safe and allowed on a clean one.
#
# The dirty check must run against the repository the command actually
# targets: a leading `cd <dir> &&`, a `git -C <dir>`, or a `--git-dir=<dir>`
# can point at a different repo than the hook's cwd. If a destructive command
# targets a repo whose state cannot be verified, fail CLOSED.
# ---------------------------------------------------------------------------

# Target resolution is shared with git-snapshot.sh via lib-git-target.sh so
# the two hooks can never disagree about which repo a command touches. If the
# lib is missing the guard cannot resolve targets — fail CLOSED for git-looking
# commands (same policy as missing jq), stay silent for everything else.
GUARD_LIB="$(dirname "${BASH_SOURCE[0]}")/lib-git-target.sh"
if [[ ! -f "$GUARD_LIB" ]]; then
    if printf '%s' "$cmd" | grep -q 'git'; then
        echo "guard-git.sh: $GUARD_LIB is missing, so the target repository of this git command cannot be resolved. Failing closed. Re-run: bash .devcontainer/post-create.sh --config-only" >&2
        exit 2
    fi
    exit 0
fi
# shellcheck source=lib-git-target.sh
source "$GUARD_LIB"

resolve_git_target "$cmd"

treat_dirty=1  # fail closed until proven otherwise
if [[ -n "$target" ]]; then
    if git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
        if st=$(git -C "$target" status --porcelain --untracked-files=no 2>/dev/null); then
            if [[ -n "$(printf '%s' "$st" | head -1)" ]]; then
                treat_dirty=1
            else
                treat_dirty=0
            fi
        else
            RECOVER="git cannot report the working-tree state of '$target' (bare repo, or git error), so the dirty-tree check cannot run there. The guard fails closed: run the command from inside a working tree it can verify."
        fi
    else
        RECOVER="the command targets '$target', which git cannot read as a repository from here, so the dirty-tree check cannot run. The guard fails closed: verify the path, or run the command from inside that repository."
    fi
elif git rev-parse --git-dir >/dev/null 2>&1; then
    if [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]]; then
        treat_dirty=1
    else
        treat_dirty=0
    fi
else
    # git cannot READ the cwd as a repository, and the command names no other
    # repo. Two causes, both of which must fail CLOSED, not open:
    #   - "dubious ownership" on bind-mounted workspaces owned by the host
    #     uid: the tree may well be dirty, the snapshot hook's git calls are
    #     failing identically (so nothing is checkpointed), and an agent can
    #     bypass the refusal per-command with `git -c safe.directory=...`.
    #   - the hook simply runs outside any repo (e.g. from $HOME) while the
    #     command reaches one through a script or an unparsed construct —
    #     previously this allowed EVERYTHING through.
    err=$(git rev-parse --git-dir 2>&1 >/dev/null || true)
    if printf '%s' "$err" | grep -qi 'dubious ownership'; then
        RECOVER='git itself cannot read this repository ("dubious ownership": the workspace is owned by a different uid than the container user). The dirty-tree check AND the snapshot safety net are both non-functional, so the tree is treated as dirty. Fix first: `git config --global --add safe.directory <workspace>`, verify `snaps` works, then retry.'
    else
        RECOVER='the current directory is not a git repository and no target repository could be extracted from the command, so the dirty-tree check cannot run. The guard fails closed: run the command from inside the repository, or name it explicitly with `git -C <repo>`.'
    fi
fi

[[ "$treat_dirty" -eq 1 ]] || exit 0

matches "${G}rebase${E}" && \
    deny "BLOCKED: \`git rebase\` over a dirty tree silently discards every uncommitted change to a tracked file, with no prompt and no way back. (\`git rebase --abort/--continue/--skip/--quit\` are allowed.) $RECOVER"

# Index-only resets (--soft/--mixed/no flag) never touch the working tree and
# are the standard way to unstage — only the tree-clobbering modes are denied.
matches "${G}reset[^;&|]*[[:space:]]--(hard|merge|keep)${E}" && \
    deny "BLOCKED: \`git reset --hard/--merge/--keep\` over a dirty tree discards uncommitted tracked changes. An index-only reset (no mode flag, or --soft/--mixed) is allowed. $RECOVER"

matches "${G}(checkout|switch)[^;&|]*[[:space:]](-f${E}|--force${E}|--discard-changes)" && \
    deny "BLOCKED: a forced checkout/switch overwrites uncommitted tracked changes. $RECOVER"

matches "${G}checkout([[:space:]]+[^[:space:]-][^[:space:]]*)*[[:space:]]+--[[:space:]]" && \
    deny "BLOCKED: \`git checkout <ref> -- <path>\` silently overwrites that file's uncommitted changes. To keep a copy, use \`cp\`. $RECOVER"

matches "${G}checkout[[:space:]]+\.${E}" && \
    deny "BLOCKED: \`git checkout .\` discards all uncommitted tracked changes. $RECOVER"

# -B / -C force-move an EXISTING branch to a new start point while switching —
# a ref clobber plus a tree switch in one step, over work in progress.
# (Lower-case -b / -c create-only forms are allowed: they refuse to clobber.)
matches "${G}checkout[^;&|]*[[:space:]]-[a-zA-Z]*B[a-zA-Z]*${E}" && \
    deny "BLOCKED: \`git checkout -B\` moves an existing branch ref and switches onto it over uncommitted work. Use \`git checkout -b\` (create-only) or commit first. $RECOVER"
matches "${G}switch[^;&|]*[[:space:]](-[a-zA-Z]*C[a-zA-Z]*${E}|--force-create${E})" && \
    deny "BLOCKED: \`git switch -C\` moves an existing branch ref and switches onto it over uncommitted work. Use \`git switch -c\` (create-only) or commit first. $RECOVER"

# git rm without -f refuses to remove a file whose content differs from HEAD;
# -f overrides exactly that check and deletes the modified file from disk.
matches "${G}rm[^;&|]*[[:space:]](--force${E}|-[a-zA-Z]*f[a-zA-Z]*${E})" && \
    deny "BLOCKED: \`git rm -f\` deletes locally-modified files from disk — the -f exists only to override git's own refusal. Plain \`git rm\` (which refuses on modified files) or \`git rm --cached\` (index-only) are allowed. $RECOVER"

matches "${G}restore${E}" && \
    deny "BLOCKED: \`git restore\` overwrites uncommitted changes from another revision. (\`git restore --staged <path>\` without --worktree is allowed — it only touches the index.) Use \`cp\` to back up and restore files. $RECOVER"

matches "${G}stash${E}" && \
    deny "BLOCKED: \`git stash\` was load-bearing in past data-loss incidents and is easy to forget to pop. (\`git stash list/show/apply\` are allowed.) Commit instead — commits are cheap, reversible, and visible."

matches "${G}branch[[:space:]]+(-f|--force)${E}" && \
    deny "BLOCKED: \`git branch -f\` silently moves a ref. Ask the user first. $RECOVER"

exit 0
