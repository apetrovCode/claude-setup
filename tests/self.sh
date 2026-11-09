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

sf_has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

sf_scan_push() {   # sf_scan_push <repo> <pre-push stdin> [remote]: the push scan, as pre-push runs it
  (cd "$1" && printf '%s\n' "$2" | bash "$REPO/.githooks/pre-commit" --push "${3:-origin}" 2>&1)
}

# The push scan covers what a push would publish: every new commit's added
# lines, file names and message. A leak that a later commit removed is still
# in the history being pushed.
sf_check_push_scan() {
  local d r word tok zero c0 c1 c2 c3 c4 k1 out rc bad=""
  d="$(mktemp -d "$H_TMP/pushscan.XXXXXX")" || return 1
  r="$d/r"
  word="zq$(printf 'vx')kwplm"   # a private word, built here
  tok="$(sf_fake_token)"
  zero="$(printf '%040d' 0)"
  sf_git init -q "$r" && sf_git init -q --bare "$d/remote.git" \
    && sf_git -C "$r" remote add origin "$d/remote.git" || return 1
  printf '%s\n' "$word" > "$r/.scrub-words"   # untracked, like the real list
  printf 'clean\n' > "$r/README" && sf_git -C "$r" add README \
    && sf_git -C "$r" commit -qm start && sf_git -C "$r" push -q origin main || return 1
  c0="$(git -C "$r" rev-parse HEAD)"
  printf 'about %s\n' "$word" > "$r/notes" && sf_git -C "$r" add notes \
    && sf_git -C "$r" commit -qm "add notes" || return 1
  c1="$(git -C "$r" rev-parse HEAD)"
  sf_git -C "$r" rm -q notes && sf_git -C "$r" commit -qm "drop notes" || return 1
  c2="$(git -C "$r" rev-parse HEAD)"
  sf_git -C "$r" commit -q --allow-empty -m "fix for $word" || return 1
  c3="$(git -C "$r" rev-parse HEAD)"
  printf 'k=%s\n' "$tok" > "$r/cfg" && sf_git -C "$r" add cfg && sf_git -C "$r" commit -qm cfg || return 1
  c4="$(git -C "$r" rev-parse HEAD)"
  k1="$(sf_git -C "$r" commit-tree -m clean -p "$c0" "$c0^{tree}")" || return 1

  out="$(sf_scan_push "$r" "refs/heads/main $c2 refs/heads/main $c0")"; rc=$?
  { [ "$rc" -ne 0 ] && sf_has "$out" "$(git -C "$r" rev-parse --short "$c1")"; } \
    || bad="$bad; a word added and then removed again"
  out="$(sf_scan_push "$r" "refs/heads/main $c3 refs/heads/main $c2")"; rc=$?
  { [ "$rc" -ne 0 ] && sf_has "$out" message; } || bad="$bad; a word in a commit message"
  out="$(sf_scan_push "$r" "refs/heads/topic $c2 refs/heads/topic $zero")"; rc=$?
  [ "$rc" -ne 0 ] || bad="$bad; a new branch"
  out="$(sf_scan_push "$r" "refs/heads/main $c4 refs/heads/main $c3")"; rc=$?
  { [ "$rc" -ne 0 ] && ! sf_has "$out" "$tok"; } || bad="$bad; a token, caught without repeating it"
  out="$(sf_scan_push "$r" "refs/heads/clean $k1 refs/heads/clean $zero
(delete) $zero refs/heads/old $c1")"; rc=$?
  [ "$rc" -eq 0 ] || bad="$bad; a clean push plus a branch deletion (should pass)"
  # Commits that only another remote has are not public on this one.
  sf_git -C "$r" update-ref refs/remotes/other/main "$c2" || return 1
  out="$(sf_scan_push "$r" "refs/heads/topic2 $c2 refs/heads/topic2 $zero" origin)"; rc=$?
  [ "$rc" -ne 0 ] || bad="$bad; commits another remote already has, pushed to this one"
  [ -z "$bad" ] || { printf 'push scan got wrong:%s\n' "${bad#;}"; return 1; }
}

