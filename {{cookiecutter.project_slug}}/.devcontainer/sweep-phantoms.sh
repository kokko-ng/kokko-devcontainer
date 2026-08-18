#!/usr/bin/env bash
# Delete cloud-sync conflict copies from the workspace (run inside the
# container; post-create.sh runs it on every start, and it is safe to run by
# hand: sweep-phantoms.sh [--dry-run] [root]).
#
# When the project folder lives inside a cloud-synced path on the host (see
# init-host-guard.sh), the sync service drops conflict copies next to the
# originals: "config 2.py", "Dockerfile 3", "core 2" - the macOS " N" naming,
# with or without an extension. They are often unreadable through the VM
# mount (EDEADLK) and break mypy, eslint, `cp -r`, and image-build context
# uploads. This sweeper removes exactly that shape, under three guards:
#
#   1. the name matches "<stem> N" or "<stem> N.<ext>" with N = 2..99
#      (conflict numbering starts at 2; a 4-digit year like "report 2024.pdf"
#      never matches),
#   2. the unsuffixed original exists alongside it, and
#   3. the file is not tracked by git (a tracked file is someone's real work,
#      whatever it is named).
set -euo pipefail

dry_run=0
root=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        -*)
            echo "usage: sweep-phantoms.sh [--dry-run] [root]" >&2
            exit 2
            ;;
        *) root="$arg" ;;
    esac
done

if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

in_git_repo=0
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    in_git_repo=1
fi

removed=0
kept=0
while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    # "<stem> N" / "<stem> N.<ext>", N in 2..99.
    if [[ "$base" =~ ^(.+)\ ([2-9]|[1-9][0-9])(\.[A-Za-z0-9][A-Za-z0-9.]*)?$ ]]; then
        original="$(dirname "$f")/${BASH_REMATCH[1]}${BASH_REMATCH[3]:-}"
        if [ ! -e "$original" ]; then
            kept=$((kept + 1))
            continue
        fi
        if [ "$in_git_repo" = 1 ] &&
            git -C "$root" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
            kept=$((kept + 1))
            continue
        fi
        if [ "$dry_run" = 1 ]; then
            echo "would remove: $f"
        else
            rm -f "$f"
            echo "removed: $f"
        fi
        removed=$((removed + 1))
    fi
done < <(find "$root" \
    \( -name .git -o -name node_modules -o -name .venv -o -name __pycache__ \) -prune \
    -o -type f -name '* [0-9]*' -print0 2>/dev/null)

if [ "$removed" -gt 0 ] || [ "$kept" -gt 0 ]; then
    echo "sweep-phantoms: $removed conflict cop$([ "$removed" = 1 ] && echo y || echo ies) removed, $kept suspicious name(s) kept (tracked or no original)"
fi
