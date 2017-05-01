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

-- print 'digraph {'
-- require './test/graphviz'.pp_k(ks[1])
-- print '}'

-- CODEGEN

local trees_k = {}

local function ensure_inside(i, o)
	if trees_k[o] then o = trees_k[o] end
	if not i or i.flow_outs then error 'TODO: i' end
	if not o or o.flow_outs then error 'TODO: o' end
	if i == o then return end
	i.inside[o] = true
	local ok, res
	if i.parent then
		ok, res = pcall(ensure_inside, i.parent, o)
	else
		ok = false
	end
	if not ok then
		local msg = 'codegen: ' .. i.name .. ' isn\'t inside ' .. o.name
		if res then
			msg = res .. '\n  ' .. msg
		end
		error(msg)
	end
end

local function deepest_common_ancestor(...)
	assert(select('#', ...) > 0)
	local level = 0
	local trees = { n = select('#', ...); }
	for i = 1, trees.n do
		trees[i] = select(i, ...)
		level = math.max(level, trees[i].level)
	end
	while level > 0 do
		local eq = true
		for i = 2, trees.n do
			if trees[i] ~= trees[1] then
				eq = false
				break
			end
		end
		if eq then
			return trees[1]
		end
		for i = 1, trees.n do
			if trees[i].level == level then
				trees[i] = trees[i].parent
			end
		end
		level = level - 1
	end
	local eq = true
	for i = 2, trees.n do
		if trees[i].parent ~= trees[1].parent then
			eq = false
			break
		end
	end
	assert(eq and trees[1].parent.root)
	return trees[1].parent
end

local function move(child, parent)
	if child.parent == parent then return end
	for inside in pairs(child.inside) do
		ensure_inside(parent, inside)
	end
	child.parent.children[child] = nil
	child.parent = parent
	child.level = parent.level + 1
	parent.children[child] = true
end

local function ensure_accessible(accessee, accessor)
	-- TODO: I don't fully understand this code
	local ancestor = deepest_common_ancestor(accessee.parent, accessor)
	do
		local tree_ = accessor
		while tree_ ~= ancestor do
			accessee.use_ins[tree_] = true
			tree_.use_outs[accessee] = true
			tree_ = tree_.parent
		end
	end
	if ancestor ~= accessee.parent then
		move(accessee, ancestor)
		local new_uses = {}
		for use in pairs(accessee.use_ins) do
			local tree_ = use
			while tree_ ~= ancestor do
				tree_.use_outs[accessee] = true
				new_uses[tree_] = true
				tree_ = tree_.parent
			end
		end
		for use in pairs(new_uses) do
			accessee.use_ins[use] = true
		end
		for use in pairs(accessee.use_outs) do
			ensure_accessible(use, accessee)
		end
	end
end

local function explore_k(k, parent)
	assert(k)
	local tree = trees_k[k]
	if tree then
		ensure_accessible(tree, parent)
	else
		tree = {
			name = k.name;
			k = k;
			parent = parent;
			level = parent.level + 1;
			inside = {};
			children = {};
			use_outs = setmetatable({}, {
				__len = function(self)
					local n = 0
					for use in pairs(self) do
						n = n + 1
					end
					return n
				end;
			});
			use_ins = setmetatable({}, {
				__len = function(self)
					local n = 0
					for use in pairs(self) do
						n = n + 1
					end
					return n
				end;
			});
		}
		parent.use_outs[tree] = true
		tree.use_ins[parent] = true
		parent.children[tree] = true
		trees_k[k] = tree
		if not k.op then
			error('unbuilt continuation: ' .. k.name)
		end
		for out_k, link in pairs(k.flow_outs) do
			explore_k(out_k, tree)
		end
		for in_k, link in pairs(k.val_ins) do
			ensure_inside(tree, in_k)
		end
		if k.op.type == 'var' then
			if k.op.var.intro_k then
				ensure_inside(tree, k.op.var.intro_k)
			end
			if k.op.var.type == 'pure' then
				explore_k(k.op.var.in_k, tree).pure_var = k.op.var
			end
		elseif k.op.type == 'if' then
		elseif k.op.type == 'str' then
		elseif k.op.type == 'apply' then
		elseif k.op.type == 'exit' then
		elseif k.op.type == types.lua_i then
		elseif k.op.type == 'define' then
			if k.op.var.type == 'pure' then
				ensure_inside(tree, k.op.var.in_k)
			end
		else
			error('unhandled operation type: ' .. util.pp_sym(k.op.type))
		end
	end
	return tree
