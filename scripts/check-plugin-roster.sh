#!/usr/bin/env bash
# Verify every plugin this container enables actually exists in the marketplace
# it claims to come from.
#
# WHY
# ---
# .devcontainer/config/claude/settings.json hardcodes a plugin roster and two
# marketplace repos. post-create.sh drives the install from that file, and a
# failed install is deliberately non-fatal -- the container must come up even
# with no network.
#
# So a plugin renamed or removed in kokko-cmds produces a container that looks
# healthy and is quietly missing a plugin. You find out when a slash command
# does not exist, or -- for kokko-safety -- when a rebase eats uncommitted work.
# There was nothing anywhere that connected the two repos.
#
# This resolves each `owner/repo` in extraKnownMarketplaces to its live
# marketplace.json and checks every enabled plugin is listed in it. Run in CI on
# this repo, and triggered by a release in kokko-cmds.
#
# Usage: scripts/check-plugin-roster.sh [path/to/settings.json]
set -uo pipefail

SETTINGS="${1:-.devcontainer/config/claude/settings.json}"
FAIL=0

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ -f "$SETTINGS" ] || { echo "no settings file at $SETTINGS" >&2; exit 1; }

jq -e . "$SETTINGS" >/dev/null || { echo "ERROR: $SETTINGS is not valid JSON"; exit 1; }

# ---------------------------------------------------------------------------
# Fetch each marketplace manifest.
# ---------------------------------------------------------------------------
declare -A MARKET_PLUGINS
declare -A MARKET_REPO

while read -r name repo; do
    [ -n "$name" ] && [ -n "$repo" ] || continue
    MARKET_REPO["$name"]="$repo"

    manifest=""
    for branch in main master; do
        url="https://raw.githubusercontent.com/${repo}/${branch}/.claude-plugin/marketplace.json"
        if manifest="$(curl -fsSL --max-time 30 "$url" 2>/dev/null)" && [ -n "$manifest" ]; then
            break
        fi
        manifest=""
    done

    if [ -z "$manifest" ]; then
        echo "ERROR: could not fetch the marketplace manifest for '$name' from $repo"
        echo "       tried main and master at .claude-plugin/marketplace.json"
        FAIL=1
        continue
    fi

    if ! printf '%s' "$manifest" | jq -e . >/dev/null 2>&1; then
        echo "ERROR: $repo has a marketplace.json that is not valid JSON"
        FAIL=1
        continue
    fi

    # The marketplace's own declared name must match the key used here, because
    # that key is half of every `plugin@marketplace` reference.
    declared="$(printf '%s' "$manifest" | jq -r '.name // ""')"
    if [ "$declared" != "$name" ]; then
        echo "ERROR: marketplace key '$name' does not match the name declared by $repo ('$declared')"
        echo "       every enabledPlugins entry referencing @$name would fail to resolve"
        FAIL=1
    fi

    MARKET_PLUGINS["$name"]="$(printf '%s' "$manifest" | jq -r '.plugins[].name')"
    count="$(printf '%s' "${MARKET_PLUGINS[$name]}" | grep -c . || true)"
    echo "Fetched $name ($repo): $count plugin(s)"
done < <(jq -r '
    (.extraKnownMarketplaces // {})
    | to_entries[]
    | select(.value.source.source == "github")
    | "\(.key) \(.value.source.repo)"' "$SETTINGS")

echo

# ---------------------------------------------------------------------------
# Resolve every enabled plugin.
# ---------------------------------------------------------------------------
enabled_count=0
while read -r entry; do
    [ -n "$entry" ] || continue
    enabled_count=$((enabled_count + 1))

    plugin="${entry%@*}"
    market="${entry##*@}"

    if [ "$plugin" = "$entry" ] || [ -z "$market" ]; then
        echo "ERROR: '$entry' is not in plugin@marketplace form"
        FAIL=1
        continue
    fi

    if [ -z "${MARKET_REPO[$market]+set}" ]; then
        echo "ERROR: $entry references marketplace '$market', which is not in extraKnownMarketplaces"
        echo "       post-create.sh only registers marketplaces listed there, so this can never install"
        FAIL=1
        continue
    fi

    if [ -z "${MARKET_PLUGINS[$market]+set}" ]; then
        echo "SKIP:  $entry (marketplace '$market' could not be fetched above)"
        continue
    fi

    if printf '%s\n' "${MARKET_PLUGINS[$market]}" | grep -qxF "$plugin"; then
        echo "OK:    $entry"
    else
        echo "ERROR: $entry does not exist in ${MARKET_REPO[$market]}"
        echo "       plugins available there: $(printf '%s' "${MARKET_PLUGINS[$market]}" | tr '\n' ' ')"
        FAIL=1
    fi
done < <(jq -r '
    (.enabledPlugins // {})
    | to_entries[]
    | select(.value == true)
    | .key' "$SETTINGS")

echo
if [ "$enabled_count" -eq 0 ]; then
    echo "ERROR: no plugins are enabled. The roster is what post-create.sh installs from;"
    echo "       an empty one means a container comes up with no plugins at all."
    FAIL=1
fi

# kokko-safety is the git safety net. Anything else missing costs a slash
# command; this costs uncommitted work.
safety="$(jq -r '(.enabledPlugins // {}) | to_entries[] | select(.key | startswith("kokko-safety@")) | .value' "$SETTINGS")"
if [ "$safety" != "true" ]; then
    echo "ERROR: kokko-safety is not enabled. It provides git-snapshot.sh and guard-git.sh,"
    echo "       which are the enforcement layer for everything GIT-SAFETY.md promises."
    FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All $enabled_count enabled plugins resolve against their marketplaces."
fi
exit "$FAIL"
