# Update kokko-devcontainer on this Mac

Copy everything below the line into Claude Code running on the Mac (not in a
container), or run `claude "Follow ~/code/kokko-devcontainer/prompts/update.md"`.

---

Update kokko-devcontainer on this Mac to the latest version, then bring my
existing projects' devcontainers up to date. Ask me before anything
destructive; never stop or rebuild a container I did not ask you to.

1. **Update the clone.** In `~/code/kokko-devcontainer`: if it has uncommitted
   changes or is not on `main`, stop and show me `git status -sb`. Otherwise
   note the current `VERSION`, run `git pull --ff-only`, and note the new one.
   If the pull refuses because `main` was rewritten upstream (it was on
   2026-10-09, to clean the history), check `git log origin/main..main`: when
   none of those commits is mine beyond what upstream has under new hashes
   (same subjects), ask me, then `git reset --hard origin/main`.
   If it was not cloned yet, follow `prompts/setup.md` instead.
2. **Check the link.** `~/.local/bin/dev` must link to
   `~/code/kokko-devcontainer/bin/dev` (`ls -l ~/.local/bin/dev`); fix it with
   `ln -sfn` if not. Run `dev guide` and report anything it flags (a missing
   Claude token means I run `dev auth`; an oversized VM means `dev vm resize`,
   which restarts running containers, so ask).
3. **What changed.** Summarise `git log --oneline <old>..HEAD` in a few lines,
   grouped as: the `dev` command (takes effect now), the project template
   (needs a per-project update), and docs.
4. **Existing projects.** Find the projects generated from this template:
   folders under `~/code` with `.devcontainer/post-create.sh` and
   `.devcontainer/firewall/`. List them with whether each container is
   running (`dev ls`). Then update each one's `.devcontainer/`, one project at
   a time, showing me the plan for a project before changing it:
   - **Skip** a project whose `.devcontainer/` has uncommitted changes; ask me
     to commit them first.
   - **Its answers.** Work out the cookiecutter answers it was generated with
     from its files (`cookiecutter.json` lists the keys): the project name in
     the first line of `devcontainer.json`, the Python version in the
     Dockerfile's `FROM`, the features present (Azure CLI, Docker-in-Docker,
     Node version), the ODBC layer, and the `DEVCONTAINER_*` values and mount
     names in `devcontainer.json` (Copilot, Playwright, sudo, firewall, volume
     scope, git identity, memory limit), the plugin roster and attribution in
     `config/claude/settings.json`.
   - **Old and new renders.** In a scratch folder, make a worktree of the
     clone at the last `main` commit before the project's latest
     `.devcontainer/` commit (`git log -1 --format=%cI -- .devcontainer` in
     the project; `git rev-list -1 --before=<date> main` in the clone).
     Render it and the updated clone with those answers:
     `uvx cookiecutter <template> --no-input -o <dir> key=value ...`. If the
     old render differs from the project in ways that look like wrong
     answers rather than local edits, fix the answers and render again.
   - **Merge.** For each file under the new render's `.devcontainer/`, and
     the project's `DEVCONTAINER.md`, three-way merge into the project:
     `git merge-file -p <project file> <old render> <new render>`. New files
     are copied; files upstream removed are reported, not deleted; local
     edits survive. Show me any conflict and how you would resolve it. Leave
     `certs/` and `.host-git-identity` alone (the host fills them).
   - **Apply.** Write the merged files, then show `git diff --stat` and the
     interesting hunks. Do not commit; ask me.
   - **Make it live.** Config changes (`config/claude/`, `config/zsh/`,
     `post-create.sh`) apply to a running container with
     `devcontainer exec --workspace-folder <project> bash .devcontainer/post-create.sh --config-only`.
     A changed `Dockerfile`, `devcontainer.json`, `firewall/` or
     `init-host-*.sh` needs `dev rebuild <project>`: ask me first, since it
     replaces the running container (volumes, so sign-ins and Claude Code
     history, are kept). A stopped container picks everything up at its next
     `dev rebuild`.
   Opening a project with `dev` already brings its Claude Code version, theme
   and sign-ins in line with the Mac, so those need nothing.

Finish with: the version before and after, what changed, and per project
what was merged, what is live, and what still needs `dev rebuild`. Remove the
scratch renders and worktrees.
