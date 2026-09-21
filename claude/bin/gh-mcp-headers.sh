#!/usr/bin/env bash
# headersHelper for the `github` MCP server. Mints a token per call; nothing is
# stored on disk.
#
# The account is explicit on purpose. With more than one account logged in,
# omitting `-u` binds the MCP to whatever `gh auth switch` last selected, which
# silently changes which org's repos the server can see. Set GH_MCP_ACCOUNT in
# ~/.claude/local/local.env to pin it.
[ -r "$HOME/.claude/local/local.env" ] && . "$HOME/.claude/local/local.env"

host="${GH_MCP_HOST:-github.com}"

if [ -n "$GH_MCP_ACCOUNT" ]; then
  token=$(gh auth token -h "$host" -u "$GH_MCP_ACCOUNT" 2>/dev/null)
else
  # No pin: fall back to the active account and say so, once, on stderr.
  echo "gh-mcp-headers: GH_MCP_ACCOUNT unset, using the active gh account" >&2
  token=$(gh auth token -h "$host" 2>/dev/null)
fi

if [ -z "$token" ]; then
  echo "gh-mcp-headers: no gh token for host=$host account=${GH_MCP_ACCOUNT:-<active>}" >&2
  exit 1
fi

printf '{"Authorization":"Bearer %s"}\n' "$token"
