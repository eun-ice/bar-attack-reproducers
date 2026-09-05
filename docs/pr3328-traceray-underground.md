Fixes #3242. Likely fixes #3301 (see below).

## Problem

`CGround::LineGroundCol` returns a hit distance of **0** when the ray origin is below the terrain. `TraceRay` only accepted ground hits with `groundLength > 0.0f`, and `CWeapon::HaveFreeLineOfFire` applied the same `> 0` filter to the returned distance. A ray that starts underground was therefore reported as *unobstructed*. `CCannon::HaveFreeLineOfFire` had the identical pattern with `CGround::TrajectoryGroundCol`, which also reports 0 for that case.

Consequences:

* A Sheldon standing against a cliff with its muzzle 65 elmo inside the rock passes the pre-aim line-of-fire test, stops, and can never fire because the fire-time test rejects the underground muzzle (#3242, the "stops and does not even start to walk" case).
* `Spring.GetUnitWeaponHaveFreeLineOfFire` tells game code the same thing.

Additionally the underground test in `LineGroundCol` compared the origin against the **corner vertex** of its heightmap square rather than the interpolated surface. Next to a steep cliff that vertex can sit far above an origin that is well clear of the ground, and then the whole ground trace was skipped. That is the shape of #3301: a mech at the foot of a cliff reports a free line of fire to a unit on top of it as soon as it moves close to the cliff face. `Spring.TraceRayGroundBetweenPositions`, which @FLOZi swapped in, treats 0 as a hit and so looked correct in the same situation.

## Change

* `TraceRay`: accept a ground distance of 0 as a hit (the ray is blocked at its origin). Only -1 means "no ground hit".
* `CWeapon::HaveFreeLineOfFire`: same for the returned distance. `CMissileLauncher` already handled it.
* `CCannon::HaveFreeLineOfFire`: reject a source below `GetHeightReal` explicitly, the test the fire-time check already applies to the muzzle, and keep ignoring the 0 from `TrajectoryGroundCol`. That scan uses `GetApproximateHeight`, which on rough ground lies above sources a couple of elmo clear of the interpolated surface; accepting its 0 blocked 48 above-ground probe points that are free today.
* `CGround::LineGroundCol`: the underground test compares against the interpolated height (`InterpolateCornerHeight`) and treats an origin exactly on the surface as above ground. `LineGroundSquareCol` still returns a hit at distance 0 when such a ray points into the ground, so the "unit position on the surface" case keeps working for rays pointing up and is blocked for rays pointing down.

Callers that scan ground with `TraceRay` are `HaveFreeLineOfFire`, `BeamLaser`, `LightningCannon`, `Rifle` and the AI callbacks. The weapons already refuse to fire when the real muzzle is below `GetHeightReal` (`TryTarget`, `preFire`), so with the interpolated underground test they never reach the new "blocked at origin" branch at fire time.

#3241 is stacked on this PR. Its explicit below-ground check for the predicted muzzle stays: it also covers weapons that skip ground checks (`avoidGround = false`) and mirrors the fire-time test.

## Validation

Headless probe in the #3242 rock scenario (five Sheldons behind the rock on All That Glitters, one with its muzzle inside the cliff; gadget `dbg_lof_underground_probe.lua` in my workspace), same BAR checkout, before = engine without this commit:

The probe creates a Flea (BeamLaser, `CWeapon::HaveFreeLineOfFire`) and a Pawn (Cannon, `CCannon::HaveFreeLineOfFire`) and calls `Spring.GetUnitWeaponHaveFreeLineOfFire` with explicit source positions towards the Fatboy.

| test | before | after |
|---|---|---|
| Sheldon with its muzzle 65 elmo inside the cliff: 3-arg and 6-arg (from muzzle) call | free / free | blocked / blocked |
| the other four Sheldons (muzzle 11 below to 26 above ground) | blocked | blocked (unchanged) |
| source 40 elmo **below** each Sheldon's position, laser and cannon (10 calls) | all free | all blocked |
| source 40 elmo above each Sheldon's position, laser and cannon | all blocked (rock in the way) | all blocked (unchanged) |
| `Spring.TraceRayGroundBetweenPositions` from the same underground sources | hit at 0 | hit at 0 (unchanged) |
| **laser**, 289 sources 2 elmo above the ground on a 128x128 grid around the cliff Sheldon | 8 free: exactly the 8 points whose heightmap corner vertex lies above the source, i.e. where the old underground test skipped the trace | 0 free: those 8 rays hit the rock face within 2.3 elmo |
| **cannon**, same grid | 48 free | 48 free, identical set (the trajectory scan is unchanged) |

Full rock reproducer (hold position and maneuver) on master + this commit: the cliff Sheldon's pre-aim test now fails (`tryTarget=false lofAim=false lofMuzzle=false`), so it no longer stops believing it has a shot. Getting it to walk out of the corner is what #3241 does; without it master's CommandAI still leaves it there.
