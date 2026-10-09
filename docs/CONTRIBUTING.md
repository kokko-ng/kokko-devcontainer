# Contributing

This repo is a cookiecutter template: a generated project receives what is under
`{{cookiecutter.project_slug}}/`. Render it to work in one:
`cookiecutter . --no-input -o .rendered`. The rules for changing it (where Jinja is
allowed, the permission model, the layout) are in [CLAUDE.md](../CLAUDE.md).

## Setup

```bash
pip install pre-commit cookiecutter
pre-commit install
```

Pre-commit runs whitespace fixers, `check-json`, shellcheck at `--severity=info` (as CI
does) and commitizen: commit messages follow Conventional Commits.

## Tests

```bash
bash tests/merge-settings-tests.sh   # bash + jq
bash tests/template-tests.sh         # bash + jq + python3 + cookiecutter
```

- A change to the settings pipeline (`*.jq`, the bundled `settings.json` and
  `managed-settings.json`, the SessionStart hook, the settings code in `post-create.sh`)
  gets a test in `merge-settings-tests.sh` in the same commit.
- A new or changed prompt gets an assertion in `template-tests.sh` in the same commit.
  It also runs shellcheck and hadolint on the renders when they are on PATH.

CI also runs actionlint, hadolint, a devcontainer build of the default render, and
gitleaks.

## Releases

Bump `VERSION` in the PR. After merge to `main`, once CI passes, `release.yml` creates
the `v<VERSION>` tag and GitHub release. Never run `gh release create` by hand.
