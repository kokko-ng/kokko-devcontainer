#!/usr/bin/env bash
# SessionStart hook: tell Claude which provisioning steps failed.
#
# post-create.sh records every step that still failed after its retries in
# ~/.devcontainer-provision-status (uv sync, npm ci, the Playwright browser
# download, ...). That ledger used to be visible only in the container
# creation log, so an agent found out that pytest was missing twenty minutes
# into a task. Claude Code adds a SessionStart hook's stdout to the session
# context, so printing the ledger here makes a failed step the first thing the
# agent learns.
#
# Silent when nothing failed, and it never fails the session: exit 0 always.
# Wired in by the bundled settings.json (merge-settings.jq keeps that wiring
# in place); installed to ~/.claude/hooks/ by post-create.sh.
set -u

ledger="${DEVCONTAINER_PROVISION_STATUS:-$HOME/.devcontainer-provision-status}"
[[ -s "$ledger" ]] || exit 0

echo "Devcontainer provisioning: these steps FAILED (full log: /tmp/post-create.log):"
sed 's/^/  /' "$ledger"
echo "The tools those steps install may be missing. Fix the cause (usually connectivity)"
echo "and re-run 'bash .devcontainer/post-create.sh', or tell the user before working around it."
exit 0
