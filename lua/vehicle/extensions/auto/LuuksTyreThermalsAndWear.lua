groundModels = {}    -- Intentionally global
groundModelsLut = {} -- Intentionally global
beamstate = require("beamstate")

local M = {}

local OPTIMAL_PRESSURE = 158000 -- In pascal (23 psi)
local WORKING_TEMP = 85         -- The "perfect" working temperature for your tyres
local ENV_TEMP = 21             -- In celsius. Represents both the outside air and surface temp in 1 variable.

local TEMP_CHANGE_RATE = 0.2    -- Global modifier for how fast temperature changes
local TEMP_GAIN_RATE = 0.85     -- Modifier for how fast temperature rises from wheel slip
local TEMP_COOL_RATE = 1.65     -- Modifier for how fast temperature cools down related to ENV_TEMP

local TEMP_CHANGE_RATE_SKIN_FROM_CORE = 0.3

local TEMP_CHANGE_RATE_CORE = 0.09 -- Global modifier for how fast the core temperature changes
local TEMP_GAIN_RATE_CORE = 0.03   -- Modifier for how fast core temperature rises from brake temp
local TEMP_COOL_RATE_CORE = 0.5    -- Modifier for how fast core temperature cools down related to skin temperature

local WEAR_RATE = 0.025

local TORQUE_ENERGY_MULTIPLIER = 0.075

local tyreData = {}
local wheelCache = {}

local totalTimeMod60 = 0

-- Research notes on tyre thermals and wear:
-- - Thermals have an obvious impact on grip, but not as much as wear.
-- - Tyres that are too hot or cold wear quicker (although for different reasons).
-- - Tyre pressure heavily affects the thermals and wear (mostly thermals I think).
-- - Brake temperature influences tyre thermals a decent amount as well.

