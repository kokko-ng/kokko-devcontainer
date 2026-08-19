#!/usr/bin/env bash
# Table-tests the settings pipeline that post-create.sh drives:
#
#   merge-settings.jq  - bundled settings merged into a live settings.json:
#                        user hooks and choices preserved, retired git-safety
#                        hook wiring stripped, acceptEdits -> auto migration,
#                        idempotency.
#   prune-roster.jq    - plugins dropped from the bundled roster are pruned
#                        from the live settings unless the user overrode them.
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

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BUNDLE_JSON="$(cat "$BUNDLED_SETTINGS")"

# ===========================================================================
# 1. The bundle itself: Auto mode on, no hook wiring, no kokko-safety
# ===========================================================================
check "bundled settings.json is valid JSON" '.' "$BUNDLE_JSON"
check "bundled defaultMode is auto" \
    '.permissions.defaultMode == "auto"' "$BUNDLE_JSON"
check "bundle ships no hooks block" \
    'has("hooks") | not' "$BUNDLE_JSON"
check "bundle does not roster kokko-safety" \
    '.enabledPlugins | has("kokko-safety@kokko-ng-kokko-cmds") | not' "$BUNDLE_JSON"
check "bundle suppresses every form of Claude attribution" \
    '.attribution.commit == "" and .attribution.pr == "" and .attribution.sessionUrl == false' "$BUNDLE_JSON"
check "bundle does not ship the deprecated includeCoAuthoredBy" \
    'has("includeCoAuthoredBy") | not' "$BUNDLE_JSON"

# ===========================================================================
# 2. merge-settings.jq - user settings survive, retired wiring is stripped
# ===========================================================================
# A live settings.json as an older bundle left it: the three retired hooks
# wired in, the user's own hooks alongside them, the old acceptEdits default,
# and an explicit plugin opt-out.
USER_SETTINGS="$WORK/user-settings.json"
cat > "$USER_SETTINGS" <<'EOF'
{
  "permissions": { "defaultMode": "acceptEdits" },
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
  "enabledPlugins": { "kokko-viz@kokko-ng-kokko-cmds": false }
}
EOF
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
    '.hooks | (has("UserPromptSubmit") or has("SessionStart")) | not' "$m1"
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

# --- attribution: the sessionUrl backfill and the includeCoAuthoredBy sunset --
# An older bundle shipped attribution WITHOUT sessionUrl. Only-when-absent
# operates on the whole object, so without the sub-key backfill the newer
# sessionUrl would never reach a settings.json that already has the block.
m_attr_old=$(jq -s -f "$MERGE_JQ" <(echo '{"attribution":{"commit":"","pr":""}}') "$BUNDLED_SETTINGS")
check "sessionUrl is backfilled into an older attribution block" \
    '.attribution.sessionUrl == false' "$m_attr_old"
check "backfill leaves commit and pr alone" \
    '.attribution.commit == "" and .attribution.pr == ""' "$m_attr_old"

# A sessionUrl the user set is a choice and wins, same as every other scalar.
m_attr_user=$(jq -s -f "$MERGE_JQ" <(echo '{"attribution":{"commit":"","pr":"","sessionUrl":true}}') "$BUNDLED_SETTINGS")
check "user-set sessionUrl is preserved" \
    '.attribution.sessionUrl == true' "$m_attr_user"

# Custom attribution text must survive the backfill untouched.
m_attr_text=$(jq -s -f "$MERGE_JQ" <(echo '{"attribution":{"commit":"mine","pr":""}}') "$BUNDLED_SETTINGS")
check "user attribution text survives the backfill" \
    '.attribution.commit == "mine" and .attribution.sessionUrl == false' "$m_attr_text"

# includeCoAuthoredBy is deprecated. A false value is redundant once the
# attribution block is present, so it goes; a true value is a deliberate
# request to be credited and stays.
m_dep_false=$(jq -s -f "$MERGE_JQ" <(echo '{"includeCoAuthoredBy":false}') "$BUNDLED_SETTINGS")
check "deprecated includeCoAuthoredBy=false is dropped" \
    '(has("includeCoAuthoredBy") | not) and .attribution.sessionUrl == false' "$m_dep_false"
