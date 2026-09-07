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
* `tools/StartScripts/startscript_<variant>.txt`, `run.sh <spring-headless> <startscript> <label>`
  (isolated write dir, gadget symlinked into the BAR checkout, `results/<label>.results.txt`),
  `run-all.sh <spring-headless> <label>` runs the three variants.
* `results-summary.txt`: master (origin/master 680e33a241 == 2026.07.01-61) vs the fix build.

## Results

| variant | master 680e33a241 | fix |
|---|---|---|
| destroy | FAIL: 415 elmo after the kill, stops 38 elmo from the dead target's spot, queue empty | PASS: 1.4 elmo |
| queued | PASS: straight to the move goal | PASS: straight to the move goal |
| remove | FAIL: 427 elmo after the removal, stops 28 elmo from the removed goal | PASS: 0.1 elmo |

Fix: `ExecuteRemove` calls `StopMove()` before finishing the active command unless the next
queued command is a move command (branch `fix/stop-move-on-removed-active-command`).
