# Close-in reproducers (RecoilEngine #3242)

Headless and recorded reproducers for RecoilEngine PRs #3241 (attack command keeps closing
in on static blockers) and #3328 (rays starting below the terrain), run against Beyond All
Reason. Everything here assumes the checkouts and maps of the author's machine (see the
paths at the top of `run.sh`); `docs/` holds the PR texts and the per-reproducer analyses.

Headless scenarios for the CommandAI change "keep closing in when a static obstacle blocks
the line of fire" (branch `fix/3242-close-in-static-blockers`, PR #3241, stacked on #3328 +
#3327 + #3325), plus two reproducers from player reports that exercise the same CommandAI
decision (commander vs Ticks, missile cruisers vs plateau geo).

    ./run.sh <spring-headless> <startscript> <label> [timeout-s]

`run.sh` links `luarules/gadgets/*.lua` into the BAR checkout (`BAR_CHECKOUT`, default
`~/Projects/bar/Beyond-All-Reason`, was on `feature/aim-from-estimate`), exposes it as
`games/Beyond-All-Reason.sdd` in `DATA_DIR` together with the two maps from
`~/Projects/bar/bar-dev/data/maps`, runs the start script and writes
`OUT_DIR/<label>.{log,infolog.txt,results.txt}`. Use one `DATA_DIR` per engine when running
two engines in parallel.

## Scenarios (`tools/StartScripts/`)

`dbg_attack_obstacle_reproducer.lua`, modoption `attackobstaclescenario`:

* `rock` (All That Glitters v2.2.3): the original five Sheldons behind the rock, target
  Fatboy. `attackobstaclemovestate` 0 = hold position (original), 1 = maneuver.
  One Sheldon starts against the cliff with its muzzle 60 elmo inside the rock.
* `friendlyline` (Quicksilver Remake 1.24): five `attackobstaclelineunit` (default cormort)
  in a column, `attackobstaclelinespacing` elmos apart, target 600 ahead, optionally
  `attackobstaclelineoffset` elmos to the side. Not a useful cascade test: Sheldons' estimated
  muzzle is 10.8 elmo off-centre so the pre-aim test says "clear" while the real muzzle is
  blocked (a #3327 estimate question), Lugers shoot over each other.
* `wall` (Quicksilver): five Sheldons abreast, a row of seven `attackobstaclewallunit`
  80 elmo in front (armbanth = mobile allies, armfort = allied structures), Fatboy 450
  beyond. This is the cascade test: behind Banthas the shooters must not move, behind
  fortifications they must walk around.

`dbg_rocko_slope_stall_reproducer.lua` (`rockoslopeattack=1`): the Rocko crest scenario
with a plain `CMD.ATTACK` instead of the sticky Set Target. Already fires without moving
on #3327 + #3325, so it does not exercise this change.

`dbg_corcom_tick_attack_stall_reproducer.lua` (`corcomtickattackstall=1`, All That Glitters):
a Cortex commander ordered to attack three Ticks 335 elmo away stops 320 elmo short and never
fires, because its never-aiming sea laser passes the range test from its forward muzzle piece
while the land laser is out of range (from a 2026-09-05 replay). `corcom_tick_attack_stall`
(scenario 1), `_second` (scenario 2, second attack of the replay), `_fireatwill`, and
`corcom_tick_move` (plain move order, terrain control). Result: `CORCOM_TICK_STALL_RESULT`
(`stalled`, `moved`, `distToTarget`, `projectiles`). Original folder:
`~/Projects/bar/corcom-tick-attack-stall-reproducer/` (README with the weapon analysis).

`dbg_mship_geo_reproducer.lua` (`mshipgeoreproducer=1`, Supreme Isthmus v2.1): four Cortex
missile cruisers get a ground attack on an advanced geo on the 304 elmo plateau ([Crd]gunseng's
replay). `mship_geo_far` (1396-1630 elmo, every ship stalls on stock), `mship_geo_close`
(`mshipgeolayout=close`, 1268-1441 elmo: the two nearest fire on stock, the two farthest sit in
range without a solution), `mship_geo_far_unit` (unit-target attack). `mshipgeoautoquit=1` ends
the game at frame 1830. Result: `MSHIP_GEO_RESULT` every 90 frames per ship (`moved`,
`tryTarget`, `projectiles`). Original folder: `~/Projects/bar/mship-geo-reproducer/`.

`dbg_lof_underground_probe.lua` (`lofprobe=1`, `startscript_lof_probe_rock.txt`): the
line-of-fire probe used for #3328, see `docs/pr3328-traceray-underground.md`.

## Whole matrix

    ./run-matrix.sh <spring-headless> <label> [parallel]   # every start script -> results/<label>/
    ./summarize-matrix.py master pr3242                     # side-by-side metrics and PASS/FAIL

`tools/build-both.sh` builds master and the stacked branch (full install) into
`../engines/master/` and `../engines/pr3242/` (paths are this machine's, adjust); `results/master/` and `results/pr3242/` are the
2026-09-05 runs of both.

## Videos

`record-all.sh` / `record-new.sh` record with `demos/aim-stall-videos/record-reproducer.sh`
(OBS whole-screen capture, engine fullscreen); `corcom-overlay/` and `mship-overlay/` are the
one-gadget overlay dirs the recorder expects. `make-previews.sh` cuts the first batch with
hand-read Awards times, `make-preview-auto.sh <label>` cuts a video by scene detection and
prepends the 2 s end-state still. Output in `~/Projects/bar/demos/close-in-videos/preview/`.

Result lines: `ATTACK_OBSTACLE_RESULT` (per shooter at frame 800: targetHits, moved,
distToTarget, movedLast60Frames), `ATTACK_OBSTACLE_DIAG` every 100 frames (tryTarget,
LOF from estimate and from muzzle, move progress). `results/` holds the runs used for the PR:
`before*` = engine without the CommandAI commits, `after3` = final engine.
