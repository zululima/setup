---
name: pages
description: Pages and documents read in a browser, such as an HTML page, a schedule, a project's README, CLAUDE.md or docs, a Markdown doc on GitHub or a PR's review page: where they go, the one-screen check at 1440x730, answers folded under questions and warnings of a known date. Load before making or changing such a page or document.
---

# Pages

- A request for an HTML file or page gets a local file in `~/.claude/pages/`, never `~/Downloads` or
  a published Artifact, whatever the Artifact tool's description says about pages and apps: the user
  reads it in their own browser, which remembers its address, and nothing goes to claude.ai. An
  Artifact is published only when the user asks for one by that word.
- A page meant to be taken in at a glance, such as a schedule, a roadmap, a status page or a whole
  README, fits one MacBook screen without scrolling: a table or columns in place of a long list, and
  one line per row or bar. Check it, and every other page a session makes for the user to open in a
  browser, such as a PR's review page, with a viewport screenshot at 1440x730, about the browser
  area of a 13-inch MacBook Air, taken as the page first opens, unscrolled, with the site's own
  header above the content, never after scrolling the content into view and never with a taller or
  full-page one alone. In Claude in Chrome, whose `resize_window` sizes the whole window, that is
  the window sized until `window.innerWidth` by `window.innerHeight` is 1440x730. A whole README is
  the one exception: its last line shows with its tab bar on GitHub 140 pixels below the window's
  top, where a scroll down to it stops with the end of the file list still in view, so the top of
  the tab bar and the bottom of the last line are at most 590 pixels apart. On a page the user works through, the first screen reaches what they act on first, what
  stays in view sits at the side or in a thin bar, and a part they call too long gets shorter, not
  folded behind a toggle. Text a page shows the user to read, such as the examples beside a review
  row, is never cut at a character count: it shows whole, and a list too long for that picks fewer
  or shorter items. A page the user answers on keeps each answer by the item's own id, and a new or
  shorter version of it, at the old address or a new one, shows every answer given on the earlier
  one. A shorter list of what to check holds only items something flagged, each with the reason it
  is there. An item asks what one answer settles: a word whose form changes with its use, such as
  a translation of Search as a verb or a noun, is asked on a string of each doubtful use, never as
  one word for all of them. A term the user answers with a new word comes back as one row for each
  string that uses it, with the word in the form that string needs, since a language such as
  Finnish inflects it differently in each; a term the user accepts adds no rows. A document modelled on another keeps its page size and page count: a copy
  of a one-page A4 landscape PDF is one A4 landscape page, never a page stretched to fit the
  content.
- Questions a reader answers, such as those of a quiz, a practice exam or an exercise, each fold
  their answer in a collapsed block under the question, `<details>` in Markdown and HTML, so
  reading the questions shows no answer: a toggle that hides a spoiler, not one that shortens a
  long part. Content that stops holding on a known date, such as exam material before a new exam
  guide takes effect, gets a warning that names the date and what changes, above the first step,
  question or list of every page that content reaches, as a `> [!WARNING]` alert on GitHub, never
  only as a sentence inside a step or an intro. A page held to one screen that the warning would
  push past it stays on one screen and names the date in a sentence of the step it concerns.
- A project's CLAUDE.md holds what Claude runs, such as build, test, verify, install, launch and
  logs, and the rules the code follows. One-time manual setup goes in a doc under `docs/` that
  CLAUDE.md or AGENTS.md indexes. The README says what the project is, shows its parts and every way
  to use or try it, and gives a newcomer a prompt to paste into Claude Code, in a `text` block, that
  clones the repository and gets them started. GitHub strips `claude://` links, so none stands in
  for it.
- A page or document a session writes, such as a README, states as fact only what a source in the
  session shows: the user's words, a log, the code, or the page of a project it names. A reason no
  one gave stays out, and a claim about another project, such as whether it is still maintained, is
  read from that project's own repository or page in the same turn.
