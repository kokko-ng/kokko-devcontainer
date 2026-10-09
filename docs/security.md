# Security

Claude Code runs in Auto mode: its classifier decides which tool calls run without a
prompt. Around it sit a policy it cannot change, an outbound allowlist, and no sudo.

## Managed policy

[`managed-settings.json`](../%7B%7Bcookiecutter.project_slug%7D%7D/.devcontainer/config/claude/managed-settings.json)
is baked into the image at `/etc/claude-code/` and ranks above every user setting. It
disables bypass mode and denies force-push, squash merges, history pruning, Azure and
GitHub deletes, Docker volume removal, and printing or reading tokens. Rules match
command text: a floor, not a boundary. A change needs `dev rebuild`.

## Firewall

With `network_firewall=on`, the container reaches only the hosts in
`.devcontainer/firewall/allowed-domains.txt` plus GitHub's ranges; `localhost` is
unaffected and other hosts fail at once with "No route to host".

- Add a project's hosts to that file, one exact name per line, then `dev rebuild`.
- `sudo devcontainer-firewall` re-resolves addresses when a CDN rotates them.
- In VS Code, set `"remote.downloadExtensionsLocally": true` so extensions download on
  the Mac.

## Sudo

With `agent_sudo=no`, provisioning removes the container user's sudo on every start, so
nothing inside can change the policy or the firewall. Run `dev root` on the Mac for a
root shell.

Docker-in-Docker (`include_docker_in_docker=yes`) runs the container privileged, which
is in effect root on the Colima VM and every project in it. It is off by default.
