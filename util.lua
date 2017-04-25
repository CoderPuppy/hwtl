local pl = require 'pl.import_into' ()

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
	if type(t) ~= 'table' then print(debug.traceback('not a table')) end
	return table.unpack(t, i or 1, j or t.n or #t)
end

local function map(fn)
	return function(...)
		local arrs = table.pack(...)
		local res = {n = 0}
		local i = 1
		while true do
			local args = {n = arrs.n}
			for j, arr in ipairs(arrs) do
				if i > (arr.n or #arr) then
					return res
				end
				args[j] = arr[i]
			end
			res.n = res.n + 1
			res[i] = fn(unpack(args))
			i = i + 1
		end
		return res
	end
end

local _ = {}

local function cut(...)
	local pat = table.pack(...)
	return function(...)
		local args = table.pack(...)
		local args_ = {n = pat.n}
		local j = 1
		for i = 1, pat.n do
			if pat[i] == _ then
				args_[i] = args[j]
				j = j + 1
			else
				args_[i] = pat[i]
			end
		end
		return args_[1](table.unpack(args_, 2, args_.n))
	end
end

local function map_message(map, fn, ...)
	local res = table.pack(pcall(fn, ...))
	if res[1] then
		return table.unpack(res, 2, res.n)
	else
		error(map(res[2]))
	end
end

local function reerror(lbl, fn, ...)
	local res = table.pack(xpcall(fn, function(msg)
		local i = 3
		local n = 0
		while n < 2 do
			local _, msg_ = pcall(error, '@', i)
			if msg_ == '@' then
				n = n + 1
			else
				n = 0
			end
			msg = msg .. '\n  ' .. msg_
			i = i + 1
		end
		msg = msg .. '\n  <reerror: ' .. lbl .. '>'
		return msg
	end, ...))
	if res[1] then
		return table.unpack(res, 2, res.n)
	else
		error(res[2])
	end
end

local function create_co(lbl, fn)
	local trace = debug.traceback()
	if type(fn) == 'function' then fn = {fn} end
	return coroutine.create(function()
		return map_message(function(msg)
			return msg .. '\n  <create_co>\n' .. trace:gsub('^stack traceback:\n', ''):gsub('\t', '    ')
		end, reerror, 'create_co: ' .. lbl, unpack(fn))
	end)
end

local function push(tbl, ...)
	for i = 1, select('#', ...) do
		tbl[tbl.n + i] = select(i, ...)
	end
	tbl.n = tbl.n + select('#', ...)
	return tbl
end

local function remove_idx(tbl, i)
	tbl.n = tbl.n - 1
	for i = i, tbl.n do
		tbl[i] = tbl[i + 1]
	end
	tbl[tbl.n + 1] = nil
end

local function pp_sym(sym)
	local t = type(sym)
	if t == 'string' then
		return sym
	elseif t == 'table' and sym.name then
		return '#' .. pp_sym(sym.name)
	else
		error('unhandled sym type: ' .. t)
	end
end

return {
	concat = concat;
	append = append;
	xtend = xtend;
	unpack = unpack;
	map = map;
	cut = cut;
	_ = _;
	map_message = map_message;
	reerror = reerror;
	create_co = create_co;
	push = push;
	remove_idx = remove_idx;
	pp_sym = pp_sym;
}
