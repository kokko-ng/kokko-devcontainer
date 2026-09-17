#!/usr/bin/env bash
# Table-tests the settings pipeline that post-create.sh drives:
#
#   merge-settings.jq     - bundled settings merged into a live settings.json:
#                           user hooks and choices preserved, retired git-safety
#                           hook wiring stripped, the bundled SessionStart hook
#                           wired in exactly once, acceptEdits -> auto migration,
#                           the dead skipDangerousModePermissionPrompt dropped,
#                           env and sandbox merged additively, idempotency.
#   prune-roster.jq       - plugins and env keys dropped from the bundled roster
#                           are pruned from the live settings unless the user
#                           overrode them.
#   managed-settings.json - the policy file post-create.sh installs to
#                           /etc/claude-code/: bypass mode locked, deny list
#                           present and scoped.
#   hooks/session-provision-status.sh - the SessionStart hook: prints the
#                           provisioning ledger when it is non-empty, nothing
#                           otherwise, and never fails.
#
# These run against the TEMPLATE payload, not a rendered project: the settings
# pipeline is deliberately kept free of Jinja (see cookiecutter.json ->
# _copy_without_render), so the files under test are valid jq and valid JSON at
# rest and need no cookiecutter to exercise.
#
# Needs only bash and jq. Run: bash tests/merge-settings-tests.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_CONFIG="$ROOT/{{cookiecutter.project_slug}}/.devcontainer/config/claude"
MERGE_JQ="$CLAUDE_CONFIG/merge-settings.jq"
PRUNE_JQ="$CLAUDE_CONFIG/prune-roster.jq"
BUNDLED_SETTINGS="$CLAUDE_CONFIG/settings.json"
MANAGED_SETTINGS="$CLAUDE_CONFIG/managed-settings.json"
STATUS_HOOK="$CLAUDE_CONFIG/hooks/session-provision-status.sh"
# The command string the bundle wires in; the live file carries it verbatim.
# shellcheck disable=SC2016  # the literal $HOME is what the bundle wires in
HOOK_CMD='$HOME/.claude/hooks/session-provision-status.sh'

PASS=0
FAIL=0
FAILED_CASES=()

check() { # <desc> <jq-bool-expr> <json>
    if printf '%s' "$3" | jq -e "$2" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); FAILED_CASES+=("$1")
    fi
}

# assert <desc> <cmd...> — the command's exit status is the assertion.
assert() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); FAILED_CASES+=("$desc"); fi
}

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BUNDLE_JSON="$(cat "$BUNDLED_SETTINGS")"
MANAGED_JSON="$(cat "$MANAGED_SETTINGS")"

# ===========================================================================
# 1. The bundle itself: Auto mode on, one informational hook, no kokko-safety,
#    the Bash tool limits, the sandbox ready but off. Policy is NOT here.
# ===========================================================================
check "bundled settings.json is valid JSON" '.' "$BUNDLE_JSON"
check "bundled defaultMode is auto" \
    '.permissions.defaultMode == "auto"' "$BUNDLE_JSON"