function print_table(node)
    -- to make output beautiful
    local function tab(amt)
        local str = ""
        for i = 1, amt do
            str = str .. "\t"
        end
        return str
    end

    local cache, stack, output = {}, {}, {}
    local depth = 1
    local output_str = "{\n"

    while true do
        local size = 0
        for k, v in pairs(node) do
            size = size + 1
        end

        local cur_index = 1
        for k, v in pairs(node) do
            if (cache[node] == nil) or (cur_index >= cache[node]) then
                if (string.find(output_str, "}", output_str:len())) then
                    output_str = output_str .. ",\n"
                elseif not (string.find(output_str, "\n", output_str:len())) then
                    output_str = output_str .. "\n"
                end

                -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
                table.insert(output, output_str)
                output_str = ""

                local key
                if (type(k) == "number" or type(k) == "boolean") then
                    key = "[" .. tostring(k) .. "]"
                else
                    key = "['" .. tostring(k) .. "']"
                end

                if (type(v) == "number" or type(v) == "boolean") then
                    output_str = output_str .. tab(depth) .. key .. " = " .. tostring(v)
                elseif (type(v) == "table") then
                    output_str = output_str .. tab(depth) .. key .. " = {\n"
                    table.insert(stack, node)
                    table.insert(stack, v)
                    cache[node] = cur_index + 1
                    break
                else
                    output_str = output_str .. tab(depth) .. key .. " = '" .. tostring(v) .. "'"
                end

                if (cur_index == size) then
                    output_str = output_str .. "\n" .. tab(depth - 1) .. "}"
                else
                    output_str = output_str .. ","
                end
            else
                -- close the table
                if (cur_index == size) then
                    output_str = output_str .. "\n" .. tab(depth - 1) .. "}"
                end
            end

            cur_index = cur_index + 1
        end

        if (#stack > 0) then
            node = stack[#stack]
            stack[#stack] = nil
            depth = cache[node] == nil and depth + 1 or depth - 1
        else
            break
        end
    end

    -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings

    table.insert(output, output_str)
    output_str = table.concat(output)

    print(output_str)
end

local function sigmoid(x, k)
    local k = k or 10
    return 1 / (1 + k ^ -x)
end



local function lerp(a, b, t)
    return a + (b - a) * t
end

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
    local weightCenter = -1 / (1 + 1 * (loadBias ^ -2)) + 1
    local weightLeft = -0.8 * loadBias + 1
    local weightRight = 0.8 * loadBias + 1

    local weightSum = weightLeft + weightCenter + weightRight
    local leftNormalise = weightLeft / weightSum
    local centerNormalise = weightCenter / weightSum
    local rightNormalise = weightRight / weightSum

    return { leftNormalise, centerNormalise, rightNormalise }
    -- return { val1, val2, val3 }
end

local function TempRingsToAvgTemp(temps, loadBias)
    local weights = CalcBiasWeights(loadBias)
    return temps[1] * weights[1] + temps[2] * weights[2] + temps[3] * weights[3]
end

-- Calculate tyre wear and thermals based on tyre data
local function RecalcTyreWear(dt, wheelID, groundModel, loadBias, treadCoef, slipEnergy, propulsionTorque, brakeTorque,
                              load, angularVel, brakeTemp, tyreWidth)
    -- local STARTING_TEMP = ENV_TEMP + 10
    local default_working_temp = WORKING_TEMP * treadCoef
    local starting_temp
    -- preheat race tyres only
    if treadCoef >= 0.95 then
        starting_temp = default_working_temp
    else
        starting_temp = ENV_TEMP
    end
    local defaultTyreData = {
        working_temp = default_working_temp,
        temp = { starting_temp, starting_temp, starting_temp, starting_temp },
        condition = 100, -- 100% perfect tyre condition
    }
    local data = tyreData[wheelID] or defaultTyreData

    local tyreWidthCoeff = (3.5 * tyreWidth) * 0.5 + 0.5
    local loadCoeff = math.max(load, 0) / 630 / tyreWidthCoeff
    local torqueEnergy = math.abs(propulsionTorque * 0.015 + brakeTorque * 0.012) * TORQUE_ENERGY_MULTIPLIER

    local weights = CalcBiasWeights(loadBias)
    -- if wheelID == 1 then
    --     print(loadBias)
    --     print(weights[1] .. " " .. weights[2] .. " " .. weights[3])
    -- end

    local avgTemp = TempRingsToAvgTemp(data.temp, loadBias)

    for i = 1, 3 do
        local loadCoeffIndividual = loadCoeff * weights[i]
        local tempGain = (slipEnergy * 0.80 + torqueEnergy * 0.08 + angularVel * 0.105) * TEMP_CHANGE_RATE *
            TEMP_GAIN_RATE * dt
        local tempDist = math.abs(data.temp[i] - data.working_temp)
        local tempLerpValue = (tempDist / data.working_temp) ^ 0.8
        tempGain = lerp(tempGain, tempGain * 0.5, tempLerpValue) * loadCoeffIndividual * 0.9
        tempGain = tempGain * (math.max(groundModel.staticFrictionCoefficient - 0.5, 0.1) * 2) +
            (0.000125 * slipEnergy ^ 2 * loadCoeffIndividual)

        local tempCoolingRate = (data.temp[i] - ENV_TEMP) * TEMP_CHANGE_RATE * dt * 0.05 * TEMP_COOL_RATE
        local coolVelCoeff = 1.25 * math.max(((angularVel / math.max(slipEnergy, 0.001)) * 0.00055) ^ 0.75 * 0.84, 1)
        local skinTempDiffCore = (data.temp[4] - avgTemp) * TEMP_CHANGE_RATE_SKIN_FROM_CORE * dt

        local tempDiff = (avgTemp - data.temp[i]) * TEMP_CHANGE_RATE * dt

        data.temp[i] = data.temp[i] + tempGain - tempCoolingRate * coolVelCoeff + tempDiff + skinTempDiffCore
    end

    -- Calculating temperature change of the core
    local avgSkin = (data.temp[1] + data.temp[2] + data.temp[3]) / 3
    local tempCoolingRate = (data.temp[4] - avgSkin) * TEMP_CHANGE_RATE_CORE * dt * TEMP_COOL_RATE_CORE
    local coreTempDiffSkin = (avgSkin - data.temp[4]) * TEMP_CHANGE_RATE_CORE * dt
    local coreTempDiffBrake = (brakeTemp - data.temp[4]) * TEMP_CHANGE_RATE_CORE * dt * TEMP_GAIN_RATE_CORE
    data.temp[4] = data.temp[4] - tempCoolingRate + coreTempDiffSkin + coreTempDiffBrake

    local thermalCoeff = (math.abs(avgTemp - data.working_temp) / data.working_temp) ^ 0.8
    local wear = (slipEnergy * 0.75 + torqueEnergy * 0.08 + angularVel * 0.05) * WEAR_RATE * dt *
        math.max(thermalCoeff, 0.75) * groundModel.staticFrictionCoefficient
    data.condition = math.max(data.condition - wear, 0)
    tyreData[wheelID] = data
end

local function CalculateTyreGrip(wheelID, loadBias, treadCoef)
    local data = tyreData[wheelID]

    local avgTemp = TempRingsToAvgTemp(data.temp, loadBias)

    local tyreGrip = 1
    tyreGrip = tyreGrip * (math.min(data.condition / 97, 1) ^ 3.5 * 0.22 + 0.78)
    -- Grip of tyres with high treadCoef are affected more by temperature change
    local tempDist = math.abs(avgTemp - data.working_temp)^treadCoef
    local tempLerpValue = (tempDist / data.working_temp) ^ 0.1
    tyreGrip = tyreGrip * lerp(1, 0.82, tempLerpValue * treadCoef)

    return tyreGrip
end

-- This is a special function that runs every frame, and has full access to
-- vehicle data for the current vehicle.
local function updateGFX(dt)
    local stream = { data = {} }

    local vectorForward = obj:getDirectionVector()
    local vectorUp = obj:getDirectionVectorUp()
    local vectorRight = vectorForward:cross(vectorUp)

    -- print("===start===")
    -- for key, value in pairs(scenario) do
    --     print("===" .. key .. "===")
    --     print(value())
    -- end
    -- print_table(wheelData)

    -- print_table(v.data.powertrain)
    -- for k, v in pairs(partmgmt.getConfig().parts) do
    --     print(k, v)
    -- end

    -- for i = 45, 50, 1 do
    --     print("=== " .. i .. " ===")
    --     print(v.data.props[i])
    --     print_table(v.data.props[i])
    -- end
    -- print("===end===\n\n\n\n")

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
        w.contactMaterialID1 = wd.contactMaterialID1
        w.contactMaterialID2 = wd.contactMaterialID2
        w.treadCoef = wd.treadCoef
        w.softnessCoef = wd.softnessCoef
        w.isBroken = wd.isBroken
        w.isTireDeflated = wd.isTireDeflated
        w.brakeCoreTemperature = wd.brakeCoreTemperature or ENV_TEMP -- Fixes AI

        -- print(w.name .. w.lastSlip)
        -- Get camber/toe/caster data
        -- TODO: Get this relative to the track angle? Banked turns kinda mess up now I think
        w.camber = (90 - math.deg(math.acos(obj:nodeVecPlanarCos(wd.node2, wd.node1, vectorUp, vectorRight))))

        wheelCache[i] = w
    end

    -- Based on sensor data, we can estimate how far the load is shifted left-right on the tyre
    local loadBiasSide = sensors.gx2 / 5
    loadBiasSide = sigmoid(loadBiasSide, 2) * 2 - 1
    -- We don't use this system for front-back load, because we can simply guess this
    -- based on individual tyre load!

    for i = 0, #wheels.wheelRotators do
        local wheel = obj:getWheel(i)
        if wheel then
            local groundModelName, groundModel = GetGroundModelData(wheelCache[i].contactMaterialID1)

            local staticFrictionCoefficient = groundModel.staticFrictionCoefficient
            local slidingFrictionCoefficient = groundModel.slidingFrictionCoefficient

            local angularVel = math.max(math.abs(wheelCache[i].angularVelocity), obj:getVelocity():length() * 3) * 0.1 *
                (math.max(groundModel.staticFrictionCoefficient - 0.5, 0.1) * 2) ^ 3
            angularVel = math.floor(angularVel * 10) / 10 -- Round to reduce small issues
            local slipEnergy = wheelCache[i].lastSlip * staticFrictionCoefficient * 1.25
            -- Multiply with wheel direction to flip the torque for right side wheels
            local velCoeff = math.min(angularVel / math.max(slipEnergy, 0.001), 1)
            local propulsionTorque = wheelCache[i].propulsionTorque * wheelCache[i].wheelDir * velCoeff
            local brakeTorque = wheelCache[i].brakingTorque * wheelCache[i].wheelDir * velCoeff
            local load = wheelCache[i].downForce * velCoeff
            local brakeTemp = wheelCache[i].brakeCoreTemperature

            local treadCoef = 1.0 - wheelCache[i].treadCoef * 0.45
            local softnessCoef = wheelCache[i].softnessCoef
            local loadBias = loadBiasSide * 0.22 * softnessCoef + (wheelCache[i].camber / 12) * wheelCache[i].wheelDir
            loadBias = sigmoid(loadBias, 50) * 2 - 1

            RecalcTyreWear(dt, i, groundModel, loadBias, treadCoef, slipEnergy, propulsionTorque, brakeTorque, load,
                angularVel, brakeTemp, wheelCache[i].width)


            local tyreGrip = CalculateTyreGrip(i, loadBias, treadCoef)
            local isNotDeflated = 1
            if wheelCache[i].isTireDeflated or wheelCache[i].isBroken then isNotDeflated = 0 end


            local temps = {}
            for j = 1, 4 do
                table.insert(temps, math.floor(tyreData[i].temp[j] * 10) / 10)
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
                brake_working_temp = 800
            })
            if condition < 6 then
                beamstate.deflateTire(i)
            end

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
    -- print_table(beamstate.getVehicleState())
end

local function onReset()
    tyreData = {}

    obj:queueGameEngineLua("if luukstyrethermalsandwear then luukstyrethermalsandwear.getGroundModels() end")
end

local function onInit()
    obj:queueGameEngineLua("if luukstyrethermalsandwear then luukstyrethermalsandwear.getGroundModels() end")
end

M.onInit = onInit
M.onReset = onReset
M.updateGFX = updateGFX
M.groundModelsCallback = groundModelsCallback

return M