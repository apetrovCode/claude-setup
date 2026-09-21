# Global preferences

Generic half of `~/.claude/CLAUDE.md`. The installer concatenates this with
`~/.claude/local/CLAUDE.work.md`, which holds everything employer-specific and is never
committed. If the local file is absent, only what follows is in effect.

## Credentials

- **Never accept, echo, or store cloud access keys or session tokens.** Ask for a profile name
  and verify identity with a read-only call such as `aws sts get-caller-identity --profile <p>`.
  If credentials get pasted, stop and point me at the SSO helper instead.
- The `no-cred-output.sh` PreToolUse hook blocks the commands that would print key material.
  Don't work around it. It exists because tool output gets checkpointed into MemPalace, so a
  credential printed once persists in the palace and resurfaces in every later search.
- **Reference secret-store parameter names and paths, never values.**

## MemPalace — cross-session memory (all projects)

`mempalace` is my long-term memory across every project. Saving is automatic, through the
SessionStart, Stop, SessionEnd and PreCompact hooks. Reading it is not automatic; these rules are:

- **Search before re-deriving.** When I ask "have we done/seen/decided X", "how did we fix Y",
  "what's the state of Z", or you're about to investigate something that sounds familiar — check
  the palace first:
  `mempalace search "<words>" [--wing <wing>] [--room <room>] [--results 10] [--since YYYY-MM-DD]`
  Use the `mempalace_search` MCP tool instead when it's loaded; the CLI is the fallback.
- **Scope by wing.** One wing per project, named `wing_<repo-dirname>` (dashes → underscores);
  past Claude Code sessions live in wing `sessions`. `mempalace status` lists wings/rooms with
  counts. Unsure → search unscoped, then narrow.
- **Cite and verify.** Hits are chunks of old files/transcripts. Name the source (wing/room/file)
  and check against the live repo before acting on it — memory goes stale.
- **No invented memory.** If nothing relevant comes back, say so.
- **Onboarding a repo** (so its docs/code are searchable, not just its session diary): add a
  `mempalace.yaml` (`wing: wing_<dirname>`, `rooms:` by folder, `exclude_patterns:` in gitignore
  syntax), make sure secrets/inventories are excluded there or in `.gitignore`, then
  `mempalace mine .` (idempotent; re-files changed files).
- **Never file secrets.** Anything holding credentials, tokens, or secret-store values stays out
  of the palace — it resurfaces in every future session's search and wake-up context.
- **Subagents have no `mempalace_*` MCP tools.** Use the `mempalace` CLI inside a subagent.

## Working style

- **Delegate wide repo sweeps to a subagent** rather than grepping a large clone set inline;
  checkpoint findings into a knowledge base or a memory note before context passes ~70%.
- **Don't re-checkpoint work I've already approved.** If I've said to fix items 3, 4 and 7, build
  and run all three — don't come back to ask before starting. Do surface: anything I've called a
  blocker pending team approval, accepting security risk on my behalf, and irreversible or
  outward-facing actions.

## Investigations and docs

- **Evidence first** (identifiers, resource names by pattern, run ids), then the conclusion, then
  the ask. Don't lead with the conclusion.
- **Tickets:** no blame; structure as *why / what / fix*; link the evidence.
- **Handover docs:** status table → Done → In flight → Blocked → Next steps → runbook links.
- **Knowledge that outlives the session** goes into the knowledge base, not into a chat summary.
