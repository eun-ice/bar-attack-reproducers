local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Missile Cruiser Geo Reproducer",
		desc = "Four cormship ground-attacking an advanced geo on the Supreme Isthmus plateau (replay 2835b469, 31:31)",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

-- Replay 2835b469b0fd6def46f281c6fd5e7ed5, player [Crd]gunseng, frames 56751-59225.
-- The recorded orders were ground CMD.ATTACK at these coordinates; the map's
-- geovent feature is at (10420, 6800) and the plateau there is ~304 elmo high.
local geoVent = { x = 10420, z = 6800 }
local attackPoint = { 10416.8, 304.1, 6813.2 }
-- Ship spawn positions are estimated (the command stream does not carry unit
-- positions): a north-south line in the deep water south-west of the plateau,
-- 1396-1630 elmo from the geo. On engine 2025.06.19 ships closer than ~1330
-- elmo can still lob rockets 305 elmo up onto the plateau; from ~1395 elmo on
-- they neither fire nor close in.
local shipLayouts = {
	-- far: 1396-1630 elmo from the geo, every ship stalls on stock
	far = {
		{ x = 9200, z = 7480 },
		{ x = 9210, z = 7600 },
		{ x = 9220, z = 7720 },
		{ x = 9170, z = 7850 },
	},
	-- close: 1268/1327/1395/1441 elmo, the two nearest ships can lob onto the plateau on stock,
	-- the two farthest sit in range without a solution (mshipgeolayout=close)
	close = {
		{ x = 9330, z = 7450 },
		{ x = 9340, z = 7570 },
		{ x = 9350, z = 7690 },
		{ x = 9365, z = 7785 },
	},
}
local shipSpawns = shipLayouts[tostring(Spring.GetModOptions().mshipgeolayout or "far")] or shipLayouts.far

local attackerTeam = 0
local targetTeam = 1

local ships = {}
local shipSet = {}
local geoID
local geoPos = {}
local geoDeadFrame
local rocketWeaponDefID
local projectiles = {}
local startPos = {}

local function Enabled()
	local value = Spring.GetModOptions().mshipgeoreproducer
	return value == true or value == 1 or value == "1"
end

local function Option(name)
	return Spring.GetModOptions()[name]
end

local function CreateScenario()
	Spring.SetGlobalLos(0, true)
	Spring.SetGlobalLos(1, true)

	-- remove the start-position commanders so only the scenario units exist
	for _, id in ipairs(Spring.GetAllUnits()) do
		Spring.DestroyUnit(id, false, true)
	end

	local geoDefID = UnitDefNames.corageo.id
	local gx, gy, gz = Spring.Pos2BuildPos(geoDefID, geoVent.x, Spring.GetGroundHeight(geoVent.x, geoVent.z), geoVent.z)
	geoID = Spring.CreateUnit("corageo", gx, gy, gz, "south", targetTeam)
	assert(geoID, "could not create corageo")
	Spring.SetUnitNeutral(geoID, false)
	geoPos = { gx, gy, gz }

	local shipDef = UnitDefs[UnitDefNames.cormship.id]
	rocketWeaponDefID = shipDef.weapons[1].weaponDef
	Script.SetWatchProjectile(rocketWeaponDefID, true)

	for i, spawn in ipairs(shipSpawns) do
		local y = Spring.GetGroundHeight(spawn.x, spawn.z)
		local id = Spring.CreateUnit("cormship", spawn.x, math.max(y, 0), spawn.z, "east", attackerTeam)
		assert(id, "could not create cormship " .. i)
		Spring.GiveOrderToUnit(id, CMD.FIRE_STATE, { 2 }, 0)
		Spring.GiveOrderToUnit(id, CMD.MOVE_STATE, { 1 }, 0)
		ships[i] = id
		shipSet[id] = i
		projectiles[id] = 0
		local x, _, z = Spring.GetUnitPosition(id)
		startPos[id] = { x, z }
	end

	Spring.Echo(("MSHIP_GEO_SCENARIO_READY geo=%d geoPos=%.1f,%.1f,%.1f ships=%s"):format(
		geoID, gx, gy, gz, table.concat(ships, ",")))
end

local function IssueAttack()
	local mode = Option("mshipgeoattackmode") or "ground"
	local params
	if mode == "unit" then
		params = { geoID }
	else
		params = { attackPoint[1], Spring.GetGroundHeight(attackPoint[1], attackPoint[3]), attackPoint[3] }
	end
	Spring.GiveOrderToUnitArray(ships, CMD.ATTACK, params, 0)
	Spring.Echo(("MSHIP_GEO_ATTACK_ISSUED mode=%s params=%s"):format(mode, table.concat(params, ",")))