m_dep_true=$(jq -s -f "$MERGE_JQ" <(echo '{"includeCoAuthoredBy":true}') "$BUNDLED_SETTINGS")
check "deliberate includeCoAuthoredBy=true is left alone" \
    '.includeCoAuthoredBy == true' "$m_dep_true"

# Both migrations must be idempotent across repeated post-create runs.
m_attr_twice=$(jq -s -f "$MERGE_JQ" <(printf '%s' "$m_dep_false") "$BUNDLED_SETTINGS")
check "attribution migrations are idempotent" \
    ". == $(printf '%s' "$m_dep_false" | jq -c .)" "$(printf '%s' "$m_attr_twice" | jq -c .)"

# A defaultMode the user chose (anything but the old bundled acceptEdits)
# must never be migrated.
m_plan=$(jq -s -f "$MERGE_JQ" <(echo '{"permissions":{"defaultMode":"plan"}}') "$BUNDLED_SETTINGS")
check "user-chosen defaultMode is preserved" \
    '.permissions.defaultMode == "plan"' "$m_plan"

# A fresh/empty settings file gets the bundled defaults and no hooks key.
m_empty=$(jq -s -f "$MERGE_JQ" <(echo '{}') "$BUNDLED_SETTINGS")
check "empty user file gets bundled defaultMode auto" \
    '.permissions.defaultMode == "auto"' "$m_empty"
check "merge invents no hooks key" \
    'has("hooks") | not' "$m_empty"

# When ONLY retired wiring existed, the hooks key disappears entirely.
m_only_ours=$(jq -s -f "$MERGE_JQ" <(jq 'del(.hooks.PreToolUse[0].hooks[2,3])' "$USER_SETTINGS") "$BUNDLED_SETTINGS")
check "hooks key is dropped once only retired wiring remains" \
    'has("hooks") | not' "$m_only_ours"

# ===========================================================================
# 3. Old-container upgrade path: merge + roster prune together
# ===========================================================================
# The previous bundle's roster snapshot shipped kokko-safety; the new bundle
# dropped it; the user never overrode it - so the prune removes it.
cat > "$WORK/prev-roster.json" <<'EOF'
{
  "enabledPlugins": {
    "kokko-safety@kokko-ng-kokko-cmds": true,
    "kokko-git@kokko-ng-kokko-cmds": true
  },
  "extraKnownMarketplaces": {}
}
EOF
old_live="$WORK/old-live.json"
jq '.enabledPlugins["kokko-safety@kokko-ng-kokko-cmds"] = true' "$WORK/m1.json" > "$old_live"
upgraded=$(jq -s -f "$PRUNE_JQ" "$WORK/prev-roster.json" "$BUNDLED_SETTINGS" "$old_live")
check "upgrade prunes kokko-safety from the live roster" \
    '.enabledPlugins | has("kokko-safety@kokko-ng-kokko-cmds") | not' "$upgraded"
check "upgrade keeps the still-bundled plugins" \
    '.enabledPlugins["kokko-git@kokko-ng-kokko-cmds"] == true' "$upgraded"
check "upgraded settings run in auto mode with no retired wiring" \
    '(.permissions.defaultMode == "auto") and ((tostring | test("guard-git|git-snapshot|session-git-safety")) | not)' "$upgraded"

# ===========================================================================
# 4. prune-roster.jq - general semantics (user overrides always survive)
# ===========================================================================
cat > "$WORK/gen-prev.json" <<'EOF'
{
  "enabledPlugins": {
    "keep-me@mkt": true,
    "removed-untouched@mkt": true,
    "removed-overridden@mkt": true
  },
  "extraKnownMarketplaces": {
    "dead-mkt": { "source": { "source": "github", "repo": "x/dead" } }
  }
}
EOF
cat > "$WORK/gen-new.json" <<'EOF'
{ "enabledPlugins": { "keep-me@mkt": true }, "extraKnownMarketplaces": {} }
EOF
cat > "$WORK/gen-live.json" <<'EOF'
{
  "enabledPlugins": {
    "keep-me@mkt": true,
    "removed-untouched@mkt": true,
    "removed-overridden@mkt": false,
    "own-plugin@mkt": true
  },
  "extraKnownMarketplaces": {
    "dead-mkt": { "source": { "source": "github", "repo": "x/dead" } }
  }
}
EOF
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
