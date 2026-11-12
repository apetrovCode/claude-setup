# shellcheck shell=bash
# Hook case tables: each public hook against tests/hooks/<hook>.cases.jsonl, with
# stubbed tools and a minimal PATH (tests/hooks/run-cases.py). CI-safe.
#
# Sourced by tests/run.sh, which provides REPO, H_TMP and the h_* helpers.

hk_settings() {   # the default build, from the static suite or built here
  [ -s "$H_TMP/settings-default.json" ] && return 0
  # shellcheck source=tests/static.sh
  . "$REPO/tests/static.sh"
  static_build default >/dev/null
}

hk_run_table() {   # hk_run_table <hook name>
  local out
  out="$(python3 -I "$REPO/tests/hooks/run-cases.py" "$REPO/claude/hooks/$1.sh" "$REPO/tests/hooks/$1.cases.jsonl" 2>&1)" \
    || { printf '%s\n' "$out" | sed '/^$/d'; return 1; }
}

# Every hook script has a table, and every blocking case uses a tool the hook's
# registered matcher sends it: a case the matcher never routes proves nothing.
hk_check_matcher_coverage() {
  local f name bad=""
  hk_settings || { printf 'the default settings do not build\n'; return 1; }
  for f in "$REPO"/claude/hooks/*.sh; do
    name="$(basename "$f" .sh)"
    [ -f "$REPO/tests/hooks/$name.cases.jsonl" ] || bad="$bad
  no case table for claude/hooks/$name.sh"
  done
  bad="$bad$(python3 -I - "$H_TMP/settings-default.json" "$REPO/tests/hooks" <<'PY'
import json, os, re, sys
settings, tables = sys.argv[1], sys.argv[2]
hooks = json.load(open(settings)).get("hooks", {})
for t in sorted(os.listdir(tables)):
    if not t.endswith(".cases.jsonl"):
        continue
    name = t[: -len(".cases.jsonl")]
    matchers = [g.get("matcher") or ".*" for groups in hooks.values() for g in groups
                for h in g.get("hooks", []) if f"/{name}.sh" in h.get("command", "")]
    if not matchers:
        print(f"\n  {name}: not registered in the default settings")
        continue
    for line in open(os.path.join(tables, t)):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        c = json.loads(line)
        tool = (c.get("stdin") or {}).get("tool_name")
        if c.get("expect") == 2 and tool and not any(re.fullmatch(m, tool) for m in matchers):
            print(f"\n  {name}/{c['id']}: tool {tool} is not routed by matcher(s) {matchers}")
PY
)"
  [ -z "$bad" ] || { printf '%s\n' "$bad" | sed '/^$/d'; return 1; }
}

hooks_suite() {
  local f name
  for f in "$REPO"/tests/hooks/*.cases.jsonl; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .cases.jsonl)"
    h_check "hook-$name" "$name.sh against its case table" hk_run_table "$name"
  done
  h_check hook-matcher-coverage "every hook has a case table its matcher routes" hk_check_matcher_coverage
}