end

local function Report(frame)
	local gx, gy, gz = geoPos[1], geoPos[2], geoPos[3]
	local alive = Spring.ValidUnitID(geoID) and not Spring.GetUnitIsDead(geoID)
	local geoHealth = alive and (Spring.GetUnitHealth(geoID) or -1) or -1
	for i, id in ipairs(ships) do
		if Spring.ValidUnitID(id) then
			local x, y, z = Spring.GetUnitPosition(id)
			local vx, _, vz = Spring.GetUnitVelocity(id)
			local dist = math.sqrt((x - gx) ^ 2 + (z - gz) ^ 2)
			local moved = math.sqrt((x - startPos[id][1]) ^ 2 + (z - startPos[id][2]) ^ 2)
			local cmds = Spring.GetUnitCommands(id, 3) or {}
			local q = {}
			for j, c in ipairs(cmds) do
				local p = {}
				for k, v in ipairs(c.params) do p[k] = string.format("%.0f", v) end
				q[j] = string.format("%d[%s]", c.id, table.concat(p, ","))
			end
			local mt = Spring.GetUnitMoveTypeData(id) or {}
			local tType, isUser, tgt = Spring.GetUnitWeaponTarget(id, 1)
			local tstr = tostring(tType)
			if tType == 1 then
				tstr = "unit:" .. tostring(tgt)
			elseif tType == 2 and type(tgt) == "table" then
				tstr = string.format("ground:%.0f,%.0f,%.0f", tgt[1], tgt[2], tgt[3])
			end
			local cur = cmds[1]
			local testRange, tryTarget
			if cur and cur.id == CMD.ATTACK then
				if #cur.params == 1 then
					testRange = Spring.GetUnitWeaponTestRange(id, 1, cur.params[1])
					tryTarget = Spring.GetUnitWeaponTryTarget(id, 1, cur.params[1])
				elseif #cur.params >= 3 then
					testRange = Spring.GetUnitWeaponTestRange(id, 1, cur.params[1], cur.params[2], cur.params[3])
					tryTarget = Spring.GetUnitWeaponTryTarget(id, 1, cur.params[1], cur.params[2], cur.params[3])
				end
			end
			local canFire = Spring.GetUnitWeaponCanFire(id, 1)
			local reload = Spring.GetUnitWeaponState(id, 1, "reloadFrame")
			local range = Spring.GetUnitWeaponState(id, 1, "range")
			Spring.Echo(("MSHIP_GEO_RESULT frame=%d ship=%d idx=%d pos=%.1f,%.1f,%.1f speed=%.2f dist2d=%.0f range=%s moved=%.0f moveState=%s queue=%s weaponTarget=%s testRange=%s tryTarget=%s canFire=%s reloadFrame=%s projectiles=%d geoHealth=%.0f"):format(
				frame, id, i, x, y, z, math.sqrt(vx ^ 2 + vz ^ 2), dist, tostring(range), moved,
				tostring(mt.progressState), table.concat(q, " "), tstr, tostring(testRange), tostring(tryTarget),
				tostring(canFire), tostring(reload), projectiles[id], geoHealth))
		end
	end
end

function gadget:Initialize()
	if not Enabled() then
		gadgetHandler:RemoveGadget(self)
	end
end

function gadget:GameFrame(frame)
	if frame == 1 then
		CreateScenario()
	elseif frame == 30 then
		IssueAttack()
	elseif frame > 30 and frame % 90 == 0 and frame <= 1800 then
		Report(frame)
	end
	-- mshipgeoautoquit=1: end the game after the last report (headless runs; the widget quits the client)
	if frame == 1830 and Option("mshipgeoautoquit") == "1" then
		Spring.GameOver({ attackerTeam })
	end
end

-- keep the target alive by default so the stalled ships stay observable;
-- mshipgeovulnerable=1 lets the rockets destroy it
function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage)
	if unitID == geoID and Option("mshipgeovulnerable") ~= "1" then
		return 0, 0
	end
	return damage
end

function gadget:UnitDestroyed(unitID)
	if unitID == geoID and not geoDeadFrame then
		geoDeadFrame = Spring.GetGameFrame()
		Spring.Echo(("MSHIP_GEO_TARGET_DESTROYED frame=%d"):format(geoDeadFrame))
	end
end

function gadget:ProjectileCreated(_, ownerID, weaponDefID)
	if shipSet[ownerID] and weaponDefID == rocketWeaponDefID then
		projectiles[ownerID] = projectiles[ownerID] + 1
	end
end
