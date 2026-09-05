Fixes #3242.

Stacked on #3328 (rays that start below the terrain), #3325 (AimWeapon heading) and #3327 (`aimFromEstimate`): the first four commits are theirs and disappear from this diff once they land. The fix itself is the last two commits.

## Problem

In current game, units with an attack command that are within 90% of their weapons range will stop moving towards the target, even if terrain obstructs the shot.

This results in units disobeying a players attack command and just cowardly hiding behind a rock.

`CMobileCAI` decides whether an attacker stops or keeps moving with the preliminary line-of-fire test (`TryTargetRotate` for unit targets, `TryTargetHeading` for ground targets). When the target is inside `0.9 * maxRange` and no weapon passes that test, the CAI does nothing useful: it plain-returns (unit target) or stops and keeps pointing (ground target), and retries from the same spot every SlowUpdate.

Video of the issue on master (five Sheldons, two stuck behind the rock, one not shooting behind another Sheldon):

https://github.com/user-attachments/assets/7eab142d-acba-4be2-ace3-0675c06602fc

## Earlier attempts (kept for reference)

1. Re-check the muzzle-below-ground condition in the pre-aim test: small improvement only.
2. Fall back to the `strafeToAttack` code when there is no solution — best results at the time, preserved in `archive/attack-obstacle-close-in-original`. @sprunk pointed out that a solution found by rotating can become invalid again after the rotation.
3. Detect the blocked state and keep moving towards the target: the rear Sheldons of a group walk to the front, block the ones they passed, and the whole ball creeps forward.
4. Detect the blocked state, sidestep first, then move closer (`FindBlockedAttackSidestepGoal`): works in the reproducers but a lot of code. Preserved in `archive/attack-obstacle-close-in-sidestep`.

## Idea

The current AI does nothing at 90% of weapons range if there's no shot, causing units to stay behind rocks or blindly continue walking depending on the unit state. 

If we tell the unit to continue closing in when the shot is blocked, it causes the creep behavior in groups of units, where the back of the pack tries to move to the front and then the other units get block and they try to get to the front. 

So the simple boolean test, blocked or not, is not enough. A unit in firing range should continue moving if terrain or buildings obstruct a shot but they should stop moving if a friendly unit is in the way. 

The core idea of this PR is to differentiate between the two obstruction types.


## Implementation

