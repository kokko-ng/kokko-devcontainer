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
assert_jq "template prompts for a container memory limit" "$ROOT/cookiecutter.json" \
    'has("container_memory_limit")'
assert_jq "template prompts for Claude attribution, off by default" "$ROOT/cookiecutter.json" \
    '.claude_attribution[0] == "no"'
# Docker-in-Docker makes the container privileged, so it must be opt-in.
assert_jq "docker-in-docker defaults to no" "$ROOT/cookiecutter.json" \
    '.include_docker_in_docker[0] == "no"'
assert_jq "managed settings and the Claude hooks are excluded from rendering" "$ROOT/cookiecutter.json" \
    '._copy_without_render
       | (index(".devcontainer/config/claude/managed-settings.json") != null)
       and (index(".devcontainer/config/claude/hooks/*") != null)'
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
assert_jq "docker-in-docker feature is absent by default" "$DC" \
    '.features | has("ghcr.io/devcontainers/features/docker-in-docker:4") | not'
assert_jq "no docker extension by default" "$DC" \
    '.customizations.vscode.extensions | index("ms-azuretools.vscode-docker") == null'
assert_jq "the Claude Code extension is installed" "$DC" \
    '.customizations.vscode.extensions | index("anthropic.claude-code") != null'
assert_jq "Claude Code state is pointed at the named volume" "$DC" \
    '.containerEnv.CLAUDE_CONFIG_DIR == "/home/vscode/.claude"'
assert_jq "Claude Code auto-update is off (the image pins the version)" "$DC" \
    '.containerEnv.DISABLE_AUTOUPDATER == "1"'
# Always per project, whatever the cache scope: the settings merge writes
# into this volume, and two projects sharing it would fight over the roster.
assert_jq "Claude Code state volume is per project" "$DC" \
    '[.mounts[] | select(test("target=/home/vscode/.claude,"))]
       == ["source=my-project-claude-config,target=/home/vscode/.claude,type=volume"]'
assert_jq "gh login volume follows the shared cache scope" "$DC" \
    '[.mounts[] | select(test("target=/home/vscode/.config/gh,"))]
       == ["source=devcontainer-gh-config,target=/home/vscode/.config/gh,type=volume"]'
assert_jq "default memory limit reaches runArgs, with swap disabled" "$DC" \
    '(.runArgs | index("--memory=8g") != null) and (.runArgs | index("--memory-swap=8g") != null)'
assert_jq "pids limit leaves room for parallel sessions" "$DC" \
    '.runArgs | index("--pids-limit=4096") != null'
assert_jq "postStart output is captured like postCreate output" "$DC" \
    '.postStartCommand | test("tee /tmp/post-start.log")'
assert "azure volume hint is offered with the azure cli" \
    grep -q 'azure-config' "$DEFAULT/.devcontainer/devcontainer.json"
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
# The attribution answer defaults to no: the bundle's empty strings, which
# hide the Co-Authored-By trailer and the PR footer, come through untouched.
assert_jq "Claude attribution is hidden by default" \
    "$DEFAULT/.devcontainer/config/claude/settings.json" \
    '.attribution == {commit: "", pr: ""}'

assert_jq "bundled managed settings stay valid JSON and lock bypass mode" \
    "$DEFAULT/.devcontainer/config/claude/managed-settings.json" \
    '.permissions.disableBypassPermissionsMode == "disable"'

# The agent-facing files a generated project carries next to .devcontainer/.
assert "generated project has a CLAUDE.md for the agent" \
    test -f "$DEFAULT/CLAUDE.md"
# shellcheck disable=SC2016  # the backticks are Markdown, not command substitution
assert "CLAUDE.md names the backend directory" \
    grep -qF '| Python backend | `src/`' "$DEFAULT/CLAUDE.md"
# shellcheck disable=SC2016
assert "CLAUDE.md names the frontend directory" \
    grep -qF '| Frontend | `ui/`' "$DEFAULT/CLAUDE.md"
assert "CLAUDE.md carries the forwarded ports" \
    grep -qE '^\| Backend port \| 8000 \|' "$DEFAULT/CLAUDE.md"
assert "CLAUDE.md lists the optional tools that were chosen" \
    grep -qE 'jq, az, playwright-cli with Chromium, copilot\.' "$DEFAULT/CLAUDE.md"
refute "CLAUDE.md does not mention docker without docker-in-docker" \
    grep -q 'nested daemon' "$DEFAULT/CLAUDE.md"
assert "generated project has a root .gitignore" \
    test -f "$DEFAULT/.gitignore"
for pat in '^\.env$' '^!\.env\.example$' '^\.claude/worktrees/$' '^\.claude/settings\.local\.json$' '^\.playwright-cli/$'; do
    assert "generated .gitignore has $pat" grep -qE "$pat" "$DEFAULT/.gitignore"
done

assert "default Dockerfile installs the ODBC driver" \
    grep -q msodbcsql18 "$DEFAULT/.devcontainer/Dockerfile"
assert "default Dockerfile pins the Claude Code version" \
    grep -qE 'install\.sh \| bash -s [0-9]+\.[0-9]+\.[0-9]+$' "$DEFAULT/.devcontainer/Dockerfile"
assert "default Dockerfile installs shellcheck and the sandbox dependencies" \
    grep -qE 'apt-get install .* shellcheck bubblewrap socat' "$DEFAULT/.devcontainer/Dockerfile"
