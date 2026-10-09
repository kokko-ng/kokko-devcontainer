# Contributing

This repo is a cookiecutter template: what a generated project receives is under
`{{cookiecutter.project_slug}}/`. There is no `.devcontainer/` at the root. To work in
one, render first:

```bash
cookiecutter . --no-input -o .rendered
```

Rules for changing the template (where Jinja is allowed, the permission model, layout)
are in [CLAUDE.md](CLAUDE.md). How the pieces fit, pins and releases are in
[MANAGING.md](MANAGING.md).

## Setup

```bash
pip install pre-commit cookiecutter
pre-commit install
```

Pre-commit runs whitespace/EOF fixers, `check-json` (not on `devcontainer.json`, which is
JSONC and templated) and shellcheck at `--severity=info`, the same as CI.

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

CI also runs actionlint, a devcontainer build of the default render, and gitleaks.

## Releases

Bump `VERSION` in your PR; the release is cut automatically after merge. See
[MANAGING.md](MANAGING.md#releases).
