local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Dead Target Keeps Moving Reproducer",
		desc = "A mobile unit whose attack target dies while it is still closing in walks on to the target's last position (from replay 2026-09-06, All That Glitters)",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

local function ModOpt(key, default)
	local v = Spring.GetModOptions()[key]
	if v == nil then return default end
	return v
end

if ModOpt("deadtargetreproducer", "0") ~= "1" then
	return false
end

local PREFIX = "DEAD_TARGET_"

if not gadgetHandler:IsSyncedCode() then
	-- unsynced: quit once the synced side has printed its result
	function gadget:Initialize()
		gadgetHandler:AddSyncAction("deadtarget_done", function() Spring.SendCommands("quitforce") end)
	end
	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("deadtarget_done")
	end
	return
end

local function Echo(fmt, ...) Spring.Echo(PREFIX .. string.format(fmt, ...)) end

-- variant:
--   destroy  attack order on a unit far away; the target is destroyed once the attacker
--            has walked TRIGGER_DIST elmo (expected: the attacker stops)
--   queued   same, with a move order shift-queued behind the attack (expected: the attacker
--            continues straight to the move goal, not via the dead target's position)
--   remove   plain move order that is removed from the queue with CMD.REMOVE once the unit
--            has walked TRIGGER_DIST elmo (expected: the unit stops)
local opts = {
	variant = ModOpt("deadtargetvariant", "destroy"),
	dist = tonumber(ModOpt("deadtargetdist", "600")),
	unit = ModOpt("deadtargetunit", "armcom"),
	target = ModOpt("deadtargettarget", "armflea"),
}

local SETUP_FRAME = 5
local ORDER_FRAME = 30
local TRIGGER_DIST = 120       -- elmo the attacker must have walked before the target is killed
local RESULT_DELAY = 480       -- frames between trigger and RESULT (enough to walk the remaining way)
local STOP_TOLERANCE = 60      -- elmo of travel after the trigger still accepted as "stopped"
local ARRIVE_TOLERANCE = 40

-- attacker position and facing from the replay (commander facing +z)
local START = { x = 3472.7, z = 908.4 }

local attackerID, attackerDefID, targetID
local targetSpot, moveGoal
local startPos, triggerFrame, triggerPos, resultFrame
local maxTravel = 0
local minDistToTargetSpot = math.huge
local done = false

local function Dist2D(ax, az, bx, bz) return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) end

local function Standable(defID, x, z)
	return Spring.TestMoveOrder(defID, x, Spring.GetGroundHeight(x, z), z, 0, 0, 0, true, false, true)
end

-- walk back along the line from START towards (x, z) until a standable spot is found
local function StandableTowards(defID, x, z)
	local d = Dist2D(START.x, START.z, x, z)
	local dx, dz = (x - START.x) / d, (z - START.z) / d
	for back = 0, d - 64, 16 do
		local px, pz = x - dx * back, z - dz * back
		if Standable(defID, px, pz) then return px, pz end
	end
	error(("no standable spot towards %.0f,%.0f"):format(x, z))
end

local function Pos(u)
	local x, y, z = Spring.GetUnitPosition(u)
	return x, y, z
end

local function Diag(frame, tag)
	if not Spring.ValidUnitID(attackerID) then Echo("%s frame=%d attacker gone", tag, frame); return end
	local x, _, z = Pos(attackerID)
	local vx, _, vz = Spring.GetUnitVelocity(attackerID)
	local cmds = Spring.GetUnitCommands(attackerID, 3) or {}
	local q = {}
	for i, c in ipairs(cmds) do
		local p = {}
		for j, v in ipairs(c.params) do p[j] = ("%.0f"):format(v) end
		q[i] = ("%d[%s]"):format(c.id, table.concat(p, ","))
	end
	local mt = Spring.GetUnitMoveTypeData(attackerID) or {}
	Echo("%s frame=%d pos=%.1f,%.1f speed=%.2f queue=%d{%s} progress=%s waypoint=%.1f,%.1f%s%s",
		tag, frame, x, z, math.sqrt(vx ^ 2 + vz ^ 2), #cmds, table.concat(q, " "), tostring(mt.progressState),
		mt.currwaypointx or -1, mt.currwaypointz or -1,
		targetSpot and (" distToTargetSpot=%.1f"):format(Dist2D(x, z, targetSpot.x, targetSpot.z)) or "",
		moveGoal and (" distToMoveGoal=%.1f"):format(Dist2D(x, z, moveGoal.x, moveGoal.z)) or "")
