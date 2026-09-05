-- Camera for the corcom tick attack stall reproducer (dbg_corcom_tick_attack_stall_reproducer.lua):
-- top-down view of the commander and the three Ticks, commander selected, for recordings.
function widget:GetInfo()
	return {
		name = "Corcom tick attack stall camera",
		desc = "Frames the commander attack stall reproducer",
		author = "aron",
		date = "2026",
		license = "GPL",
		layer = 1000000,
		enabled = true,
	}
end

local function Enabled()
	local value = Spring.GetModOptions().corcomtickattackstall
	return value == true or value == 1 or value == "1"
end

local positioned = false

function widget:Update()
	if not Enabled() then
		widgetHandler:RemoveWidget(self)
		return
	end
	if positioned or Spring.GetGameFrame() < 5 then
		return
	end
	positioned = true

	-- midpoint between the commander (3452,764 / 3439,683) and the Ticks (~3720,985), north up
	local cx, cz = 3590, 860
	Spring.SetCameraState({
		mode = 2, name = "spring",
		px = cx, py = Spring.GetGroundHeight(cx, cz), pz = cz,
		dx = 0, dy = -0.9995065, dz = -0.0314107,
		rx = 3.1101768, ry = 0, rz = 0,
		dist = 1000, fov = 45,
	}, 0)

	local commanders = {}
	for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID())) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		if unitDefID and UnitDefs[unitDefID].name == "corcom" then
			commanders[#commanders + 1] = unitID
		end
	end
	Spring.SelectUnitArray(commanders)
end
