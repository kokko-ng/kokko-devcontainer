#!/usr/bin/env bash
# Trivy filesystem scan (dependencies in uv.lock and package-lock.json,
# misconfiguration, secrets), configured in trivy.yaml. Runs before a push
# because it needs the network for its vulnerability database.
#
# Uses a local trivy binary when there is one, otherwise the pinned official
# image through Docker. The devcontainer has neither (trivy's database host is
# not on the firewall allowlist), so there it skips with a notice: CI runs the
# same scan as its own job, where a missing scanner is a failure, not a skip.
set -euo pipefail
cd "$(dirname "$0")/../.."

TRIVY_IMAGE="aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa"

if command -v trivy >/dev/null 2>&1; then
    exec trivy fs --config trivy.yaml .
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    exec docker run --rm -v "$PWD":/src -w /src "$TRIVY_IMAGE" fs --config trivy.yaml .
fi

if [[ -n "${CI:-}" ]]; then
    echo "trivy: neither a trivy binary nor Docker is available in CI" >&2
    exit 1
fi

cat >&2 <<'MESSAGE'
trivy: skipped, no trivy binary and no Docker here (expected inside the
devcontainer). CI runs the same scan on every push and pull request; run it
on the Mac with `brew install trivy` and `scripts/hooks/trivy.sh`.
MESSAGE
exit 0
