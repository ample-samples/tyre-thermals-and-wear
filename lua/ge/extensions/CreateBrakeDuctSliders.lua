local M = {}

local variablesById = {}

local brakeSetting = {}
local function onVehicleSpawned(vehID)
	brakeSetting = {}
	local vehicleData = core_vehicle_manager.getVehicleData(vehID)
	if not vehicleData then return end
	local vdata = vehicleData.vdata
	if not vdata then return end
	if not vdata.variables then vdata.variables = {} end
	local partConfig = be:getObjectByID(vehID).partConfig -- either serialized table or a pathname
	local tablePartConfig = jsonReadFile(partConfig) or deserialize(partConfig)
	-- dump(tablePartConfig)
	if tablePartConfig.vars and tablePartConfig.vars["$WheelCoolingDuctFront"] then
		brakeSetting[1] = tablePartConfig.vars["$WheelCoolingDuctFront"]
	end
	if tablePartConfig.vars and tablePartConfig.vars["$WheelCoolingDuctRear"] then
		brakeSetting[2] = tablePartConfig.vars["$WheelCoolingDuctRear"]
	end

	-- if brakeSetting ~= nil then
	-- 	brakeSetting = v.data.variables["$WheelCoolingDuct"].val
	-- end

	if not variablesById[vehID] then
		variablesById[vehID] = {
			["$WheelCoolingDuctFront"] = {
				name = "$WheelCoolingDuctFront",
				category = "Brakes",
				title = "Front Cooling ducts",
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
				val = brakeSetting[1] or 4
			},
			["$WheelCoolingDuctRear"] = {
				name = "$WheelCoolingDuctRear",
				category = "Brakes",
				title = "Rear Cooling ducts",
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
				val = brakeSetting[2] or 4
			}
		}
	else
		variablesById[vehID]["$WheelCoolingDuctFront"].val = brakeSetting[1] or 4
		variablesById[vehID]["$WheelCoolingDuctRear"].val = brakeSetting[2] or 4
	end

	tableMerge(vdata.variables, variablesById[vehID])
end

local function onSpawnCCallback(vehID)
	if not variablesById[vehID] then return end
	local _, configDataIn = debug.getlocal(3, 3)
	if type(configDataIn) ~= "string" or configDataIn:sub(1, 1) ~= "{" then return end
	local desirialized = deserialize(configDataIn)

	if type(desirialized) ~= "table" or type(desirialized.vars) ~= "table" then return end

	for name, _ in pairs(variablesById[vehID]) do
		if desirialized.vars[name] then
			variablesById[vehID][name].val = desirialized.vars[name]
		else
			variablesById[vehID][name].val = variablesById[vehID][name].default or variablesById[vehID][name].val
		end
	end
end

local function onSettingsChanged()
	if not be then return end
	if not core_vehicle_manager.getPlayerVehicleData() then return end
	brakeSetting = {}
	local mailboxSend = {core_vehicle_manager.getPlayerVehicleData().vdata.variables["$WheelCoolingDuctFront"].val or 4, core_vehicle_manager.getPlayerVehicleData().vdata.variables["$WheelCoolingDuctRear"].val or 4}
	be:sendToMailbox("tyreWearMailboxDuct", serialize(mailboxSend))
	-- dump(core_environment.getTemperatureK() .. " K")
	local env_temp = tonumber(core_environment.getTemperatureK()) - 273.15
	be:sendToMailbox("tyreWearMailboxEnvTemp", env_temp)
end

local function onVehicleDestroyed(vehID)
	variablesById[vehID] = nil
	brakeSetting = {}
end

M.onSettingsChanged = onSettingsChanged
M.onVehicleSpawned = onVehicleSpawned
M.onSpawnCCallback = onSpawnCCallback
M.onVehicleDestroyed = onVehicleDestroyed
return M
