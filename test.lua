local require = require('nsrq')()
local parse = require './parse'
local parse2 = require './parse2'
local parse3 = require './parse3'
local compile = require './compile'
local resolve = require './resolve' {}
local pretty = require './pretty'
local pl = require 'pl.import_into' ()
local util = require './util'

-- --[==[
print('----]] Parsing')
local h = io.open('test.lisp', 'r')
local res = parse3.match {
	handle = h;
	src ='test.lisp';
	fn = parse3.main;
	args = table.pack('hi');
}
h:close()
local sexps = res.vals[1]

print(pl.pretty.write(res))
for _, sexp in ipairs(sexps) do
	print(pretty(sexp))
end
print()
-- ]==]

-- --[==[
print('----]] Resolving')
local env = resolve.namespace('env')
local builtins = resolve.block('builtins'); do
	table.insert(builtins.namespace.entries, {
		type = 'define';
		name = 'define';
		var = {
			name = 'define';
			block = builtins;
			mutable = false;
		};
	})
end
table.insert(env.entries, {
	type = 'namespace';
	namespace = builtins.namespace;
	here = { pre = ''; post = ''; };
	there = { pre = ''; post = ''; };
})
print('builtins', tostring(builtins.namespace))
print('env', tostring(env))
local co = coroutine.create(function()
	return resolve.parallel(util.unpack(util.map(function(sexp)
		return table.pack(resolve.resolve, env, sexp)
	end)(sexps)))
end)
local uniq_vars = setmetatable({}, {
	__index = function(self, namespace)
		local data = {}
		local t = setmetatable({}, {
			__index = data;
			__newindex = function(_, name, var)
				if data[name] and data[name] ~= var then
					error 'bad'
				else
					data[name] = var
				end
			end;
		})
		rawset(self, namespace, t)
		return t
	end;
})
while coroutine.status(co) == 'suspended' do
	local res = table.pack(coroutine.resume(co))
	if res[1] then
		local s = coroutine.status(co)
		if s == 'suspended' then
			local cmd = res[2]
			print('outer: cmd', resolve.pp_cmd(cmd))
			if cmd.type == 'wait' then
				error('dead lock')
			elseif cmd.type == 'uniq_var' then
				uniq_vars[cmd.namespace][cmd.name] = cmd.var
			else
				error('unhandled cmd type: ' .. cmd.type)
			end
		elseif s == 'dead' then
			print('outer: dead', pl.pretty.write(res))
		else
			error('unhandled status: ' .. s)
		end
	else
		error(res[2])
	end
end
print()
-- ]==]
