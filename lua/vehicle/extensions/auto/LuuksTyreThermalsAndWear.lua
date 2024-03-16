groundModels = {}    -- Intentionally global
groundModelsLut = {} -- Intentionally global
beamstate = require("beamstate")

local M = {}

local OPTIMAL_PRESSURE = 158000              -- In pascal (23 psi)
local WORKING_TEMP = 85                      -- The "perfect" working temperature for your tyres
local ENV_TEMP = 21                          -- In celsius. Represents both the outside air and surface temp in 1 variable.

local TEMP_CHANGE_RATE = 0.9                -- Global modifier for how fast skin temperature changes
local TEMP_WORK_GAIN_RATE = 1.5              -- Modifier for how fast temperature rises from wheel side loading e.i. generating G's
local TEMP_SLIP_GAIN_RATE = 1.4              --
local TEMP_COOL_RATE = 78.0                  -- Modifier for how fast temperature cools down related to ENV_TEMP
local TEMP_COOL_VEL_RATE = 0.06              -- Modifier for how much velocity influences cooling skin
local DEFORMATION_ENERGY_MULTIPLIER = 0.017
local TORQUE_ENERGY_MULTIPLIER = 1.3       -- Modifier for how much energy is generated by torque and braking

local TEMP_CHANGE_RATE_SKIN_FROM_CORE = 0.06 -- Modifier for how fast skin temperature changes from core

local TEMP_CHANGE_RATE_CORE_FROM_SKIN = 2.5
local TEMP_CHANGE_RATE_CORE = 0.00625 -- Modifier for how fast the core temperature changes
local TEMP_GAIN_RATE_CORE = 0.9       -- Modifier for how fast core temperature rises from brake temp
local CORE_TEMP_VEL_COOL_RATE = 0.25  -- Modifier for how fast core temperature cools down from moving air
local CORE_TEMP_COOL_RATE = 3.0       -- Modifier for how fast core temperature cools down from static air/IR radiation

local WEAR_RATE = 0.1

local tyreGripTable = {}
local tyreData = {}
local wheelCache = {}

local totalTimeMod60 = 0

-- Research notes on tyre thermals and wear:
-- - Thermals have an obvious impact on grip, but not as much as wear.
-- - Tyres that are too hot or cold wear quicker (although for different reasons).
-- - Tyre pressure heavily affects the thermals and wear (mostly thermals I think).
-- - Brake temperature influences tyre thermals a decent amount as well.

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
    local weightCenter = -1 / (1 + 5 * (loadBias ^ -2)) + 1
    local weightLeft = -0.8 * loadBias + 1
    local weightRight = 0.8 * loadBias + 1

    local weightSum = weightLeft + weightCenter + weightRight
    return {
        weightLeft / weightSum,
        weightCenter / weightSum,
        weightRight / weightSum
    }
    -- return { val1, val2, val3 }
end

local function TempRingsToAvgTemp(temps, loadBias)
    local weights = CalcBiasWeights(loadBias)
    return temps[1] * weights[1] + temps[2] * weights[2] + temps[3] * weights[3]
end

