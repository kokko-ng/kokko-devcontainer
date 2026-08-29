#!/usr/bin/env bash
# Renders the cookiecutter template with several answer sets and asserts what
# came out. This is the test that keeps the template honest: every option in
# cookiecutter.json changes the generated tree, and nothing but a real render
# proves that the Jinja in devcontainer.json and the Dockerfile still produces
# a parseable devcontainer and a lintable Dockerfile.
#
# Needs bash, jq, python3 and cookiecutter (pip install cookiecutter). The
# generated scripts and Dockerfiles are additionally linted when a shellcheck
# or hadolint binary is on PATH. Run: bash tests/template-tests.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_PAYLOAD="$ROOT/{{cookiecutter.project_slug}}"

PASS=0
FAIL=0
FAILED_CASES=()

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); FAILED_CASES+=("$1"); }

# assert <desc> <cmd...> — the command's exit status is the assertion.
assert() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok; else bad "$desc"; fi
}

# refute <desc> <cmd...> — passes when the command FAILS.
refute() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then bad "$desc"; else ok; fi
}

# assert_jq <desc> <json-file> <jq-expr>
assert_jq() {
    local desc="$1" file="$2" expr="$3"
    if jq -e "$expr" "$file" >/dev/null 2>&1; then ok; else bad "$desc"; fi
}

for tool in jq python3 cookiecutter; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "$tool is required (pip install cookiecutter)" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# JSONC -> JSON. devcontainer.json is JSONC (the spec allows comments), so it
# cannot be fed to jq directly. Strip comments with a string-aware scanner —
# a naive regex would eat the "//" inside every URL in the file. Trailing
# commas are deliberately NOT tolerated: the spec allows them, but they would
# be a template bug here, so let the parse fail loudly.
# ---------------------------------------------------------------------------
jsonc_to_json() {
    python3 - "$1" <<'PY'
import json
import sys

src = open(sys.argv[1], encoding="utf-8").read()
out = []
i, n, in_string = 0, len(src), False
while i < n:
    c = src[i]
    if in_string:
        out.append(c)
        if c == "\\" and i + 1 < n:
            out.append(src[i + 1])
            i += 2
            continue
        if c == '"':
            in_string = False
        i += 1
        continue
    if c == '"':
        in_string = True
        out.append(c)
        i += 1
        continue
    if c == "/" and i + 1 < n and src[i + 1] == "/":
        while i < n and src[i] != "\n":
            i += 1
        continue
    if c == "/" and i + 1 < n and src[i + 1] == "*":
        i += 2
        while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
            i += 1
        i += 2
        continue
    out.append(c)
    i += 1

json.dump(json.loads("".join(out)), sys.stdout)
PY
}

render() { # render <outdir> [key=value ...]
    local out="$1"; shift
    cookiecutter "$ROOT" --no-input -o "$out" "$@" >/dev/null 2>"$out.err"
}

# ===========================================================================
# 1. The template itself
# ===========================================================================
assert_jq "cookiecutter.json is valid JSON" "$ROOT/cookiecutter.json" '.'
assert_jq "template prompts for a project_slug" "$ROOT/cookiecutter.json" \
    'has("project_slug")'
assert_jq "settings.json is excluded from rendering" "$ROOT/cookiecutter.json" \
    '._copy_without_render | index(".devcontainer/config/claude/settings.json") != null'
assert_jq "template prompts for a git identity" "$ROOT/cookiecutter.json" \
    'has("git_user_name") and has("git_user_email")'
assert "template payload directory exists" test -d "$TEMPLATE_PAYLOAD"

# ===========================================================================
# 2. Default answers — the FastAPI + Vue setup this repo has always shipped
# ===========================================================================
render "$WORK/default"
DEFAULT="$WORK/default/my-project"
assert "default answers render" test -d "$DEFAULT/.devcontainer"

DC="$WORK/default-devcontainer.json"
if jsonc_to_json "$DEFAULT/.devcontainer/devcontainer.json" > "$DC" 2>/dev/null; then
    ok
else
    bad "generated devcontainer.json parses as JSONC"
fi

assert_jq "container name comes from the slug" "$DC" '.name == "my-project-dev"'
assert_jq "default ports are forwarded" "$DC" '.forwardPorts == [8000, 5173]'
# shellcheck disable=SC2016  # ${containerWorkspaceFolder} is devcontainer syntax, not shell
assert_jq "PYTHONPATH points at the backend source dir" "$DC" \
    '.containerEnv.PYTHONPATH == "${containerWorkspaceFolder}/src"'
assert_jq "frontend dir is published to post-create" "$DC" \
    '.containerEnv.DEVCONTAINER_FRONTEND_DIR == "ui"'
assert_jq "the git identity is published to post-create" "$DC" \
    '.containerEnv.DEVCONTAINER_GIT_USER_NAME == "kokko-ng"
       and .containerEnv.DEVCONTAINER_GIT_USER_EMAIL == "Kokko.Ng@insight.com"'
