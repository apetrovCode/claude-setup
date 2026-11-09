# shellcheck shell=bash
# Minimal check runner, shared by tests/run.sh and the private checks in
# ~/.claude/local/harness/checks.sh. Bash 3.2 compatible (stock macOS bash).
#
# Every check ends in one status:
#   ok     passed
#   FAIL   failed                                     -> the run fails
#   xfail  failed, and its id is a listed known gap   -> the run passes
#   XPASS  passed, but its id is still listed as a gap -> the run fails
#          until the entry is removed, so every fix gets recorded
#   skip   not runnable here (missing tool, suite not built yet)
#   warn   informational; never fails the run
#
# Known gaps live in expected-fail files: one "id<TAB>since<TAB>reason" per line.

H_PASS=0
H_FAIL=0
H_XFAIL=0
H_XPASS=0
H_SKIP=0
H_WARN=0
H_EXPECTED=""   # newline-separated paths of expected-fail files
H_TMP=""

h_tmp_init() {
  H_TMP="$(mktemp -d "${TMPDIR:-/tmp}/claude-setup-tests.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$H_TMP'" EXIT
}

h_suite() { printf '\n== %s\n' "$*"; }

h_clear_git_env() {   # forget the GIT_* variables git exports to hooks
  # Inside a hook, GIT_DIR and its relatives point every git command at the
  # repo running the hook, even `git -C <another repo>`. The private suite
  # inspects another repo, so without this a pre-push run checked this one.
  # shellcheck disable=SC2046
  unset $(git rev-parse --local-env-vars 2>/dev/null)
}

h_expected() {   # h_expected <id>: 0 if <id> is listed in an expected-fail file
  local id="$1" f
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    grep -qE "^${id}([[:space:]]|$)" "$f" && return 0
  done <<EOF
$H_EXPECTED
EOF
  return 1
}

h_details() {   # indent a check's output under its status line
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | head -n "${2:-20}" | sed 's/^/          /'
}

h_check() {   # h_check <id> <description> <command> [args...]
  local id="$1" desc="$2" out rc
  shift 2
  out="$("$@" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    if h_expected "$id"; then
      H_XPASS=$((H_XPASS + 1))
      printf '  XPASS %s - %s (listed as a known gap: remove the entry)\n' "$id" "$desc"
    else
      H_PASS=$((H_PASS + 1))
      printf '  ok    %s - %s\n' "$id" "$desc"
    fi
  elif h_expected "$id"; then
    H_XFAIL=$((H_XFAIL + 1))
    printf '  xfail %s - %s\n' "$id" "$desc"
    h_details "$out" 5
  else
    H_FAIL=$((H_FAIL + 1))
    printf '  FAIL  %s - %s\n' "$id" "$desc"
    h_details "$out" 20
  fi
}

h_skip() {   # h_skip <id> <description> <reason>
  H_SKIP=$((H_SKIP + 1))
  printf '  skip  %s - %s (%s)\n' "$1" "$2" "$3"
}

h_warn_check() {   # like h_check, but a failure is only a warning
  local id="$1" desc="$2" out
  shift 2
  if out="$("$@" 2>&1)"; then
    H_PASS=$((H_PASS + 1))
    printf '  ok    %s - %s\n' "$id" "$desc"
  else
    H_WARN=$((H_WARN + 1))
    printf '  warn  %s - %s\n' "$id" "$desc"
    h_details "$out" 10
  fi
}

h_version_ge() {   # h_version_ge <a> <b>: 0 if version a >= version b (numeric, dotted)
  local a="$1" b="$2" i x y
  for i in 1 2 3 4; do
    x="$(printf '%s' "$a" | cut -d. -f"$i")"; x="${x%%[!0-9]*}"; x="${x:-0}"
    y="$(printf '%s' "$b" | cut -d. -f"$i")"; y="${y%%[!0-9]*}"; y="${y:-0}"
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 0
}

h_summary() {
  local total=$((H_PASS + H_FAIL + H_XFAIL + H_XPASS))
  printf '\nchecks %d: ok %d, xfail %d, FAIL %d, XPASS %d, skipped %d, warnings %d\n' \
    "$total" "$H_PASS" "$H_XFAIL" "$H_FAIL" "$H_XPASS" "$H_SKIP" "$H_WARN"
  [ $((H_FAIL + H_XPASS)) -eq 0 ]
}
