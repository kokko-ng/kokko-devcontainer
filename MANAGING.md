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
7. [Cleanup](#cleanup)

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

All containers share the Colima VM's CPU, memory, and disk budget. The default allocation (`--cpu 4 --memory 8 --disk 60`) is sufficient for one or two active containers.

If you run multiple containers concurrently, increase the allocation:

```bash
colima stop
colima start --cpu 6 --memory 12 --disk 80
```

To check current resource usage:

```bash
colima status
docker stats --no-stream
```

---

## Cleanup

Stopped containers and unused images accumulate over time. Reclaim disk space periodically:

```bash
# Remove all stopped containers
docker container prune

# Remove dangling images (untagged layers)
docker image prune

# Remove all unused images, not just dangling ones
docker image prune -a

# Nuclear option: remove everything (containers, images, volumes, networks)
docker system prune -a --volumes
```

To remove a single project's container without affecting others:

```bash
docker ps -a --filter label=devcontainer.local_folder=/path/to/project -q | xargs docker rm
```
