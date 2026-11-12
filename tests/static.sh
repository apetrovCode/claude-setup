# shellcheck shell=bash
# Public static checks. They run against settings built from the repo's own
# fragments with no private layer, so CI and every machine see the same input.
# Employer-specific rules never go here; they belong in the private layer.
#
# Sourced by tests/run.sh, which provides REPO, QUICK, H_TMP and the h_* helpers.

static_build() {   # static_build <profile>: build into $H_TMP/settings-<profile>.json
  local profile="$1"
  if (
    CLAUDE_CONFIG_DIR="$H_TMP/cfg-$profile"   # empty config dir: no local layer
    export CLAUDE_CONFIG_DIR
    mkdir -p "$CLAUDE_CONFIG_DIR"
    # shellcheck source=lib/common.sh
    . "$REPO/lib/common.sh"
    # shellcheck source=lib/merge.sh
    . "$REPO/lib/merge.sh"
    build_settings "$profile"
  ) > "$H_TMP/settings-$profile.json" 2> "$H_TMP/settings-$profile.err" \
    && jq empty "$H_TMP/settings-$profile.json" 2>/dev/null; then
    return 0
  fi
  cat "$H_TMP/settings-$profile.err"
  return 1
}

st_rules() {   # st_rules <allow|ask|deny>: rules of the default build, one per line
  jq -r --arg k "$1" '.permissions[$k] // [] | .[]' "$H_TMP/settings-default.json"
}

st_bash_globs() {   # st_bash_globs <allow|ask|deny>: the patterns inside Bash(...)
  st_rules "$1" | sed -n 's/^Bash(\(.*\))$/\1/p'
}

# Approximates Claude Code's Bash rule matching with shell globs: '*' matches
# any run of characters, spaces included. Plan step 3's smoke run checks the
# approximation against the real permission engine.
st_match_any() {   # st_match_any <command> <file of globs>
  local cmd="$1" g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    # shellcheck disable=SC2053   # unquoted on purpose: glob match
    [[ $cmd == $g ]] && return 0
  done < "$2"
  return 1
}

st_check_deny_baseline() {
  local want missing=""
  for want in 'Read(~/.aws/**)' 'Read(~/.ssh/**)' 'Read(~/.gnupg/**)' \
              'Read(~/.config/gh/**)' 'Read(~/.git-credentials)' \
              'Read(~/.docker/config.json)' 'Read(~/.npmrc)' 'Read(~/.kube/**)' \
              'Read(//**/accessKeys*.csv)'; do
    st_rules deny | grep -qxF "$want" || missing="$missing $want"
  done
  [ -z "$missing" ] || { printf 'missing deny rules:%s\n' "$missing"; return 1; }
}

# A path rule that starts with **/ (or any relative path) is matched against the session's working
# directory, so it only protects sessions started above the file. Smoke run c6bccef5 (2026-11-11):
# Read(**/internal_users.txt) let a read through from a temp cwd; Read(//**/...) denied it.
st_check_deny_not_cwd_relative() {
  local hits
  hits="$(st_rules deny | grep -E '^(Read|Edit|Write)\((\*\*/|\./|[^/~*])' || true)"
  [ -z "$hits" ] || { printf 'cwd-relative deny rules (use //** or ~/):\n%s\n' "$hits"; return 1; }
}

# A Read rule that covers the whole home directory (or more). Case table:
# tests/fixtures/home-wide-read.tsv, checked by home-wide-read-patterns.
ST_HOME_WIDE_RE='^Read$|^Read\((\*\*|//\*\*|~/\*\*)(/\*+)*\)$|^Read\(~\)$|^Read\(//([Uu]sers|[Hh]ome)(/[^/]+)?(/\*\*(/\*+)*)?\)$'

st_check_no_home_wide_read() {
  local hits
  hits="$(st_rules allow | grep -E "$ST_HOME_WIDE_RE" || true)"
  [ -z "$hits" ] || { printf 'home-wide Read allow:\n%s\n' "$hits"; return 1; }
}

st_check_home_wide_read_patterns() {
  local want rule got bad=""
  while IFS=$'\t' read -r want rule; do
    [ -n "$want" ] || continue
    rule="$(printf '%s' "$rule" | sed 's/@U@/Users/; s/@H@/home/; s/@u@/users/')"
    if printf '%s\n' "$rule" | grep -qE "$ST_HOME_WIDE_RE"; then got=flag; else got=pass; fi
    [ "$got" = "$want" ] || bad="$bad
  want $want, got $got: $rule"
  done < "$REPO/tests/fixtures/home-wide-read.tsv"
  [ -z "$bad" ] || { printf '%s\n' "$bad"; return 1; }
}

