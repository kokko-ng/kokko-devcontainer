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
#
# ONE EXCEPTION: kokko-safety. See FORCE_ENABLE below.

def ours: "/home/vscode/\\.claude/hooks/";

# Plugins whose bundled value overrides an existing one, rather than deferring
# to it.
#
# kokko-safety shipped as `false` in this bundle for as long as it was a set of
# noisy "ask" hooks that fired on routine commands. The `false` in an existing
# settings.json is therefore almost certainly THIS bundle's old default rather
# than a considered user preference — and it now disables the git snapshot and
# guard hooks, which used to be installed unconditionally by post-create.sh and
# are the enforcement layer for everything GIT-SAFETY.md promises.
#
# Deferring to the stale `false` would silently downgrade every existing
# container from "protected" to "unprotected" on the next config refresh. So
# this one key is forced. To keep it off deliberately, set it after the merge
# (or run with the roster removed from the bundle).
def FORCE_ENABLE: ["kokko-safety@kokko-ng-kokko-cmds"];

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
  then .enabledPlugins = (
      ($new.enabledPlugins // {}) + (.enabledPlugins // {})
      # ...then re-apply the bundle's value for the forced keys only.
      + (($new.enabledPlugins // {})
         | with_entries(select(.key | IN(FORCE_ENABLE[]))))
  )
  else . end
| if (($new.extraKnownMarketplaces // {}) | length) > 0
  then .extraKnownMarketplaces = (($new.extraKnownMarketplaces // {}) + (.extraKnownMarketplaces // {}))
  else . end
