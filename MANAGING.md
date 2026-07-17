# Managing Multiple Devcontainer Instances

A guide to running and managing multiple instances of this devcontainer across different projects on the same machine.

---

## Table of contents

1. [How instances work](#how-instances-work)
2. [Naming containers](#naming-containers)
3. [Port conflicts](#port-conflicts)
4. [Listing and stopping containers](#listing-and-stopping-containers)
5. [CLI targeting](#cli-targeting)
6. [Colima resource allocation](#colima-resource-allocation)
7. [Disk management](#disk-management)
8. [Cleanup](#cleanup)

---

## How instances work

Each project directory with a `.devcontainer/` folder gets its own isolated container. When you copy this starter into multiple projects, each one runs independently with its own filesystem, installed dependencies, and forwarded ports.

The typical workflow:

```bash
# Copy the devcontainer into each project
cp -r path/to/devcontainer-starter/.devcontainer ~/projects/alpha/
cp -r path/to/devcontainer-starter/.devcontainer ~/projects/beta/
```

Each project's container is identified by its workspace folder path. There is no shared state between instances unless you explicitly mount host directories.

---

## Naming containers

The default `devcontainer.json` sets `"name": "fastapi-vue-dev"`. When running multiple instances, change this per project so containers are easy to distinguish:

```jsonc
// ~/projects/alpha/.devcontainer/devcontainer.json
"name": "alpha-dev"
```

```jsonc
// ~/projects/beta/.devcontainer/devcontainer.json
"name": "beta-dev"
```

The name appears in `docker ps` output and in the VS Code Remote Containers sidebar.

---

## Port conflicts

The default configuration forwards ports `8000` (FastAPI) and `5173` (Vite). Two containers cannot forward the same host port simultaneously.

Options when running multiple instances concurrently:

**Change the forwarded ports** in one project's `devcontainer.json`:

```jsonc
"forwardPorts": [8001, 5174]
```

**Remove auto-forwarding** and forward manually when needed:

```jsonc
"forwardPorts": []
```

Then forward on demand from the VS Code Ports panel or with `docker port`.

**Use `portsAttributes` to avoid collisions** by letting VS Code assign random host ports:

```jsonc
"portsAttributes": {
  "8000": { "label": "Backend", "onAutoForward": "notify" },
  "5173": { "label": "Frontend", "onAutoForward": "notify" }
}
```

---

## Listing and stopping containers

```bash
# List all running containers
docker ps

# List only devcontainers (running and stopped)
docker ps -a --filter label=devcontainer.local_folder

# Stop a specific container by ID or name
docker stop <container-id>

# Stop all running devcontainers
docker ps --filter label=devcontainer.local_folder -q | xargs docker stop
```

---

## CLI targeting

The devcontainer CLI uses `--workspace-folder` to identify which container to operate on. Always provide the full path to the project:

```bash
# Start a specific project's container
devcontainer up --workspace-folder ~/projects/alpha

# Open a shell in a specific project's container
devcontainer exec --workspace-folder ~/projects/alpha zsh

# Rebuild a specific project's container
devcontainer up --workspace-folder ~/projects/alpha --remove-existing-container
```

The bundled aliases (`dcu`, `dce`, `dcur`) use `--workspace-folder .`, so they operate on whichever project directory your terminal is in.

---

## Colima resource allocation

All containers share the Colima VM's CPU, memory, and disk budget.

```bash
colima stop
colima start --cpu 8 --memory 16 --disk 150
```

Note that `--disk 150` is deliberately generous — see [Disk management](#disk-management) for why. The disk is sparse, so it only consumes host space as it actually fills. CPU and memory are cheap to change later; **the disk is not** — Colima can grow a disk but not shrink it, so starting too small is the expensive mistake.

To check CPU and memory usage:

```bash
docker stats --no-stream
```

`colima status` reports whether the VM booted. It does **not** report disk usage, and it will happily print a healthy status while the Docker daemon inside is dead. Do not use it to check disk — see below.

---

## Disk management

**Read this section before you need it.** A full VM disk is the most likely way this setup breaks, and it fails in a way that is genuinely hard to diagnose.

### Why it fills up

This starter is disk-hungry by design:

| Source | Typical size |
|---|---|
| Each project's `vsc-*` devcontainer image | 5-6 GB |
| Each rebuild, leaving the old image as a dangling `<none>` | 5-6 GB again |
| `docker-in-docker` nested image store (`dind-var-lib-docker-*` volume) | grows unbounded |
| Python/Node/Playwright layers | ~1-2 GB |

Three projects and a handful of rebuilds is comfortably 50 GB. Rebuilds are the biggest trap: `dcur` (`--remove-existing-container`) removes the *container* but leaves the old *image* behind, untagged and invisible unless you look for it.

The `docker-in-docker` store is the subtle one: it is a **named volume**, so it survives container removal, `docker system df` does not count it, and `docker image prune` on the host does not touch it. Prune it from **inside** each devcontainer:

```bash
docker system prune -a     # run INSIDE the devcontainer
```

### Check disk usage

```bash
# What the VM's real disk looks like -- the number that actually matters
colima ssh -- df -h /

# What Docker thinks it is using. This does NOT include the docker-in-docker
# nested stores -- see below for those.
docker system df

# How big each devcontainer's nested docker-in-docker store has grown
docker system df -v | grep dind-var-lib-docker
```

The container build prints a warning automatically once the VM disk passes 80%.

### Reclaim space

```bash
# Dangling images from rebuilds -- usually the biggest and safest win
docker image prune

# All images not used by an existing container.
# Anything still needed is rebuilt or re-pulled on next use.
docker image prune -a

# Stopped containers
docker container prune
```

### Do not use `--volumes`

```bash
docker system prune -a --volumes   # DESTRUCTIVE -- avoid
```

`--volumes` deletes named volumes holding local state you probably did not mean to delete:

- `dind-var-lib-docker-*` — a devcontainer's nested Docker image store
- `claude-code-config-*`, `claude-code-bashhistory-*` — Claude Code settings and shell history
- `vscode` — VS Code server and extensions

Losing these does not destroy source code, but it is a silent loss. Prune images, not volumes.

### Retiring a project's dind volume

A `dind-var-lib-docker-*` volume stays tied to its container for as long as that container exists — **even when stopped**. A stopped devcontainer you have not opened in months still owns its volume, so a multi-GB `dind-*` volume is not evidence of anything left over.

Before assuming a volume is garbage, check the `LINKS` column — `0` means nothing references it, `1` means a container still does:

```bash
docker system df -v | grep -E "VOLUME NAME|dind-var-lib-docker"
```

```
VOLUME NAME                          LINKS     SIZE
dind-var-lib-docker-051bsgre...      1         3.897GB    <- in use, leave alone
dind-var-lib-docker-1iqoip1a...      1         470MB      <- in use, leave alone
```

A dind volume is only genuinely reclaimable once its container is gone. To retire a project:

```bash
docker rm <container>                          # remove the container first
docker volume rm dind-var-lib-docker-<hash>    # then its now-unreferenced volume
```

Remove them **by name**. `docker volume prune` takes every unreferenced volume, including the Claude Code and vscode ones above.

Docker will refuse to remove a volume an existing container still references, so a mistake here fails loudly rather than destroying anything — but do not rely on that as the check.

### When the disk is already full

The failure is misleading, so recognise it by these symptoms together:

- `docker` commands fail with `Cannot connect to the Docker daemon` or `failed to connect ... /var/run/docker.sock`
- `docker context ls` shows no `colima` context
- `colima start` says `already running, ignoring`
- `colima status` claims the VM is healthy

What has actually happened: containerd's garbage collector tried to write to a full disk, hit `ENOSPC`, and **panicked on a nil-pointer dereference**; dockerd then failed with `no space left on device`. Because the VM itself booted fine, Colima reports success and skips the provisioning that creates the host socket and Docker context — which is why `docker` on the host silently falls back to Docker Desktop's socket path.

Confirm and recover:

```bash
# Confirm: is it really the disk?
colima ssh -- df -h /
colima ssh -- sudo journalctl -u docker -n 20 --no-pager

# Free space from inside the VM (the daemon is down, so docker CLI cannot help)
colima ssh -- sudo du -sh /var/lib/docker /var/lib/containerd

# Then restart the runtimes. reset-failed is required: systemd gives up after
# repeated crashes, so a plain 'start' will refuse.
colima ssh -- sudo systemctl reset-failed containerd docker
colima ssh -- sudo systemctl start containerd docker

# Full restart, which also recreates the host socket and docker context
colima stop && colima start --cpu 8 --memory 16
```

### The orphaned `overlay2` store

If Colima has been installed since before Docker's containerd snapshotter became the default, `/var/lib/docker/overlay2` may hold tens of gigabytes of unreachable data from the old storage driver. Docker no longer tracks it, so **`docker system prune` can never reclaim it** and it will waste that space indefinitely.

Check whether the snapshotter is on and whether the old store is stale:

```bash
colima ssh -- sudo cat /etc/docker/daemon.json          # look for "containerd-snapshotter": true
colima ssh -- sudo du -sh /var/lib/docker/overlay2      # how much is in there
colima ssh -- sudo ls -lt /var/lib/docker/overlay2 | head   # newest mtime
```

If the snapshotter is enabled and nothing in `overlay2` has been modified since around when you enabled it, it is dead weight and can be removed. Delete only `overlay2` — the sibling `volumes/` directory holds live state:

```bash
colima ssh -- sudo rm -rf /var/lib/docker/overlay2
colima ssh -- sudo systemctl reset-failed containerd docker
colima ssh -- sudo systemctl start containerd docker
```

---

## Cleanup

To remove a single project's container without affecting others:

```bash
docker ps -a --filter label=devcontainer.local_folder=/path/to/project -q | xargs docker rm
```

For reclaiming disk space, see [Disk management](#disk-management) above.
