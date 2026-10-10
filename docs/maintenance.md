# Maintenance

## Updating a project

`/devcontainer-update` (kokko-env plugin) three-way merges the latest template files
(`.devcontainer/`, `DEVCONTAINER.md`, `CLAUDE.md`, `.gitignore`, the pre-commit config,
`pyproject.toml`, `trivy.yaml`, CI and `scripts/hooks/`, never the project's own code)
into a project and says what needs a rebuild; [prompts/update.md](../prompts/update.md) updates
this clone and every project. Changes under `.devcontainer/config/` apply on the next
start (or now: `bash .devcontainer/post-create.sh --config-only`); the Dockerfile,
`devcontainer.json`, the policy and the firewall allowlist need `dev rebuild`.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `docker` cannot connect, `colima status` looks fine | VM disk full: [When the disk is full](#when-the-disk-is-full) |
| Container very slow, exec sessions die | VM on `sshfs`: [Mount type](#mount-type) |
| Files like `name 2.ext` keep appearing | Project in a cloud-synced folder. Move it to `~/code` |
| "No route to host" from a host | The firewall: `devcontainer-firewall --blocked` names it; [security.md](security.md#firewall) |
| "Illegal instruction" from az or Python | Old image without `OPENSSL_armcap=0`. `dev rebuild` |
| Orange renders as red | Old container without `COLORTERM=truecolor`. `dev rebuild` |
| A provisioning step failed | Shown when a Claude Code session starts; details in `/tmp/post-create.log` |

## Port conflicts

Two containers cannot forward the same host port. Give each project its own
`backend_port`/`frontend_port`, or edit `forwardPorts` in `devcontainer.json` and
rebuild.

## Mount type

Use `virtiofs`; `sshfs` is far slower on small-file writes. Check with
`colima ssh -- mount | grep /Users`. `colima start --mount-type` does nothing on an
existing VM; to migrate in place (images and volumes survive):

```bash
cp ~/.colima/default/colima.yaml ~/colima.yaml.bak
colima stop
sed -i '' 's/^mountType: sshfs$/mountType: virtiofs/'         ~/.colima/default/colima.yaml
sed -i '' 's/^mountType: sshfs$/mountType: virtiofs/'         ~/.colima/_lima/colima/colima.yaml
sed -i '' 's/^mountType: reverse-sshfs$/mountType: virtiofs/' ~/.colima/_lima/colima/lima.yaml
dev vm start
```

## Disk management

A full VM disk kills the Docker daemon while `colima status` stays healthy;
`post-create.sh` warns above 80%. Images are 5-6 GB, each rebuild leaves the old one
dangling, and Docker-in-Docker keeps a `dind-var-lib-docker-*` volume that
`docker system df` does not count.

```bash
colima ssh -- df -h /       # the number that matters
docker image prune -a       # safe, biggest win
docker system prune -a      # inside a dind container, for its store
```

Never run `docker system prune --volumes` or `docker volume prune`: they delete Claude
Code state, sign-ins, caches and dind stores. To retire a project, `docker rm` its
container and `docker volume rm <slug>-claude-config <slug>-persist` (and its dind
volume, if any). `<slug>-persist` holds the project's local secrets and clones: copy out
what you still need first.

### When the disk is full

```bash
colima ssh -- sudo du -sh /var/lib/docker /var/lib/containerd   # then free space
colima ssh -- sudo systemctl reset-failed containerd docker
colima ssh -- sudo systemctl start containerd docker
colima stop && dev vm start                                     # restores the host socket
```

### Leftover snapshot refs

Template versions before 2.0.0 left inert git snapshots under `refs/snapshots/`. To
drop them in a repo:

```bash
git for-each-ref --format='%(refname)' refs/snapshots/ | while read -r ref; do git update-ref -d "$ref"; done
```

## Pin audit

`scripts/update-pins.sh` brings the pins below up to date every day
([Daily pin update](#daily-pin-update)); Dependabot covers GitHub Actions in this
repo's own workflows and the Dockerfile `FROM` digest. `bash scripts/update-pins.sh
--check` shows what is behind today without editing anything. Files are under
`{{cookiecutter.project_slug}}/` unless marked (repo):

| Pin | File | Updated to |
|---|---|---|
| `uv==`, `pre-commit==`, Starship, `BICEP_VERSION`, Claude Code fallback | `.devcontainer/Dockerfile` | PyPI latest; latest release of starship/starship, Azure/bicep; `npm view @anthropic-ai/claude-code version` |
| `@github/copilot@`, `@playwright/cli@`, zsh plugin tags | `.devcontainer/post-create.sh` | npm latest; newest release tag (`git ls-remote --tags`) |
| Skill `ref`s | `.devcontainer/config/claude/skills.json` | Head commit of each skill repo's default branch; the PR links the compare view |
| Hook `rev:`s | `.pre-commit-config.yaml`, and the repo's own (repo) | `pre-commit autoupdate` on a rendered copy, copied back by repo URL |
| Dev tool floors (`ruff>=`, ...) | `pyproject.toml` | PyPI latest |
| Action SHAs (version comments), `pre-commit@`, `commitizen==` | `.github/workflows/ci.yml` | Newest release in the pinned major, as a commit SHA; PyPI latest |
| Trivy tag and digest | `scripts/hooks/trivy.sh` | Latest aquasecurity/trivy release; the `aquasec/trivy` image digest on Docker Hub |

The script never moves a pin backwards: an upstream "latest" older than the pin (a
pulled release, or `pre-commit autoupdate` describing a branch the newest tag is not
on) is reported and left alone. Claude Code plugins in the roster are not pinned: they
install from their marketplaces' HEAD, so there is nothing to bump.

Left to a human. The daily PR lists newer majors and this repo's own workflow pins, and
applies none of them:

| Pin | File | How |
|---|---|---|
| `autoMode` (Claude Code's default auto-mode rules plus the bundle's own) | `.devcontainer/config/claude/settings.json` | When the Claude Code pin moves, refresh by hand with `claude auto-mode defaults` and `scripts/auto-mode/build.jq` (usage in its header), then append the new block's hash to `auto-mode-shipped.sha256` so containers with the old block take it |
| Python and Node versions offered | `cookiecutter.json` | A major is a choice; add or drop one deliberately |
| Feature major tags | `.devcontainer/devcontainer.json` | `devcontainer features info tags <feature>` |
| A new major of a CI action | `.github/workflows/ci.yml` | Read its changelog, then bump the SHA and comment |
| `commitizen==`, the `rhysd/actionlint` image (repo) | `.github/workflows/ci.yml` | The workflow token may not push workflow files; `bash scripts/update-pins.sh` applies them locally (PyPI latest; latest release, once its image is published) |

Only Python `3.14` has a digest; other versions render a tag-only `FROM`.

## Daily pin update

`.github/workflows/update-pins.yml` runs daily at 05:23 UTC, and on demand with
`gh workflow run update-pins.yml`:

1. It skips, with a notice, while an earlier `deps/daily-*` PR is open: that PR is
   waiting for a human.
2. It runs `scripts/update-pins.sh --bump-minor --no-repo-workflows` with a read-only
   token. If nothing moved, the run ends there. Otherwise `VERSION` gets the next
   minor, and both test scripts and `pre-commit run --all-files` run against the
   result.
3. It commits on `deps/daily-<date>` as kokko-ng (`build(deps): daily pin update;
   release X.Y.0`), opens a PR whose body is the old -> new summary, and dispatches CI
   on the branch: pushes and PRs made with the workflow token start no CI themselves.
4. On green CI it merges the branch into main with a merge commit, deletes the branch
   and dispatches `release.yml` for `vX.Y.0`. The merge itself starts no CI on main;
   the branch's run is the check.

A failure shows up as a failed run of the workflow (GitHub emails whoever last changed
its schedule), and once the PR exists, as a comment on it. A PR whose CI failed stays
open and stops later runs until someone fixes it on its branch and merges it, or
closes it and deletes the branch. A pin whose lookup fails does not fail the run: the
PR body lists it under "Skipped" and the pin stays as it was.

By hand, `bash scripts/update-pins.sh --check` reports without editing; without
`--check` it edits the working tree (this repo's workflow files included, unless
`--no-repo-workflows`), and `--bump-minor` also bumps `VERSION`. It needs `gh`
(signed in), `jq`, `npm`, `curl`, `git`, `python3`, and `pre-commit` and `cookiecutter`
on PATH or through `uvx`.

The workflow needs the repository setting "Allow GitHub Actions to create and approve
pull requests" (Settings -> Actions -> General); without it the PR cannot be opened.
