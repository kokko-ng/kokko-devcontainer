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

Dependabot covers GitHub Actions and the Dockerfile `FROM` digest only. Check the rest
quarterly (files under `{{cookiecutter.project_slug}}/`):

| Pin | File | Latest |
|---|---|---|
| `uv==`, `pre-commit==`, Starship, Claude Code fallback | `.devcontainer/Dockerfile` | PyPI; `gh release view -R starship/starship`; `npm view @anthropic-ai/claude-code version` |
| `BICEP_VERSION` | `.devcontainer/Dockerfile` | `gh release view -R Azure/bicep` |
| `autoMode.allow` (Claude Code's default allow rules, copied from 2.1.295) | `.devcontainer/config/claude/settings.json` | `claude auto-mode defaults`; refresh when the Claude Code version moves, keeping the last two rules |
| `@github/copilot@`, `@playwright/cli@`, zsh plugin tags | `.devcontainer/post-create.sh` | `npm view <package> version`; `git ls-remote --tags` |
| Node `version`, feature major tags | `.devcontainer/devcontainer.json` | `devcontainer features info tags <feature>` |
| Hook `rev:`s | `.pre-commit-config.yaml` | `pre-commit autoupdate` in a rendered project, then copy back |
| Dev tool floors (`ruff>=`, ...) | `pyproject.toml` | PyPI |
| Action SHAs, `pre-commit@`, `commitizen==` | `.github/workflows/ci.yml` | `gh api repos/<owner>/<action>/releases/latest` |
| Trivy tag and digest | `scripts/hooks/trivy.sh` | `gh release view -R aquasecurity/trivy` |

Only Python `3.14` has a digest; other versions render a tag-only `FROM`.
