#!/usr/bin/env bash
# guard-git-tests.sh — regression tests for the git safety layer.
#
# Feeds real PreToolUse JSON payloads through the actual hooks and asserts
# deny/allow per command string, from several working directories (dirty repo,
# clean repo, plain non-repo directory). Also covers merge-hooks.jq semantics
# and bundled settings.json validity. Plain bash — no bats required.
#
# Usage: bash tests/guard-git-tests.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/.devcontainer/config/claude/hooks/guard-git.sh"
SNAPSHOT="$ROOT/.devcontainer/config/claude/hooks/git-snapshot.sh"
MERGE_JQ="$ROOT/.devcontainer/config/claude/merge-hooks.jq"
BUNDLED_SETTINGS="$ROOT/.devcontainer/config/claude/settings.json"

command -v jq >/dev/null || { echo "FATAL: jq is required to run these tests" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkrepo() { # <dir> [dirty]
    local d="$1"
    mkdir -p "$d"
    git -C "$d" init -q -b main
    git -C "$d" config user.email test@example.com
    git -C "$d" config user.name test
    echo base > "$d/file.txt"
    git -C "$d" add file.txt
    git -C "$d" commit -qm init
    if [[ "${2:-}" == dirty ]]; then
        echo changed > "$d/file.txt"
    fi
}

DIRTY="$WORK/dirty";   mkrepo "$DIRTY" dirty
CLEAN="$WORK/clean";   mkrepo "$CLEAN"
OTHER="$WORK/other";   mkrepo "$OTHER" dirty
PLAIN="$WORK/plain";   mkdir -p "$PLAIN"

PASS=0
FAIL=0
FAILED_CASES=()

# run_guard <cwd> <command> -> sets DECISION (deny|allow) and OUT
run_guard() {
    local cwd="$1" c="$2"
    local payload rc
    payload=$(jq -n --arg c "$c" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}')
    OUT=$(cd "$cwd" && printf '%s' "$payload" | bash "$GUARD" 2>/dev/null)
    rc=$?
    if [[ $rc -eq 2 ]]; then
        DECISION=deny
    elif printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        DECISION=deny
    else
        DECISION=allow
    fi
}

t() { # <expect deny|allow> <cwd> <command...>
    local expect="$1" cwd="$2" c="$3"
    run_guard "$cwd" "$c"
    if [[ "$DECISION" == "$expect" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("expected $expect, got $DECISION [cwd=$(basename "$cwd")]: $c")
    fi
}

# ===========================================================================
# 1. Wrapper-token / path bypasses (all previously slipped past the anchor)
# ===========================================================================
t deny  "$DIRTY" 'sudo git rebase main'
t deny  "$DIRTY" 'env git reset --hard'
t deny  "$DIRTY" 'command git clean -fd'
t deny  "$DIRTY" 'time git rebase main'
t deny  "$DIRTY" 'nohup git rebase main'
t deny  "$DIRTY" 'xargs git rebase main'
t deny  "$DIRTY" 'nice -n 10 git reset --hard'
t deny  "$DIRTY" 'stdbuf -o0 git rebase main'
t deny  "$DIRTY" '/usr/bin/git rebase main'
t deny  "$DIRTY" 'GIT_DIR=.git git rebase main'
t deny  "$DIRTY" 'sudo -u vscode env FOO=bar /usr/bin/git reset --hard'
# Shell wrappers with -c in a short-option cluster (bare `-c` was recognized,
# `-lc`/`-exc` slipped through), backslash alias-skip, and eval.
t deny  "$DIRTY" "sh -lc 'git rebase main'"
t deny  "$DIRTY" 'bash -exc "git rebase main"'
t deny  "$DIRTY" 'zsh -xec "git reset --hard"'
t deny  "$DIRTY" '\git rebase main'
t deny  "$DIRTY" '\git reset --hard'
t deny  "$DIRTY" 'eval "git rebase main"'
t deny  "$DIRTY" "eval 'git reset --hard'"
t deny  "$DIRTY" 'eval git rebase main'
# ...benign look-alikes must not fire:
t allow "$DIRTY" 'tar -cf out.tar somedir'
t allow "$DIRTY" 'ls -lc gitdir'
t allow "$DIRTY" 'echo "see eval git usage docs"'

# ===========================================================================
# 2. git clean — all forms denied except dry runs
# ===========================================================================
t deny  "$DIRTY" 'git clean --force'
t deny  "$DIRTY" 'git clean -fd'
t deny  "$DIRTY" 'git clean -f'
t deny  "$DIRTY" 'git clean -xdf'
t deny  "$CLEAN" 'git clean -fd'
t deny  "$DIRTY" 'git clean'
t allow "$DIRTY" 'git clean -n'
t allow "$DIRTY" 'git clean -nd'
t allow "$DIRTY" 'git clean --dry-run'
t deny  "$DIRTY" 'git clean -n && git clean -fd'

# ===========================================================================
# 3. Force push — flag anywhere among args, and +refspec forms
# ===========================================================================
t deny  "$DIRTY" 'git push -f'
t deny  "$DIRTY" 'git push -f origin main'
t deny  "$DIRTY" 'git push origin main -f'
t deny  "$DIRTY" 'git push origin main --force'
t deny  "$DIRTY" 'git push --force-with-lease origin main'
t deny  "$DIRTY" 'git push --force origin main'
t deny  "$CLEAN" 'git push -f origin main'
t deny  "$DIRTY" 'git push origin +main:main'
t deny  "$DIRTY" 'git push origin "+main:main"'
t allow "$DIRTY" 'git push origin main'
t allow "$DIRTY" 'git push -u origin HEAD'
t allow "$DIRTY" 'git push --follow-tags origin main'

# ===========================================================================
# 4. Target-repo resolution (cd / -C / --git-dir) and fail-closed
# ===========================================================================
t deny  "$PLAIN" "cd $DIRTY && git rebase main"
t allow "$PLAIN" "cd $CLEAN && git rebase main"
t deny  "$PLAIN" 'git rebase main'                    # non-repo cwd, no target: closed
t deny  "$CLEAN" "git -C $OTHER reset --hard"
t deny  "$PLAIN" "git -C $OTHER rebase main"
t allow "$CLEAN" "git -C $CLEAN rebase main"
t deny  "$PLAIN" "git --git-dir=$DIRTY/.git rebase main"
# The space-separated --git-dir form is equally valid git and must resolve too.
t deny  "$PLAIN" "git --git-dir $DIRTY/.git rebase main"
t allow "$PLAIN" "git --git-dir $CLEAN/.git rebase main"
t deny  "$PLAIN" "cd $WORK/does-not-exist && git rebase main"   # unresolvable: closed
t allow "$PLAIN" 'ls -la'                             # non-git commands untouched
t allow "$PLAIN" 'echo git'

# ===========================================================================
# 5. Recovery whitelist — must PASS even on a dirty tree
# ===========================================================================
t allow "$DIRTY" 'git rebase --abort'
t allow "$DIRTY" 'git rebase --continue'
t allow "$DIRTY" 'git rebase --skip'
t allow "$DIRTY" 'git rebase --quit'
t allow "$DIRTY" 'git reset'
t allow "$DIRTY" 'git reset HEAD~1'
t allow "$DIRTY" 'git reset --soft HEAD~1'
t allow "$DIRTY" 'git reset --mixed HEAD'
t allow "$DIRTY" 'git restore --staged file.txt'
t allow "$DIRTY" 'git stash list'
t allow "$DIRTY" 'git stash show -p stash@{0}'
t allow "$DIRTY" 'git stash apply refs/snapshots/20250101T000000Z-abc1234'
# ...but the destructive halves stay blocked, including in compounds:
t deny  "$DIRTY" 'git reset --hard'
t deny  "$DIRTY" 'git reset --hard HEAD~1'
t deny  "$DIRTY" 'git reset --keep HEAD~1'
t deny  "$DIRTY" 'git reset --merge'
t deny  "$DIRTY" 'git restore file.txt'
t deny  "$DIRTY" 'git restore --staged --worktree file.txt'
t deny  "$DIRTY" 'git restore --staged -W file.txt'
t deny  "$DIRTY" 'git stash'
t deny  "$DIRTY" 'git stash pop'
t deny  "$DIRTY" 'git stash push -m wip'
t deny  "$DIRTY" 'git rebase --abort && git rebase main'
t deny  "$DIRTY" 'git stash apply x && git stash drop x'
t deny  "$CLEAN" 'git stash drop'
t deny  "$CLEAN" 'git stash clear'

# ===========================================================================
# 6. Existing dirty-gated denials still hold, clean tree still allowed
# ===========================================================================
t deny  "$DIRTY" 'git rebase main'
t deny  "$DIRTY" 'git checkout .'
t deny  "$DIRTY" 'git checkout main -- file.txt'
t deny  "$DIRTY" 'git checkout -f main'
t deny  "$DIRTY" 'git switch --discard-changes main'
t deny  "$DIRTY" 'git branch -f main HEAD~1'
t allow "$CLEAN" 'git rebase main'
t allow "$CLEAN" 'git reset --hard HEAD~1'
t allow "$CLEAN" 'git restore file.txt'
t allow "$DIRTY" 'git status'
t allow "$DIRTY" 'git commit -m "fix"'
t allow "$DIRTY" 'git checkout -b feature'
t allow "$DIRTY" 'git add .claude/settings.json'
t allow "$DIRTY" 'git add .gitignore'
t deny  "$DIRTY" 'git add .'
t deny  "$DIRTY" 'git add -A'

# ===========================================================================
# 6b. New always-denied rules: remote deletion, worktree/branch force-delete
# ===========================================================================
t deny  "$DIRTY" 'git push origin :feature'
t deny  "$CLEAN" 'git push origin :refs/heads/feature'
t deny  "$CLEAN" 'git push --delete origin feature'
t deny  "$DIRTY" 'git push -d origin feature'
t deny  "$CLEAN" 'git worktree remove --force ../wt'
t deny  "$CLEAN" 'git worktree remove -f ../wt'
t deny  "$CLEAN" 'git branch -D feature'
t deny  "$DIRTY" 'git branch --delete --force feature'
# ...their benign look-alikes stay allowed:
t allow "$CLEAN" 'git worktree remove ../wt'      # refuses on dirty trees itself
t allow "$CLEAN" 'git branch -d feature'          # refuses on unmerged work
t allow "$CLEAN" 'git branch --delete feature'
t allow "$DIRTY" 'git push origin HEAD:main'      # colon mid-refspec, no deletion
t allow "$DIRTY" 'git push --dry-run origin main'

# ===========================================================================
# 6c. New dirty-gated rules: ref-moving switches and forced rm
# ===========================================================================
t deny  "$DIRTY" 'git checkout -B main'
t deny  "$DIRTY" 'git switch -C main'
t deny  "$DIRTY" 'git switch --force-create main'
t deny  "$DIRTY" 'git rm -f file.txt'
t deny  "$DIRTY" 'git rm -rf dir'
t deny  "$DIRTY" 'git rm --force file.txt'
t allow "$CLEAN" 'git checkout -B main'
t allow "$CLEAN" 'git switch -C topic'
t allow "$CLEAN" 'git rm -f file.txt'
t allow "$DIRTY" 'git switch -c topic'            # create-only, never clobbers
t allow "$DIRTY" 'git rm --cached file.txt'       # index-only
t allow "$DIRTY" 'git rm file.txt'                # refuses on modified files itself

# ===========================================================================
# 7. False positives that must NOT fire
# ===========================================================================
t allow "$DIRTY" 'echo "recover with (git stash apply ref)"'
t allow "$DIRTY" 'echo "never git reset --hard"'
t allow "$DIRTY" 'digit restore file.txt'
t allow "$DIRTY" 'echo hi && never git reset --hard'

# ===========================================================================
# 8. Bypass escape hatch — allowed, but loudly recorded
# ===========================================================================
run_guard "$DIRTY" 'CLAUDE_GIT_GUARD=off git rebase main'
if [[ "$DECISION" == allow ]] && printf '%s' "$OUT" | jq -e '.systemMessage | test("BYPASSED")' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("inline CLAUDE_GIT_GUARD=off: expected allow + BYPASSED systemMessage")
fi
payload=$(jq -n '{hook_event_name: "PreToolUse", tool_input: {command: "git rebase main"}}')
OUT=$(cd "$DIRTY" && printf '%s' "$payload" | CLAUDE_GIT_GUARD=off bash "$GUARD" 2>/dev/null)
if printf '%s' "$OUT" | jq -e '.systemMessage | test("BYPASSED")' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("env CLAUDE_GIT_GUARD=off: expected allow + BYPASSED systemMessage")
fi

# ===========================================================================
# 9. jq missing — the guard must fail CLOSED for git commands, not silent
# ===========================================================================
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
for tool in bash sh cat grep sed head git date tail mktemp rm; do
    p=$(command -v "$tool" 2>/dev/null) && ln -sf "$p" "$FAKEBIN/$tool"
done
payload=$(jq -n '{hook_event_name: "PreToolUse", tool_input: {command: "git rebase main"}}')
OUT=$(cd "$DIRTY" && printf '%s' "$payload" | env PATH="$FAKEBIN" bash "$GUARD" 2>/dev/null)
rc=$?
if [[ $rc -eq 2 ]]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("jq missing + git payload: expected exit 2 (fail closed), got rc=$rc out=$OUT")
fi
OUT=$(cd "$DIRTY" && printf '%s' '{"tool_input":{"command":"ls -la"}}' | env PATH="$FAKEBIN" bash "$GUARD" 2>/dev/null)
rc=$?
if [[ $rc -eq 0 ]]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("jq missing + non-git payload: expected exit 0, got rc=$rc")
fi

# ===========================================================================
# 10. git-snapshot.sh targets the repo named by -C, not the hook cwd
# ===========================================================================
payload=$(jq -n --arg c "git -C $OTHER rebase main" '{hook_event_name: "PreToolUse", tool_input: {command: $c}}')
(cd "$PLAIN" && printf '%s' "$payload" | bash "$SNAPSHOT" >/dev/null 2>&1)
if [[ -n "$(git -C "$OTHER" for-each-ref refs/snapshots/ 2>/dev/null)" ]]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("git-snapshot.sh did not snapshot the -C target repo")
fi

# ===========================================================================
# 11. merge-hooks.jq — user hooks survive, idempotent, scalar policy
# ===========================================================================
USER_SETTINGS="$WORK/user-settings.json"
cat > "$USER_SETTINGS" <<'EOF'
{
  "permissions": { "defaultMode": "plan" },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "/home/vscode/my-own-hook.sh" },
                   { "type": "command", "command": "/home/vscode/.claude/hooks/my-own-hook.sh" } ] }
    ]
  },
  "enabledPlugins": { "kokko-safety@kokko-ng-kokko-cmds": false }
}
EOF
m1=$(jq -s -f "$MERGE_JQ" "$USER_SETTINGS" "$BUNDLED_SETTINGS")
echo "$m1" > "$WORK/m1.json"
m2=$(jq -s -f "$MERGE_JQ" "$WORK/m1.json" "$BUNDLED_SETTINGS")

