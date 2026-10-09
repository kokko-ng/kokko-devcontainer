# CLAUDE.md

Instructions for Claude Code in every project in this devcontainer.

---

## Permissions

This container runs Claude Code in **Auto mode** (`permissions.defaultMode: "auto"`):
the built-in classifier decides which tool calls run without a prompt. The container
sets `gc.reflogExpire`, `gc.reflogExpireUnreachable` and `gc.pruneExpire` to `never`,
so committed work is always recoverable from the reflog. Commit early and often; only
committed work has that safety net.

A managed deny list (`/etc/claude-code/managed-settings.json`) sits under auto mode and
blocks the irreversible operations: force-push in any spelling, squash merges,
`git reflog expire` and `git gc --prune`, Azure `delete` and `purge`, Docker volume
removal and pruning, `gh repo delete` and `gh api` DELETE calls, and reading or
printing the gh, Azure and Claude tokens.
**A denied command was denied on purpose.** Report it and ask; do not look for another
spelling, wrapper, or program that does the same thing. Bypass mode is disabled.

**The container has an outbound firewall** (unless `DEVCONTAINER_FIREWALL` is `0`) that
you cannot change and must not try to: everything here reaches only an allowlist of hosts
(GitHub, Copilot, Anthropic, npm, PyPI, Azure, and what the project added). A request
that fails at once with "No route to host" to a host outside that list is the firewall,
not a bug: say which host it needed and let the user add it to
`.devcontainer/firewall/allowed-domains.txt`; do not route around it. If an
allowlisted host stops answering, `sudo devcontainer-firewall` refreshes its addresses
(normally the only thing sudo does here). System packages need a Dockerfile change and
a rebuild, which the user runs.

**This may be a small machine.** The container has a hard memory cap (2 GB on an
8 GB Mac) and an out-of-memory kill takes your process with it. Run heavy steps one at a
time: no `pytest -n auto`, no `make -j`, no several installs or builds at once, no more
dev servers than the task needs, and stop the ones you started when you are done. If a
step looks likely to need more than about 2 GB of memory, ask first.

A `SessionStart` hook prints any provisioning step that failed when the container was
built. If it does, the tools that step installs may be missing — fix the cause or tell
the user before working around it.

---

## Infrastructure

Bugs are not always in the code. When the symptoms make it plausible — timeouts,
intermittent failures, connection resets, out-of-memory kills, disk-full errors,
TLS/DNS failures, throttling (429/503), quota or capacity errors — investigate
whether the infrastructure is the cause, not just the code in front of you.

- **Read-only investigation is always fine.** `az account show`, `az resource list`,
  `az monitor metrics list`, service logs and status, `df -h`, `docker system df`,
  and similar inspection commands need no special permission.
- **Raise capacity and provisioning needs with the user.** When the evidence points
  at missing or undersized infrastructure — an exhausted plan, a too-small SKU or
  tier, a full disk, a resource that does not exist yet — report the finding and the
  exact command you would run to fix it (e.g. the `az` CLI command to provision or
  scale), with the cost impact where known, per "Presenting decisions" below.
- **Deploy only to sandbox, dev or demo targets** (resource groups or subscriptions named
  that way) unless the user names another. Ask once before the first deploy to such a
  target in a task; once the user agrees, redeploying the same app to the same target
  in that task needs no further confirmation. Anything named prod or production needs
  the user's go-ahead for every action.
