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
# So: drop any entry pointing at our own hooks directory (a previous install of
# these same hooks), then append the current bundled set. User hooks never match
# that path and survive untouched.
#
# It also ADDITIVELY merges the bundled plugin roster (enabledPlugins,
# extraKnownMarketplaces): bundled entries are added only when the key is
# absent, so a user's explicit choices — including disabling a plugin with
# `false` — always win, while new plugins added to the bundle reach
# long-lived host-mounted setups that would otherwise never see them.

def ours: "/home/vscode/\\.claude/hooks/";

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
