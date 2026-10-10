# Security

Claude Code runs in Auto mode: its classifier decides which tool calls run without a
prompt. Around it sit a policy it cannot change, an outbound allowlist, and no sudo.

## Managed policy

[`managed-settings.json`](../%7B%7Bcookiecutter.project_slug%7D%7D/.devcontainer/config/claude/managed-settings.json)
is baked into the image at `/etc/claude-code/` and ranks above every user setting. It
disables bypass mode and denies force-push, squash merges, history pruning, GitHub
deletes, Docker volume removal, and printing or reading tokens, including the full
sign-in `dev auth --full` stores in `~/.claude/.credentials.json`. Azure `delete` and
`purge` are an ask rule instead: they always stop at a permission prompt, so an approved
clean-up runs in the session rather than being handed to you. Rules match
command text: a floor, not a boundary. It also forces Claude Code's Bash sandbox off
(bubblewrap cannot run in an unprivileged container), so a project's own
`.claude/settings.local.json` cannot switch it on. A change needs `dev rebuild`.

The bundled `settings.json` gives Auto mode's classifier an environment section (your
GitHub orgs, Azure as the cloud, sandbox, dev and demo as the safe deploy targets and
prod, production and prd as the protected ones, the firewall) and adds six allow rules to
Claude Code's defaults:

- merging your own `kokko-ng/*` and `Insight-Services-APAC/*` PRs with a merge commit
  once CI is green;
- cloning, committing and pushing branches in repos of your three orgs, except pushes to
  insight-slidev-theme and to the-runbook's `main`;
- redeploying an approved app to the same sandbox, dev or demo target;
- deploying to a sandbox, dev or demo target when you ask for a deploy;
- setting a secret there that the session generated or you gave;
- a repo's own scripts fetching a service key there and using it only with that service.

Both come from `scripts/auto-mode/` (`own-rules.json` plus Claude Code's defaults, built
by `build.jq`). The merge adds them only to a settings.json without an `autoMode` block,
so `refresh-auto-mode.sh` moves a block an earlier bundle shipped, unedited, onto the
new one; an edited block is left alone.

## Firewall

With `network_firewall=on`, the container reaches only the hosts in
`.devcontainer/firewall/allowed-domains.txt` plus GitHub's ranges; `localhost` is
unaffected and other hosts fail at once with "No route to host".

- dnsmasq in the container is its resolver and adds an allowlisted name's addresses as
  it is looked up, so rotating CDN addresses keep working.
- Add a project's hosts to that file, one per line, then `dev rebuild`. An entry covers
  its subdomains too; write `*.example.com` for a domain whose hosts are not known ahead.
- `devcontainer-firewall --blocked` lists hosts looked up recently whose addresses were
  refused, with expected background traffic (a browser's Google services, tool
  telemetry) on a line of its own; the query log is
  `/var/log/devcontainer-firewall/dns.log`.
- The image carries a Chromium policy (`config/chromium/managed-policy.json`, installed
  in `/etc/chromium/policies/managed/`) that turns off sign-in, sync, autofill, component
  updates, Safe Browsing and search suggestions, the background traffic Playwright's own
  launch flags leave on.
- It allows by address, not by name: a host on a shared CDN (Cloudflare, Fastly, Google,
  Netlify, Vercel, GitHub Pages) also lets through other sites served from the same
  addresses. `query.wikidata.org` is left out for that reason (it opens Wikipedia,
  which takes anonymous edits). Filtering by name would need a TLS-aware proxy.
- The list covers the hosts the kokko projects use: package registries (PyPI, npm,
  Maven, NuGet, uv's Python builds), GitHub, Anthropic (including the full sign-in and
  Remote Control's bridge), Azure management and the data-plane services the projects
  call, container registries for Docker-in-Docker builds, and the documentation sites
  WebFetch reads.
- `sudo devcontainer-firewall` re-applies the rules.
- In VS Code, set `"remote.downloadExtensionsLocally": true` so extensions download on
  the Mac.

## Sudo

With `agent_sudo=no`, provisioning removes the container user's sudo on every start, so
nothing inside can change the policy or the firewall. Run `dev root` on the Mac for a
root shell.

Docker-in-Docker (`include_docker_in_docker=yes`) runs the container privileged, which
is in effect root on the Colima VM and every project in it. It is off by default.
