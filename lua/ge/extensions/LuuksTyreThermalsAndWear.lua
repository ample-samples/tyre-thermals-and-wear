local M = {}

function getGroundModels()
    local cmd = "groundModels = {"
    for k, v in pairs(core_environment.groundModels) do
        local name = tostring(k)
        if #name > 0 then
            cmd = cmd .. name .. " = { staticFrictionCoefficient = " .. v.cdata.staticFrictionCoefficient .. ", slidingFrictionCoefficient = " .. v.cdata.slidingFrictionCoefficient .. " }, "
        end
    end
    cmd = cmd .. "debug = 0 };"
    local veh = be:getPlayerVehicle(0)
	if veh then veh:queueLuaCommand(cmd) end
end

M.getGroundModels = getGroundModels

return M
