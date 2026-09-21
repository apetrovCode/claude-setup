#!/usr/bin/env bash
# Verify the installed state. Read-only: doctor never repairs, it reports.

doctor() {
  FAILURES=0
  WARNINGS=0
  local live="$CLAUDE_DIR/settings.json"

  step "Platform"
  detect_platform
  check_tools

  step "Settings"
  if [ ! -f "$live" ]; then
    bad "no $live — run ./install.sh install"
  elif ! jq empty "$live" 2>/dev/null; then
    bad "$live is not valid JSON"
  else
    local want got
    want="$(jq '.permissions.allow | length' "$REPO/settings/base.json")"
    got="$(jq '.permissions.allow | length' "$live")"
    if [ "$got" -ge "$want" ]; then
      ok "permission rules: $got allow / $(jq '.permissions.deny|length' "$live") deny / $(jq '.permissions.ask|length' "$live") ask"
    else
      bad "allow rules shrank: repo has $want, live has $got"
    fi

    # Every hook group the repo declares must still be present. dcg rewrites
    # settings.json on every invocation, and this is where that would show up
    # as damage rather than as a harmless extra entry.
    local ev n_repo n_live
    for ev in $(jq -r '.hooks | keys[]' "$REPO/settings/hooks.json"); do
      n_repo="$(jq --arg e "$ev" '.hooks[$e] | map(.hooks[]) | length' "$REPO/settings/hooks.json")"
      n_live="$(strip_dcg_hooks < "$live" | jq --arg e "$ev" '(.hooks[$e] // []) | map(.hooks[]) | length')"
      if [ "$n_live" -ge "$n_repo" ]; then
        ok "hooks.$ev: $n_live registered (repo declares $n_repo)"
      else
        bad "hooks.$ev: live has $n_live, repo declares $n_repo — an entry was lost"
      fi
    done

    if [ -n "$DCG" ]; then
      if jq -e '[.. | objects | select(has("command")) | .command] | any(test("dcg"))' "$live" >/dev/null 2>&1; then
        ok "dcg hook registered"
      else
        warn "dcg is installed but not registered — run: dcg install --force"
      fi
    fi
  fi

  step "Links"
  local line src dst broken=0 total=0
  for line in $LINKED_FILES; do
    src="${line%%|*}"; dst="$CLAUDE_DIR/${line##*|}"
    total=$((total + 1))
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$REPO/$src" ]; then :
    elif [ -L "$dst" ]; then bad "$dst points outside the repo: $(readlink "$dst")"; broken=$((broken + 1))
    elif [ -e "$dst" ]; then bad "$dst is a regular file, not a link into the repo"; broken=$((broken + 1))
    else bad "$dst missing"; broken=$((broken + 1))
    fi
  done
  [ "$broken" -eq 0 ] && ok "$total shell artifacts linked correctly"

  step "Skills"
  local want_skills live_skills
  want_skills="$(find "$REPO/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
  live_skills="$(find "$CLAUDE_DIR/skills" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$live_skills" -ge "$want_skills" ]; then
    ok "$live_skills skills at ~/.claude/skills ($want_skills vendored by this repo)"
  else
    bad "only $live_skills skills installed, expected at least $want_skills"
  fi
  local s
  for s in "$REPO"/skills/*/; do
    [ -d "$s" ] || continue
    [ -f "$s/SKILL.md" ] || bad "skills/$(basename "$s") has no SKILL.md"
  done

  step "MCP servers"
  if have claude; then
    local expect got_n
    expect="$(jq -r '.servers | keys | length' "$REPO/mcp/servers.json")"
    got_n="$(claude mcp list 2>/dev/null | grep -cE '^[a-zA-Z0-9_-]+:' || true)"
    info "$got_n registered, repo declares $expect"
    claude mcp list 2>/dev/null | sed 's/^/    /' || true
  fi

  step "Plugins"
  local pexpect
  pexpect="$(jq -r '.enabledPlugins | length' "$REPO/settings/plugins.json")"
  info "repo declares $pexpect enabled plugins"
  claude plugin list 2>/dev/null | sed 's/^/    /' || info "(claude plugin list unavailable)"

  step "Local layer"
  if [ -d "$LOCAL_DIR" ]; then
    local f
    for f in local.env settings.work.json CLAUDE.work.md projects-CLAUDE.md; do
      if [ -e "$LOCAL_DIR/$f" ]; then ok "local/$f"; else info "local/$f absent (optional)"; fi
    done
  else
    info "no local layer — public config only"
  fi

  step "Leak scan"
  scrub_check

  step "Known gaps"
  [ -z "$DCG" ] && info "no destructive-command guard (dcg is a standalone binary, not in this repo)"
  [ "$PLATFORM" != macos ] && info "macOS desktop-app MCP extensions are not reproducible here"
  info "claude.ai connectors are account-side: re-enable them in connector settings"

  printf '\n'
  if [ "$FAILURES" -gt 0 ]; then
    printf '%sdoctor: %d failure(s), %d warning(s)%s\n' "$C_ERR" "$FAILURES" "$WARNINGS" "$C_OFF"
    return 1
  fi
  printf '%sdoctor: OK%s (%d warning(s))\n' "$C_OK" "$C_OFF" "$WARNINGS"
  return 0
}

# Refuse to let machine-specific or employer-specific strings reach the public
# tree. Same checks the pre-commit hook runs, so `doctor` catches them earlier.
scrub_check() {
  local hits=0 pat
  local tracked
  tracked="$(cd "$REPO" && git ls-files 2>/dev/null)"
  [ -z "$tracked" ] && { info "nothing tracked yet"; return 0; }

  for pat in "$(printf '/Users/%s' "$(id -un)")" 'ghp_' 'gho_' 'github_pat_' 'AKIA' 'ASIA' 'xoxb-' 'sk-ant-' '-----BEGIN'; do
    if (cd "$REPO" && printf '%s\n' "$tracked" | xargs grep -l -F -- "$pat" 2>/dev/null | grep -q .); then
      bad "tracked files contain '$pat':"
      (cd "$REPO" && printf '%s\n' "$tracked" | xargs grep -l -F -- "$pat" 2>/dev/null | sed 's/^/      /')
      hits=$((hits + 1))
    fi
  done

  if [ -f "$REPO/.scrub-words" ]; then
    while read -r pat; do
      [ -n "$pat" ] || continue
      case "$pat" in \#*) continue ;; esac
      if (cd "$REPO" && printf '%s\n' "$tracked" | xargs grep -l -i -F -- "$pat" 2>/dev/null | grep -q .); then
        bad "tracked files contain the private word '$pat':"
        (cd "$REPO" && printf '%s\n' "$tracked" | xargs grep -l -i -F -- "$pat" 2>/dev/null | sed 's/^/      /')
        hits=$((hits + 1))
      fi
    done < "$REPO/.scrub-words"
  fi

  [ "$hits" -eq 0 ] && ok "no home paths, credentials or private words in tracked files"
}
