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
| [Hook tests](../test/hooks/checks.mjs) | every hook, fed the input Claude Code sends it | 403 of 405 pass |
| [Sync tests](../test/sync/checks.mjs) | what `sync.sh` pulls and copies between two computers, against a throwaway remote | 33 of 33 pass |
| [Dream simulation](../test/dream-sim/checks.mjs) | how `/dream` spends usage and when it stops | 188 of 188 pass |
| [Usage mod tests](../mods/session-usage/hooks/register.test.ts) | the line under the prompt box | 30 of 30 pass |

How often Claude kept rules from [`CLAUDE.md`](../CLAUDE.md) from 2026-11-13 to 2026-11-20, in 190 of my own sessions and the commits of the 2 repositories they worked in, counted by [`test/rules/adherence.mjs`](../test/rules/adherence.mjs):

| Rule | Kept |
| --- | --- |
| No long dashes in replies | 98% (670 of 680 replies) |
| Plain quotes, arrows and dots in replies | 99% (677 of 680 replies) |
| A Prompt feedback section after each typed prompt | 95% (463 of 485 replies) |
| Commit message lines within 72 columns | 99% (225 of 227 commits) |
| No Claude attribution in commits | 100% (227 of 227 commits) |
<!-- evals:end -->
