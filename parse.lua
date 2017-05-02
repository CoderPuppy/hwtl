local util = require './util'
local xtend = util.xtend
local pl = require 'pl.import_into' ()

local function primitive(t)
	local res = table.pack(coroutine.yield(t))
	if res[1] then
		return table.unpack(res, 2, res.n)
	else
		error(res[2])
	end
end

local function fail(...)
	return primitive {
		type = 'fail';
		data = table.pack(...);
	}
end

local function check(b, ...)
	if b then
	else
		fail(...)
	end
end

local function pull(length)
	return primitive {
		type = 'pull';
		length = length;
	}
end

local function try(fn, ...)
	if type(fn) ~= 'function' then error('expected a function', 2) end
	return primitive {
		type = 'try';
		fn = fn;
		args = table.pack(...);
	}
end

local function lookahead(fn, ...)
	if type(fn) ~= 'function' then error('expected a function', 2) end
	return primitive {
		type = 'lookahead';
		fn = fn;
		args = table.pack(...);
	}
end

local function get_pos()
	return primitive {
		type = 'get_pos';
	}
end

local function get_src()
	return primitive {
		type = 'get_src';
	}
end

local function get_log()
	return primitive {
		type = 'get_log';
	}
end

local function eof()
	if lookahead(pull, 0) then
		local ok, s = lookahead(function()
			local s = ''
			while true do
				local c = try(pull, 1)
				if c then
					s = s .. c
				else
					break
				end
			end
			return s
		end)
		if not ok then
			error 'bad'
		end
		fail(('expected eof got %q'):format(s))
	else
	end
	return true
end

local function negative(f, ...)
	local res = table.pack(lookahead(f, ...))
	if res[1] then
		fail('negative')
	else
		return true, res[2]
	end
end

local function choose(ps)
	for i, p in pairs(ps) do
		if type(p) == 'function' then p = {p} end
		local res = table.pack(try(util.unpack(p)))
		if res[1] then
			return table.unpack(res, 1, res.n)
		end
	end
	fail('no choice matched')
end