end
local function tree_k(k)
	return assert(trees_k[k])
end
local root = {
	root = true;
	name = 'root';
	level = 0;
	inside = {};
	children = {};
	use_outs = setmetatable({}, {
		__len = function(self)
			local n = 0
			for use in pairs(self) do
				n = n + 1
			end
			return n
		end;
	});
	use_ins = setmetatable({}, {
		__len = function(self)
			local n = 0
			for use in pairs(self) do
				n = n + 1
			end
			return n
		end;
	});
}
local tree = explore_k(ks[1], root)
local function print_tree(tree, indent)
	print(indent .. '- ' .. tree.name)
	print(indent .. '  op: ' .. util.pp_sym(tree.k.op.type))
	if tree.pure_var then
		print(indent .. '  pure variable: ' .. resolve.pp_var(tree.pure_var))
	end
	if tree.k.op.type == 'var' then
		print(indent .. '  variable: ' .. resolve.pp_var(tree.k.op.var))
	end
	print(indent .. '  children:')
	for child in pairs(tree.children) do
		print_tree(child, indent .. '    ')
	end
end
print_tree(tree, '')
local state = {
	indent = '';
	names = {};
}
local generate_op, generate_goto, generate_k, generate_k_
function generate_k_(tree)
	print('function(...)')
	print(state.indent .. '  local r<id> = table.pack(...)')
	local old_state = state
	state = util.xtend({}, state, {
		indent = state.indent .. '  ';
	})
	generate_op(tree)
	state = old_state
	io.write(state.indent .. 'end')
end
function generate_k(tree)
	if #tree.use_ins > 1 then
		io.write('k<id>')
	else
		generate_k_(tree)
	end
end
function generate_goto(tree, ...)
	if #tree.use_ins <= 1 then
		io.write(state.indent .. 'local r<id> = table.pack(')
		for i = 1, select('#', ...) do
			if i ~= 1 then
				io.write ', '
			end
			io.write(select(i, ...))
		end
		print ')'
		generate_op(tree)
	else
		io.write(state.indent .. 'return k<id>(')
		for i = 1, select('#', ...) do
			if i ~= 1 then
				io.write ', '
			end
			io.write(select(i, ...))
		end
		print ')'
	end
end
local pure_var_depss = {}
local function pure_var_deps(pure_var)
	if pure_var_depss[pure_var] then return pure_var_depss[pure_var] end
	local deps = {}
	pure_var_depss[pure_var] = deps
	local done = {}
	local queue = {n = 1; pure_var.in_k;}
	while queue.n > 0 do
		local k = util.remove_idx(queue, queue.n)
		for out_k in pairs(k.flow_outs) do
			if not done[out_k] then
				util.push(queue, out_k)
				done[out_k] = true
			end
		end
		if k.op.type == 'var' and k.op.var.type == 'pure' then
			deps[k.op.var] = true
		end
	end
	return deps
