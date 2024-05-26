M = {}

function vector_cross(v1, v2)

	local result = {
		v1[2]*v2[3] - v1[3]*v2[2],
		v1[3]*v2[1] - v1[1]*v2[3],
		v1[1]*v2[2] - v1[2]*v2[1]
	}
	return vec3(result)
end

M.vector_cross = vector_cross
return M
