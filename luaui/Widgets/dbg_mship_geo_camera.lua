function widget:GetInfo()
	return {
		name = "Missile Cruiser Geo Reproducer Camera",
		desc = "Selects the reproducer cruisers, frames the plateau, optional screenshots/quit",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

local function Enabled()
	local value = Spring.GetModOptions().mshipgeoreproducer
	return value == true or value == 1 or value == "1"
end

local positioned = false
local shots = {}

function widget:Update()
	if not Enabled() then
		widgetHandler:RemoveWidget(self)
		return
	end
	local frame = Spring.GetGameFrame()
	if not positioned and frame >= 5 then
		local ships = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), UnitDefNames.cormship.id)
		if #ships > 0 then
			positioned = true
			Spring.SelectUnitArray(ships)
			-- spring camera: top-down on the midpoint between the ships (~9200-9370, 7450-7850)
			-- and the geo on the plateau (10424, 6808), north up
			local cx, cz = 9800, 7300
			Spring.SetCameraState({
				mode = 2, name = "spring",
				px = cx, py = Spring.GetGroundHeight(cx, cz), pz = cz,
				dx = 0, dy = -0.9995065, dz = -0.0314107,
				rx = 3.1101768, ry = 0, rz = 0,
				dist = 3300, fov = 45,
			}, 0)
		end
	end
	if Spring.GetModOptions().mshipgeoscreenshots == "1" then
		for _, f in ipairs({ 120, 600, 1200 }) do
			if frame >= f and not shots[f] then
				shots[f] = true
				Spring.SendCommands("screenshot png")
			end
		end
	end
	if Spring.GetModOptions().mshipgeoautoquit == "1" and frame >= 1830 then
		Spring.SendCommands("quitforce")
	end
end