assert "default Dockerfile pins pre-commit" \
    grep -qE 'pip install .* pre-commit==[0-9]+\.[0-9]+\.[0-9]+' "$DEFAULT/.devcontainer/Dockerfile"
assert "default Dockerfile pins the base image by digest" \
    grep -qE '^FROM .*python:3\.14-bookworm@sha256:' "$DEFAULT/.devcontainer/Dockerfile"
assert "certs/.gitkeep survives so plain docker build works" \
    test -f "$DEFAULT/.devcontainer/certs/.gitkeep"
assert "extracted host certs are gitignored inside .devcontainer" \
    grep -qx 'certs/\*' "$DEFAULT/.devcontainer/.gitignore"

# Files listed in _copy_without_render must come through byte-identical —
# a stray Jinja delimiter in jq or zsh config would otherwise be swallowed.
for f in config/claude/merge-settings.jq config/claude/prune-roster.jq config/zsh/.zshrc \
         config/claude/settings.json config/claude/CLAUDE.md \
         config/claude/managed-settings.json config/claude/hooks/session-provision-status.sh; do
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
    container_memory_limit=2048m \
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
assert_jq "chosen memory limit reaches runArgs" "$SDC" \
    '(.runArgs | index("--memory=2048m") != null) and (.runArgs | index("--memory-swap=2048m") != null)'
assert_jq "per-project gh login volume is namespaced by slug" "$SDC" \
    '[.mounts[] | select(test("source=slim-app-gh-config,"))] | length == 1'
assert_jq "Claude Code state volume is namespaced by slug" "$SDC" \
    '[.mounts[] | select(test("source=slim-app-claude-config,"))] | length == 1'
refute "no azure volume hint without the azure cli" \
    grep -q 'azure-config' "$SLIM/.devcontainer/devcontainer.json"
refute "slim CLAUDE.md lists none of the optional tools" \
    grep -qE 'playwright-cli|copilot|, az|nested daemon' "$SLIM/CLAUDE.md"
assert "slim Dockerfile still installs shellcheck and the sandbox dependencies" \
    grep -qE 'apt-get install .* shellcheck bubblewrap socat' "$SLIM/.devcontainer/Dockerfile"

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
# 3b. Opt-ins the other renders leave off: Docker-in-Docker (the one answer
#     that changes the container's privilege level), Claude attribution, and
#     both post-generation edits to settings.json at once (empty roster plus
#     attribution) to prove they compose.
# ===========================================================================
render "$WORK/dind" project_name="Dind App" include_docker_in_docker=yes \
    claude_attribution=yes claude_plugin_roster=none
DIND="$WORK/dind/dind-app"
assert "dind answers render" test -d "$DIND/.devcontainer"

DDC="$WORK/dind-devcontainer.json"
if jsonc_to_json "$DIND/.devcontainer/devcontainer.json" > "$DDC" 2>/dev/null; then
    ok
else
    bad "dind devcontainer.json parses as JSONC"
fi
assert_jq "docker-in-docker feature is added on request" "$DDC" \
    '.features | has("ghcr.io/devcontainers/features/docker-in-docker:4")'
assert_jq "docker extension follows docker-in-docker" "$DDC" \
    '.customizations.vscode.extensions | index("ms-azuretools.vscode-docker") != null'
assert "CLAUDE.md tells the agent the container is privileged" \
    grep -q 'privileged' "$DIND/CLAUDE.md"
assert "DEVCONTAINER.md says the container is privileged" \
    grep -q 'privileged' "$DIND/DEVCONTAINER.md"
assert "generation prints the privileged note" \
    grep -q 'PRIVILEGED' "$WORK/dind.err"
# claude_attribution=yes removes the empty-string override so Claude Code's own
# default trailer and PR footer apply; nothing else in the bundle may move.
assert_jq "attribution answer removes the override" \
    "$DIND/.devcontainer/config/claude/settings.json" \
    'has("attribution") | not'
assert_jq "attribution edit composes with the emptied roster" \
    "$DIND/.devcontainer/config/claude/settings.json" \
    '(.enabledPlugins | length == 0) and (.extraKnownMarketplaces | length == 0)'
assert_jq "settings.json edits keep the rest of the bundle" \
    "$DIND/.devcontainer/config/claude/settings.json" \
    '.permissions.defaultMode == "auto"
       and (.hooks | has("SessionStart"))
       and .env.BASH_DEFAULT_TIMEOUT_MS == "600000"
       and .sandbox.enabled == false'

# ===========================================================================
# 4. Nothing anywhere is left unrendered
# ===========================================================================
# A forgotten `{{` or `{%` in a generated file means an option silently did
# nothing. Only real Jinja delimiters count — `${...}` variable syntax and
# bash's `${#array[@]}` are fine.
unrendered=$(grep -rlE '\{\{|\{%' "$DEFAULT" "$SLIM" "$DIND" 2>/dev/null || true)
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
                "$project/.devcontainer/init-host-certs.sh" \
                "$project/.devcontainer/config/claude/hooks/session-provision-status.sh"
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
reject "a memory limit without a unit is rejected" container_memory_limit=8
reject "a memory limit with a bogus unit is rejected" container_memory_limit=8tb
reject "a memory limit below 512m is rejected" container_memory_limit=256m

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
