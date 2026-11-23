# Evals

These are the numbers from the last `/dream` run, or from the last time I ran the evals by hand. The
rule counts come from my own sessions, and only the counts leave my computer. To run the evals on
your copy:

```bash
node ~/Projects/setup/test/evals.mjs
```

<!-- evals:start -->
| Suite | What it checks | Result |
| --- | --- | --- |
| [Hook tests](../test/hooks/checks.mjs) | every hook, fed the input Claude Code sends it | 416 of 417 pass |
| [Sync tests](../test/sync/checks.mjs) | what `sync.sh` pulls and copies between two computers, against a throwaway remote | 35 of 35 pass |
| [Dream simulation](../test/dream-sim/checks.mjs) | how `/dream` spends usage and when it stops | 201 of 201 pass |
| [Usage mod tests](../mods/session-usage/hooks/register.test.ts) | the line under the prompt box | 30 of 30 pass |

How often Claude kept rules from [`CLAUDE.md`](../CLAUDE.md) from 2026-11-16 to 2026-11-23, in 137 of my own sessions and the commits of the 9 repositories they worked in, counted by [`test/rules/adherence.mjs`](../test/rules/adherence.mjs):

| Rule | Kept |
| --- | --- |
| No long dashes in replies | 97% (583 of 595 replies) |
| Plain quotes, arrows and dots in replies | 99% (594 of 595 replies) |
| A Prompt feedback section after each typed prompt | 97% (420 of 432 replies) |
| Commit message lines within 72 columns | 98% (150 of 152 commits) |
| No Claude attribution in commits | 100% (152 of 152 commits) |
<!-- evals:end -->
