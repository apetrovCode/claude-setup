#!/usr/bin/env bash
# PostToolUse / Edit|Write — lint GitHub Actions workflows Claude just wrote.
#
# actionlint: syntax, expressions, shellcheck on run blocks.
# zizmor:     Actions threat model (script injection, pull_request_target,
#             mutable action refs, over-scoped tokens).
#
# zizmor exit codes: 0 clean | 1 tool error | 2 bad args | 3 no inputs
#                    11 informational | 12 low | 13 medium | 14 high
# Only 11+ are findings, so exit 1 must NOT be read as "clean" — it is reported
# without blocking, otherwise a crashing linter would silently pass everything.
#
# Exit 2 = block with reason on stderr. Exit 0 = allow.
f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[ -z "$f" ] && exit 0
case "$f" in
  */.github/workflows/*.yml|*/.github/workflows/*.yaml) ;;
  *) exit 0 ;;
esac
[ -f "$f" ] || exit 0

fail=0
out=""

# Preflight. Without it, a missing linter takes the failure branch below and
# blocks every single workflow edit — which is exactly what a freshly
# provisioned machine looks like before the linters are installed. Missing
# tool = warn and skip that linter. Present tool = enforce it.
have() { command -v "$1" >/dev/null 2>&1; }

if have actionlint; then
  if o=$(actionlint -no-color "$f" 2>&1); then :; else
    fail=1
    out+="actionlint:"$'\n'"$o"$'\n'
  fi
else
  out+="actionlint not installed — workflow NOT syntax-linted."$'\n'
fi

if ! have zizmor; then
  printf '%szizmor not installed — workflow NOT security-linted.\n' "$out" >&2
  exit 0
fi

# --min-confidence medium is load-bearing: the `artipacked` audit flags every
# actions/checkout without `persist-credentials: false` at medium severity but
# LOW confidence, which would block essentially every workflow. Filtering by
# confidence keeps real medium findings and drops that noise.
o=$(zizmor --offline --min-severity medium --min-confidence medium --format plain --no-progress "$f" 2>&1)
rc=$?
if [ "$rc" -ge 11 ]; then
  fail=1
  out+="zizmor (severity exit $rc):"$'\n'"$o"$'\n'
elif [ "$rc" -eq 1 ] || [ "$rc" -eq 2 ]; then
  out+="zizmor could not run (exit $rc) — workflow NOT security-linted:"$'\n'"$o"$'\n'
fi

if [ "$fail" -eq 1 ]; then
  printf 'GitHub Actions lint failed for %s\n\n%s\n' "$f" "$out" >&2
  printf 'Fix these before the workflow ships.\n' >&2
  exit 2
fi

[ -n "$out" ] && printf '%s' "$out" >&2
exit 0
