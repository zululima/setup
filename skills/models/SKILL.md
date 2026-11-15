---
name: models
description: Which Claude model and effort each kind of work runs on, when a task moves up to a stronger model, and the cheaper picks for work a session starts when the limits run short. Load before any other step at a prompt that starts software that is hard or open, research across many web sources or chart reading, and before starting or offering a subagent, a workflow agent or a session.
---

# Models and effort

- Every piece of work a session starts runs on the model and effort of its task's row below, set
  through the starting tool's own fields: `model` and `effort` of the Agent tool, the `model` and
  `effort` options of a workflow's `agent()` and `model` and `effort` of `start_session`. A task
  that fits two rows takes the stronger one. This skill is the instruction the Agent tool's
  `effort` field waits for.
- `start_session` takes a model and effort only at or below the starting session's own. A session
  that needs another model or effort, both as its row gives them, starts with a prompt that asks it
  only to reply `ready` and run no tools, so its first turn costs next to nothing. It then gets
  `detach_session`, `set_session_model` and `set_session_effort`, which the app may ask the user to
  approve, and only then its task with `send_message`.
- No session nests under another. Every brief, a card's too, opens by telling its session to call
  `detach_session` with `self` before any other step, and a session another one started does so
  first, told or not. The session that started one also detaches it in the next message. It then
  reports nothing back, so the reply of a session that stays, one with work of its own left, links
  it, and a step that needs its result waits for the user to say it is done. A spawner, as
  `~/.claude/CLAUDE.md` defines it, archives itself instead, once the start, the detach and any
  send of the task returned without error: it calls `wrap_up` with a recap alone, then
  `archive_session` with `self`, and writes no reply. A session that used `hand_off_to_session` to
  answer a new message is no spawner, since it answers. The brief of a session a spawner starts
  also gives the spawner's `local_` id and tells its session to call `archive_session` on it before
  its first closing reply unless `get_session` shows it archived, and not to mention that.
- The window layout of the desktop app is the user's. A session started from this one is never
  opened in a split pane, a window or the main pane unless the user asks for that, and a session
  that stays links it in its reply.
- A tool that cannot set the model or effort its row asks for is named in the reply with that row.
- An offer to start a session is a question in the next-step box, never a `start_session` card,
  neither an "own_initiative" proposal nor an "offer": the question names the task with the
  session's model and effort in full, its first button, which one shortcut presses, is the yes,
  and on that yes the session starts it with `start_session` and "user_asked". When the pace is
  `tight`, that one question names the rung Stepping down gives, and its second button keeps this
  session's own model and effort.
- The turn that the yes opens makes `start_session` its first call and `detach_session` its next
  message, before any other step, `get_usage` and loading a skill included. The app posts its
  "moved to top level" banner when the session that calls `detach_session` is not the one on
  screen, and the person who pressed yes may move to another session within seconds. A started
  session that needs another model or effort gets `set_session_model` and `set_session_effort`
  right after the detach, in the same way.
- The reply that asks, like the one of a session that stays and links a session it started, names
  that session's model and effort and says why they are the best for it: what in its task puts it
  on its row, and what the score or guidance behind the row means for that task, such as that a
  crash whose cause is not yet found is hard software, where Fable 5.2 at high scores above Opus
  5.5 at xhigh. The reason is written for that session's task, never the row's last cell copied as
  it stands. A spawner writes no reply after the start, so the question that asked is where its
  model, effort and reason stand.
- No row uses max effort: on Fable 5.2 Anthropic keeps it for measuring the model's ceiling, and
  on software work it does worse than xhigh. No row uses Fable 5.2 at xhigh either: the 5-hour
  limit cannot carry it, as What a session costs shows.
- A task runs in the session it is typed in, on that session's model and effort, with no question
  and no session started for it: handing a task on costs a second context and the turns that
  arrange it, more than a cheaper model saves, as What a session costs shows. The one move is up.
  A session cannot switch its own model or effort, so at a prompt that starts software that is
  hard or open, research across many web sources or chart reading, each more than a few tool
  calls, it reads them with `get_session` and `self`. In a session on a cheaper model than Fable
  5.2, such a task goes to a new session on its row unless the pace is `tight`: started as above,
  with `context` "fork" so it holds this conversation, and with a task that asks it to carry out
  the user's last prompt there, so the prompt stays the user's own in its log and its commits.
  This session does none of it: a session that stays links that one in its reply and says the
  work goes on there, and a spawner writes no reply, so no question named the fork's model and
  effort and its task asks the fork's first reply to say them, with why, as the sentence below
  does. Every other task runs here, also in a session on a model that costs more than its row's,
  such as a draft in a session on Fable 5.2: the user picked that model, and no reply asks to
  move the task down. When the session's model or effort is not its task's row's, the first line
  of the reply that starts the task says so in a full sentence of plain words: which model and
  effort this skill gives that kind of task and which the session runs on, such as "This skill
  gives software like this to Fable 5.2 at high effort, and this session runs on Opus 5.5 at
  xhigh". No line a reply writes under this skill opens with a label before a colon, such as the
  task's kind, which reads as a question put to the user, and none uses this skill's own words
  row, rung or tight: it names the model, the effort and the limit, and says of the limit how
  full it is and what it is on pace for. A session whose opening prompt says the user picked its
  model and effort for the pace keeps them, as Stepping down says. That settles its own model and
  effort only: it still loads this skill before it starts or proposes a session, and its reply
  names that session's model and effort as the bullet above says.

