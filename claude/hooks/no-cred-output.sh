#!/usr/bin/env bash
# PreToolUse / Bash — refuse commands whose OUTPUT is credential material.
#
# Why: MemPalace's Stop and PreCompact hooks checkpoint tool output into the
# palace, and `mempalace hook run` has no redaction option. A credential printed
# once therefore persists in the sessions wing and resurfaces in future searches.
# With `assume <profile>` none of these commands is needed inside a session.
#
# Scope (narrowed 2026-09-11): only commands that emit a credential.
# `env`/`printenv` and `~/.aws/config` reads are NOT matched — they blocked
# legitimate diagnostics, and reads of ~/.aws/** are already denied by the
# permission rules.
# GitHub (added 2026-11-11): `gh auth token` and `gh auth status --show-token|-t`
# are blocked unless the token goes straight into a variable, as in
#   GH_TOKEN="$(gh auth token -u <account>)" git push ...
# which uses it without printing it. Case table: tests/fixtures/no-cred-output.tsv.
#
# Exit 2 = block, reason on stderr. Exit 0 = allow (silent).
# Unparsable input fails (exit 1) rather than passing: with onFailure "block" the
# call is then blocked, which is the point of a fail-closed guard.
cmd=$(jq -r '.tool_input.command // empty') || { printf 'no-cred-output: could not parse the hook input\n' >&2; exit 1; }
[ -z "$cmd" ] && exit 0

if printf '%s' "$cmd" | grep -Eq \
  'aws[[:space:]]+sts[[:space:]]+(assume-role|assume-role-with-saml|assume-role-with-web-identity|get-session-token|get-federation-token)|aws[[:space:]]+configure[[:space:]]+export-credentials|granted[[:space:]]+credential-process|assume[[:space:]]+(-x|--export-all-env-vars)|\.aws/credentials'
then
  cat >&2 <<'MSG'
BLOCKED: this command prints AWS credentials to stdout, and tool output is
checkpointed into MemPalace by the Stop/PreCompact hooks — a credential printed
once persists in the palace and resurfaces in later searches.

Instead: run `assume <profile>` in your own shell and give Claude the profile
name. To verify identity without exposing anything:  aws sts get-caller-identity
MSG
  exit 2
fi

# Drop the one allowed form, VAR=$(gh auth token ...) with optional quotes, then
# block whatever gh token output is left.
# Arguments inside the allowed form are limited to flags, hosts and account names:
# no ; | & > < or nested substitutions can hide in it.
# The form is only exempt as an assignment at the start of a command (line start,
# after ; & | ( or then/do, optionally after export), so `echo X="$(gh auth token)"`
# still counts as printing.
rest=$(printf '%s' "$cmd" | sed -E 's/(^|[;&|(]|(^|[[:space:]])(then|do))([[:space:]]*)(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\([[:space:]]*gh[[:space:]]+auth[[:space:]]+token[-A-Za-z0-9._@[:space:]]*\)"?/\1\4/g')
# Only where gh is in command position (line start, after ; & | ( ` { !, or after
# then/do/else/command/env/exec/time/xargs/sudo; a path prefix like /opt/x/bin/gh
# counts), so text that merely mentions it, in a grep pattern or commit message,
# passes. Status: --show-token, or any short-flag group containing t.
if printf '%s' "$rest" | grep -Eq \
  '(^|[;&|(`{!]|(^|[[:space:]])(then|do|else|command|env|exec|time|xargs|sudo))[[:space:]]*\\?([^[:space:]"'"'"']*/)?gh[[:space:]]+auth[[:space:]]+(token|status([^;&|]*[[:space:]])(--show-token|-[A-Za-z]*t[A-Za-z]*)([[:space:]=]|$))'
then
  cat >&2 <<'MSG'
BLOCKED: this command prints a GitHub token, and tool output is checkpointed
into MemPalace — a token printed once persists in the palace.

Instead: pass it straight into the variable that needs it, without printing:
  GH_TOKEN="$(gh auth token -h github.com -u <account>)" <command>
To check which account is active:  gh auth status   (without --show-token)
MSG
  exit 2
fi
exit 0
