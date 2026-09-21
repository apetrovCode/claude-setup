# claude-setup

My [Claude Code](https://claude.com/claude-code) configuration, in a form that rebuilds itself on
another machine: settings, hooks, a statusline, skills, MCP servers and plugin declarations.

Developed on macOS, deployed on Linux. Nothing here hardcodes an install prefix.

```bash
git clone https://github.com/apetrovCode/claude-setup ~/gits/claude-setup
cd ~/gits/claude-setup
./bootstrap-linux.sh     # Linux only: installs jq, gh, uv, mempalace, the linters
./install.sh install
./install.sh doctor
```

## What it does

| Command | Effect |
|---|---|
| `./install.sh install` | Links, generates and registers everything. Idempotent. |
| `./install.sh use <profile>` | Rebuilds `settings.json` against another profile. |
| `./install.sh sync` | Reports drift between the live files and the repo. Changes nothing. |
| `./install.sh doctor` | Verifies the installed state. Changes nothing. |

## How it is put together

**Two layers.** This repo is the public one. Everything organization-specific lives in
`~/.claude/local/`, outside this tree, and is never committed. The installer merges the two.
`local/` here holds only templates. See [local/README.md](local/README.md).

The local layer sits outside the working tree rather than inside it as an ignored directory.
That removes the class of accident where a `git add -f` or a mistyped ignore rule publishes it.

**Some files are linked, some are generated.** The split is by how many processes write the file.

Linked, so editing the live file edits the repo: the hook scripts, the statusline, the MCP header
helper, and every vendored skill. Each has exactly one writer. Skills are linked to exactly
`~/.claude/skills/<name>`, because skills resolve each other by that path.

Generated, because several processes write them: `settings.json`, `~/.claude/CLAUDE.md`,
`~/Projects/CLAUDE.md`, `jira-defaults.json`. Claude Code writes the theme, the output style and
every "always allow" into `settings.json`, and the `dcg` guard rewrites its own hook entry on
every invocation. A symlink there would either sit permanently dirty or be silently replaced by a
regular file the first time a writer did write-to-temp-then-rename. Generating it makes drift a
report — `./install.sh sync` — instead of a lost edit.

**Settings merge additively.** `jq`'s `*` operator replaces arrays, which would drop every
permission rule the moment a fragment mentioned `permissions`. `lib/merge.sh` unions arrays in
order instead, and asserts afterwards that the allow list did not shrink.

Fragments, merged in order:

```
settings/base.json        generic env, permissions, statusline, theme
settings/hooks.json       memory hooks, credential guard, workflow linter
settings/plugins.json     enabled plugins and extra marketplaces
settings/profile.<p>.json the active profile
~/.claude/local/settings.work.json   org-specific, private
```

**The guard installs itself.** `dcg` insists on a resolved absolute path in its hook entry and
repairs `settings.json` whenever it disagrees, so the repo does not store that entry at all. The
installer runs `dcg install --force` last and lets `dcg` write its own. `sync` and `doctor`
ignore it when diffing.

**MCP servers** are registered with `claude mcp add-json --scope user`, looped over
[mcp/servers.json](mcp/servers.json). `add-json` rather than `add`, because the GitHub server
needs a `headersHelper` and plain `add` has no flag for it. Project-scope `.mcp.json` cannot
express a user-global server, so it was not used.

**Skills** come in two kinds. Seven have no upstream and are vendored here as real directories.
The other eight are upstream-owned and are recorded in `skills/skill-lock.json` by pinned git ref,
so they get refetched rather than forked.

## Secrets

No credential is stored in this repo, and none is stored on disk by anything it installs. The
GitHub MCP token is minted per call by `claude/bin/gh-mcp-headers.sh` shelling out to `gh`.

Two layers of protection:

- `.gitignore` is an **allowlist** — deny everything, then re-admit known paths. Unknown files
  fail closed.
- `.githooks/pre-commit` scans staged content for home paths, credential shapes, and any word in
  an untracked personal `.scrub-words` file. Enable it with `git config core.hooksPath .githooks`.

## Known gaps

Things this repo deliberately cannot reproduce:

- **`dcg`**, the destructive-command guard, is a standalone binary with no recorded package
  source. Its pack config is here; the binary is not. A machine without it has no guard, and
  `doctor` says so.
- **macOS desktop-app MCP extensions** (Chrome control, osascript, PDF viewer, AWS API,
  filesystem) are registered by the desktop app, not the CLI.
- **claude.ai connectors** are account-side. Re-enable them in connector settings.
- **Interactive OAuth** for the Atlassian and Slack MCP servers, once per machine, via `/mcp`.
- **MemPalace data.** The CLI installs from PyPI and the hooks are here, but the palace itself is
  local, large, and holds machine identity. Only the plumbing travels.
- **Two vendored skills have missing dependencies** and were already broken before this repo
  existed: `caveman-stats` needs a tracker hook that exists nowhere, and `cavecrew` dispatches to
  three subagents with no definitions. Details in [skills/README.md](skills/README.md).

## Layout

```
install.sh            entrypoint
bootstrap-linux.sh    dependency install for Debian/Ubuntu and Fedora/RHEL
lib/                  common, platform, merge, links, mcp, plugins, doctor
settings/             settings.json fragments
claude/               CLAUDE.md, hooks, statusline, MCP header helper
skills/               7 vendored skills + the lockfile for 8 upstream ones
mcp/servers.json      user-scope MCP server manifest
dcg/config.toml       guard pack configuration
local/                templates for the private layer
```