| Task | Model | Effort | Benchmarks behind it |
|---|---|---|---|
| Software that is hard or open: a cause not yet found, a design decision or a change across layers | Fable 5.2 (`fable`) | high | FrontierCode 2.0: 45.3 at high, Opus 5.5 43.4 at xhigh and 45.5 at its best. FrontierSWE v2: 69.9, Opus 5.5 62.3. Fable 5.2 at xhigh scores 49.1 for 2.1 times the cost per task |
| Other software: building, changing, debugging or reviewing code, scripts, hooks, skills and workflows | Opus 5.5 (`opus`) | xhigh | FrontierCode 2.0: 43.4 at xhigh, 1.9 under Fable 5.2 at high for 77% of its cost per task, and 34.5 at high. Anthropic names Opus 5.5 the daily driver for most coding and knowledge tasks |
| Research across many web sources and collecting data from them | Fable 5.2 (`fable`) | medium | WANDR: medium matches Opus 5.5's top score for about 40% of its cost per task |
| Reading charts, figures and screenshots | Fable 5.2 (`fable`) | medium | Chartography: 66.4 at medium, Opus 5.5 64.4 at max, for under a tenth of the cost |
| Everything else: writing, drafts, documents, planning and questions | Opus 5.5 (`opus`) | xhigh | Humanity's Last Exam with tools: 66.4 at xhigh, 63.9 at high, and 67.7 at max for three times the cost per task |
| A bounded step that needs judgement, such as summarising one file | Sonnet 5.5 (`sonnet`) | medium | Anthropic: move down to Sonnet or Haiku when a task is simpler |
| A mechanical step: a lookup, a listing, reading one value, a format check | Haiku 5.5 (`haiku`) | low | The same guidance |

- The table changes only when newer benchmarks back another pick, or when two or more independent
  trackers that rerun a fixed test on live models show a row's model has dropped. The dream
  workflow's `anthropic` source reads each model launch page and those trackers, and proposes the
  row as it would read, with the scores behind it.

## What a session costs

- The rows are the strongest picks the plan's 5-hour limit carries through a working day, counted
  on 12 November 2026 from the transcripts under `~/.claude/projects` at API list prices. That
  limit holds about $108 of Fable 5.2. A window filled in 3 hours 30 minutes with 13 sessions and
  473 responses, every one on Fable 5.2, 312 at xhigh and 161 at high after a step down. Cache
  writes were 48% of its cost, output 34% and cache reads 18%.
- The model sets what a response costs, and the effort sets little of it: two thirds of the cost
  is the context each response carries, which is priced by the model. Per response since 9
  November 2026, Fable 5.2 cost $0.235 at xhigh over 1,204 responses and $0.198 at high over 621,
  and Opus 5.5 cost $0.090 at xhigh over 6,531. A lower effort ends a task in fewer responses,
  which is the saving a benchmark's cost per task shows, but each response costs nearly the same,
  so the limit fills almost as fast. A step down therefore changes the model, and no session is
  started only to lower the effort on the model it already runs on.
- A new session writes its context again before its task starts: about 65,000 tokens beyond the
  shared prompt, $1.04 on Fable 5.2 and $0.52 on Opus 5.5. Such writes, at a session's start and
  after its cache went cold, were 21% of the window that filled. So a task moves to another
  session only up to Fable 5.2, and never when a few tool calls settle it.
- A session that only hands its task on costs more than that write, since it loads this skill,
  reads the limits, asks and waits for the answer. A window that filled in 2 hours 28 minutes on
  14 November 2026 held $156.05 over 1,336 responses in 27 sessions, 44% of it cache writes. Seven
  of those sessions, on Fable 5.2 at xhigh, ended by starting the session that did their task:
  $35.55 over 173 responses, 23% of the window. An Opus 5.5 session that handed its task to Sonnet
  5.5 that day cost $1.18 over 14 responses, which the 30% that Sonnet 5.5 saves pays back only on
  a task of about $5 on Opus 5.5. So no task is handed down to a cheaper model.
