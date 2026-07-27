#!/usr/bin/env bash
# Tests for merge-hooks.jq.
#
# This jq program rewrites the user's live ~/.claude/settings.json on every
# rebuild and on every `--config-only` refresh. Its two required properties --
# preserve the user's own hooks, and be idempotent -- are exactly the kind that
# hold until someone edits the program, and whose failure is silent: a lost user
# hook looks like a user who never added one, and duplicated entries look like a
# slow session.
#
# Usage: scripts/test-merge-hooks.sh
set -uo pipefail

JQ_PROGRAM=".devcontainer/config/claude/merge-hooks.jq"
BUNDLED=".devcontainer/config/claude/settings.json"
PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

merge() { jq -s -f "$JQ_PROGRAM" "$1" "$BUNDLED"; }

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "ok   - $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL - $name"
        echo "         expected: $expected"
        echo "         actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
cat > "$TMP/empty.json" <<'EOF'
{}
EOF

cat > "$TMP/user.json" <<'EOF'
{
  "theme": "dark",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "/home/vscode/my-own-hook.sh"}
      ]}
    ],
    "Notification": [
      {"hooks": [{"type": "command", "command": "/home/vscode/notify.sh"}]}
    ]
  },
  "enabledPlugins": {
    "kokko-viz@kokko-ng-kokko-cmds": false,
    "third-party@elsewhere": true
  }
}
EOF

# A container provisioned by the previous version of post-create.sh.
cat > "$TMP/legacy.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "/home/vscode/.claude/hooks/git-snapshot.sh"},
        {"type": "command", "command": "/home/vscode/.claude/hooks/guard-git.sh"},
        {"type": "command", "command": "/home/vscode/keep-me.sh"}
      ]}
    ],
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "/home/vscode/.claude/hooks/session-git-safety.sh"}]}
    ]
  },
  "enabledPlugins": {
    "kokko-safety@kokko-ng-kokko-cmds": false
  }
}
EOF

# --- The program compiles at all -------------------------------------------
if merge "$TMP/empty.json" >/dev/null 2>&1; then
    echo "ok   - merge-hooks.jq compiles"
    PASS=$((PASS + 1))
else
    echo "FAIL - merge-hooks.jq does not compile"
    jq -s -f "$JQ_PROGRAM" "$TMP/empty.json" "$BUNDLED" 2>&1 | sed 's/^/         /'
    FAIL=$((FAIL + 1))
    exit 1
fi

# --- Output is valid JSON ---------------------------------------------------
check "output is valid JSON" "0" \
    "$(merge "$TMP/user.json" | jq -e . >/dev/null 2>&1; echo $?)"

# --- User settings survive --------------------------------------------------
check "unrelated keys survive" "dark" \
    "$(merge "$TMP/user.json" | jq -r '.theme')"

check "the user's own PreToolUse hook survives" "1" \
    "$(merge "$TMP/user.json" | jq '[.hooks.PreToolUse[].hooks[] | select(.command == "/home/vscode/my-own-hook.sh")] | length')"

check "a hook event the bundle does not touch survives" "1" \
    "$(merge "$TMP/user.json" | jq '.hooks.Notification | length')"

check "the user's explicit plugin choice wins" "false" \
    "$(merge "$TMP/user.json" | jq -r '.enabledPlugins["kokko-viz@kokko-ng-kokko-cmds"]')"

check "a third-party plugin survives" "true" \
    "$(merge "$TMP/user.json" | jq -r '.enabledPlugins["third-party@elsewhere"]')"

# --- The bundle is applied --------------------------------------------------
check "the safety-net verifier is wired up" "1" \
    "$(merge "$TMP/empty.json" | jq '[.hooks.SessionStart[].hooks[] | select(.command | endswith("verify-safety-net.sh"))] | length')"

check "new plugins reach an existing settings.json" "true" \
    "$(merge "$TMP/user.json" | jq -r '.enabledPlugins["kokko-git@kokko-ng-kokko-cmds"]')"

check "marketplaces are registered" "true" \
    "$(merge "$TMP/empty.json" | jq '.extraKnownMarketplaces | has("kokko-ng-kokko-cmds")')"

# --- Migration off the old in-repo hooks ------------------------------------
check "superseded snapshot hook is unwired" "0" \
    "$(merge "$TMP/legacy.json" | jq '[.. | .command? // empty | select(endswith("git-snapshot.sh"))] | length')"

check "superseded guard hook is unwired" "0" \
    "$(merge "$TMP/legacy.json" | jq '[.. | .command? // empty | select(endswith("/.claude/hooks/guard-git.sh"))] | length')"

check "superseded session hook is unwired" "0" \
    "$(merge "$TMP/legacy.json" | jq '[.. | .command? // empty | select(endswith("session-git-safety.sh"))] | length')"

check "a user hook alongside the superseded ones survives" "1" \
    "$(merge "$TMP/legacy.json" | jq '[.. | .command? // empty | select(endswith("keep-me.sh"))] | length')"

check "a stale kokko-safety=false is corrected to true" "true" \
    "$(merge "$TMP/legacy.json" | jq -r '.enabledPlugins["kokko-safety@kokko-ng-kokko-cmds"]')"

# --- Idempotence ------------------------------------------------------------
merge "$TMP/user.json" > "$TMP/once.json"
jq -s -f "$JQ_PROGRAM" "$TMP/once.json" "$BUNDLED" > "$TMP/twice.json"
jq -s -f "$JQ_PROGRAM" "$TMP/twice.json" "$BUNDLED" > "$TMP/thrice.json"

check "merging twice equals merging once" "same" \
    "$(if diff -q <(jq -S . "$TMP/once.json") <(jq -S . "$TMP/twice.json") >/dev/null; then echo same; else echo different; fi)"

check "merging three times equals merging once" "same" \
    "$(if diff -q <(jq -S . "$TMP/once.json") <(jq -S . "$TMP/thrice.json") >/dev/null; then echo same; else echo different; fi)"

check "hook entries do not accumulate" "1" \
    "$(jq '[.hooks.SessionStart[].hooks[] | select(.command | endswith("verify-safety-net.sh"))] | length' "$TMP/thrice.json")"

# --- Every hook the bundle declares points at a file this repo ships ---------
missing=0
while read -r cmd; do
    [ -n "$cmd" ] || continue
    base="${cmd##*/}"
    if [ ! -f ".devcontainer/config/claude/hooks/$base" ]; then
        echo "         bundled settings.json wires $base, which this repo does not ship"
        missing=$((missing + 1))
    fi
done < <(jq -r '[.hooks[]?[]?.hooks[]?.command] | .[]' "$BUNDLED")
check "every wired hook exists in the repo" "0" "$missing"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
