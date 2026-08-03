#!/usr/bin/env bash
# lib-git-target.sh — shared git-target resolution for the safety hooks.
#
# NOT a hook itself: guard-git.sh and git-snapshot.sh both source this file so
# the two can never drift apart on WHICH repository a command actually
# touches. A command may target a different repo than the hook's cwd — via a
# leading `cd <dir> &&`, a `git -C <dir>`, or `--git-dir=<dir>` /
# `--git-dir <dir>` — and the guard must check dirtiness (and the snapshot
# hook must checkpoint) in the repo the destructive command is about to hit,
# not wherever the hook happens to run.
#
# Usage (after sourcing):
#   resolve_git_target "$cmd"    # sets $target ("" when the command names
#                                # no repo — callers then use their own cwd)

extract_cd_target() {
    printf '%s' "$cmd" | sed -nE \
        's/^[[:space:]]*cd[[:space:]]+("([^"]+)"|'\''([^'\'']+)'\''|([^[:space:];&|]+))[[:space:]]*(&&|;).*/\2\3\4/p' | head -1
}
extract_dash_c_target() {
    # Only a -C in git's GLOBAL-option position (before the subcommand) names
    # a target repo. Between `git` and `-C`, tolerate other dash options and
    # name=value arguments (`git -c k=v -C <dir> ...`) but NOT a bare word —
    # otherwise `git switch -C topic` reads "topic" as a repository path.
    printf '%s' "$cmd" | sed -nE \
        's/.*git[[:space:]]+((-[^[:space:]]+|[^[:space:]]+=[^[:space:]]*)[[:space:]]+)*-C[[:space:]]+("([^"]+)"|'\''([^'\'']+)'\''|([^[:space:];&|]+)).*/\4\5\6/p' | head -1
}
extract_git_dir_target() {
    # [=[:space:]] accepts both `--git-dir=<dir>` and `--git-dir <dir>` — the
    # space-separated form is equally valid git and used to slip past both
    # hooks. A character class (not a group) keeps the backreferences stable.
    printf '%s' "$cmd" | sed -nE \
        's/.*--git-dir[=[:space:]][[:space:]]*("([^"]+)"|'\''([^'\'']+)'\''|([^[:space:];&|]+)).*/\2\3\4/p' | head -1
}

resolve_git_target() {
    # Bash scoping is dynamic: the extract_* helpers above see this local.
    local cmd="$1"
    local cd_t c_t gd_t
    cd_t=$(extract_cd_target || true)
    c_t=$(extract_dash_c_target || true)
    gd_t=$(extract_git_dir_target || true)

    target=""
    if [[ -n "$c_t" ]]; then
        # A relative -C path resolves against a leading cd, if there is one.
        if [[ -n "$cd_t" && "$c_t" != /* && "$c_t" != "~"* ]]; then
            target="$cd_t/$c_t"
        else
            target="$c_t"
        fi
    elif [[ -n "$gd_t" ]]; then
        # --git-dir points at the .git directory; the working tree is its parent.
        target="$gd_t"
        [[ "$target" == */.git ]] && target="${target%/.git}"
    elif [[ -n "$cd_t" ]]; then
        target="$cd_t"
    fi
    target="${target/#\~/$HOME}"
}