- The user's sessions start on Opus 5.5 at xhigh, on the Mac and on the Linux desktop, whose
  account is on the Pro plan: the row of most tasks, so most tasks run where they are typed with
  no session started for them.

## Stepping down

- Before a session moves a task up or starts any work, such as a subagent, a workflow agent or a
  session, it reads the plan's limits with `get_usage`, once a task, after the start and detach
  that a yes to an offer of a session makes first, and pipes the result as it came to
  `~/.claude/skills/models/pace.sh`, which prints what the 5-hour limit and each weekly limit is
  on pace for, and a verdict. On `fits` or `unknown` the move is made and the work runs on its
  row. A task that stays where it is typed and starts no work needs no read.
- On `tight` no task moves up and no work starts on Fable 5.2, apart from research and chart
  reading in a subagent or a workflow agent, whose benchmarks put every Opus 5.5 rung at a higher
  cost per task or far below. Software that is hard or open then runs where it is typed: on Opus
  5.5 at xhigh it scores 1.9 points under its row at 38% of Fable 5.2's cost per response.
- A session keeps its own task whatever the verdict, and no reply asks to move it to a cheaper
  model. A reply that kept a task off its row for the limit, or started work on a second rung,
  gives what `pace.sh` printed for the limit that binds.
- Work a session starts while the pace is `tight`, such as a subagent, a workflow agent or a new
  session, takes the second rung of its line: Opus 5.5 at xhigh for software that is hard or open,
  Opus 5.5 at high for other software and for everything else, and Fable 5.2 at low for research
  and chart reading, or Opus 5.5 at medium when the limit that binds is the weekly Fable one. The
  Sonnet and Haiku rows stay as they are. It takes that rung without a question of its own, and
  an offer to start a session names it. The brief of a session started on such a rung says the
  user picked its model and effort for the pace, so that session keeps them and moves no task up.
- A reply that offers a session reads the limits again first, with `get_usage` and `pace.sh`,
  unless the session read them in the last 10 minutes, and a figure or time the offer or the brief
  gives for a limit is quoted from that read. When it has the 5-hour limit within 5 points of full,
  the question gives the reset time `pace.sh` printed and names the model and effort the task takes
  in the new window: its row's, or its rung's when a weekly limit is tight too. Its first button
  starts the task at that reset and its second starts it now, on the rung. On the first, the turn
  makes a one-time task under Scheduled for a minute after the reset in place of `start_session`.
  The scheduling tool sets no model, so the task's prompt holds the brief and has the session it
  opens start the brief's session on that model and effort as a spawner, with no question, since
  the user said yes.
- A session started on a second rung that has the context it needs and still gets the task wrong
  twice says so and names its row's model and effort, which the user picks in the app's model
  menu.

The first table gives the score of each model and effort, its cost per task in dollars at API
prices, and that cost as a share of Fable 5.2 at xhigh. A benchmark runs its task in a small
context, so its share between two models holds in the user's sessions, where Opus 5.5 at xhigh
costs 38% of Fable 5.2 at xhigh per response, and its share between two efforts of one model does
not: Fable 5.2 at high costs 84% of xhigh per response, not 47%.

| Task | Score and cost per task, strongest first | Benchmark |
|---|---|---|
| Software | Fable 5.2 xhigh 49.1, $14.19, 100%. Fable 5.2 high 45.3, $6.72, 47%. Opus 5.5 xhigh 43.4, $5.18, 37%. Fable 5.2 medium 37.6, $2.48, 17%. Opus 5.5 high 34.5, $2.42, 17%. Opus 5.5 medium 30.1, $1.70, 12% | FrontierCode 2.0 |
| Research | Fable 5.2 xhigh 80.6, $39.84, 100%. Fable 5.2 high 79.3, $29.20, 73%. Fable 5.2 medium 73.6, $15.71, 39%. Fable 5.2 low 71.4, $12.66, 32%. Opus 5.5 xhigh 71.3, $29.25, 73%. Opus 5.5 high 67.3, $17.31, 43%. Opus 5.5 medium 62.8, $11.40, 29% | WANDR |
| Charts, figures and screenshots | Fable 5.2 xhigh 71.4, $0.151, 100%. Fable 5.2 high 69.8, $0.068, 45%. Fable 5.2 medium 66.4, $0.035, 23%. Fable 5.2 low 64.2, $0.031, 21%. Opus 5.5 xhigh 62.4, $0.082, 54%. Opus 5.5 high 59.2, $0.032, 21%. Opus 5.5 medium 59.0, $0.025, 17% | Chartography |
| Everything else | Fable 5.2 xhigh 73.4, $1.48, 100%. Fable 5.2 high 71.5, $0.63, 42%. Fable 5.2 medium 68.6, $0.21, 14%. Fable 5.2 low 68.4, $0.19, 13%. Opus 5.5 xhigh 66.4, $0.69, 47%. Opus 5.5 high 63.9, $0.29, 20%. Opus 5.5 medium 63.0, $0.17, 12% | Humanity's Last Exam with tools |

