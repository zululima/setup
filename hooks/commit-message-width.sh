#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses a commit whose message has a
# line over 72 columns, which neither GitHub nor git log reflows. It reads the
# message of git commit -F <file> or --file <file>, of a heredoc after -F -,
# and of sync.sh --commit <file>. A file named by a variable is found when the
# command assigns it. A line with no space to break at, such as a long address,
# goes through, and -m messages are not looked at.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null)" || exit 0
case "$cmd" in
  *commit*) ;;
  *) exit 0 ;;
esac
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
head="${cmd%%<<*}"
head="${head//$'\\\n'/ }"

sp='[[:space:]]'
token="(\"[^\"]*\"|'[^']*'|[^[:space:];&|()]+)"
git_commit="(^|[;&|({]|$sp)git($sp+-[Cc]$sp*$token)*$sp+commit($sp|\$)"
sync_commit="sync\\.sh$sp+--commit$sp+$token"
file_flag="$sp(-F$sp*|--file=|--file$sp+)$token"

unquote() {
  local v="$1"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

if [[ $head =~ $sync_commit ]]; then
  file="$(unquote "${BASH_REMATCH[1]}")"
elif [[ $head =~ $git_commit ]]; then
  after=" ${head#*"${BASH_REMATCH[0]}"}"
  [[ $after =~ $file_flag ]] || exit 0
  file="$(unquote "${BASH_REMATCH[2]}")"
else
  exit 0
fi

if [ "$file" = - ]; then
  heredoc="<<-?$sp*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?"
  [[ $cmd =~ $heredoc ]] || exit 0
  message="$(printf '%s\n' "$cmd" | awk -v d="${BASH_REMATCH[1]}" '
    started { line = $0; sub(/^\t+/, "", line); if (line == d) exit; print; next }
    /<</ { started = 1 }')"
else
  name_re='^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$'
  if [[ $file =~ $name_re ]]; then
    name="${BASH_REMATCH[1]}"
    if [ "$name" = HOME ]; then
      file="$HOME"
    else
      assign="(^|[;&|(]|$sp)$name=$token"
      [[ $head =~ $assign ]] || exit 0
      file="$(unquote "${BASH_REMATCH[2]}")"
    fi
  fi
  case "$file" in
    '~'/*) file="$HOME/${file#'~/'}" ;;
    '$HOME'/*) file="$HOME/${file#'$HOME/'}" ;;
    '${HOME}'/*) file="$HOME/${file#'${HOME}/'}" ;;
  esac
  case "$file" in
    *'$'*) exit 0 ;;
  esac
  if [ "${file#/}" = "$file" ]; then
    dirs=()
    move="(^|[;&|(]|$sp)(cd$sp+|git$sp+-C$sp*)$token"
    [[ $head =~ $move ]] && dirs+=("$(unquote "${BASH_REMATCH[3]}")")
    [ -n "$cwd" ] && dirs+=("$cwd")
    found=""
    for dir in ${dirs[@]+"${dirs[@]}"}; do
      case "$dir" in
        '~'/*) dir="$HOME/${dir#'~/'}" ;;
      esac
      [ "${dir#/}" = "$dir" ] && [ -n "$cwd" ] && dir="$cwd/$dir"
      if [ -f "$dir/$file" ]; then
        found="$dir/$file"
        break
      fi
    done
    file="$found"
  fi
  [ -n "$file" ] && [ -f "$file" ] || exit 0
  message="$(cat "$file")"
fi

for locale in C.UTF-8 en_US.UTF-8 C.utf8 en_US.utf8; do
  if locale -a 2>/dev/null | grep -qx "$locale"; then
    LC_ALL="$locale"
    break
  fi
done

long=""
n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  [ "${#line}" -le 72 ] && continue
  text="${line#"${line%%[![:space:]>]*}"}"
  case "$text" in
    *[[:space:]]*) long="$long  line $n, ${#line} columns: ${line:0:60}..."$'\n' ;;
  esac
done <<<"$message"
[ -n "$long" ] || exit 0

{
  echo "Refused by ~/.claude/hooks/commit-message-width.sh: the commit message has"
  echo "lines over 72 columns, which neither GitHub nor git log reflows. Wrap them"
  echo "at 72, quoted prompt lines as > lines too, and commit again:"
  echo
  printf '%s' "$long"
} >&2
exit 2
