local nodes = require("vehicleeditor.nodes")

local M = {}

local function sigmoid(x, k)
    local k = k or 10
    return 1 / (1 + k ^ -x)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function getVehWeight() 

end


M.sigmoid = sigmoid
M.lerp = lerp
return M
