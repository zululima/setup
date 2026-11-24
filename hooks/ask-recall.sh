#!/usr/bin/env bash

# Claude Code hook that searches before Claude asks the user something. As a
# PreToolUse hook on the desktop app's wrap_up it reads the question in its
# ask field, and as a Stop hook the question that ends the closing message.
# It takes only questions that ask a fact, such as which, where or do you
# have, never a go-ahead or whether a step is done. It runs the recall skill's
# search over typed prompts, memory notes, meeting notes and background files,
# and when a hit comes close in meaning it sends the turn back with the hits
# to read, once a question and once a prompt, so a question they do not answer
# goes through the second time. The phrase lists are a heuristic. Without the
# index or Ollama the search has no meaning scores, and every question goes
# through.
# ASK_RECALL_SEARCH replaces the search command and ASK_RECALL_MIN the score.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$session" ] || exit 0

case "$event" in
  PreToolUse)
    question="$(printf '%s' "$input" | jq -r '
      select(.tool_name // "" | endswith("wrap_up")) | .tool_input.ask // empty' 2>/dev/null)" ;;
  Stop)
    [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = false ] || exit 0
    question="$(printf '%s' "$input" | jq -r '
      (.last_assistant_message // "")
      | sub("(?s)\n[#*_ ]*Prompt feedback\\b.*$"; "")
      | gsub("(?s)```.*?```"; "")
      | [splits("\n\\s*\n") | select(test("\\S"))] | .[-2:]
      | [.[] | splits("\n") | select(test("^\\s*>") | not)
         | sub("^[\\s*_#-]*(\\d+[.)]\\s*)?"; "") | sub("[\\s*_]+$"; "")
         | select(endswith("?"))]
      | last // ""' 2>/dev/null)" ;;
  *) exit 0 ;;
esac

question="$(printf '%s' "$question" | tr '\n' ' ' \
  | sed -E 's/^.*[.!?][[:space:]]+//; s/^[[:space:]*_"]+//; s/[[:space:]]+$//')"
case "$question" in ????????????*\?) ;; *) exit 0 ;; esac

lower="$(printf '%s' "$question" | tr '[:upper:]' '[:lower:]')"
fact='^((also|and|but|so|then),? )?(what|which|where|who|whom|whose|when|how|why|do you (have|use|own|know|keep|still|run|work|need|remember)|does your|mikä|mitkä|mitä|missä|mihin|mistä|milloin|miten|millä|kuka|ketkä|kenen|kumpi|kumman|montako|paljonko|käytätkö|onko sinulla)\b'
choice='\b(shall|should|may|can) (i|we)\b|\b(do|would) you (want|like|prefer)\b|\b(first|next|now|instead|later|today)\?$|\b(done|finished|ready|valmis|valmiit|tehty)\?$|\bor not\?$'
printf '%s' "$lower" | grep -qE "$fact" || exit 0
printf '%s' "$lower" | grep -qE "$choice" && exit 0

config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/claude-ask-recall"
mkdir -p "$state" 2>/dev/null || exit 0
hash="$(printf '%s' "$lower" | shasum | cut -c1-16)"
grep -qxF "$hash" "$state/$session.asked" 2>/dev/null && exit 0
prompt="$( { wc -l <"$config/prompt-log/$session.jsonl"; } 2>/dev/null | tr -d ' ')"
[ -n "$prompt" ] && [ "$(cat "$state/$session.prompt" 2>/dev/null)" = "$prompt" ] && exit 0

if [ -n "${ASK_RECALL_SEARCH:-}" ]; then
  found="$($ASK_RECALL_SEARCH "$question" 2>/dev/null)" || exit 0
else
  recall="$config/skills/recall/recall.py"
  [ -f "$recall" ] && [ -s "$config/state/recall/index.db" ] || exit 0
  command -v python3 >/dev/null 2>&1 || exit 0
  found="$(CLAUDE_CODE_SESSION_ID="$session" RECALL_BUDGET=0 python3 "$recall" "$question" \
    --kind session,prompt,memory,meeting,note --role '!assistant' --limit 3 --json 2>/dev/null)" \
    || exit 0
fi

hits="$(printf '%s' "$found" | jq -r --argjson min "${ASK_RECALL_MIN:-0.68}" '
  [.hits[]? | select((.cosine // 0) >= $min)] | sort_by(-.cosine)[]
  | "- \(.id) (\(.kind), \((.time // "")[0:10]), \(.project // "no project")): "
    + ((.snippet // "") | gsub("\\s+"; " ") | .[0:200])
' 2>/dev/null)"
[ -n "$hits" ] || exit 0

printf '%s\n' "$hash" >>"$state/$session.asked"
[ -n "$prompt" ] && printf '%s\n' "$prompt" >"$state/$session.prompt"

case "$event" in
  PreToolUse) after="call wrap_up again without the question." ;;
  *) after="end the turn again without the question." ;;
esac
cat >&2 <<EOF
Sent back once by ~/.claude/hooks/ask-recall.sh: an earlier session, memory
note or background file may already answer "$question"

$hits

Read each hit with python3 ~/.claude/skills/recall/recall.py show <id>, and
its file for more. If none answers the question, ask it as before: the hook
lets the same question through. If one does, act on that answer, name its
source in the reply and $after
EOF
exit 2