# A leak scan without a private-word list has to say so. --public-only (CI)
# shows a skip; any other run fails rather than pass on a partial scan. A
# linked worktree uses its main worktree's list.
sf_check_missing_word_list() {
  local d out bad=""
  d="$(mktemp -d "$H_TMP/nolist.XXXXXX")" || return 1
  sf_git init -q "$d/r" && printf 'x\n' > "$d/r/a.txt" && sf_git -C "$d/r" add a.txt \
    && sf_git -C "$d/r" commit -qm init && sf_git -C "$d/r" worktree add -q "$d/wt" -b wt || return 1
  # shellcheck source=tests/static.sh
  . "$REPO/tests/static.sh"
  out="$(ST_SCAN_ROOT="$d/r"; PUBLIC_ONLY=1; st_leak_checks 2>&1)"
  sf_has "$out" "skip  private-words" || bad="$bad; --public-only shows no skip"
  sf_has "$out" "or private words" && bad="$bad; --public-only still claims a private-word scan"
  out="$(ST_SCAN_ROOT="$d/r"; PUBLIC_ONLY=0; st_leak_checks 2>&1)"
  sf_has "$out" "FAIL  private-words" || bad="$bad; a run with the private layer passes without a list"
  : > "$d/r/.scrub-words"
  out="$(ST_SCAN_ROOT="$d/wt"; PUBLIC_ONLY=0; st_leak_checks 2>&1)"
  sf_has "$out" "ok    leak-scan - no home paths, credential shapes or private words" \
    || bad="$bad; a linked worktree does not use the main worktree's list"
  [ -z "$bad" ] || { printf 'without a word list:%s\n' "${bad#;}"; return 1; }
}

# pre-push logs stay private: mode 0600 in a 0700 directory, inside the clone's
# git dir when there is no private layer (never a shared /tmp), newest 30 kept.
sf_check_prepush_log() {
  local d dir log mode i n bad=""
  d="$(mktemp -d "$H_TMP/prepushlog.XXXXXX")" || return 1
  sf_git init -q "$d/r" && sf_git -C "$d/r" commit -q --allow-empty -m init || return 1
  log="$(cd "$d/r" && CLAUDE_SETUP_HARNESS_DIR="$d/none/harness" bash "$REPO/.githooks/pre-push" --log-path </dev/null 2>/dev/null)"
  dir="$(dirname "$log")"
  case "$dir" in
    "$(cd "$d/r" && git rev-parse --absolute-git-dir)"/*) ;;
    *) printf 'without a private layer the log is not in the clone'"'"'s git dir\n'; return 1 ;;
  esac
  mode="$(ls -ld "$log" | cut -c1-10)"; [ "$mode" = "-rw-------" ] || bad="$bad; log mode $mode"
  mode="$(ls -ld "$dir" | cut -c1-10)"; [ "$mode" = "drwx------" ] || bad="$bad; directory mode $mode"
  i=0
  while [ "$i" -lt 40 ]; do
    : > "$dir/2020-01-01-0000$(printf '%02d' "$i")-old.log" && touch -t 202001010000 "$dir/2020-01-01-0000$(printf '%02d' "$i")-old.log"
    i=$((i + 1))
  done
  log="$(cd "$d/r" && CLAUDE_SETUP_HARNESS_DIR="$d/none/harness" bash "$REPO/.githooks/pre-push" --log-path </dev/null 2>/dev/null)"
  n="$(find "$dir" -name '*.log' | wc -l | tr -d ' ')"
  [ "$n" -le 30 ] || bad="$bad; $n logs kept"
  [ -f "$log" ] || bad="$bad; the newest log was pruned"
  [ -z "$bad" ] || { printf 'pre-push log:%s\n' "${bad#;}"; return 1; }
}

self_suite() {
  h_check hook-git-env-cleared "a hook's GIT_DIR does not redirect the suites' git -C calls" sf_check_git_env_cleared
  h_check suite-load-guard "a suite that fails to load or reports nothing fails the run" sf_check_suite_load_guard
  h_check scanner-hides-hits "the leak scanner reports where a hit is, never the matched text" sf_check_scanner_hides_hits
  h_check push-scan "pre-push scans every commit a push publishes, messages included" sf_check_push_scan
  h_check missing-word-list "a leak scan without a private-word list says so" sf_check_missing_word_list
  h_check prepush-log-private "pre-push logs are private, inside the clone, and pruned" sf_check_prepush_log
}
