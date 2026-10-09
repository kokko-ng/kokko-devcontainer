# Security

Claude Code runs in Auto mode: its classifier decides which tool calls run without a
prompt. The limits sit around it: a policy it cannot change, an outbound allowlist, and
no sudo.

## Managed policy

`/etc/claude-code/managed-settings.json`, baked into the image from
`.devcontainer/config/claude/managed-settings.json`, ranks above every user setting. It
denies:

- force-push, squash merges (`gh pr merge --squash`, `git merge --squash`),
  `git reflog expire`, `git gc --prune`
- Azure `delete` and `purge`, `gh repo delete`, `gh api ... DELETE`
- Docker volume removal and `docker system prune --volumes`
- printing gh and az tokens, and reading the Claude token, the az token cache and gh's
  `hosts.yml`

Deny rules match command text, so they are a floor, not a boundary. A policy change
needs `dev rebuild`. Never set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` in it: that forces the
permission mode back to default, which turns Auto mode off.

Git in the container never expires the reflog or prunes unreachable objects, so
committed work stays recoverable.

## Firewall

With `network_firewall=on`, iptables limits every process in the container to the hosts
in `.devcontainer/firewall/allowed-domains.txt` (GitHub, Copilot, Anthropic, npm, PyPI,
Azure, Playwright, VS Code) plus GitHub's published ranges. `localhost` is unaffected.
Other hosts fail with "connection refused".

- Add a project's hosts to that file, one exact name per line, then `dev rebuild`.
- `sudo devcontainer-firewall` re-resolves addresses when a CDN rotates them. It is the
  one command the container user can still run with sudo.
- In VS Code, set `"remote.downloadExtensionsLocally": true` in your user settings so
  extensions download on the Mac.

Claude Code's own Bash sandbox stays off: it cannot create user namespaces in an
unprivileged container.

## Sudo

With `agent_sudo=no`, provisioning removes the user's passwordless sudo once the root
steps are done, on every start. Nothing in the container can then change the policy or
the firewall. For a root shell, run `dev root` on the Mac.

Docker-in-Docker (`include_docker_in_docker=yes`) runs the container privileged: an
agent in it has, in effect, root on the Colima VM, including other projects' containers
and volumes. It is off by default.

## Credentials

- Sign-ins live in named volumes (`<prefix>-gh-config`, `<prefix>-claude-auth`,
  `<prefix>-azure-config`), filled by `dev` from the Mac. Host credential folders are
  never mounted.
- The Claude token is kept in the macOS Keychain (service
  `kokko-devcontainer-claude-oauth-token`) and copied into the volume with mode 600.
- From `~/.azure`, only `azureProfile.json`, `msal_token_cache.json` and
  `clouds.config` are copied; service principal secrets are not.
- `devcontainer up` gets the Mac's gh token as a lifecycle secret, for the plugin
  bootstrap, without storing it in the container's configuration.

These sign-ins are as powerful as yours. Sign in to Azure as an identity whose rights
you are happy for an agent to use; the policy above limits what an agent does with them.
