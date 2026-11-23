#!/usr/bin/env bash

# Claude Code Stop hook. When the turn's closing message calls someone he, him,
# his, himself, she, her, hers or herself, it sends the turn back once with
# that sentence, since the Prose rule of CLAUDE.md makes a person whose
# pronouns no source states they. Fenced blocks other than text blocks, code
# spans, URLs, quotes and block quotes are skipped, and so is he in a Finnish
# sentence, where it means they. A person listed in rules/pronouns.md as
#
#   - Full Name: she/her, source
#
# lets that set of pronouns through in a reply that names them.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)"
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = false ] || exit 0
last="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
[ -n "$last" ] || exit 0
listed="$(cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules/pronouns.md" 2>/dev/null)"

hit="$(jq -rn --arg last "$last" --arg listed "$listed" '
  def names($set):
    [$listed | split("\n")[] | capture("^- (?<name>[^:]+): (?<set>[a-z]+)/")?
     | select(.set == $set) | .name | ., (split(" ") | first)] | unique;
  def named($set): any(names($set)[]; . as $n | $last | test("\\b" + $n + "\\b"));
  def prose:
    reduce split("\n")[] as $l ({out: [], fence: null};
      if .fence == null then
        if ($l | test("^\\s*```")) then .fence = ($l | test("^\\s*```text\\s*$"))
        else .out += [$l] end
      elif ($l | test("^\\s*```\\s*$")) then .fence = null
      elif .fence then .out += [$l]
      else . end)
    | .out | map(select(test("^\\s*>") | not)) | join("\n")
    | gsub("`[^`\\n]*`"; " ") | gsub("https?://[^\\s)\\]]+"; " ") | gsub("\"[^\"\\n]*\""; " ");
  def finnish:
    test("[äöÄÖ]|\\b([Jj]a|[Ee]i|[Jj]os|[Kk]un|[Tt]ai|[Nn]iin|[Mm]utta|[Mm]yös|[Ee]ttä|ovat|eivät|olivat)\\b|\\b[Hh]e \\w+(vat|vät)\\b");
  def word: (.[0:1] | "[" + . + ascii_upcase + "]") + .[1:];
  named("he") as $heok
  | ((if $heok then [] else ["him", "his", "himself"] end)
     + (if named("she") then [] else ["she", "her", "hers", "herself"] end)) as $words
  | ($words | map(word) | "\\b(" + join("|") + ")\\b") as $re
  | [$last | prose | splits("(?<=[.!?])\\s+|\\n+")
     | select((($words | length) > 0 and test($re))
              or (($heok | not) and test("\\b[Hh]e\\b") and (finnish | not)))]
  | first // empty | sub("^\\s+"; "") | .[0:240]
' 2>/dev/null)"
[ -n "$hit" ] || exit 0

printf '%s\n' "This reply gives someone a gendered pronoun in: \"$hit\". The Prose rule of ~/.claude/CLAUDE.md says a person whose pronouns no source states is they, them and their, whatever their name or role. Write the closing message again in full, without calling wrap_up again, with they, them, their or the person's name in place of each such pronoun. Where a source does state the person's pronouns, keep them and name that source in the reply." >&2
exit 2
