#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses a command that starts a Chrome
# or Chromium of its own: the browser binary run directly, headless or not, or
# `open` with --args or -n for Chrome. Rendering a page to a PDF or an image is
# browser work for Claude in Chrome, and a Chrome the session starts itself
# takes a Dock icon, can open a window over the user's work and keeps a profile
# of its own. Heredoc bodies are not looked at. Playwright's own Chromium,
# started through npx playwright, is not matched.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

cmd="$(printf '%s\n' "$cmd" | awk '
  skip { t = $0; if (tabs) sub(/^\t+/, "", t); if (t == delim) skip = 0; next }
  { print
    line = $0; gsub(/<<</, "", line)
    if (match(line, /<<-?[ \t]*["'\'']?[A-Za-z_][A-Za-z0-9_]*["'\'']?/)) {
      d = substr(line, RSTART, RLENGTH); tabs = (d ~ /^<<-/)
      sub(/^<<-?[ \t]*/, "", d); gsub(/["'\'']/, "", d); delim = d; skip = 1 } }')"
cmd="${cmd//$'\\\n'/ }"

hit=""
case "$cmd" in
  *"Contents/MacOS/Google Chrome"* | *"Contents/MacOS/Chromium"* | *"Contents/MacOS/Google Chrome Canary"*)
    hit="the Chrome binary" ;;
esac
if [ -z "$hit" ] && printf '%s\n' "$cmd" | grep -Eq '(^|[;&|( ])(google-chrome(-stable)?|chromium(-browser)?|chrome) +--'; then
  hit="the Chrome binary"
fi
if [ -z "$hit" ] && printf '%s\n' "$cmd" | grep -Eiq '(^|[;&|( ])open +([^;&|]* )?-[a-z]*a +"?(Google Chrome|Chromium)' \
  && printf '%s\n' "$cmd" | grep -Eq '(^|[;&|( ])open +([^;&|]* )?(--args|-[a-z]*n)'; then
  hit="open with --args or -n"
fi

[ -n "$hit" ] || exit 0
cat >&2 <<EOF
Refused by ~/.claude/hooks/no-own-chrome.sh: this command starts a Chrome of
its own through $hit. No session starts one, headless or with another profile,
also not to render a page to a PDF or an image. Load the chrome skill and do it
in Claude in Chrome, or, for a job Chrome cannot do that way, such as a vector
print PDF, ask the user first.
EOF
exit 2
