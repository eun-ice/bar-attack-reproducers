# Missile cruiser vs. plateau geo reproducer

Minimal overlay for a Beyond All Reason checkout. It recreates the situation
from Discord report by `[Crd]gunseng` (replay id
`2835b469b0fd6def46f281c6fd5e7ed5`, `2026-03-13_16-02-48-437_Supreme Isthmus
v2.1_2025.06.19.sdfz`, 31:31-32:54 game time): four Cortex missile cruisers
(`cormship`) receive a ground `CMD.ATTACK` on an advanced geothermal
(`corageo`) that stands on the ~304 elmo plateau of `Supreme Isthmus v2.1`.
The cruisers aim, keep the order, and neither fire nor move closer.

## What the replay contains

- Player 14 `[Crd]gunseng` (Cortex) issued eight ground attacks with the same
  four units selected, alternating between (10416.8, 304.1, 6813.2) and
  (10054.3, 303.3, 6610.0), frames 55307-59225. All were ground attacks with
  four parameters, not unit-target attacks.
- The map's `geovent` feature is at (10420, 6800); the geo snaps to
  (10424, 303.9, 6808). The nearest deep water is ~540 elmo away, so the geo is
  well inside the cruisers' nominal 1550 range from the sea.
- The command stream does not carry unit positions. The spawn positions in the
  gadget are estimated: a north-south line in the deep water south-west of the
  plateau, 1396-1630 elmo from the geo, like the reporter's screenshot.

## Install

Copy `luarules/`, `luaui/` and `tools/` into the BAR repository root,
preserving paths. The data directory must contain `Supreme Isthmus v2.1`.

## Run

```sh
'/path/to/recoil/spring' \
  --window \
  --isolation \
  --write-dir '/path/to/isolated-bar-data' \
  '/path/to/Beyond-All-Reason/tools/StartScripts/startscript_mship_geo.txt'
```

Frame 1 spawns the geo (team 1, NullAI) and the four cruisers (team 0), frame 30
issues the attack, and every 90 frames until 1800 the gadget writes one
`MSHIP_GEO_RESULT` line per ship to `infolog.txt`. The geo is invulnerable by
default so the stalled ships stay observable.

Modoptions in the start script:

| option | default | meaning |
| --- | --- | --- |
| `mshipgeoreproducer` | 1 | enables gadget and widget |
| `mshipgeoattackmode` | ground | `ground` = recorded ground attack, `unit` = attack the geo unit |
| `mshipgeovulnerable` | 0 | 1 lets the rockets destroy the geo |
| `mshipgeoscreenshots` | 0 | 1 takes screenshots at frames 120, 600, 1200 |
| `mshipgeoautoquit` | 0 | 1 quits at frame 1830 |

## Observed result

Engine 2025.06.19 (the replay's engine), `results/engine-2025.06.19-stock.log`:
all four ships keep `queue=20[10417,304,6813]`, stop moving (`moveState=done`),
auto-acquire the geo (`weaponTarget=unit:<geo>`), report `testRange=false
tryTarget=false` for the order and fire nothing for 60 seconds:

```text
frame=1800 ship=29750 idx=1 pos=9200.0,-1.0,7480.0 speed=0.00 dist2d=1396 moved=0   moveState=done queue=20[10417,304,6813] weaponTarget=unit:25171 testRange=false tryTarget=false canFire=true projectiles=0
frame=1800 ship=27190 idx=4 pos=9396.6,-1.0,7782.9 speed=0.00 dist2d=1416 moved=236 moveState=done queue=20[10417,304,6813] weaponTarget=unit:25171 testRange=false tryTarget=false canFire=true projectiles=0
```

With a closer line (1268/1327/1395/1441 elmo) the two nearest ships fired and
destroyed the geo while the two farthest stalled, so the effective range for
lobbing onto the +305 elmo plateau lies between ~1330 and ~1395 elmo; the
cruisers' order logic treats up to 1550 as in range and does not close in.

PR 3241 (`fix/3242-close-in-static-blockers`, commit 5069900) covers this case:
in `ExecuteGroundAttack` a target inside `0.9 * maxRange` with no weapon
solution is re-tested with mobile allies ignored, and a failure that survives
that re-test (the range failure does) counts as a static block, so the unit
keeps closing in via `SetGoal(attackPos)`. Run of the close layout
(1268/1327/1395/1441 elmo) with a binary of that commit,
`results/engine-2026.07.01-64-g5069900-pr3241-close-layout.log`: the two ships
that started in the in-range-without-solution state moved in (1395 -> 1252 and
1489 -> 1291 elmo) and fired; on stock the same two ships stalled. The far
layout has not been run against a PR 3241 binary yet.
`results/engine-2026.07.01-62-g53e7a9b-traceray-branch.log` is the far layout
on a master-based build without the PR; it stalls like stock.

`tools/scan-demo-commands.py <demo.sdfz> [cmdIDs] [tmin_s] [tmax_s]` prints the
player command stream that was used to locate the situation.
