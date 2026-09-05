function widget:GetInfo()
	return {
		name = "Rocko Slope Stall Reproducer Camera",
		desc = "Shows and selects the reproducer Rocko",
		author = "local test setup",
		layer = 1000000,
		enabled = true,
	}
end

local function ReproducerEnabled()
	local value = Spring.GetModOptions().rockoslopestallreproducer
	return value == true or value == 1 or value == "1"
end

local positioned = false

function widget:Update()
	if not ReproducerEnabled() then
		widgetHandler:RemoveWidget(self)
		return
	end
	if positioned or Spring.GetGameFrame() < 5 then
		return
	end

	local attackers = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), UnitDefNames.armrock.id)
	if #attackers == 0 then
		return
	end

	positioned = true
	Spring.SelectUnitArray(attackers)
	-- between the Rocko on the ridge (5024, 194, 3264) and its target (4747, 90, 3424)
	Spring.SetCameraTarget(4900, 150, 3340, 0)
end
