# Usage

`dev guide` lists every command with this Mac's VM size and sign-in state. This page
covers what it does not.

## PROJECT

A path, or a folder name under `DEV_HOME` (default `~/code`). Left out, it is the nearest
folder upward with `.devcontainer/devcontainer.json`: in `~/code/demo/ui`, `dev claude`
is `dev claude demo`.

## Opening a container

A first build takes a few minutes; `dev` shows the current step, and the full log is
`$TMPDIR/dev-<project>.log`. Before opening a shell, Claude Code or VS Code, `dev`:

- fills missing sign-ins from the Mac;
- updates the container's Claude Code to the Mac's version if it is older (a new image
  is built with the Mac's version; the Dockerfile pin is the fallback);
- sets the Mac's Claude Code theme and marks onboarding done, so `dev claude` opens
  signed in with no theme picker.

`dev new` lowercases the name and turns spaces and underscores into dashes. It reuses an
empty folder, and opens a project an interrupted `dev new` already generated. Set
`DEV_TEMPLATE` to generate from another source, such as your clone.

`dev theme` with no argument applies the Mac's theme; `light` and `dark` mean the `-ansi`
themes. Sessions started afterwards use it; one already open keeps the theme it started with.

## Resources

| Setting | Value |
|---|---|
| VM memory | 3 GB on an 8 GB Mac, 6 GB up to 16 GB, else half the RAM minus 4 GB |
| VM CPUs | Half the cores, 2 to 8 |
| VM disk | 60 GB on an 8 GB Mac, else 100 GB; sparse, and never shrunk |
| Container memory | VM minus 1 GB, at least 2 GB; `container_memory_limit` without `dev` |
| At once | Under 16 GB: one devcontainer; starting one stops the others |

An existing VM keeps its size until `dev vm resize`, which stops running containers;
`dev vm` compares the two. `dev` asks before starting the VM when macOS has under 25% of
its memory free. Overrides, per command or in `~/.zshrc.local`: `DEV_VM_CPUS`,
`DEV_VM_MEMORY`, `DEV_VM_DISK` (GB), `DEV_ALLOW_MULTIPLE=1`, `DEV_FORCE=1`.
