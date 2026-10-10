#!/usr/bin/env bash
# update-pins.sh — brings the versions the template pins up to date: the image
# tools in the Dockerfile, the npm CLIs and zsh plugins post-create.sh installs,
# the bundled skills, the generated project's hook revs, dev tool floors, CI
# actions and Trivy, and this repo's own hook revs and CI tools. The daily
# workflow (.github/workflows/update-pins.yml) runs it; it runs by hand too.
# What it covers and what stays manual: docs/maintenance.md -> Pin audit.
#
# Usage: scripts/update-pins.sh [--check] [--bump-minor] [--summary <file>]
#                                [--no-repo-workflows]
#   --check              report what would change, edit nothing
#   --bump-minor         when a pin moved, bump VERSION's minor and zero its patch
#   --summary <file>     also write the report (Markdown) to <file>
#   --no-repo-workflows  report, not edit, the pins in this repo's own
#                        .github/workflows/: GITHUB_TOKEN may not push changes
#                        to workflow files, so the daily workflow passes this
#
# Needs gh (signed in, or GH_TOKEN), jq, npm, curl, git and python3, plus
# pre-commit and cookiecutter on PATH or through uvx. bash 3.2-compatible
# (macOS /bin/bash). Each pin is one function run on its own: a lookup that
# fails is reported and that pin left alone, never guessed. A newer major of a
# CI action, Node, Python or a devcontainer feature is reported, not applied.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/{{cookiecutter.project_slug}}"
DOCKERFILE="$TPL/.devcontainer/Dockerfile"
POST_CREATE="$TPL/.devcontainer/post-create.sh"
DEVCONTAINER_JSON="$TPL/.devcontainer/devcontainer.json"
SKILLS_JSON="$TPL/.devcontainer/config/claude/skills.json"
TPL_PRE_COMMIT="$TPL/.pre-commit-config.yaml"
TPL_PYPROJECT="$TPL/pyproject.toml"
TPL_CI="$TPL/.github/workflows/ci.yml"
TPL_TRIVY="$TPL/scripts/hooks/trivy.sh"
REPO_CI="$ROOT/.github/workflows/ci.yml"
REPO_PRE_COMMIT="$ROOT/.pre-commit-config.yaml"

CHECK=0
BUMP=0
NO_REPO_WORKFLOWS=0
SUMMARY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --bump-minor) BUMP=1 ;;
        --no-repo-workflows) NO_REPO_WORKFLOWS=1 ;;
        --summary)
            [ $# -ge 2 ] || { echo "update-pins: --summary needs a file" >&2; exit 2; }
            SUMMARY="$2"
            shift
            ;;
        -h | --help) sed -n '2,23p' "$0"; exit 0 ;;
        *) echo "update-pins: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

for tool in gh jq npm curl git python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "update-pins: $tool is required" >&2; exit 1; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/update-pins.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/changed"
: > "$WORK/skipped"
: > "$WORK/manual"

# --- Reporting ---------------------------------------------------------------

record() { # LABEL OLD NEW [NOTE]
    # shellcheck disable=SC2016  # the backticks are Markdown, not command substitution
    printf -- '- %s: `%s` -> `%s`%s\n' "$1" "$2" "$3" "${4:+ ($4)}" >> "$WORK/changed"
    printf '%-44s %s -> %s\n' "$1" "$2" "$3"
}

skip() { # LABEL REASON
    printf -- '- %s: %s\n' "$1" "$2" >> "$WORK/skipped"
    echo "update-pins: WARNING: $1 skipped: $2" >&2
}

manual() { # LABEL TEXT — newer than the pin, but for a human to apply
    printf -- '- %s: %s\n' "$1" "$2" >> "$WORK/manual"
}

# run_pin LABEL FUNCTION [ARGS...] — runs one pin in a subshell with errexit
# live (it is not, inside an `if` or `||`), so any failed step aborts only
# that pin.
run_pin() {
    local label="$1" rc
    shift
    set +e
    (
        set -e
        "$@"
    )
    rc=$?
    set -e
    [ "$rc" -eq 0 ] || skip "$label" "lookup or edit failed (see the run log)"
}

