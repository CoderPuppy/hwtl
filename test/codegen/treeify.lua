local types = require '../types'
local rules = require '../rules'
local util = require '../../util'
local resolve = require '../resolve'

-- TODO: make this support all codegen not just continuations

local trees_k = setmetatable({}, { __mode = 'kv'; })

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
	assert(eq and not trees[1].parent.parent)
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
			level = parent and parent.level + 1 or 0;
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
		function tree.print(indent)
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
				child.print(indent .. '    ')
			end
		end
		if parent then
			parent.use_outs[tree] = true
			tree.use_ins[parent] = true
			parent.children[tree] = true
		end
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
		(rules.treeify_rules[k.op.type] or error('unhandled operation type: ' .. util.pp_sym(k.op.type)))(tree)
	end
	return tree
end

local function tree_k(k)
	return assert(trees_k[k])
end

return {
	get = function(k) return assert(trees_k[k]) end;
	ensure_inside = ensure_inside;
	deepest_common_ancestor = deepest_common_ancestor;
	move = move;
	ensure_accessible = ensure_accessible;
	explore = explore_k;
}
