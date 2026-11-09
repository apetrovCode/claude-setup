# shellcheck shell=bash
# Self-tests: the harness checking its own gates. Each test builds what it needs
# under $H_TMP. Fake secrets and private words are assembled at run time, so no
# literal one ever sits in this repo.
#
# Sourced by tests/run.sh, which provides REPO, H_TMP and the h_* helpers.

sf_git() {   # git that ignores the caller's hooks, signing and identity
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false \
      -c user.name=harness -c user.email=harness@example.invalid \
      -c init.defaultBranch=main "$@"
}

# A hook's GIT_DIR must not redirect the suites' `git -C <other repo>` calls.
sf_check_git_env_cleared() {
  local d out
  d="$(mktemp -d "$H_TMP/gitenv.XXXXXX")" || return 1
  sf_git init -q "$d/a" && sf_git init -q "$d/b" \
    && sf_git -C "$d/a" remote add origin https://example.invalid/a.git || return 1
  out="$(GIT_DIR="$d/a/.git"; export GIT_DIR; h_clear_git_env; git -C "$d/b" remote)"
  [ -z "$out" ] || { printf 'git -C read the outer GIT_DIR instead (remote: %s)\n' "$out"; return 1; }
}

# A suite that fails to load, lacks its entry function or reports nothing must
# fail the run. Silence must never read as a pass.
sf_check_suite_load_guard() {
  local d c rc bad=""
  d="$(mktemp -d "$H_TMP/loadguard.XXXXXX")" || return 1
  for c in broken renamed silent good; do
    mkdir -p "$d/$c"
    case "$c" in
      broken)  printf 'private_suite() {\n  h_check x x true\n' ;;
      renamed) printf 'private_checks() { h_check x x true; }\n' ;;
      silent)  printf 'private_suite() { :; }\n' ;;
      good)    printf 'private_suite() { h_check x x true; }\n' ;;
    esac > "$d/$c/checks.sh"
    CLAUDE_SETUP_HARNESS_DIR="$d/$c" bash "$REPO/tests/run.sh" private >/dev/null 2>&1
    rc=$?
    case "$c" in
      good) [ "$rc" -eq 0 ] || bad="$bad $c(exit $rc)" ;;
      *)    [ "$rc" -ne 0 ] || bad="$bad $c(exit 0)" ;;
    esac
  done
  [ -z "$bad" ] || { printf 'wrong exit status for:%s\n' "$bad"; return 1; }
}

sf_fake_token() {   # a token-shaped string that matches the scanner, built at run time
  printf '%s%s' "$(printf 'gh%s_' p)" "$(printf '%036d' 0 | tr 0 Q)"
}

# The leak scanner names the file and line of a hit, never the matched text:
# its output lands in terminals, pre-push logs and agent transcripts.
sf_check_scanner_hides_hits() {
  local d tok out rc
  d="$(mktemp -d "$H_TMP/redact.XXXXXX")" || return 1
  tok="$(sf_fake_token)"
  sf_git init -q "$d/r" || return 1
  printf 'export X=%s\n' "$tok" > "$d/r/leak.txt"
  sf_git -C "$d/r" add leak.txt || return 1
  out="$(cd "$d/r" && bash "$REPO/.githooks/pre-commit" --all 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || { printf 'the scanner passed a planted token\n'; return 1; }
  case "$out" in *leak.txt*) ;; *) printf 'the report does not name the file\n'; return 1 ;; esac
  case "$out" in *"$tok"*) printf 'the report repeats the matched text\n'; return 1 ;; esac
}

self_suite() {
  h_check hook-git-env-cleared "a hook's GIT_DIR does not redirect the suites' git -C calls" sf_check_git_env_cleared
  h_check suite-load-guard "a suite that fails to load or reports nothing fails the run" sf_check_suite_load_guard
  h_check scanner-hides-hits "the leak scanner reports where a hit is, never the matched text" sf_check_scanner_hides_hits
}
