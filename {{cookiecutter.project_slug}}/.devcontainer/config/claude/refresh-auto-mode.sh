#!/usr/bin/env bash
# refresh-auto-mode.sh — bring a live settings.json's autoMode block up to the
# bundled one, unless the user edited it.
#
# Usage: refresh-auto-mode.sh <live settings.json> <bundled settings.json> <shipped list>
#
# merge-settings.jq adds the bundled autoMode block only when the live file has
# none, so newer bundled rules would never reach a container provisioned
# earlier. This replaces the live block when it is byte-for-byte one that an
# earlier bundle shipped: its sha256 (of `jq -cS .autoMode`) is in the shipped
# list, auto-mode-shipped.sha256. Any other block is the user's and is left
# alone, with a note. Prints what it did; never fails the caller.
set -u

live="$1" bundled="$2" shipped="$3"

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'
}

[[ -f "$live" && -f "$bundled" && -f "$shipped" ]] || exit 0
new="$(jq -cS '.autoMode // empty' "$bundled" 2>/dev/null)" || exit 0
cur="$(jq -cS '.autoMode // empty' "$live" 2>/dev/null)" || exit 0
# Nothing bundled, nothing live yet (the merge adds it), or already current.
[[ -n "$new" && -n "$cur" && "$cur" != "$new" ]] || exit 0

if grep -qxF "$(jq -cS '.autoMode' "$live" | sha256)" "$shipped"; then
    if jq --slurpfile b "$bundled" '.autoMode = $b[0].autoMode' "$live" >"$live.automode-tmp" 2>/dev/null &&
        jq -e . "$live.automode-tmp" >/dev/null 2>&1; then
        mv "$live.automode-tmp" "$live"
        echo "  Refreshed the auto mode rules from the bundle (the previous ones were unedited)"
    else
        rm -f "$live.automode-tmp"
        echo "  WARNING: could not refresh the auto mode rules; settings.json left unchanged"
    fi
else
    echo "  NOTE: settings.json has its own autoMode rules and was left alone. Compare them"
    echo "        with the bundle: jq .autoMode '$bundled'"
fi
exit 0