end

local function Setup()
	for _, u in ipairs(Spring.GetAllUnits()) do Spring.DestroyUnit(u, false, true) end
	Spring.SetGlobalLos(0, true)
	Spring.SetGlobalLos(1, true)

	attackerDefID = UnitDefNames[opts.unit].id
	local targetDefID = UnitDefNames[opts.target].id
	assert(Standable(attackerDefID, START.x, START.z), "attacker start not standable")
	attackerID = Spring.CreateUnit(opts.unit, START.x, Spring.GetGroundHeight(START.x, START.z), START.z, "south", 0)
	assert(attackerID, "could not create attacker")
	startPos = { x = START.x, z = START.z }

	local tx, tz = StandableTowards(targetDefID, START.x, START.z + opts.dist)
	targetSpot = { x = tx, z = tz }
	if opts.variant ~= "remove" then
		targetID = Spring.CreateUnit(opts.target, tx, Spring.GetGroundHeight(tx, tz), tz, "north", 1)
		assert(targetID, "could not create target")
	end
	if opts.variant == "queued" then
		local mx, mz = StandableTowards(attackerDefID, START.x + 260, START.z + 180)
		moveGoal = { x = mx, z = mz }
	end
	Echo("SETUP variant=%s attacker=%s#%d at %.1f,%.1f target=%s%s at %.1f,%.1f dist=%.1f%s",
		opts.variant, opts.unit, attackerID, START.x, START.z, opts.target, targetID and ("#" .. targetID) or "(none)",
		tx, tz, Dist2D(START.x, START.z, tx, tz),
		moveGoal and (" moveGoal=%.1f,%.1f"):format(moveGoal.x, moveGoal.z) or "")
end

local function GiveOrders(frame)
	if opts.variant == "remove" then
		Spring.GiveOrderToUnit(attackerID, CMD.MOVE, { targetSpot.x, Spring.GetGroundHeight(targetSpot.x, targetSpot.z), targetSpot.z }, 0)
	else
		Spring.GiveOrderToUnit(attackerID, CMD.ATTACK, { targetID }, 0)
		if opts.variant == "queued" then
			Spring.GiveOrderToUnit(attackerID, CMD.MOVE, { moveGoal.x, Spring.GetGroundHeight(moveGoal.x, moveGoal.z), moveGoal.z }, CMD.OPT_SHIFT)
		end
	end
	Diag(frame, "ORDERS")
end

local function Trigger(frame)
	local x, _, z = Pos(attackerID)
	triggerFrame, triggerPos, resultFrame = frame, { x = x, z = z }, frame + RESULT_DELAY
	if opts.variant == "remove" then
		local front = (Spring.GetUnitCommands(attackerID, 1) or {})[1]
		assert(front, "no active command to remove")
		Spring.GiveOrderToUnit(attackerID, CMD.REMOVE, { front.tag }, 0)
		Echo("TRIGGER frame=%d removed active command id=%d tag=%d attackerPos=%.1f,%.1f", frame, front.id, front.tag, x, z)
	else
		Spring.DestroyUnit(targetID, false, false)
		Echo("TRIGGER frame=%d destroyed target #%d attackerPos=%.1f,%.1f distToTargetSpot=%.1f", frame, targetID, x, z, Dist2D(x, z, targetSpot.x, targetSpot.z))
	end
	Diag(frame, "TRIGGERED")
