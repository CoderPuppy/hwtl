local require = require('nsrq')()
local parse = require './parse'
local parse2 = require './parse2'
local parse3 = require './parse3'
local compile = require './compile'
local resolve = require './resolve'
local pretty = require './pretty'
local pl = require 'pl.import_into' ()

local h = io.open('test.lisp', 'r')
local c = h:read '*a'
h:close()

--[==[
print('----]] Parsing')
local i = 1
local line, col = 1, 1
local src = {
	consume = function(self, pat)
		local res = table.pack(c:match('^(' .. pat .. ')(.*)$', i))
		if res[1] then
			local cr = false
			for c in res[1]:gmatch '.' do
				if c == '\n' then
					if not cr then
						line = line + 1
						col = 1
					end
					cr = false
				elseif c == '\r' then
					cr = true
					line = line + 1
					col = 1
				else
					col = col + 1
				end
			end
			i = i + #res[1]
			if res.n > 2 then
				return table.unpack(res, 2, res.n - 1)
			else
				return res[1]
			end
		end
	end;
	tostring = function(self)
		return tostring(line) .. ':' .. tostring(col) .. ': ' .. ('%q'):format(c:sub(i))
	end;
	try = function(self, f)
		local state = self:state()
		local res, err = f(self)
		if res then
			return res, err
		else
			self:restore_state(state)
			return res, err
		end
	end;
	state = function(self)
		return { i = i; line = line; col = col; }
	end;
	restore_state = function(self, state)
		i = state.i
		line = state.i
		col = state.i
	end;
}
local sexp, err = parse.spaceList(parse.expr)(src)
print(pl.pretty.write(sexp))
for _, err in ipairs(err) do
	print(('%d:%d: %s\n-------------\n%s\n-------------'):format(err.state.line, err.state.col, err.traceback, c:sub(err.state.i)))
end
print(src:tostring())
print('-------------')
for i = 1, sexp.n do
	print(pretty(sexp[i]))
end
print()
-- ]==]

--[==[
print('----]] Resolving')
local env = resolve.env()
table.insert(env.includes, function(name)
	if name == 'hwtl/primitive/unquote' then
	end
end)
local fns = {}
for i = 1, sexp.n do
	fns[i] = function() resolve.resolve(env, sexp[i]) end
end
local co = coroutine.create(function() resolve.parallel(table.unpack(fns, 1, sexp.n)) end)
while coroutine.status(co) == 'suspended' do
	local res = table.pack(coroutine.resume(co))
	if res[1] then
		local s = coroutine.status(co)
		print(s, pl.pretty.write(res))
		if s == 'suspended' then
			error('dead lock')
		else
			error('unhandled status: ' .. s)
		end
	else
		error(res[2])
	end
end
print()
-- ]==]
