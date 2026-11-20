#!/usr/bin/env bash

# Claude Code hook that keeps a turn going until the repository's verify
# command passes. After an Edit, Write, MultiEdit or NotebookEdit, or a Bash
# command whose bashEditDiff lists changed files, it notes the git work tree
# the session changed. When the turn ends, it runs that tree's verify command
# there and sends the turn back with the command's last lines while it fails.
#
# The verify command is `git config claude.verify` in the tree, where "off"
# turns the gate off, else `npm run verify` when package.json has a verify
# script, else `make verify` when the Makefile has a verify target. A tree with
# none is left alone.
#
# A pass is kept per fingerprint of HEAD, the diff against it, the untracked
# files and the command, so an unchanged tree is not run again, also when
# another session or Claude's own Bash run of the same command passed it. A
# failure on a tree that has not changed since the last failure lets the turn
# end, so a failure the session did not cause costs one round, and after
# CLAUDE_VERIFY_GATE_TRIES failures in a row, 3 unless set, the turn ends too.
# Both tell the user in a system message. Exit 127, a command missing from the
# hook's PATH, never sends a turn back.

set -u
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

state="${XDG_STATE_HOME:-$HOME/.local/state}/claude-verify-gate"
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"
tries_max="${CLAUDE_VERIFY_GATE_TRIES:-3}"
input=$(cat)
event=$(jq -r '.hook_event_name // ""' <<<"$input")
session=$(jq -r '.session_id // ""' <<<"$input")
[ -n "$session" ] || exit 0
session=${session//\//_}
mkdir -p "$state/edited" "$state/pass" "$state/last" "$state/logs" "$state/locks" 2>/dev/null || exit 0

toplevel_of() {
  local d=$1
  [ -d "$d" ] || d=$(dirname "$d")
  while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
  git -C "$d" rev-parse --show-toplevel 2>/dev/null
}

verify_cmd() {
  local c
  if c=$(git -C "$1" config --get claude.verify 2>/dev/null); then
    [ "$c" = off ] || printf '%s' "$c"
    return
  fi
  if [ -f "$1/package.json" ] && jq -e '.scripts.verify // empty' "$1/package.json" >/dev/null 2>&1; then
    printf 'npm run verify'
  elif [ -f "$1/Makefile" ] && grep -qE '^verify:' "$1/Makefile"; then
    printf 'make verify'
  fi
}

fingerprint() {
  {
    printf '%s\n' "$2"
    git -C "$1" rev-parse HEAD 2>/dev/null
    git -C "$1" diff HEAD --binary 2>/dev/null
    git -C "$1" ls-files --others --exclude-standard -z 2>/dev/null |
      while IFS= read -r -d '' f; do
        printf '%s ' "$f"
        git -C "$1" hash-object -- "$f" 2>/dev/null
      done
  } | git hash-object --stdin
}

key_of() { printf '%s' "$1" | git hash-object --stdin; }

if [ "$event" != Stop ]; then
  tool=$(jq -r '.tool_name // ""' <<<"$input")
  cwd=$(jq -r '.cwd // ""' <<<"$input")
  if [ "$tool" = Bash ]; then
    jq -r '.tool_response.bashEditDiff.changedFiles[]? // empty' <<<"$input"
  else
    jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input"
  fi | while IFS= read -r f; do
    case $f in /*) ;; *) f="$cwd/$f" ;; esac
    top=$(toplevel_of "$f") || continue
    [ -n "$top" ] || continue
    grep -qxF "$top" "$state/edited/$session" 2>/dev/null || printf '%s\n' "$top" >>"$state/edited/$session"
  done

  # Claude's own successful run of the verify command counts as a pass.
  if [ "$tool" = Bash ] && [ "$event" = PostToolUse ]; then
    c=$(jq -r '.tool_input.command // ""' <<<"$input")
    c=${c#"("}; c=${c%")"}
    dir=$cwd
    re='^cd +([^;&|]+) +&& +(.*)$'
    if [[ $c =~ $re ]]; then
      dir=${BASH_REMATCH[1]}; c=${BASH_REMATCH[2]}
      dir=${dir%\"}; dir=${dir#\"}; dir=${dir%\'}; dir=${dir#\'}
      case $dir in "~"*) dir="$HOME${dir#\~}" ;; /*) ;; *) dir="$cwd/$dir" ;; esac
    fi
    top=$(toplevel_of "$dir") || exit 0
    cmd=$(verify_cmd "$top")
    [ -n "$cmd" ] && [ "$c" = "$cmd" ] && : >"$state/pass/$(fingerprint "$top" "$cmd")"
  fi
  exit 0
fi

find "$state" -type f -mtime +14 -delete 2>/dev/null
list="$state/edited/$session"
[ -s "$list" ] || exit 0

block="" note="" keep=""
while IFS= read -r top; do
  [ -d "$top" ] || continue
  cmd=$(verify_cmd "$top")
  [ -n "$cmd" ] || continue
  key=$(key_of "$session $top")
  last="$state/last/$key"
  log="$state/logs/$key.log"

  lock="$state/locks/$(key_of "$top")"
  waited=0
  until mkdir "$lock" 2>/dev/null; do
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +20 2>/dev/null)" ]; then rmdir "$lock" 2>/dev/null; continue; fi
    [ "$waited" -ge 300 ] && { lock=""; break; }
    sleep 2; waited=$((waited + 2))
  done

  fp=$(fingerprint "$top" "$cmd")
  if [ -e "$state/pass/$fp" ]; then
    rm -f "$last"; { [ -z "$lock" ] || rmdir "$lock" 2>/dev/null; }; continue
  fi
  prev_fp="" tries=0
  [ -f "$last" ] && read -r prev_fp tries <"$last"
  if [ "$prev_fp" = "$fp" ]; then
    note+="Verify gate: \`$cmd\` still fails in $top, and the turn ended without a change since. Log: $log"$'\n'
    rm -f "$last"; { [ -z "$lock" ] || rmdir "$lock" 2>/dev/null; }; continue
  fi

  (cd "$top" && bash -c "$cmd") >"$log" 2>&1 </dev/null
  code=$?
  fp=$(fingerprint "$top" "$cmd")
  { [ -z "$lock" ] || rmdir "$lock" 2>/dev/null; }
  if [ "$code" -eq 0 ]; then
    : >"$state/pass/$fp"; rm -f "$last"; continue
  fi
  if [ "$code" -eq 127 ]; then
    note+="Verify gate: \`$cmd\` could not run in $top (exit 127, a command not found). Log: $log"$'\n'
    continue
  fi
  tries=$((tries + 1))
  if [ "$tries" -gt "$tries_max" ]; then
    note+="Verify gate: \`$cmd\` still fails in $top after $tries_max tries. Log: $log"$'\n'
    rm -f "$last"; continue
  fi
  printf '%s %s\n' "$fp" "$tries" >"$last"
  keep+="$top"$'\n'
  block+="\`$cmd\` failed in $top (exit $code, try $tries of $tries_max) after this session changed files there. Its last 40 lines, full log in $log:"$'\n'
  block+="$(tail -n 40 "$log")"$'\n\n'
done <"$list"

printf '%s' "$keep" >"$list"
[ -s "$list" ] || rm -f "$list"

if [ -n "$block" ]; then
  block+="Fix what this session's change broke and end the turn again; the gate runs the command again. If the failure does not come from this session's change, or needs the user, end the turn without changing files there and say so in the reply: the gate lets an unchanged tree through."
  jq -n --arg r "Verify gate: $block" --arg m "${note%$'\n'}" \
    '{decision: "block", reason: $r} + (if $m == "" then {} else {systemMessage: $m} end)'
elif [ -n "$note" ]; then
  jq -n --arg m "${note%$'\n'}" '{systemMessage: $m}'
fi
exit 0
