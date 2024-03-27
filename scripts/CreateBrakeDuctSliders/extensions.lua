local M = {}

local variablesById = {}
local vehid

local function onVehicleSpawned(vehID)
	vehid = vehID
	local vehicleData = core_vehicle_manager.getVehicleData(vehID)
	if not vehicleData then return end
	local vdata = vehicleData.vdata
	if not vdata then return end
	if not vdata.variables then vdata.variables = {} end

	if not variablesById[vehID] then
		variablesById[vehID] = {
			["$JustForFun"] = {
				name = "$JustForFun",
				category = "Brakes",
				title = "Duct 1",
				description = "JustForFun description",

				type = "range",
				unit = "setting",

				min =    1, minDis =    1,
				max =   6, maxDis =   6,
				step = 1, stepDis = 1,
				default = 4,
				val = 4
			}
		}
	end

	tableMerge(vdata.variables, variablesById[vehID])
end

local function onSettingsChanged()
	be:sendToMailbox("tyreWearMailbox", core_vehicle_manager.getPlayerVehicleData().vdata.variables["$JustForFun"].val)
end

local function onSpawnCCallback(vehID)
	if not variablesById[vehID] then return end
	local _, configDataIn = debug.getlocal(3,3)
	if type(configDataIn) ~= "string" or configDataIn:sub(1,1) ~= "{" then return end
	local desirialized = deserialize(configDataIn)

	if type(desirialized) ~= "table" or type(desirialized.vars) ~= "table" then return end

	for name, variable in pairs(variablesById[vehID]) do
		if desirialized.vars[name] then
			variablesById[vehID][name].val = desirialized.vars[name]
		else
			variablesById[vehID][name].val = variablesById[vehID][name].default or variablesById[vehID][name].val
		end
	end
end

local function onVehicleDestroyed(vehID)
	variablesById[vehID] = nil
end


M.onVehicleSpawned = onVehicleSpawned
M.onSpawnCCallback = onSpawnCCallback
M.onVehicleDestroyed = onVehicleDestroyed
M.onSettingsChanged = onSettingsChanged
return M
