# Cortex commander attack stall reproducer (stock engine 2026.07.04)

Headless overlay for a Beyond All Reason checkout. Rebuilt from the replay
`2026-09-05_05-22-43-092_All That Glitters v2.2.3_2026.07.04.sdfz` (player data dir):
the player gave the Cortex commander an area attack on three Ticks (`armflea`) about
335 elmo away. The commander walked ~15 elmo, stopped 320 elmo from the nearest Tick
(20 elmo outside its 300 laser range), kept the attack order and never fired. Both
attack episodes of the replay (frame 1511 and frame 2059) are reproduced exactly.

## What happens

`CMobileCAI::ExecuteObjectAttack` stops the unit as soon as *any* weapon's
`TryTargetRotate` succeeds and hands the target to the weapons. The Cortex commander has
three weapons:

| # | weapon | range | aim-from piece (`corcom.bos`) | note |
|---|--------|-------|-------------------------------|------|
| 1 | `corcomlaser` (J7Laser) | 300 | `torso` (unit centre) | the weapon that can fire on land |
| 2 | `corcomsealaser` (J7NSLaser) | 300 | `lfirept` (muzzle, ~24 elmo forward) | `AimSecondary` returns 0 while `PIECE_Y(head) > 0`, i.e. never aims on land |
| 3 | `disintegrator` | 262 | `torso` | manual fire only, fails `TestTarget` for a plain attack |

Range is tested from the aim-from piece with `targetBorder = 1` (the Tick's collision
volume edge is ~10 elmo closer), so at 320 elmo weapon 2 passes `TestRange`
(24 + 10 elmo of slack) while weapon 1 fails. The CAI therefore calls `StopMove()`,
weapon 2 takes the target (`GetUnitWeaponTarget` = the Tick) but its script refuses to
aim because the commander is on land, weapon 1 rejects the target as out of range, and
nothing is ever re-evaluated: the commander stands there with the attack order forever.
Fire state, move state and terrain play no role (see the variants). A plain move order
to the Tick position walks straight there, so the terrain is passable.

Diagnostics in the log show it directly (`WEAPONS` line):

```
w1[test=true range=false try=false ... tgtType=0] w2[test=true range=true try=true ... tgtType=1] w3[test=false ...]
```

The same behaviour is expected for any unit whose "can I shoot from here" oracle is a
weapon the unit script will not aim (submerged-only weapons on amphibious units), when the
target sits between the two weapons' effective ranges. This is the unit-target variant of
RecoilEngine #3242 (attackers stop without a firing solution), on stock 2026.07.04; the
`fix/traceray-underground-start` dev build (2026.07.01-62) reproduces it as well.

## Files

* `luarules/gadgets/dbg_corcom_tick_attack_stall_reproducer.lua` — synced gadget, enabled
  by modoption `corcomtickattackstall=1`. Destroys the initial-spawn units, enables global
  LOS (the replay had `/globallos`), creates the commander (team 0) and the three Ticks
  (team 1, NullAI) at the replay positions, sets fire/move state, and at frame 30 gives
  the same orders `CSelectedUnitsHandlerAI::SelectAttackNet` produces for the area
  attack: `CMD.ATTACK <nearest tick>` followed by shift-queued attacks on the other two.
  Every frame for 100 frames, then every 30 frames, it logs `DIAG` (position, speed,
  move-type progress/goal, front command, distance, weapon 1 range/try/LOF) and `WEAPONS`
  (all three weapons: TestTarget/TestRange/TryTarget/LOF/current target/muzzle).
  Frame 630: `RESULT` line. Every command reaching the commander is logged
  (`ALLOWCOMMAND`/`UNITCOMMAND`) to show that no Lua issues stops.
* Modoptions: `corcomtickattackstallscenario` 1 = commander on its start position
  (replay frame 1511), 2 = commander at 3438.8,682.7 heading 31972 (replay frame 2059);
  `corcomtickattackstallorder` `attack` (default) or `move` (plain move to the Tick, the
  terrain control); `corcomtickattackstallfirestate` (default 0 = hold fire, as in the
  replay; 2 = fire at will); `corcomtickattackstallmovestate` (default 0 = hold position,
  as in the replay).
* `tools/StartScripts/` — one start script per variant (All That Glitters v2.2.3,
  team 0 Cortex player, team 1 NullAI).
* `run.sh <spring-headless> <startscript> <label> [timeout]` — links the gadget into the
  BAR checkout (`BAR_CHECKOUT`, default `~/Projects/bar/Beyond-All-Reason`), exposes it as
  `games/Beyond-All-Reason.sdd` in `DATA_DIR` (default `./data`) with the map from
  `BAR_MAPS_DIR` (default `~/Projects/bar/bar-dev/data/maps`), runs headless, writes
  `results/<label>.{log,infolog.txt,results.txt}` (the result lines are taken from the stdout `.log`; the infolog copy can miss the last lines).
* `rerun-all.sh` — runs the four variants with the stock engine (`STOCK_ENGINE`) and,
  if `DEV_ENGINE` is set, scenario 1 with that build; prints the `RESULT` lines.
* `results/` — the runs used for this write-up (BAR master 798d39c8f7, worktree
  `/tmp/bar-master-wt`).

## Run

```sh
BAR_CHECKOUT=/tmp/bar-master-wt ./run.sh \
  '/home/aron/.local/state/Beyond All Reason/engine/recoil_2026.07.04/spring-headless' \
  tools/StartScripts/startscript_corcom_tick_attack_stall.txt attack1
```

Reproduced failure (`RESULT` at frame 630):

```
RESULT stalled=true order=attack scenario=1 ... moved=15 distToTarget=319.6 minDistToTarget=319.6 range=300 progress=done cmd=20 projectiles=0 targetAlive=true
```

Expected after a fix: `stalled=false`, `projectiles>0`, `targetAlive=false` (Ticks have
60 HP; the laser does 75).

The `move` variant reports `order=move ... distToTarget<30`, showing the path is clear.

## Notes

* `Spring.RequestPath` from the synced gadget segfaulted spring-headless 2026.07.04
  (core dump, no stack), so the path probe was replaced by the move variant.
* The replay itself was analysed with a LuaUI widget in an isolated replay run, see
  `~/Projects/bar/demos/replay-diag/` (`data/LuaUI/Widgets/dbg_replay_diag.lua`,
  `diag1.txt`): the commander stops at 320.8 / 313.4 elmo in the two episodes with
  `progress=done`, weapon 1 `range=false`, no shots.
