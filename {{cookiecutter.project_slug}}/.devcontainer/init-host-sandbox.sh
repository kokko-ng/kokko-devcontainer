#!/usr/bin/env bash
# Runs on the HOST before the container is created (initializeCommand, chained
# after init-host-guard.sh). Lets Claude Code's Bash sandbox (/sandbox) start
# inside the container when Docker is served by a Colima VM.
#
# Why: Colima's VM runs Ubuntu 24.04, which sets
# kernel.apparmor_restrict_unprivileged_userns=1. A user namespace created
# outside an AppArmor profile then gets no capabilities, so bubblewrap (the
# sandbox's engine) fails with "loopback: Failed RTM_NEWADDR: Operation not
# permitted" whatever the container's runArgs say. Only the VM can change a
# kernel setting, so this sets it to 0 there. The sysctl.d file persists
# across `colima stop`/`start`; after `colima delete` the next container start
# applies it again. Once it is 0, this is one `colima ssh` and nothing else.
#
# Other containers on the VM are unaffected: Docker's default seccomp and
# AppArmor profiles refuse user namespaces by themselves, and only a container
# that opts in (this template's runArgs) can create them. CI proves both on a
# real Colima VM.
#
# Never fails the container build: problems are warnings, and post-create.sh's
# bubblewrap probe reports a sandbox that still cannot start.
set -uo pipefail

KEY=kernel.apparmor_restrict_unprivileged_userns

command -v colima >/dev/null 2>&1 || exit 0
command -v docker >/dev/null 2>&1 || exit 0

# Which Colima profile serves this build: the devcontainer CLI uses whatever
# docker uses, DOCKER_HOST if set, else the current context. Colima's socket is
# <config dir>/colima/<profile>/docker.sock (~/.colima on macOS), and its
# context is "colima" for the default profile and "colima-<profile>" otherwise.
profile=""
if [[ -n "${DOCKER_HOST:-}" ]]; then
    if [[ "$DOCKER_HOST" =~ colima/([^/]+)/docker\.sock$ ]]; then
        profile="${BASH_REMATCH[1]}"
    fi
else
    context="$(docker context show 2>/dev/null || true)"
    case "$context" in
        colima) profile="default" ;;
        colima-*) profile="${context#colima-}" ;;
    esac
fi
# Not Colima (Docker Desktop, OrbStack, a native Linux daemon, ...): nothing
# here applies.
[[ -n "$profile" ]] || exit 0

current="$(colima ssh -p "$profile" -- sysctl -n "$KEY" 2>/dev/null || true)"
# Already 0, or a kernel without the knob: nothing to do.
[[ "$current" == "1" ]] || exit 0

echo "Colima VM '$profile' restricts user namespaces ($KEY=1), which stops"
echo "Claude Code's Bash sandbox in the container. Setting it to 0 (see"
echo "DEVCONTAINER.md -> Permission model)."
if colima ssh -p "$profile" -- sudo sh -c 'echo kernel.apparmor_restrict_unprivileged_userns=0 > /etc/sysctl.d/99-bash-sandbox.conf && sysctl -p /etc/sysctl.d/99-bash-sandbox.conf' >/dev/null; then
    echo "  Done — persists across colima stop/start."
else
    cat >&2 <<EOF

  WARNING: could not set $KEY=0 on Colima VM '$profile'.
  The container will start, but /sandbox will not work in it. Retry by hand:
    colima ssh -p $profile -- sudo sh -c 'echo kernel.apparmor_restrict_unprivileged_userns=0 > /etc/sysctl.d/99-bash-sandbox.conf && sysctl -p /etc/sysctl.d/99-bash-sandbox.conf'

EOF
fi
exit 0
