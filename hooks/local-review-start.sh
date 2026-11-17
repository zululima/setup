#!/usr/bin/env bash

# Claude Code PostToolUse hook for Bash. After a command that runs gh pr
# create, gh pr checkout or git push, it starts skills/local-review, which has
# a local model review the branch in the background, and hands the model the
# question to ask once the pull request or its review is handed over. It
# prints nothing when local-review skips the branch, such as a default branch,
# a model not pulled, automatic starts turned off or a run already at that head.
#
# The repository is the one named by git -C before the push, else by the first
# cd in the command, else the session's working directory.

set -u

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$command" ] || exit 0

sp='[[:space:]]'
arg='("[^"]*"|[^[:space:];&|()]+)'
printf '%s\n' "$command" |
  grep -Eq "(^|[;&|(])$sp*(git($sp+-C$sp+$arg)?$sp+push|gh$sp+pr$sp+(create|checkout))($sp|\$)" ||
  exit 0

dir="$(printf '%s\n' "$command" | grep -Eo "git$sp+-C$sp+$arg$sp+push" | head -n 1 |
  sed -E "s/^git$sp+-C$sp+//; s/$sp+push\$//")"
[ -n "$dir" ] || dir="$(printf '%s\n' "$command" | grep -Eo "(^|[;&|(])$sp*cd$sp+$arg" | head -n 1 |
  sed -E "s/^[;&|(]?$sp*cd$sp+//")"
dir="${dir#\"}"
dir="${dir%\"}"
case "$dir" in
  "~" | "~/"*) dir="$HOME${dir#"~"}" ;;
esac
base="${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"
case "$dir" in
  "") dir="$base" ;;
  /*) ;;
  *) dir="$base/$dir" ;;
esac

git -C "$dir" rev-parse --show-toplevel > /dev/null 2>&1 || exit 0
out="$("$HOME/.claude/skills/local-review/local-review.sh" start "$dir" 2>&1)" || exit 0
case "$out" in
  started:*) ;;
  *) exit 0 ;;
esac

context="A local review ${out#started: }: a local model reviews this branch in the background. Load the local-review skill. The reply that hands over this branch's pull request, or its review page, asks in the next-step box: Shall I stop the local review and check its findings?"

jq -n --arg context "$context" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
exit 0
