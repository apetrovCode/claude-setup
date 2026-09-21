#!/usr/bin/env bash
# Platform and tool discovery. Nothing here hardcodes an install prefix: the
# repo is developed on Apple Silicon and deployed on Linux, so every tool is
# resolved through `command -v` and every absent tool is reported rather than
# assumed.

detect_platform() {
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS" in
    Darwin) PLATFORM=macos ;;
    Linux)  PLATFORM=linux ;;
    *)      PLATFORM=unknown ;;
  esac
  if [ "$PLATFORM" = linux ] && grep -qi microsoft /proc/version 2>/dev/null; then
    PLATFORM=wsl
  fi
  info "platform: $PLATFORM ($OS/$ARCH)"
}

# Required: the installer cannot do its job without these.
REQUIRED_TOOLS="jq git claude"
# Optional: each one degrades a specific feature, named in the warning.
# shellcheck disable=SC2034
OPTIONAL_TOOLS="gh mempalace mempalace-mcp terraform-mcp-server dcg actionlint zizmor"

check_tools() {
  local missing=""
  for t in $REQUIRED_TOOLS; do
    have "$t" || missing="$missing $t"
  done
  [ -n "$missing" ] && die "missing required tools:$missing"

  have gh                   || warn "gh not found — the github MCP server will not authenticate"
  have mempalace            || warn "mempalace not found — the 4 memory hooks will fail on every session (uv tool install mempalace)"
  have mempalace-mcp        || warn "mempalace-mcp not found — the mempalace MCP server will not start"
  have actionlint           || warn "actionlint not found — workflow edits are not syntax-linted"
  have zizmor               || warn "zizmor not found — workflow edits are not security-linted"

  if have terraform-mcp-server; then
    TERRAFORM_MCP_SERVER="$(command -v terraform-mcp-server)"
    info "terraform-mcp-server: $TERRAFORM_MCP_SERVER"
  else
    TERRAFORM_MCP_SERVER=""
    warn "terraform-mcp-server not found — the terraform MCP server will be skipped"
  fi

  if have dcg; then
    DCG="$(command -v dcg)"
    info "dcg: $DCG"
  else
    DCG=""
    warn "dcg not found — NO destructive-command guard on this machine."
    warn "  dcg is distributed as a standalone binary; see README 'Known gaps'."
  fi
}
