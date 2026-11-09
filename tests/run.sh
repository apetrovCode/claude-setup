#!/usr/bin/env bash
# Run the harness checks.
#
#   tests/run.sh [--public-only] [--quick] [--live] [suite ...]
#
# Suites: static   public checks on settings built from the repo alone (CI-safe)
#         private  ~/.claude/local/harness/checks.sh, when present
#         hooks, dcg, scanner  not built yet
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
    -h|--help)     sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            printf 'unknown flag: %s\n' "$a" >&2; exit 2 ;;
    *)             SUITES="$SUITES $a" ;;
  esac
done
[ -n "$SUITES" ] || SUITES="static private hooks dcg scanner"
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

for s in $SUITES; do
  case "$s" in
    static)
      h_suite "static (public)"
      # shellcheck source=tests/static.sh
      . "$REPO/tests/static.sh"
      static_suite
      ;;
    private)
      h_suite "private"
      if [ "$PUBLIC_ONLY" -eq 1 ]; then
        h_skip private "private checks" "--public-only"
      elif [ -f "$PRIVATE_DIR/checks.sh" ]; then
        # shellcheck disable=SC1091
        . "$PRIVATE_DIR/checks.sh"
        private_suite
      else
        h_skip private "private checks" "no private harness layer on this machine"
      fi
      ;;
    hooks)   h_suite hooks;   h_skip hooks "hook case tables" "not built yet" ;;
    dcg)     h_suite dcg;     h_skip dcg "dcg corpus" "not built yet" ;;
    scanner) h_suite scanner; h_skip scanner "scanner self-test" "not built yet" ;;
    *)       printf 'unknown suite: %s\n' "$s" >&2; exit 2 ;;
  esac
done

h_summary