# --- File edits --------------------------------------------------------------
# REGEX is a Python regex with one group, the pinned value; ^ and $ match per
# line. Python rather than sed: BSD and GNU sed differ on -i and on escapes.

read_pin() { # FILE REGEX
    python3 - "$1" "$2" <<'PY'
import re, sys
with open(sys.argv[1], encoding="utf-8", newline="") as f:
    m = re.search(sys.argv[2], f.read(), flags=re.M)
if not m:
    sys.exit("no pin matching %r in %s" % (sys.argv[2], sys.argv[1]))
print(m.group(1))
PY
}

write_pin() { # FILE REGEX NEW — every match gets NEW
    python3 - "$1" "$2" "$3" <<'PY'
import re, sys
path, pattern, new = sys.argv[1:4]
with open(path, encoding="utf-8", newline="") as f:
    text = f.read()
def swap(m):
    return m.group(0)[: m.start(1) - m.start(0)] + new + m.group(0)[m.end(1) - m.start(0):]
text, n = re.subn(pattern, swap, text, flags=re.M)
if n == 0:
    sys.exit("no pin matching %r in %s" % (pattern, path))
with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(text)
PY
}

# set_pin LABEL FILE REGEX NEW [SHOWN_OLD SHOWN_NEW] — never moves a version
# backwards: an upstream "latest" older than the pin (a pulled release, or
# pre-commit autoupdate describing a branch the newest tag is not on) is
# reported instead.
set_pin() {
    local label="$1" file="$2" re="$3" new="$4" old
    old="$(read_pin "$file" "$re")"
    [ "$old" != "$new" ] || return 0
    if [ "$(vcmp "$new" "$old" 2>/dev/null || true)" = -1 ]; then
        skip "$label" "upstream's latest $new is older than the pin $old, left as is"
        return 0
    fi
    case "$file" in
        "$ROOT/.github/workflows/"*)
            if [ "$NO_REPO_WORKFLOWS" = 1 ]; then
                manual "$label" "\`${5:-$old}\` -> \`${6:-$new}\`; a workflow file, bump by hand"
                return 0
            fi
            ;;
    esac
    record "$label" "${5:-$old}" "${6:-$new}"
    [ "$CHECK" = 1 ] || write_pin "$file" "$re" "$new"
}

# vcmp A B — prints -1, 0 or 1 as version A is lower than, equal to or higher
# than B; fails unless both are plain versions (a -N packaging suffix allowed).
vcmp() {
    python3 - "$1" "$2" <<'PY'
import re, sys
def key(v):
    if not re.fullmatch(r"v?\d+(\.\d+)*(-\d+)?", v):
        sys.exit(1)
    return [int(p) for p in re.split(r"[.-]", v.lstrip("v"))]
a, b = key(sys.argv[1]), key(sys.argv[2])
print((a > b) - (a < b))
PY
}

re_escape() { python3 -c 'import re, sys; print(re.escape(sys.argv[1]))' "$1"; }

# --- Lookups -----------------------------------------------------------------
# Only plain release numbers pass: a pre-release, an empty answer or "null"
# fails the lookup instead of landing in a file.

stable() { # VERSION
    if printf '%s\n' "$1" | grep -Eq '^v?[0-9]+(\.[0-9]+)*$'; then
        printf '%s\n' "$1"
    else
        echo "update-pins: not a release version: '$1'" >&2
        return 1
    fi
}

is_sha() { printf '%s\n' "$1" | grep -Eq '^[0-9a-f]{40}$'; }

pypi_latest() { # PACKAGE
    local v
    v="$(curl -fsSL --retry 3 "https://pypi.org/pypi/$1/json" | jq -r .info.version)"
    stable "$v"
}

npm_latest() { # PACKAGE
    local v
    v="$(npm view "$1" version)"
    stable "$v"
}

gh_release() { # OWNER/REPO — the latest non-prerelease release's tag
    local v
    v="$(gh api "repos/$1/releases/latest" --jq .tag_name)"
    stable "$v"
}