check "bundle wires only the SessionStart status hook" \
    "(.hooks | keys) == [\"SessionStart\"]
       and ([.hooks.SessionStart[].hooks[].command] == [\"$HOOK_CMD\"])" "$BUNDLE_JSON"
check "bundle does not roster kokko-safety" \
    '.enabledPlugins | has("kokko-safety@kokko-ng-kokko-cmds") | not' "$BUNDLE_JSON"
check "bundle no longer ships skipDangerousModePermissionPrompt" \
    'has("skipDangerousModePermissionPrompt") | not' "$BUNDLE_JSON"
check "bundle raises the Bash tool limits" \
    '.env.BASH_DEFAULT_TIMEOUT_MS == "600000"
       and .env.BASH_MAX_TIMEOUT_MS == "1800000"
       and .env.BASH_MAX_OUTPUT_LENGTH == "100000"' "$BUNDLE_JSON"
check "bundle ships the sandbox configured for a container but switched off" \
    '.sandbox.enabled == false
       and .sandbox.enableWeakerNestedSandbox == true
       and (.sandbox.excludedCommands | index("docker *") != null)' "$BUNDLE_JSON"
check "bundle carries no policy keys (those live in managed-settings.json)" \
    '(.permissions | has("deny") or has("disableBypassPermissionsMode")) | not' "$BUNDLE_JSON"

check "managed-settings.json is valid JSON" '.' "$MANAGED_JSON"
check "managed settings lock bypass mode" \
    '.permissions.disableBypassPermissionsMode == "disable"' "$MANAGED_JSON"
check "managed settings deny every force-push spelling" \
    '.permissions.deny
       | (index("Bash(git push --force*)") != null)
       and (index("Bash(git push -f*)") != null)
       and (index("Bash(git push * --force*)") != null)
       and (index("Bash(git push * -f*)") != null)' "$MANAGED_JSON"
check "managed settings deny the destructive cloud, docker and gh operations" \
    '.permissions.deny
       | (index("Bash(az * delete*)") != null)
       and (index("Bash(docker volume prune*)") != null)
       and (index("Bash(gh repo delete*)") != null)' "$MANAGED_JSON"
# A bare "Bash" deny would remove the tool from Claude entirely; every rule
# must be scoped to a command pattern.
check "every deny rule is a scoped Bash pattern" \
    '.permissions.deny | all(test("^Bash\\(.+\\)$"))' "$MANAGED_JSON"
check "managed settings carry no allow rules or defaults" \
    '(.permissions | has("allow") or has("defaultMode")) | not' "$MANAGED_JSON"

# ===========================================================================
# 2. merge-settings.jq - user settings survive, retired wiring is stripped,
#    the bundled hook is wired exactly once
# ===========================================================================
# A live settings.json as an older bundle left it: the three retired hooks
# wired in, the user's own hooks alongside them, the old acceptEdits default,
# the old skipDangerousModePermissionPrompt, an explicit plugin opt-out, a
# shorter Bash timeout, and the sandbox already switched on.
USER_SETTINGS="$WORK/user-settings.json"
cat > "$USER_SETTINGS" <<'JSON'
{
  "permissions": { "defaultMode": "acceptEdits" },
  "skipDangerousModePermissionPrompt": true,
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "/home/vscode/.claude/hooks/git-snapshot.sh", "timeout": 15 },
                   { "type": "command", "command": "/home/vscode/.claude/hooks/guard-git.sh", "timeout": 10 },
                   { "type": "command", "command": "/home/vscode/my-own-hook.sh" },
                   { "type": "command", "command": "/home/vscode/.claude/hooks/my-own-hook.sh" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "/home/vscode/.claude/hooks/git-snapshot.sh", "timeout": 15 } ] }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "/home/vscode/.claude/hooks/session-git-safety.sh", "timeout": 10 } ] }
    ]
  },
  "enabledPlugins": { "kokko-viz@kokko-ng-kokko-cmds": false },
  "env": { "BASH_DEFAULT_TIMEOUT_MS": "120000", "MY_VAR": "x" },
  "sandbox": { "enabled": true }
}
JSON
m1=$(jq -s -f "$MERGE_JQ" "$USER_SETTINGS" "$BUNDLED_SETTINGS")
echo "$m1" > "$WORK/m1.json"
m2=$(jq -s -f "$MERGE_JQ" "$WORK/m1.json" "$BUNDLED_SETTINGS")

check "user hook outside .claude/hooks/ survives" \
    '[.hooks.PreToolUse[].hooks[].command] | index("/home/vscode/my-own-hook.sh") != null' "$m1"
# A user's OWN hook living in ~/.claude/hooks/ - the natural location - must
# survive too: "ours" matches the three retired basenames, not the directory.
check "user hook inside .claude/hooks/ survives" \
    '[.hooks.PreToolUse[].hooks[].command] | index("/home/vscode/.claude/hooks/my-own-hook.sh") != null' "$m1"
check "retired guard-git wiring is stripped" \
    '[.hooks.PreToolUse[].hooks[].command] | map(test("guard-git")) | any | not' "$m1"
