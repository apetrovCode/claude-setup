#!/usr/bin/env bash
# Add the marketplaces, then install the plugins named in settings/plugins.json.
#
# `enabledPlugins` in settings.json is what actually turns them on; these calls
# make sure the code is present locally so the flag has something to enable.

install_plugins() {
  local spec="$REPO/settings/plugins.json"
  [ -f "$spec" ] || { warn "no settings/plugins.json"; return 0; }

  # Marketplaces first — a plugin cannot install from one that is not known.
  # claude-plugins-official is auto-installed by Claude Code, so only the extras
  # are declared in the repo.
  local url n=0
  while read -r url; do
    [ -n "$url" ] || continue
    if claude plugin marketplace add "$url" >/dev/null 2>&1; then
      n=$((n + 1))
    else
      info "marketplace already present or unreachable: $url"
    fi
  done <<< "$(jq -r '.extraKnownMarketplaces // {} | to_entries[] | .value.source.url // .value.source.repo // empty' "$spec")"
  ok "$n extra marketplaces ensured"

  local installed=0 failed=0 p
  while read -r p; do
    [ -n "$p" ] || continue
    if claude plugin install "$p" >/dev/null 2>&1; then
      installed=$((installed + 1))
    else
      # Already installed is the common case here and is not a failure.
      if claude plugin details "${p%%@*}" >/dev/null 2>&1; then
        installed=$((installed + 1))
      else
        warn "plugin failed to install: $p"
        failed=$((failed + 1))
      fi
    fi
  done <<< "$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | .key' "$spec")"

  ok "$installed plugins present${failed:+, $failed failed}"
  return 0
}
