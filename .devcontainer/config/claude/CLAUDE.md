# CLAUDE.md

Global instructions for Claude Code across all projects.

---

## Permissions

This container runs Claude Code in **Auto mode** (`permissions.defaultMode: "auto"`):
the built-in classifier decides which tool calls run without a prompt. There is no
bespoke git-guard or snapshot hook layer. Git recoverability relies on git itself —
the container sets `gc.reflogExpire`, `gc.reflogExpireUnreachable`, and
`gc.pruneExpire` to `never`, so committed work is always recoverable from the reflog.
Commit early and often; only committed work has that safety net.

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
- **Never modify infrastructure without explicit user permission.** No provisioning,
  scaling, restarting, deleting, or reconfiguring cloud resources — however small
  the change seems — until the user approves that specific action. Inspection is
  free; mutation needs sign-off.

---

## Pre-commit hooks

**If `.pre-commit-config.yaml` exists in the repo, pre-commit runs on every commit you
make. No exceptions.**

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
- **Use the customer's vocabulary** for systems, environments, teams, and roles wherever it
  differs from the internal name.
- **Check the finished draft for leakage** before handing it over: search it for internal
  identifier patterns, internal hostnames, and internal tool names, and report anything you
  removed or need a decision on.

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

Your context window will be automatically compacted as it approaches its limit. Do not stop tasks early due to token budget concerns. Always be persistent and autonomous, completing tasks fully regardless of context remaining.

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

## Validation Output

- Never write validation or verification reports as documents in the repo
  (no VERIFICATION.md, no report files). Report validation results directly
  in the reply message instead.
