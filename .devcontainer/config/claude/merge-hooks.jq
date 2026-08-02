# merge-hooks.jq — splice the bundled git-safety hooks into an existing
# settings.json without disturbing anything else in it.
#
# Usage: jq -s -f merge-hooks.jq <current.json> <bundled.json>
#
# Two properties this must have, neither of which a plain `*` merge gives you:
#
#   1. It must PRESERVE the user's own hooks. Overwriting the whole `hooks` key
#      would silently delete them — the exact class of silent, unprompted data
#      loss this whole change exists to prevent.
#   2. It must be IDEMPOTENT. post-create.sh runs on every rebuild, and naive
#      appending would stack duplicate hook entries until every Bash call ran
#      the guard a dozen times.
#
# So: drop any entry pointing at one of OUR OWN hook scripts (a previous
# install of these same hooks), then append the current bundled set. "Ours" is
# matched by basename — only the three bundled scripts under a .claude/hooks/
# path — NOT by directory: ~/.claude/hooks/ is the natural home for a user's
# own hooks too, and a directory-wide match silently deleted them on every
# container start. The match is path-prefix agnostic because post-create.sh
# seds /home/vscode to the actual $HOME before running this filter.
#
# It also ADDITIVELY merges the bundled plugin roster (enabledPlugins,
# extraKnownMarketplaces): bundled entries are added only when the key is
# absent, so a user's explicit choices — including disabling a plugin with
# `false` — always win, while new plugins added to the bundle reach
# long-lived host-mounted setups that would otherwise never see them.
#
# The same only-when-absent policy applies to the bundled non-hook settings
# (attribution, permissions.defaultMode, alwaysThinkingEnabled,
# skipDangerousModePermissionPrompt): a fresh settings.json gets the bundled
# defaults, while any value the user has set — whatever it is — wins.

def ours: "\\.claude/hooks/(guard-git|git-snapshot|session-git-safety)\\.sh$";

def strip_ours:
    map(.hooks |= map(select((.command // "") | test(ours) | not)))
    | map(select((.hooks | length) > 0));

.[0] as $cur
| .[1] as $new
| ($cur.hooks // {}) as $cur_hooks
| ($new.hooks // {}) as $new_hooks
| $cur
  * {
      hooks: (
          reduce ($new_hooks | keys_unsorted[]) as $event
              ($cur_hooks | with_entries(.value |= strip_ours);
               .[$event] = ((.[$event] // []) + $new_hooks[$event]))
      )
  }
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
| if (has("alwaysThinkingEnabled") | not) and ($new | has("alwaysThinkingEnabled"))
  then .alwaysThinkingEnabled = $new.alwaysThinkingEnabled
  else . end
| if (has("skipDangerousModePermissionPrompt") | not) and ($new | has("skipDangerousModePermissionPrompt"))
  then .skipDangerousModePermissionPrompt = $new.skipDangerousModePermissionPrompt
  else . end
