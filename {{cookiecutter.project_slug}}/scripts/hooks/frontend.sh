#!/usr/bin/env bash
# The frontend's gates: strict type check, lint with no warnings, unit tests.
# Usage: scripts/hooks/frontend.sh <frontend-dir>
#
# The frontend directory starts empty. Until it has a package.json there is
# nothing to check and the hook passes. From then on package.json must define
# the three scripts below; a missing one is a failure, not a skip, so a gate
# cannot disappear by deleting its script.
set -euo pipefail
cd "$(dirname "$0")/../.."

dir="${1:?usage: frontend.sh <frontend-dir>}"
if [[ ! -f "$dir/package.json" ]]; then
    echo "frontend: no $dir/package.json yet, nothing to check"
    exit 0
fi
cd "$dir"

if ! command -v npm >/dev/null 2>&1; then
    echo "frontend: npm is required once $dir/package.json exists" >&2
    exit 1
fi

missing=()
for script in typecheck lint test; do
    if [[ "$(npm pkg get "scripts.$script")" == "{}" ]]; then
        missing+=("$script")
    fi
done
if ((${#missing[@]} > 0)); then
    cat >&2 <<MESSAGE
frontend: $dir/package.json must define these scripts: ${missing[*]}
  typecheck  strict type check, e.g. "vue-tsc --build"
  lint       lint with no warnings, e.g. "eslint . --max-warnings 0"
  test       unit tests, run once, e.g. "vitest run"
MESSAGE
    exit 1
fi

if [[ ! -d node_modules ]]; then
    if [[ -f package-lock.json ]]; then
        npm ci --no-audit --no-fund --silent
    else
        npm install --no-audit --no-fund --silent
    fi
fi

npm run --silent typecheck
npm run --silent lint
npm run --silent test