local function exact(s)
	local s_ = pull(#s)
	check(s_ == s, ('expected %q got %q'):format(s, s_))
	return s
end

local function oneOf(t)
	for _, s in ipairs(t) do
		if try(exact, s) then
			return s
		end
	end
	local e = ''
	for i, s in ipairs(t) do
		if i ~= 1 then
			e = e .. ', '
		end
		e = e .. ('%q'):format(s)
	end
	fail('expected one of ' .. e)
end

local function noneOf(t)
	for _, s in ipairs(t) do
		if lookahead(exact, s) then
			local e = ''
			for i, s in ipairs(t) do
				if i ~= 1 then
					e = e .. ', '
				end
				e = e .. ('%q'):format(s)
			end
			fail('expected none of ' .. e)
		end
	end
	return true
end

local function remaining()
	local s = ''
	while true do
		local c = try(pull, 1)
		if c then
			s = s .. c
		else
			break
		end
	end
	return s
end

local function dec()
	return oneOf { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }
end

local function hex()
	return oneOf { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'A', 'b', 'B', 'c', 'C', 'd', 'D', 'e', 'E', 'f', 'F' }
end

local expr

local function space()
	choose {
		function() -- line comment
			exact ';'
			while true do
				local c = pull(1)
				if c == '\n' or c == '\r' then
					break
				else
				end
			end
			return true
		end;
		function() -- block comment
			exact '#|'
			local level = 1
			while true do
				if try(exact, '#|') then
					level = level + 1
				elseif try(exact, '|#') then
					level = level - 1
					if level == 0 then
						break
					end
				else
					pull(1)
				end
			end
			return true
		end;
		function() -- expr comment
			exact '#;'
			while try(space) do end
			expr()
			return true
		end;
		table.pack(oneOf, {'\n', '\r', ' ', '\t'});
	}
	return true
end

function expr()
	noneOf { '#;' }
	return choose {
		function() -- list
			local start = get_pos()
			exact '('
			local res = {
				type = 'list';
				pos = {
					type = 'parsed';
					src = get_src();
					start = start;
				};
				n = 0;
			}
			while true do
				local v = try(function()
					while try(space) do end
					return expr()
				end)
				if v then
					res.n = res.n + 1
					res[res.n] = v
				else
					break
				end
			end
			if try(function()
				space()
				while try(space) do end
				exact '.'
				space()
				return true
			end) then
				while try(space) do end
				res.tail = expr()
			end
			while try(space) do end
			exact ')'
			res.pos.stop = get_pos()
			return res
		end;
		function() -- symbol
			local start = get_pos()
			noneOf { '#\'', '#`', ',', '\'', '`', '@' }
			local function char()
				return choose {
					function()
						exact '\\'
						return pull(1)
					end;
					function()
						noneOf {'#|', ';', '(', ')', '[', ']', '{', '}', '\n', '\r', ' ', '\t', '"', '\\'}
						return pull(1)
					end;
				}
			end
			local s = char()
			while true do
				local c = try(char)
				if c then
					s = s .. c
				else
					break
				end
			end
			if s == '.' then fail('not a \'.\'') end
			return {
				type = 'sym';
				name = s;
				pos = {
					type = 'parsed';
					src = get_src();
					start = start;
					stop = get_pos();
				};
			}
		end;
		function() -- prefix
			local start = get_pos()
			local pre = oneOf { '#\'', '#`', '\'', '`', ',', '@' }
			local stop1 = get_pos()
			local e = expr()
			local stop2 = get_pos()
			local src = get_src()
			local name
			if pre == '#\'' then
				name = 'syntax-quote'
			elseif pre == '#`' then
				name = 'syntax-quasiquote'
			elseif pre == '\'' then
				name = 'quote'
			elseif pre == '`' then
				name = 'quasiquote'
			elseif pre == ',' then
				name = 'unquote'
			elseif pre == '@' then
				name = 'splice'
			else
				error('unhandled prefix: ' .. tostring(pre))
			end
			return {
				type = 'list';
				pos = {
					type = 'parsed';
					src = src;
					start = start;
					stop = stop2;
				};
				n = 2;
				{
					type = 'sym';
					pos = {
						type = 'parsed';
						src = src;
						start = start;
						stop = stop1;
					};
					name = name;
				};
				e;
			}
		end;
		function() -- string
			local start = get_pos()
			exact '"'
			local s = ''
			while true do
				local c = try(choose, {
					function() exact '\\n' return '\n' end;
					function() exact '\\r' return '\r' end;
					function() exact '\\t' return '\t' end;
					function() exact '\\"' return '"' end;
					function() exact '\\\\' return '\\' end;
					function() exact '\\ ' return ' ' end;
					function() exact '\\\n'; while try(oneOf, { ' ', '\t' }) do end return '' end;
					function()
						exact '\\x'
						local s = hex() .. hex()
						return string.char(tonumber(s, 16))
					end;
					function()
						exact '\\'
						local s = dec()
						for i = 1, 2 do
							local c = try(dec)
							if c then
								s = s .. c
							else
								break
							end
						end
						return string.char(tonumber(s))
					end;
					function()
						exact '\\u{'
						local u = ''
						while true do
							local c = hex()
							if c then
								u = u .. c
							else
								break
							end
						end
						exact '}'
						return utf8.char(tonumber(u, 16))
					end;
					function()
						noneOf { '\\', '"' }
						return pull(1)
					end;
				})
				if c then
					s = s .. c
				else
					break
				end
			end
			exact '"'
			return {
				type = 'str';
				pos = {
					type = 'parsed';
					src = get_src();
					start = start;
					stop = get_pos();
				};
				str = s;
			}
		end;
		function() -- block string
			local start = get_pos()
			exact '['
			local level = 0
			while try(exact, '=') do
				level = level + 1
			end
			exact '['
			local s = ''
			while true do
				local c = try(function()
					noneOf { ']' .. ('='):rep(level) .. ']' }
					return pull(1)
				end)
				if c then
					s = s .. c
				else
					break
				end
			end
			exact(']' .. ('='):rep(level) .. ']')
			return {
				type = 'str';
				pos = {
					type = 'parsed';
					src = get_src();
					start = start;
					stop = get_pos();
				};
				str = s;
			}
		end;
	}
end

local function main()
	local t = {n = 0}
	while true do
		local v = try(space)
		if not v then break end
	end
	while true do
		local v = try(expr)
		while try(space) do end
		if v then
			t.n = t.n + 1
			t[t.n] = v
		else
			break
		end
	end
	eof()
	return t
end

local function match(opts)
	local pos = xtend({
		lin = 1;
		line = 1;
		col = 1;
		seek = opts.handle:seek 'cur';
	}, opts.pos or {})

	local function create_co(lbl, fn)
		return coroutine.create(function(...)
			return util.reerror('parse: ' .. lbl, fn, ...)
		end);
	end

	local stack = table.pack({
		co = create_co('match', opts.fn);
		log = opts.log and {n = 0; pos = xtend({}, pos);};
		wait = 'init';
		args = opts.args or table.pack();
	})
	local s = 'suspended'
	local done = false
	local ret

	local function exit(ok, ...)
		-- print('exit', ok)
		local frame = stack[stack.n]
		ret = { type = 'exit'; ok = ok; vals = table.pack(...); log = frame.log; }
		if stack.n == 1 then
			done = true
		else
			stack[stack.n] = nil
			stack.n = stack.n - 1
			local frame_ = stack[stack.n]
			if (frame_.wait == 'try' and not ok) or frame_.wait == 'lookahead' then
				pos = xtend({}, frame_.pos)
				frame_.pos = nil
				opts.handle:seek('set', pos.seek)
			end
		end
	end

	while not done and s == 'suspended' do
		local frame = stack[stack.n]
		local args
		if frame.wait == 'init' then
			-- `ok` isn't added here because this isn't wrapped by `primitive`
			args = frame.args
		elseif frame.wait == 'try' then
			if ret.ok then
				args = table.pack(true, table.unpack(ret.vals, 1, ret.vals.n))
			elseif ret.error then
				args = table.pack(false, ret.error)
			else
				args = table.pack(true, false, ret.log)
			end
		elseif frame.wait == 'lookahead' then
			if ret.ok then
				args = table.pack(true, true, table.unpack(ret.vals, 1, ret.vals.n))
			elseif ret.error then
				args = table.pack(false, ret.error)
			else
				args = table.pack(true, false, ret.log)
			end
		elseif frame.wait == 'pull' then
			args = table.pack(true, ret.str)
		elseif frame.wait == 'get_pos' then
			args = table.pack(true, ret.pos)
		elseif frame.wait == 'get_src' then
			args = table.pack(true, ret.src)
		else
			error('unhandled wait: ' .. frame.wait)
		end
		local res = table.pack(coroutine.resume(frame.co, table.unpack(args, 1, args.n)))
		local s = coroutine.status(frame.co)
		if s == 'suspended' then
			local req = res[2]
			-- print('depth', stack.n)
			-- print('req', pl.pretty.write(req))
			-- print('pos', pl.pretty.write(pos))
			-- print('seek', src.handle:seek('cur'))
			if req.type == 'try' then
				stack.n = stack.n + 1
				local frame_ = {
					co = create_co('try', req.fn);
					log = opts.log and {n = 0; pos = xtend({}, pos);};
					wait = 'init';
					args = req.args;
				}
				stack[stack.n] = frame_
				frame.wait = 'try'
				frame.pos = xtend({}, pos)
				if opts.log then
					frame.log.n = frame.log.n + 1
					frame.log[frame.log.n] = {
						type = 'try';
						log = frame_.log;
						pos = xtend({}, pos);
					}
				end
				s = 'suspended'
			elseif req.type == 'lookahead' then
				stack.n = stack.n + 1
				local frame_ = {
					co = create_co('lookahead', req.fn);
					log = opts.log and {n = 0; pos = xtend({}, pos);};
					wait = 'init';
					args = req.args;
				}
				stack[stack.n] = frame_
				frame.wait = 'lookahead'
				frame.pos = xtend({}, pos)
				if opts.log then
					frame.log.n = frame.log.n + 1
					frame.log[frame.log.n] = {
						type = 'lookahead';
						log = frame_.log;
						pos = xtend({}, pos);
					}
				end
				s = 'suspended'
			elseif req.type == 'pull' then
				frame.wait = 'pull'

				local str = opts.handle:read(req.length)
				if opts.log then
					frame.log.n = frame.log.n + 1
					frame.log[frame.log.n] = {
						type = 'pull';
						length = length;
						pos = pos;
					}
					if opts.log_str then
						frame.log[frame.log.n].str = str
					end
				end
				if str then
					-- print('str', ('%q'):format(str))
					local pos_ = xtend({}, pos)
					pos_.seek = opts.handle:seek 'cur'
					local prev
					for c in str:gmatch '.' do
						if c == '\n' or c == '\r' then
							-- this handles CRLF and LFCR
							if (prev ~= '\n' and prev ~= '\r') or prev == c then
								pos_.line = pos_.line + 1
								pos_.col = 1
							end
						else
							pos_.col = pos_.col + 1
						end
						pos_.lin = pos_.lin + 1
						prev = c
					end
					pos = pos_
					ret = { type = 'pull'; str = str; }
				else
					if opts.log then
						frame.log[frame.log.n].fail = true
					end
					exit(false)
				end
			elseif req.type == 'fail' then
				if opts.log then
					frame.log.n = frame.log.n + 1
					frame.log[frame.log.n] = {
						type = 'fail';
						data = req.data;
						pos = xtend({}, pos);
						fail = true;
					}
				end
				exit(false)
			elseif req.type == 'get_pos' then
				if opts.log then
					frame.log.n = frame.log.n + 1
					frame.log[frame.log.n] = {
						type = 'get_pos';
						pos = xtend({}, pos);
					}
				end
				frame.wait = 'get_pos'
				ret = { type = 'get_pos'; pos = xtend({}, pos); }
			elseif req.type == 'get_src' then
				frame.wait = 'get_src'
				ret = { type = 'get_src'; src = opts.src or 'unknown'; }
			else
				error('unhandled req type: ' .. req.type)
			end
		elseif s == 'dead' then
			if res[1] then
				if opts.log then
					frame.log.end_pos = xtend({}, pos)
				end
				exit(true, table.unpack(res, 2, res.n))
			else
				error(res[2])
			end
		else
			error('unhandled status: ' .. s)
		end
	end

	ret.log = nil
	return ret
end

return {
	main = main;
	expr = expr;
	match = match;
}
