local function pretty_fs(fs)
	local str = ''
	while fs do
		if #str > 0 then
			str = str .. ', '
		end
		if fs.type == 'frames/cons' then
			str = str .. 'frame(' .. tostring(fs.head.data) .. ')'
			fs = fs.tail
		elseif fs.type == 'frames/fake' then
			str = str .. 'fake'
			break
		else
			error('bad frames type: ' .. tostring(fs.type))
		end
	end
	return str
end

local function prompt(data, enter, body, exit) return function(k, fs)
	local f = {
		data = data;
		enter = enter;
		exit = exit;
		k = k;
	}
	body(function(fs, ...)
		print('prompt after', pretty_fs(fs))
		if fs.type == 'frames/cons' then
			fs.head.k(fs.tail, ...)
		elseif fs.type == 'frames/fake' then
			fs.k(nil, ...)
		else
			error('bad frames type: ' .. tostring(fs.type))
		end
	end, { type = 'frames/cons'; head = f; tail = fs; })
end end

local function prefix_fs(k, fs)
	if fs then
		if fs.type == 'frames/cons' then
			local f = fs.head
			local f_ = setmetatable({}, {
				__index = function(self, key)
					if key == 'k' then
						return function(fs, ...)
							k({ type = 'frames/cons'; head = f; tail = fs; }, ...)
						end
					else
						return f[key]
					end
				end;
			})
			return { type = 'frames/cons'; head = f_; tail = fs.tail; }
		elseif fs.type == 'frames/fake' then
			return { type = 'frames/fake'; k = function(fs_, ...)
				k(prefix_fs(fs.k, fs_), ...)
			end; }
		else
			error('bad frames type: ' .. tostring(fs.type))
		end
	else
		return { type = 'frames/fake'; k = k; }
	end
end

local function control(i, body) return function(k, fs)
	local fs_outer = fs
	local fs_inner = {}
	for j = 1, i - 1 do
		if not fs_outer or fs_outer.type ~= 'frames/cons' then
			error('not enough frames')
		end
		fs_inner[j] = fs_outer.head
		fs_outer = fs_outer.tail
	end
	fs_inner.n = i - 1
	body(function(...)
		local val = table.pack(...)
		return function(k_, fs)
			fs = prefix_fs(k_, fs)
			for i = fs_inner.n, 1, -1 do
				fs = { type = 'frames/cons'; head = fs_inner[i]; tail = fs; }
			end
			k(fs, table.unpack(val))
		end
	end)(fs_outer.head.k, fs_outer.tail)
end end

local function block(...)
	local parts = table.pack(...)
	return function(k, fs)
		local k_ = function(fs, ...)
			k(fs, table.unpack((select(select('#', ...), ...))))
		end
		for i = parts.n, 1, -1 do
			local k__ = k_
			k_ = function(fs, ...)
				local ress = table.pack(...)
				parts[i](...)(function(fs, ...)
					local res = table.pack(...)
					if ress.n == 0 then
						ress_ = table.pack(res)
					else
						ress_ = table.pack(table.unpack(ress), res)
					end
					k__(fs, table.unpack(ress_))
				end, fs)
			end
		end
		k_(fs)
	end
end

prompt('a',
	function(k, fs)
		print('enter', pretty_fs(fs))
		k(fs)
	end,
	function(k, fs)
		print('inside', pretty_fs(fs))
		control(1, function(cont) return function(k, fs)
			print('escaping', pretty_fs(fs))
			k(fs, cont)
		end end)(k, fs)
	end,
	function(final) return function(k, fs)
		print('exit', final, pretty_fs(fs))
		k(fs)
	end end
)(function(fs, cont)
	print('after', pretty_fs(fs))
	cont(2)(function(fs, ...)
		print('hi', pretty_fs(fs), ...)
	end, fs)
end, nil)
