#!/usr/bin/env bash
# Symlink the single-writer artifacts into place.
#
# These files have exactly one writer — you — so linking them means editing the
# live file is editing the repo. settings.json and the CLAUDE.md files are NOT
# here: several processes write those, so they are generated instead.
#
# Skills must land at exactly ~/.claude/skills/<name>, because skills resolve
# each other by that path.

# link_one <repo-relative source> <absolute destination>
link_one() {
  local src="$REPO/$1" dest="$2"
  [ -e "$src" ] || { warn "missing in repo: $1"; return 1; }
  mkdir -p "$(dirname "$dest")" || { bad "cannot create $(dirname "$dest")"; return 1; }

  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$src" ]; then
      return 0                       # already correct
    fi
    rm -f "$dest"
  elif [ -e "$dest" ]; then
    # A real file where a link belongs. Never silently discard it.
    if diff -rq "$src" "$dest" >/dev/null 2>&1; then
      rm -rf "$dest"
    else
      backup "$dest"
      warn "$dest differed from the repo — backed up to $BACKUP_DIR"
      rm -rf "$dest"
    fi
  fi

  # Report what actually happened. Returning 0 unconditionally here made the
  # installer claim "4 artifacts linked" on a machine where every ln failed.
  if ! ln -s "$src" "$dest" 2>/dev/null; then
    bad "could not link $dest -> $src"
    return 1
  fi
  return 0
}

# Hooks are not here: install_hooks copies them (see below).
LINKED_FILES="
claude/agents/reader.md|agents/reader.md
claude/bin/gh-mcp-headers.sh|bin/gh-mcp-headers.sh
claude/statusline-command.sh|statusline-command.sh
"

install_links() {
  local n=0 total=0
  local line src dst
  for line in $LINKED_FILES; do
    src="${line%%|*}"; dst="${line##*|}"
    total=$((total + 1))
    link_one "$src" "$CLAUDE_DIR/$dst" && n=$((n + 1))
  done
  chmod +x "$REPO"/claude/bin/*.sh "$REPO"/claude/statusline-command.sh 2>/dev/null || true
  if [ "$n" -eq "$total" ]; then
    ok "$n shell artifacts linked"
  else
    bad "$n of $total shell artifacts linked"
  fi

  # Org-specific hooks live in the local layer and are used in place.
  if [ -d "$LOCAL_DIR/hooks" ]; then
    chmod +x "$LOCAL_DIR"/hooks/*.sh 2>/dev/null || true
    info "local hooks: $(find "$LOCAL_DIR/hooks" -name '*.sh' | wc -l | tr -d ' ')"
  fi

  # A dcg allowlist kept in the local layer replaces the live one: copied, not linked,
  # with the replaced file backed up. dcg reads it from the platform config directory.
  if [ -f "$LOCAL_DIR/dcg/allowlist.toml" ]; then
    local live
    case "$(uname -s)" in
      Darwin) live="$HOME/Library/Application Support/dcg/allowlist.toml" ;;
      *)      live="${XDG_CONFIG_HOME:-$HOME/.config}/dcg/allowlist.toml" ;;
    esac
    if cmp -s "$LOCAL_DIR/dcg/allowlist.toml" "$live"; then
      info "dcg allowlist: managed copy already live"
    elif mkdir -p "$(dirname "$live")" && backup "$live" && cp "$LOCAL_DIR/dcg/allowlist.toml" "$live"; then
      ok "dcg allowlist installed from the local layer"
    else
      bad "could not install the dcg allowlist from the local layer"
    fi
  fi
}

# Public hooks are COPIED, not linked. A link into this working tree changes the
# moment the checkout switches branches, so an untested branch would be guarding
# every session. They are copied only after the hooks suite passes (cmd_install
# runs it and sets HOOKS_SUITE_RC; without it this runs the suite itself); if it
# failed, the live hooks stay exactly as they were. Each copy lands atomically:
# hooks run concurrently with this.
install_hooks() {
  local f name dest tmp n=0 total=0 rc="${HOOKS_SUITE_RC:-}"
  if [ -z "$rc" ]; then
    bash "$REPO/tests/run.sh" --public-only hooks >/dev/null 2>&1
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    bad "hooks suite failed: live hooks left as they were (see: bash tests/run.sh hooks)"
    return 1
  fi
  mkdir -p "$CLAUDE_DIR/hooks" || { bad "cannot create $CLAUDE_DIR/hooks"; return 1; }
  for f in "$REPO"/claude/hooks/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"; dest="$CLAUDE_DIR/hooks/$name"; total=$((total + 1))
    [ -L "$dest" ] && rm -f "$dest"
    if cmp -s "$f" "$dest" && [ -x "$dest" ]; then n=$((n + 1)); continue; fi
    [ -e "$dest" ] && backup "$dest"
    tmp="$dest.tmp.$$"
    if cp "$f" "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$dest"; then
      n=$((n + 1))
    else
      rm -f "$tmp"; bad "could not copy $name"
    fi
  done
  if [ "$n" -eq "$total" ]; then ok "$n hooks copied (hooks suite passed)"; else return 1; fi
}

install_skills() {
  local n=0 total=0 s
  mkdir -p "$CLAUDE_DIR/skills" || { bad "cannot create $CLAUDE_DIR/skills"; return 1; }
  for s in "$REPO"/skills/*/; do
    [ -d "$s" ] || continue
    total=$((total + 1))
    link_one "skills/$(basename "$s")" "$CLAUDE_DIR/skills/$(basename "$s")" && n=$((n + 1))
  done
  if [ "$n" -eq "$total" ]; then
    ok "$n vendored skills linked"
  else
    bad "$n of $total vendored skills linked"
  fi

  # The other skills are upstream-owned; carry the lockfile so they can be
  # refetched at their pinned refs rather than vendored into this repo.
  if [ -f "$REPO/skills/skill-lock.json" ]; then
    mkdir -p "$HOME/.agents"
    if write_if_changed "$HOME/.agents/.skill-lock.json" < "$REPO/skills/skill-lock.json"; then
      ok "skill-lock.json installed ($(jq '.skills | length' "$REPO/skills/skill-lock.json") upstream skills)"
    else
      info "skill-lock.json already current"
    fi
  fi
}