st_check_gh_api_mutations_ask() {
  local cmd missing=""
  st_bash_globs ask > "$H_TMP/ask.globs"
  while IFS= read -r cmd; do
    case "$cmd" in ''|\#*) continue ;; esac
    st_match_any "$cmd" "$H_TMP/ask.globs" || missing="$missing
  $cmd"
  done < "$REPO/tests/fixtures/gh-api-mutations.txt"
  [ -z "$missing" ] || { printf 'not matched by any ask rule:%s\n' "$missing"; return 1; }
}

st_check_gh_api_reads_allowed() {
  local cmd bad=""
  st_bash_globs allow > "$H_TMP/allow.globs"
  { st_bash_globs ask; st_bash_globs deny; } > "$H_TMP/askdeny.globs"
  while IFS= read -r cmd; do
    case "$cmd" in ''|\#*) continue ;; esac
    if ! st_match_any "$cmd" "$H_TMP/allow.globs"; then
      bad="$bad
  not allowed: $cmd"
    elif st_match_any "$cmd" "$H_TMP/askdeny.globs"; then
      bad="$bad
  asks or denies: $cmd"
    fi
  done < "$REPO/tests/fixtures/gh-api-reads.txt"
  [ -z "$bad" ] || { printf 'read-only gh api forms affected:%s\n' "$bad"; return 1; }
}

st_hook_commands() {
  jq -r '[.hooks[]?[]?.hooks[]?.command // empty] | .[]' "$H_TMP/settings-default.json"
}

st_check_hook_scripts_parse() {
  local cmd f out bad="" n=0
  while IFS= read -r cmd; do
    case "$cmd" in */.claude/hooks/*.sh*) ;; *) continue ;; esac
    f="${cmd##*/.claude/hooks/}"
    f="${f%% *}"
    n=$((n + 1))
    if [ ! -f "$REPO/claude/hooks/$f" ]; then
      bad="$bad
  registered but missing: claude/hooks/$f"
    elif ! out="$(bash -n "$REPO/claude/hooks/$f" 2>&1)"; then
      bad="$bad
  syntax error in claude/hooks/$f: $out"
    fi
  done <<EOF
$(st_hook_commands)
EOF
  [ "$n" -gt 0 ] || { printf 'no hook scripts registered\n'; return 1; }
  [ -z "$bad" ] || { printf '%s\n' "$bad"; return 1; }
}

# no-cred-output.sh against its case table: block = exit 2, allow = exit 0.
st_check_no_cred_output_cases() {
  local want cmd rc got bad=""
  while IFS=$'\t' read -r want cmd; do
    [ -n "$want" ] || continue
    jq -n --arg c "$cmd" '{tool_input: {command: $c}}' | bash "$REPO/claude/hooks/no-cred-output.sh" >/dev/null 2>&1
    rc=$?
    case "$rc" in 2) got=block ;; 0) got=allow ;; *) got="exit $rc" ;; esac
    [ "$got" = "$want" ] || bad="$bad
  want $want, got $got: $cmd"
  done < "$REPO/tests/fixtures/no-cred-output.tsv"
  [ -z "$bad" ] || { printf '%s\n' "$bad"; return 1; }
}

