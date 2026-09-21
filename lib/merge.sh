#!/usr/bin/env bash
# Build ~/.claude/settings.json by merging fragments.
#
# Why a custom merge: jq's `*` operator REPLACES arrays. Using it would silently
# drop the 34 allow rules the moment any fragment mentioned `permissions`. Here
# objects merge key by key and arrays are unioned in order, so a fragment adds
# rules and hook groups instead of overwriting them.

MERGE_PROGRAM='
def uniq_stable:
  reduce .[] as $i ([]; if any(.[]; . == $i) then . else . + [$i] end);

# $a and $b, not a and b: a bare jq parameter is a CLOSURE re-evaluated against
# the current input, so inside the reduce below it would resolve to the
# accumulator rather than the original operand — and every array would take the
# replace branch instead of the union branch.
def deepmerge($a; $b):
  reduce ($b | keys_unsorted[]) as $k ($a;
    if ($a | has($k) | not) then
      .[$k] = $b[$k]
    elif ($a[$k] | type) == "object" and ($b[$k] | type) == "object" then
      .[$k] = deepmerge($a[$k]; $b[$k])
    elif ($a[$k] | type) == "array" and ($b[$k] | type) == "array" then
      .[$k] = (($a[$k] + $b[$k]) | uniq_stable)
    else
      .[$k] = $b[$k]
    end);

reduce .[] as $x ({}; deepmerge(.; $x))
| walk(if type == "object" then del(._comment) else . end)
'

# Emit the merged settings JSON on stdout. Does not write anything.
build_settings() {
  local profile="${1:-default}"
  local profile_file="$REPO/settings/profile.$profile.json"
  [ -f "$profile_file" ] || die "unknown profile '$profile' (expected $profile_file)"

  local fragments=(
    "$REPO/settings/base.json"
    "$REPO/settings/hooks.json"
    "$REPO/settings/plugins.json"
    "$profile_file"
  )
  [ -f "$LOCAL_DIR/settings.work.json" ] && fragments+=("$LOCAL_DIR/settings.work.json")

  local subst=()
  local f tmp
  for f in "${fragments[@]}"; do
    tmp="$(mktemp)"
    subst_tokens < "$f" > "$tmp"
    jq empty "$tmp" 2>/dev/null || die "invalid JSON after substitution: $f"
    subst+=("$tmp")
  done

  local merged
  merged="$(jq -s "$MERGE_PROGRAM" "${subst[@]}")" || die "settings merge failed"
  rm -f "${subst[@]}"

  # Guard against the exact failure this merge exists to prevent.
  local want got
  want="$(jq '.permissions.allow | length' "$REPO/settings/base.json")"
  got="$(printf '%s' "$merged" | jq '.permissions.allow | length')"
  [ "$got" -ge "$want" ] || die "merge lost allow rules: base has $want, result has $got"

  # An unsubstituted token means a value nobody supplied. Left alone it lands in
  # settings.json as the literal text, which fails at a much less obvious moment.
  if printf '%s' "$merged" | grep -q '\${'; then
    warn "unsubstituted token(s) in the built settings — set them in $LOCAL_DIR/local.env:"
    printf '%s' "$merged" | grep -o '\${[A-Z_]*}' | sort -u | sed 's/^/      /' >&2
  fi

  # An empty string where a name belongs is the quieter version of the same bug.
  local empties
  empties="$(printf '%s' "$merged" | jq -r '.env | to_entries[] | select(.value == "") | .key')"
  if [ -n "$empties" ]; then
    warn "empty env value(s) in profile '$profile': $(printf '%s' "$empties" | tr '\n' ' ')"
  fi

  printf '%s\n' "$merged"
}

# The dcg hook is deliberately absent from the repo (dcg rewrites its own
# absolute path on every invocation). Strip it before comparing live settings
# against a fresh build, so dcg's own entry never reads as drift.
strip_dcg_hooks() {
  jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= ( map(.hooks |= map(select((.command // "") | test("dcg") | not)))
                    | map(select(.hooks | length > 0)) )
      )
    else . end
  '
}
