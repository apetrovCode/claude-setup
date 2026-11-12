# Rules for AI agents working in this repo

This repo builds a personal Claude Code setup (`~/.claude`) and is **public**. It must stay generic: it should
work for its owner at any employer, and say nothing about any of them. Read this before changing anything.

## 1. Nothing employer- or person-specific, ever

The owner may change workplace. Everything tied to an employer lives in the **local layer**, `~/.claude/local`
(templates in `local/*.example`), which is private and replaceable. This repo carries only what would still be
true at the next job.

- **Never add** company, product, team or service names; GitHub org or repo names other than this one; Jira
  project keys; internal hostnames, URLs or IP ranges; cloud account IDs, ARNs, profile or role names; Slack
  channels; people's names, emails or handles; ticket numbers; paths under a home directory.
- **Remove on sight.** If you find a work-specific identifier already here, move what it does into the local
  layer, or make it generic (a `${TOKEN}` substituted from `local.env`, a profile in `settings/profile.<name>.json`),
  and take the identifier out. Do it in its own commit that says what moved where, without repeating the
  identifier in the message.
- **History counts.** A leaked identifier stays in git history after a later commit removes it. Catch it before it
  is pushed; if it was pushed, tell the owner instead of quietly fixing forward.
- When unsure whether something is specific, treat it as specific and put it in the local layer.

## 2. Machine differences go in profiles or the local layer

Workstations differ (model provider, tools installed, servers). Express a difference as a settings profile
(`settings/profile.<name>.json`, chosen with `./install.sh use <profile>`) or as values in that machine's
`~/.claude/local/local.env`. Do not fork shared files per machine, and do not hard-code one machine's paths.

## 3. Setup on a new clone

1. Point git at the hooks with an **absolute** path (a relative one is lost when git runs with only `--git-dir`):
   `git config core.hooksPath "$(git rev-parse --show-toplevel)/.githooks"`
2. Copy the owner's private-word list to `.scrub-words` in the clone root. It is untracked on purpose. Without it
   the leak scan refuses to pass rather than scan partially; ask the owner for it, never recreate it from guesses.

## 4. How to change things

- Work on a branch and open a **pull request** into `main`. Never push to `main` directly. One change per PR.
- **Test first.** Add or change a check in `tests/` (static, self, hooks suites; hook case tables in
  `tests/hooks/`), run it and see it fail, then make the change.
- `./install.sh test` must end with **0 FAIL and 0 XPASS**. A known gap you cannot close now goes in
  `tests/expected-fail.txt` with the date and the step that fixes it.
- A hook that blocks commands fails closed (`"onFailure": "block"`), so a broken hook stops every session's shell.
  Any hook change needs case-table cases, and must pass `./install.sh test` before it is installed.
- Commit messages say why, cite evidence (check ids, log file names), and carry **no AI attribution trailers**.

## 5. Never bypass the gates without the owner

Do not use `git commit --no-verify`, `git push --no-verify`, `CLAUDE_SETUP_SKIP_CHECKS=1` or
`CLAUDE_SETUP_NO_ONFAILURE=1`, and do not weaken a check, a deny rule or the leak scan to get a change through.
If a gate blocks you, stop and report what blocked and why.

## 6. Secrets

No credentials, tokens or keys in any file, commit message or output, real or "example". The pre-commit and
pre-push scans report hits by file and line only; keep it that way.