# newest_tag OWNER/REPO [MAJOR] — highest plain-version tag, optionally within
# one major. Tags, not releases: some repos tag without publishing releases.
newest_tag() {
    local tags
    tags="$(git ls-remote --tags --refs "https://github.com/$1.git")"
    printf '%s\n' "$tags" | python3 -c '
import re, sys
want = sys.argv[1] if len(sys.argv) > 1 else ""
best = None
for line in sys.stdin:
    tag = line.rstrip("\n").rsplit("refs/tags/", 1)[-1]
    if not re.fullmatch(r"v?\d+(\.\d+)*", tag):
        continue
    key = tuple(int(p) for p in tag.lstrip("v").split("."))
    if want and str(key[0]) != want:
        continue
    if best is None or key > best[0]:
        best = (key, tag)
if best is None:
    sys.exit("no release tag found")
print(best[1])
' "${2:-}"
}

commit_of() { # OWNER/REPO REF — the commit SHA a tag or branch points to
    local sha
    sha="$(gh api "repos/$1/commits/$2" --jq .sha)"
    is_sha "$sha" || { echo "update-pins: no commit for $1@$2" >&2; return 1; }
    printf '%s\n' "$sha"
}

hub_digest() { # IMAGE TAG — the multi-arch index digest on Docker Hub
    local digest
    digest="$(curl -fsSL --retry 3 "https://hub.docker.com/v2/repositories/$1/tags/$2" | jq -r .digest)"
    printf '%s\n' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' \
        || { echo "update-pins: no digest for $1:$2" >&2; return 1; }
    printf '%s\n' "$digest"
}

pre_commit() {
    if command -v pre-commit >/dev/null 2>&1; then pre-commit "$@"; else uvx pre-commit "$@"; fi
}

cookiecutter_cmd() {
    if command -v cookiecutter >/dev/null 2>&1; then cookiecutter "$@"; else uvx cookiecutter "$@"; fi
}

# --- Pins: the image (Dockerfile) ----------------------------------------------

pin_uv() {
    local v
    v="$(pypi_latest uv)"
    set_pin "uv (image)" "$DOCKERFILE" 'uv==([0-9.]+)' "$v"
}

pin_image_pre_commit() {
    local v
    v="$(pypi_latest pre-commit)"
    set_pin "pre-commit (image)" "$DOCKERFILE" 'pre-commit==([0-9.]+)' "$v"
}

pin_starship() {
    local tag
    tag="$(gh_release starship/starship)"
    set_pin "Starship (image)" "$DOCKERFILE" 'starship/releases/download/(v[0-9.]+)/' "$tag"
}

pin_bicep() {
    local tag
    tag="$(gh_release Azure/bicep)"
    set_pin "Bicep (image)" "$DOCKERFILE" 'BICEP_VERSION=(v[0-9.]+)' "$tag"
}

pin_claude_code() {
    local v
    v="$(npm_latest @anthropic-ai/claude-code)"
    set_pin "Claude Code fallback (image)" "$DOCKERFILE" 'CLAUDE_CODE_VERSION:-([0-9.]+)\}' "$v"
}

# --- Pins: provisioning (post-create.sh) and bundled skills ---------------------

pin_npm_cli() { # PACKAGE
    local v
    v="$(npm_latest "$1")"
    set_pin "$1 (post-create)" "$POST_CREATE" "npm install -g $(re_escape "$1")@([0-9.]+)" "$v"
}

pin_zsh_plugin() { # OWNER/REPO
    local tag
    tag="$(newest_tag "$1")"
    set_pin "${1#*/} (post-create)" "$POST_CREATE" \
        "clone_zsh_plugin https://github\\.com/$(re_escape "$1") \\S+ (\\S+)$" "$tag"
}

skill_repos() { jq -r '.skills[].repo' "$SKILLS_JSON"; }

pin_skill() { # OWNER/REPO — the default branch's head commit
    local old new
    old="$(jq -er --arg r "$1" '.skills[] | select(.repo == $r) | .ref' "$SKILLS_JSON")"
    new="$(commit_of "$1" HEAD)"
    [ "$old" != "$new" ] || return 0
    # The compare link is what a reviewer reads: this is third-party code
    # that ships into every container.
    record "skill $1" "${old:0:12}" "${new:0:12}" "https://github.com/$1/compare/$old...$new"
    [ "$CHECK" = 1 ] && return 0
    jq --arg r "$1" --arg s "$new" '(.skills[] | select(.repo == $r) | .ref) = $s' \
        "$SKILLS_JSON" > "$WORK/skills.json"
    cat "$WORK/skills.json" > "$SKILLS_JSON"
}