# A relative core.hooksPath is resolved against the work tree git infers, so a
# commit or push run with only --git-dir (or GIT_DIR) from another directory
# finds no hooks and skips the leak scan silently. Checked 2026-11-11.
st_check_hooks_path_absolute() {
  local hp
  hp="$(git -C "$REPO" config --get core.hooksPath 2>/dev/null)" || return 0   # unset: CI, fresh clone
  case "$hp" in
    /*) [ "$hp" = "$REPO/.githooks" ] || { printf 'core.hooksPath points elsewhere: not %s\n' "this clone's .githooks"; return 1; } ;;
    *)  printf 'core.hooksPath is relative (%s): run  git config core.hooksPath "$(git rev-parse --show-toplevel)/.githooks"\n' "$hp"; return 1 ;;
  esac
}

# Safety hooks fail closed: with onFailure "block" a PreToolUse guard that crashes,
# hangs or prints bad JSON blocks the call instead of letting it through
# (code.claude.com/docs/en/hooks, 2.1.295+). The recovery build drops the key.
ST_FAIL_CLOSED_HOOKS="no-cred-output.sh"

st_check_safety_hooks_fail_closed() {
  local h bad=""
  for h in $ST_FAIL_CLOSED_HOOKS; do
    jq -e --arg h "$h" '[.hooks.PreToolUse[]?.hooks[]? | select(.command | test("/" + $h)) | .onFailure == "block"] | (length > 0 and all)' \
      "$H_TMP/settings-default.json" >/dev/null || bad="$bad $h"
  done
  [ -z "$bad" ] || { printf 'PreToolUse hooks without onFailure "block":%s\n' "$bad"; return 1; }
}

st_check_onfailure_recovery() {
  local out
  out="$(
    CLAUDE_CONFIG_DIR="$H_TMP/cfg-recovery"; export CLAUDE_CONFIG_DIR; mkdir -p "$CLAUDE_CONFIG_DIR"
    CLAUDE_SETUP_NO_ONFAILURE=1; export CLAUDE_SETUP_NO_ONFAILURE
    . "$REPO/lib/common.sh"; . "$REPO/lib/merge.sh"
    build_settings default 2>/dev/null
  )" || { printf 'the recovery build failed\n'; return 1; }
  printf '%s' "$out" | jq -e '[.. | objects | select(has("onFailure"))] | length == 0' >/dev/null \
    || { printf 'CLAUDE_SETUP_NO_ONFAILURE=1 still leaves onFailure in the settings\n'; return 1; }
}

st_check_hook_scripts_registered() {
  local f bad=""
  for f in "$REPO"/claude/hooks/*.sh; do
    [ -f "$f" ] || continue
    st_hook_commands | grep -qF "/.claude/hooks/$(basename "$f")" || bad="$bad $(basename "$f")"
  done
  [ -z "$bad" ] || { printf 'hook scripts with no registration:%s\n' "$bad"; return 1; }
}

st_check_min_versions() {
  local cli id filter min src bad=""
  cli="$(claude --version 2>/dev/null | awk '{print $1}')"
  while IFS=$'\t' read -r id filter min src; do
    case "$id" in ''|\#*) continue ;; esac
    if jq -e "$filter" "$H_TMP/settings-default.json" >/dev/null 2>&1; then
      h_version_ge "$cli" "$min" || bad="$bad
  $id needs Claude Code >= $min ($src); the CLI on PATH is $cli"
    fi
  done < "$REPO/tests/settings-min-versions.tsv"
  [ -z "$bad" ] || { printf '%s\n' "$bad"; return 1; }
}

st_check_gitignore() {
  local p bad="" ignored
  for p in tests/run.sh tests/lib.sh tests/static.sh tests/expected-fail.txt \
           tests/settings-min-versions.tsv tests/fixtures/gh-api-mutations.txt \
           tests/fixtures/gh-api-reads.txt .githooks/pre-push \
           .github/workflows/ci.yml tools/harness-scan tools/harness-replay; do
    (cd "$REPO" && git check-ignore -q --no-index "$p") && bad="$bad $p"
  done
  ignored="$(cd "$REPO" && git ls-files -oi --exclude-standard -- tests tools .github)"
  [ -z "$bad" ] && [ -z "$ignored" ] && return 0
  printf 'ignored by .gitignore:%s\n%s\n' "$bad" "$ignored"
  return 1
}

st_check_shellcheck() {
  local files
  files="$(cd "$REPO" && git ls-files -co --exclude-standard -- \
    install.sh bootstrap-linux.sh 'lib/*.sh' 'claude/*.sh' 'claude/hooks/*.sh' \
    'claude/bin/*.sh' '.githooks/*' 'tests/*.sh' 'tests/**/*.sh' | sort -u)"
  [ -n "$files" ] || { printf 'no shell files found\n'; return 1; }
  # shellcheck disable=SC2086   # one file name per word
  (cd "$REPO" && shellcheck -x -S warning $files)
}

st_scan() {   # st_scan <scanner args>: the repo's leak scanner, run in $ST_SCAN_ROOT (default: the repo)
  (cd "${ST_SCAN_ROOT:-$REPO}" && bash "$REPO/.githooks/pre-commit" "$@")
}

