#!/usr/bin/env bash
# Outbound firewall for the devcontainer: everything in the container (Claude
# Code and the commands it runs, Copilot CLI, gh, az, MCP servers, your own
# shells) reaches only the hosts in the allowlist, plus DNS, loopback and the
# Docker host. Inbound traffic (port forwarding) is untouched.
#
# Installed root-owned at /usr/local/sbin/devcontainer-firewall, with the
# allowlist at /etc/devcontainer/allowed-domains.txt; both are baked into the
# image, so an edit to the copies under .devcontainer/firewall/ takes effect at
# the next rebuild, which only the host can run. The container user may run
# this script (and nothing else) through sudo: it only ever rebuilds the same
# rules from the same list, so running it again just refreshes the addresses
# the allowlisted hosts resolve to now (CDNs rotate them).
#
# Needs the NET_ADMIN and NET_RAW capabilities (devcontainer.json runArgs).
set -euo pipefail

ALLOWLIST="${DEVCONTAINER_FIREWALL_ALLOWLIST:-/etc/devcontainer/allowed-domains.txt}"
SET=devcontainer-allow

[[ $EUID -eq 0 ]] || {
    echo "devcontainer-firewall: run as root (sudo $0)" >&2
    exit 1
}
for tool in iptables ipset dig curl jq; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "devcontainer-firewall: $tool is missing from the image" >&2
        exit 1
    }
done
[[ -r "$ALLOWLIST" ]] || {
    echo "devcontainer-firewall: no allowlist at $ALLOWLIST" >&2
    exit 1
}

# Open up while addresses are resolved, so a re-run is not blocked by the
# rules it is about to replace.
iptables -P OUTPUT ACCEPT
iptables -F OUTPUT
ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
ip6tables -F OUTPUT 2>/dev/null || true

ipset create "$SET" hash:net -exist
ipset flush "$SET"
added=0
add() {
    if ipset add "$SET" "$1" -exist 2>/dev/null; then added=$((added + 1)); fi
}

# GitHub publishes its address ranges; hosts behind them rotate too often to
# resolve one by one.
if meta="$(curl -fsS --max-time 15 https://api.github.com/meta)"; then
    while read -r cidr; do
        [[ "$cidr" == *:* ]] || add "$cidr"
    done < <(jq -r '(.web + .api + .git + .packages + (.copilot // [])) | .[]' <<<"$meta")
else
    echo "devcontainer-firewall: could not fetch GitHub's ranges; resolving github.com hosts by name only" >&2
fi

unresolved=()
while read -r host; do
    host="${host%%#*}"
    host="${host//[[:space:]]/}"
    [[ -n "$host" ]] || continue
    if [[ "$host" == \** ]]; then
        echo "devcontainer-firewall: wildcards are not supported, skipping $host (list exact hosts)" >&2
        continue
    fi
    ips="$(dig +short +time=3 +tries=2 A "$host" | grep -E '^[0-9.]+$' || true)"
    if [[ -z "$ips" ]]; then
        unresolved+=("$host")
        continue
    fi
    for ip in $ips; do add "$ip"; done
done <"$ALLOWLIST"

# The Docker host's network: port forwarding replies and host.docker.internal.
host_net="$(ip route | awk '/default/ { print $3 }' | head -1 | sed 's/\.[0-9]*$/.0\/24/')"

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
[[ -n "$host_net" ]] && iptables -A OUTPUT -d "$host_net" -j ACCEPT
iptables -A OUTPUT -m set --match-set "$SET" dst -j ACCEPT
# REJECT rather than DROP, so a blocked request fails at once instead of
# hanging until its timeout.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
iptables -P OUTPUT DROP
if ip6tables -L OUTPUT >/dev/null 2>&1; then
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A OUTPUT -j REJECT
    ip6tables -P OUTPUT DROP
fi

# Prove it: an allowlisted host answers, anything else is refused.
if ! curl -fsS --max-time 10 -o /dev/null https://api.github.com/zen; then
    echo "devcontainer-firewall: WARNING: api.github.com is unreachable through the firewall" >&2
fi
if curl -fsS --max-time 5 -o /dev/null https://example.com 2>/dev/null; then
    echo "devcontainer-firewall: ERROR: example.com is reachable; the firewall is not in force" >&2
    exit 1
fi
echo "devcontainer-firewall: outbound traffic limited to $added allowlisted addresses"
if ((${#unresolved[@]} > 0)); then
    echo "devcontainer-firewall: did not resolve: ${unresolved[*]}"
fi
