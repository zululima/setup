#!/usr/bin/env bash

# Claude Code PreToolUse hook for show_pane. Refuses the tasks pane while
# anthropics/claude-code issue 111704 is open: closing the last tab of the
# right pane leaves the pane standing empty, so a tasks pane shown for a
# background run stays behind in the user's window after it closes. The issue's
# state is cached for a day, and a state gh cannot read counts as open.

set -u

command -v jq >/dev/null 2>&1 || exit 0
[ "$(jq -r '.tool_input.pane // empty' 2>/dev/null)" = tasks ] || exit 0

cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-hooks/claude-code-issue-111704"
if [ -z "$(find "$cache" -mtime -1 2>/dev/null)" ]; then
  state="$(gh issue view 111704 -R anthropics/claude-code --json state -q .state 2>/dev/null)"
  [ -n "$state" ] && mkdir -p "$(dirname "$cache")" && printf '%s\n' "$state" >"$cache"
fi
[ "$(cat "$cache" 2>/dev/null)" = CLOSED ] && exit 0

cat >&2 <<'EOF'
Refused by ~/.claude/hooks/tasks-pane-after-111704.sh: ~/.claude/CLAUDE.md
shows the tasks pane only once anthropics/claude-code issue 111704 is closed,
and it is still open, or gh could not tell. Until then a tasks pane that closes
again stays behind empty in the user's window. Say in the reply that the run
goes on in the background, and show no pane for it.
EOF
exit 2
