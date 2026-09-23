#!/usr/bin/env bash
# claude-setup — reproduce a Claude Code configuration on this machine.
#
#   ./install.sh install        link, generate and register everything
#   ./install.sh use <profile>  rebuild settings.json against another profile
#   ./install.sh sync           report drift between the live files and the repo
#   ./install.sh doctor         verify the installed state, change nothing
#
# Design: artifacts with one writer are symlinked, so editing the live file
# edits the repo. Artifacts several processes write — settings.json above all,
# which Claude Code and dcg both rewrite — are generated, so drift becomes a
# report instead of a lost edit.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO

# shellcheck source=lib/common.sh
. "$REPO/lib/common.sh"
# shellcheck source=lib/platform.sh
. "$REPO/lib/platform.sh"
# shellcheck source=lib/merge.sh
. "$REPO/lib/merge.sh"
# shellcheck source=lib/links.sh
. "$REPO/lib/links.sh"
# shellcheck source=lib/mcp.sh
. "$REPO/lib/mcp.sh"
# shellcheck source=lib/plugins.sh
. "$REPO/lib/plugins.sh"
# shellcheck source=lib/doctor.sh
. "$REPO/lib/doctor.sh"

# ---------------------------------------------------------------- local layer

fetch_local_layer() {
  [ -n "${CLAUDE_SETUP_LOCAL_REMOTE:-}" ] || return 0
  if [ -d "$LOCAL_DIR/.git" ]; then
    info "updating local layer from its remote"
    git -C "$LOCAL_DIR" pull --ff-only >/dev/null 2>&1 || warn "local layer pull failed"
  else
    [ -e "$LOCAL_DIR" ] && die "$LOCAL_DIR exists and is not a clone; move it aside first"
    info "cloning the private local layer"
    git clone --depth 1 "$CLAUDE_SETUP_LOCAL_REMOTE" "$LOCAL_DIR" >/dev/null 2>&1 \
      || die "could not clone CLAUDE_SETUP_LOCAL_REMOTE"
  fi
  ok "local layer present"
}

# ---------------------------------------------------------------- generators

generate_settings() {
  local profile="${1:-$CLAUDE_PROFILE}"
  local out="$CLAUDE_DIR/settings.json"
  local built
  built="$(build_settings "$profile")" || return 1

  # Compare against the live file with dcg's own hook entry removed. dcg
  # re-stamps that entry at the end of every install, so comparing against the
  # raw file would report a difference every single run and rewrite the file
  # just to have dcg put its entry back — a churn loop, not idempotence.
  if [ -f "$out" ] \
     && diff -q <(strip_dcg_hooks < "$out" | jq -S .) <(printf '%s\n' "$built" | jq -S .) >/dev/null 2>&1
  then
    info "settings.json already current (profile: $profile)"
    return 0
  fi

  printf '%s\n' "$built" | write_if_changed "$out" >/dev/null
  ok "settings.json built (profile: $profile)"
}

generate_claude_md() {
  local out="$CLAUDE_DIR/CLAUDE.md" tmp
  tmp="$(mktemp)"
  cat "$REPO/claude/CLAUDE.md" > "$tmp"
  if [ -f "$LOCAL_DIR/CLAUDE.work.md" ]; then
    printf '\n' >> "$tmp"
    cat "$LOCAL_DIR/CLAUDE.work.md" >> "$tmp"
  else
    info "no local/CLAUDE.work.md — global prefs will be the public half only"
  fi
  if write_if_changed "$out" < "$tmp"; then
    ok "CLAUDE.md generated ($(wc -l < "$out" | tr -d ' ') lines)"
  else
    info "CLAUDE.md already current"
  fi
  rm -f "$tmp"
}

# Same shape as generate_claude_md: public template plus an optional private
# overlay. ~/Projects is a convention, not a requirement — absent means skip.
generate_projects_md() {
  local base="$REPO/claude/projects-CLAUDE.md"
  [ -f "$base" ] || { warn "no claude/projects-CLAUDE.md in repo"; return 0; }
  [ -d "$HOME/Projects" ] || { info "no ~/Projects on this machine — skipping"; return 0; }
  local out="$HOME/Projects/CLAUDE.md" tmp
  tmp="$(mktemp)"
  cat "$base" > "$tmp"
  if [ -f "$LOCAL_DIR/projects-CLAUDE.work.md" ]; then
    printf '\n' >> "$tmp"
    cat "$LOCAL_DIR/projects-CLAUDE.work.md" >> "$tmp"
  else
    info "no local/projects-CLAUDE.work.md — ~/Projects/CLAUDE.md is the public half only"
  fi
  if write_if_changed "$out" < "$tmp"; then
    ok "~/Projects/CLAUDE.md generated ($(wc -l < "$out" | tr -d ' ') lines)"
  else
    info "~/Projects/CLAUDE.md already current"
  fi
  rm -f "$tmp"
}

