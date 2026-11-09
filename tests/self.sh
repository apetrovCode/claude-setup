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

# A suite that fails to load, lacks its entry function, reports nothing, exits
# the runner or reloads the helpers must fail the run; a valid suite whose last
# line happens to be false must not. Silence must never read as a pass.
sf_check_suite_load_guard() {
  local d c rc bad=""
  d="$(mktemp -d "$H_TMP/loadguard.XXXXXX")" || return 1
  for c in broken renamed silent exits topexit relib good lastfalse; do
    mkdir -p "$d/$c"
    case "$c" in
      broken)    printf 'private_suite() {\n  h_check x x true\n' ;;
      renamed)   printf 'private_checks() { h_check x x true; }\n' ;;
      silent)    printf 'private_suite() { :; }\n' ;;
      exits)     printf 'private_suite() { h_check x x true; exit 0; }\n' ;;
      topexit)   printf 'exit 0\nprivate_suite() { h_check x x true; }\n' ;;
      relib)     printf 'private_suite() { h_check x x false; . "$REPO/tests/lib.sh"; h_check y y true; }\n' ;;
      good)      printf 'private_suite() { h_check x x true; }\n' ;;
      lastfalse) printf 'private_suite() { h_check x x true; }\n[ -f /nonexistent/extra.sh ] && . /nonexistent/extra.sh\n' ;;
    esac > "$d/$c/checks.sh"
    CLAUDE_SETUP_HARNESS_DIR="$d/$c" bash "$REPO/tests/run.sh" private >/dev/null 2>&1
    rc=$?
    case "$c" in
      good|lastfalse) [ "$rc" -eq 0 ] || bad="$bad $c(exit $rc)" ;;
      *)              [ "$rc" -ne 0 ] || bad="$bad $c(exit 0)" ;;
    esac
  done
  bash "$REPO/tests/run.sh" "" >/dev/null 2>&1 && bad="$bad empty-suite-name(exit 0)"
  [ -z "$bad" ] || { printf 'wrong exit status for:%s\n' "$bad"; return 1; }
}

# The static suite keeps going when the settings do not build: the scans that
# do not need them (shellcheck, ignore rules, the leak scan) still run.
sf_check_static_keeps_going() {
  local out
  out="$(
    # shellcheck source=tests/static.sh
    . "$REPO/tests/static.sh"
    static_build() { return 1; }   # no profile builds
    QUICK=1 static_suite 2>&1
  )"
  sf_has "$out" "leak-scan" || { printf 'with no settings built, the static suite skipped the leak scan\n'; return 1; }
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

sf_utf8_locale() {   # a UTF-8 locale this machine has: en_US.UTF-8 on macOS, C.UTF-8 on Linux
  locale -a 2>/dev/null | grep -i -m 1 -E '^(C|en_US)\.utf-?8$'
}

sf_add() {   # sf_add <repo> <file> <printf format> [args]: write a file and stage it
  local r="$1" f="$2" fmt="$3"
  shift 3
  mkdir -p "$(dirname "$r/$f")" || return 1
  # shellcheck disable=SC2059
  printf "$fmt" "$@" > "$r/$f" && sf_git -C "$r" add -f -- "$f"
}

sf_all_repo() {   # sf_all_repo <dir> <.scrub-words printf format> [args]: a repo with that list
  local d="$1" fmt="$2"
  shift 2
  sf_git init -q "$d" || return 1
  # shellcheck disable=SC2059
  printf "$fmt" "$@" > "$d/.scrub-words"
}

sf_all() {   # sf_all <repo>: the --all scan in $SF_LOC; output in SF_OUT, status the scan's
  SF_OUT="$(cd "$1" && LC_ALL="${SF_LOC:-C}" bash "$REPO/.githooks/pre-commit" --all 2>&1)"
}

# sf_push_repo <dir>: a repo with a bare remote, a fake private word in its
# .scrub-words, and one clean commit already pushed. Sets SF_R, SF_C0, SF_WORD
# and SF_ZERO.
sf_push_repo() {
  SF_R="$1/r"
  SF_WORD="zq$(printf 'vx')kwplm"
  SF_ZERO="$(printf '%040d' 0)"
  sf_git init -q "$SF_R" && sf_git init -q --bare "$1/remote.git" \
    && sf_git -C "$SF_R" remote add origin "$1/remote.git" || return 1
  printf '%s\n' "$SF_WORD" > "$SF_R/.scrub-words"
  sf_add "$SF_R" README 'clean\n' && sf_git -C "$SF_R" commit -qm start \
    && sf_git -C "$SF_R" push -q origin main || return 1
  SF_C0="$(git -C "$SF_R" rev-parse HEAD)"
}

