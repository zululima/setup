---
name: recall
description: One local search over what earlier Claude Code sessions said, typed prompts, memory notes, meeting notes and background files, by keywords, by meaning and by regex. Load before searching earlier sessions, the prompt log, memory or meetings for what the user said, decided or set up, and before asking the user a fact an earlier session may hold.
---

# Recall

- `recall.py` beside this skill keeps an index of the transcripts under `~/.claude/projects` (the
  sessions and their direct subagents, the user's and Claude's text without tool output), the
  memory notes, meeting notes under `~/.claude/meetings` and each project's `meetings/`, prompts
  in `~/.claude/prompt-log` whose session left no transcript, and the files `sources.txt` beside
  it lists as `<kind> <glob>`. The index lives in `~/.claude/state/recall/index.db` and stays on
  the machine that built it.
- A search is `python3 ~/.claude/skills/recall/recall.py "<query>"`, run bare with the query
  alone unless a filter below narrows it. It first adds what changed since the last search, then
  ranks by keywords (SQLite full-text search, BM25, each word also matching as a prefix, so
  Finnish endings still match) and by meaning (an embedding model in a local Ollama,
  `qwen3-embedding:0.6b` unless `RECALL_MODEL` names another) and merges the two lists. A query in
  Finnish finds English text by meaning and the other way round, so write it in the words the
  answer would use, or run it once in each language.
- Filters: `--kind` with a comma list of session, subagent, memory, meeting, prompt or a kind
  `sources.txt` names; `--project` with part of a project's name; `--role user` for what the user
  typed, `--role assistant` for Claude's replies, `--role '!assistant'` for all but those; `--since`
  and `--until` with a date; `--regex` with a pattern, case-insensitive, which alone lists the
  newest text it matches; `--limit` (10 by default); `--all-sessions` to include the session that
  runs the search, left out otherwise.
- Each hit prints its id, local time, kind, project, session and role, a snippet, and the file with
  its line. `--json` prints the hits as JSON, each with its meaning score as `cosine`. `recall.py
  show <id>` prints the hit with the messages around it, and a hit inside a conversation is read
  that way, with `--around` widened as needed, before a reply quotes it or rests on it, since a
  later message may settle or reverse it.
- Embedding runs at about 19 chunks a second on a laptop's GPU with nothing else on it, so a first
  build over a few months of sessions takes about half an hour. A search therefore embeds new text
  for 30 seconds at most (`RECALL_BUDGET`), newest first, and says how many chunks still wait;
  those match by keywords until `recall.py index`, run in the background, embeds them all. A search
  starts `ollama serve` when it is not running and stops it when done. Without Ollama or the model
  a search runs on keywords alone and says so.
- `recall.py status` shows what the index holds. Deleting the index file rebuilds it from scratch
  at the next run.
- The hook `~/.claude/hooks/ask-recall.sh` runs this search on a question that asks the user a
  fact, in the next-step box or at the end of the closing message, and sends the turn back once
  with the hits whose meaning score reaches 0.68. A hit it names is read with `show` before the
  question goes out again, and a question the hits do not answer is asked as it was.
- Hits hold whatever the sessions held, customer data included. They stay in the session that
  searched: none goes into a request to an outside service, and a hit from one client's project
  is used only in work on that project.
