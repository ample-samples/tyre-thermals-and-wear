module "tyre_utils"

local M = {}

local function sigmoid(x, k)
	local k = k or 10
	return 1 / (1 + k ^ -x)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function slicksTempToGrip(temp)
	return 0.9467726 + 0.001128785 * temp - 0.000006350308 * temp ^ (2) + (3.923052 * 10 ^ (-9)) * temp ^ (3)
end

local function streetTempToGrip(temp)
	return 0.9817336 + 0.000429597 * temp - 0.000002799886 * temp ^ (2) + (3.080513 * 10 ^ (-9)) * temp ^ (3)
end

local function updateNodeStribeck(currentTyreNode)
	local exampleNode = {
		beamDeform = 43600,
		beamStrength = 78000,
		cid = 586,
		disableMeshBreaking = false,
		dragCoef = 5.85,
		firstGroup = 73,
		frictionCoef = 0.5,
		fullLoadCoef = 0.5,
		loadSensitivitySlope = 0.00012,
		noLoadCoef = 1.36,
		node1 = 442,
		node2 = 441,
		nodeArm = 52,
		nodeMaterial = 2,
		nodeWeight = 0.5,
		ntype = 0,
		padGlazingSusceptibility = 0.7,
		partName = "pickup",
		partOrigin = "pickup_wheeldata_R",
		pos = vec3(0.9525, 1.304076685, 0.5323254513),
		skinName = "brown",
		slidingFrictionCoef = 1,
		softnessCoef = 0.7,
		squealCoefLowSpeed = 0,
		squealCoefNatural = 0,
		torqueCoupling = 47,
		treadCoef = 0.7,
		triangleCollision = false,
		wheelID = 0
	}
	local newTyreNode = {}
	for key, value in pairs(exampleNode) do
		-- newTyreNode[key] = 
	end
	-- obj:setNode(
	--
	-- 		currentTyreNode.cid,
	-- 	currentTyreNode.pos.x,
	-- 	currentTyreNode.pos.y,
	-- 	currentTyreNode.pos.z,
	-- 	currentTyreNode.nodeWeight,
	-- 	currentTyreNode.ntype,
	-- 	currentTyreNode.frictionCoef,
	-- 	currentTyreNode.slidingFrictionCoef,
	-- 	currentTyreNode.stribeckExponent or 1.75,
	-- 	currentTyreNode.stribeckVelMult or 1,
	-- 	currentTyreNode.noLoadCoef,
	-- 	currentTyreNode.fullLoadCoef,
	-- 	currentTyreNode.loadSensitivitySlope,
	-- 	currentTyreNode.softnessCoef or 0.5,
	-- 	currentTyreNode.treadCoef or 0.5,
	-- 	currentTyreNode.tag or '',
	-- 	currentTyreNode.couplerStrength or math.huge,
	-- 	currentTyreNode.firstGroup or -1,
	--
	-- 	currentTyreNode.beamDeform,
	-- 	currentTyreNode.beamStrength,
	-- 	currentTyreNode.cid,
	-- 	currentTyreNode.disableMeshBreaking,
	-- 	currentTyreNode.dragCoef,
	-- 	currentTyreNode.firstGroup,
	-- 	currentTyreNode.frictionCoef,
	-- 	currentTyreNode.fullLoadCoef,
	-- 	currentTyreNode.loadSensitivitySlope,
	-- 	currentTyreNode.noLoadCoef,
	-- 	currentTyreNode.node1,
	-- 	currentTyreNode.node2,
	-- 	currentTyreNode.nodeArm,
	-- 	currentTyreNode.nodeMaterial,
	-- 	currentTyreNode.nodeWeight,
	-- 	currentTyreNode.ntype,
	-- 	currentTyreNode.padGlazingSusceptibility,
	-- 	currentTyreNode.partName,
	-- 	currentTyreNode.partOrigin,
	-- 	currentTyreNode.pos, 1.304076685, 0.5323254513),
	-- 	currentTyreNode.skinName,
	-- 	currentTyreNode.slidingFrictionCoef,
	-- 	currentTyreNode.softnessCoef,
	-- 	currentTyreNode.squealCoefLowSpeed,
	-- 	currentTyreNode.squealCoefNatural,
	-- 	currentTyreNode.torqueCoupling,
	-- 	currentTyreNode.treadCoef,
	-- 	currentTyreNode.triangleCollision,
	-- 	currentTyreNode.wheelID = 0,
	-- 	)
end


M.slicksTempToGrip = slicksTempToGrip
M.streetTempToGrip = streetTempToGrip
M.sigmoid = sigmoid
M.lerp = lerp
return M
