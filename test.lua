local very_start = os.clock()
local require = require('nsrq')()
local pretty = require './pretty'
local pl = require 'pl.import_into' ()
local util = require './util'
local types = require './test/types'
local continuations = require './test/continuations'
local code_env = require './test/code-env'
local resolve = require './test/resolve'
local parse = require './parse'
local builtins = require './test/setup/builtins'
local treeify = require './test/codegen/treeify'
local generate = require './test/codegen/lua' {
	output = io.write;
	-- output = function() end;
}

require './test/setup'

-- print('----]] Parsing')
local h = io.open('test.lisp', 'r')
local start = os.clock()
local sexps, err = parse('test.lisp', h)
if not sexps then
	error(err)
end
local stop = os.clock()
-- print('parse', stop - start)
h:close()

-- print(pl.pretty.write(sexps))
for _, sexp in ipairs(sexps) do
	-- print(pretty(sexp))
end
-- print()

-- print('----]] Resolving')
local ground = resolve.namespace('ground'); do
	ground.imports[builtins] = true
end
local ks = {n = sexps.n + 1}
for i = 1, sexps.n + 1 do
	ks[i] = continuations.new('test.' .. tostring(i))
end
ks[ks.n].op = { type = 'exit'; }
local nss = {n = sexps.n + 1}
for i = 1, sexps.n + 1 do
	nss[i] = resolve.namespace('test.' .. tostring(i))
	nss[i].imports[ground] = true
end
local jobs = {}
for i, sexp in ipairs(sexps) do
	jobs[i] = resolve.spawn('test.' .. tostring(i), resolve.resolve, ground, sexp, ks[i], ks[i + 1], nss[i], nss[i + 1])
end
local co = util.create_co('test', resolve.run)
local start = os.clock()
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
-- TODO: check uniq_vars
local stop = os.clock()
-- print('resolve', stop - start)

-- print 'digraph {'
-- require './test/graphviz'.pp_k(ks[1])
-- print '}'

-- CODEGEN

local start = os.clock()
local tree = treeify.explore(ks[1], root)
local stop = os.clock()
-- print('explore', stop - start)
-- tree.print('')
local start = os.clock()
io.write [[
local require = require 'nsrq' ()
local extern = require './test/code-env'.extern
local util = require './util'
]]
generate.op(tree)
local stop = os.clock()
-- print('generate', stop - start)
-- print('whole', stop - very_start)
