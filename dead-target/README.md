# Dead target keeps moving reproducer (RecoilEngine #3332)

Headless overlay for a Beyond All Reason checkout. From the replay
`2026-09-06_23-28-45-736_All That Glitters v2.2.3_2026.07.04.sdfz` (engine 2026.07.04): an Armada
commander with queued attack orders on Fleas killed the last one (frame 2287) just after it had
started closing in on it. The order was finished at frame 2289 with an empty queue, but the
commander walked on for ~290 elmo to the Flea's last position (goal of the close-in step) and only
stopped there at frame 2525.

## What happens

When the target object is deleted, `CCommandAI::DependentDied` removes every command that
references it with `ExecuteRemove(CMD_REMOVE, tag)`. For the active command `ExecuteRemove`
calls `FinishCommand()` and nothing else, so the move type keeps heading for the goal the attack
order had set (`CMobileCAI::ExecuteAttack` / `ExecuteObjectAttack` `SetGoal` to the target's
position minus its radius). The `targetDied` branch in `CMobileCAI::ExecuteAttack`, which does
`StopMoveAndFinishCommand()`, never runs for this: by the next SlowUpdate the command is gone.
Removing the active command from the queue with `CMD_REMOVE` (queue editing) has the same effect.

Normally invisible because a unit that kills its target has usually already stopped in range;
it shows when the target dies while the unit is still moving towards it (the unit itself firing
during a close-in step, or an ally killing the target).

## Files

* `luarules/gadgets/dbg_dead_target_keeps_moving_reproducer.lua`, enabled by modoption
  `deadtargetreproducer=1`. Destroys the initial spawn, enables global LOS, creates the attacker
  (`deadtargetunit`, default `armcom`) at the replay position 3472.7,908.4 facing +z and the
  target (`deadtargettarget`, default `armflea`, team 1 NullAI) `deadtargetdist` (default 600)
  elmo further along +z (568 elmo on this map after the standability search). Frame 30: orders.
  Once the attacker has walked 120 elmo the trigger fires; 480 frames later a `RESULT` line with
  a verdict is printed and the game quits.
* `deadtargetvariant`:
  * `destroy` (default): `CMD.ATTACK` on the target, the target is destroyed at the trigger.
    Expected: the attacker stops. Master: walks 415 elmo on to the target's position.
  * `queued`: as `destroy` with a `CMD.MOVE` shift-queued behind the attack. Expected: the
    attacker goes straight to the move goal (control for "do not stop when the next command
    moves the unit anyway"). Passes on master and on the fix.
  * `remove`: plain `CMD.MOVE` to the same spot; at the trigger the active command is removed
    with `CMD.REMOVE <tag>`. Expected: the unit stops. Master: walks 427 elmo on to the goal.
  * `luagoal`: as `destroy`, but in the trigger frame a gadget first calls
    `Spring.SetUnitMoveGoal` towards another spot. Expected: the unit keeps walking to the Lua
    goal; the removed attack order must not clear a goal it did not set. Passes on master, fails
    on the first fix commit (unconditional stop), passes on the second.
  * `replace`: as `destroy`, but at the trigger a replacement `CMD.ATTACK` on the same target is
    inserted at the front of the queue (`CMD.INSERT`) and the original one, now second, is
    removed by tag; the target is destroyed 30 frames later. Expected: the unit stops, i.e. the
    move goal is owned by the replacement order, not by the removed one. Master: walks 378 elmo.
* `tools/StartScripts/startscript_<variant>.txt`, `run.sh <spring-headless> <startscript> <label>`
  (isolated write dir, gadget symlinked into the BAR checkout, `results/<label>.results.txt`),
  `run-all.sh <spring-headless> <label>` runs the five variants.
* `results-summary.txt`: master (origin/master 680e33a241 == 2026.07.01-61), the first fix commit
  (`fix_*`, 5dc4002df2: unconditional `StopMove()` in `ExecuteRemove`) and the second
  (`fix2_*`, ff99e47982: stop only if the removed command owns the move goal).

## Results

| variant | master 680e33a241 | fix commit 1 (5dc4002df2) | fix commit 2 (ff99e47982) |
|---|---|---|---|
| destroy | FAIL: 415 elmo after the kill, stops 38 elmo from the dead target's spot, queue empty | PASS: 1.4 elmo | PASS: 1.4 elmo |
| queued | PASS: straight to the move goal | PASS | PASS |
| remove | FAIL: 427 elmo after the removal, stops 28 elmo from the removed goal | PASS: 0.1 elmo | PASS: 0.1 elmo |
| luagoal | PASS: keeps the Lua-set goal | FAIL: stops, the Lua goal is discarded | PASS: keeps the Lua-set goal |
| replace | FAIL: 378 elmo after the kill, stops 38 elmo from the dead target's spot | PASS: 1.4 elmo | PASS: 1.4 elmo |

Fix (PR [RecoilEngine #3333](https://github.com/beyond-all-reason/RecoilEngine/pull/3333), branch
`fix/stop-move-on-removed-active-command`): `ExecuteRemove` calls `StopMove()` before finishing the
removed active command if that command owns the move goal (`CCommandAI::moveGoalCmdTag`, set by
`CMobileCAI::SetGoal`, reset by `Spring.SetUnitMoveGoal`) and the next queued command is not a move
command.
