# shellcheck shell=bash
# tools/harness-scan: the harness's own measuring tool (plan step 5). It reads
# transcripts and stores and prints counts only. These checks run it against a
# synthetic tree it builds itself, with planted fakes, so they are CI-safe.
#
# Sourced by tests/run.sh, which provides REPO, H_TMP and the h_* helpers.

sc_scan() { python3 -I "$REPO/tools/harness-scan" "$@"; }

# The self-test: every signal the go/no-go rule reads comes out of a planted
# tree with known counts (friction, AWS session-hours, upkeep, secret shapes).
sc_check_self_test() {
  [ -f "$REPO/tools/harness-scan" ] || { printf 'no tools/harness-scan\n'; return 1; }
  local out
  out="$(sc_scan --self-test 2>&1)" || { printf '%s\n' "$out" | tail -n 20; return 1; }
}

# Counts only: a scan of the planted tree must not print any planted secret,
# command argument or message text, whatever the output format.
sc_check_counts_only() {
  [ -f "$REPO/tools/harness-scan" ] || { printf 'no tools/harness-scan\n'; return 1; }
  local d leaked
  d="$(mktemp -d "$H_TMP/scan.XXXXXX")" || return 1
  sc_scan --make-fixture "$d" >/dev/null 2>&1 || { printf 'could not build the fixture\n'; return 1; }
  sc_scan --config "$d/scan.json" --since 2026-01-01 --until 2027-01-01 > "$d/out.json" 2>&1 || {
    printf 'scan failed on the fixture\n'; return 1; }
  leaked="$(python3 -I - "$d/planted.txt" "$d/out.json" <<'PY'
import sys
planted = [l.rstrip("\n") for l in open(sys.argv[1]) if l.strip()]
out = open(sys.argv[2]).read()
if not out.strip() or not planted:
    print("empty scan output or empty planted list")
print("\n".join(f"planted item {i + 1}" for i, p in enumerate(planted) if p in out))
PY
)"
  leaked="$(printf '%s\n' "$leaked" | sed '/^$/d')"
  [ -z "$leaked" ] || { printf 'the scan output repeats planted text:\n%s\n' "$leaked"; return 1; }
}

# tools/harness-replay: past shell commands through dcg under two configs. Needs dcg,
# so it is skipped where dcg is absent (CI); the planted history fixes every count.
sc_check_replay_self_test() {
  [ -f "$REPO/tools/harness-replay" ] || { printf 'no tools/harness-replay\n'; return 1; }
  local out
  out="$(python3 -I "$REPO/tools/harness-replay" --self-test 2>&1)" || { printf '%s\n' "$out" | tail -n 20; return 1; }
}

scanner_suite() {
  h_check harness-scan-self-test "harness-scan reproduces the planted counts" sc_check_self_test
  h_check harness-scan-counts-only "harness-scan output carries no planted secret, argument or message text" sc_check_counts_only
  if command -v dcg >/dev/null 2>&1; then
    h_check harness-replay-self-test "harness-replay reproduces the planted matrix, flips, protected flips and fidelity" sc_check_replay_self_test
  else
    h_skip harness-replay-self-test "harness-replay against its planted history" "no dcg on this machine"
  fi
}
