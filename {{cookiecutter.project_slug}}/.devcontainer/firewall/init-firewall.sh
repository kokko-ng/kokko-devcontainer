#!/usr/bin/env bash
# Outbound firewall for the devcontainer: everything in the container (Claude
# Code and the commands it runs, Copilot CLI, gh, az, MCP servers, your own
# shells) reaches only the hosts in the allowlist, plus loopback and the Docker
# host. Inbound traffic (port forwarding) is untouched.
#
#   devcontainer-firewall            (re)apply the rules; run as root
#   devcontainer-firewall --blocked  list recently looked-up hosts whose
#                                    addresses the firewall refuses
#
# How addresses get into the allowlist: dnsmasq runs in the container as its
# resolver (127.0.0.1 in /etc/resolv.conf, forwarding to the resolver Docker
# gave the container) with an `ipset=` line per allowlist entry, so every
# lookup of an allowlisted name, or of any name under it, adds the addresses
# it returns to the set at that moment. That keeps up with CDNs that rotate
# addresses mid-session, and is what lets `*.example.com` entries work. The
# names are also resolved once at start, and GitHub's published ranges added.
# dnsmasq logs every query (/var/log/devcontainer-firewall/dns.log, size-capped)
# and `--blocked` reads it back.
#
# Installed root-owned at /usr/local/sbin/devcontainer-firewall, with the
# allowlist at /etc/devcontainer/allowed-domains.txt; both are baked into the
# image, so an edit to the copies under .devcontainer/firewall/ takes effect at
# the next rebuild, which only the host can run. The container user may run
# this script (and nothing else) through sudo: it only ever rebuilds the same
# rules from the same list. post-create.sh applies it on every start; a re-run
# is safe at any time.
#
# Needs the NET_ADMIN and NET_RAW capabilities (devcontainer.json runArgs).
set -euo pipefail

ALLOWLIST="${DEVCONTAINER_FIREWALL_ALLOWLIST:-/etc/devcontainer/allowed-domains.txt}"
SET=devcontainer-allow
STATE_DIR=/run/devcontainer-firewall
LOG_DIR=/var/log/devcontainer-firewall
LOG="$LOG_DIR/dns.log"
LOG_MAX_BYTES=$((2 * 1024 * 1024))
# The resolver Docker wrote into /etc/resolv.conf, saved before this script
# replaces it: Docker leaves a resolv.conf the container edited alone, also
# across restarts, so the saved copy is the only record of the upstream.
UPSTREAM_COPY=/etc/devcontainer/resolv.conf.upstream
MARK="# devcontainer-firewall"
DNSMASQ_CONF="$STATE_DIR/dnsmasq.conf"
DNSMASQ_PID="$STATE_DIR/dnsmasq.pid"
SUPERVISOR_PID="$STATE_DIR/supervisor.pid"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

say() { echo "devcontainer-firewall: $*"; }
die() {
    echo "devcontainer-firewall: $*" >&2
    exit 1
}

mode=apply
case "${1:-}" in
    "") ;;
    --blocked) mode=blocked ;;
    --supervise) mode=supervise ;; # internal: started in the background by apply
    -h | --help)
        echo "usage: devcontainer-firewall [--blocked]"
        exit 0
        ;;
    *)
        echo "usage: devcontainer-firewall [--blocked]" >&2
        exit 2
        ;;
esac

if [[ $EUID -ne 0 ]]; then
    # Reading the set takes root; the sudo grant covers this script.
    [[ "$mode" == blocked ]] && exec sudo -n "$SELF" --blocked
    die "run as root (sudo $SELF)"
fi

# The user dnsmasq drops to (dnsmasq-base creates it); the DNS rules below let
# only that user, and root, reach the upstream resolver.
DNS_USER=dnsmasq
id -u "$DNS_USER" >/dev/null 2>&1 || DNS_USER=nobody

