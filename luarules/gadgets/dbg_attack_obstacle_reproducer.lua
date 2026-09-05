local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Attack Obstacle Reproducer",
		desc = "Reproduces stalled Sheldon attacks for RecoilEngine #3242 (rock and friendly-line scenarios)",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

-- modoptions:
--   attackobstaclereproducer=1        enable
--   attackobstaclescenario=rock       (default) five Sheldons behind a rock, All That Glitters v2.2.3
--   attackobstaclescenario=friendlyline  five Sheldons in a column on flat ground, Quicksilver Remake 1.24
--   attackobstaclemovestate=0|1|2     move state of the attackers (default 1 = maneuver)

local rockUnits = {
	{ "cormort", 687.921, 237.938, 2223.893, 0 },
	{ "cormort", 669.510, 228.387, 2204.495, 0 },
	{ "cormort", 685.108, 225.179, 2180.946, 0 },
	{ "cormort", 662.220, 225.105, 2171.320, 0 },
	{ "cormort", 698.160, 226.486, 2201.629, 0 },
	{ "armfboy", 707.070, 224.542, 2649.709, 1 },
	{ "armfboy", 934.079, 220.462, 2902.515, 1 },
	{ "armfboy", 822.687, 220.551, 2791.332, 1 },
	{ "armfboy", 1138.442, 218.324, 3042.212, 1 },
	{ "armflea", 866.013, 221.709, 2611.074, 1 },
	{ "armflea", 718.753, 225.932, 2606.819, 1 },
	{ "armflea", 655.294, 243.879, 2625.215, 1 },
	{ "armflea", 989.432, 220.519, 2703.996, 1 },
	{ "armflea", 1012.585, 220.619, 2614.458, 1 },
	{ "armflea", 1157.433, 220.462, 2612.061, 1 },
	{ "armflea", 919.839, 220.635, 2708.947, 1 },
	{ "armflea", 1185.007, 220.441, 2715.322, 1 },
	{ "armflea", 1053.609, 220.462, 2706.715, 1 },
	{ "armflea", 1122.463, 220.422, 2717.727, 1 },
}

-- friendly line: attackers in a column, spacing in elmos, target this far ahead
local LINE_SPACING = 26
local LINE_TARGET_DIST = 600
local LINE_FLAT_TOLERANCE = 3

local units
local attackers = {}
local startPositions = {}
local targetHits = {}
local otherHits = {}
local firstTargetHitPositions = {}
local latePositions = {}
local targetID
local targetExpected = { 707.070, 2649.709 }

local function Option(name)
	return Spring.GetModOptions()[name]
end

local function ReproducerEnabled()
	local value = Option("attackobstaclereproducer")
	return value == true or value == 1 or value == "1"
end

local function Scenario()
	return tostring(Option("attackobstaclescenario") or "rock")
end

local function MoveState()
	return tonumber(Option("attackobstaclemovestate")) or 1
end

-- search the map for a north-south column of flat land long enough for the line scenario
local function FindFlatColumn(halfWidth, length)
	halfWidth = halfWidth or 32
	length = length or (LINE_TARGET_DIST + 5 * LINE_SPACING + 64)
	local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
	for x = 256, mapX - 256, 64 do
		for z0 = 256, mapZ - 256 - length, 64 do
			local hMin, hMax = math.huge, -math.huge
			local ok = true
			for d = -32, length + 32, 16 do
				for dx = -halfWidth, halfWidth, 16 do
					local h = Spring.GetGroundHeight(x + dx, z0 + d)
					if h < 8 then
						ok = false
						break
					end
					hMin = math.min(hMin, h)
					hMax = math.max(hMax, h)
				end
				if not ok or (hMax - hMin) > LINE_FLAT_TOLERANCE then
					ok = false
					break
				end
			end
			if ok then
				return x, z0
			end
		end
	end
	return nil
end