end
local pure_var_datas = {}
function generate_op(tree)
	-- TODO: handle references to mutable variables (by duplicating the definition)
	local pure_var_data = pure_var_datas[tree]
	if not pure_var_data then
		-- split the variables into mutually dependent subsets (called mutual blocks)
		local mutual_blocks = {}
		local pure_vars = {}
		pure_var_data = {
			mutual_blocks = mutual_blocks;
			pure_vars = pure_vars;
		}
		pure_var_datas[tree] = pure_var_data
		-- generate a mutual block for each variable
		for child in pairs(tree.children) do
			if child.pure_var then
				local mutual_block = {
					elements = { [child.pure_var] = true; };
					outs = {};
					ins = {};
					one = true;
				}
				mutual_blocks[mutual_block] = true
				pure_vars[child.pure_var] = mutual_block
			end
		end
		-- figure out dependencies between the mutual blocks
		for mutual_block in pairs(mutual_blocks) do
			for pure_var in pairs(mutual_block.elements) do
				for pure_var_ in pairs(pure_var_deps(pure_var)) do
					local mutual_block_ = pure_vars[pure_var_]
					if mutual_block_ then
						mutual_block.outs[mutual_block_] = true
						mutual_block_.ins[mutual_block] = true
					end
				end
			end
		end
		-- merge mutual dependent mutual blocks
		while true do
			local work = false
			for mutual_block in pairs(mutual_blocks) do
				for mutual_block_ in pairs(mutual_block.outs) do
					if mutual_block.ins[mutual_block_] then
						mutual_block.ins[mutual_block_] = nil
						mutual_block.outs[mutual_block_] = nil
						mutual_block_.ins[mutual_block] = nil
						mutual_block_.outs[mutual_block] = nil
						mutual_blocks[mutual_block_] = nil
						for pure_var in pairs(mutual_block_.elements) do
							mutual_block.elements[pure_var] = true
							pure_vars[pure_var] = mutual_block
						end
						for mutual_block__ in pairs(mutual_block_.outs) do
							mutual_block.outs[mutual_block__] = true
							mutual_block__.ins[mutual_block_] = nil
							mutual_block__.ins[mutual_block] = true
						end
						for mutual_block__ in pairs(mutual_block_.ins) do
							mutual_block.ins[mutual_block__] = true
							mutual_block__.outs[mutual_block_] = nil
							mutual_block__.outs[mutual_block] = true
						end
						mutual_block.one = false
						work = true
						break
					end
				end
				if work then break end
			end
			if not work then break end
		end
		-- for mutual_block in pairs(mutual_blocks) do
		-- 	print(mutual_block)
		-- 	if mutual_block.one then
		-- 		print('  one')
		-- 	end
		-- 	print('  elements:')
		-- 	for pure_var in pairs(mutual_block.elements) do
		-- 		print('    ' .. resolve.pp_var(pure_var))
		-- 	end
		-- 	print('  dependencies:')
		-- 	for dep in pairs(mutual_block.outs) do
		-- 		print('    ' .. tostring(dep))
		-- 	end
		-- end
	end
	while true do
		local all_built = true
		for mutual_block in pairs(pure_var_data.mutual_blocks) do
			repeat
				-- generate mutual blocks if they haven't been built yet and all their dependencies have been
				if mutual_block.built then break end
				local all_deps = true
				for dep in pairs(mutual_block.outs) do
					if not dep.built then
						all_deps = false
						break
					end
				end
				if not all_deps then
					all_built = false
					break
				end

				mutual_block.built = true
				if mutual_block.one then
					return generate_op(tree_k(next(mutual_block.elements).in_k))
				else
					for pure_var in pairs(mutual_block.elements) do
						print(state.indent .. 'local ' .. pure_var.name .. '_lazy, ' .. pure_var.name .. '_val, ' .. pure_var.name .. '_set, ' .. pure_var.name .. '_started')
					end
					for pure_var in pairs(mutual_block.elements) do
						print(state.indent .. pure_var.name .. '_lazy = function(k)')
						local old_state = state
						state = util.xtend({}, state, {
							indent = state.indent .. '  ';
						})
						print(state.indent .. 'if ' .. pure_var.name .. '_started then error \'bad\' end')
						print(state.indent .. pure_var.name .. '_started = true')
						generate_op(tree_k(pure_var.in_k))
						state = old_state
						print(state.indent .. 'end')
					end
				end
			until true
		end
		if all_built then break end
	end
	if tree.k.op.type == 'define' and tree.k.op.var.type == 'pure' then
		local var_tree = tree_k(tree.k.op.var.in_k)
		local par_tree = var_tree.parent
		local mutual_block = pure_var_datas[par_tree].pure_vars[tree.k.op.var]
		if mutual_block.one then
			print(state.indent .. 'local ' .. tree.k.op.var.name .. ' = r<id>')
			return generate_op(par_tree)
		else
			print(state.indent .. 'if ' .. tree.k.op.var.name .. '_set then error \'bad\' end')
			print(state.indent .. tree.k.op.var.name .. '_val = r<id>')
			print(state.indent .. tree.k.op.var.name .. '_set = true')
			print(state.indent .. 'return ' .. tree.k.op.var.name .. '_k(' .. tree.k.op.var.name .. '_val)')
			return
		end
	end

	for child in pairs(tree.children) do
		if not child.pure_var and #child.use_ins > 1 then
			io.write(state.indent .. 'local k<id> = ')
			generate_k_(child)
			print()
		end
	end

	if tree.k.op.type == types.lua_i then
		local deindent = tree.k.op.str:match '^%s*'
		local str = ''
		local first = true
		for line in tree.k.op.str:gsub('\r\n', '\n'):gsub('\n\r', '\n'):gmatch '([^\n\r]*)[\n\r]' do
			if not first then
				str = str .. state.indent
			end
			str = str .. line:gsub('^' .. deindent, ''):gsub('\t', '  ') .. '\n'
			first = false
		end
		str = str:sub(1, -2)
		generate_goto(tree_k(tree.k.op.k), 'lua')
	elseif tree.k.op.type == 'var' then
		if tree.k.op.var.type == 'pure' and not pure_var_datas[tree_k(tree.k.op.var.in_k).parent].pure_vars[tree.k.op.var].one then
			print(state.indent .. 'return ' .. tree.k.op.var.name .. '_lazy(function(...)')
			local old_state = state
			state = util.xtend({}, state, {
				indent = state.indent .. '  ';
			})
			generate_goto(tree_k(tree.k.op.k), tree.k.op.var.name .. '_val')
			state = old_state
			print(state.indent .. 'end)')
		else
			generate_goto(tree_k(tree.k.op.k), tree.k.op.var.name)
		end
	elseif tree.k.op.type == 'if' then
		local old_state = state
		state = util.xtend({}, state, {
			indent = state.indent .. '  ';
		})
		print(old_state.indent .. 'if r<id>[1] then')
		generate_goto(tree_k(tree.k.op.true_k))
		print(old_state.indent .. 'else')
		generate_goto(tree_k(tree.k.op.false_k))
		print(old_state.indent .. 'end')
		state = old_state
	elseif tree.k.op.type == 'str' then
		generate_goto(tree_k(tree.k.op.k), ('%q'):format(tree.k.op.str):gsub('\\\n', '\\n'))
	elseif tree.k.op.type == 'apply' then
		io.write(state.indent .. 'return r<id>[1](')
		generate_k(tree_k(tree.k.op.k))
		for _, arg in ipairs(tree.k.op.args) do
			io.write(', r<id>')
		end
		print(')')
	elseif tree.k.op.type == 'exit' then
		print(state.indent .. 'return')
	elseif tree.k.op.type == 'define' then
		print(state.indent .. 'local ' .. tree.k.op.var.name .. ' = r<id>[1]')
		generate_goto(tree_k(tree.k.op.k), tree.k.op.var.name)
	else
		error('unhandled operation type: ' .. util.pp_sym(tree.k.op.type))
	end
end
generate_op(tree)