assert_jq "azure-cli feature is present by default" "$DC" \
    '.features | has("ghcr.io/devcontainers/features/azure-cli:1")'
assert_jq "docker-in-docker feature is present by default" "$DC" \
    '.features | has("ghcr.io/devcontainers/features/docker-in-docker:4")'
assert_jq "node feature is pinned to the chosen version" "$DC" \
    '.features["ghcr.io/devcontainers/features/node:2"].version == "22"'
assert_jq "playwright browser volume keeps its historical shared name" "$DC" \
    '[.mounts[] | select(test("ms-playwright"))] | any(test("source=pw-browsers,"))'
assert_jq "shared caches keep their historical volume names" "$DC" \
    '[.mounts[] | select(test("source=devcontainer-uv-cache,"))] | length == 1'

assert_jq "bundled settings.json stays valid JSON" \
    "$DEFAULT/.devcontainer/config/claude/settings.json" '.'
assert_jq "default roster ships the kokko-ng plugins" \
    "$DEFAULT/.devcontainer/config/claude/settings.json" \
    '.enabledPlugins | length > 0 and (keys | any(test("@kokko-ng-")))'
assert_jq "default roster registers the kokko-ng marketplaces" \
    "$DEFAULT/.devcontainer/config/claude/settings.json" \
    '.extraKnownMarketplaces | length > 0'

assert "default Dockerfile installs the ODBC driver" \
    grep -q msodbcsql18 "$DEFAULT/.devcontainer/Dockerfile"
assert "default Dockerfile pins the base image by digest" \
    grep -qE '^FROM .*python:3\.14-bookworm@sha256:' "$DEFAULT/.devcontainer/Dockerfile"
assert "certs/.gitkeep survives so plain docker build works" \
    test -f "$DEFAULT/.devcontainer/certs/.gitkeep"
assert "extracted host certs are gitignored inside .devcontainer" \
    grep -qx 'certs/\*' "$DEFAULT/.devcontainer/.gitignore"

# Files listed in _copy_without_render must come through byte-identical —
# a stray Jinja delimiter in jq or zsh config would otherwise be swallowed.
for f in config/claude/merge-settings.jq config/claude/prune-roster.jq config/zsh/.zshrc; do
    assert "$f is copied verbatim" \
        cmp -s "$TEMPLATE_PAYLOAD/.devcontainer/$f" "$DEFAULT/.devcontainer/$f"
done

# ===========================================================================
# 3. Everything optional turned off
# ===========================================================================
render "$WORK/slim" \
    project_name="Slim App" python_version=3.13 node_version=24 \
    backend_src_dir=backend frontend_dir=web \
    backend_port=8080 frontend_port=3000 \
    include_azure_cli=no include_azure_sql_driver=no include_docker_in_docker=no \
    include_copilot_cli=no include_playwright=no \
    claude_plugin_roster=none cache_volume_scope=per-project \
    git_user_name= git_user_email=
SLIM="$WORK/slim/slim-app"
assert "slim answers render" test -d "$SLIM/.devcontainer"

SDC="$WORK/slim-devcontainer.json"
if jsonc_to_json "$SLIM/.devcontainer/devcontainer.json" > "$SDC" 2>/dev/null; then
    ok
else
    bad "slim devcontainer.json parses as JSONC"
fi

assert_jq "azure-cli feature is dropped" "$SDC" \
    '.features | has("ghcr.io/devcontainers/features/azure-cli:1") | not'
assert_jq "docker-in-docker feature is dropped" "$SDC" \
    '.features | has("ghcr.io/devcontainers/features/docker-in-docker:4") | not'
assert_jq "github-cli and common-utils are always kept" "$SDC" \
    '.features | has("ghcr.io/devcontainers/features/github-cli:1")
       and has("ghcr.io/devcontainers/features/common-utils:2")'
assert_jq "chosen ports are forwarded" "$SDC" '.forwardPorts == [8080, 3000]'
# Blank has to survive as blank. Rendering the default here would set a
# stranger's name and address as the author of every commit in the project.
assert_jq "a blank git identity stays blank" "$SDC" \
    '.containerEnv.DEVCONTAINER_GIT_USER_NAME == ""
       and .containerEnv.DEVCONTAINER_GIT_USER_EMAIL == ""'
# shellcheck disable=SC2016  # ${containerWorkspaceFolder} is devcontainer syntax, not shell
assert_jq "chosen backend source dir reaches PYTHONPATH" "$SDC" \
    '.containerEnv.PYTHONPATH == "${containerWorkspaceFolder}/backend"'
assert_jq "chosen frontend dir reaches post-create" "$SDC" \
    '.containerEnv.DEVCONTAINER_FRONTEND_DIR == "web"'
assert_jq "copilot install is toggled off" "$SDC" \
    '.containerEnv.DEVCONTAINER_INSTALL_COPILOT_CLI == "0"'
assert_jq "playwright install is toggled off" "$SDC" \
    '.containerEnv.DEVCONTAINER_INSTALL_PLAYWRIGHT == "0"'
