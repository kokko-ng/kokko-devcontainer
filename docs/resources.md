# Resources

`dev` sizes the Colima VM from the Mac's RAM and caps each container below it, so a
runaway process is killed inside its container instead of taking the VM down.

| Setting | Value |
|---|---|
| VM memory | 3 GB on an 8 GB Mac, 6 GB up to 16 GB, else half the RAM minus 4 GB |
| VM CPUs | Half the cores, 2 to 8 |
| VM disk | 60 GB on an 8 GB Mac, else 100 GB. Sparse: a ceiling, not an allocation |
| VM mount type | `virtiofs` |
| Container memory | VM minus 1 GB, at least 2 GB; no swap |
| At once | Under 16 GB: one devcontainer, and starting one stops the others. Otherwise as many as fit |

- An existing VM keeps its size until `dev vm resize`, which restarts the VM and so
  stops running containers. `dev` warns when the running VM has more memory than this
  Mac should give it.
- The VM disk never shrinks: Colima cannot shrink one, so a larger existing disk is kept.
- Before starting the VM, `dev` asks when macOS has under 25% of its memory free.
- Started without `dev`, a container gets the `container_memory_limit` answer (default
  `5g`) as its cap.

## `dev vm`

| Command | Does |
|---|---|
| `dev vm` / `dev vm status` | The VM's current memory next to the size `dev` would give it, and free macOS memory |
| `dev vm start` | Start the VM at that size (every container command does this when needed) |
| `dev vm stop` | Stop the VM; its memory goes back to macOS |
| `dev vm resize` | Restart the VM at the size above; asks first if containers are running |

## Overrides

Set these per command or in `~/.zshrc.local`:

| Variable | Effect |
|---|---|
| `DEV_VM_CPUS`, `DEV_VM_MEMORY`, `DEV_VM_DISK` | VM size (memory and disk in GB) |
| `DEV_ALLOW_MULTIPLE=1` | Several devcontainers at once on a Mac under 16 GB |
| `DEV_FORCE=1` | Start the VM even when macOS is short of memory |

For example: `DEV_VM_CPUS=6 DEV_VM_MEMORY=8 DEV_VM_DISK=150 dev vm resize`. A full disk
or a slow mount: [maintenance.md](maintenance.md#troubleshooting).
