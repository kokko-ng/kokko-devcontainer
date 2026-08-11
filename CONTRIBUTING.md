# Contributing

## Setup

```bash
pip install pre-commit
pre-commit install
```

Pre-commit runs trailing-whitespace/EOF fixers, `check-json` (devcontainer.json is JSONC
and excluded), and shellcheck at `--severity=info` — the same severity CI uses, so a
passing local commit does not fail in CI.

## Tests

```bash
bash tests/merge-settings-tests.sh
```

Needs bash and jq — nothing else. Every change to `merge-settings.jq`,
`prune-roster.jq`, or the settings-handling parts of `post-create.sh` comes with tests
in the same commit (see [CLAUDE.md](CLAUDE.md)). CI additionally runs shellcheck,
actionlint, hadolint, a full devcontainer build smoke test, and gitleaks.

## Releases

The version lives in the `VERSION` file at the repo root. The flow:

1. Bump `VERSION` (e.g. `1.0.0` → `1.1.0`) in the PR that warrants it.
2. Merge to `main`. When CI succeeds there, `.github/workflows/release.yml` creates the
   `v<VERSION>` tag and GitHub release automatically (it skips silently if the tag
   already exists).

No one runs `gh release create` by hand. Downstream projects can then pin with
`/devcontainer-update --ref v<VERSION>`.
