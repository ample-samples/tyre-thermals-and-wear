local nodes = require("vehicleeditor.nodes")
htmlTools = require("htmlTools")
groundModels = {}    -- Intentionally global
groundModelsLut = {} -- Intentionally global
beamstate = require("beamstate")

local tyre_data = require("tyreData")
local tyre_utils = require("tyre_utils")


local lerp = tyre_utils.lerp
local sigmoid = tyre_utils.sigmoid

local M = {}

local OPTIMAL_PRESSURE = 206842              -- In pascal (30 psi)
local WORKING_TEMP = 85                      -- The "perfect" working temperature for your tyres
local ENV_TEMP = 21                          -- In celsius. Represents both the outside air and surface temp in 1 variable.
local got_env_temp = false                   -- set to false until the mailbox request comes back

local TEMP_CHANGE_RATE = 2.0                 -- Global modifier for how fast skin temperature changes
local TEMP_WORK_GAIN_RATE = 4.5              -- Modifier for how fast temp rises if wheelSpin = FALSE // Modifier for how fast temperature rises from wheel side loading e.i. generating G's
local TEMP_SLIP_GAIN_RATE = 15.55            -- Modifier for how fast temp rises if wheelSpin = TRUE // Should be 1.7X!!!
local TEMP_COOL_RATE = 0.6                   -- Modifier for how fast temperature cools down related to ENV_TEMP
local TEMP_COOL_VEL_RATE = 0.0028              -- Modifier for how much velocity influences cooling skin
local DEFORMATION_ENERGY_MULTIPLIER = 0.45
local TORQUE_ENERGY_MULTIPLIER = 1.6         -- Modifier for how much energy is generated by torque and braking // Rotational inertia?

local TEMP_CHANGE_RATE_SKIN_FROM_CORE = 0.06 -- Modifier for how fast skin temperature changes from core

local TEMP_CHANGE_RATE_CORE_FROM_SKIN = 3.7  -- Modifier for how much the temperature of the skin changes the temperature of the core
local TEMP_CHANGE_RATE_CORE = 0.0325         -- Modifier for how fast the core temperature changes
local TEMP_GAIN_RATE_CORE = 0.09             -- Modifier for how fast core temperature rises from brake temp
local CORE_TEMP_VEL_COOL_RATE = 0.07         -- Modifier for how fast core temperature cools down from moving air
local CORE_TEMP_COOL_RATE = 1.5              -- Modifier for how fast core temperature cools down from static air/IR radiation

local WEAR_RATE = 0.042

local tyreGripTable = {}
local brakeDuctSettings = { -1, -1 }
local baseBrakeCoolings = {}
local isRaceBrake = {}
local padMaterials = {}

local tyreData = {}
local wheelCache = {}

local totalTimeMod60 = 0

local debugStepFinished = false
local stepCounter = 0
local stribeckValues = { -1, -1 }

-- Research notes on tyre thermals and wear:
-- - Thermals have an obvious impact on grip, but not as much as wear.
-- - Tyres that are too hot or cold wear quicker (although for different reasons).
-- - Tyre pressure heavily affects the thermals and wear (mostly thermals I think).
-- - Brake temperature influences tyre thermals a decent amount as well.

local function GetGroundModelData(id)
    local materials, materialsMap = particles.getMaterialsParticlesTable()
    local matData = materials[id] or {}
    local name = matData.name or "DOESNT EXIST"
    -- local name = groundModelsLut[id] or "DOESNT EXIST"
    local data = groundModels[name] or { staticFrictionCoefficient = 1, slidingFrictionCoefficient = 1 }
    return name, data
end

local function CalcBiasWeights(loadBias)
    -- tyreStiffnessFactor controls how evenly the tyre supports weight as camber changes.
    -- Higher is more support and less even support
    local tyreStiffnessFactor = 0.25
    local weightCenter = -1 / (1 + 5 * (loadBias ^ -2)) + 1
    local weightLeft = -1 * loadBias + 1
    local weightRight = 1 * loadBias + 1

    local weightSum = weightLeft + weightCenter + weightRight
    return {
        weightLeft / weightSum,
        weightCenter / weightSum,
        weightRight / weightSum
    }
    -- return { val1, val2, val3 }
end

local function calculateLateralWeightBias(loadBias)

end

