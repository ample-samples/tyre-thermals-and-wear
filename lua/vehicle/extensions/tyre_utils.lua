module"tyre_utils"

local M = {}

local function sigmoid(x, k)
    local k = k or 10
    return 1 / (1 + k ^ -x)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function slicksTempToGrip(temp)
		return 0.9467726+0.001128785*temp-0.000006350308*temp^(2)+(3.923052*10^(-9))*temp^(3)
end

local function streetTempToGrip(temp)
	return 0.9817336+0.000429597*temp-0.000002799886*temp^(2)+(3.080513*10^(-9))*temp^(3)
end


M.slicksTempToGrip = slicksTempToGrip
M.streetTempToGrip = streetTempToGrip
M.sigmoid = sigmoid
M.lerp = lerp
return M