# --- Pins: pre-commit hook revs ------------------------------------------------
# pre-commit autoupdate runs on a scratch copy; the new revs are then copied
# into the real file by repo URL, so comments and (in the template) Jinja
# around them are untouched.

repo_revs() { # CONFIG — prints "URL REV" per remote repo
    python3 - "$1" <<'PY'
import re, sys
url = None
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r"\s*- repo:\s*(\S+)", line)
    if m:
        url = m.group(1)
        continue
    m = re.match(r"\s*rev:\s*(\S+)", line)
    if m and url and url not in ("local", "meta"):
        print(url, m.group(1))
        url = None
PY
}

apply_autoupdate() { # LABEL TARGET SOURCE — SOURCE is a parseable copy of TARGET
    local label="$1" target="$2" dir url rev
    dir="$(mktemp -d "$WORK/autoupdate.XXXXXX")"
    cp "$3" "$dir/.pre-commit-config.yaml"
    git -C "$dir" init -q
    if ! (cd "$dir" && pre_commit autoupdate -j 4 > "$dir/autoupdate.log" 2>&1); then
        cat "$dir/autoupdate.log" >&2
        return 1
    fi
    repo_revs "$dir/.pre-commit-config.yaml" > "$dir/revs"
    while read -r url rev; do
        # Release tags only, the form template-tests.sh asserts: a packaging
        # re-tag such as shellcheck-py's v0.11.0.1-1 waits for the next release.
        if ! printf '%s\n' "$rev" | grep -Eq '^v[0-9]+(\.[0-9]+)+$'; then
            skip "${url#https://github.com/} ($label)" "$rev is not a plain release tag, left as is"
            continue
        fi
        set_pin "${url#https://github.com/} ($label)" "$target" \
            "- repo: $(re_escape "$url")[ \\t]*\\n[ \\t]+rev: (\\S+)" "$rev"
    done < "$dir/revs"
}

pin_template_hook_revs() {
    local out project
    out="$(mktemp -d "$WORK/render.XXXXXX")"
    cookiecutter_cmd "$ROOT" --no-input -o "$out" project_name="Pin Update" >/dev/null
    project="$out/pin-update"
    apply_autoupdate "template hooks" "$TPL_PRE_COMMIT" "$project/.pre-commit-config.yaml"
}

pin_repo_hook_revs() {
    apply_autoupdate "repo hooks" "$REPO_PRE_COMMIT" "$REPO_PRE_COMMIT"
}

# --- Pins: the generated project's tooling --------------------------------------

dev_floor_names() { # the "name>=" entries of the dev dependency group
    python3 - "$TPL_PYPROJECT" <<'PY'
import re, sys
block = re.search(r"^dev = \[(.*?)^\]", open(sys.argv[1], encoding="utf-8").read(), re.M | re.S)
for name in re.findall(r'"([A-Za-z0-9_.-]+)>=', block.group(1) if block else ""):
    print(name)
PY
}

pin_dev_floor() { # PACKAGE
    local v
    v="$(pypi_latest "$1")"
    set_pin "$1 floor (template pyproject)" "$TPL_PYPROJECT" "\"$(re_escape "$1")>=([^\"]+)\"" "$v"
}

template_actions() { # OWNER/REPO of every SHA-pinned action in the template CI
    python3 - "$TPL_CI" <<'PY'
import re, sys
seen = []
for m in re.finditer(r"uses: ([\w.-]+/[\w.-]+)@[0-9a-f]{40} # v", open(sys.argv[1], encoding="utf-8").read()):
    if m.group(1) not in seen:
        seen.append(m.group(1))
print("\n".join(seen))
PY
}

