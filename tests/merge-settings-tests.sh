#!/usr/bin/env bash
# Table-tests the settings pipeline that post-create.sh drives:
#
#   merge-settings.jq     - bundled settings merged into a live settings.json:
#                           user hooks and choices preserved, retired git-safety
#                           hook wiring stripped, the bundled SessionStart hook
#                           wired in exactly once, acceptEdits -> auto migration,
#                           the dead skipDangerousModePermissionPrompt dropped,
#                           env and sandbox merged additively, tui and autoMode
#                           added only when absent, idempotency.
#   prune-roster.jq       - plugins and env keys dropped from the bundled roster
#                           are pruned from the live settings unless the user
#                           overrode them.
#   managed-settings.json - the policy file post-create.sh installs to
#                           /etc/claude-code/: bypass mode locked, Bash sandbox
#                           forced off, deny list present and scoped.
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
MISSING_JQ="$CLAUDE_CONFIG/missing-plugins.jq"
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
check "bundle rosters impeccable with its marketplace" \
    '.enabledPlugins["impeccable@impeccable"] == true
       and .extraKnownMarketplaces.impeccable.source.repo == "pbakaus/impeccable"' "$BUNDLE_JSON"
# skills.json drives install_claude_skills: every entry needs a path-safe
# name, an owner/repo and a full commit SHA (a branch name would float).
check "skills.json lists asd-ste100 and every entry is pinned to a commit" \
    '(.skills | map(.name) | index("asd-ste100") != null)
       and all(.skills[]; (.name | test("^[A-Za-z0-9._-]+$"))
                          and (.repo | test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"))
                          and (.ref | test("^[0-9a-f]{40}$")))' "$(cat "$CLAUDE_CONFIG/skills.json")"
# The bundled autoMode block is Claude Code's defaults plus the bundle's own
# rules (scripts/auto-mode/): its own rules are exactly own-rules.json's, last.
# shellcheck disable=SC2016  # $own is a jq variable
assert "bundled autoMode.allow ends with own-rules.json's rules" \
    jq -e --slurpfile own "$ROOT/scripts/auto-mode/own-rules.json" \
    '.autoMode.allow[-($own[0].allow | length):] == $own[0].allow' "$BUNDLED_SETTINGS"
check "policy denies squash merges" \
    '[.permissions.deny[] | select(test("squash"))] | length >= 3' "$MANAGED_JSON"
check "bundle no longer rosters kokko-code-quality or kokko-janitor" \
    '(.enabledPlugins | keys | map(select(test("kokko-code-quality|kokko-janitor"))) | length == 0)
       and (.extraKnownMarketplaces | has("kokko-ng-kokko-janitor") | not)' "$BUNDLE_JSON"
check "bundle no longer rosters kokko-notifications" \
    '.enabledPlugins | has("kokko-notifications@kokko-ng-kokko-cmds") | not' "$BUNDLE_JSON"
check "bundle no longer rosters theme-sync or its marketplace" \
    '(.enabledPlugins | has("theme-sync@kokko-claude-mods") | not)
       and (.extraKnownMarketplaces | has("kokko-claude-mods") | not)' "$BUNDLE_JSON"
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
check "bundle defaults Claude Code to the fullscreen renderer" \
    '.tui == "fullscreen"' "$BUNDLE_JSON"
# A custom autoMode.allow or environment REPLACES Claude Code's defaults, so
# the bundle carries all of them (claude auto-mode defaults: 17 allow rules)
# plus its own six rules and environment entries (scripts/auto-mode/).
check "bundle autoMode allow keeps Claude Code's 17 defaults and adds six rules" \
    '(.autoMode | keys) == ["allow", "environment"]
       and (.autoMode.allow | length == 23)
       and ([.autoMode.allow[] | split(":")[0]]
            | (.[0] == "Security Discussion")
              and (index("Read-Only Operations") != null)
              and (index("Git Push Destination") != null)
              and (index("Browser Trusted Navigation") == 16)
              and (.[17:] == ["Own-Repo PR Merge", "Own-Org Repositories", "Approved Sandbox Redeploy",
                              "Sandbox Deploy on Request", "Sandbox Secret Writes", "Repo Script Service Keys"]))' "$BUNDLE_JSON"
check "bundle autoMode environment names the user's orgs and the prod markers" \
    '[.autoMode.environment[] | select(startswith("**Source control**") or startswith("**Sensitive remote targets**"))]
       | length == 2 and (.[0] | test("Insight-Services-APAC")) and (.[1] | test("prd"))' "$BUNDLE_JSON"
check "the PR-merge rule keeps squash merges and red checks out" \
    '.autoMode.allow[17] | test("Squash merges are never wanted") and test("--admin")' "$BUNDLE_JSON"
check "the redeploy rule covers sandbox/dev/demo targets and never prod" \
    '.autoMode.allow[19] | test("sandbox, dev or demo") and test("prod or production")' "$BUNDLE_JSON"
check "the sandbox deploy, secret and key rules are scoped to sandbox, dev or demo targets" \
    '[.autoMode.allow[20:23][] | test("named sandbox, dev or demo")] == [true, true, true]' "$BUNDLE_JSON"
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
check "managed settings deny the destructive docker and gh operations" \
    '.permissions.deny
       | (index("Bash(docker volume prune*)") != null)
       and (index("Bash(gh repo delete*)") != null)' "$MANAGED_JSON"
check "Azure delete and purge always ask instead of being denied" \
    '(.permissions.ask | index("Bash(az * delete*)") != null and index("Bash(az * purge*)") != null)
       and (.permissions.deny | map(select(test("^Bash\\(az .*(delete|purge)"))) | length == 0)' "$MANAGED_JSON"
# A bare "Bash" deny would remove the tool from Claude entirely; every rule
# must be scoped to a command pattern.
check "every deny and ask rule is a scoped Bash, Read or Edit pattern" \
    '(.permissions.deny + .permissions.ask) | all(test("^(Bash|Read|Edit)\\(.+\\)$"))' "$MANAGED_JSON"
# The shared sign-ins are reachable inside the container (the firewall, not
# the policy, limits where they can go); the policy at least refuses to read
# the Claude token file or print the gh and az tokens on an agent's behalf.
# Claude Code's own Bash sandbox is not used: bubblewrap cannot create user
# namespaces in an unprivileged container. The policy forces it off, so a
# project's own .claude/settings.local.json (on the bind-mounted workspace)
# cannot switch it on and send every command to an unsandboxed-retry prompt.
check "policy forces the Bash sandbox off" \
    '.sandbox == {enabled: false}' "$MANAGED_JSON"
check "policy denies reading the shared Claude token" \
    '.permissions.deny | index("Read(~/.config/claude-auth/**)") != null' "$MANAGED_JSON"
# CLAUDE_CODE_SUBPROCESS_ENV_SCRUB forces the permission mode back to default,
# which would switch Auto mode off: the policy must never set it.
check "policy leaves Auto mode on (no subprocess env scrub)" \
    '(.env // {}) | has("CLAUDE_CODE_SUBPROCESS_ENV_SCRUB") | not' "$MANAGED_JSON"
check "policy denies printing gh and az tokens" \
    '(.permissions.deny | index("Bash(gh auth token*)") != null)
       and (.permissions.deny | index("Bash(az account get-access-token*)") != null)' "$MANAGED_JSON"
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
check "tui and autoMode are added when absent" \
    ".tui == \"fullscreen\" and .autoMode == $(printf '%s' "$BUNDLE_JSON" | jq -c .autoMode)" "$m1"
check "user's sandbox toggle wins, bundled sandbox keys fill the gaps" \
    '.sandbox.enabled == true
       and .sandbox.enableWeakerNestedSandbox == true
       and (.sandbox.excludedCommands | index("docker *") != null)' "$m1"

# A defaultMode the user chose (anything but the old bundled acceptEdits)
# must never be migrated.
m_plan=$(jq -s -f "$MERGE_JQ" <(echo '{"permissions":{"defaultMode":"plan"}}') "$BUNDLED_SETTINGS")
check "user-chosen defaultMode is preserved" \
    '.permissions.defaultMode == "plan"' "$m_plan"

# tui and autoMode: a user's own choice wins, whole, and survives a re-merge.
USER_CHOICES='{"tui":"default","autoMode":{"allow":["Mine: my rule"],"environment":["My env"]}}'
m_choice=$(jq -s -f "$MERGE_JQ" <(echo "$USER_CHOICES") "$BUNDLED_SETTINGS")
m_choice2=$(jq -s -f "$MERGE_JQ" <(echo "$m_choice") "$BUNDLED_SETTINGS")
check "a user's /tui default choice is preserved" '.tui == "default"' "$m_choice"
check "a user's own autoMode block is preserved whole" \
    ".autoMode == $(printf '%s' "$USER_CHOICES" | jq -c .autoMode)" "$m_choice"
check "merging again keeps the user's tui and autoMode" \
    ". == $(printf '%s' "$m_choice" | jq -c .)" "$(printf '%s' "$m_choice2" | jq -c .)"

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
# The 6.3 bundle shipped theme-sync and its marketplace; 6.4 dropped both.
cat > "$WORK/prev-roster-63.json" <<'JSON'
{
  "enabledPlugins": {
    "kokko-git@kokko-ng-kokko-cmds": true,
    "kokko-notifications@kokko-ng-kokko-cmds": true,
    "theme-sync@kokko-claude-mods": true
  },
  "extraKnownMarketplaces": {
    "kokko-claude-mods": {"source": {"source": "github", "repo": "kokko-ng/kokko-claude-mods"}}
  }
}
JSON
jq -s '.[0] * {enabledPlugins: .[1].enabledPlugins, extraKnownMarketplaces: .[1].extraKnownMarketplaces}' \
    "$WORK/m1.json" "$WORK/prev-roster-63.json" > "$WORK/old-live-63.json"
upgraded63=$(jq -s -f "$PRUNE_JQ" "$WORK/prev-roster-63.json" "$BUNDLED_SETTINGS" "$WORK/old-live-63.json")
check "upgrade prunes kokko-notifications from the live roster" \
    '.enabledPlugins | has("kokko-notifications@kokko-ng-kokko-cmds") | not' "$upgraded63"
check "upgrade from 6.3 prunes theme-sync and the kokko-claude-mods marketplace" \
    '(.enabledPlugins | has("theme-sync@kokko-claude-mods") | not)
       and (.extraKnownMarketplaces | has("kokko-claude-mods") | not)
       and .enabledPlugins["kokko-git@kokko-ng-kokko-cmds"] == true' "$upgraded63"
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
# missing-plugins.jq - enabled plugins the cache lacks bypass the 24h window
# ===========================================================================
mkdir -p "$WORK/mp-cache/a"
cat > "$WORK/mp-settings.json" <<'JSON'
{ "enabledPlugins": { "a@m": true, "b@m": true, "gone@m": true, "off@m": false } }
JSON
cat > "$WORK/mp-installed.json" <<JSON
{ "version": 2, "plugins": {
  "a@m": [ { "version": "1.0.0", "installPath": "$WORK/mp-cache/a" } ],
  "gone@m": [ { "version": "1.0.0", "installPath": "$WORK/mp-cache/gone" } ] } }
JSON
# The same loop post-create.sh runs: a plugin is missing when it has no
# recorded install path or the path is not a directory.
mp_missing() { # <installed.json>
    local name path out=""
    while IFS=$'\t' read -r name path; do
        [[ -n "$name" ]] || continue
        [[ -n "$path" && -d "$path" ]] || out="${out:+$out }$name"
    done < <(jq -rn --slurpfile settings "$WORK/mp-settings.json" --slurpfile installed "$1" -f "$MISSING_JQ")
    printf '%s' "$out"
}
mp_out=$(mp_missing "$WORK/mp-installed.json")
assert "missing-plugins flags an enabled plugin that was never installed" grep -qw 'b@m' <<<"$mp_out"
assert "missing-plugins flags a recorded install whose folder is gone" grep -qw 'gone@m' <<<"$mp_out"
assert "missing-plugins does not flag an installed plugin" test "$(grep -cw 'a@m' <<<"$mp_out")" = 0
assert "missing-plugins never flags a disabled plugin" test "$(grep -cw 'off@m' <<<"$mp_out")" = 0
mp_fresh=$(mp_missing /dev/null)
assert "missing-plugins flags every enabled plugin when nothing is installed" test "$mp_fresh" = "a@m b@m gone@m"
assert "post-create consults missing-plugins.jq inside the 24h window" \
    grep -q 'missing-plugins.jq' "$ROOT/{{cookiecutter.project_slug}}/.devcontainer/post-create.sh"

# ===========================================================================
# 6. refresh-auto-mode.sh - newer bundled autoMode rules reach old containers
# ===========================================================================
REFRESH="$CLAUDE_CONFIG/refresh-auto-mode.sh"
SHIPPED="$CLAUDE_CONFIG/auto-mode-shipped.sha256"
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
assert "refresh-auto-mode.sh is executable" test -x "$REFRESH"
assert "the shipped list records the current bundle's autoMode block" \
    grep -qxF "$(jq -cS .autoMode "$BUNDLED_SETTINGS" | sha256_of)" "$SHIPPED"
# shellcheck disable=SC2016  # $own is a jq variable
assert "bundled autoMode.environment carries every own-rules.json entry" \
    jq -e --slurpfile own "$ROOT/scripts/auto-mode/own-rules.json" \
    '.autoMode.environment as $e | all($own[0].environment[]; . as $x | $e | index($x) != null)' "$BUNDLED_SETTINGS"
echo '{"autoMode":{"allow":["A: shipped earlier"]},"model":"opus"}' > "$WORK/am-old.json"
echo '{"autoMode":{"allow":["A: edited by the user"]}}' > "$WORK/am-own.json"
echo '{"model":"opus"}' > "$WORK/am-none.json"
{ jq -cS .autoMode "$WORK/am-old.json" | sha256_of; } > "$WORK/am-shipped"
am_out=$(bash "$REFRESH" "$WORK/am-old.json" "$BUNDLED_SETTINGS" "$WORK/am-shipped")
check "an unedited earlier block is replaced by the bundled one" \
    ".autoMode == $(jq -c .autoMode "$BUNDLED_SETTINGS") and .model == \"opus\"" "$(cat "$WORK/am-old.json")"
assert "the refresh says what it did" grep -q 'Refreshed the auto mode rules' <<<"$am_out"
am_out=$(bash "$REFRESH" "$WORK/am-own.json" "$BUNDLED_SETTINGS" "$WORK/am-shipped")
check "a user's own block is left alone" \
    '.autoMode.allow == ["A: edited by the user"]' "$(cat "$WORK/am-own.json")"
assert "a user's own block earns a note" grep -q 'NOTE: settings.json has its own autoMode rules' <<<"$am_out"
bash "$REFRESH" "$WORK/am-none.json" "$BUNDLED_SETTINGS" "$WORK/am-shipped" >/dev/null
check "a file without autoMode is left to the merge" '. == {"model": "opus"}' "$(cat "$WORK/am-none.json")"
cp "$BUNDLED_SETTINGS" "$WORK/am-current.json"
assert "a current block is a silent no-op" \
    test -z "$(bash "$REFRESH" "$WORK/am-current.json" "$BUNDLED_SETTINGS" "$WORK/am-shipped")"
# The full sign-in `dev auth --full` writes is as sensitive as the shared token.
check "policy denies reading and editing the full sign-in's credentials file" \
    '(.permissions.deny | index("Read(~/.claude/.credentials.json)") != null)
       and (.permissions.deny | index("Edit(~/.claude/.credentials.json)") != null)' "$MANAGED_JSON"

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
