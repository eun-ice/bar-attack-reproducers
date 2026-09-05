-- Probe for RecoilEngine line-of-fire traces that start below the terrain (issues #3242, #3301).
-- Runs inside the "rock" scenario of dbg_attack_obstacle_reproducer.lua (five Sheldons behind a
-- rock on All That Glitters, one with its muzzle inside the cliff). Enable with modoption lofprobe=1.
--
-- Output lines (infolog):
--   LOF_PROBE_SHELDON  per Sheldon: muzzle height above ground, 3-arg and 6-arg (from muzzle)
--                      Spring.GetUnitWeaponHaveFreeLineOfFire towards the Fatboy (cannon path)
--   LOF_PROBE_POINT    per Sheldon position, for a Pawn (EMG, plain TraceRay path): 8-arg call
--                      from 40 elmo below / 40 elmo above the ground, and TraceRayGroundBetweenPositions
--   LOF_PROBE_GRID     8-arg call from ground+2 on a grid around the cliff Sheldon, with whether the
--                      corner vertex of the heightmap square lies above the source point
--   LOF_PROBE_SUMMARY  counts for the grid
function gadget:GetInfo()
	return {
		name = "LOF underground probe",
		desc = "Probes line-of-fire traces that start below the terrain",
		author = "aron",
		date = "2026",
		license = "GPL",
		layer = 100,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local HFLOF = Spring.GetUnitWeaponHaveFreeLineOfFire
local probeUnits = {} -- { {label, unitID}, ... }

local function Echo(...)
	Spring.Echo(...)
end

local function UnitsNamed(name, teamID)
	local out = {}
	for _, id in ipairs(Spring.GetAllUnits()) do
		local def = UnitDefs[Spring.GetUnitDefID(id)]
		if def and def.name == name and (teamID == nil or Spring.GetUnitTeam(id) == teamID) then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end

local function Target()
	local best, bestD
	for _, id in ipairs(UnitsNamed("armfboy")) do
		local x, _, z = Spring.GetUnitPosition(id)
		local d = (x - 707.070) ^ 2 + (z - 2649.709) ^ 2
		if not bestD or d < bestD then
			best, bestD = id, d
		end
	end
	return best
end

local function Probe()
	local targetID = Target()
	if not targetID then
		Echo("LOF_PROBE_ERROR no target")
		return
	end
	local tx, ty, tz = Spring.GetUnitPosition(targetID)
	ty = ty + 20
	local sheldons = UnitsNamed("cormort", 0)
	local cliffID, cliffMuzzle = nil, math.huge

	for _, id in ipairs(sheldons) do
		local x, y, z = Spring.GetUnitPosition(id)
		local mx, my, mz = Spring.GetUnitWeaponVectors(id, 1)
		local mag = my - Spring.GetGroundHeight(mx, mz)
		if mag < cliffMuzzle then
			cliffID, cliffMuzzle = id, mag
		end
		Echo(("LOF_PROBE_SHELDON id=%d pos=%.1f,%.1f,%.1f muzzleAboveGround=%.1f lofAim=%s lofMuzzle=%s tryTarget=%s"):format(
			id, x, y, z, mag, tostring(HFLOF(id, 1, targetID)), tostring(HFLOF(id, 1, mx, my, mz, targetID)),
			tostring(Spring.GetUnitWeaponTryTarget(id, 1, targetID))))
	end

	for _, probe in ipairs(probeUnits) do
		local label, probeUnitID = probe[1], probe[2]
		if not probeUnitID or not Spring.ValidUnitID(probeUnitID) then
			Echo("LOF_PROBE_ERROR no probe unit " .. label)
		else
			local wd = WeaponDefs[UnitDefs[Spring.GetUnitDefID(probeUnitID)].weapons[1].weaponDef]
			Echo(("LOF_PROBE_WEAPON probe=%s weaponType=%s aoe=%.1f"):format(label, wd.type, wd.damageAreaOfEffect))
			for _, id in ipairs(sheldons) do
				local x, _, z = Spring.GetUnitPosition(id)
				local gh = Spring.GetGroundHeight(x, z)
				local under = HFLOF(probeUnitID, 1, x, gh - 40, z, tx, ty, tz)
				local above = HFLOF(probeUnitID, 1, x, gh + 40, z, tx, ty, tz)
				local traceUnder = Spring.TraceRayGroundBetweenPositions(x, gh - 40, z, tx, ty, tz)
				local traceAbove = Spring.TraceRayGroundBetweenPositions(x, gh + 40, z, tx, ty, tz)
				Echo(("LOF_PROBE_POINT probe=%s sheldon=%d lofUnder=%s lofAbove=%s traceUnder=%s traceAbove=%s"):format(
					label, id, tostring(under), tostring(above), tostring(traceUnder), tostring(traceAbove)))
			end

			-- grid of sources 2 elmo above the ground around the cliff Sheldon
			local cx, _, cz = Spring.GetUnitPosition(cliffID)
			local n, nCornerAbove, nFree, nFreeCornerAbove, nBlockedCornerAbove, nFreeTraceHit = 0, 0, 0, 0, 0, 0
			for dx = -64, 64, 8 do
				for dz = -64, 64, 8 do
					local px, pz = cx + dx + 3, cz + dz + 3 -- inside a square, not on its edge
					local py = Spring.GetGroundHeight(px, pz) + 2
					local cornerH = Spring.GetGroundHeight(math.floor(px / 8) * 8, math.floor(pz / 8) * 8)
					local cornerAbove = cornerH > py
					local lof = HFLOF(probeUnitID, 1, px, py, pz, tx, ty, tz)
					local trace = Spring.TraceRayGroundBetweenPositions(px, py, pz, tx, ty, tz)
					n = n + 1
					if cornerAbove then nCornerAbove = nCornerAbove + 1 end
					if lof then nFree = nFree + 1 end
					if cornerAbove and lof then nFreeCornerAbove = nFreeCornerAbove + 1 end
					if cornerAbove and not lof then nBlockedCornerAbove = nBlockedCornerAbove + 1 end
					if lof and trace and trace > 0 then nFreeTraceHit = nFreeTraceHit + 1 end
					Echo(("LOF_PROBE_GRID probe=%s dx=%d dz=%d py=%.1f cornerH=%.1f cornerAbove=%s lof=%s trace=%s"):format(
						label, dx, dz, py, cornerH, tostring(cornerAbove), tostring(lof), tostring(trace)))
				end
			end
			Echo(("LOF_PROBE_SUMMARY probe=%s cliffSheldon=%d muzzleAboveGround=%.1f points=%d cornerAbove=%d free=%d freeCornerAbove=%d blockedCornerAbove=%d freeButStraightTraceHits=%d"):format(
				label, cliffID, cliffMuzzle, n, nCornerAbove, nFree, nFreeCornerAbove, nBlockedCornerAbove, nFreeTraceHit))
		end
	end
end

function gadget:Initialize()
	if not Spring.GetModOptions().lofprobe then
		gadgetHandler:RemoveGadget(self)
	end
end

function gadget:GameFrame(frame)
	if frame == 30 then
		for i, def in ipairs({ { "laser", "armflea" }, { "cannon", "armpw" } }) do
			local x, z = 600 + 40 * i, 2150
			local id = Spring.CreateUnit(def[2], x, Spring.GetGroundHeight(x, z), z, 0, 0)
			probeUnits[#probeUnits + 1] = { def[1], id }
			Echo("LOF_PROBE_UNIT " .. def[1] .. " " .. tostring(id))
		end
	elseif frame == 60 then
		Probe()
	elseif frame == 90 then
		Spring.GameOver({ 0 })
	end
end
