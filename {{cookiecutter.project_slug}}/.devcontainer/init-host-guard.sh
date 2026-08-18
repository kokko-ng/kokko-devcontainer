#!/usr/bin/env bash
# Runs on the HOST before docker build (initializeCommand, chained after
# init-host-certs.sh). Warns when the workspace sits inside a cloud-synced
# folder on macOS.
#
# Why: a project under iCloud Drive (including ~/Documents and ~/Desktop when
# "Desktop & Documents Folders" syncing is on) or under ~/Library/CloudStorage
# (OneDrive, Dropbox, Google Drive in File Provider mode) gets rewritten by
# the sync service while the container works on it. The visible damage is
# phantom conflict copies named "file 2.ext", "Dockerfile 3", ... appearing
# next to the originals, often unreadable through the VM mount (EDEADLK,
# "Resource deadlock avoided"). They break linters, type-checkers, `cp -r`,
# and container image builds, and they respawn after deletion for as long as
# the sync service keeps watching the folder.
#
# This guard only WARNS - it never fails the container build - because only
# the human can apply the fix (move the project, or exempt it from sync).
set -euo pipefail

# Non-macOS hosts (Linux, CI) have none of these sync layers: nothing to do.
[ "$(uname -s)" = "Darwin" ] || exit 0

# initializeCommand runs with the workspace folder as cwd; resolve symlinks so
# a path routed through a symlink into a synced folder is still caught.
workspace="$(pwd -P)"
home_real="$(cd "${HOME}" && pwd -P)"

reason=""
remedy=""

case "$workspace" in
    "$home_real/Library/CloudStorage/"*)
        reason="under ~/Library/CloudStorage (OneDrive/Dropbox/Google Drive File Provider sync)"
        remedy="Move the project to a non-synced path, e.g. ~/code, and re-open it there."
        ;;
    "$home_real/Library/Mobile Documents/"*)
        reason="inside iCloud Drive (~/Library/Mobile Documents)"
        remedy="Move the project to a non-synced path (e.g. ~/code), or rename its parent folder with a .nosync suffix (iCloud ignores 'name.nosync' folders; add a symlink under the old name if other tools expect it)."
        ;;
    "$home_real/Documents/"* | "$home_real/Desktop/"*)
        # Only synced when the iCloud "Desktop & Documents Folders" option is
        # on, which materialises this directory:
        if [ -d "$home_real/Library/Mobile Documents/com~apple~CloudDocs/Documents" ] ||
            [ -d "$home_real/Library/Mobile Documents/com~apple~CloudDocs/Desktop" ]; then
            reason="under ~/Documents or ~/Desktop with iCloud 'Desktop & Documents Folders' syncing enabled"
            remedy="Move the project outside ~/Documents and ~/Desktop (e.g. ~/code), or rename its parent folder with a .nosync suffix (iCloud ignores 'name.nosync' folders), or turn off Desktop & Documents syncing in System Settings > Apple ID > iCloud."
        fi
        ;;
esac

# A .nosync ancestor means iCloud already skips this tree: no warning owed.
if [ -n "$reason" ]; then
    case "$workspace" in
        *.nosync | *.nosync/*) reason="" ;;
    esac
fi

[ -n "$reason" ] || exit 0

cat >&2 <<EOF

============================================================================
 WARNING: this project lives inside a cloud-synced folder
   $workspace
   ($reason)

 The sync service will fight the container for these files. Expect phantom
 conflict copies ("file 2.ext", "Dockerfile 3", ...) that respawn after
 deletion, unreadable files (EDEADLK) that break linters and image builds,
 and silently corrupted caches.

 Fix (one-time, on this Mac):
   $remedy

 The container will still start; sweep-phantoms.sh cleans up existing
 conflict copies inside the container, but new ones will keep appearing
 until the project is out of the synced folder.
============================================================================

EOF

exit 0
