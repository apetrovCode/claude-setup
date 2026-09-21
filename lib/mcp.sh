#!/usr/bin/env bash
# Register the user-scope MCP servers.
#
# `claude mcp add-json` rather than `claude mcp add`, because the github server
# carries a `headersHelper` and plain `add` has no flag for it.
#
# Project-scope .mcp.json was rejected: it cannot express a user-global server,
# and it would have to be committed into every repo to take effect.

install_mcp() {
  local manifest="$REPO/mcp/servers.json"
  [ -f "$manifest" ] || { warn "no mcp/servers.json"; return 0; }

  local names name json added=0 skipped=0
  names="$(jq -r '.servers | keys[]' "$manifest")"

  for name in $names; do
    # Skip servers whose binary is absent rather than registering one that
    # fails to start on every session.
    local need
    need="$(jq -r --arg n "$name" '.requiresBinary[$n] // empty' "$manifest")"
    if [ -n "$need" ] && ! have "$need"; then
      warn "mcp $name skipped — $need not installed"
      skipped=$((skipped + 1))
      continue
    fi

    json="$(jq -c --arg n "$name" '.servers[$n]' "$manifest" | subst_tokens)"

    if claude mcp get "$name" >/dev/null 2>&1; then
      # Re-register so an edited manifest actually takes effect.
      claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
    fi

    if claude mcp add-json "$name" "$json" --scope user >/dev/null 2>&1; then
      added=$((added + 1))
    else
      bad "mcp $name failed to register"
    fi
  done

  ok "$added MCP servers registered${skipped:+, $skipped skipped}"

  local oauth
  oauth="$(jq -r '.needsInteractiveAuth[]?' "$manifest" | tr '\n' ' ')"
  [ -n "$oauth" ] && info "needs an interactive /mcp login: $oauth"
  return 0
}