assert_jq "no playwright env without playwright" "$SDC" \
    '.containerEnv | has("PLAYWRIGHT_BROWSERS_PATH") | not'
assert_jq "no browser volume without playwright" "$SDC" \
    '[.mounts[] | select(test("ms-playwright"))] | length == 0'
assert_jq "per-project caches are namespaced by slug" "$SDC" \
    '[.mounts[] | select(test("source=slim-app-uv-cache,"))] | length == 1'
assert_jq "no docker extension without docker-in-docker" "$SDC" \
    '.customizations.vscode.extensions | index("ms-azuretools.vscode-docker") == null'

assert_jq "empty roster is still valid JSON" \
    "$SLIM/.devcontainer/config/claude/settings.json" '.'
assert_jq "roster is emptied on request" \
    "$SLIM/.devcontainer/config/claude/settings.json" \
    '(.enabledPlugins | length == 0) and (.extraKnownMarketplaces | length == 0)'
assert_jq "emptying the roster keeps the other settings" \
    "$SLIM/.devcontainer/config/claude/settings.json" \
    '.permissions.defaultMode == "auto"'

refute "slim Dockerfile drops the ODBC driver" \
    grep -q msodbcsql18 "$SLIM/.devcontainer/Dockerfile"
assert "slim Dockerfile still installs jq" \
    grep -q 'install -y --no-install-recommends jq' "$SLIM/.devcontainer/Dockerfile"
assert "non-default python version reaches FROM" \
    grep -qE '^FROM .*python:3\.13-bookworm$' "$SLIM/.devcontainer/Dockerfile"

# ===========================================================================
# 4. Nothing anywhere is left unrendered
# ===========================================================================
# A forgotten `{{` or `{%` in a generated file means an option silently did
# nothing. Only real Jinja delimiters count — `${...}` variable syntax and
# bash's `${#array[@]}` are fine.
unrendered=$(grep -rlE '\{\{|\{%' "$DEFAULT" "$SLIM" 2>/dev/null || true)
if [[ -z "$unrendered" ]]; then
    ok
else
    bad "no unrendered Jinja delimiters remain (found in: $unrendered)"
fi

# ===========================================================================
# 5. Generated shell scripts stay lint-clean
# ===========================================================================
if command -v shellcheck >/dev/null 2>&1; then
    for project in "$DEFAULT" "$SLIM"; do
        assert "shellcheck passes on $(basename "$project")'s scripts" \
            shellcheck --severity=info \
                "$project/.devcontainer/post-create.sh" \
                "$project/.devcontainer/init-host-certs.sh"
    done
else
    echo "note: shellcheck not installed — skipping the generated-script lint"
fi

# ===========================================================================
# 6. Generated Dockerfiles stay lint-clean
# ===========================================================================
# Both apt layers the template can emit. --failure-threshold info matches the
# default hadolint-action uses in CI, so a finding that fails there fails here
# too — otherwise a hadolint version bump lands as a red main instead of a red
# local run.
if command -v hadolint >/dev/null 2>&1; then
    for project in "$DEFAULT" "$SLIM"; do
        assert "hadolint passes on $(basename "$project")'s Dockerfile" \
            hadolint --failure-threshold info "$project/.devcontainer/Dockerfile"
    done
else
    echo "note: hadolint not installed — skipping the generated-Dockerfile lint"
fi

# ===========================================================================
# 7. Bad answers are rejected before anything is written
# ===========================================================================
reject() { # reject <desc> <key=value ...>
    local desc="$1"; shift
    local out="$WORK/reject-$RANDOM"
    if cookiecutter "$ROOT" --no-input -o "$out" "$@" >/dev/null 2>&1; then
        bad "$desc"
    else
        ok
    fi
}

reject "an uppercase project_slug is rejected" project_slug=MyProject
reject "a project_slug with spaces is rejected" project_slug="my project"
reject "an absolute backend_src_dir is rejected" backend_src_dir=/etc
reject "a backend_src_dir escaping the workspace is rejected" backend_src_dir=../elsewhere
reject "a non-numeric port is rejected" backend_port=eighty
reject "a privileged port is rejected" backend_port=80
reject "duplicate ports are rejected" backend_port=8000 frontend_port=8000
reject "a git_user_email that is not an address is rejected" \
    git_user_email=not-an-address
reject "a git identity given only half is rejected" git_user_email=
reject "a git_user_name containing a quote is rejected" \
    'git_user_name=he said "hi"'

# ===========================================================================
# Report
# ===========================================================================
echo ""
echo "template render test results"
echo "----------------------------"
if [[ ${#FAILED_CASES[@]} -gt 0 ]]; then
    for case_name in "${FAILED_CASES[@]}"; do
        echo "FAIL  $case_name"
    done
fi
echo "passed: $PASS  failed: $FAIL  total: $((PASS + FAIL))"
[[ "$FAIL" -eq 0 ]]