check "retired git-snapshot wiring is stripped" \
    '(.hooks | tostring | test("git-snapshot")) | not' "$m1"
check "event emptied by the strip is dropped" \
    '.hooks | has("UserPromptSubmit") | not' "$m1"
# SessionStart carried only retired wiring; after the strip it holds exactly
# the bundled status hook.
check "SessionStart holds only the bundled status hook after the strip" \
    "[.hooks.SessionStart[].hooks[].command] == [\"$HOOK_CMD\"]" "$m1"
check "second merge equals first (idempotent)" \
    ". == $(printf '%s' "$m1" | jq -c .)" "$(printf '%s' "$m2" | jq -c .)"
check "user's explicit plugin opt-out wins" \
    '.enabledPlugins["kokko-viz@kokko-ng-kokko-cmds"] == false' "$m1"
check "bundled plugins added when absent" \
    '.enabledPlugins["kokko-git@kokko-ng-kokko-cmds"] == true' "$m1"
check "old bundled acceptEdits migrates to auto" \
    '.permissions.defaultMode == "auto"' "$m1"
check "bundled scalars added when absent" \
    '.alwaysThinkingEnabled == true and (.attribution | type == "object")' "$m1"
check "old bundled skipDangerousModePermissionPrompt is dropped" \
    'has("skipDangerousModePermissionPrompt") | not' "$m1"
check "user's env value wins, bundled env keys fill the gaps, own keys survive" \
    '.env.BASH_DEFAULT_TIMEOUT_MS == "120000"
       and .env.BASH_MAX_TIMEOUT_MS == "1800000"
       and .env.MY_VAR == "x"' "$m1"
check "user's sandbox toggle wins, bundled sandbox keys fill the gaps" \
    '.sandbox.enabled == true
       and .sandbox.enableWeakerNestedSandbox == true
       and (.sandbox.excludedCommands | index("docker *") != null)' "$m1"

# A defaultMode the user chose (anything but the old bundled acceptEdits)
# must never be migrated.
m_plan=$(jq -s -f "$MERGE_JQ" <(echo '{"permissions":{"defaultMode":"plan"}}') "$BUNDLED_SETTINGS")
check "user-chosen defaultMode is preserved" \
    '.permissions.defaultMode == "plan"' "$m_plan"

# skipDangerousModePermissionPrompt: only the old bundled `true` is dropped.
m_skip_false=$(jq -s -f "$MERGE_JQ" <(echo '{"skipDangerousModePermissionPrompt":false}') "$BUNDLED_SETTINGS")
check "a user-set skipDangerousModePermissionPrompt=false is preserved" \
    '.skipDangerousModePermissionPrompt == false' "$m_skip_false"

# A fresh/empty settings file gets the bundled defaults and the status hook.
m_empty=$(jq -s -f "$MERGE_JQ" <(echo '{}') "$BUNDLED_SETTINGS")
check "empty user file gets bundled defaultMode auto" \
    '.permissions.defaultMode == "auto"' "$m_empty"
