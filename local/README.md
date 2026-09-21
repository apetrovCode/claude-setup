# The local layer

Everything in this directory is a **template**. The real files live at `~/.claude/local/`,
outside this repo's working tree, and are never committed.

That separation is deliberate. This repo is public, and the live local layer holds employer
context: organization and account names, internal service names, ticket prefixes, sensitive
file locations. Keeping it outside the tree removes the class of accident where a `git add -f`
or a mistyped ignore rule publishes it.

## Files

| Template | Real location | Holds |
|---|---|---|
| `local.env.example` | `~/.claude/local/local.env` | Per-machine values: GitHub account, clone dir, Jira key, active profile |
| `settings.work.json.example` | `~/.claude/local/settings.work.json` | Settings merged on top of the public ones: extra permission rules, extra hooks, the autoMode environment block |
| `CLAUDE.work.md.example` | `~/.claude/local/CLAUDE.work.md` | Appended to the public `CLAUDE.md` to form `~/.claude/CLAUDE.md` |
| — | `~/.claude/local/projects-CLAUDE.md` | Copied verbatim to `~/Projects/CLAUDE.md` |
| — | `~/.claude/local/hooks/*.sh` | Hook scripts too org-specific to publish |

`install.sh` works without any of them. It reports which are missing and installs the
public half alone.

## Carrying the local layer to another machine

By design it does not travel with this repo. Three options, in increasing convenience:

1. **Retype it.** The templates here are the outline.
2. **Copy it out of band** — an encrypted archive, a password manager attachment, `scp`.
3. **Point the installer at a private repo.** Set `CLAUDE_SETUP_LOCAL_REMOTE` to a private
   git URL and `install.sh` clones it into `~/.claude/local/` instead of expecting the files
   by hand. This public repo never learns anything about it.

```bash
CLAUDE_SETUP_LOCAL_REMOTE=git@github.com:<you>/claude-setup-local.git ./install.sh install
```
