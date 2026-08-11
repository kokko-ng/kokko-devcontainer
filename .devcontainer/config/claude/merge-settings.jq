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
# It ADDITIVELY merges the bundled plugin roster (enabledPlugins,
# extraKnownMarketplaces): bundled entries are added only when the key is
# absent, so a user's explicit choices — including disabling a plugin with
# `false` — always win, while new plugins added to the bundle reach
# long-lived host-mounted setups that would otherwise never see them.
#
# The same only-when-absent policy applies to the bundled scalar settings
# (attribution, permissions.defaultMode, alwaysThinkingEnabled,
# skipDangerousModePermissionPrompt): a fresh settings.json gets the bundled
# defaults, while any value the user has set — whatever it is — wins.
#
# Two migration duties, kept until every container provisioned by an older
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

def ours: "\\.claude/hooks/(guard-git|git-snapshot|session-git-safety)\\.sh$";

def strip_ours:
    map(.hooks |= map(select((.command // "") | test(ours) | not)))
    | map(select((.hooks | length) > 0));

.[0] as $cur
| .[1] as $new
| $cur
| if has("hooks")
  then .hooks = (.hooks
          | with_entries(.value |= strip_ours)
          | with_entries(select((.value | length) > 0)))
       | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end
| if (($new.enabledPlugins // {}) | length) > 0
  then .enabledPlugins = (($new.enabledPlugins // {}) + (.enabledPlugins // {}))
  else . end
| if (($new.extraKnownMarketplaces // {}) | length) > 0
  then .extraKnownMarketplaces = (($new.extraKnownMarketplaces // {}) + (.extraKnownMarketplaces // {}))
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
| if (has("skipDangerousModePermissionPrompt") | not) and ($new | has("skipDangerousModePermissionPrompt"))
  then .skipDangerousModePermissionPrompt = $new.skipDangerousModePermissionPrompt
  else . end
