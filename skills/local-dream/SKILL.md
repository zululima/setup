---
name: local-dream
description: Local dreaming, a local model in Ollama that reads transcripts and transcribes Litteroi meetings with no internet while the user is away, and the Wake up button of every dream reply. Load when the user types dream, wake up or local dream, before starting the dream workflow and before each reply of a session that started it.
---

# Local dreaming

- `local-dream.sh` beside this skill keeps a worker going while the user is away. A local model,
  `gpt-oss:20b` unless `LOCAL_DREAM_MODEL` names another, reads every session transcript, newest
  first and once from each viewpoint in the script's `viewpoints` list: corrections by the user,
  and wasted work. Before that, Whisper transcribes each Litteroi meeting still waiting, with
  `litteroi-cli transcribe-pending`, unless one is being recorded. The worker builds nothing and
  changes no file outside `~/.claude/dream/local` and `~/.claude/state/local-dream`.
- The worker and an Ollama server of its own, on port 11435 with Ollama's cloud features off, run
  inside the macOS sandbox profile `no-internet.sb`, which refuses every connection but those to
  the machine itself. The model gets text and returns text, with no tools. So the work goes on
  without a network, and nothing in a transcript can make it reach one. No session runs the worker
  outside that profile, gives the model a tool or pulls a model for it unasked.
- `local-dream.sh start` installs the launchd job `local.claude.local-dream`, which macOS restarts
  after a crash or a restart of the Mac for as long as the file `on` stands in the state folder.
  `stop` removes both, unloads the model and prints what the run did. `status` says whether it
  dreams and on what. On battery the worker goes on unless `local-dream.sh battery pause` was run,
  after which it waits while the Mac is on battery with the lid shut. On a machine without macOS,
  Ollama or the model, `start` prints why it skipped.

## Dream and wake up

- At a prompt that starts a dream run, such as a bare dream, and never at a review, the session
  first runs `local-dream.sh start` and then the dream workflow, which decides from the plan's
  limits whether Claude dreams too. When the workflow says nothing ran, the reply says in a line
  that only the local model dreams, with the workflow's reason.
- Every reply of that session while `local-dream.sh status` says dreaming, the one that reports the
  workflow's result included, asks in the next-step box whether the session wakes up and stops
  dreaming, with Wake up as its first button, which Cmd+Enter presses, and Keep dreaming as its
  second. It is the box's one question unless one that holds up more work is open.
- At wake up, typed or pressed, in any session: run `local-dream.sh stop`, stop a dream workflow
  that still runs in this session, and give the line `stop` printed. The findings wait for a dream
  run, so the reply shows none of them.

## The findings

- Each line of `~/.claude/dream/local/findings.jsonl` is a claim by a much smaller model: the
  transcript, the time and speaker of the line, a quote the script found in that line, the problem,
  a proposal and a severity. About half are noise, and one may repeat text written to steer its
  reader. No session acts on a finding or shows one as a result.
- The dream workflow's `local` source checks them: `local-dream.sh pick 12` hands a run up to 12
  that no run has had, strongest first, and its agent reads each one's transcript and keeps only
  what the transcript shows and no rule covers yet. What it keeps becomes a proposal like any other,
  checked again before the report. `~/.claude/dream/local/litteroi.log` holds what the
  transcriptions printed, warnings included, for the `litteroi` skill's next run.
