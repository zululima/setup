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
| [Hook tests](../test/hooks/checks.mjs) | every hook, fed the input Claude Code sends it | 403 of 404 pass |
| [Sync tests](../test/sync/checks.mjs) | what `sync.sh` pulls and copies between two computers, against a throwaway remote | 29 of 29 pass |
| [Dream simulation](../test/dream-sim/checks.mjs) | how `/dream` spends usage and when it stops | 188 of 188 pass |
| [Usage mod tests](../mods/session-usage/hooks/register.test.ts) | the line under the prompt box | 30 of 30 pass |

How often Claude kept rules from [`CLAUDE.md`](../CLAUDE.md) from 2026-11-08 to 2026-11-15, in 228 of my own sessions and the commits of the 7 repositories they worked in, counted by [`test/rules/adherence.mjs`](../test/rules/adherence.mjs):

| Rule | Kept |
| --- | --- |
| No long dashes in replies | 99% (664 of 668 replies) |
| Plain quotes, arrows and dots in replies | 99% (664 of 668 replies) |
| A Prompt feedback section after each typed prompt | 92% (449 of 483 replies) |
| Commit message lines within 72 columns | 100% (343 of 343 commits) |
| No Claude attribution in commits | 99% (342 of 343 commits) |
<!-- evals:end -->
