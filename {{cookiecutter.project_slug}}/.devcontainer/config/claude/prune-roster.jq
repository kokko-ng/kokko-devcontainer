# prune-roster.jq — drop roster entries the bundle no longer ships, without
# touching anything the user set themselves.
#
# Usage: jq -s -f prune-roster.jq <prev-roster.json> <bundled.json> <live.json>
#
# merge-settings.jq is deliberately ADDITIVE for enabledPlugins and
# extraKnownMarketplaces — bundled keys are added when absent, user values
# always win. The cost of additive is that a plugin REMOVED from the bundled
# roster stays enabled in a live settings.json forever. This filter closes
# that gap using a snapshot of the PREVIOUS bundle
# (~/.claude/.kokko-bundled-roster.json, written by post-create.sh after each
# merge): a key is deleted from the live settings ONLY when
#
#   1. the previous bundle shipped it,
#   2. the new bundle no longer ships it, and
#   3. the live value still equals what the previous bundle shipped —
#      i.e. the user never overrode it. A user override always survives.

def prune($prev_map; $new_map):
    # Bind key/value up front: inside `$prev_map | has(...)` the context is
    # the map, so a bare .key there would be evaluated against the wrong side.
    with_entries(.key as $k | .value as $v | select(
        (
            ($prev_map | has($k))
            and (($new_map | has($k)) | not)
            and ($v == $prev_map[$k])
        ) | not
    ));

.[0] as $prev
| .[1] as $new
| .[2] as $live
| $live
| if has("enabledPlugins")
  then .enabledPlugins |= prune(($prev.enabledPlugins // {}); ($new.enabledPlugins // {}))
  else . end
| if has("extraKnownMarketplaces")
  then .extraKnownMarketplaces |= prune(($prev.extraKnownMarketplaces // {}); ($new.extraKnownMarketplaces // {}))
  else . end