check "empty user file gets exactly the bundled SessionStart hook" \
    "(.hooks | keys) == [\"SessionStart\"]
       and ([.hooks.SessionStart[].hooks[].command] == [\"$HOOK_CMD\"])" "$m_empty"
check "empty user file gets the bundled env and sandbox" \
    '.env.BASH_MAX_TIMEOUT_MS == "1800000" and .sandbox.enabled == false' "$m_empty"

# When ONLY retired wiring existed, nothing but the bundled hook remains.
m_only_ours=$(jq -s -f "$MERGE_JQ" <(jq 'del(.hooks.PreToolUse[0].hooks[2,3])' "$USER_SETTINGS") "$BUNDLED_SETTINGS")
check "only the bundled hook remains once retired wiring is stripped" \
    "(.hooks | keys) == [\"SessionStart\"]
       and ([.hooks.SessionStart[].hooks[].command] == [\"$HOOK_CMD\"])" "$m_only_ours"

# A live file that already wires the bundled hook — with the user's own
# timeout — gets no second copy, and the user's edit survives.
m_custom=$(jq -s -f "$MERGE_JQ" <(cat <<JSON
{ "hooks": { "SessionStart": [
    { "hooks": [ { "type": "command", "command": "$HOOK_CMD", "timeout": 3 } ] } ] } }
JSON
) "$BUNDLED_SETTINGS")
check "an already-wired status hook is not duplicated" \
    "[.hooks.SessionStart[].hooks[].command | select(. == \"$HOOK_CMD\")] | length == 1" "$m_custom"
check "the user's edit to the bundled hook entry survives" \
    '.hooks.SessionStart[0].hooks[0].timeout == 3' "$m_custom"

# A user's own SessionStart hook is kept, and the bundled one is added
# alongside it — once.
m_own=$(jq -s -f "$MERGE_JQ" <(echo '{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"/home/vscode/banner.sh"}]}]}}') "$BUNDLED_SETTINGS")
echo "$m_own" > "$WORK/m_own.json"
m_own2=$(jq -s -f "$MERGE_JQ" "$WORK/m_own.json" "$BUNDLED_SETTINGS")
check "user's own SessionStart hook survives next to the bundled one" \
    "[.hooks.SessionStart[].hooks[].command] == [\"/home/vscode/banner.sh\", \"$HOOK_CMD\"]" "$m_own"
check "merging again adds nothing next to a user's own SessionStart hook" \
    ". == $(printf '%s' "$m_own" | jq -c .)" "$(printf '%s' "$m_own2" | jq -c .)"

# ===========================================================================
# 3. Old-container upgrade path: merge + roster prune together
# ===========================================================================
# The previous bundle's roster snapshot shipped kokko-safety; the new bundle
# dropped it; the user never overrode it - so the prune removes it.
cat > "$WORK/prev-roster.json" <<'JSON'
{
  "enabledPlugins": {
    "kokko-safety@kokko-ng-kokko-cmds": true,
    "kokko-git@kokko-ng-kokko-cmds": true
  },
  "extraKnownMarketplaces": {}
}
JSON
old_live="$WORK/old-live.json"
jq '.enabledPlugins["kokko-safety@kokko-ng-kokko-cmds"] = true' "$WORK/m1.json" > "$old_live"
upgraded=$(jq -s -f "$PRUNE_JQ" "$WORK/prev-roster.json" "$BUNDLED_SETTINGS" "$old_live")
check "upgrade prunes kokko-safety from the live roster" \
    '.enabledPlugins | has("kokko-safety@kokko-ng-kokko-cmds") | not' "$upgraded"
check "upgrade keeps the still-bundled plugins" \
    '.enabledPlugins["kokko-git@kokko-ng-kokko-cmds"] == true' "$upgraded"
check "upgraded settings run in auto mode with no retired wiring" \
    '(.permissions.defaultMode == "auto") and ((tostring | test("guard-git|git-snapshot|session-git-safety")) | not)' "$upgraded"
# A pre-4.0 snapshot has no env/sandbox section: the prune must leave those
# untouched rather than treating "absent" as "shipped and now dropped".
check "a snapshot without env leaves the live env alone" \
    '.env.BASH_DEFAULT_TIMEOUT_MS == "120000" and .env.MY_VAR == "x"' "$upgraded"

# ===========================================================================
# 4. prune-roster.jq - general semantics (user overrides always survive)
# ===========================================================================
cat > "$WORK/gen-prev.json" <<'JSON'
{
  "enabledPlugins": {
    "keep-me@mkt": true,
    "removed-untouched@mkt": true,
    "removed-overridden@mkt": true
  },
  "extraKnownMarketplaces": {
    "dead-mkt": { "source": { "source": "github", "repo": "x/dead" } }
  },
  "env": { "KEEP_ENV": "1", "REMOVED_ENV": "1", "REMOVED_ENV_OVERRIDDEN": "1" }
}
JSON
cat > "$WORK/gen-new.json" <<'JSON'
{ "enabledPlugins": { "keep-me@mkt": true }, "extraKnownMarketplaces": {}, "env": { "KEEP_ENV": "1" } }
JSON
cat > "$WORK/gen-live.json" <<'JSON'
{
  "enabledPlugins": {
    "keep-me@mkt": true,
    "removed-untouched@mkt": true,
    "removed-overridden@mkt": false,
    "own-plugin@mkt": true
  },
  "extraKnownMarketplaces": {
    "dead-mkt": { "source": { "source": "github", "repo": "x/dead" } }
  },
  "env": { "KEEP_ENV": "1", "REMOVED_ENV": "1", "REMOVED_ENV_OVERRIDDEN": "9", "MY_ENV": "2" }
}
JSON
pruned=$(jq -s -f "$PRUNE_JQ" "$WORK/gen-prev.json" "$WORK/gen-new.json" "$WORK/gen-live.json")
check "removed-and-untouched plugin is pruned" \
    '.enabledPlugins | has("removed-untouched@mkt") | not' "$pruned"
check "removed-but-user-overridden plugin survives" \
    '.enabledPlugins["removed-overridden@mkt"] == false' "$pruned"
check "still-bundled plugin survives the prune" \
    '.enabledPlugins["keep-me@mkt"] == true' "$pruned"
check "user's own plugin (never bundled) survives the prune" \
    '.enabledPlugins["own-plugin@mkt"] == true' "$pruned"
check "removed marketplace is pruned" \
    '.extraKnownMarketplaces | has("dead-mkt") | not' "$pruned"
check "removed-and-untouched env key is pruned" \
    '.env | has("REMOVED_ENV") | not' "$pruned"
check "removed-but-user-overridden env key survives" \
    '.env.REMOVED_ENV_OVERRIDDEN == "9"' "$pruned"
check "still-bundled and user's own env keys survive the prune" \
    '.env.KEEP_ENV == "1" and .env.MY_ENV == "2"' "$pruned"

# ===========================================================================
# 5. hooks/session-provision-status.sh - the SessionStart hook
# ===========================================================================
assert "status hook is executable" test -x "$STATUS_HOOK"
printf '2026-01-01T00:00:00Z FAILED: uv-sync\n2026-01-01T00:00:01Z FAILED: frontend-deps\n' > "$WORK/ledger"
: > "$WORK/empty-ledger"
# Claude Code feeds the hook a JSON event on stdin; it must be ignored, not
# read as the ledger.
STDIN_EVENT='{"hook_event_name":"SessionStart","source":"startup"}'
hook_output() { # <ledger> [stdin]
    printf '%s' "${2:-}" | DEVCONTAINER_PROVISION_STATUS="$1" bash "$STATUS_HOOK"
}
assert "status hook is silent when no step failed" \
    test -z "$(hook_output "$WORK/empty-ledger" "$STDIN_EVENT")"
assert "status hook is silent when the ledger does not exist" \
    test -z "$(hook_output "$WORK/does-not-exist")"
ledger_out="$(hook_output "$WORK/ledger" "$STDIN_EVENT")"
assert "status hook prints the first failed step" grep -q "FAILED: uv-sync" <<<"$ledger_out"
assert "status hook prints the second failed step" grep -q "FAILED: frontend-deps" <<<"$ledger_out"
assert "status hook points at the provisioning log" grep -q "post-create.log" <<<"$ledger_out"
assert "status hook exits 0 with a non-empty ledger" hook_output "$WORK/ledger"
if command -v shellcheck >/dev/null 2>&1; then
    assert "status hook is shellcheck-clean" shellcheck --severity=info "$STATUS_HOOK"
else
    echo "note: shellcheck not installed — skipping the hook lint"
fi

# ===========================================================================
# Report
# ===========================================================================
echo ""
echo "settings pipeline test results"
echo "------------------------------"
if [[ ${#FAILED_CASES[@]} -gt 0 ]]; then
    for case_name in "${FAILED_CASES[@]}"; do
        echo "FAIL  $case_name"
    done
fi
echo "passed: $PASS  failed: $FAIL  total: $((PASS + FAIL))"
[[ "$FAIL" -eq 0 ]]