end

local function Result(frame)
	local x, _, z = Pos(attackerID)
	local vx, _, vz = Spring.GetUnitVelocity(attackerID)
	local speed = math.sqrt(vx ^ 2 + vz ^ 2)
	local queue = Spring.GetUnitCommandCount(attackerID)
	local travel = Dist2D(x, z, triggerPos.x, triggerPos.z)
	local distToTargetSpot = Dist2D(x, z, targetSpot.x, targetSpot.z)
	local verdict, why
	if opts.variant == "queued" then
		local distToMoveGoal = Dist2D(x, z, moveGoal.x, moveGoal.z)
		if distToMoveGoal <= ARRIVE_TOLERANCE and queue == 0 and minDistToTargetSpot > ARRIVE_TOLERANCE then
			verdict, why = "PASS", "went straight to the move goal"
		elseif distToMoveGoal <= ARRIVE_TOLERANCE and queue == 0 then
			verdict, why = "FAIL", ("detoured via the dead target's position (came within %.1f elmo of it)"):format(minDistToTargetSpot)
		else
			verdict, why = "FAIL", ("did not arrive at the move goal (dist %.1f, queue %d)"):format(distToMoveGoal, queue)
		end
	else
		if travel <= STOP_TOLERANCE and speed == 0 and queue == 0 then
			verdict, why = "PASS", "stopped where the order ended"
		elseif distToTargetSpot <= ARRIVE_TOLERANCE then
			verdict, why = "FAIL", "walked on to the removed order's goal with an empty queue"
		else
			verdict, why = "FAIL", "still moving or queue not empty"
		end
	end
	Echo("RESULT variant=%s verdict=%s reason=\"%s\" triggerFrame=%d travelAfterTrigger=%.1f maxTravel=%.1f speed=%.2f queue=%d distToTargetSpot=%.1f minDistToTargetSpot=%.1f pos=%.1f,%.1f",
		opts.variant, verdict, why, triggerFrame, travel, maxTravel, speed, queue, distToTargetSpot, minDistToTargetSpot, x, z)
	done = true
	SendToUnsynced("deadtarget_done")
end

function gadget:GameFrame(frame)
	if done then return end
	if frame == SETUP_FRAME then Setup(); return end
	if frame == ORDER_FRAME then GiveOrders(frame); return end
	if frame < ORDER_FRAME or not Spring.ValidUnitID(attackerID) then return end

	local x, _, z = Pos(attackerID)
	if not triggerFrame then
		if Dist2D(x, z, startPos.x, startPos.z) >= TRIGGER_DIST then
			Trigger(frame)
		elseif frame % 30 == 0 then
			Diag(frame, "DIAG")
		elseif frame > ORDER_FRAME + 900 then
			Echo("RESULT variant=%s verdict=ERROR reason=\"attacker never walked %d elmo\"", opts.variant, TRIGGER_DIST)
			done = true
			SendToUnsynced("deadtarget_done")
		end
		return
	end

	maxTravel = math.max(maxTravel, Dist2D(x, z, triggerPos.x, triggerPos.z))
	minDistToTargetSpot = math.min(minDistToTargetSpot, Dist2D(x, z, targetSpot.x, targetSpot.z))
	local since = frame - triggerFrame
	if since <= 60 and since % 5 == 0 or since % 30 == 0 then Diag(frame, "DIAG") end
	if frame >= resultFrame then Result(frame) end
end

function gadget:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	if unitID ~= attackerID then return end
	local p = {}
	for j, v in ipairs(cmdParams) do p[j] = ("%.0f"):format(v) end
	Diag(Spring.GetGameFrame(), ("CMDDONE id=%d params=[%s] tag=%d"):format(cmdID, table.concat(p, ","), cmdTag))
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if unitID == targetID then
		Echo("TARGET_DESTROYED frame=%d", Spring.GetGameFrame())
	end
end
