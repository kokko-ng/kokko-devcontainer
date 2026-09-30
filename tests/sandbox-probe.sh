#!/usr/bin/env bash
# Proves, from INSIDE a container, whether Claude Code's Bash sandbox can run
# there. CI's sandbox-colima job runs it as a non-root user in containers on a
# real Colima VM: once with Docker's default security options (the sandbox
# must be refused, or this probe proves nothing) and once with the template's
# runArgs (the sandbox must work end to end).
#
#   bash tests/sandbox-probe.sh blocked   # bubblewrap must be refused
#   bash tests/sandbox-probe.sh works     # bubblewrap AND the full sandbox work
#
# "works" drives @anthropic-ai/sandbox-runtime's `srt` CLI, the engine Claude
# Code's sandbox is built on, so it needs srt, node, rg, socat and curl on PATH.
set -u

expect="${1:-}"
[[ "$expect" == "blocked" || "$expect" == "works" ]] || {
    echo "usage: $0 blocked|works" >&2
    exit 2
}

PASS=0
FAIL=0
FAILED_CASES=()

# check <desc> <cmd...> — the command's exit status is the assertion.
check() {
    local desc="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); echo "  ok   $desc"
    else FAIL=$((FAIL + 1)); FAILED_CASES+=("$desc"); echo "  FAIL $desc"; fi
}

# refute <desc> <cmd...> — passes when the command FAILS.
refute() {
    local desc="$1"; shift
    if "$@"; then FAIL=$((FAIL + 1)); FAILED_CASES+=("$desc"); echo "  FAIL $desc"
    else PASS=$((PASS + 1)); echo "  ok   $desc"; fi
}

finish() {
    echo ""
    echo "sandbox probe ($expect): passed: $PASS  failed: $FAIL"
    if (( FAIL > 0 )); then
        printf '  FAILED: %s\n' "${FAILED_CASES[@]}"
        exit 1
    fi
    exit 0
}

# bubblewrap exactly as Claude Code runs it with enableWeakerNestedSandbox
# (the same flags as post-create.sh's check_bash_sandbox).
# shellcheck disable=SC2317,SC2329  # invoked through check/refute (SC2317 before shellcheck 0.11)
bwrap_probe() {
    bwrap --new-session --die-with-parent --ro-bind / / --dev /dev \
        --unshare-user --unshare-net --unshare-pid --bind /proc /proc true
}

echo "=== uid $(id -u), $(bwrap --version 2>/dev/null || echo 'no bwrap')"

if [[ "$expect" == "blocked" ]]; then
    refute "bubblewrap is refused under Docker's default security options" bwrap_probe
    finish
fi

check "bubblewrap builds its namespaces" bwrap_probe
(( FAIL == 0 )) || finish

work="$HOME/sandbox-probe"
mkdir -p "$work"
cd "$work" || exit 1
settings="$HOME/srt-settings.json"
cat > "$settings" <<EOF
{
  "enableWeakerNestedSandbox": true,
  "network": { "allowedDomains": ["github.com"], "deniedDomains": [] },
  "filesystem": { "denyRead": [], "allowWrite": ["$work"], "denyWrite": [] }
}
EOF

# shellcheck disable=SC2317,SC2329  # invoked through check/refute (SC2317 before shellcheck 0.11)
sandboxed() { srt --settings "$settings" -c "$1"; }

# A Unix-domain connect that fails with EPERM was refused by the sandbox's
# seccomp filter; ENOENT would mean the socket call itself got through.
# shellcheck disable=SC2016  # expanded inside the sandbox, not here
unix_socket_js='require("net").connect("/tmp/no-such-socket").on("error", e => process.exit(e.code === "EPERM" ? 0 : 1))'

check "a command runs inside the sandbox" sandboxed 'true'
check "the workspace is writable" sandboxed 'touch written-inside'
# shellcheck disable=SC2016  # $HOME expands inside the sandbox
refute "home outside the workspace is read-only" sandboxed 'touch "$HOME/escaped"'
check "nothing escaped to home" test ! -e "$HOME/escaped"
# No -f: any HTTP answer proves the proxy let the connection through; a
# refused CONNECT makes curl itself fail.
check "an allowlisted domain is reachable" sandboxed 'curl -sS -o /dev/null -m 30 https://github.com'
refute "a domain off the allowlist is blocked" sandboxed 'curl -sS -o /dev/null -m 30 https://example.com'
check "Unix sockets are blocked by the seccomp filter" sandboxed "node -e '$unix_socket_js'"

finish
