# Usage

The command list is in the [README](../README.md#commands). This page covers what each
command does beyond its one line.

## PROJECT

`PROJECT` is a path, or a folder name under `DEV_HOME` (default `~/code`; set it in
`~/.zshrc.local` to move it). Left out, it is the nearest folder from the current
directory upward that has `.devcontainer/devcontainer.json`. So in `~/code/demo/ui`,
`dev claude` is `dev claude demo`.

## Starting a container

Every command that opens a container starts the Colima VM first if it is stopped (see
[resources.md](resources.md)), then runs `devcontainer up` when the container is not
running. A first build takes a few minutes. `dev` shows one status line with the elapsed
time and the current step (image build step, then setup phase); the full log is
`$TMPDIR/dev-<project>.log`, and on failure `dev` prints its last 25 lines.

Then, before opening anything, `dev`:

- Fills missing sign-ins from the Mac ([setup.md](setup.md#sign-ins)).
- Updates the container's Claude Code to the Mac's version if it is older. A new image is
  built with the Mac's version (`DEVCONTAINER_CLAUDE_VERSION` -> build arg
  `CLAUDE_CODE_VERSION`); the Dockerfile pin is the fallback.
- Sets the Mac's Claude Code theme and marks onboarding done with the Mac's account
  profile, so `dev claude` opens signed in, with no theme picker and no `/login`.
- Passes `KOKKO_SOUND_EVENTS` from the Mac's Claude Code settings.

## Commands

| Command | Details |
|---|---|
| `dev [PROJECT] [-- CMD...]` | Opens `zsh -l` (or `CMD`) with `devcontainer exec` in this terminal |
| `dev claude` | Runs `claude --permission-mode auto`; takes `-t` / `-w` too |
| `dev -t` / `dev -w` | Opens the shell in a new Ghostty tab of the front window (a window if none is open) / a new window |
| `dev code` | Attaches VS Code to the container `dev` started, instead of letting "Reopen in Container" build its own |
| `dev up` | Starts the container and fills sign-ins; opens nothing |
| `dev rebuild` | `devcontainer up --remove-existing-container`, then a shell. Volumes, and so sign-ins and Claude Code history, are kept |
| `dev stop` | Stops the container, then Colima when no container is left; `--keep-vm` leaves Colima running |
| `dev root` | `bash -l` as root in `/workspaces/<project>`; the container user has no sudo |
| `dev guide` | Also `dev help`, `-h`, `--help`. Shows the VM size, the Claude token state and your shell aliases for each command |

## `dev new`

`dev new NAME [key=value...]` lowercases the name and turns spaces and underscores into
dashes. `key=value` pairs are [template options](template.md#options). It then runs
`git init -b main` and commits the scaffold.

- An empty folder of that name is reused.
- A project an interrupted `dev new` already generated is opened instead of refused.
- The template is `gh:kokko-ng/kokko-devcontainer` (`main`). Set `DEV_TEMPLATE` to use
  another source, such as your clone.

## `dev theme`

`dev theme` sets Claude Code's theme in every running devcontainer. With no argument it
applies the Mac's theme; `light` and `dark` mean the `-ansi` themes; any other theme name
is passed through. mac-setup's `tt` calls it. The `theme-sync@kokko-claude-mods` plugin
in the container applies the change to open sessions.
