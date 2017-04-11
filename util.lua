local function append(t, ...)
	for i = 1, select('#', ...) do
		for _, e in ipairs(select(i, ...)) do
			t.n = t.n + 1
			t[t.n] = e
		end
	end
	return t
end

local function concat(...)
	local t = {n = 0;}
	append(t, ...)
	return t
end

local function xtend(t, ...)
	for i = 1, select('#', ...) do
		for k, v in pairs(select(i, ...)) do
			t[k] = v
		end
	end
	return t
end

local function unpack(t, i, j)
	return table.unpack(t, i or 1, j or t.n or #t)
end

return {
	concat = concat;
	append = append;
	xtend = xtend;
	unpack = unpack;
}
