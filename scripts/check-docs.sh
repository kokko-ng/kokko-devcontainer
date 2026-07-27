#!/usr/bin/env bash
# Verify the documentation still describes the repository that exists.
#
# Four top-level documents (README, INSTRUCTIONS, MANAGING, GIT-SAFETY) describe
# a provisioning script, a set of hooks and a plugin roster, and nothing checked
# that any of it was still true. Moving the git safety hooks into the
# kokko-safety plugin invalidated a chunk of GIT-SAFETY.md at a stroke; without
# this check that would have gone unnoticed until someone followed the docs.
#
# Two checks, both narrow enough to avoid false alarms:
#   1. Every repo-relative path mentioned in backticks actually exists.
#   2. A short list of load-bearing claims still holds.
set -uo pipefail

DOCS=(README.md INSTRUCTIONS.md MANAGING.md GIT-SAFETY.md)
FAIL=0

# ---------------------------------------------------------------------------
# 1. Paths named in the docs exist.
# ---------------------------------------------------------------------------
for doc in "${DOCS[@]}"; do
    [ -f "$doc" ] || { echo "ERROR: $doc is missing"; FAIL=1; continue; }

    while read -r path; do
        [ -n "$path" ] || continue
        # Only check things that look like a path into this repo.
        case "$path" in
            .devcontainer/*|ghostty/*|scripts/*|.github/*) ;;
            *) continue ;;
        esac
        # Trim a trailing slash so a directory reference resolves.
        clean="${path%/}"
        if [ ! -e "$clean" ]; then
            echo "ERROR: $doc references \`$path\`, which does not exist"
            FAIL=1
        fi
    done < <(grep -oE '`[^`]+`' "$doc" | tr -d '`' | sort -u)
done

# ---------------------------------------------------------------------------
# 2. Load-bearing claims.
# ---------------------------------------------------------------------------
claim() {
    local description="$1"
    shift
    if "$@"; then
        echo "OK:    $description"
    else
        echo "ERROR: $description"
        FAIL=1
    fi
}

claim "post-create.sh still supports --config-only (the /devcontainer-update contract)" \
    grep -q -- '--config-only' .devcontainer/post-create.sh

claim "the safety-net verifier is shipped" \
    test -f .devcontainer/config/claude/hooks/verify-safety-net.sh

claim "the snaps helper is shipped" \
    test -f .devcontainer/config/bin/snaps

claim "kokko-safety is enabled in the roster" \
    grep -q '"kokko-safety@kokko-ng-kokko-cmds": true' .devcontainer/config/claude/settings.json

# The git safety hooks moved to the kokko-safety plugin. Documentation that
# still tells the reader to look for them in this repo is now wrong.
for doc in "${DOCS[@]}"; do
    [ -f "$doc" ] || continue
    while read -r stale; do
        echo "ERROR: $doc still refers to \`$stale\`, which moved to the kokko-safety plugin"
        FAIL=1
    done < <(grep -oE '\.devcontainer/config/claude/hooks/(git-snapshot|guard-git|session-git-safety)\.sh' "$doc" | sort -u)
done

# GIT-SAFETY.md documents the recovery path. If it names a command, that command
# must be one that exists.
if [ -f GIT-SAFETY.md ]; then
    claim "GIT-SAFETY.md documents the refs/snapshots recovery path" \
        grep -q 'refs/snapshots' GIT-SAFETY.md
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "Documentation matches the repository."
fi
exit "$FAIL"
