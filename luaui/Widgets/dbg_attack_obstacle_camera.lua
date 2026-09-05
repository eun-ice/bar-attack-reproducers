function widget:GetInfo()
	return {
		name = "Attack Obstacle Reproducer Camera",
		desc = "Frames the reproducer scenario and selects the shooters",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

local function ReproducerEnabled()
	local value = Spring.GetModOptions().attackobstaclereproducer
	return value == true or value == 1 or value == "1"
end

local positioned = false

-- the view captured for the original rock scenario (All That Glitters)
local rockCamera = {
	mode = 2,
	name = "spring",
	px = 810.389648,
	py = 227.514221,
	pz = 2590.49756,
	dx = 0.0000000014704,
	dy = -0.9995065,
	dz = -0.0314107,
	rx = 3.1101768,
	ry = 0.47123894,
	rz = 0,
	dist = 1664.40771,
	fov = 45,
}

function widget:Update()
	if not ReproducerEnabled() then
		widgetHandler:RemoveWidget(self)
		return
	end
	if positioned or Spring.GetGameFrame() < 5 then
		return
	end

	local cx = Spring.GetGameRulesParam("attackobstacle_cx")
	local cz = Spring.GetGameRulesParam("attackobstacle_cz")
	local extent = Spring.GetGameRulesParam("attackobstacle_extent")
	if not cx then
		return
	end
	positioned = true

	local scenario = tostring(Spring.GetModOptions().attackobstaclescenario or "rock")
	local cam = {}
	for k, v in pairs(rockCamera) do
		cam[k] = v
	end
	if scenario ~= "rock" then
		-- straight top-down view centred on the units, north up
		cam.px, cam.pz = cx, cz
		cam.py = Spring.GetGroundHeight(cx, cz)
		cam.ry = 0
		cam.dist = math.max(900, extent * 2.0)
	end
	Spring.SetCameraState(cam, 0)

	local shooterName = Spring.GetModOptions().attackobstaclelineunit or "cormort"
	local shooters = {}
	for _, unitID in ipairs(Spring.GetTeamUnits(Spring.GetMyTeamID())) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		if unitDefID and UnitDefs[unitDefID].name == shooterName then
			shooters[#shooters + 1] = unitID
		end
	end
	Spring.SelectUnitArray(shooters)
end
