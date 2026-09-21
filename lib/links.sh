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
  mkdir -p "$(dirname "$dest")"

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

  ln -s "$src" "$dest"
  return 0
}

LINKED_FILES="
claude/hooks/no-cred-output.sh|hooks/no-cred-output.sh
claude/hooks/gha-lint.sh|hooks/gha-lint.sh
claude/bin/gh-mcp-headers.sh|bin/gh-mcp-headers.sh
claude/statusline-command.sh|statusline-command.sh
"

install_links() {
  local n=0
  local line src dst
  for line in $LINKED_FILES; do
    src="${line%%|*}"; dst="${line##*|}"
    link_one "$src" "$CLAUDE_DIR/$dst" && n=$((n + 1))
  done
  chmod +x "$REPO"/claude/hooks/*.sh "$REPO"/claude/bin/*.sh "$REPO"/claude/statusline-command.sh 2>/dev/null || true
  ok "$n shell artifacts linked"

  # Org-specific hooks live in the local layer and are used in place.
  if [ -d "$LOCAL_DIR/hooks" ]; then
    chmod +x "$LOCAL_DIR"/hooks/*.sh 2>/dev/null || true
    info "local hooks: $(find "$LOCAL_DIR/hooks" -name '*.sh' | wc -l | tr -d ' ')"
  fi
}

install_skills() {
  local n=0 s
  mkdir -p "$CLAUDE_DIR/skills"
  for s in "$REPO"/skills/*/; do
    [ -d "$s" ] || continue
    link_one "skills/$(basename "$s")" "$CLAUDE_DIR/skills/$(basename "$s")" && n=$((n + 1))
  done
  ok "$n vendored skills linked"

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
