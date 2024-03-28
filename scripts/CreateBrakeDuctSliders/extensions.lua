local json = require("../utils/json_parse")
local M = {}

local variablesById = {}
local vehid

local brakeSetting = nil
local function onVehicleSpawned(vehID)
	vehid = vehID
	brakeSetting = nil
	local vehicleData = core_vehicle_manager.getVehicleData(vehID)
	if not vehicleData then return end
	local vdata = vehicleData.vdata
	if not vdata then return end
	if not vdata.variables then vdata.variables = {} end
	local partConfig = be:getObjectByID(vehID).partConfig -- either serialized table or a pathname
	local tablePartConfig = jsonReadFile(partConfig) or deserialize(partConfig)
	-- dump(tablePartConfig)
	if tablePartConfig.vars and tablePartConfig.vars["$WheelCoolingDuct"] then
		brakeSetting = tablePartConfig.vars["$WheelCoolingDuct"]
	end

	-- if brakeSetting ~= nil then
	-- 	brakeSetting = v.data.variables["$WheelCoolingDuct"].val
	-- end

	if not variablesById[vehID] then
		variablesById[vehID] = {
			["$WheelCoolingDuct"] = {
				name = "$WheelCoolingDuct",
				category = "Brakes",
				title = "Wheel Cooling ducts",
				description = "Controls the amount of air passing over the inner wheel. 1 - Fully closed, 6 - Fully open",
				type = "range",
				unit = "setting",

				min = 1,
				minDis = 1,
				max = 6,
				maxDis = 6,
				step = 1,
				stepDis = 1,
				default = 4,
				val = brakeSetting or 4
			}
		}
	else
		variablesById[vehID]["$WheelCoolingDuct"].val = brakeSetting or 4
	end

	tableMerge(vdata.variables, variablesById[vehID])
end

local function onSpawnCCallback(vehID)
	if not variablesById[vehID] then return end
	local _, configDataIn = debug.getlocal(3, 3)
	if type(configDataIn) ~= "string" or configDataIn:sub(1, 1) ~= "{" then return end
	local desirialized = deserialize(configDataIn)

	if type(desirialized) ~= "table" or type(desirialized.vars) ~= "table" then return end

	for name, variable in pairs(variablesById[vehID]) do
		if desirialized.vars[name] then
			variablesById[vehID][name].val = desirialized.vars[name]
		else
			variablesById[vehID][name].val = variablesById[vehID][name].default or variablesById[vehID][name].val
		end
	end
	brakeSetting = nil
	be:sendToMailbox("tyreWearMailbox", core_vehicle_manager.getPlayerVehicleData().vdata.variables["$WheelCoolingDuct"].val or 4)
end

local function onVehicleDestroyed(vehID)
	variablesById[vehID] = nil
	brakeSetting = nil
end

M.onVehicleSpawned = onVehicleSpawned
M.onSpawnCCallback = onSpawnCCallback
M.onVehicleDestroyed = onVehicleDestroyed
return M
