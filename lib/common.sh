#!/usr/bin/env bash
# Shared paths, logging and token substitution. Sourced by install.sh.

REPO="${REPO:?REPO must be set by install.sh}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LOCAL_DIR="$CLAUDE_DIR/local"
BACKUP_DIR="$CLAUDE_DIR/backups/claude-setup-$(date +%Y%m%d-%H%M%S)"

WARNINGS=0
FAILURES=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'
  C_DIM=$'\033[2m';   C_BOLD=$'\033[1m';    C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==>%s %s%s%s\n' "$C_BOLD" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
info() { printf '  %s·%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
bad()  { printf '  %s✗%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; FAILURES=$((FAILURES + 1)); }
die()  { printf '\n%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Load the per-machine values. Absent is fine; every consumer has a default.
load_local_env() {
  if [ -r "$LOCAL_DIR/local.env" ]; then
    # shellcheck disable=SC1091
    . "$LOCAL_DIR/local.env"
    info "loaded $LOCAL_DIR/local.env"
  else
    info "no local.env (template: local/local.env.example)"
  fi
  CLAUDE_PROFILE="${CLAUDE_PROFILE:-default}"
  GITS_DIR="${GITS_DIR:-$HOME/gits}"
}

# Replace the install-time tokens on stdin.
subst_tokens() {
  sed -e "s|\${CLAUDE_DIR}|${CLAUDE_DIR}|g" \
      -e "s|\${TERRAFORM_MCP_SERVER}|${TERRAFORM_MCP_SERVER:-terraform-mcp-server}|g" \
      -e "s|\${BEDROCK_AWS_PROFILE}|${BEDROCK_AWS_PROFILE:-}|g" \
      -e "s|\${GITS_DIR}|${GITS_DIR:-$HOME/gits}|g" \
      -e "s|\${JIRA_PROJECT_KEY}|${JIRA_PROJECT_KEY:-}|g"
}

backup() {
  [ -e "$1" ] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -a "$1" "$BACKUP_DIR/$(basename "$1")" 2>/dev/null || true
}

# Write stdin to $1 atomically, but only if the content actually differs.
# Returns 0 when it wrote, 1 when it was already correct — so install is idempotent
# and says so.
write_if_changed() {
  local dest="$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi
  backup "$dest"
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  return 0
}