st_check_leak_scan() {
  st_scan --all
}

st_check_word_list() {   # reached only when a run with the private layer has no list
  printf 'no .scrub-words in this checkout or its main worktree, so private words went unscanned.\n'
  printf 'Create the list (an empty file opts out), or run with --public-only.\n'
  return 1
}

# The leak scan over tracked files, and an honest line about private words. It
# names them only when a list with at least one word was found. Without a list,
# a run that carries the private layer fails; any other run (CI, a fork) skips.
st_leak_checks() {
  local list words tab
  tab="$(printf '\t')"
  list="$(st_scan --scrub-list 2>/dev/null)" || list=""
  words="${list##*"$tab"}"
  case "$words" in ''|*[!0-9]*) words=0 ;; esac
  if [ -n "$list" ] && [ "$words" -gt 0 ]; then
    h_check leak-scan "no home paths, credential shapes or private words in tracked files" st_check_leak_scan
    return
  fi
  h_check leak-scan "no home paths or credential shapes in tracked files" st_check_leak_scan
  if [ -n "$list" ]; then
    h_skip private-words "private-word scan" ".scrub-words is empty, which opts out"
  elif [ "${H_PRIVATE_LAYER:-0}" -eq 1 ]; then
    h_check private-words "the leak scan covered private words" st_check_word_list
  else
    h_skip private-words "private-word scan" "no .scrub-words list here"
  fi
}

static_suite() {
  local p
  # install.sh defaults to the default profile, so its build is checked even
  # when the file is missing. Other profiles are checked as found.
  h_check settings-build-default "settings for profile 'default' build into valid JSON" static_build default
  for p in "$REPO"/settings/profile.*.json; do
    p="${p##*/profile.}"
    p="${p%.json}"
    case "$p" in default|'*') continue ;; esac
    h_check "settings-build-$p" "settings for profile '$p' build into valid JSON" static_build "$p"
  done
  if [ -s "$H_TMP/settings-default.json" ]; then
    st_rule_checks
  else
    h_skip rules "rule checks" "the default profile did not build"
  fi
  # These need no built settings, so they run either way.
  h_skip hook-matcher-coverage "hook matchers cover their case tables" "hook case tables not built yet"
  h_check gitignore-readmits "test, tool and CI files are not ignored" st_check_gitignore
  if [ "${QUICK:-0}" -eq 1 ]; then
    h_skip shellcheck "shellcheck" "--quick"
  elif command -v shellcheck >/dev/null 2>&1; then
    h_check shellcheck "shellcheck finds no warnings" st_check_shellcheck
  else
    h_skip shellcheck "shellcheck" "shellcheck not installed"
  fi
  st_leak_checks
}

st_rule_checks() {   # checks on the built default settings
  h_check deny-baseline "credential stores stay Read-denied" st_check_deny_baseline
  h_check deny-not-cwd-relative "no deny rule depends on the working directory" st_check_deny_not_cwd_relative
  h_check no-home-wide-read-allow "no allow rule reads the whole home directory" st_check_no_home_wide_read
  h_check home-wide-read-patterns "the home-wide Read pattern flags every broad form" st_check_home_wide_read_patterns
  h_check gh-api-mutations-ask "mutating gh api forms need approval" st_check_gh_api_mutations_ask
  h_check gh-api-reads-allowed "read-only gh api forms stay allowed" st_check_gh_api_reads_allowed
  h_check hook-scripts-parse "every registered hook script exists and parses" st_check_hook_scripts_parse
  h_check hook-scripts-registered "every hook script is registered" st_check_hook_scripts_registered
  h_check safety-hooks-fail-closed "PreToolUse safety hooks block when they fail" st_check_safety_hooks_fail_closed
  h_check onfailure-recovery "CLAUDE_SETUP_NO_ONFAILURE=1 rebuilds the settings without onFailure" st_check_onfailure_recovery
  h_check hooks-path-absolute "this clone's core.hooksPath is absolute, so --git-dir runs still scan" st_check_hooks_path_absolute
  h_check no-cred-output-cases "no-cred-output.sh blocks credential-printing commands only" st_check_no_cred_output_cases
  if command -v claude >/dev/null 2>&1; then
    h_check settings-min-versions "no settings key needs a newer CLI than the one on PATH" st_check_min_versions
  else
    h_skip settings-min-versions "settings keys vs CLI version" "no claude CLI here"
  fi
}