sf_branch_commit() {   # sf_branch_commit <branch> <file> <printf format> [args]: one commit on a new branch from SF_C0
  local b="$1"
  shift
  sf_git -C "$SF_R" checkout -q -b "$b" "$SF_C0" && sf_add "$SF_R" "$@" && sf_git -C "$SF_R" commit -qm "$b"
}

sf_scan_branch() {   # sf_scan_branch <branch>: push-scan it as a new ref, in $SF_LOC; output in SF_OUT
  local tip
  tip="$(git -C "$SF_R" rev-parse "refs/heads/$1")" || return 2
  SF_OUT="$(LC_ALL="${SF_LOC:-C}" sf_scan_push "$SF_R" "refs/heads/$1 $tip refs/heads/$1 $SF_ZERO")"
}

# The file scan (staged and --all) reads binary and non-UTF-8 files, takes the
# word list however it was saved, finds embedded private keys and covers its
# own scripts. Its reports never repeat a token or a private word.
sf_check_scanner_content() {
  local d word tok SF_LOC bad=""
  d="$(mktemp -d "$H_TMP/content.XXXXXX")" || return 1
  word="zq$(printf 'vx')kwplm"
  tok="$(sf_fake_token)"
  SF_LOC="$(sf_utf8_locale)"
  sf_all_repo "$d/plain" '%s\n' "$word" && sf_add "$d/plain" a.txt 'x %s y\n' "$word" || return 1
  sf_all "$d/plain" || sf_has "$SF_OUT" "$word" && bad="$bad; a report repeats the private word"
  sf_all_repo "$d/nul" '' && sf_add "$d/nul" asset.dat 'BIN\000\nk=%s\n' "$tok" || return 1
  if sf_all "$d/nul"; then bad="$bad; a token in a file with a NUL byte"
  elif sf_has "$SF_OUT" "$tok"; then bad="$bad; a report repeats the token"; fi
  sf_all_repo "$d/latin" '%s\n' "$word" && sf_add "$d/latin" l1.txt 'caf\351 %s\n' "$word" || return 1
  sf_all "$d/latin" && bad="$bad; a word on a line with a Latin-1 byte"
  sf_all_repo "$d/crlf" '%s\r\n' "$word" && sf_add "$d/crlf" a.txt 'x %s y\n' "$word" || return 1
  sf_all "$d/crlf" && bad="$bad; a word list saved with CRLF"
  sf_all_repo "$d/nonl" '%s' "$word" && sf_add "$d/nonl" a.txt 'x %s y\n' "$word" || return 1
  sf_all "$d/nonl" && bad="$bad; a word list without a final newline"
  sf_all_repo "$d/space" '%s \n' "$word" && sf_add "$d/space" a.txt 'x %s y\n' "$word" || return 1
  sf_all "$d/space" && bad="$bad; a word with a trailing space in the list"
  sf_all_repo "$d/key" '' \
    && sf_add "$d/key" k.json '{"private_key": "%sBEGIN PRIVATE KEY%s\\nabc"}\n' '-----' '-----' || return 1
  sf_all "$d/key" && bad="$bad; a private key inside a JSON value"
  sf_all_repo "$d/doctor" '%s\n' "$word" && sf_add "$d/doctor" lib/doctor.sh '# %s\n' "$word" || return 1
  sf_all "$d/doctor" && bad="$bad; a private word in lib/doctor.sh"
  sf_all_repo "$d/syntax" '' && sf_add "$d/syntax" bad.sh 'if then %s\n' "$tok" || return 1
  sf_all "$d/syntax"
  sf_has "$SF_OUT" "$tok" && bad="$bad; the syntax report repeats a token"
  [ -z "$bad" ] || { printf 'file scan got wrong:%s\n' "${bad#;}"; return 1; }
}

