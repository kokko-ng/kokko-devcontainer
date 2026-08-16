# Contributing

## Layout

This repo is a cookiecutter template. Everything a generated project receives lives under
`{{cookiecutter.project_slug}}/`; `cookiecutter.json` holds the prompts and `hooks/` holds
the validation and post-generation steps. There is no `.devcontainer/` at the repo root —
to work inside one, render the template and open the result:

```bash
cookiecutter . --no-input -o .rendered
code .rendered/my-project
```

Only `devcontainer.json`, the `Dockerfile`, and the Markdown carry Jinja. `post-create.sh`,
`init-host-certs.sh`, the `.jq` files, the bundled `settings.json`, and the zsh config are
deliberately Jinja-free so they stay lintable and testable without a render. Options those
files need arrive at run time as `DEVCONTAINER_*` variables in `containerEnv`. Keep it that
way — see [CLAUDE.md](CLAUDE.md).

## Setup

```bash
pip install pre-commit cookiecutter
pre-commit install
```

Pre-commit runs trailing-whitespace/EOF fixers, `check-json` (`devcontainer.json` is JSONC
and templated, so it is excluded), and shellcheck at `--severity=info` — the same severity
CI uses, so a passing local commit does not fail in CI.

## Tests

```bash
bash tests/merge-settings-tests.sh   # needs bash + jq
bash tests/template-tests.sh         # needs bash + jq + python3 + cookiecutter
```

`merge-settings-tests.sh` covers `merge-settings.jq`, `prune-roster.jq`, and the settings
handling in `post-create.sh`. Every change to those comes with tests in the same commit.

`template-tests.sh` renders several answer sets and asserts the generated tree: features
added and dropped, ports and paths threaded through, the plugin roster emptied on request,
no unrendered Jinja left behind, and invalid answers rejected by `pre_gen_project.py`.
**Every new or changed prompt in `cookiecutter.json` gets an assertion here in the same
commit** — an option nothing renders against is an option that silently stops working.

CI additionally runs shellcheck, actionlint, hadolint against both rendered Dockerfile
variants, a full devcontainer build smoke test on the rendered default project, and
gitleaks.

## Releases

The version lives in the `VERSION` file at the repo root. The flow:

1. Bump `VERSION` (e.g. `3.0.0` → `3.1.0`) in the PR that warrants it.
2. Merge to `main`. When CI succeeds there, `.github/workflows/release.yml` creates the
   `v<VERSION>` tag and GitHub release automatically (it skips silently if the tag
   already exists).

No one runs `gh release create` by hand. Downstream projects can then pin with
`cookiecutter gh:kokko-ng/kokko-devcontainer --checkout v<VERSION>` or
`/devcontainer-update --ref v<VERSION>`.
