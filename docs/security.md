# Security

Claude Code runs in Auto mode: its classifier decides which tool calls run without a
prompt. Around it sit a policy it cannot change, an outbound allowlist, and no sudo.

## Managed policy

[`managed-settings.json`](../%7B%7Bcookiecutter.project_slug%7D%7D/.devcontainer/config/claude/managed-settings.json)
is baked into the image at `/etc/claude-code/` and ranks above every user setting. It
disables bypass mode and denies force-push, squash merges, history pruning, Azure and
GitHub deletes, Docker volume removal, and printing or reading tokens. Rules match
command text: a floor, not a boundary. It also forces Claude Code's Bash sandbox off
(bubblewrap cannot run in an unprivileged container), so a project's own
`.claude/settings.local.json` cannot switch it on. A change needs `dev rebuild`.

The bundled `settings.json` adds two Auto mode allow rules to Claude Code's defaults:
merging your own `kokko-ng/*` and `Insight-Services-APAC/*` PRs with a merge commit once
CI is green, and redeploying an approved app to the same sandbox, dev or demo target.

## Firewall

With `network_firewall=on`, the container reaches only the hosts in
`.devcontainer/firewall/allowed-domains.txt` plus GitHub's ranges; `localhost` is
unaffected and other hosts fail at once with "No route to host".

- dnsmasq in the container is its resolver and adds an allowlisted name's addresses as
  it is looked up, so rotating CDN addresses keep working.
- Add a project's hosts to that file, one per line, then `dev rebuild`. An entry covers
  its subdomains too; write `*.example.com` for a domain whose hosts are not known ahead.
- `devcontainer-firewall --blocked` lists hosts looked up recently whose addresses were
  refused; the query log is `/var/log/devcontainer-firewall/dns.log`.
- `sudo devcontainer-firewall` re-applies the rules.
- In VS Code, set `"remote.downloadExtensionsLocally": true` so extensions download on
  the Mac.

## Sudo

With `agent_sudo=no`, provisioning removes the container user's sudo on every start, so
nothing inside can change the policy or the firewall. Run `dev root` on the Mac for a
root shell.

Docker-in-Docker (`include_docker_in_docker=yes`) runs the container privileged, which
is in effect root on the Colima VM and every project in it. It is off by default.
