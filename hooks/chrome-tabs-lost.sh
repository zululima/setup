#!/usr/bin/env bash

# Claude Code hook for UserPromptSubmit. Claude in Chrome links a session to its
# tab group only while Chrome runs, so a restart of Chrome or the computer
# leaves the session with no group and no tabs, and nothing tells it so until
# its next browser step. When Chrome started after the session's last Claude in
# Chrome step, or is not running, this adds to the context the addresses the
# session's tabs last showed, read from the transcript, so it can open them
# again. It speaks once per lost group, and not at all for a session that never
# used Chrome, closed its last tab or quit Chrome itself. Anything missing lets
# the prompt through without a word.

set -u
command -v jq >/dev/null 2>&1 || exit 0

session="" transcript=""
{
  IFS= read -r session
  IFS= read -r transcript
} < <(jq -r '.session_id // "", .transcript_path // ""' 2>/dev/null)
case "$session" in "" | *[^A-Za-z0-9_-]*) exit 0 ;; esac
[ -f "$transcript" ] || exit 0

last="$(grep -F '"name":"mcp__claude-in-chrome__' "$transcript" | jq -r '
  select(.type == "assistant" and any(.message.content[]?;
    .type == "tool_use" and (.name | startswith("mcp__claude-in-chrome__"))))
  | .timestamp // empty | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2>/dev/null | tail -n 1)"
case "$last" in "" | *[^0-9]*) exit 0 ;; esac

pid="$(pgrep -o -x 'Google Chrome' || pgrep -o -x chrome || pgrep -o -x chromium)"
started=""
if [ -n "$pid" ]; then
  elapsed="$(ps -o etime= -p "$pid" 2>/dev/null | awk '{
    t = $1; d = 0
    if (i = index(t, "-")) { d = substr(t, 1, i - 1); t = substr(t, i + 1) }
    n = split(t, a, ":"); s = 0
    for (k = 1; k <= n; k++) s = s * 60 + a[k]
    print d * 86400 + s }')"
  [ -n "$elapsed" ] || exit 0
  started=$(($(date +%s) - elapsed))
  [ "$started" -gt "$last" ] || exit 0
fi

dir="${TMPDIR:-/tmp}/claude-chrome-tabs-lost"
mkdir -p "$dir" 2>/dev/null || exit 0
find "$dir" -type f -mtime +30 -delete 2>/dev/null
[ "$(cat "$dir/$session" 2>/dev/null)" != "$last" ] || exit 0
printf '%s\n' "$last" >"$dir/$session" 2>/dev/null

quit="$(grep -F -e 'quit app' -e 'ungroup' "$transcript" | jq -r --argjson last "$last" '
  select(.type == "assistant" and (.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= $last)
  | .message.content[]? | select(.type == "tool_use" and .name == "Bash")
  | .input.command // "" | select(test("quit app \"Google Chrome\"|\\{\"ungroup\""))' 2>/dev/null | head -n 1)"
[ -z "$quit" ] || exit 0

tabs="$(grep -F -e 'Tab Context:' -e 'tab(s) remain' "$transcript" | tail -n 50 | jq -n -r --slurpfile uses <(
  grep -F '"name":"mcp__claude-in-chrome__' "$transcript" | jq -c '
    select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and (.name | startswith("mcp__claude-in-chrome__")))
    | {id, input}' 2>/dev/null
) '
  (reduce $uses[] as $u ({}; .[$u.id] = true)) as $ours
  | [inputs | select(.type == "user") | .message.content[]?
     | select(.type == "tool_result" and $ours[.tool_use_id // ""])
     | .content | if type == "array" then map(select(.type == "text") | .text) | join("\n") else (. // "") end
     | select(test("Tab Context:|tab\\(s\\) remain"))]
  | last // empty
  | if test("\\b0 tab\\(s\\) remain") then empty else . end
  | split("\n")[]
  | capture("tabId (?<id>[0-9]+): \"(?<title>.*)\" \\(\"(?<url>.*)\"\\)\\s*$")?
  | select(.url != "" and .url != "about:blank" and (.url | startswith("chrome://") | not))
  | . as $tab
  # The listing cuts a long address short and can mask parts of its query, so the
  # address comes from the last navigate to the same page in that tab.
  | if (.url | test("\\[truncated\\]$")) then
      (.url | sub(".\\[truncated\\]$"; "")) as $cut
      | ($cut | split("?")[0]) as $page
      | ([$uses[].input | .. | objects
          | select((.url? | type) == "string" and ((.tabId? // "") | tostring) == $tab.id)
          | .url | select(startswith($cut) or . == $page or startswith($page + "?"))] | last) as $full
      | .url = ($full // ($cut + " (cut short in the transcript)"))
    else . end
  | "- \"\(.title)\": \(.url)"' 2>/dev/null)"
[ -n "$tabs" ] || exit 0

when() { date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M'; }
if [ -n "$started" ]; then
  chrome="Chrome started again at $(when "$started"), after this session's last browser step at $(when "$last")"
else
  chrome="Chrome has stopped since this session's last browser step at $(when "$last")"
fi

jq -n --arg chrome "$chrome" --arg tabs "$tabs" '{hookSpecificOutput: {
  hookEventName: "UserPromptSubmit",
  additionalContext: "Claude in Chrome links a session to its tab group only while Chrome runs. \($chrome), so this session no longer has its tab group, and its tabs are closed. They last showed:\n\($tabs)\n\nAs the first step of this turn, load the chrome skill and open again, in a new group of this session'"'"'s, each of these pages that a step of the work still waits on, such as one where a step waits on the user, so the user sees it in Chrome again. Leave out pages of finished work. Check what each page holds now, since anything only the tab held, such as form input or a step of a checkout, is gone, and name in the reply which pages were opened again and what was lost."
}}'
exit 0