The second table gives Sonnet 5.5 beside Opus 5.5 from the Sonnet 5.5 launch page, whose charts
leave out Fable 5.2, with each cost per task as a share of Opus 5.5 at xhigh. On Humanity's Last
Exam with tools that page gives Sonnet 5.5 64.5 and Opus 5.5 67.7, with no effort or cost.

| Task | Score and cost per task, strongest first | Benchmark |
|---|---|---|
| Software | Opus 5.5 xhigh 66.4, $7.35, 100%. Opus 5.5 high 64.2, $3.88, 53%. Sonnet 5.5 xhigh 61.5, $5.30, 72%. Opus 5.5 medium 57.6, $2.94, 40%. Sonnet 5.5 high 43.0, $1.94, 26%. Sonnet 5.5 medium 28.8, $0.83, 11% | Terminal-Bench 4.0 |
| Software | Opus 5.5 medium 54.6, $0.80, 36%. Opus 5.5 high 54.0, $1.09, 48%. Sonnet 5.5 xhigh 52.1, $1.59, 71%. Opus 5.5 xhigh 51.4, $2.25, 100%. Sonnet 5.5 high 49.4, $0.42, 19%. Sonnet 5.5 medium 36.5, $0.24, 11% | FrontierCode 1.1, main set |
| Software | Opus 5.5 xhigh 56.0, $6.98, 100%. Opus 5.5 high 56.0, $3.97, 57%. Sonnet 5.5 xhigh 53.1, $3.88, 56%. Opus 5.5 medium 52.5, $2.91, 42%. Sonnet 5.5 high 47.8, $1.67, 24%. Sonnet 5.5 medium 39.2, $0.70, 10% | CursorBench 4.0 |
| Everything else | Opus 5.5 xhigh 1780, $12.27, 100%. Sonnet 5.5 xhigh 1746, $9.63, 79%. Opus 5.5 high 1705, $6.27, 51%. Opus 5.5 medium 1642, $4.40, 36%. Sonnet 5.5 high 1634, $3.95, 32%. Sonnet 5.5 medium 1461, $1.64, 13% | AA-Briefcase v1.1, Elo |

- Trackers, read on 11 November 2026: none flags a Claude model. NerfBench has Opus 5.5 at 105.8%
  of its launch score, last tested on 16 October, and showed no other Claude model. AIStupidLevel,
  for 12 October to 11 November, gives a coding pass rate of 93% for Opus 5.5, 85% for Fable 5.2
  and 80% for Sonnet 5.5, from 7 bug fixes tried 7 times every 4 hours. MarginLab runs Claude Code
  on Opus 5.5 at high: 77% on the day and 81% over 30 days, with its baseline still being
  collected. IsItNerfed lists no current Claude model.
- The rungs and the tracker line change as the rows do: the dream workflow's `anthropic` source
  proposes each as it would read. A launch page's HTML holds the points of each cost chart as rows
  of series, cost, score and effort, which is where the costs per task come from.

Sources: Claude Fable 5.2 and Mythos 5.2 launch page, 9 November 2026,
[https://www.anthropic.com/claude-fable-and-mythos-5-2](https://www.anthropic.com/claude-fable-and-mythos-5-2),
the Claude Sonnet 5.5 launch page, 28 September 2026,
[https://www.anthropic.com/news/claude-sonnet-5-5](https://www.anthropic.com/news/claude-sonnet-5-5),
the model configuration page of the Claude Code docs,
[https://code.claude.com/docs/en/model-config](https://code.claude.com/docs/en/model-config),
Anthropic's post on choosing a model and effort level, 7 July 2026,
[https://www.claude.com/blog/claude-model-and-effort-level-in-claude-code](https://www.claude.com/blog/claude-model-and-effort-level-in-claude-code),
and the trackers:
[https://www.bridgebench.ai/nerf-bench](https://www.bridgebench.ai/nerf-bench),
[https://aistupidlevel.info](https://aistupidlevel.info),
[https://marginlab.ai/trackers/claude-code](https://marginlab.ai/trackers/claude-code) and
[https://isitnerfed.org](https://isitnerfed.org).