check() { # <desc> <jq-bool-expr> <json>
    if printf '%s' "$3" | jq -e "$2" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); FAILED_CASES+=("merge-hooks: $1")
    fi
}
check "synthetic user hook survives the merge" \
    '[.hooks.PreToolUse[].hooks[].command] | index("/home/vscode/my-own-hook.sh") != null' "$m1"
# A user's OWN hook living in ~/.claude/hooks/ — the most natural location —
# must survive too: "ours" matches the three bundled basenames, not the dir.
check "user hook inside .claude/hooks/ survives the merge" \
    '[.hooks.PreToolUse[].hooks[].command] | index("/home/vscode/.claude/hooks/my-own-hook.sh") != null' "$m1"
check "user hook inside .claude/hooks/ survives a second merge" \
    '[.hooks.PreToolUse[].hooks[].command] | index("/home/vscode/.claude/hooks/my-own-hook.sh") != null' "$m2"
check "bundled guard hook is present after merge" \
    '[.hooks.PreToolUse[].hooks[].command] | map(test("guard-git")) | any' "$m1"
check "second merge equals first (idempotent)" \
    ". == $(printf '%s' "$m1" | jq -c .)" "$(printf '%s' "$m2" | jq -c .)"
guards1=$(printf '%s' "$m2" | jq '[.hooks.PreToolUse[].hooks[].command] | map(select(test("guard-git"))) | length')
if [[ "$guards1" == "1" ]]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("merge-hooks: guard hook duplicated after double merge (count=$guards1)")
fi
# The bundle ships kokko-safety as true; the user disabled it — false must win.
check "user's explicit plugin choice wins" \
    '.enabledPlugins["kokko-safety@kokko-ng-kokko-cmds"] == false' "$m1"
check "bundled plugins added when absent" \
    '.enabledPlugins["kokko-git@kokko-ng-kokko-cmds"] == true' "$m1"
check "user's permissions.defaultMode is preserved" \
    '.permissions.defaultMode == "plan"' "$m1"
check "bundled scalars added when absent" \
    '.alwaysThinkingEnabled == true and (.attribution | type == "object")' "$m1"
m3=$(jq -s -f "$MERGE_JQ" <(echo '{}') "$BUNDLED_SETTINGS")
check "empty user file gets bundled defaultMode" \
    '.permissions.defaultMode == "acceptEdits"' "$m3"

# ===========================================================================
# 12. Bundled settings.json is valid JSON
# ===========================================================================
if jq -e . "$BUNDLED_SETTINGS" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("bundled settings.json is not valid JSON")
fi

# ===========================================================================
echo "guard-git-tests: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    printf '  FAIL: %s\n' "${FAILED_CASES[@]}"
    exit 1
fi
exit 0
