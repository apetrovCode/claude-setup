# Work planning — `~/Projects`

Loads for every session under `~/Projects`. Governs one thing: planning a piece of work into its
own directory here. Secrets, cloud-account, IaC and knowledge-base rules are the global ones in
`~/.claude/CLAUDE.md` and are not restated; a project's own CLAUDE.md governs its repo.

Markdown here is mined into MemPalace wing `wing_projects`. Search it before re-deriving earlier
planning; `mempalace mine .` from `~/Projects` after adding files. `mempalace.yaml` is the only
exclusion layer here (no git) — keep it current.

## Repos live in `~/gits`

Every repo a task touches is checked out at `~/gits/<repo-name>` (dir name = GitHub repo name).
Before reading or editing a repo, `ls ~/gits` for it; if it is missing, `git clone` it into
`~/gits/<repo-name>` and work from there. Clones go nowhere else — not into `~/Projects/<task>/`,
not into the scratchpad.

## Three kinds of work

| Kind | Source of truth | Directory | `README.md` shape |
|---|---|---|---|
| **Ticket** | one Jira issue — `getJiraIssue` with remote links and comments | `~/Projects/<TICKET>/` | **why / what / fix** |
| **Exploration** — PoC, spike, "is X viable" | the question, pinned in step 3 | `~/Projects/<kebab-name>/` | **question / tried / found / recommend**, ending in go or no-go |
| **Initiative** — multi-ticket, runs in waves | epic or Confluence page plus its child tickets | `~/Projects/<kebab-name>/` | handover shape from the global docs rule: status table → Done → In flight → Blocked → Next steps |

A directory that already exists is resumed, not recreated: read its `status.md` first, then
`README.md`, and update both in place. If it has files but no `README.md` (the older initiatives),
write the README as an index of what is already there before adding anything; if it has no
`status.md`, write one from what the other files show before doing new work.

## In this order, every kind

1. **Sweep evidence.** `mempalace search` scoped to the relevant repo's wing, then the repo
   itself, then GitHub MCP for PRs, workflow runs and job logs. Done when every repo, PR and run
   the source references has been read and can be cited by wing/room/file, PR number, or run URL.
   For an initiative, sweep every child ticket.
2. **Read the source of truth** for the kind (table above).
3. **Ask clarifying questions, then wait.** The answers gate step 4 — files written before them
   get written twice. For an exploration this is where the question gets pinned and its deciding
   result agreed: which outcome means go, which means no-go.
4. **Create the directory** with exactly these four markdown files:

| File | Contents |
|---|---|
| `README.md` | Shape per kind (table above). Evidence, then conclusion, then the ask. No blame. |
| `plan.md` | Ordered, verifiable steps. Line 1 names the cloud account and region. Exploration: each step states what its result would decide. Initiative: steps grouped by wave. |
| `resources.md` | Ticket or epic URL, Confluence links, PR and workflow-run URLs, ARNs by name pattern, secret-store parameter names. Initiative: the child-ticket list. |
| `status.md` | The resume point for a fresh session. Line 1: `Last updated: <date>`. Then **Done / In flight / Blocked / Next**, each a few bullets, and the plan step to pick up at. High level only — the detail lives in the other three files. |

`status.md` is the one file that must be true at the end of every session. Update it when a
plan step completes, when something blocks, and before the session ends. A fresh session that
reads only `status.md` should know what happened and what to do next, without opening anything
else.

Plans are grounded: real evidence plus your answers, never agent guesses.