pin_template_action() { # OWNER/REPO — newest release within the pinned major
    local repo="$1" re cur tag newest sha oldsha
    re="uses: $(re_escape "$repo")@([0-9a-f]{40} # v[0-9.]+)$"
    cur="$(read_pin "$TPL_CI" "$re")"
    oldsha="${cur%% *}"
    cur="${cur##* }"
    newest="$(newest_tag "$repo")"
    if [ "$(major_of "$newest")" -gt "$(major_of "$cur")" ]; then
        manual "$repo (template ci.yml)" "pinned $cur; $newest is out"
    fi
    tag="$(newest_tag "$repo" "$(major_of "$cur")")"
    sha="$(commit_of "$repo" "$tag")"
    set_pin "$repo (template ci.yml)" "$TPL_CI" "$re" "$sha # $tag" \
        "$cur ${oldsha:0:7}" "$tag ${sha:0:7}"
}

major_of() { local v="${1#v}"; printf '%s\n' "${v%%.*}"; }

pin_template_ci_pre_commit() {
    local v
    v="$(pypi_latest pre-commit)"
    set_pin "pre-commit (template ci.yml)" "$TPL_CI" 'uvx pre-commit@([0-9.]+)' "$v"
}

pin_template_ci_commitizen() {
    local v
    v="$(pypi_latest commitizen)"
    set_pin "commitizen (template ci.yml)" "$TPL_CI" 'commitizen==([0-9.]+)' "$v"
}

pin_trivy() { # the image tag and its digest move together
    local re tag v digest old old_digest new_digest
    re='TRIVY_IMAGE="aquasec/trivy:([^"]+)"'
    tag="$(gh_release aquasecurity/trivy)"
    v="${tag#v}"
    digest="$(hub_digest aquasec/trivy "$v")"
    old="$(read_pin "$TPL_TRIVY" "$re")"
    old_digest="${old#*@sha256:}"
    new_digest="${digest#sha256:}"
    set_pin "Trivy (template hook)" "$TPL_TRIVY" "$re" "$v@$digest" \
        "${old%%@*} ${old_digest:0:12}" "$v ${new_digest:0:12}"
}

# --- Pins: this repo's own CI ---------------------------------------------------

pin_repo_ci_commitizen() {
    local v
    v="$(pypi_latest commitizen)"
    set_pin "commitizen (repo ci.yml)" "$REPO_CI" 'commitizen==([0-9.]+)' "$v"
}

pin_repo_ci_actionlint() { # a docker:// reference, which Dependabot does not bump
    local tag v
    tag="$(gh_release rhysd/actionlint)"
    v="${tag#v}"
    hub_digest rhysd/actionlint "$v" >/dev/null # the image exists, not just the release
    set_pin "actionlint image (repo ci.yml)" "$REPO_CI" 'docker://rhysd/actionlint:([0-9.]+)' "$v"
}

# --- Newer majors: reported for a human, never applied --------------------------

highest_choice() { # KEY — the highest option cookiecutter.json offers for KEY
    jq -r --arg k "$1" '.[$k] | map(split(".") | map(tonumber)) | max | map(tostring) | join(".")' \
        "$ROOT/cookiecutter.json"
}

report_node() {
    local have lts
    have="$(highest_choice node_version)"
    lts="$(curl -fsSL --retry 3 https://nodejs.org/dist/index.json \
        | jq -r '[.[] | select(.lts != false)][0].version')"
    lts="$(major_of "$(stable "$lts")")"
    [ "$lts" -le "$have" ] || manual "Node" "cookiecutter.json offers up to $have; $lts is the newest LTS"
}

report_python() {
    local have newest
    have="$(highest_choice python_version)"
    newest="$(curl -fsSL --retry 3 https://endoflife.date/api/python.json \
        | jq -r 'map(.cycle | split(".") | map(tonumber)) | max | map(tostring) | join(".")')"
    stable "$newest" >/dev/null
    if [ "$(printf '%s\n%s\n' "$have" "$newest" | sort -t. -k1,1n -k2,2n | tail -n 1)" != "$have" ]; then
        manual "Python" "cookiecutter.json offers up to $have; $newest is released"
    fi
}

