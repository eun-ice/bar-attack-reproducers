local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Corcom Tick Attack Stall Reproducer",
		desc = "Commander ordered to attack ticks stops short of its range and never fires (from replay 2026-09-05, All That Glitters)",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

-- Positions taken from the replay (frame 1511 / frame 2059 attack orders, engine 2026.07.04).
local scenarios = {
	-- first attack: commander still on its start position
	[1] = { x = 3452.0, z = 764.0, heading = 0 },
	-- second attack: commander after the player moved it back north
	[2] = { x = 3438.8, z = 682.7, heading = 31972 },
}
-- the three enemy ticks the area attack (center 3699,986 r=73 / r=131) resolved to
local tickSpots = {
	{ x = 3701.1, z = 987.7 },
	{ x = 3722.3, z = 976.2 },
	{ x = 3746.1, z = 983.8 },
}

local ATTACK_FRAME = 30
local RESULT_FRAME = ATTACK_FRAME + 600
local DIAG_PERIOD = 30

local opts = {}
local attackerID, attackerDefID, attackerWeaponDefID
local weaponRange
local tickIDs = {}
local primaryTarget
local projectilesCreated = 0
local startX, startZ
local minDist = math.huge

local function ModOpt(key, default)
	local v = Spring.GetModOptions()[key]
	if v == nil then return default end
	return v
end

local function Enabled()
	local v = ModOpt("corcomtickattackstall")
	return v == true or v == 1 or v == "1"
end

local function Dist2D(ax, az, bx, bz)
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

local function Echo(fmt, ...)
	Spring.Echo(("CORCOM_TICK_STALL_" .. fmt):format(...))
end

local function DestroyPreexistingUnits()
	for _, u in ipairs(Spring.GetAllUnits()) do
		Spring.DestroyUnit(u, false, true)
	end
end

