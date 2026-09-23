# Skills

Two kinds live here, and the installer treats them differently.

**Vendored** — the seven `caveman*` and `cavecrew` directories. They come from
[JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman), but were installed without a
lockfile entry, so this is a snapshot rather than a pin. Upstream has since moved on (Windows
support, more skills). The snapshot is committed as-is and `install.sh` symlinks each one to
`~/.claude/skills/<name>`. That exact path matters: skills resolve each other by it.

To track upstream instead, add them to `skill-lock.json` with `skillPath: skills/<name>/SKILL.md`
and drop the vendored copies.

**Upstream** — eight more, recorded in `skill-lock.json` by pinned git ref rather than forked
into this repo:

| Source | Skills |
|---|---|
| `github/awesome-copilot` | the three `github-actions-*` skills |
| `hashicorp/agent-skills` | `refactor-module`, `terraform-policy`, `terraform-search-import`, `terraform-style-guide`, `terraform-test` |

The installer copies `skill-lock.json` to `~/.agents/.skill-lock.json`; the skill manager fetches
them from there.

## Two vendored skills have missing dependencies

Both were already broken before this repo existed. They are carried as-is rather than silently
deleted, but neither works until its dependency is supplied.

**`caveman-stats`** expects `hooks/caveman-mode-tracker.js` and `hooks/caveman-stats.js` to
intercept `/caveman-stats` and return the numbers as a blocked-decision reason. Neither file
exists anywhere on the machine this repo was built from. The skill triggers and then does
nothing.

**`cavecrew`** dispatches to three subagents — `cavecrew-investigator`, `cavecrew-builder` and
`cavecrew-reviewer`. No agent definitions exist at user scope, and the Claude Code desktop Code
tab does not offer them either. Use the built-in `Explore` agent with a caveman-style prompt
instead, or write the three agent definitions into `~/.claude/agents/`.

`install.sh doctor` does not fail on either, because a skill with a missing optional dependency
is a degraded feature rather than a broken install.
