#!/usr/bin/env bash
# PreToolUse / Bash — refuse commands whose OUTPUT is credential material.
#
# Why: MemPalace's Stop and PreCompact hooks checkpoint tool output into the
# palace, and `mempalace hook run` has no redaction option. A credential printed
# once therefore persists in the sessions wing and resurfaces in future searches.
# With `assume <profile>` none of these commands is needed inside a session.
#
# Scope (narrowed 2026-09-11): only commands that emit an AWS credential set.
# `env`/`printenv`, `gh auth token`, and `~/.aws/config` reads are NOT matched —
# they blocked legitimate diagnostics, and reads of ~/.aws/** are already denied
# by the permission rules.
#
# Exit 2 = block, reason on stderr. Exit 0 = allow (silent).
cmd=$(jq -r '.tool_input.command // empty')
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
exit 0