local function CreateScenario()
	local sc = scenarios[tonumber(opts.scenario)] or scenarios[1]
	DestroyPreexistingUnits()
	Spring.SetGlobalLos(0, true)
	Spring.SetGlobalLos(1, true)

	local y = Spring.GetGroundHeight(sc.x, sc.z)
	attackerID = Spring.CreateUnit("corcom", sc.x, y, sc.z, "south", 0)
	assert(attackerID, "could not create corcom")
	local a = sc.heading * math.pi / 32768
	Spring.SetUnitDirection(attackerID, math.sin(a), 0, math.cos(a))
	Spring.GiveOrderToUnit(attackerID, CMD.FIRE_STATE, { tonumber(opts.firestate) }, 0)
	Spring.GiveOrderToUnit(attackerID, CMD.MOVE_STATE, { tonumber(opts.movestate) }, 0)

	attackerDefID = Spring.GetUnitDefID(attackerID)
	local ud = UnitDefs[attackerDefID]
	attackerWeaponDefID = ud.weapons[1].weaponDef
	weaponRange = WeaponDefs[attackerWeaponDefID].range
	Script.SetWatchProjectile(attackerWeaponDefID, true)
	startX, _, startZ = Spring.GetUnitPosition(attackerID)

	for i, t in ipairs(tickSpots) do
		local ty = Spring.GetGroundHeight(t.x, t.z)
		local id = Spring.CreateUnit("armflea", t.x, ty, t.z, "south", 1)
		assert(id, "could not create armflea")
		tickIDs[i] = id
	end
	-- SelectAttackNet order: nearest target first
	table.sort(tickIDs, function(a, b)
		local ax, _, az = Spring.GetUnitPosition(a)
		local bx, _, bz = Spring.GetUnitPosition(b)
		return Dist2D(ax, az, startX, startZ) < Dist2D(bx, bz, startX, startZ)
	end)
	primaryTarget = tickIDs[1]

	Echo("SCENARIO_READY scenario=%s order=%s firestate=%s movestate=%s attacker=%d pos=%.1f,%.1f,%.1f heading=%d range=%.0f liveRange=%s moveDef=%s",
		tostring(opts.scenario), opts.order, tostring(opts.firestate), tostring(opts.movestate), attackerID, startX, y, startZ,
		Spring.GetUnitHeading(attackerID), weaponRange, tostring(Spring.GetUnitWeaponState(attackerID, 1, "range")), tostring(ud.moveDef and ud.moveDef.name))
	Echo("MAXRANGE unitMaxRange=%s weapons=%d", tostring(Spring.GetUnitMaxRange(attackerID)), #ud.weapons)
	for i, w in ipairs(ud.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		Echo("WEAPON n=%d name=%s type=%s range=%.0f liveRange=%s turret=%s targetBorder=%s manualFire=%s cylinderTargeting=%s", i, wd.name, wd.type, wd.range,
			tostring(Spring.GetUnitWeaponState(attackerID, i, "range")), tostring(wd.turret), tostring(wd.targetBorder), tostring(wd.manualFire), tostring(wd.cylinderTargeting))
	end
	for i, id in ipairs(tickIDs) do
		local tx, ty, tz = Spring.GetUnitPosition(id)
		Echo("TICK n=%d id=%d pos=%.1f,%.1f,%.1f dist=%.1f", i, id, tx, ty, tz, Dist2D(tx, tz, startX, startZ))
	end

	-- terrain / pathability profile along the straight line to the primary target
	local tx, _, tz = Spring.GetUnitPosition(primaryTarget)
	local profile = {}
	for i = 0, 20 do
		local f = i / 20
		local px, pz = startX + (tx - startX) * f, startZ + (tz - startZ) * f
		local gh = Spring.GetGroundHeight(px, pz)
		local ok = Spring.TestMoveOrder(attackerDefID, px, gh, pz, 0, 0, 0, true, false, true)
		profile[#profile + 1] = ("%.0f%%:%.0f%s"):format(f * 100, gh, ok and "" or "X")
	end
	Echo("TERRAIN_PROFILE (percent:groundheight, X = corcom cannot stand there) %s", table.concat(profile, " "))

	-- (Spring.RequestPath from synced code segfaulted spring-headless 2026.07.04 here; use the move variant instead)
end

local function IssueOrder()
	local tx, ty, tz = Spring.GetUnitPosition(primaryTarget)
	if opts.order == "move" then
		Spring.GiveOrderToUnit(attackerID, CMD.MOVE, { tx, ty, tz }, 0)
	else
		-- what CSelectedUnitsHandlerAI::SelectAttackNet produces for an area attack
		for i, id in ipairs(tickIDs) do
			Spring.GiveOrderToUnit(attackerID, CMD.ATTACK, { id }, i == 1 and 0 or CMD.OPT_SHIFT)
		end
	end
	Echo("ORDER_ISSUED order=%s target=%d", opts.order, primaryTarget)
end

local function Diag(frame, tag)
	if not Spring.ValidUnitID(attackerID) then Echo("%s attacker gone", tag); return end
	local x, y, z = Spring.GetUnitPosition(attackerID)
	local vx, _, vz = Spring.GetUnitVelocity(attackerID)
	local mt = Spring.GetUnitMoveTypeData(attackerID) or {}
	local cmd = (Spring.GetUnitCommands(attackerID, 1) or {})[1]
	local tx, _, tz = Spring.GetUnitPosition(primaryTarget)
	local dist = Dist2D(x, z, tx, tz)
	if dist < minDist then minDist = dist end
	local testRange = Spring.GetUnitWeaponTestRange(attackerID, 1, primaryTarget)
	local tryTarget = Spring.GetUnitWeaponTryTarget(attackerID, 1, primaryTarget)
	local lof = Spring.GetUnitWeaponHaveFreeLineOfFire(attackerID, 1, primaryTarget)
	if frame % DIAG_PERIOD == 0 then
		local parts = { ("heading=%d"):format(Spring.GetUnitHeading(attackerID)) }
		for w = 1, 3 do
			local wtype, _, wtgt = Spring.GetUnitWeaponTarget(attackerID, w)
			local mx, my, mz = Spring.GetUnitWeaponVectors(attackerID, w)
			parts[#parts + 1] = ("w%d[test=%s range=%s try=%s lof=%s tgtType=%s tgt=%s muzzle=%.1f,%.1f,%.1f]"):format(w,
				tostring(Spring.GetUnitWeaponTestTarget(attackerID, w, primaryTarget)), tostring(Spring.GetUnitWeaponTestRange(attackerID, w, primaryTarget)),
				tostring(Spring.GetUnitWeaponTryTarget(attackerID, w, primaryTarget)), tostring(Spring.GetUnitWeaponHaveFreeLineOfFire(attackerID, w, primaryTarget)),
				tostring(wtype), tostring(wtgt), mx or -1, my or -1, mz or -1)
		end
		Echo("WEAPONS frame=%d %s", frame, table.concat(parts, " "))
	end
	Echo("%s frame=%d pos=%.1f,%.1f,%.1f speed=%.2f progress=%s goal=%.1f,%.1f goalRadius=%.1f waypoint=%.1f,%.1f cmd=%s distToTarget=%.1f range=%.0f testRange=%s tryTarget=%s lof=%s projectiles=%d",
		tag, frame, x, y, z, math.sqrt(vx ^ 2 + vz ^ 2), tostring(mt.progressState), mt.goalx or -1, mt.goalz or -1, mt.goalRadius or -1,
		mt.currwaypointx or -1, mt.currwaypointz or -1,
		cmd and (tostring(cmd.id) .. "[" .. table.concat(cmd.params, ",") .. "]") or "none",
		dist, weaponRange, tostring(testRange), tostring(tryTarget), tostring(lof), projectilesCreated)
end

local function Result(frame)
	local x, _, z = Spring.GetUnitPosition(attackerID)
	local vx, _, vz = Spring.GetUnitVelocity(attackerID)
	local mt = Spring.GetUnitMoveTypeData(attackerID) or {}
	local cmd = (Spring.GetUnitCommands(attackerID, 1) or {})[1]
	local tx, _, tz = Spring.GetUnitPosition(primaryTarget)
	local dist = Dist2D(x, z, tx, tz)
	local stalled = cmd ~= nil and cmd.id == CMD.ATTACK and cmd.params[1] == primaryTarget
		and math.sqrt(vx ^ 2 + vz ^ 2) < 0.01 and mt.progressState ~= "active"
		and dist > weaponRange and projectilesCreated == 0
	Echo("RESULT stalled=%s order=%s scenario=%s frame=%d moved=%.1f distToTarget=%.1f minDistToTarget=%.1f range=%.0f progress=%s cmd=%s projectiles=%d targetAlive=%s",
		tostring(stalled), opts.order, tostring(opts.scenario), frame, Dist2D(x, z, startX, startZ), dist, minDist, weaponRange,
		tostring(mt.progressState), cmd and tostring(cmd.id) or "none", projectilesCreated, tostring(Spring.ValidUnitID(primaryTarget)))
end

function gadget:Initialize()
	if not Enabled() then
		gadgetHandler:RemoveGadget(self)
		return
	end
	opts.scenario = ModOpt("corcomtickattackstallscenario", 1)
	opts.order = tostring(ModOpt("corcomtickattackstallorder", "attack"))
	opts.firestate = ModOpt("corcomtickattackstallfirestate", 0)
	opts.movestate = ModOpt("corcomtickattackstallmovestate", 0)
end

function gadget:GameFrame(frame)
	if frame == 1 then
		CreateScenario()
	elseif frame == ATTACK_FRAME then
		IssueOrder()
	elseif frame == RESULT_FRAME then
		Diag(frame, "DIAG")
		Result(frame)
	elseif frame > ATTACK_FRAME and frame < RESULT_FRAME and (frame % DIAG_PERIOD == 0 or frame <= ATTACK_FRAME + 100) then
		Diag(frame, "DIAG")
	end
end

function gadget:ProjectileCreated(_, ownerID, weaponDefID)
	if ownerID == attackerID and weaponDefID == attackerWeaponDefID then
		projectilesCreated = projectilesCreated + 1
	end
end

-- log every command anything (engine net, Lua) gives to the attacker
function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua, fromInsert)
	if unitID == attackerID then
		Echo("ALLOWCOMMAND frame=%d cmd=%d params=%s fromLua=%s fromSynced=%s shift=%s", Spring.GetGameFrame(), cmdID,
			table.concat(cmdParams, ","), tostring(fromLua), tostring(fromSynced), tostring(cmdOptions.shift))
	end
	return true
end

function gadget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag, playerID, fromSynced, fromLua)
	if unitID == attackerID then
		Echo("UNITCOMMAND frame=%d cmd=%d params=%s fromLua=%s", Spring.GetGameFrame(), cmdID, table.concat(cmdParams, ","), tostring(fromLua))
	end
end

function gadget:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	if unitID == attackerID then
		Echo("UNITCMDDONE frame=%d cmd=%d params=%s", Spring.GetGameFrame(), cmdID, table.concat(cmdParams, ","))
	end
end

function gadget:UnitDestroyed(unitID)
	if unitID == primaryTarget then
		Echo("TARGET_DESTROYED frame=%d projectiles=%d", Spring.GetGameFrame(), projectilesCreated)
	end
end