generate_jira_defaults() {
  local out="$CLAUDE_DIR/jira-defaults.json"
  [ -n "${JIRA_PROJECT_KEY:-}" ] || { info "no JIRA_PROJECT_KEY — skipping jira-defaults.json"; return 0; }
  if jq -n --arg k "$JIRA_PROJECT_KEY" --arg w "$GITS_DIR" \
       '{defaultProjectKey: $k, workspaceDir: $w}' | write_if_changed "$out"; then
    ok "jira-defaults.json written"
  else
    info "jira-defaults.json already current"
  fi
}

generate_dcg_config() {
  [ -f "$REPO/dcg/config.toml" ] || return 0
  local out="${XDG_CONFIG_HOME:-$HOME/.config}/dcg/config.toml"
  if write_if_changed "$out" < "$REPO/dcg/config.toml"; then ok "dcg config written"; else info "dcg config already current"; fi
}

# dcg must run LAST. It rewrites settings.json to carry its own resolved
# absolute path, so anything that regenerates settings.json afterwards would
# undo it.
register_dcg_hook() {
  [ -n "$DCG" ] || { info "dcg absent — no destructive-command guard installed"; return 0; }
  if "$DCG" install --force >/dev/null 2>&1; then
    ok "dcg hook registered by dcg itself"
  else
    warn "dcg install --force failed — run it by hand"
  fi
}

# ---------------------------------------------------------------- commands

cmd_install() {
  step "Platform"
  detect_platform
  check_tools

  step "Local layer"
  fetch_local_layer
  load_local_env

  step "Links"
  install_links
  install_skills

  step "Generated files"
  generate_settings "$CLAUDE_PROFILE"
  generate_claude_md
  generate_projects_md
  generate_jira_defaults
  generate_dcg_config

  step "Plugins"
  install_plugins

  step "MCP servers"
  install_mcp

  step "Guard"
  register_dcg_hook

  printf '\n'
  if [ "$FAILURES" -gt 0 ]; then
    printf '%sinstall finished with %d failure(s), %d warning(s)%s\n' "$C_ERR" "$FAILURES" "$WARNINGS" "$C_OFF"
    printf 'Backups, if any: %s\n' "$BACKUP_DIR"
    return 1
  fi
  printf '%sinstall complete%s (%d warning(s)). Next: ./install.sh doctor\n' "$C_OK" "$C_OFF" "$WARNINGS"
  [ -d "$BACKUP_DIR" ] && printf 'Replaced files backed up to %s\n' "$BACKUP_DIR"
  return 0
}

cmd_use() {
  local profile="${1:-}"
  [ -n "$profile" ] || die "usage: ./install.sh use <profile>"
  load_local_env
  detect_platform >/dev/null
  check_tools >/dev/null 2>&1
  generate_settings "$profile"
  register_dcg_hook
  say ""
  say "Profile '$profile' active. Restart Claude Code to pick it up."
  say "Make it permanent by setting CLAUDE_PROFILE=$profile in $LOCAL_DIR/local.env"
}

# Rebuild into a buffer and diff against the live file. This is how drift gets
# noticed: Claude Code writes theme, output style and every "always allow" into
# settings.json, and dcg repairs its own hook entry. Neither is an error; both
# should be promoted into the repo deliberately rather than discovered later.
cmd_sync() {
  load_local_env
  detect_platform >/dev/null
  check_tools >/dev/null 2>&1

  local live="$CLAUDE_DIR/settings.json"
  [ -f "$live" ] || die "no $live — run ./install.sh install"

  local a b
  a="$(mktemp)"; b="$(mktemp)"
  strip_dcg_hooks < "$live" | jq -S . > "$a"
  build_settings "$CLAUDE_PROFILE" | jq -S . > "$b"

  step "settings.json drift (live vs repo, dcg's own hook ignored)"
  if diff -u "$b" "$a" > /dev/null; then
    ok "no drift"
  else
    diff -u --label "repo (would build)" --label "live (on disk)" "$b" "$a" | sed 's/^/  /'
    say ""
    say "Lines marked + exist only in the live file. Promote the ones you want into"
    say "  settings/base.json      (generic, public)"
    say "  $LOCAL_DIR/settings.work.json   (org-specific, private)"
  fi
  rm -f "$a" "$b"

  step "Links"
  local line src dst
  for line in $LINKED_FILES; do
    src="${line%%|*}"; dst="$CLAUDE_DIR/${line##*|}"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      warn "$dst is a regular file — it should be a link into the repo"
      diff -u "$REPO/$src" "$dst" | sed 's/^/    /' || true
    fi
  done
  ok "link check done"
}

usage() {
  sed -n '2,13p' "$REPO/install.sh" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  install|"") cmd_install ;;
  use)        shift; cmd_use "$@" ;;
  sync)       cmd_sync ;;
  doctor)     doctor ;;
  -h|--help|help) usage ;;
  *)          usage; exit 1 ;;
esac
