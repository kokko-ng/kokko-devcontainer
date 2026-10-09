# Set up kokko-devcontainer on this Mac

Copy everything below the line into Claude Code running on the Mac (not in a
container).

---

Set up kokko-devcontainer on this Mac so I can run `dev claude` in a project.
Work through the steps in order, check each one before moving on, and ask me
before anything destructive. Logins and anything that opens a browser are
mine to run: give me the exact command (with the `!` prefix where that works)
and wait.

1. **Prerequisites.** Check for each, and install what is missing with
   Homebrew (ask first): `colima`, `docker` (the CLI only; Colima is the
   runtime), `jq`, `gh`, `uv`, `node`. Then `npm install -g @devcontainers/cli`.
   Optional: `azure-cli` (cask) for Azure, `ghostty` (cask) for `dev -t`, VS
   Code for `dev code`. Claude Code itself must be on the Mac (`claude
   --version`). Do not start Colima; `dev` starts and sizes it.
2. **Sign-ins on the Mac.** `gh auth status` must show a login; if not, I run
   `gh auth login`. If Azure is installed, `az account show` should work; if
   not, I run `az login`. Devcontainers copy both from the Mac.
3. **Clone and link.**
   ```bash
   mkdir -p ~/code ~/.local/bin
   git clone https://github.com/kokko-ng/kokko-devcontainer.git ~/code/kokko-devcontainer
   ln -sfn ~/code/kokko-devcontainer/bin/dev ~/.local/bin/dev
   ```
   If the clone already exists, `git -C ~/code/kokko-devcontainer pull`
   instead. Make sure `~/.local/bin` is on PATH in a new login shell
   (`zsh -lic 'command -v dev'`); if it is not, tell me which file to add it
   to rather than editing my shell config unasked.
4. **First project.** Ask me for a short lowercase name (the folder name;
   `dev new` would lowercase capitals and turn spaces and underscores into
   hyphens), then I run `dev new <name>` myself in a terminal: it generates
   `~/code/<name>` from the template, builds the container (a few minutes
   the first time; it shows progress) and opens a shell in it, which I leave
   with `exit`.
5. **Claude Code token.** I run `dev auth <name>` myself (it needs a project;
   it opens the browser once and keeps a year-long token in the Keychain that
   every devcontainer shares). Wait for me.
6. **Check.** Run `dev guide`: it should show "Claude token: in Keychain" and
   the VM size for this Mac. Report the VM size and anything it flags. Then
   `dev claude <name>`, or just `dev claude` inside `~/code/<name>`, opens
   Claude Code there, signed in.

If `~/code` already has projects generated from this template (folders with
`.devcontainer/post-create.sh` and `.devcontainer/firewall/`), bring their
devcontainers up to date as `prompts/update.md` step 4 describes.

Finish with a short checklist: each step done, skipped, or waiting on me.
