# kokko-devcontainer

A [cookiecutter](https://cookiecutter.readthedocs.io/) template for a portable
FastAPI + Vue development container, designed to run on macOS with Colima as the Docker
runtime. Answer a dozen prompts and you get a `.devcontainer/` tailored to your project
instead of a starter you have to hand-edit.

## Quick start

```bash
# 1. Install prerequisites (see INSTRUCTIONS.md for detail)
brew install colima devcontainer cookiecutter
brew install --cask ghostty

# 2. Start Colima
# --disk is generous on purpose: devcontainer images are 5-6GB each and
# Colima can grow a disk but never shrink it. See MANAGING.md.
# --mount-type virtiofs is the current default, but it only applies to a
# NEWLY CREATED VM -- an existing VM keeps whatever it was made with, and
# sshfs is ~940x slower on small-file writes. See MANAGING.md.
# --memory should be at most half your host RAM (use 8 on a 16GB Mac).
colima start --cpu 8 --memory 16 --disk 150 --mount-type virtiofs

# 3. Generate a project
cookiecutter gh:kokko-ng/kokko-devcontainer

# 4. Open it
cd <your-project-slug>
code .
# Accept the "Reopen in Container" prompt

# — or — use the CLI
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```

Pin to a released version instead of tracking `main`:

```bash
cookiecutter gh:kokko-ng/kokko-devcontainer --checkout v4.0.0
```

### Adding it to a project you already have

Cookiecutter always writes a new directory, so generate next to your project and move
the result in:

```bash
cookiecutter gh:kokko-ng/kokko-devcontainer -o /tmp
cp -r /tmp/<your-project-slug>/.devcontainer ~/projects/your-project/
cp /tmp/<your-project-slug>/CLAUDE.md ~/projects/your-project/        # or merge into yours
cat /tmp/<your-project-slug>/.gitignore >> ~/projects/your-project/.gitignore
```

Answer the prompts with your existing layout (`backend_src_dir`, `frontend_dir`, the
ports) so the generated config matches what is already there. The `CLAUDE.md` tells
Claude Code how to verify its work in that layout, and the `.gitignore` keeps what the
container creates (`.env`, Claude worktrees, Playwright artifacts) out of commits.

### Repeatable and scripted generation

Every answer can be supplied on the command line, which is also how CI generates the
project it builds:

```bash
cookiecutter gh:kokko-ng/kokko-devcontainer --no-input \
  project_name="Acme API" include_azure_cli=no include_playwright=no
```

`cookiecutter --replay gh:kokko-ng/kokko-devcontainer` regenerates with the answers you
gave last time.

## Template options

| Prompt | Default | What it changes |
|---|---|---|
| `project_name` | `My Project` | Documentation headings |
| `project_slug` | derived from the name | Generated directory, container name, per-project volume names |
| `python_version` | `3.14` | Base image tag. Only `3.14` carries the digest pin — see [Base image pinning](#base-image-pinning) |
| `node_version` | `22` | `node` feature version |
| `backend_src_dir` | `src` | `PYTHONPATH` |
| `frontend_dir` | `ui` | Where `post-create.sh` installs frontend dependencies |
| `backend_port` | `8000` | Forwarded port |
| `frontend_port` | `5173` | Forwarded port |
| `include_azure_cli` | `yes` | The `azure-cli` feature and the optional in-container Azure login volume hint |
| `include_azure_sql_driver` | `yes` | The `msodbcsql18` + `unixodbc-dev` apt layer (pyodbc / Azure SQL) |
| `include_docker_in_docker` | `no` | The `docker-in-docker` feature and the Docker VS Code extension. Off by default: the feature runs the container **privileged**, which hands an unattended agent the whole Colima VM |
| `include_copilot_cli` | `yes` | Whether `post-create.sh` installs `@github/copilot` |
| `include_playwright` | `yes` | The Playwright CLI, its browser volume, and the Chromium-related `runArgs` |
| `claude_plugin_roster` | `kokko-ng` | `kokko-ng` ships all 9 plugins; `none` ships an empty roster |
| `claude_attribution` | `no` | Whether Claude Code signs the commits and pull requests it makes with its `Co-Authored-By` trailer and PR footer. `no` hides both |
| `cache_volume_scope` | `shared` | `shared` reuses one set of cache and gh-login volumes across projects; `per-project` namespaces them by slug. The Claude Code state volume is always per project |
| `container_memory_limit` | `8g` | Docker's `--memory` (and `--memory-swap`) for the container, so a runaway process is killed inside it instead of taking the Colima VM down. Keep it below the VM's `--memory` |
| `git_user_name` | `kokko-ng` | With `git_user_email`, the author of every commit made in the container, Claude Code's included. Set on first provision and never overwritten, so a value changed inside the container survives rebuilds. Leave both blank to leave git untouched |
| `git_user_email` | `Kokko.Ng@insight.com` | See `git_user_name`; both or neither |

Invalid answers are rejected before anything is written — a non-lowercase slug, a port
below 1024, two services on the same port, an absolute or escaping source directory, a
memory limit without an `m`/`g` unit or below `512m`.

## What you get

| Tool | Purpose |
|------|---------|
| Python 3.14 + uv | Backend runtime and dependency management |
| Node 22 | Frontend build tooling |
| GitHub CLI | Repository and PR workflows |
| Claude Code | AI coding assistant (native binary via `claude.ai/install.sh`, pinned to a version and baked into the image, auto-update off), with the `kokko-ng` plugin roster installed automatically |
| pre-commit + shellcheck | The hooks the bundled `CLAUDE.md` makes mandatory, and a linter for the shell agents write |
| bubblewrap + socat | Linux dependencies of Claude Code's Bash sandbox, shipped switched off and one `/sandbox` away |
| zsh + oh-my-zsh | Shell with autosuggestions and syntax highlighting |
| Azure CLI | Azure resource management (optional) |
| ODBC Driver 18 (msodbcsql18) | Azure SQL connectivity via pyodbc (optional) |
| GitHub Copilot CLI | `copilot` binary, installed via `npm i -g @github/copilot@<pinned>` (optional) |
| Playwright CLI + Chromium | Browser automation for coding agents (optional) |
| Docker-in-Docker | Container builds inside the devcontainer (optional, off by default: it runs the container privileged) |

Versions and optional rows follow your answers. Docker-in-Docker keeps its own image
store in a volume that grows unnoticed — `docker system df` does not count it. Prune it
periodically from inside the container; see [Disk management](MANAGING.md#disk-management).

Alongside `.devcontainer/`, a generated project gets a `CLAUDE.md` (layout, verification
commands and container facts for the agent) and a `.gitignore` for what the container
creates. Claude Code's login, plugins and history live in a per-project named volume,
and the `gh` login in another, so a rebuild costs neither a sign-in nor a re-download.

The generated container is portable — `HOST_USER` is auto-injected from your macOS
username, and bundled config paths are resolved relative to the script, so the workspace
can be named anything.

## Repo structure

```
cookiecutter.json         # The prompts, their defaults, and what is copied unrendered
hooks/
├── pre_gen_project.py    # Rejects invalid answers before anything is written
└── post_gen_project.py   # Trims the Claude plugin roster; prints next steps
{{cookiecutter.project_slug}}/     # Everything a generated project receives
├── DEVCONTAINER.md       # Generated per-project docs
├── CLAUDE.md             # Generated project instructions for Claude Code
├── .gitignore            # What the container creates and git must not see
└── .devcontainer/
    ├── devcontainer.json # Jinja-templated (JSONC)
    ├── Dockerfile        # Jinja-templated
    ├── init-host-certs.sh
    ├── post-create.sh    # Jinja-free; options arrive as containerEnv variables
    └── config/
        ├── zsh/          # Shell config (bundled into container)
        └── claude/       # Claude Code settings, policy, hook and CLAUDE.md
            ├── settings.json          # Defaults the user may override (merged)
            ├── managed-settings.json  # Policy the user may not: deny list, no bypass mode
            ├── hooks/                 # SessionStart hook: surfaces failed provisioning
            ├── merge-settings.jq      # Merges bundled settings into a live settings.json
            └── prune-roster.jq        # Removes roster entries the bundle dropped
ghostty/
└── config                # Host-side Ghostty terminal config (not templated)
tests/
├── merge-settings-tests.sh  # Regression tests for the settings pipeline
└── template-tests.sh        # Renders the template and asserts the output
.github/                  # CI (pre-commit, both test suites, shellcheck, actionlint,
                          # hadolint, render + build, gitleaks) + release workflow
VERSION                   # Drives the v<version> tag published by release.yml
CLAUDE.md                 # For agents working ON this repo (tests, layout, rules)
CONTRIBUTING.md           # Test commands, pre-commit setup, release flow
INSTRUCTIONS.md           # Full setup walkthrough
MANAGING.md               # Multi-instance management guide
```

### Which files carry Jinja

Only `devcontainer.json`, the `Dockerfile`, and the Markdown (including the generated
`CLAUDE.md`) are templated. `post-create.sh`, `init-host-certs.sh`, the `.jq` files, the
bundled `settings.json` and `managed-settings.json`, the hook script, and the zsh config
are deliberately Jinja-free, so they stay shellcheck-clean, `jq`-parseable, and directly
testable with no rendering step. The options those files need arrive at run time as
`DEVCONTAINER_*` variables in `containerEnv`.

## Permission model

Claude Code runs in **Auto mode** (`permissions.defaultMode: "auto"` in the bundled
settings.json, and the `cca` alias): Claude Code's built-in classifier decides which
tool calls are safe to run without a prompt. There is no bespoke hook layer in front of
git — the guard/snapshot hooks and the `snaps` CLI that earlier versions shipped are
retired, and `post-create.sh` removes their leftovers from containers that still carry
them.

Two things sit around auto mode:

- **A deny floor it cannot cross.** `managed-settings.json` is installed to
  `/etc/claude-code/managed-settings.json`, the highest-precedence settings file, so
  nothing in `~/.claude` or a project can loosen it. It denies force-push in every
  spelling, `git reflog expire` and `git gc --prune`, Azure `delete`/`purge`, Docker
  volume pruning, `gh repo delete` and `gh api ... DELETE`, and it disables bypass mode
  (`--dangerously-skip-permissions`; the old `skipDangerousModePermissionPrompt` is
  gone, and the merge strips it from existing containers). Deny rules match the
  command as Claude writes it, including inside `&&` chains and subshells, but not a
  different program that does the same thing — a floor, not a security boundary.
- **The Bash sandbox, ready but off.** `bubblewrap` and `socat` are in the image and
  the bundled settings carry the container-specific sandbox configuration; `/sandbox`
  turns it on. It ships off because its network allowlist has to match your
  environment first.

Docker-in-Docker is opt-in for the same reason: the feature runs the container
privileged, which hands an unattended agent the whole Colima VM.

Git recoverability rests on git itself: `gc.reflogExpire`, `gc.reflogExpireUnreachable`
and `gc.pruneExpire` are set to `never`, so committed work is always recoverable from
the reflog, and `safe.directory` is `*` so git works in the bind-mounted workspace and
in the worktrees `claude --worktree` creates.

A `SessionStart` hook prints any provisioning step that failed into the session, so the
agent learns about a broken `uv sync` before it starts work. The Bash tool's timeout is
raised (10 minutes by default, 30 on request) so full test suites finish in one call.

## Claude Code plugins

`post-create.sh` registers the marketplaces in `extraKnownMarketplaces` and installs every
plugin set to `true` in `enabledPlugins`, both read from
`.devcontainer/config/claude/settings.json`. `enabledPlugins` on its own only *enables* a
plugin that is already installed, so without this step a fresh container comes up with an
empty plugin directory.

With `claude_plugin_roster=kokko-ng` (the default) that is all 9 `kokko-ng` plugins across
[kokko-skills](https://github.com/kokko-ng/kokko-skills) and
[kokko-janitor-skill](https://github.com/kokko-ng/kokko-janitor-skill). With `none` the roster is empty
and you add your own. Either way, edit `enabledPlugins` afterwards to change it; a plugin
set to `false` is never installed.

The bootstrap reads the **merged** `~/.claude/settings.json`, so a plugin you disable
locally stays disabled. Its network calls run at most once per 24 hours (stamp:
`~/.claude/.plugin-bootstrap-stamp`); two environment variables control it:

| Variable | Effect |
|---|---|
| `KOKKO_PLUGIN_REFRESH=1` | Force a marketplace/plugin refresh now, ignoring the 24h stamp |
| `KOKKO_SKIP_PLUGINS=1` | Skip the plugin bootstrap entirely (used by CI) |

## Base image pinning

The `Dockerfile` pins its base image by digest, but the template only carries a digest
for its default Python (`3.14`). Choosing another Python version emits a tag-only `FROM`
plus a warning telling you how to pin it — inventing a digest would be worse than
shipping none.

## Updating a generated project

Bundled config changes — `CLAUDE.md`, `settings.json`, `managed-settings.json`, the
SessionStart hook, zsh config, the plugin roster — can be re-applied in place, with no
rebuild:

```bash
bash .devcontainer/post-create.sh --config-only
```

`/devcontainer-update` (from `kokko-env` in
[kokko-skills](https://github.com/kokko-ng/kokko-skills)) does the whole job: diff this
project's `.devcontainer/` against the latest upstream, update the files, run the refresh,
and report what still needs a rebuild.

Releases are tagged: the `VERSION` file at the repo root drives a `v<version>` tag and
GitHub release, published automatically once CI passes on `main`. That means
`--checkout v4.0.0` (cookiecutter) or `/devcontainer-update --ref v4.0.0` can pin a
project to a known-good version instead of tracking `main`. Dockerfile (including the
Claude Code version pin) and `devcontainer.json` `features`/`containerEnv`/`runArgs`/
`mounts` changes always need a rebuild.

## Caveats

- The generated devcontainer assumes a **FastAPI + Vue** project layout. The
  `backend_src_dir` and `frontend_dir` prompts cover the common case; anything more
  unusual is a post-generation edit.
- Shell config (zsh) and Claude Code settings are bundled in `.devcontainer/config/` — no
  host dotfiles are read.
- Claude Code state persists in a per-project named volume and the `gh` login in a
  shared one; nothing is bind-mounted from the host. Host credential directories
  (`~/.ssh`, `~/.azure`, the host's `~/.claude`) stay outside on purpose — everything
  reachable inside the container is reachable by an agent running without prompts. An
  optional named volume for an in-container `az login` is commented out in
  `devcontainer.json`.
- Claude Code is pinned to a version in the `Dockerfile` and does not auto-update. `cu`
  installs the latest release until the next rebuild; bump the pin to move for good.

See [INSTRUCTIONS.md](INSTRUCTIONS.md) for a full setup walkthrough and [MANAGING.md](MANAGING.md) for running multiple instances.