-- Calculate tyre wear and thermals based on tyre data
local function CalcTyreWear(dt, wheelID, groundModel, loadBias, treadCoef, slipEnergy, propulsionTorque, brakeTorque,
                            load, angularVel, brakeTemp, tyreWidth, airspeed, deformationEnergy, g_table)
    -- Table of thermal related variables and functions.`
    -- adjust for lower weight cars which generate less force
    load = ((400 + load) * load / (100 + load) - 0.15 * load)
    -- local STARTING_TEMP = ENV_TEMP + 10
    local default_working_temp = (WORKING_TEMP + 1 * ENV_TEMP) * treadCoef - ENV_TEMP * 1
    local starting_temp
    -- preheat race tyres only
    if treadCoef >= 1.95 then
        starting_temp = default_working_temp
    else
        starting_temp = ENV_TEMP
    end
    local defaultTyreData = {
        working_temp = default_working_temp,
        temp = { starting_temp, starting_temp, starting_temp, starting_temp },
        condition = 100, -- 100% perfect tyre condition
        lastTyregrip = 1
    }
    local data = tyreData[wheelID] or defaultTyreData

    local tyreWidthCoeff = (3.5 * tyreWidth) * 0.5 + 0.5


    local weights = CalcBiasWeights(loadBias)
    local avgTemp = TempRingsToAvgTemp(data.temp, loadBias)
    -- TODO: should angularVel be included in this?
    local netTorqueEnergy = math.abs(propulsionTorque * 0.015 - brakeTorque * 0.015) * 0.01 * angularVel *
    TORQUE_ENERGY_MULTIPLIER * 3

    for i = 1, 3 do
        local loadCoeffIndividual = weights[i] * load
        local tempDist = math.abs(data.temp[i] - data.working_temp)
        local tempLerpValue = (tempDist / data.working_temp) ^ 0.8

        -- TODO: Multiply by vehicle mass?
        local relative_work = math.abs(g_table.gx) * loadCoeffIndividual / 1000
        local tempGain = (slipEnergy * 0.3 + netTorqueEnergy * 0.05 + deformationEnergy * 0.001 * DEFORMATION_ENERGY_MULTIPLIER) *
        3 * weights[i]
        tempGain = tempGain * (math.max(groundModel.staticFrictionCoefficient - 0.5, 0.1) * 2)
            -- Temp gain from wheelspin / lockup
        + (((0.003 * slipEnergy ^ 2 * loadCoeffIndividual) * TEMP_SLIP_GAIN_RATE * (tyreGripTable[wheelID] or 1)
        -- Temp gain from work done in corner
        -- TODO: Test horizontal G * weights[i]

        + 0.15 * relative_work * TEMP_WORK_GAIN_RATE / (1 + slipEnergy ^ 2)) * groundModel.staticFrictionCoefficient / tyreWidthCoeff )
        local tempCoolingRate = (data.temp[i] - ENV_TEMP) * 0.05 * TEMP_COOL_RATE
        local coolVelCoeff = TEMP_COOL_VEL_RATE *
            math.max(((angularVel / math.max(slipEnergy, 0.001)) * 0.00055) ^ 0.75 * 0.84, 1) * dt
        local skinTempDiffCore = (data.temp[4] - avgTemp) * TEMP_CHANGE_RATE_SKIN_FROM_CORE

        local tempDiff = (avgTemp - data.temp[i]) * 0.2
        tempGain = tempGain + ( tempGain * (data.working_temp - data.temp[i]) / 20 ) * treadCoef

        data.temp[i] = data.temp[i] +
             dt * (tempGain - tempCoolingRate * coolVelCoeff + tempDiff + skinTempDiffCore) * TEMP_CHANGE_RATE /
            tyreWidthCoeff
    end

    -- Calculating temperature change of the core
    local avgSkin = (data.temp[1] + data.temp[2] + data.temp[3]) / 3
    local coreTempDiffSkin = (avgSkin - data.temp[4]) * TEMP_CHANGE_RATE_CORE_FROM_SKIN
    local coreTempDiffBrake = (0.3 * (brakeTemp - data.temp[4] - 0.0009 * brakeTemp ^ 2)) * TEMP_GAIN_RATE_CORE
    --                          This stops extreme brake temp numbers causing  overheating issues^
    local coreTempCooling = (data.temp[4] - ENV_TEMP) *
    (0.05 * CORE_TEMP_VEL_COOL_RATE * airspeed + 0.05 * CORE_TEMP_COOL_RATE)
    data.temp[4] = data.temp[4] + (coreTempDiffSkin + coreTempDiffBrake - coreTempCooling) * TEMP_CHANGE_RATE_CORE * dt

    local thermalCoeff = (math.abs(avgTemp - data.working_temp) / data.working_temp) ^ 0.8
    local wear = (slipEnergy * 0.75 + netTorqueEnergy * 0.08 + angularVel * 0.05) * WEAR_RATE * dt *
        math.max(thermalCoeff, 0.75) * groundModel.staticFrictionCoefficient
    data.condition = math.max(data.condition - wear, 0)
    -- data.condition = 100
    tyreData[wheelID] = data
end

local function CalculateTyreGrip(wheelID, loadBias, treadCoef)
    local data = tyreData[wheelID]

    local avgTemp = TempRingsToAvgTemp(data.temp, loadBias)

    local tyreGrip = 1
    tyreGrip = tyreGrip * (math.min(data.condition / 97, 1) ^ 3.5 * 0.22 + 0.78)
    -- Grip of tyres with high treadCoef are affected more by temperature change
    local tempDist = math.abs(avgTemp - data.working_temp) ^ treadCoef
    -- Insane calculation to make temps forgiving when around ideal temperature
    -- but linear between 10 and 25 degrees from ideal
    local tempLerpValue = -1 / ((1 + 0.0001 * (-2 + (0.6 * tempDist - 2) ^ 2) ^ 2)) + 1
    tempLerpValue = -1 / (1 + 0.005 * tempDist ^ 2) + 1
    tyreGrip = tyreGrip * lerp(1, 0.9, tempLerpValue)

    -- TODO: Experiment with including a contact patch size based on loadBias
    tyreGripTable[wheelID] = tyreGrip
    return tyreGrip
end

-- This is a special function that runs every frame, and has full access to
-- vehicle data for the current vehicle.
local function updateGFX(dt)
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
            obj:getPosition() + (localVectNode2 + localVectNode1)/2 - wd.radius * vectorWheelUp:normalized(), 0.1
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

            local treadCoef = 1.0 - wheelCache[i].treadCoef * 0.45
            local softnessCoef = wheelCache[i].softnessCoef
            local loadBias = loadBiasSide * 0.22 + (wheelCache[i].camber / 12) * wheelCache[i].wheelDir
            loadBias = sigmoid(loadBias, 50) * 2 - 1

            CalcTyreWear(dt, i, groundModel, loadBias, treadCoef, slipEnergy, propulsionTorque, brakeTorque, load,
                angularVel, brakeTemp, wheelCache[i].width, vehicleAirspeed, deformationEnergy, g_table)


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
                brake_working_temp = 800,
                camber = wheelCache[i].camber * wheelCache[i].wheelDir,
            })
            if condition < 0.1 then
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
M.onVehicleSpawn = onVehicleSpawn

return M
