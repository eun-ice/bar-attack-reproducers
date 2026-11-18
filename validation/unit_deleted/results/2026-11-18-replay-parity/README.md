# Successful 20-replay parity comparison — 2026-11-18

All 20 replays completed in all three variants: **60/60 successful runs**,
**zero recorded-checksum warnings in every variant**, and identical sampled
physical state and cumulative damage/deletion event hashes in every pairwise comparison.

| Variant | Engine | BAR runtime | Completed | Checksum warnings |
| --- | --- | --- | --- | --- |
| A (`release`) | Official 2026.09.03 | Recorded BAR | 20/20 | 0 |
| B (`extended`) | 2026.09.03 + #3431 + corrected #3454 | Recorded BAR | 20/20 | 0 |
| C (`pr8935`) | Same as B | #8935 historical replay runtime with compatibility fixes and Set Target ordering patch | 20/20 | 0 |

#3348 is already included in release 2026.09.03. The BAR parity branch is
[`1f3cd9b9b8`](https://github.com/eun-ice/Beyond-All-Reason/commit/1f3cd9b9b8).
Engine binaries, base archives and runtime hashes were verified against the
frozen validated inputs before execution; see [provenance.json](provenance.json).
The engine binary is the release integration with the #3454 correction, not a
new standalone build of the current PR branch.

Across the 20 recordings, the input audit found **9,836 recorded sync checkpoints**
and **145,241 sync-response packets**. Each variant uses the same prepared replay
bytes; all non-setup packet bytes match the originals, including commands and
sync responses. There are **3,952 state/event sample frames per variant**.
The formerly divergent replay `2c8ffc6a0c7f88b9c8f596a02ef0c523` now has zero
warnings instead of 245, with all 227 state/event samples equal.

## Evidence

- [Final per-replay audit](final-audit.json): completion, comparisons, warning counts and input coverage.
- [Recorded checksum/input audit](checksum-input-audit.json): packet hashes and checkpoint ranges.
- [Per-replay comparison report](report.json).
- [Run metadata and state/event hash streams](runs/): all 60 successful runs.
- [Plain-text summary](RESULTS.txt).

These are fresh executions of all three variants. A tool-session interruption
required restarting unfinished attempts; only successful complete attempts are
included here. No results were reused from the previous validation matrix.
Original console logs remain in the local evidence directory named in the run
metadata; they and the replay/engine binaries are not bundled here. Warning
counts are extracted from those logs. Local paths in provenance are historical
references, not portable installation instructions.

## Scope

- Engine checksums are checked against recorded sync responses, not exported for every frame.
- Physical state is sampled every 150 frames; damage/deletion events accumulate continuously.
- LuaUI is disabled; observation ends 150–299 frames before each recording ends.
- Native replay commands are unchanged. This does not test newly generated compact inputs or live UI gestures.

OpenAI Codex assisted execution, analysis and publication of the validation evidence.
Human gameplay verification remains pending.
