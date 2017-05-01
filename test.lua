local require = require('nsrq')()
local pretty = require './pretty'
local pl = require 'pl.import_into' ()
local util = require './util'

-- print('----]] Parsing')
local h = io.open('test.lisp', 'r')
local parse = require './parse'
local res = parse.match {
	handle = h;
	src ='test.lisp';
	fn = parse.main;
	args = table.pack('hi');
}
h:close()
local sexps = res.vals[1]

-- print(pl.pretty.write(res))
for _, sexp in ipairs(sexps) do
	-- print(pretty(sexp))
end
-- print()

require './test/setup'

local types = require './test/types'
local continuations = require './test/continuations'
local code_env = require './test/code-env'
local resolve = require './test/resolve'

-- print('----]] Resolving')
local builtins = require './test/setup/builtins'
local ground = resolve.namespace('ground'); do
	ground.add_entry(function(name, complete_ref)
		return resolve.resolve_var(builtins, name, complete_ref)
	end)
end
local ks = {n = sexps.n + 1}
for i = 1, sexps.n + 1 do
	ks[i] = continuations.new('test.' .. tostring(i))
end
ks[ks.n].op = { type = 'exit'; }
local nss = {n = sexps.n + 1}
for i = 1, sexps.n + 1 do
	nss[i] = resolve.namespace('test.' .. tostring(i))
	nss[i].add_entry(function(name, complete_ref)
		return resolve.resolve_var(ground, name, complete_ref)
	end)
end
local jobs = {}
for i, sexp in ipairs(sexps) do
	jobs[i] = resolve.spawn('test.' .. tostring(i), resolve.resolve, ground, sexp, ks[i], ks[i + 1], nss[i], nss[i + 1])
end
local co = util.create_co('test', resolve.run)
while true do
	local res = table.pack(coroutine.resume(co))
	local s = coroutine.status(co)
	if s == 'suspended' then
		error('unhandled cmd type: ' .. res[2].type)
	elseif s == 'dead' then
		if res[1] then
			break
		else
			error(res[2])
		end
	else
		error('unhandled status: ' .. s)
	end
end