local function TempRingsToAvgTemp(temps, loadBias)
    local weights = CalcBiasWeights(loadBias)
    return temps[1] * weights[1] + temps[2] * weights[2] + temps[3] * weights[3]
end

-- Calculate tyre wear and thermals based on tyre data
local function CalcTyreWear(dt, wheelID, groundModel, loadBias, treadCoef, slipEnergy, propulsionTorque, brakeTorque,
                            load, angularVel, brakeTemp, tyreWidth, airspeed, deformationEnergy, g_table, wheel_name,
                            brakeCooling)
    -- Table of thermal related variables and functions.`
    local vWeight = nodes.calculateNodesWeight(v.data.nodes)
    -- dump("vWeight")
    -- dump(vWeight)
    local relativeWeight = load / (vWeight * 9.81)
    -- adjust for lower weight cars which generate less force
    -- x = ((400 + x) * x / (100 + x) - 0.15 * x)
    -- load = relativeWeight * 10
    -- local STARTING_TEMP = ENV_TEMP + 10
    local mapTemp
    local starting_temp
    if powertrain ~= nil then
        mapTemp = powertrain.currentEnvTemperatureCelsius or ENV_TEMP
        starting_temp = powertrain.currentEnvTemperatureCelsius or ENV_TEMP
    end
    local default_working_temp = lerp(90, 97, math.max(0, (1 - (1 - treadCoef) / 0.45) - 0.5) * 2)
    -- preheat race tyres only
    -- TODO: preheat tyres if padMaterial is "semi-race" or "race"?
    -- v.data.wheels[i].padMaterial
    if isRaceBrake[wheelID] or treadCoef > 0.974 then
        -- starting_temp = default_working_temp
    else
    end

    local defaultWheelData = {
        working_temp = default_working_temp,
        temp = { starting_temp, starting_temp, starting_temp, starting_temp },
        condition = 100, -- 100% perfect tyre condition
        lastTyregrip = 1,
        brakeCooling = baseBrakeCoolings[wheelID],
    }

    local vehNotParked = 1
    if angularVel < 0.1 and g_table.g_horiz < 0.1 then
        vehNotParked = 0
    end

    -- print("vehNotParked: " .. vehNotParked)
    -- print("angularVel: " .. angularVel)

    local brake_coolingSetting
    if string.lower(string.sub(wheel_name, 1, 1)) == "f" then
        brake_coolingSetting = brakeDuctSettings[1]
    else
        brake_coolingSetting = brakeDuctSettings[2]
    end
    wheelCache[wheelID].brakeCooling = (((brake_coolingSetting or 12) - 1) / 12) * (baseBrakeCoolings[wheelID] or 0.5)

    local data = tyreData[wheelID] or defaultWheelData

    local tyreWidthCoeff = (3.5 * tyreWidth) * 0.5 + 0.5
    -- dump("tyreWidthCoeff")
    -- dump(tyreWidthCoeff)

    local weights = CalcBiasWeights(loadBias)
    local avgTemp = TempRingsToAvgTemp(data.temp, loadBias)
    -- TODO: should angularVel be included in this?
    local netTorqueEnergy = vehNotParked * math.abs(propulsionTorque * 0.015 - brakeTorque * 0.025) * 0.1 *
        TORQUE_ENERGY_MULTIPLIER * 3
    if wheelID == 0 then
        -- dump("loadBias")
        -- dump(loadBias)
    end

    for i = 1, 3 do
        local loadCoeffIndividual = weights[i] * relativeWeight
        local tempDist = math.abs(data.temp[i] - data.working_temp)
        local tempLerpValue = (tempDist / data.working_temp) ^ 0.8

        local relative_work = math.abs(g_table.gx) * loadCoeffIndividual * 10
        local tempGain = (slipEnergy * 0.3 + netTorqueEnergy * 0.05 + deformationEnergy * 0.001 * DEFORMATION_ENERGY_MULTIPLIER) *
            3.5 * weights[i] * tyreWidthCoeff
        tempGain = tempGain * (math.max(groundModel.staticFrictionCoefficient - 0.5, 0.1) * 2)
            -- Temp gain from wheelspin / lockup
            + ((((0.004 * slipEnergy + 0.005 * (slipEnergy / 2) ^ 2) * math.sqrt(loadCoeffIndividual) * 1000) * TEMP_SLIP_GAIN_RATE
                -- Temp gain from work done in corner
                -- TODO: Test horizontal G * weights[i]

            + 0.15 * math.sqrt(relative_work) * TEMP_WORK_GAIN_RATE / (1 + slipEnergy ^ 2)) * groundModel.staticFrictionCoefficient / tyreWidthCoeff)

        local tempCoolingRate = (data.temp[i] - ENV_TEMP) * 0.05 * TEMP_COOL_RATE
        local staticCoolingRate = 0.06 * tempCoolingRate / treadCoef
        -- TODO: * dt should not be in this calculation
        local velCoolingCoeff = math.sqrt(airspeed) * TEMP_COOL_VEL_RATE / treadCoef
        local skinTempDiffCore = (data.temp[4] - avgTemp) * TEMP_CHANGE_RATE_SKIN_FROM_CORE /
            (0.5 * treadCoef) -- Slicks hold heat better

        local tempDiff = (avgTemp - data.temp[i]) * 0.2

        data.temp[i] = data.temp[i] +
            dt *
            (tempGain - (tempCoolingRate + tempCoolingRate * velCoolingCoeff + staticCoolingRate) + tempDiff + skinTempDiffCore) *
            TEMP_CHANGE_RATE /
            tyreWidthCoeff
    end

    -- Calculating temperature change of the core
    local avgSkin = (data.temp[1] + data.temp[2] + data.temp[3]) / 3
    local coreTempDiffSkin = (avgSkin - data.temp[4]) * TEMP_CHANGE_RATE_CORE_FROM_SKIN * (0.5 * treadCoef)
    local coreTempDiffBrake = (0.3 * (brakeTemp - data.temp[4] - 0.0009 * brakeTemp ^ 2)) * TEMP_GAIN_RATE_CORE
    --   This stops extreme brake temp numbers causing  overheating issues^^^

    local coreTempCooling = (data.temp[4] - ENV_TEMP) *
        (0.08 * CORE_TEMP_VEL_COOL_RATE * math.sqrt(airspeed) + 0.05 * CORE_TEMP_COOL_RATE) *
        lerp(0.8, 1.2, brake_coolingSetting / 12)
    data.temp[4] = data.temp[4] + (coreTempDiffSkin + coreTempDiffBrake - coreTempCooling) * TEMP_CHANGE_RATE_CORE * dt

    local thermalCoeff = (math.abs(avgTemp - data.working_temp) / data.working_temp) ^ 0.8

    local wear = (slipEnergy * 8.75 + (vehNotParked * math.abs(propulsionTorque * 0.008 - brakeTorque * 0.025) * 0.1 *
            TORQUE_ENERGY_MULTIPLIER * 3) * 0.08 + angularVel * 0.05) * WEAR_RATE * dt *
        math.max(thermalCoeff, 0.75) * groundModel.staticFrictionCoefficient / tyreWidthCoeff
    data.condition = math.max(data.condition - wear, 0)
    -- data.condition = 100
    tyreData[wheelID] = data
end

local function CalculateTyreGrip(wheelID, loadBias, treadCoef)
    local data = tyreData[wheelID]

    local avgTemp = TempRingsToAvgTemp(data.temp, loadBias)

    local tyreGrip = 1
    tyreGrip = tyreGrip * 0.7701504 + 0.002476352 * data.condition + 0.0001259966 * data.condition ^ (2) -
        0.000002465426 * data.condition ^ (3) + 1.187875 * 10 ^ (-8) * data.condition ^ (4)

    local raceTempGrip = tyre_utils.slicksTempToGrip(avgTemp)
    local streetTempGrip = tyre_utils.streetTempToGrip(avgTemp)

    -- local treadCoef = 1.0 - wheelCache[i].treadCoef * 0.45
    local gripTempModifier = tyre_utils.lerp(streetTempGrip, raceTempGrip,
        math.max(0, (1 - (1 - treadCoef) / 0.45) - 0.5) * 2)
    -- dump("grip calc")
    -- dump("lerp coef", math.max(0, (1 - (1 - treadCoef) / 0.45) - 0.5) * 2)
    -- dump("raceTempGrip", raceTempGrip)
    -- dump("streetTempGrip", streetTempGrip)
    -- dump("gripTempModifier", gripTempModifier)

    tyreGrip = tyreGrip * gripTempModifier
    -- tyreGrip = tyreGrip * (tyre_data.tempToGrip.slicks[math.floor(avgTemp)] or 0.96)
    -- print ("tyreGrip  " .. (tyreGrip or "not found") )
    -- dump("tyreGrip")
    -- dump(tyreGrip)
    -- TODO: Experiment with including a contact patch size based on loadBias
    tyreGripTable[wheelID] = tyreGrip
    return tyreGrip
end

-- This is a special function that runs every frame, and has full access to
-- vehicle data for the current vehicle.
local function updateGFX(dt)
    if got_env_temp == false then
        local be_env_temp = obj:getLastMailbox("tyreWearMailboxEnvTemp")
        if type(be_env_temp) == "string" then
            if type(tonumber(be_env_temp)) == "number" then
                ENV_TEMP = tonumber(be_env_temp)
                got_env_temp = true
            end
        end
    end
    if brakeDuctSettings[1] == -1 or brakeDuctSettings[2] == -1 or brakeDuctSettings[1] == nil or brakeDuctSettings[2] == nil then
        local mailboxResult = obj:getLastMailbox("tyreWearMailboxDuct")
        if type(mailboxResult) == "string" then
            local tableMailboxResult = deserialize(mailboxResult)
            if tableMailboxResult ~= nil then
                brakeDuctSettings[1] = tonumber(tableMailboxResult[1])
                brakeDuctSettings[2] = tonumber(tableMailboxResult[2])
            end
        end
    end

    local stream = { data = {} }
    for i, wd in pairs(wheels.wheelRotators) do
        local w = wheelCache[i] or {}
        w.name = wd.name
        w.radius = wd.radius
        w.width = wd.tireWidth
        w.wheelDir = wd.wheelDir
        w.angularVelocity = wd.angularVelocity
        w.propulsionTorque = wd.propulsionTorque
        w.lastSlip = wd.lastSlip
        w.lastSideSlip = wd.lastSideSlip
        w.downForce = wd.downForce
        w.brakingTorque = wd.brakingTorque
        w.brakeTorque = wd.brakeTorque
        w.brakeCooling = wd.brakeTypeSurfaceCoolingCoef
        w.lastTorque = wd.lastTorque
        w.contactMaterialID1 = wd.contactMaterialID1
        w.contactMaterialID2 = wd.contactMaterialID2
        w.treadCoef = wd.treadCoef
        w.softnessCoef = wd.softnessCoef
        w.isBroken = wd.isBroken
        w.isTireDeflated = wd.isTireDeflated
        w.downForceRaw = wd.downForceRaw
        w.brakeSurfaceTemperature = wd.brakeSurfaceTemperature or ENV_TEMP -- Fixes AI

        -- Get camber data
        -- node1 is outside rim, node2 is inside
        local vectorUp = obj:getDirectionVectorUp()
        local localVectNode1 = obj:getNodePosition(wd.node1)
        local localVectNode2 = obj:getNodePosition(wd.node2)
        local vectorWheelForward = (localVectNode2 - localVectNode1):cross(vectorUp)
        local vectorWheelUp = vectorWheelForward:cross(localVectNode2 - localVectNode1)
        local surfaceNormal = mapmgr.surfaceNormalBelow(
            obj:getPosition() + (localVectNode2 + localVectNode1) / 2 - wd.radius * vectorWheelUp:normalized(), 0.1
        )

        -- local vectorSurfaceToVehicle =
        -- get plane of wheelforward x wheelup and find arg of it's normal and surfaceNormal
        w.camber = 90 -
            math.deg(math.acos((localVectNode2 - localVectNode1):normalized():dot(surfaceNormal:normalized())))
        wheelCache[i] = w
    end

    -- Based on sensor data, we can estimate how far the load is shifted left-right on the tyre
    local loadBiasSide = sensors.gx2 / 5
    loadBiasSide = sigmoid(loadBiasSide, 2) * 2 - 1
    -- We don't use this system for front-back load, because we can simply guess this
    -- based on individual tyre load!

    -- l-r
    local gx = sensors.gx / 9.81
    -- f-b
    local gy = sensors.gy / 9.81
    -- u-d
    local gz = sensors.gz / 9.81
    local g_horiz = math.sqrt(gx * gx + gy * gy)
    local g_table = { gx = gx, gy = gy, gz = gz, g_horiz = g_horiz }

    local vehicleAirspeed = electrics.values.airflowspeed

    for i = 0, #wheels.wheelRotators do
        local wheel = obj:getWheel(i)
        if wheel then
            local groundModelName, groundModel = GetGroundModelData(wheelCache[i].contactMaterialID1)

            local staticFrictionCoefficient = groundModel.staticFrictionCoefficient
            local slidingFrictionCoefficient = groundModel.slidingFrictionCoefficient

            local angularVel = math.max(math.abs(wheelCache[i].angularVelocity), obj:getVelocity():length() * 3) * 0.1 *
                (math.max(groundModel.staticFrictionCoefficient - 0.5, 0.1) * 2) ^ 3
            angularVel = math.floor(angularVel * 10) / 10 -- Round to reduce small issues
            -- maximum grip occurs between lastSlip 1-3
            -- Sliding when lastSlip > 4
            local slipEnergy = wheelCache[i].lastSlip * staticFrictionCoefficient * 0.05
            -- Multiply with wheel direction to flip the torque for right side wheels
            local velCoeff = math.min(angularVel / math.max(slipEnergy, 0.001), 1)
            local propulsionTorque = wheelCache[i].propulsionTorque * wheelCache[i].wheelDir
            local brakeTorque = wheelCache[i].brakingTorque * wheelCache[i].wheelDir
            local deformationEnergy = wheelCache[i].downForce * velCoeff
            local load = wheelCache[i].downForceRaw
            -- Brake temp is measured in degrees C, not F
            local brakeTemp = wheelCache[i].brakeSurfaceTemperature
            if not baseBrakeCoolings[i] then
                baseBrakeCoolings[i] = wheelCache[i].brakeCooling
            end

            local treadCoef = 1.0 - wheelCache[i].treadCoef * 0.45
            local softnessCoef = wheelCache[i].softnessCoef
            -- TODO: what is this garbage?
            local loadBias = loadBiasSide * 0.1 + 0.5 * (wheelCache[i].camber / 12) * wheelCache[i].wheelDir
            loadBias = sigmoid(loadBias, 50) * 2 - 1

            CalcTyreWear(dt, i, groundModel, loadBias, treadCoef, slipEnergy, propulsionTorque, brakeTorque, load,
                angularVel, brakeTemp, wheelCache[i].width, vehicleAirspeed, deformationEnergy, g_table,
                wheelCache[i].name)
            wheels.wheelRotators[i].brakeTypeSurfaceCoolingCoef = wheelCache[i].brakeCooling

            local tyreGrip = CalculateTyreGrip(i, loadBias, treadCoef)
            local isNotDeflated = 1
            if wheelCache[i].isTireDeflated or wheelCache[i].isBroken then isNotDeflated = 0 end


            local temps = {}
            for j = 1, 4 do
                table.insert(temps, math.floor(tyreData[i].temp[j] * 10) / 10)
            end
            -- dump(temps)
            -- TODO: assignment to be replaced when the softnessCoef of the tyre is gotten
            local initalSoftnessCoef = 1
            for j = 1, #wheels.wheelRotators[i].nodes, 1 do
                -- local currentTyreNode = v.data.nodes[wheels.wheelRotators[0].nodes[i]]
                v.data
                .nodes[wheels
                .wheelRotators[i]
                .nodes[j]]
                .softnessCoef = initalSoftnessCoef * (tyreData[i].temp[4]  / 97)
                -- dump(v.data.nodes[wheels.wheelRotators[0].nodes[i]])
            end
            local condition = math.floor(tyreData[i].condition * 10) / 10 * isNotDeflated
            table.insert(stream.data, {
                name = wheelCache[i].name,
                tread_coef = treadCoef,
                working_temp = math.floor(tyreData[i].working_temp * 10) / 10,
                temp = temps,
                avg_temp = math.floor(TempRingsToAvgTemp(tyreData[i].temp, loadBias) * 10) / 10,
                condition = math.floor(tyreData[i].condition * 10) / 10 * isNotDeflated,
                tyreGrip = math.floor(tyreGrip * 1000) / 1000,
                load_bias = loadBias,
                contact_material = groundModelName,
                brake_temp = brakeTemp,
                brake_working_temp = 800,
                camber = wheelCache[i].camber * wheelCache[i].wheelDir,
            })
            if condition < 0.1 then
                beamstate.deflateTire(i)
            end

            if false and not debugStepFinished and stepCounter > 10 then
                -- dump('temp')
                -- dump(powertrain.currentEnvTemperatureCelsius)
                dump("electrics")
                dump(electrics)
                dump("globals")
                for key, value in pairs(_G) do
                    --load
                    --drivetrain
                    --
                    print(key, value)
                end
                -- dump(wheels)
                -- dump(wheel)
                -- dump(wheels.wheelRotators[i])
                -- wheels.wheelRotators[i].brakeCoolingArea = 1
                -- dump("weight")
                -- dump(nodes.calculateNodesWeight(v.data.nodes))

                -- dump(v.data)
                -- for key, value in pairs(v.data) do
                --     print(key)
                -- end

                -- local wheelRotatorsKeys = {}
                -- local debugValue = wheels.rotators
                -- for key, value in pairs(debugValue) do
                --     wheelRotatorsKeys[key] = ""
                --     print(key)
                -- end

                debugStepFinished = true
                dump("debug step finished")
            else
                stepCounter = stepCounter + 1
            end
            -- for key, value in pairs(wheels.wheelRotators[0].nodes[10]) do
            --     print(key)
            -- end
            -- dump("wheels.wheelRotators[0].nodes")
            -- dump("================= obj funcs")
            for key, value in pairs(getmetatable(obj)[1]) do
                -- dump(key)
            end
            -- dump(v.data.nodes)


            wheel:setFrictionThermalSensitivity(
                -300,     -- frictionLowTemp              default: -300
                1e7,      -- frictionHighTemp             default: 1e7
                1e-10,    -- frictionLowSlope             default: 1e-10
                1e-10,    -- frictionHighSlope            default: 1e-10
                10,       -- frictionSlopeSmoothCoef      default: 10
                tyreGrip, -- frictionCoefLow              default: 1
                tyreGrip, -- frictionCoefMiddle           default: 1
                tyreGrip  -- frictionCoefHigh             default: 1
            )
        end
    end
    totalTimeMod60 = (totalTimeMod60 + dt) % 60 -- Loops every 60 seconds
    stream.total_time_mod_60 = totalTimeMod60
    gui.send("TyreWearThermals", stream)
end

local tableContains = function(tbl, item)
    for key, value in pairs(tbl) do
        if value == item then
            return true
        end
    end
    return false
end

local function onReset()
    htmlTools.dumpToFile(getmetatable(obj)[1], "obj_funcs")
    tyreData = {}
    brakeDuctSettings = { -1, -1 }
    padMaterials = {}
    isRaceBrake = {}
    local racePadMaterials = {
        "race",
        "semi-race",
        "full-race",
        "carbon-ceramic"
    }
    -- dump("getting pad materials")
    for i = 0, #v.data.wheels, 1 do
        padMaterials[i] = ""
        if (v and v.data and v.data.wheels[i] and v.data.wheels[i]) then
            padMaterials[i] = v.data.wheels[i].padMaterial
        end
        -- dump(padMaterials[i])
    end
    for i = 0, #padMaterials, 1 do
        isRaceBrake[i] = tableContains(racePadMaterials, padMaterials[i])
    end

    obj:queueGameEngineLua("if luukstyrethermalsandwear then luukstyrethermalsandwear.getGroundModels() end")
end

local function onInit()
    obj:queueGameEngineLua("if luukstyrethermalsandwear then luukstyrethermalsandwear.getGroundModels() end")
end

local function vSettingsDebug()
    local count = 0
    htmlTools.dumpToFile(obj.partConfig, "obj")
end

local function onSettingsChanged()
    brakeDuctSettings = { -1, -1 }
    stribeckValues = { -1, -1 }
    got_env_temp = false
    padMaterials = {}
    isRaceBrake = {}
    for i = 0, #v.data.wheels, 1 do
        if v and v.data and v.data.wheels[i] and v.data.wheels[i].padMaterial then
            padMaterials[i] = v.data.wheels[i].padMaterial
        end
        for i = 0, #padMaterials, 1 do
            isRaceBrake[i] = padMaterials[i] == "race" or padMaterials[i] == "semi-race" or
                padMaterials[i] == "full-race"
        end
    end
    -- vSettingsDebug()
end

local function onVehicleSpawned()
end

M.onSettingsChanged = onSettingsChanged
M.onInit = onInit
M.onReset = onReset
M.updateGFX = updateGFX
M.onVehicleSpawned = onVehicleSpawned
M.groundModelsCallback = groundModelsCallback

return M
