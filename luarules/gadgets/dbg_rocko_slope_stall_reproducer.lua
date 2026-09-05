local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Rocko Slope Stall Reproducer",
		desc = "Rocko on a ridge attacking a ground point down the slope; RecoilEngine #3242 variant with a plain attack command",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

-- modoptions:
--   rockoslopestallreproducer=1   enable
--   rockoslopeattack=1            phase 1 is a plain CMD.ATTACK on the point instead of a sticky Set Target
--   rockoslopemovestate=0|1|2     move state of the Rocko (default 1 = maneuver)

-- Quicksilver Remake 1.24: ridge at 194 elmo, target 104 elmo lower and 320 elmo away
local spawnX, spawnZ = 5024.0, 3264.0
local spawnDirection = { -0.704, 0.0, 0.710 }
local target = { 4746.9, 89.6, 3424.0 }

-- frames of the scripted sequence
local FRAME_SET_TARGET = 30
local FRAME_GROUND_ATTACK = 600
local FRAME_STOP = 780
local FRAME_END = 1500

local attackerID
local attackerWeaponDefID
local raisePoint
local phase = "setup"
local projectiles = { settarget = 0, groundattack = 0, afterstop = 0 }
local startX, startZ

local function Option(name)
	local value = Spring.GetModOptions()[name]
	return value == true or value == 1 or value == "1"
end

local function MoveState()
	return tonumber(Spring.GetModOptions().rockoslopemovestate) or 1
end

-- a ground point at long range that is level with the ridge, so aiming at it lifts the arm
local function FindRaisePoint(spawnY)
	local best
	for deg = 0, 345, 15 do
		local a = math.rad(deg)
		local x, z = spawnX + math.sin(a) * 400, spawnZ + math.cos(a) * 400
		local y = Spring.GetGroundHeight(x, z)
		if y > 2 and (not best or math.abs(y - spawnY) < math.abs(best[2] - spawnY)) then
			best = { x, y, z }
		end
	end
	return best
end

local function CreateScenario()
	Spring.SetGlobalLos(0, true)

	local spawnY = Spring.GetGroundHeight(spawnX, spawnZ)
	attackerID = Spring.CreateUnit("armrock", spawnX, spawnY, spawnZ, "south", 0)
	assert(attackerID, "Rocko slope stall reproducer could not create armrock")
	Spring.SetUnitDirection(attackerID, spawnDirection[1], spawnDirection[2], spawnDirection[3])
	Spring.GiveOrderToUnit(attackerID, CMD.FIRE_STATE, { 2 }, 0)
	Spring.GiveOrderToUnit(attackerID, CMD.MOVE_STATE, { MoveState() }, 0)

	raisePoint = FindRaisePoint(spawnY)
	attackerWeaponDefID = UnitDefs[Spring.GetUnitDefID(attackerID)].weapons[1].weaponDef
	Script.SetWatchProjectile(attackerWeaponDefID, true)
	startX, _, startZ = Spring.GetUnitPosition(attackerID)
	Spring.Echo(("ROCKO_SLOPE_STALL_SCENARIO_READY attacker=%d target=%.1f,%.1f,%.1f raisePoint=%.1f,%.1f,%.1f attack=%s movestate=%d"):format(
		attackerID, target[1], target[2], target[3], raisePoint[1], raisePoint[2], raisePoint[3], tostring(Option("rockoslopeattack")), MoveState()))
end

local function ReportResult(frame)
	local x, _, z = Spring.GetUnitPosition(attackerID)
	local moved = math.sqrt((x - startX) ^ 2 + (z - startZ) ^ 2)
	local current = (Spring.GetUnitCommands(attackerID, 1) or {})[1]
	local weaponTargetType, _, weaponTarget = Spring.GetUnitWeaponTarget(attackerID, 1)
	local weaponTargetStr = "-"
	if weaponTargetType == 2 and type(weaponTarget) == "table" then
		weaponTargetStr = ("%.0f,%.0f,%.0f"):format(weaponTarget[1], weaponTarget[2], weaponTarget[3])
	elseif weaponTargetType == 1 then
		weaponTargetStr = "unit" .. tostring(weaponTarget)
	end
	local mx, my, mz = Spring.GetUnitWeaponVectors(attackerID, 1)
	local muzzleLOF = Spring.GetUnitWeaponHaveFreeLineOfFire(attackerID, 1, mx, my, mz, target[1], target[2], target[3])
	local distToTarget = math.sqrt((target[1] - x) ^ 2 + (target[3] - z) ^ 2)

	Spring.Echo(
		("ROCKO_SLOPE_STALL_RESULT frame=%d phase=%s projectiles=%d/%d/%d command=%s moved=%.1f distToTarget=%.1f weaponTarget=%s muzzle=%.1f,%.1f,%.1f muzzleLOFtoSetTarget=%s"):format(
			frame, phase, projectiles.settarget, projectiles.groundattack, projectiles.afterstop, tostring(current and current.id), moved, distToTarget,
			weaponTargetStr, mx or 0, my or 0, mz or 0, tostring(muzzleLOF)
		)
	)
end

function gadget:Initialize()
	if not Option("rockoslopestallreproducer") then
		gadgetHandler:RemoveGadget(self)
	end
end

function gadget:GameFrame(frame)
	if frame == 1 then
		CreateScenario()
	elseif frame == FRAME_SET_TARGET then
		phase = "settarget"
		if Option("rockoslopeattack") then
			-- plain ground attack on the point below the crest; the CommandAI may reposition
			Spring.GiveOrderToUnit(attackerID, CMD.ATTACK, target, 0)
			Spring.Echo("ROCKO_SLOPE_STALL_ATTACK")
		else
			-- sticky Set Target on the ground below (S + Ctrl-click): survives STOP
			Spring.GiveOrderToUnit(attackerID, GameCMD.UNIT_SET_TARGET, target, { "ctrl" })
			Spring.Echo("ROCKO_SLOPE_STALL_SET_TARGET")
		end
	elseif frame == FRAME_GROUND_ATTACK then
		-- ground attack at a level point far away: the arm comes up
		phase = "groundattack"
		Spring.GiveOrderToUnit(attackerID, CMD.ATTACK, raisePoint, 0)
		Spring.Echo("ROCKO_SLOPE_STALL_GROUND_ATTACK")
	elseif frame == FRAME_STOP then
		-- stop the attack; a sticky set target remains and the bot now shoots it
		phase = "afterstop"
		Spring.GiveOrderToUnit(attackerID, CMD.STOP, {}, 0)
		Spring.Echo("ROCKO_SLOPE_STALL_STOP")
	end
	if frame >= 120 and frame <= FRAME_END and frame % 120 == 0 then
		ReportResult(frame)
	end
end

function gadget:ProjectileCreated(_, ownerID, weaponDefID)
	if ownerID == attackerID and weaponDefID == attackerWeaponDefID and projectiles[phase] then
		projectiles[phase] = projectiles[phase] + 1
	end
end