local function BuildLineUnits()
	local x, z0 = FindFlatColumn()
	assert(x, "Attack obstacle reproducer found no flat column for the friendly-line scenario")
	local list = {}
	-- attackobstaclelineunit / attackobstaclelinespacing: which unit stands in the column and how densely
	local unitName = tostring(Option("attackobstaclelineunit") or "cormort")
	LINE_SPACING = tonumber(Option("attackobstaclelinespacing")) or LINE_SPACING
	-- rearmost attacker first; the column faces south towards the target
	for i = 0, 4 do
		local z = z0 + i * LINE_SPACING
		list[#list + 1] = { unitName, x, Spring.GetGroundHeight(x, z), z, 0 }
	end
	-- the target may sit off the column axis (attackobstaclelineoffset, elmos in x) so that the
	-- line of fire from an off-centre muzzle still runs through the unit in front
	local tx = x + (tonumber(Option("attackobstaclelineoffset")) or 0)
	local tz = z0 + 4 * LINE_SPACING + LINE_TARGET_DIST
	assert(Spring.GetGroundHeight(tx, tz) > 8, "Attack obstacle reproducer: friendly-line target spot is in water")
	list[#list + 1] = { "armfboy", tx, Spring.GetGroundHeight(tx, tz), tz, 1 }
	targetExpected = { tx, tz }
	Spring.Echo(("ATTACK_OBSTACLE_LINE column x=%.0f z=%.0f..%.0f target=%.0f,%.0f"):format(x, z0, z0 + 4 * LINE_SPACING, tx, tz))
	return list
end

-- wall: a row of five shooters behind a row of allied blockers (attackobstaclewallunit, mobile or
-- immobile), target straight ahead; shooters blocked by mobile allies must wait, shooters blocked
-- by structures must walk around them
local WALL_SHOOTER_SPACING = 40
local WALL_BLOCKER_SPACING = 32
local WALL_BLOCKER_DIST = 80
local WALL_TARGET_DIST = 450
local shooterName = "cormort"

local function BuildWallUnits()
	local blockerName = tostring(Option("attackobstaclewallunit") or "armbanth")
	local x, z0 = FindFlatColumn(112, WALL_BLOCKER_DIST + WALL_TARGET_DIST + 64)
	assert(x, "Attack obstacle reproducer found no flat area for the wall scenario")
	local list = {}
	for i = -2, 2 do
		list[#list + 1] = { shooterName, x + i * WALL_SHOOTER_SPACING, Spring.GetGroundHeight(x + i * WALL_SHOOTER_SPACING, z0), z0, 0 }
	end
	local zb = z0 + WALL_BLOCKER_DIST
	for j = -3, 3 do
		list[#list + 1] = { blockerName, x + j * WALL_BLOCKER_SPACING, Spring.GetGroundHeight(x + j * WALL_BLOCKER_SPACING, zb), zb, 0 }
	end
	local tz = zb + WALL_TARGET_DIST
	list[#list + 1] = { "armfboy", x, Spring.GetGroundHeight(x, tz), tz, 1 }
	targetExpected = { x, tz }
	Spring.Echo(("ATTACK_OBSTACLE_WALL x=%.0f shooters z=%.0f blockers=%s z=%.0f target z=%.0f"):format(x, z0, blockerName, zb, tz))
	return list
end

local function FindTarget()
	local targets = Spring.GetTeamUnitsByDefs(1, UnitDefNames.armfboy.id)
	local bestDistance

	for _, candidateID in ipairs(targets) do
		local x, _, z = Spring.GetUnitPosition(candidateID)
		local distance = (targetExpected[1] - x) ^ 2 + (targetExpected[2] - z) ^ 2
		if not bestDistance or distance < bestDistance then
			targetID = candidateID
			bestDistance = distance
		end
	end
end

local function CreateScenario()
	if Scenario() == "friendlyline" then
		units = BuildLineUnits()
		shooterName = tostring(Option("attackobstaclelineunit") or "cormort")
	elseif Scenario() == "wall" then
		units = BuildWallUnits()
	else
		units = rockUnits
	end
	-- tell the camera widget where the action is: centre and extent of all created units
	local xMin, xMax, zMin, zMax = math.huge, -math.huge, math.huge, -math.huge
	for _, unit in ipairs(units) do
		xMin, xMax = math.min(xMin, unit[2]), math.max(xMax, unit[2])
		zMin, zMax = math.min(zMin, unit[4]), math.max(zMax, unit[4])
	end
	Spring.SetGameRulesParam("attackobstacle_cx", (xMin + xMax) / 2)
	Spring.SetGameRulesParam("attackobstacle_cz", (zMin + zMax) / 2)
	Spring.SetGameRulesParam("attackobstacle_extent", math.max(xMax - xMin, zMax - zMin))

	for _, unit in ipairs(units) do
		local name, x, y, z, teamID = unpack(unit)
		local unitID = Spring.CreateUnit(name, x, y, z, "south", teamID)
		if unitID then
			Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { 0 }, 0)
			Spring.GiveOrderToUnit(unitID, CMD.MOVE_STATE, { 0 }, 0)
			if name ~= shooterName and teamID == 0 then
				Spring.Echo(("ATTACK_OBSTACLE_BLOCKER %s id=%d height=%.1f"):format(name, unitID, Spring.GetUnitHeight(unitID) or -1))
			end
		end
	end
	Spring.Echo("ATTACK_OBSTACLE_SCENARIO_READY scenario=" .. Scenario() .. " movestate=" .. MoveState() .. " units=" .. #units)
end

local function StartValidation()
	Spring.SetGlobalLos(0, true)
	attackers = Spring.GetTeamUnitsByDefs(0, UnitDefNames[shooterName].id)
	table.sort(attackers)
	FindTarget()
	assert(targetID, "Attack obstacle reproducer could not find its Fatboy target")

	for _, attackerID in ipairs(attackers) do
		local x, _, z = Spring.GetUnitPosition(attackerID)
		startPositions[attackerID] = { x, z, Spring.GetUnitHeading(attackerID) }
		targetHits[attackerID] = 0
		otherHits[attackerID] = 0
		Spring.GiveOrderToUnit(attackerID, CMD.FIRE_STATE, { 2 }, 0)
		Spring.GiveOrderToUnit(attackerID, CMD.MOVE_STATE, { MoveState() }, 0)
		Spring.GiveOrderToUnit(attackerID, CMD.ATTACK, { targetID }, 0)
	end

	Spring.Echo("ATTACK_OBSTACLE_VALIDATION_START attackers=" .. #attackers .. " target=" .. targetID)
end

local function ReportResults()
	local tx, _, tz = Spring.GetUnitPosition(targetID)
	for _, attackerID in ipairs(attackers) do
		local x, _, z = Spring.GetUnitPosition(attackerID)
		local start = startPositions[attackerID]
		local moved = math.sqrt((x - start[1]) ^ 2 + (z - start[2]) ^ 2)
		local targetVectorX = tx - start[1]
		local targetVectorZ = tz - start[2]
		local initialTargetDistance = math.sqrt(targetVectorX ^ 2 + targetVectorZ ^ 2)
		local movedX = x - start[1]
		local movedZ = z - start[2]
		local forwardMoved = (movedX * targetVectorX + movedZ * targetVectorZ) / initialTargetDistance
		local lateralMoved = math.abs(movedX * targetVectorZ - movedZ * targetVectorX) / initialTargetDistance
		local firstHitPosition = firstTargetHitPositions[attackerID]
		local movedAfterFirstHit = firstHitPosition
				and math.sqrt((x - firstHitPosition[1]) ^ 2 + (z - firstHitPosition[2]) ^ 2)
			or -1
		local latePosition = latePositions[attackerID]
		local movedLast60Frames = math.sqrt((x - latePosition[1]) ^ 2 + (z - latePosition[2]) ^ 2)
		local distToTarget = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
		local commandID, _, _, commandTarget = Spring.GetUnitCurrentCommand(attackerID)
		local heading = Spring.GetUnitHeading(attackerID)

		Spring.Echo(
			("ATTACK_OBSTACLE_RESULT scenario=%s movestate=%d attacker=%d target=%d targetHits=%d otherHits=%d moved=%.1f forward=%.1f lateral=%.1f movedAfterFirstHit=%.1f movedLast60Frames=%.1f distToTarget=%.1f start=%.1f,%.1f end=%.1f,%.1f heading=%d->%d targetPos=%.1f,%.1f command=%s commandTarget=%s"):format(
				Scenario(),
				MoveState(),
				attackerID,
				targetID,
				targetHits[attackerID],
				otherHits[attackerID],
				moved,
				forwardMoved,
				lateralMoved,
				movedAfterFirstHit,
				movedLast60Frames,
				distToTarget,
				start[1],
				start[2],
				x,
				z,
				start[3],
				heading,
				tx,
				tz,
				tostring(commandID),
				tostring(commandTarget)
			)
		)
	end
end

-- what the weapon and the CommandAI currently think, per attacker
local function ReportDiagnostics(frame)
	local tx, ty, tz = Spring.GetUnitPosition(targetID)
	for _, attackerID in ipairs(attackers) do
		local x, _, z = Spring.GetUnitPosition(attackerID)
		local mx, my, mz = Spring.GetUnitWeaponVectors(attackerID, 1)
		local tryTarget = Spring.GetUnitWeaponTryTarget(attackerID, 1, targetID)
		local lofAim = Spring.GetUnitWeaponHaveFreeLineOfFire(attackerID, 1, targetID)
		local lofMuzzle = mx and Spring.GetUnitWeaponHaveFreeLineOfFire(attackerID, 1, mx, my, mz, targetID)
		local canFire = Spring.GetUnitWeaponCanFire(attackerID, 1)
		local wtType = Spring.GetUnitWeaponTarget(attackerID, 1)
		local mt = Spring.GetUnitMoveTypeData(attackerID) or {}
		local _, _, _, speed = Spring.GetUnitVelocity(attackerID)
		local muzzleAboveGround = mx and (my - Spring.GetGroundHeight(mx, mz)) or 0
		Spring.Echo(
			("ATTACK_OBSTACLE_DIAG frame=%d attacker=%d dist=%.1f tryTarget=%s lofAim=%s lofMuzzle=%s canFire=%s weaponTargetType=%s progress=%s speed=%.2f muzzleAboveGround=%.1f hits=%d"):format(
				frame, attackerID, math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2), tostring(tryTarget), tostring(lofAim), tostring(lofMuzzle),
				tostring(canFire), tostring(wtType), tostring(mt.progressState), speed or 0, muzzleAboveGround, targetHits[attackerID] or 0
			)
		)
	end
end

function gadget:Initialize()
	if not ReproducerEnabled() then
		gadgetHandler:RemoveGadget(self)
	end
end

function gadget:GameFrame(frame)
	if frame == 1 then
		CreateScenario()
	elseif frame == 120 then
		StartValidation()
	elseif frame == 740 then
		for _, attackerID in ipairs(attackers) do
			local x, _, z = Spring.GetUnitPosition(attackerID)
			latePositions[attackerID] = { x, z }
		end
	elseif frame == 800 then
		ReportResults()
	elseif frame == 820 then
		Spring.GameOver({ 0 })
	end
	if frame >= 200 and frame <= 700 and frame % 100 == 0 then
		ReportDiagnostics(frame)
	end
end

function gadget:UnitDamaged(unitID, _, _, _, _, _, _, attackerID)
	if targetHits[attackerID] == nil then
		return
	end

	if unitID == targetID then
		targetHits[attackerID] = targetHits[attackerID] + 1
		if not firstTargetHitPositions[attackerID] then
			local x, _, z = Spring.GetUnitPosition(attackerID)
			firstTargetHitPositions[attackerID] = { x, z }
		end
	else
		otherHits[attackerID] = otherHits[attackerID] + 1
	end
end

function gadget:UnitPreDamaged(unitID, _, _, damage)
	if unitID == targetID then
		return math.min(damage, 1), 0
	end

	return damage, 1
end
