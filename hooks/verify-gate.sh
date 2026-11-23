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
#
# Before the command runs, the files the session changed are compared with the
# HEAD it first found in the tree, so its commits count too. A changed verify
# command or a script it runs, a changed test runner, linter or type checker
# config, a deleted test file, fewer test cases, a changed assertion, an added
# skip, only or suppression marker, or a rewritten snapshot sends the turn back
# once with the list, so the reply says why the check had to change. A list
# shown once lets the turn end.

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
mkdir -p "$state/edited" "$state/pass" "$state/last" "$state/logs" "$state/locks" \
  "$state/base" "$state/files" "$state/seen" 2>/dev/null || exit 0

toplevel_of() {
  local d=$1
  [ -d "$d" ] || d=$(dirname "$d")
  while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
  git -C "$d" rev-parse --show-toplevel 2>/dev/null
}

rel_of() {
  local d=$1 rest=""
  while [ ! -d "$d" ] && [ "$d" != / ]; do rest="/${d##*/}$rest"; d=$(dirname "$d"); done
  printf '%s%s' "$(git -C "$d" rev-parse --show-prefix 2>/dev/null)" "${rest#/}"
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

note_base() {
  local f="$state/base/$(key_of "$session $1")"
  [ -f "$f" ] || printf '%s\n%s\n' "$(git -C "$1" rev-parse HEAD 2>/dev/null)" "$(verify_cmd "$1")" >"$f"
}

# npm scripts the verify script reaches by name, through npm run, npm-run-all
# and their pre and post scripts.
jq_reach='
def cut: if length > 120 then .[0:117] + "..." else . end;
def toks: [splits("[^A-Za-z0-9:_.*@/-]+")] | map(select(. != "") | sub("^npm:"; ""));
def expand($s): if endswith("*") then rtrimstr("*") as $pre | ($s | keys[] | select(startswith($pre))) else . end;
def reach($s; $from):
  def go($seen): [$seen[] | (($s[.] // "") | toks[] | expand($s)), "pre" + ., "post" + .]
    | map(select(. as $k | $s | has($k))) | . + $seen | unique
    | if . == $seen then . else go(.) end;
  go([$from[] | select(. as $k | $s | has($k))] | unique);
'

scripts_of() {
  local s
  if [ "$2" = - ]; then s=$(jq -c '.scripts // {}' "$1/$3" 2>/dev/null)
  else s=$(git -C "$1" show "$2:$3" 2>/dev/null | jq -c '.scripts // {}' 2>/dev/null); fi
  printf '%s' "${s:-"{}"}"
}

scripts_changed() {
  jq -rn --argjson a "$(scripts_of "$1" "$2" "$3")" --argjson b "$(scripts_of "$1" - "$3")" \
    --argjson ta "$(scripts_of "$1" "$2" package.json)" --argjson tb "$(scripts_of "$1" - package.json)" \
    --arg f "$3" "$jq_reach"'
    (["verify"] + if $f == "package.json" then [] else
      [(reach($ta; ["verify"])[] | $ta[.]), (reach($tb; ["verify"])[] | $tb[.]) | toks[]] end) as $from
    | reach($a; $from) + reach($b; $from) | unique[] | select($a[.] != $b[.])
    | "\($f): the script \"\(.)\", which the verify command runs, " + (if $b[.] == null then "was removed"
      elif $a[.] == null then "was added: \($b[.] | cut)" else "now reads: \($b[.] | cut)" end)'
}

# Files the verify command or its npm scripts name, and the Makefile behind make verify.
watched() {
  local top=$1 base=$2 t
  {
    printf '%s\n%s\n' "$3" "$4"
    jq -rn --argjson a "$(scripts_of "$top" "$base" package.json)" --argjson b "$(scripts_of "$top" - package.json)" \
      "$jq_reach"'(reach($a; ["verify"])[] | $a[.]), (reach($b; ["verify"])[] | $b[.])'
  } | tr -s ' \t;&|()"'"'" '\n' | sed 's|^\./||' | sort -u | while IFS= read -r t; do
    case $t in ''|*package.json) continue ;; esac
    [ -f "$top/$t" ] && printf '%s\n' "$t"
  done
  case "$3 $4" in *make*) [ -f "$top/Makefile" ] && echo Makefile ;; esac
}

diff_lines='
/^diff --git / { hdr = 1; next }
hdr && /^\+\+\+ / { cur = substr($0, 5); if (cur == "/dev/null") cur = ""; else sub(/^b\//, "", cur); next }
/^@@/ { hdr = 0; next }
hdr || cur == "" { next }
/^[+-]/ { print "L\t" cur "\t" $0 }
'

classify='
function is_test(p) {
  return p ~ /(^|\/)(tests?|__tests__|specs?|e2e|playwright|cypress)\// ||
    p ~ /\.(test|spec|e2e|cy)\.[A-Za-z0-9]+$/ || p ~ /(_test\.(go|py|rb|exs?|dart)|_spec\.rb)$/ ||
    p ~ /(^|\/)test_[^\/]*\.py$/ || p ~ /(Test|Tests|Spec)\.(java|kt|php|swift|cs|scala)$/
}
function is_snap(p) {
  return p ~ /(^|\/)(__snapshots__|__screenshots__)\// || p ~ /-snapshots\// || p ~ /\.(snap|ambr)$/ || p ~ /\.approved\./
}
function is_config(p,  b) {
  b = p; sub(/.*\//, "", b)
  return b ~ /^(jest|vitest|playwright|cypress)\.config\./ || b ~ /^(vitest\.workspace|karma\.conf)\./ ||
    b ~ /^\.mocharc/ || b ~ /^(pytest|mypy|tox)\.ini$/ || b ~ /^(\.flake8|\.?ruff\.toml|clippy\.toml)$/ ||
    b ~ /^(phpunit\.xml|phpstan\.neon|psalm\.xml)/ || b ~ /^(\.eslintrc|eslint\.config\.|\.prettierrc|\.stylelintrc)/ ||
    b ~ /^\.(eslint|prettier|stylelint)ignore$/ || b ~ /^biome\.jsonc?$/ || b ~ /^tsconfig.*\.json$/ ||
    b ~ /^(\.golangci\.|\.rubocop|\.swiftlint|detekt)/ || b ~ /^analysis_options\.yaml$/
}
function is_def(t) {
  return t ~ /^((it|test|describe|context)(\.[a-z]+)*(\(| ")|(async )?def test_|func Test|(public )?function test|#\[(tokio::)?test|@(Test|ParameterizedTest)([^A-Za-z]|$)|fn test_|test_that\()/
}
function short(s) { return length(s) > 100 ? substr(s, 1, 97) "..." : s }
BEGIN { n = split(ENVIRON["WATCH"], w, "\n"); for (i = 1; i <= n; i++) if (w[i] != "") watch[w[i]] = 1 }
$1 == "S" {
  p = $3
  if ($2 == "D") {
    if (is_test(p)) print p ": test file deleted"
    else if (is_snap(p)) print p ": snapshot deleted"
    else if (is_config(p) || (p in watch)) print p ": deleted, and it shapes what the verify command checks"
  } else if (is_config(p) || (p in watch)) shape[p] = 1
  else if (is_snap(p)) { if ($2 == "M") snap[p] = 0; else skip[p] = 1 }
  next
}
$1 == "L" {
  p = $2; t = substr($0, length(p) + 4); sign = substr(t, 1, 1); t = substr(t, 2)
  gsub(/^[ \t]+|[ \t]+$/, "", t)
  if (p in skip) next
  if (p in snap) { snap[p]++; next }
  if (p in shape) {
    if (++shown[p] <= 5) print p ": " (sign == "+" ? "adds" : "removes") " a line in a file that shapes the check: " short(t)
    else more[p]++
    next
  }
  if (sign == "+") add[p SUBSEP t]++; else del[p SUBSEP t]++
  if (is_test(p) && is_def(t)) { if (sign == "-") gone[p]++; else came[p]++ }
}
END {
  for (k in add) {
    if ((k in del) && del[k] >= add[k]) continue
    split(k, a, SUBSEP); p = a[1]; t = a[2]
    if (t ~ /eslint-disable|@ts-(ignore|expect-error|nocheck)|biome-ignore|type: *ignore|noqa|pylint: *disable|@phpstan-ignore|@psalm-suppress|phpcs:(ignore|disable)|nolint|#!?\[allow\(|@Suppress|rubocop:(disable|todo)|(istanbul|c8|v8) ignore|swiftlint:disable|\/\/ *ignore(_for_file)?:|NOSONAR|prettier-ignore|stylelint-disable/)
      print p ": adds a check suppression: " short(t)
    else if (is_test(p) && t ~ /(^|[^A-Za-z0-9_])(it|test|describe|context|suite|bench)(\.[a-z]+)*\.(skip|only|todo|fixme)([ (.]|$)|(^|[^A-Za-z0-9_.])(xit|xtest|xdescribe|xcontext|fit|fdescribe)\(|pytest\.mark\.(skip|skipif|xfail)|unittest\.(skip|expectedFailure)|pytest\.skip\(|\.skipTest\(|markTest(Skipped|Incomplete)|->(skip|todo)\(|(^|[^A-Za-z0-9_])t\.Skip(Now|f)?\(|#\[ignore|@(Disabled|Ignore)([^A-Za-z]|$)|XCTSkip|skip: *true/)
      print p ": skips or narrows tests: " short(t)
  }
  for (k in del) {
    if ((k in add) && add[k] >= del[k]) continue
    split(k, a, SUBSEP); p = a[1]; t = a[2]
    if (is_test(p) && !is_def(t) && t ~ /expect\(|assert|Assert|\.should|\.to(Be|Equal|Match|Have|Throw|Contain)|(^|[^A-Za-z0-9_])t\.(Error|Fatal)|require\.[A-Z]|refute/)
      print p ": changes or removes an assertion: " short(t)
  }
  for (p in gone) if (gone[p] > came[p]) print p ": " gone[p] - came[p] " fewer test cases than before"
  for (p in more) print p ": " more[p] " more changed lines in a file that shapes the check"
  for (p in snap) print p ": snapshot rewritten" (snap[p] ? ", " snap[p] " lines differ" : "")
}
'

# Prints the changes to the check that this session has not been shown yet.
guard() {
  local top=$1 key=$2 cmd=$3 base="" was="" f all files=()
  [ -s "$state/files/$key" ] || return 0
  { IFS= read -r base; IFS= read -r was; } <"$state/base/$key" 2>/dev/null
  [ -n "$cmd$was" ] || return 0
  { [ -n "$base" ] && git -C "$top" merge-base --is-ancestor "$base" HEAD 2>/dev/null; } || base=HEAD
  while IFS= read -r f; do files+=("$f"); done <"$state/files/$key"
  export GIT_LITERAL_PATHSPECS=1
  all=$(
    [ "$cmd" = "$was" ] || printf 'the verify command was `%s` and is now `%s`\n' "${was:-none}" "${cmd:-none}"
    for f in "${files[@]}"; do
      case $f in (package.json|*/package.json) scripts_changed "$top" "$base" "$f" ;; esac
    done
    {
      git -C "$top" -c core.quotePath=false diff --name-status --no-renames "$base" -- "${files[@]}" | sed 's/^/S	/'
      git -C "$top" ls-files --others --exclude-standard -z -- "${files[@]}" | while IFS= read -r -d '' f; do
        printf 'S\tA\t%s\n' "$f"
        grep -Iq . "$top/$f" 2>/dev/null && awk -v p="$f" '{ print "L\t" p "\t+" $0 }' "$top/$f"
      done
      git -C "$top" -c core.quotePath=false diff --no-color --no-ext-diff --no-renames -U0 "$base" -- "${files[@]}" |
        awk "$diff_lines"
    } | WATCH="$(watched "$top" "$base" "$cmd" "$was")" awk -F'\t' "$classify"
  )
  unset GIT_LITERAL_PATHSPECS
  all=$(printf '%s\n' "$all" | sed '/^$/d' | sort -u)
  [ -n "$all" ] || return 0
  touch "$state/seen/$key"
  printf '%s\n' "$all" | grep -vxF -f "$state/seen/$key"
  printf '%s\n' "$all" >>"$state/seen/$key"
}

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
    note_base "$top"
    files="$state/files/$(key_of "$session $top")"
    rel=$(rel_of "$f")
    grep -qxF "$rel" "$files" 2>/dev/null || printf '%s\n' "$rel" >>"$files"
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
    [ -n "$top" ] || exit 0
    note_base "$top"
    cmd=$(verify_cmd "$top")
    [ -n "$cmd" ] && [ "$c" = "$cmd" ] && : >"$state/pass/$(fingerprint "$top" "$cmd")"
  fi
  exit 0
fi

find "$state" -type f -mtime +14 -delete 2>/dev/null
list="$state/edited/$session"
[ -s "$list" ] || exit 0

block="" guarded="" note="" keep=""
while IFS= read -r top; do
  [ -d "$top" ] || continue
  cmd=$(verify_cmd "$top")
  key=$(key_of "$session $top")
  found=$(guard "$top" "$key" "$cmd")
  if [ -n "$found" ]; then
    n=$(printf '%s\n' "$found" | wc -l | tr -d ' ')
    keep+="$top"$'\n'
    guarded+="In $top this session changed what the verify command checks:"$'\n'
    guarded+="$(printf '%s\n' "$found" | head -n 20 | sed 's/^/- /')"$'\n'
    [ "$n" -gt 20 ] && guarded+="- and $((n - 20)) more"$'\n'
    guarded+=$'\n'
    continue
  fi
  [ -n "$cmd" ] || continue
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

reason=""
if [ -n "$guarded" ]; then
  reason+="Verify gate: $guarded"
  reason+="A changed check can make the verify command pass without fixing anything. Undo each change above that this task does not need. For each one it does need, such as a test whose expected behaviour the task changed, and each one that was there before this session, say in the closing reply what changed and why. Then end the turn again: the gate shows each change once and runs the verify command there at the next stop."
fi
if [ -n "$block" ]; then
  [ -z "$reason" ] || reason+=$'\n\n'
  reason+="Verify gate: $block"
  reason+="Fix what this session's change broke and end the turn again; the gate runs the command again. If the failure does not come from this session's change, or needs the user, end the turn without changing files there and say so in the reply: the gate lets an unchanged tree through."
fi
if [ -n "$reason" ]; then
  jq -n --arg r "$reason" --arg m "${note%$'\n'}" \
    '{decision: "block", reason: $r} + (if $m == "" then {} else {systemMessage: $m} end)'
elif [ -n "$note" ]; then
  jq -n --arg m "${note%$'\n'}" '{systemMessage: $m}'
fi
exit 0