* **TraceRay**: new `Collision::NOMOBILEFRIENDLIES`, a trace-only flag (never part of a weapon's `avoidFlags`) that skips allied units that are able to move. Allied structures, features and terrain are still scanned. Honoured by `TraceRay`, `TestCone`, `TestTrajectoryCone` and the MissileLauncher trajectory scan.
* **CWeapon**: `TryTargetRotate` / `TryTargetHeading` take optional extra avoid flags for one test.
* **CMobileCAI**: when the target is in range but no weapon has a solution, test again with mobile allies ignored.
  * still no solution: the blocker is static (terrain, feature, allied wall or building) and the unit keeps closing in like an out-of-range unit would, for unit and ground targets;
  * solution: only an allied unit is in the way and it may move out of it, so the unit **stops** and waits (`StopMove` + `KeepPointingTo`) instead of walking past it.
  * Bounds: the approach stops at 20% of `maxRange` (artillery does not walk up to a target that sits behind a wall); an approach that fails (unreachable goal, e.g. the rock itself) is not retried for 10 seconds; `stopToAttack` units always wait; the `strafeToAttack` sidestep and the gunship / very-close / owner-rotation branches are unchanged. Hold-position units follow the same logic: an explicit attack order already makes them approach an out-of-range target, and the temp-order case is cancelled earlier as before.
* **CWeapon::TryTarget**: the "aim position below ground" rejection, so far only applied at fire time to the real muzzle, is also applied to the predicted muzzle (`aimFromEstimate`). Without it a Sheldon standing against a cliff (muzzle 60 elmo inside the rock) passes the pre-aim test, stops, and can never fire; with it the CAI sees a static blocker and moves the unit out. The `AimFromWeapon` piece is deliberately not checked: it may legitimately sit inside the hull below the surface on slopes. With #3328 an underground predicted muzzle is also caught by `HaveFreeLineOfFire` itself; this check stays because it covers weapons that skip ground checks (`avoidGround = false`) and mirrors the fire-time test.

Why stopping matters: the plain `return` of the old code has the creep problem of attempt 3 already. The goal set with the attack order is the target itself, so a unit that enters range without a solution simply keeps walking; the false positives of the old pre-aim test hid that. With the honest test a column of five Sheldons ordered to attack a Fatboy 600 elmo away walks all the way up to it.

## Performance consideration

Cost: For every units that are within 90% range of their target and have no firing solution we make one extra `TryTargetRotate` per weapon per SlowUpdate.


## Validation

Headless runs of BAR overlays (gadgets, start scripts and runner: https://github.com/eun-ice/bar-attack-reproducers), BAR `feature/aim-from-estimate` (beyond-all-reason/Beyond-All-Reason#9090). "baseline" = #3325 + #3327 without the fix commits. Five Sheldons per run, `targetHits` and `moved` (elmos) per unit at frame 800:

| scenario | baseline | this branch |
|---|---|---|
| rock, maneuver: five Sheldons behind the rock, one of them against the cliff | 2 stall (moved 11–15, 0 hits), 3 walk ~350–400 and hit | all 5 walk out (moved 340–400), 3 hit 7–9×, 2 fire but hit only the Fleas around the Fatboy; all stand still afterwards (`movedLast60Frames=0`) |
| rock, hold position | 1 stalls against the cliff (moved 14, 0 hits) | all 5 reposition, same as maneuver |
| wall, mobile: five Sheldons abreast behind seven allied Banthas (100 elmo high), Fatboy 450 beyond | shooters push 45–70 elmo into the Bantha row, 1 slips through and hits 13× | **no shooter moves** (0.0 elmo), none fires; they wait for the Banthas |
| wall, static: same with seven allied fortification walls | shooters walk 60–207, 4 hit (they were walking to the target anyway) | 3 walk around the walls (56–138) and hit 12–13×, 2 stop behind the Sheldons that went first and wait |
| Rocko on the crest, plain attack order | fires without moving (fixed by #3325/#3327) | unchanged |

Two reproducers built from player reports, plus one more wall variant, run against **master** (not the #3325 + #3327 baseline) and the current branch stacked on #3328:

| scenario | master | this branch |
|---|---|---|
| missile cruisers vs. plateau geo, far ([Crd]gunseng's replay, Supreme Isthmus): four `cormship` 1396–1630 elmo from an advanced geo on the 304 elmo plateau, ground attack on it | all 4 stop (`moveState=done`), `tryTarget=false`, 0 rockets in 60 s | all 4 close in (139–359 elmo) and fire, 7–8 rockets each |
| missile cruisers, close: 1268–1441 elmo | the 2 nearest fire (8 each), the 2 farthest sit in range without a solution, 0 rockets | all 4 fire; the two farthest move 144 and 171 elmo first |
| missile cruisers, far, **unit**-target attack on the geo | all 4 fire | all 4 fire (unchanged) |
| wall, mobile: five Sheldons behind seven allied Korgoths | shooters walk 121–156 around the Korgoths, all 5 hit | **no shooter moves**, none fires; they wait for the Korgoths |
| Cortex commander vs. three Ticks (replay 2026-09-05, All That Glitters): area attack on Ticks 335 elmo away, commander stops 320 elmo short of its 300-range laser | stalls, 0 shots | stalls, 0 shots (**not covered**, see below) |

The commander case is the unit-target sibling of #3242 but this change cannot see it: the commander's sea laser (never aims on land) passes `TryTargetRotate` from its forward muzzle piece while the land laser is out of range, so the CAI is told there *is* a solution and stops. Only a "no weapon has a solution" state triggers the re-test added here. It needs its own fix (a weapon the script refuses to aim should not count as a solution); reproducer and analysis are in the repo above.

The two waiting units in the static-wall row are the price of the "wait for allies" rule: the allies in the way are their own group mates, which now stand and fire. A sidestep for that case (lateral goal instead of waiting) is a possible follow-up; it is a different problem from #3242 and was left out on purpose.

## Videos

Same scenarios as above, recorded fullscreen at 1x; baseline = #3325 + #3327 without the fix commits. Each video opens with a two-second still of the end state, then runs from game start to the result at frame 800.

**Rock, maneuver: baseline.** Two Sheldons stay behind the rock, one of them with its muzzle inside the cliff.

https://github.com/user-attachments/assets/c8cb56d3-66ad-4379-b5be-825527eb1fec

**Rock, maneuver: this branch.** All five walk out and stop once they have a shot. (Re-recorded with the branch stacked on #3328.)

https://github.com/user-attachments/assets/61d1334a-3430-4565-9b43-986fbe10efad

**Rock, hold position: baseline.**

https://github.com/user-attachments/assets/a646f45f-b697-49dc-bea0-289f930bdd76

**Rock, hold position: this branch.**

https://github.com/user-attachments/assets/832fc55f-a0e3-4371-a638-f034269718be

**Bantha row (mobile allies): baseline.** The Sheldons push into the row of allied Banthas that blocks their shot.

https://github.com/user-attachments/assets/eddcf44a-6f82-4e6f-8c89-963bdb30b27d

**Bantha row (mobile allies): this branch.** Nobody moves; they wait for the Banthas.

https://github.com/user-attachments/assets/66164951-bc25-429d-8d55-68bacc013a05

**Fortification row (allied structures): baseline.**

https://github.com/user-attachments/assets/fd3638b1-5708-4de0-9353-1dad60898ab6

**Fortification row (allied structures): this branch.** Three walk around the wall and fire, two wait behind the Sheldons that went first.

https://github.com/user-attachments/assets/98747aa5-55e1-4eec-8485-2d7b48edb39c

**Rocko on the crest, plain attack order: this branch.** Fires from where it stands (#3325 + #3327 already fixed this; unchanged here).

https://github.com/user-attachments/assets/460b4a71-ffbc-4c4f-a490-83d34babd68b

**Missile cruisers vs. plateau geo, far layout: master.** All four sit at 1396–1630 elmo, aim at the geo, and never fire (cut at 32 s, nothing happens afterwards).

https://github.com/user-attachments/assets/a3a96820-22e1-41ae-8ce9-6a3f465ca187

**Missile cruisers, far layout: this branch.** All four close in and shell the geo (cut at 32 s).

https://github.com/user-attachments/assets/cef83d5d-73b7-4fa8-b4f0-6d39a73ee512

**Missile cruisers, close layout: master.** The two nearest fire, the two farthest never do.

https://github.com/user-attachments/assets/c613d0af-699c-4b80-a99c-9833f49caeed

**Missile cruisers, close layout: this branch.** The two farthest move up and all four fire.

https://github.com/user-attachments/assets/6ed3bf27-5fa5-4136-b073-ddcbd05054ab

**Commander vs. Ticks: master.** Stops 320 elmo from the Ticks with the attack order and never fires.

https://github.com/user-attachments/assets/d906aabf-7996-4b0e-a942-98c044b2c831

**Commander vs. Ticks: this branch.** Unchanged, see above.

https://github.com/user-attachments/assets/effd87a4-3b40-452c-992a-e0d0e060f6ef

Known residual visible in the rock videos: a Sheldon can stop at a spot where the pre-aim test from the estimated muzzle says "clear" but the real muzzle is a few elmo above the terrain and the fire-time test says "blocked". The CommandAI is then told there is a solution and stays; that is an estimate-accuracy question for #3327 / the BAR values, not something this change can see.

## AI disclosure

OpenAI Codex assisted with the earlier attempts; Claude Code (Fable 5.1) assisted with diagnosis, implementation, the reproducers and this description of the current approach. I directed the iterations and reviewed the diff and in-game behaviour.




