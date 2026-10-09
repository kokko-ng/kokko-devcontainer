# Contributing

This repo is a cookiecutter template: what a generated project receives is under
`{{cookiecutter.project_slug}}/`. There is no `.devcontainer/` at the root. To work in
one, render first:

```bash
cookiecutter . --no-input -o .rendered
```

The rules for changing the template (where Jinja is allowed, the permission model, the
file layout) are in [CLAUDE.md](../CLAUDE.md).

## How it fits together

| Piece | Runs on | Role |
|---|---|---|
| `bin/dev` | Mac | Sizes and starts Colima, runs `devcontainer up`, fills the shared sign-in volumes, syncs Claude Code, opens a shell, Claude Code or VS Code |
| `cookiecutter.json`, `hooks/` | Mac | Prompts; `pre_gen_project.py` rejects bad answers, `post_gen_project.py` edits the bundled `settings.json` (roster, attribution) |
| `.devcontainer/init-host-*.sh` | Mac (`initializeCommand`) | Copy host CA certs, warn about cloud-synced folders, record the Mac's git identity |
| `Dockerfile` | Build | Base image, tools, Claude Code, the policy and the firewall script |
| `post-create.sh` | Container | Full provisioning on create; `--config-only` on every start |

Options reach `post-create.sh` as `DEVCONTAINER_*` variables in `containerEnv`, not as
Jinja.

## Setup

```bash
pip install pre-commit cookiecutter
pre-commit install
```

Pre-commit runs whitespace and EOF fixers, `check-json` (not on `devcontainer.json`,
which is JSONC and templated), shellcheck at `--severity=info` as CI does, and
commitizen on the commit message: commits follow Conventional Commits.

## Tests

```bash
bash tests/merge-settings-tests.sh   # bash + jq
bash tests/template-tests.sh         # bash + jq + python3 + cookiecutter
```

- `merge-settings-tests.sh` covers the settings pipeline: `merge-settings.jq`,
  `prune-roster.jq`, the bundled `settings.json` and `managed-settings.json`, the
  SessionStart hook and the settings code in `post-create.sh`. Change those with a test
  in the same commit.
- `template-tests.sh` renders several answer sets and asserts the output, including
  rejected answers. Every new or changed prompt gets an assertion in the same commit.
  It also runs shellcheck and hadolint on the output when they are on PATH. CI's
  hadolint version is the one pinned in `hadolint/hadolint-action`:

  ```bash
  curl -sSL -o ~/.local/bin/hadolint \
    https://github.com/hadolint/hadolint/releases/download/v2.15.0/hadolint-Linux-x86_64
  chmod +x ~/.local/bin/hadolint
  ```

CI also checks commit messages, runs actionlint, hadolint on two renders, a
devcontainer build of the default render, and gitleaks.

## Releases

1. Bump `VERSION` in the PR that warrants it.
2. Merge to `main`. When CI passes, `release.yml` creates the `v<VERSION>` tag and GitHub
   release (skipped if the tag exists). Never run `gh release create` by hand.