# running <pidfile> <text in its command line>: the command line check keeps
# a stale pid file (a restarted container keeps /run) from naming a process
# that merely reused the number.
running() {
    local pid
    pid="$(cat "$1" 2>/dev/null)" || return 1
    [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
    tr '\0' ' ' <"/proc/$pid/cmdline" | grep -qF -- "$2"
}

stop_pid() { # <pidfile> <text in its command line>
    if running "$1" "$2"; then
        kill "$(cat "$1")" 2>/dev/null || true
        local _
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            running "$1" "$2" || break
            sleep 0.2
        done
    fi
    rm -f "$1"
}

start_dnsmasq() {
    install -d -m 0755 "$LOG_DIR"
    [[ -e "$LOG" ]] || install -m 0644 -o "$DNS_USER" /dev/null "$LOG"
    if ! dnsmasq --conf-file="$DNSMASQ_CONF" </dev/null >/dev/null 2>"$STATE_DIR/dnsmasq.err"; then
        cat "$STATE_DIR/dnsmasq.err" >&2
        return 1
    fi
    # dnsmasq makes its log owner-only; the container user reads it too.
    chmod 0644 "$LOG"
}

# Keeps dnsmasq running and its log under LOG_MAX_BYTES (one rotated copy).
# dnsmasq appends (O_APPEND), so truncating in place is safe.
supervise() {
    echo $$ >"$SUPERVISOR_PID"
    while true; do
        sleep 30
        if ! running "$DNSMASQ_PID" "$DNSMASQ_CONF"; then
            start_dnsmasq 2>/dev/null || true
        fi
        if [[ -f "$LOG" ]] && (($(stat -c %s "$LOG") > LOG_MAX_BYTES)); then
            cp "$LOG" "$LOG.1" && chmod 0644 "$LOG.1" && : >"$LOG"
        fi
    done
}

# Hosts looked up recently whose addresses are not in the allowlist: the
# requests the firewall refused (or will). Names come from the dnsmasq query
# log; an address counts as refused when it is neither in the set nor on the
# Docker host's network.
blocked() {
    local logs=() f
    for f in "$LOG.1" "$LOG"; do [[ -r "$f" ]] && logs+=("$f"); done
    ((${#logs[@]} > 0)) || die "no query log at $LOG (is the firewall applied?)"
    local host_net
    host_net="$(ip route | awk '/default/ { print $3 }' | head -1 | sed 's/\.[0-9]*$/./')"
    local -A refused=() addrs=()
    local when name ip
    # Fields (log-queries=extra): Mon DD HH:MM:SS dnsmasq[pid]: SERIAL CLIENT
    # VERB NAME ...; the serial ties each reply to the name that was asked,
    # not to the CNAME it ended at. One line per name and address, last seen.
    # Only lines since dnsmasq last started count: every apply restarts it
    # with an emptied set, so older answers say nothing about the set now.
    while read -r when name ip; do
        [[ -n "$host_net" && "$ip" == "$host_net"* ]] && continue
        ipset test "$SET" "$ip" 2>/dev/null && continue
        if [[ "${refused[$name]:-}" < "$when" ]]; then refused["$name"]="$when"; fi
        addrs["$name"]="${addrs[$name]:-}${addrs[$name]:+ }$ip"
    done < <(awk '
        / started, version / { delete asked; delete last; next }
        $7 == "query[A]" { asked[$5] = $8; next }
        ($7 == "reply" || $7 == "cached") && $9 == "is" && $10 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
            name = ($5 in asked) ? asked[$5] : $8
            last[name " " $10] = sprintf("%s-%02d-%s", $1, $2, $3)
        }
        END { for (k in last) print last[k], k }' "${logs[@]}")
    if ((${#refused[@]} == 0)); then
        say "no refused lookups in the query log"
        return 0
    fi
    echo "Hosts looked up whose addresses the firewall refuses (most recent last)."
    echo "Allow one by adding it to .devcontainer/firewall/allowed-domains.txt, then dev rebuild."
    for name in "${!refused[@]}"; do
        printf '%s  %s  (%s)\n' "${refused[$name]//-/ }" "$name" "${addrs[$name]}"
    done | sort -k1,1M -k2,2n -k3,3 | tail -n 50
}

case "$mode" in
    blocked)
        blocked
        exit 0
        ;;
    supervise)
        supervise
        exit 0
        ;;
esac

for tool in iptables ipset dig curl jq dnsmasq; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is missing from the image (dev rebuild)"
done
[[ -r "$ALLOWLIST" ]] || die "no allowlist at $ALLOWLIST"
install -d -m 0755 "$STATE_DIR"

# Open up while addresses are resolved, so a re-run is not blocked by the
# rules it is about to replace.
iptables -P OUTPUT ACCEPT
iptables -F OUTPUT
ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
ip6tables -F OUTPUT 2>/dev/null || true

# A re-run starts a fresh dnsmasq: its cache would otherwise answer from
# memory, and only answers fetched from upstream add addresses to the set.
stop_pid "$SUPERVISOR_PID" --supervise
stop_pid "$DNSMASQ_PID" "$DNSMASQ_CONF"

# The upstream resolver: Docker's, saved on first use.
if ! grep -q "^$MARK" /etc/resolv.conf; then
    cp /etc/resolv.conf "$UPSTREAM_COPY"
fi
[[ -s "$UPSTREAM_COPY" ]] || die "no saved upstream resolver at $UPSTREAM_COPY (dev rebuild)"
mapfile -t upstreams < <(awk '$1 == "nameserver" && $2 ~ /^[0-9.]+$/ && $2 != "127.0.0.1" { print $2 }' "$UPSTREAM_COPY")
((${#upstreams[@]} > 0)) || die "no IPv4 nameserver in $UPSTREAM_COPY"

ipset create "$SET" hash:net -exist
ipset flush "$SET"
added=0
add() {
    if ipset add "$SET" "$1" -exist 2>/dev/null; then added=$((added + 1)); fi
}

# The allowlist: one host per line; `*.example.com` means example.com and
# every name under it. dnsmasq matches a domain and its subdomains either way;
# exact names are additionally resolved at start below.
exact=()
domains=()
while read -r host; do
    host="${host%%#*}"
    host="${host//[[:space:]]/}"
    [[ -n "$host" ]] || continue
    if [[ ! "${host#\*.}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
        echo "devcontainer-firewall: not a host name, skipping: $host" >&2
        continue
    fi
    domains+=("${host#\*.}")
    [[ "$host" == \** ]] || exact+=("$host")
done <"$ALLOWLIST"

{
    echo "# Generated by devcontainer-firewall; rewritten on every run."
    echo "listen-address=127.0.0.1"
    echo "bind-interfaces"
    echo "no-resolv"
    echo "no-hosts"
    echo "user=$DNS_USER"
    echo "pid-file=$DNSMASQ_PID"
    echo "log-queries=extra"
    echo "log-facility=$LOG"
    echo "cache-size=1000"
    # IPv6 egress is refused outright; answering A only spares every client
    # a failed IPv6 attempt first.
    echo "filter-AAAA"
    for ns in "${upstreams[@]}"; do echo "server=$ns"; done
    for d in "${domains[@]}"; do echo "ipset=/$d/$SET"; done
} >"$DNSMASQ_CONF"
start_dnsmasq || die "dnsmasq did not start; DNS is unchanged"

# /etc/resolv.conf is a bind mount: rewrite it in place, keeping Docker's
# search and options lines.
{
    echo "$MARK: dnsmasq on 127.0.0.1 forwards to ${upstreams[*]}"
    echo "nameserver 127.0.0.1"
    grep -E '^(search|options)[[:space:]]' "$UPSTREAM_COPY" || true
} >/etc/resolv.conf

# GitHub publishes its address ranges; hosts behind them rotate too often to
# resolve one by one.
if meta="$(curl -fsS --max-time 15 https://api.github.com/meta)"; then
    while read -r cidr; do
        [[ "$cidr" == *:* ]] || add "$cidr"
    done < <(jq -r '(.web + .api + .git + .packages + (.copilot // [])) | .[]' <<<"$meta")
else
    echo "devcontainer-firewall: could not fetch GitHub's ranges; resolving github.com hosts by name only" >&2
fi

# Resolve the exact names now (through dnsmasq, which adds them as well), so
# the count below means something and a host that does not resolve is named.
unresolved=()
for host in "${exact[@]}"; do
    ips="$(dig +short +time=3 +tries=2 A "$host" | grep -E '^[0-9.]+$' || true)"
    if [[ -z "$ips" ]]; then
        unresolved+=("$host")
        continue
    fi
    for ip in $ips; do add "$ip"; done
done

# The Docker host's network: port forwarding replies and host.docker.internal.
host_net="$(ip route | awk '/default/ { print $3 }' | head -1 | sed 's/\.[0-9]*$/.0\/24/')"

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# DNS leaves the container only from dnsmasq, to the upstream it forwards to.
# Root too: on a user-defined network Docker's embedded resolver (127.0.0.11)
# forwards from inside this namespace as root.
for proto in udp tcp; do
    for ns in "${upstreams[@]}"; do
        iptables -A OUTPUT -p "$proto" --dport 53 -d "$ns" -m owner --uid-owner "$DNS_USER" -j ACCEPT
    done
    iptables -A OUTPUT -p "$proto" --dport 53 -m owner --uid-owner 0 -j ACCEPT
    iptables -A OUTPUT -p "$proto" --dport 53 -j REJECT
done
[[ -n "$host_net" ]] && iptables -A OUTPUT -d "$host_net" -j ACCEPT
iptables -A OUTPUT -m set --match-set "$SET" dst -j ACCEPT
# REJECT rather than DROP, so a blocked request fails at once ("No route to
# host") instead of hanging until its timeout. `devcontainer-firewall
# --blocked` lists the hosts that ended up here.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
iptables -P OUTPUT DROP
if ip6tables -L OUTPUT >/dev/null 2>&1; then
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A OUTPUT -j REJECT
    ip6tables -P OUTPUT DROP
fi

# Restart dnsmasq if it dies, and cap its log. Detached, with no inherited
# descriptors, so the caller's pipe (post-create.sh | tee) is not held open.
setsid "$SELF" --supervise </dev/null >/dev/null 2>&1 &

# Prove it: an allowlisted host answers, anything else is refused.
if ! curl -fsS --max-time 10 -o /dev/null https://api.github.com/zen; then
    echo "devcontainer-firewall: WARNING: api.github.com is unreachable through the firewall" >&2
fi
if curl -fsS --max-time 5 -o /dev/null https://example.com 2>/dev/null; then
    die "ERROR: example.com is reachable; the firewall is not in force"
fi
say "outbound traffic limited to ${#domains[@]} allowlisted names ($added addresses so far, more as they are looked up)"
if ((${#unresolved[@]} > 0)); then
    say "did not resolve: ${unresolved[*]}"
fi
