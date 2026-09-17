# merge-settings.jq — merge the bundled Claude Code settings into an existing
# settings.json without disturbing anything else in it.
#
# Usage: jq -s -f merge-settings.jq <current.json> <bundled.json>
#
# Two properties this must have, neither of which a plain `*` merge gives you:
#
#   1. It must PRESERVE the user's own settings — their hooks, their permission
#      choices, their plugin toggles. Overwriting whole keys would silently
#      delete them.
#   2. It must be IDEMPOTENT. post-create.sh runs the merge on every rebuild
#      and every container start, so re-running it must never stack or
#      duplicate anything.
#
# What it merges, and the rule for each:
#
#   * enabledPlugins, extraKnownMarketplaces, env — ADDITIVE per key: bundled
#     entries are added only when the key is absent, so a user's explicit
#     choices — including disabling a plugin with `false`, or a shorter Bash
#     timeout — always win, while keys added to the bundle still reach
#     long-lived setups that would otherwise never see them.
#   * sandbox — additive per top-level key, same rule: a user who flipped
#     `enabled` keeps that, and a key the bundle adds later still arrives.
#   * hooks — the bundled SessionStart hook (session-provision-status.sh) is
#     wired in when no hook in that event references it yet. A user's own
#     hooks are never touched, a user's edits to the bundled entry (a
#     different timeout, say) survive, and a second run adds nothing.
#   * attribution, permissions.defaultMode, alwaysThinkingEnabled — only when
#     absent: a fresh settings.json gets the bundled defaults, while any value
#     the user has set — whatever it is — wins.
#
# Policy that must NOT be user-overridable (the deny list, the bypass-mode
# lock) is not merged here at all: it ships in managed-settings.json, which
# post-create.sh installs to /etc/claude-code/, where Claude Code applies it
# above every user and project setting.
#
# Three migration duties, kept until every container provisioned by an older
# bundle has moved on:
#
#   1. The retired git-safety hooks (guard-git.sh, git-snapshot.sh,
#      session-git-safety.sh) are STRIPPED from the live hook wiring, so a
#      settings.json written by an older bundle stops invoking scripts that
#      post-create.sh no longer installs. "Ours" is matched by basename under
#      a .claude/hooks/ path — never by directory, because ~/.claude/hooks/
#      is the natural home for a user's own hooks too.
#   2. permissions.defaultMode moves from "acceptEdits" (the value every older
#      bundle shipped) to the bundled "auto". Only that exact value migrates:
#      any other live value is a user choice and wins, mirroring
#      prune-roster.jq's you-never-overrode-it rule.
#   3. skipDangerousModePermissionPrompt is DROPPED when it is `true` — the
#      value every older bundle shipped. Its only effect was to make
#      --dangerously-skip-permissions frictionless, which managed-settings.json
#      now forbids outright. Any other value is a user choice and stays.

def retired: "\\.claude/hooks/(guard-git|git-snapshot|session-git-safety)\\.sh$";
def bundled_hook: "\\.claude/hooks/session-provision-status\\.sh$";

def strip_retired:
    map(.hooks |= map(select((.command // "") | test(retired) | not)))
    | map(select((.hooks | length) > 0));

# True when any hook in an event's group list already runs the bundled script.
def wired($groups):
    any(($groups // [])[]? | (.hooks // [])[]?; ((.command // "") | test(bundled_hook)));

.[0] as $cur
| .[1] as $new
| $cur
| if has("hooks")
  then .hooks = (.hooks
          | with_entries(.value |= strip_retired)
          | with_entries(select((.value | length) > 0)))
       | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end
| reduce (($new.hooks // {}) | to_entries[]) as $ev (.;
      if wired(.hooks[$ev.key]) then .
      else .hooks[$ev.key] = ((.hooks[$ev.key] // []) + $ev.value) end)
| if (($new.enabledPlugins // {}) | length) > 0
  then .enabledPlugins = (($new.enabledPlugins // {}) + (.enabledPlugins // {}))
  else . end
| if (($new.extraKnownMarketplaces // {}) | length) > 0
  then .extraKnownMarketplaces = (($new.extraKnownMarketplaces // {}) + (.extraKnownMarketplaces // {}))
  else . end
| if (($new.env // {}) | length) > 0
  then .env = (($new.env // {}) + (.env // {}))
  else . end
| if (($new.sandbox // {}) | length) > 0
  then .sandbox = (($new.sandbox // {}) + (.sandbox // {}))
  else . end
| if (has("attribution") | not) and ($new | has("attribution"))
  then .attribution = $new.attribution
  else . end
| if ((.permissions // {}) | has("defaultMode") | not) and (($new.permissions // {}) | has("defaultMode"))
  then .permissions = ((.permissions // {}) + { defaultMode: $new.permissions.defaultMode })
  else . end
| if ((.permissions // {}).defaultMode == "acceptEdits") and (($new.permissions // {}).defaultMode == "auto")
  then .permissions.defaultMode = "auto"
  else . end
| if (has("alwaysThinkingEnabled") | not) and ($new | has("alwaysThinkingEnabled"))
  then .alwaysThinkingEnabled = $new.alwaysThinkingEnabled
  else . end
| if .skipDangerousModePermissionPrompt == true
  then del(.skipDangerousModePermissionPrompt)
  else . end
