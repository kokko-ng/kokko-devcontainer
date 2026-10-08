#!/usr/bin/env bash
# Runs on the HOST before docker build (initializeCommand, after the cert and
# sync-folder steps). Records the git author identity the host would commit
# with in this folder, so post-create.sh can give the container the same one
# when the template's git_user_name / git_user_email answers were left blank.
#
# Writes .devcontainer/.host-git-identity (gitignored next to it): two lines,
# `name=...` and `email=...`, either of which may be empty. Never fails the
# build: a host without git, or without an identity, just records nothing.
set -uo pipefail

out="$(dirname "$0")/.host-git-identity"
name="$(git config user.name 2>/dev/null || true)"
email="$(git config user.email 2>/dev/null || true)"
printf 'name=%s\nemail=%s\n' "$name" "$email" >"$out"
exit 0
