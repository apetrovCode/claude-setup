#!/usr/bin/env bash
# Run the harness checks.
#
#   tests/run.sh [--public-only] [--quick] [--live] [suite ...]
#
# Suites: static   public checks on settings built from the repo alone (CI-safe)
#         self     the harness testing its own gates (CI-safe)
#         private  ~/.claude/local/harness/checks.sh, when present
#         hooks    each public hook against its case table (CI-safe)
#         dcg, scanner  not built yet
# --public-only  skip the private suite and private expected-fail list (CI)
# --quick        skip the slow checks (shellcheck)
# --live         reserved for suites that need the real HOME and installed binaries
# Exit 1 on any FAIL or XPASS. Known gaps: tests/expected-fail.txt plus the
# private layer's harness/expected-fail.txt.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO
PRIVATE_DIR="${CLAUDE_SETUP_HARNESS_DIR:-$HOME/.claude/local/harness}"

PUBLIC_ONLY=0
QUICK=0
LIVE=0
SUITES=""
for a in "$@"; do
  case "$a" in
    --public-only) PUBLIC_ONLY=1 ;;
    --quick)       QUICK=1 ;;
    --live)        LIVE=1 ;;
    -h|--help)     sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            printf 'unknown flag: %s\n' "$a" >&2; exit 2 ;;
    *)             case "$a" in *[![:space:]]*) ;; *) printf 'empty suite name\n' >&2; exit 2 ;; esac
                   SUITES="$SUITES $a" ;;
  esac
done
[ -n "$SUITES" ] || SUITES="static self private hooks dcg scanner"
export PUBLIC_ONLY QUICK LIVE

# shellcheck source=tests/lib.sh
. "$REPO/tests/lib.sh"
h_clear_git_env
h_tmp_init
H_EXPECTED="$REPO/tests/expected-fail.txt"
if [ "$PUBLIC_ONLY" -eq 0 ] && [ -f "$PRIVATE_DIR/expected-fail.txt" ]; then
  H_EXPECTED="$H_EXPECTED
$PRIVATE_DIR/expected-fail.txt"
fi
# A run that carries the private layer must also have the private-word list.
H_PRIVATE_LAYER=0
if [ "$PUBLIC_ONLY" -eq 0 ] && [ -f "$PRIVATE_DIR/checks.sh" ]; then H_PRIVATE_LAYER=1; fi
export H_PRIVATE_LAYER

for s in $SUITES; do
  case "$s" in
    static)
      h_suite "static (public)"
      h_run_suite suite-static "$REPO/tests/static.sh" static_suite
      ;;
    self)
      h_suite "self-tests (public)"
      h_run_suite suite-self "$REPO/tests/self.sh" self_suite
      ;;
    private)
      h_suite "private"
      if [ "$PUBLIC_ONLY" -eq 1 ]; then
        h_skip private "private checks" "--public-only"
      elif [ -f "$PRIVATE_DIR/checks.sh" ]; then
        h_run_suite suite-private "$PRIVATE_DIR/checks.sh" private_suite
      else
        h_skip private "private checks" "no private harness layer on this machine"
      fi
      ;;
    hooks)
      h_suite "hooks (public)"
      h_run_suite suite-hooks "$REPO/tests/hooks.sh" hooks_suite
      ;;
    dcg)     h_suite dcg;     h_skip dcg "dcg corpus" "not built yet" ;;
    scanner) h_suite scanner; h_skip scanner "scanner self-test" "not built yet" ;;
    *)       printf 'unknown suite: %s\n' "$s" >&2; exit 2 ;;
  esac
done

h_summary