# The push scan reads content git calls binary or that is not UTF-8, sees
# through replace refs, handles odd file names, and checks file names without
# mistaking a repo path such as tests/fixtures/home/ for a home directory.
sf_check_push_content() {
  local d cr k1 SF_LOC bad=""
  d="$(mktemp -d "$H_TMP/pushcontent.XXXXXX")" && sf_push_repo "$d" || return 1
  SF_LOC="$(sf_utf8_locale)"
  sf_branch_commit nul asset.dat 'BIN\000\nowner=%s\n' "$SF_WORD" || return 1
  sf_scan_branch nul && bad="$bad; a file with a NUL byte"
  sf_branch_commit attr .gitattributes '*.json -diff\n' && sf_add "$SF_R" x.json '{"o": "%s"}\n' "$SF_WORD" \
    && sf_git -C "$SF_R" commit -qm json || return 1
  sf_scan_branch attr && bad="$bad; a file marked -diff"
  sf_branch_commit latin l1.txt 'caf\351 %s\n' "$SF_WORD" || return 1
  sf_scan_branch latin && bad="$bad; a line with a Latin-1 byte"
  sf_branch_commit rep rep.txt 'about %s\n' "$SF_WORD" || return 1
  cr="$(git -C "$SF_R" rev-parse HEAD)"
  k1="$(sf_git -C "$SF_R" commit-tree -m clean -p "$SF_C0" "$SF_C0^{tree}")" \
    && sf_git -C "$SF_R" replace "$cr" "$k1" || return 1
  sf_scan_branch rep && bad="$bad; a leak behind a replace ref"
  sf_branch_commit keyname 'my key.pem' '%sBEGIN PRIVATE KEY%s\nabc\n' '-----' '-----' || return 1
  sf_scan_branch keyname && bad="$bad; a key in a file whose name has a space"
  sf_branch_commit fname "notes-$SF_WORD.txt" 'clean\n' || return 1
  if sf_scan_branch fname; then bad="$bad; a private word in a file name"
  elif sf_has "$SF_OUT" "$SF_WORD"; then bad="$bad; a report repeats the private word"; fi
  sf_branch_commit fixture "tests/fixtures/$(printf 'ho%s' me)/user1/settings.json" '{}\n' || return 1
  sf_scan_branch fixture || bad="$bad; a repo path under home/ was blocked"
  [ -z "$bad" ] || { printf 'push scan got wrong:%s\n' "${bad#;}"; return 1; }
}

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

# A push publishes more than commit content: author and committer identities,
# ref names and annotated tag objects. A ref to a blob, a tree or an object the
# clone lacks is refused, since the scan reads commits and tags only.
sf_check_push_refs() {
  local d tag blob bad=""
  d="$(mktemp -d "$H_TMP/pushrefs.XXXXXX")" && sf_push_repo "$d" || return 1
  sf_git -C "$SF_R" checkout -q -b ident "$SF_C0" && sf_add "$SF_R" i.txt 'clean\n' \
    && sf_git -C "$SF_R" -c user.email="dev@$SF_WORD.example" commit -qm ident || return 1
  sf_scan_branch ident && bad="$bad; a private word in an author email"
  if SF_OUT="$(sf_scan_push "$SF_R" "refs/heads/$SF_WORD-wip $SF_C0 refs/heads/$SF_WORD-wip $SF_ZERO")"; then
    bad="$bad; a private word in a ref name"
  elif sf_has "$SF_OUT" "$SF_WORD"; then bad="$bad; a report repeats the ref name"; fi
  sf_git -C "$SF_R" tag -a v1 -m "about $SF_WORD" "$SF_C0" || return 1
  tag="$(git -C "$SF_R" rev-parse refs/tags/v1)"
  SF_OUT="$(sf_scan_push "$SF_R" "refs/tags/v1 $tag refs/tags/v1 $SF_ZERO")" && bad="$bad; a private word in a tag message"
  blob="$(printf 'x\n' | git -C "$SF_R" hash-object -w --stdin)" || return 1
  SF_OUT="$(sf_scan_push "$SF_R" "refs/tags/b $blob refs/tags/b $SF_ZERO")" && bad="$bad; a ref to a blob"
  SF_OUT="$(sf_scan_push "$SF_R" "refs/heads/z $(printf '%040d' 1) refs/heads/z $SF_ZERO")" \
    && bad="$bad; a ref to an object the clone lacks"
  [ -z "$bad" ] || { printf 'push scan got wrong:%s\n' "${bad#;}"; return 1; }
}

self_suite() {
  h_check hook-git-env-cleared "a hook's GIT_DIR does not redirect the suites' git -C calls" sf_check_git_env_cleared
  h_check suite-load-guard "a suite that fails to load, exits or reports nothing fails the run" sf_check_suite_load_guard
  h_check static-keeps-going "the static suite still scans when the settings do not build" sf_check_static_keeps_going
  h_check scanner-hides-hits "the leak scanner reports where a hit is, never the matched text" sf_check_scanner_hides_hits
  h_check scanner-content "the file scan handles binary, non-UTF-8, odd word lists and embedded keys" sf_check_scanner_content
  h_check push-scan "pre-push scans every commit a push publishes, messages included" sf_check_push_scan
  h_check push-content "the push scan handles binary, non-UTF-8, replace refs and odd names" sf_check_push_content
  h_check push-refs "the push scan covers identities, ref names and tags, and refuses other objects" sf_check_push_refs
  h_check missing-word-list "a leak scan without a private-word list says so" sf_check_missing_word_list
  h_check prepush-log-private "pre-push logs are private, inside the clone, and pruned" sf_check_prepush_log
}
