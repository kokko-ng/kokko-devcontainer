# Managing kokko-devcontainer

Operations, troubleshooting and maintainer notes. Start with the [README](README.md).

## How it fits together

| Piece | Runs on | Role |
|---|---|---|
| `bin/dev` | Mac | Sizes and starts Colima, runs `devcontainer up` with the memory cap and the Mac's Claude Code version, fills the shared sign-in volumes, syncs Claude Code version/theme/onboarding, opens a shell, Claude Code or VS Code |
| `cookiecutter.json`, `hooks/` | Mac | Prompts; `pre_gen_project.py` rejects bad answers, `post_gen_project.py` edits the bundled `settings.json` (roster, attribution) |
| `.devcontainer/init-host-*.sh` | Mac (`initializeCommand`) | Copy host CA certs, warn about cloud-synced folders, record the Mac's git identity |
| `Dockerfile` | Build | Base image, tools, Claude Code, the policy and the firewall script |
| `post-create.sh` | Container | Full provisioning on create; `--config-only` on every start (settings merge, policy, hook, plugins, git, zsh), then firewall and sudo lock |

Options reach `post-create.sh` as `DEVCONTAINER_*` variables in `containerEnv`, not as
Jinja. Repo layout and rules for changing it: [CLAUDE.md](CLAUDE.md).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `docker` cannot connect, `colima status` looks fine | VM disk full. Check `colima ssh -- df -h /`; see [When the disk is full](#when-the-disk-is-full) |
| Container very slow, `dce` or exec sessions die | VM on `sshfs`. See [Mount type](#mount-type) |
| Files like `name 2.ext` keep appearing | Project is in a cloud-synced folder. Move it to `~/code` (or rename the iCloud parent to `*.nosync`). `sweep-phantoms.sh` removes untracked copies on each start; `init-host-guard.sh` warns at build |
| Mac swapping | VM too large. `dev vm`, then `dev vm resize` |
| "connection refused" from a host | The firewall. Add the host to `.devcontainer/firewall/allowed-domains.txt`, `dev rebuild`. `sudo devcontainer-firewall` re-resolves addresses when a CDN rotates them |
| Orange renders as red | Old container without `COLORTERM=truecolor`. `dev rebuild` |

## Port conflicts

Two containers cannot forward the same host port. Give each project its own
`backend_port`/`frontend_port`, or edit `forwardPorts` in `devcontainer.json` and
rebuild. `"onAutoForward": "ignore"` in `portsAttributes` stops VS Code auto-forwarding.

## Mount type

Use `virtiofs`; `sshfs` is about 940x slower on small-file writes. Check with
`colima ssh -- mount | grep /Users`. The mount type is fixed when the VM is created, and
`colima start --mount-type virtiofs` silently does nothing on an existing VM. To migrate
in place (images and volumes survive):

```bash
cp ~/.colima/default/colima.yaml ~/colima.yaml.bak
colima stop
sed -i '' 's/^mountType: sshfs$/mountType: virtiofs/'         ~/.colima/default/colima.yaml
sed -i '' 's/^mountType: sshfs$/mountType: virtiofs/'         ~/.colima/_lima/colima/colima.yaml
sed -i '' 's/^mountType: reverse-sshfs$/mountType: virtiofs/' ~/.colima/_lima/colima/lima.yaml
dev vm start
colima ssh -- mount | grep /Users    # expect: type virtiofs
```

## Disk management

A full VM disk is the most likely failure, and it is hard to spot: the Docker daemon
dies while `colima status` stays healthy. `post-create.sh` warns above 80%.

What fills it: each image is 5-6 GB, every rebuild leaves the old image dangling, and
Docker-in-Docker keeps a `dind-var-lib-docker-*` volume that `docker system df` does not
count and host prunes do not reach.

```bash
colima ssh -- df -h /                          # the number that matters
docker system df                               # excludes dind volumes
docker system df -v | grep dind-var-lib-docker
docker image prune -a                          # safe, biggest win
docker system prune -a                         # inside a dind container, for its store
```

### Do not use `--volumes`

Never `docker system prune --volumes` or `docker volume prune`. They delete the Claude
Code state (`<slug>-claude-config`), the sign-ins (`*-gh-config`, `*-claude-auth`,
`*-azure-config`), caches, `pw-browsers`, the VS Code server and dind stores. Remove
volumes by name.

### Retiring a project

```bash
docker rm <container>
docker volume rm <slug>-claude-config            # plus dind-var-lib-docker-<hash> if any
docker volume ls | grep <slug>                   # per-project caches, if that scope was used
```

A dind volume with `LINKS 1` in `docker system df -v` still belongs to a container,
even a stopped one.

### When the disk is full

```bash
colima ssh -- df -h /
colima ssh -- sudo du -sh /var/lib/docker /var/lib/containerd   # then free space
colima ssh -- sudo systemctl reset-failed containerd docker
colima ssh -- sudo systemctl start containerd docker
colima stop && dev vm start                                     # restores the host socket
```

On a VM older than the containerd snapshotter, `/var/lib/docker/overlay2` can hold tens
of GB nothing tracks. If `/etc/docker/daemon.json` has `"containerd-snapshotter": true`
and nothing in `overlay2` changed since, `colima ssh -- sudo rm -rf /var/lib/docker/overlay2`
(only that folder), then restart the services as above.

### Leftover snapshot refs

Template versions before 2.0.0 stored git snapshots under `refs/snapshots/`. They are
inert. To drop them in a repo:

```bash
git for-each-ref --format='%(refname)' refs/snapshots/ | while read -r ref; do git update-ref -d "$ref"; done
git -c gc.reflogExpire=90.days -c gc.pruneExpire=2.weeks gc   # optional; also expires reflog recovery
```

## Pin audit

Dependabot covers GitHub Actions and the Dockerfile `FROM` digest only. Check the rest
by hand, quarterly (paths under `{{cookiecutter.project_slug}}/.devcontainer/`):

| Pin | File | Latest |
|---|---|---|
| `uv==`, `pre-commit==` | `Dockerfile` | `curl -s https://pypi.org/pypi/<name>/json \| jq -r .info.version` |
| Claude Code fallback (`CLAUDE_CODE_VERSION:-x.y.z`) | `Dockerfile` | `npm view @anthropic-ai/claude-code version`. Used only when built without `dev` |
| Starship `v<version>` | `Dockerfile` | `gh release view -R starship/starship --json tagName -q .tagName` |
| `@github/copilot@`, `@playwright/cli@` | `post-create.sh` | `npm view <package> version` |
| zsh plugin tags | `post-create.sh` | `git ls-remote --tags https://github.com/zsh-users/<plugin>` |
| Node feature `version`, feature major tags | `devcontainer.json` | Node release schedule; `devcontainer features info tags <feature>` |
| Hook `rev:`s | `{{cookiecutter.project_slug}}/.pre-commit-config.yaml` | `pre-commit autoupdate` in a rendered project, then copy the revs back |
| Dev tool floors (`ruff>=`, `mypy>=`, ...) | `{{cookiecutter.project_slug}}/pyproject.toml` | PyPI, as for `uv==` |
| Action SHAs, `pre-commit@`, `commitizen==` | `{{cookiecutter.project_slug}}/.github/workflows/ci.yml` | `gh api repos/<owner>/<action>/releases/latest`; Dependabot does not see the template's workflow |
| Trivy image tag and digest | `{{cookiecutter.project_slug}}/scripts/hooks/trivy.sh` | `gh release view -R aquasecurity/trivy`; resolve the digest of the new tag |

Feature major tags (`node:2`, `azure-cli:1`) float within the major on purpose. Only
Python `3.14` has a digest; other versions render a tag-only `FROM`.

## Releases

1. Bump `VERSION` in the PR that warrants it.
2. Merge to `main`. When CI passes, `release.yml` creates the `v<VERSION>` tag and GitHub
   release (skipped if the tag exists). Never run `gh release create` by hand.

Projects pin with `cookiecutter ... --checkout v<VERSION>` or
`/devcontainer-update --ref v<VERSION>`.