- **Read back what you deployed.** After a deploy or revision roll, query the live
  resource (the image tag, the active revision and its health, the app's response)
  rather than trusting the command's output.
- **Tag new Azure resource groups and resources** `contactEmail=Kokko.Ng@insight.com`
  where the subscription requires the tag.
- **Never modify infrastructure without explicit user permission.** No provisioning,
  scaling, restarting, deleting, or reconfiguring cloud resources — however small
  the change seems — until the user approves that specific action (a deploy approved
  as above counts). Inspection is
  free; mutation needs sign-off.

---

## Git

- **Stage explicit file paths.** Never `git add -A`, `git add .` or `git add -u`: they
  sweep in files you did not mean to commit.
- **Commit messages follow the repo's convention.** Most repos here use Conventional
  Commits (`feat:`, `fix:`, `docs:` ...), checked by commitizen in pre-commit.
- **Never squash-merge.** Merge pull requests with a merge commit
  (`gh pr merge --merge`), never `--squash` and never `git merge --squash`, so every
  commit keeps its own message and history. A rebase merge only when the user asks.
- **Never rewrite published history** (rebase, amend or reset of pushed commits) unless
  the user asks for that specific change.
- **Commit as the configured identity** (`kokko-ng <Kokko.Ng@insight.com>`) and add no
  `Co-Authored-By`, `Claude-Session` or other AI trailers to commits or PR bodies.
- **Never change a repository's visibility** or push private code to a public repo,
  including forks; check a new fork is private.
- **Before merging a subagent's branch**, compare `git merge-base main <branch>` with
  `main`: a stale base silently drops other work in auto-merged files. Have the agent
  merge `main` and re-run its checks instead of resolving its conflicts yourself.
- **Work that seems lost probably is not.** On an unexplained clean tree mid-task, check
  `git stash list` (and the reflog) before redoing or reporting anything as lost.

## Pre-commit

**In a repo with a `.pre-commit-config.yaml`, pre-commit runs on every commit you make.
No exceptions.** A repo without one: say so once and offer to add one; do not add it
unasked.

- **Before pushing or opening a pull request**, run `pre-commit run --all-files` and fix
  what fails, so CI does not find it first.
- **Test cadence.** While iterating, run the tests for what changed. Run the full suites
  and `pre-commit run --all-files` at the end, and before anything expensive that depends
  on a working tree (a long agent run, a deploy).
- **Never pass `--no-verify` or `-n` to `git commit`**, and never set `PRE_COMMIT_ALLOW_NO_CONFIG`
  or otherwise disable the hooks. If you are reaching for a bypass, you are about to
  commit something the repo has decided is not acceptable.
- **If the hooks are not installed**, install them before committing: `uv run pre-commit install`
  (or `pre-commit install` where uv is not in use). A config file with no installed hook
  is a silent no-op, so verify `.git/hooks/pre-commit` exists rather than assuming.
- **When hooks fail, fix the cause.** Read the output, correct the code, and commit again.
  Do not work around the check, loosen the rule, or add per-file ignores to make it pass
  unless the user asks for exactly that.
- **When hooks rewrite files** (formatters like black, ruff, prettier), the commit aborts
  with the fixes left in the working tree. Re-stage the **explicit file paths** — never
  `git add -u` or `git add .`, per the git rules above — and commit again. Check the diff
  the hook produced before re-staging; it is a real change to your work.
- **Run hooks early on large changes** rather than discovering everything at commit time:
  `pre-commit run --files <paths>`.
- **A failing hook is information, not an obstacle.** Report what failed and what you did
  about it; do not silently retry until something goes through.

---

## Communication Style

- Never use emojis in any communication, code, comments, or documentation
- Maintain a concise, professional tone in all interactions
- Provide direct, clear technical communication without unnecessary elaboration
- Focus on facts and technical accuracy over conversational language

## Technical documents for customers

When drafting or writing a technical document a customer will read — as-built
documentation, solution designs, runbooks, handover packs, proposals, reports — reference
only artifacts and terminology the customer actually receives.

- **Never cite an internal artifact the customer will not be given.** Internal
  specification identifiers (`SPEC-01`, `SPEC-014` and similar), ticket and epic numbers,
  branch or repo paths, internal wiki links, and project-internal codenames must not
  appear. An as-built document that says "as per SPEC-01" is unusable to a reader who has
  never seen SPEC-01, and it advertises a document they cannot request.
- **Replace the pointer with what it points at.** "Configured as specified in SPEC-01"
  becomes the actual configuration, stated in full. If the reference exists because the
  detail is long, reproduce the detail in an appendix rather than citing the internal doc.
- **Ask when the audience is unclear.** If it is not obvious whether a document,
  identifier, term, or diagram is shared with the customer, **ask the user which artifacts
  the customer sees before writing** — do not guess, and do not silently drop content that
  may in fact be shared. One question up front is cheaper than a rewrite.
- **Commercial documents** (proposals, SOWs, RFP responses): never show labour rates,
  rate cards, internal estimating tools or currency conversions; round amounts to the
  nearest 10 so lines still add up to totals; use role titles rather than names outside
  the personnel section.
- **Describe local-only material neutrally** ("local reference material, never
  committed"), never as confidential client or engagement material, and leave no trail
  (file names, titles, source IDs) back to it in anything committed.
- **Use the customer's vocabulary** for systems, environments, teams, and roles wherever it
  differs from the internal name.
- **Check the finished draft for leakage** before handing it over: search it for internal
  identifier patterns, internal hostnames, and internal tool names, and report anything you
  removed or need a decision on.

## Visual changes

What the user or client has already reviewed is the spec. Do not "correct" reviewed sizes,
colours or spacing toward a design document on your own initiative; ask first.

## Finishing a task

Never end a task with only a summary of what was done. Every completed task ends with a
short **Next steps** section — 2 to 5 concrete, specific items, ordered by value. Cover
whatever applies:

- **Follow-on work** the change implies but did not include (tests, docs, migrations,
  callers not yet updated, error paths not yet handled).
- **Improvements** to what was just written — refactors deferred for scope, duplication
  introduced, naming or structure worth revisiting.
- **Risks and unknowns** — assumptions made, things not verified, edge cases untested,
  places where the change could break something not exercised.
- **Verification the user should run** if it could not be run here.

Rules for this section:

- Be specific and actionable. "Add tests for the retry path in `client.py`" — not
  "consider adding tests".
- Name the files or commands involved.
- Say why each item matters in a clause, not a paragraph.
- Rank them. If one item matters more than the rest, say so and say why.
- If a task genuinely has no meaningful follow-ups, say that explicitly in one line
  rather than padding the list with filler.

This applies to trivial tasks as well as large ones — the list is just shorter.

## Presenting decisions

When a decision is the user's to make, **never** hand it back without a position.
"Let me know how you want to proceed", "I'll leave it up to you", and "either works" are
not acceptable as a complete answer.

Every decision put to the user includes:

1. **The options**, named and briefly described — including the option of doing nothing
   when that is real.
2. **Trade-offs for each**, as explicit pros and cons. Cover the axes that actually
   differ: effort, complexity, performance, maintenance burden, reversibility, blast
   radius, dependencies added, how it ages.
3. **A recommendation** — one option, stated plainly as the one to pick.
4. **Why that one**, and specifically what would have to be true for a different option
   to win instead. If the recommendation is close, say it is close and say what tips it.

Keep it tight — a compact table or short bulleted comparison, not an essay. The point is
that the user can decide in seconds because the analysis is already done.

If information needed to make the call is genuinely missing, say what is missing, give
the recommendation under a stated assumption, and note how it changes if the assumption
is wrong. A missing fact is not a reason to withhold a recommendation.

## Context Window

Your context window is compacted automatically as it approaches its limit, so the
context remaining is never a reason to stop a task early or cut it short.

## Testing and Development Files

All testing artifacts, temporary files, and development scripts should be placed in `/tmp` to maintain repository cleanliness:

- Development scripts and experiments
- Temporary output files
- Test artifacts and logs
- Mock data generators

## Process Management

**Never kill processes by name** — no `pkill <name>`, no `killall <name>`. Name matching
takes down every match, not just yours: this container's own services, other sessions'
dev servers, potentially your own session's processes. Instead:

- When you start a long-running process you may need to stop or restart, capture its PID
  (`$!`, or a pidfile) and `kill` that specific PID.
- For a process you did not start, report it and ask the user instead of killing it.

## Shell

The shell is zsh. Brace a variable that is followed by a colon (`"${app}:${tag}"`,
`"${app}:latest"`): after an unbraced name zsh reads `:l`, `:u`, `:h`, `:t` and others as
modifiers and silently changes the string (`$app:light-only` once reached Azure as
`frontendight-only`).

## Subagents

Launch subagents with `model: "opus"` unless the task needs the strongest model; give each
a self-contained brief with the expected base commit when it works on a branch.

## Validation Output

- Never write validation or verification reports as documents in the repo
  (no VERIFICATION.md, no report files). Report validation results directly
  in the reply message instead.