report_feature() { # NAME — a devcontainers/features feature pinned to a major tag
    local cur token newest
    cur="$(read_pin "$DEVCONTAINER_JSON" "ghcr\\.io/devcontainers/features/$(re_escape "$1"):([0-9]+)\"")"
    token="$(curl -fsSL "https://ghcr.io/token?scope=repository:devcontainers/features/$1:pull" | jq -r .token)"
    newest="$(curl -fsSL -H "Authorization: Bearer $token" \
        "https://ghcr.io/v2/devcontainers/features/$1/tags/list" \
        | jq -r '[.tags[] | select(test("^[0-9]+$")) | tonumber] | max')"
    stable "$newest" >/dev/null
    [ "$newest" -le "$cur" ] || manual "feature $1" "pinned :$cur; :$newest is out"
}

feature_names() {
    grep -oE 'ghcr\.io/devcontainers/features/[a-z0-9-]+:' "$DEVCONTAINER_JSON" \
        | sed -e 's#.*/##' -e 's#:$##' | sort -u
}

# --- VERSION ------------------------------------------------------------------

bump_minor() {
    local old new
    old="$(tr -d '[:space:]' < "$ROOT/VERSION")"
    printf '%s\n' "$old" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
        || { echo "update-pins: VERSION is not X.Y.Z: '$old'" >&2; return 1; }
    new="$(printf '%s\n' "$old" | awk -F. '{ printf "%d.%d.0\n", $1, $2 + 1 }')"
    record VERSION "$old" "$new"
    [ "$CHECK" = 1 ] || printf '%s\n' "$new" > "$ROOT/VERSION"
}

# --- Run ----------------------------------------------------------------------

if [ "$CHECK" = 1 ]; then echo "update-pins: --check, nothing is edited"; fi

run_pin "uv (image)" pin_uv
run_pin "pre-commit (image)" pin_image_pre_commit
run_pin "Starship (image)" pin_starship
run_pin "Bicep (image)" pin_bicep
run_pin "Claude Code fallback (image)" pin_claude_code
run_pin "@github/copilot (post-create)" pin_npm_cli @github/copilot
run_pin "@playwright/cli (post-create)" pin_npm_cli @playwright/cli
run_pin "zsh-autosuggestions (post-create)" pin_zsh_plugin zsh-users/zsh-autosuggestions
run_pin "zsh-syntax-highlighting (post-create)" pin_zsh_plugin zsh-users/zsh-syntax-highlighting
for repo in $(skill_repos); do
    run_pin "skill $repo" pin_skill "$repo"
done
run_pin "hook revs (template)" pin_template_hook_revs
run_pin "hook revs (repo)" pin_repo_hook_revs
for pkg in $(dev_floor_names); do
    run_pin "$pkg floor (template pyproject)" pin_dev_floor "$pkg"
done
for action in $(template_actions); do
    run_pin "$action (template ci.yml)" pin_template_action "$action"
done
run_pin "pre-commit (template ci.yml)" pin_template_ci_pre_commit
run_pin "commitizen (template ci.yml)" pin_template_ci_commitizen
run_pin "Trivy (template hook)" pin_trivy
run_pin "commitizen (repo ci.yml)" pin_repo_ci_commitizen
run_pin "actionlint image (repo ci.yml)" pin_repo_ci_actionlint
run_pin "Node major report" report_node
run_pin "Python major report" report_python
for feature in $(feature_names); do
    run_pin "feature $feature major report" report_feature "$feature"
done

if [ "$BUMP" = 1 ] && [ -s "$WORK/changed" ]; then
    run_pin "VERSION bump" bump_minor
fi

{
    echo "## Pin update"
    echo
    if [ -s "$WORK/changed" ]; then
        [ "$CHECK" = 0 ] || echo "Would change (--check):"
        [ "$CHECK" = 1 ] || echo "Changed:"
        echo
        cat "$WORK/changed"
    else
        echo "Every pin is current."
    fi
    if [ -s "$WORK/skipped" ]; then
        echo
        echo "Skipped, pin left as is:"
        echo
        cat "$WORK/skipped"
    fi
    if [ -s "$WORK/manual" ]; then
        echo
        echo "Not applied, for a human (docs/maintenance.md -> Pin audit):"
        echo
        cat "$WORK/manual"
    fi
} > "$WORK/summary.md"

echo
cat "$WORK/summary.md"
[ -z "$SUMMARY" ] || cp "$WORK/summary.md" "$SUMMARY"
