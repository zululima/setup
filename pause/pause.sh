#!/usr/bin/env bash

# Frees the CPU and memory at once, as when a call starts while work runs, and
# puts it all back after. Run as pause, it freezes build and test processes with
# their children, pauses every running Docker container, stops the local review
# runs and holds new ones off, which unloads their model, and unloads any other
# model Ollama holds. Run as resume, it undoes what the pauses since the last
# resume did and nothing else. Claude sessions, the apps on screen and the
# system are left alone. Command names listed one per line in more-names beside
# this script, which stays local, are frozen too. install.sh puts both names on
# the PATH.

set -u

# An app such as Overload starts this with the system's PATH alone.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
state="$HOME/.claude/state/pause"
file="$state/$(hostname -s)"
review="$HOME/.claude/skills/local-review/local-review.sh"
runs="$HOME/.claude/state/local-review/runs"
tools='vite|webpack|tsc|jest|vitest|playwright|eslint|next|nuxt|esbuild|rollup|npm-run-all|run-p|run-s|xcodebuild|XCBBuildService|swift-build|swift-frontend|swift-driver|swiftc|clang|ld|cargo|rustc|gradle|gradlew|ffmpeg|yt-dlp|whisper|whisper-cli|composer|phpunit|pytest'
managers='npm|pnpm|yarn|bun'
runners='node|bun|deno|python[0-9.]*|php|ruby|java|sh|bash|zsh'
more="$HOME/.claude/pause/more-names"
[ -s "$more" ] && tools="$tools|$(grep -v '^#' "$more" | grep . | paste -sd '|' -)"

started() { ps -o lstart= -p "$1" 2> /dev/null | tr -s ' ' | sed 's/^ //; s/ $//'; }

reverse() { tail -r "$1" 2> /dev/null || tac "$1"; }

busy_review_repos() {
  local d pid
  for d in "$runs"/*/; do
    pid="$(jq -r '.pid // empty' "$d/status.json" 2> /dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null && jq -r '.repo // empty' "$d/status.json"
  done
}

# Processes of this user that run one of the tools, as the program or as the
# script a runner such as node runs, and all their children, parents first,
# less this script, its ancestors and any job already stopped. Words further on
# in a command, such as a shell's -c string, never match.
heavy_pids() {
  ps -Ao pid=,ppid=,uid=,stat=,command= | awk -v me="$$" -v uid="$(id -u)" \
    -v tools="^($tools)\$" -v managers="^($managers)\$" -v runners="^($runners)\$" '
    {
      pid = $1; parent[pid] = $2; owner[pid] = $3; st[pid] = $4
      kids[$2] = kids[$2] " " pid; all[++n] = pid
      a = $5; b = $6; sub(/.*\//, "", a); sub(/.*\//, "", b)
      if (a ~ tools || (tolower(a) ~ runners && b ~ tools) || $5 ~ /ms-playwright\// ||
          (a ~ managers && $6 ~ /^(run|test|ci|install)$/)) hit[pid] = 1
    }
    END {
      for (p = me; p > 1 && (p in parent); p = parent[p]) skip[p] = 1
      for (i = 1; i <= n; i++) if (all[i] in hit) mark(all[i])
      for (i = 1; i <= n; i++) {
        p = all[i]
        if (!(p in take)) continue
        d = 0
        for (q = parent[p]; q in take; q = parent[q]) d++
        print d, p
      }
    }
    function mark(p,   k, list, i) {
      if (p in take || p in skip || owner[p] != uid || st[p] ~ /^[TZ]/) return
      take[p] = 1
      k = split(kids[p], list, " ")
      for (i = 1; i <= k; i++) mark(list[i])
    }' | sort -n | awk '{ print $2 }'
}

show_load() {
  echo
  if [ "$(uname -s)" = Darwin ]; then
    memory_pressure 2> /dev/null | awk -F': ' '/free percentage/ { print "memory free: " $2 }'
    echo "still busy:"
    ps -Ao %cpu=,comm= -r | head -n 5 | sed 's|  */.*/| |'
  else
    free -h | awk '/^Mem:/ { print "memory available: " $7 " of " $2 }'
    echo "still busy:"
    ps -eo %cpu=,comm= --sort=-%cpu | head -n 5
  fi
}

do_pause() {
  local pid name id m
  mkdir -p "$state"
  touch "$file"

  for pid in $(heavy_pids); do
    name="$(ps -o comm= -p "$pid" 2> /dev/null)"
    printf 'pid %s %s\n' "$pid" "$(started "$pid")" >> "$file"
    kill -STOP "$pid" 2> /dev/null && echo "froze $pid ${name##*/}"
  done

  if command -v docker > /dev/null; then
    for id in $(docker ps -q --filter status=running 2> /dev/null); do
      name="$(docker inspect -f '{{.Name}}' "$id" 2> /dev/null)"
      docker pause "$id" > /dev/null 2>&1 && echo "container $id" >> "$file" &&
        echo "paused container ${name#/}"
    done
  fi

  if [ -f "$review" ]; then
    if [ ! -e "$HOME/.claude/state/local-review/off" ]; then
      bash "$review" off > /dev/null && echo "review-on" >> "$file"
    fi
    busy_review_repos | while IFS= read -r repo; do
      echo "review $repo" >> "$file"
      echo "stopped local review in $repo"
    done
    for _ in 1 2 3 4 5; do
      [ -n "$(busy_review_repos)" ] || break
      (cd / && bash "$review" stop > /dev/null)
    done
  fi

  if command -v ollama > /dev/null && curl -s -m 2 http://127.0.0.1:11434/api/version > /dev/null; then
    for m in $(curl -s -m 5 http://127.0.0.1:11434/api/ps | jq -r '.models[]?.name'); do
      ollama stop "$m" > /dev/null 2>&1 && echo "unloaded model $m"
    done
  fi

  [ -s "$file" ] || { rm -f "$file"; echo "nothing to pause"; }
  show_load
}

do_resume() {
  local kind a b
  [ -s "$file" ] || { echo "nothing paused"; return 0; }

  while read -r kind a; do
    [ "$kind" = container ] || continue
    [ "$(docker inspect -f '{{.State.Paused}}' "$a" 2> /dev/null)" = true ] &&
      docker unpause "$a" > /dev/null && echo "unpaused container $(docker inspect -f '{{.Name}}' "$a" | sed 's|^/||')"
  done < "$file"

  reverse "$file" | while read -r kind a b; do
    [ "$kind" = pid ] || continue
    [ "$(started "$a")" = "$b" ] && kill -CONT "$a" 2> /dev/null &&
      echo "resumed $a $(basename "$(ps -o comm= -p "$a")")"
  done

  grep -qx review-on "$file" && bash "$review" on > /dev/null && echo "local reviews on"
  while read -r kind a; do
    [ "$kind" = review ] && [ -d "$a" ] && bash "$review" start "$a" | tail -n 1
  done < "$file"

  rm -f "$file"
}

case "$(basename "$0")" in
  resume*) do_resume ;;
  *) do_pause ;;
esac
