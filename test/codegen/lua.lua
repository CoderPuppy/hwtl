local types = require '../types'
local treeify = require './treeify'
local util = require '../../util'
local resolve = require '../resolve'

return function(opts)
	local state = {
		indent = '';
		names = {};
		next_anon = 'a';
	}
	local mangle_rules = {
		['_'] = '';
		['/'] = 's';
		['-'] = 't';
		['!'] = 'b';
	}
	local function mangle_name(name)
		return name:gsub('[^a-zA-Z0-9]+', function(s)
			local s_ = ''
			while #s > 0 do
				local found = false
				for match, name in pairs(mangle_rules) do
					if s:find(match, 1, true) then
						s_ = s_ .. '_' .. name .. '_'
						s = s:sub(#match + 1)
						found = true
						break
					end
				end
				if not found then
					s_ = s_ .. '_' .. s:byte() .. '_'
					s = s:sub(2)
				end
			end
			return s_
		end)
	end
	local function uniq_name(name)
		local i = state.names[name]
		if i then
			i = i + 1
			state.names[name] = i
			return i
		else
			state.names[name] = 0
			return 0
		end
	end
	local function gen_anon()
		local name = state.next_anon
		state.next_anon = state.next_anon:gsub('^(.-)([a-y]?)(z*)$', function(pre, head, zs)
			return pre .. (#head == 1 and string.char(head:byte() + 1) or 'a') .. ('a'):rep(#zs)
		end)
		return name
	end
	local k_names = {}
	local function k_name(k)
		if k_names[k] then return k_names[k] end
		local name = gen_anon()
		k_names[k] = name
		return name
	end
	local var_names = {}
	local function var_name(var)
		if var_names[var] then return var_names[var] end
		local name = 'v_' .. mangle_name(var.name)
		name = name .. '_' .. uniq_name(name)
		var_names[var] = name
		return name
	end
	local output = opts.output
	local generate_op, generate_goto, generate_k, generate_k_
	-- TODO: refactor
	-- TODO: fancy stuff with number of values given or expected
	-- TODO: drop stuff (result definitions, pure variables?) when it's not needed
	function generate_k_(tree)
		output('function(...)\n')
		output(state.indent .. '  local r_' .. k_name(tree.k) .. ' = table.pack(...)\n')
		local old_state = state
		state = util.xtend({}, state, {
			indent = state.indent .. '  ';
			names = util.xtend({}, state.names);
		})
		generate_op(tree)
		state = old_state
		output(state.indent .. 'end')
	end
	function generate_k(tree)
		if #tree.use_ins > 1 then
			output('k_' .. k_name(tree.k))
		else
			return generate_k_(tree)
		end
	end
	function generate_goto(tree, ...)
		if #tree.use_ins <= 1 then
			if #tree.k.val_outs > 0 or select('#', ...) > 0 then
				output(state.indent .. 'local r_' .. k_name(tree.k) .. ' = table.pack(')
				for i = 1, select('#', ...) do
					if i ~= 1 then
						output ', '
					end
					output(select(i, ...))
				end
				output ')\n'
			end
			return generate_op(tree)
		else
			output(state.indent .. 'return k_' .. k_name(tree.k) .. '(')
			for i = 1, select('#', ...) do
				if i ~= 1 then
					output ', '
				end
				output(select(i, ...))
			end
			output ')\n'
		end
	end
	local pure_var_depss = {}
	local function pure_var_deps(tree)
		if pure_var_depss[tree] then return pure_var_depss[tree] end
		local deps = {}
		pure_var_depss[tree] = deps
		local queue = {n = 1; tree;}
		while queue.n > 0 do
			local tree_ = util.remove_idx(queue, queue.n)
			if tree_.k.op.type == 'var' and tree_.k.op.var.type == 'pure' then
				deps[tree_.k.op.var] = true
			end
			for child in pairs(tree_.children) do
				util.push(queue, child)
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
			local index = {}
			pure_var_data = {
				mutual_blocks = mutual_blocks;
				index = index;
			}
			pure_var_datas[tree] = pure_var_data
			-- generate a mutual block for each variable
			for child in pairs(tree.children) do
				if child.pure_var then
					local mutual_block = {
						elements = { [child] = true; };
						outs = {};
						ins = {};
						one = true;
					}
					mutual_blocks[mutual_block] = true
					index[child] = mutual_block
					index[child.pure_var] = mutual_block
				end
			end
			-- figure out dependencies between the mutual blocks
			for mutual_block in pairs(mutual_blocks) do
				for tree_ in pairs(mutual_block.elements) do
					for pure_var in pairs(pure_var_deps(tree_)) do
						local mutual_block_ = index[pure_var]
						if mutual_block_ then
							if mutual_block_ == mutual_block then
								mutual_block.self_recursive = true
							else
								mutual_block.outs[mutual_block_] = true
								mutual_block_.ins[mutual_block] = true
							end
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
							for tree_ in pairs(mutual_block_.elements) do
								mutual_block.elements[tree_] = true
								index[tree_] = mutual_block
								index[tree_.pure_var] = mutual_block
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
			-- 	for tree_ in pairs(mutual_block.elements) do
			-- 		print('    ' .. resolve.pp_var(tree_.pure_var))
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
						local tree_ = next(mutual_block.elements)
						if mutual_block.self_recursive then
							output(state.indent .. 'local ' ..
								var_name(tree_.pure_var) .. '_val, ' ..
								var_name(tree_.pure_var) .. '_set\n'
							)
						end
						return generate_op(tree_)
					else
						for tree_ in pairs(mutual_block.elements) do
							output(state.indent .. 'local ' ..
								var_name(tree_.pure_var) .. '_lazy, ' ..
								var_name(tree_.pure_var) .. '_val, ' ..
								var_name(tree_.pure_var) .. '_set, ' ..
								var_name(tree_.pure_var) .. '_started\n'
							)
						end
						for tree_ in pairs(mutual_block.elements) do
							output(state.indent .. var_name(tree_.pure_var) .. '_lazy = function(' .. var_name(tree_.pure_var) .. '_k)\n')
							local old_state = state
							state = util.xtend({}, state, {
								indent = state.indent .. '  ';
								names = util.xtend({}, state.names);
							})
							output(state.indent .. 'if ' .. var_name(tree_.pure_var) .. '_set then ' ..
								'return ' .. var_name(tree_.pure_var) .. '_k(' .. var_name(tree_.pure_var) .. '_val) ' ..
							'end\n')
							output(state.indent .. 'if ' .. var_name(tree_.pure_var) .. '_started then error \'bad\' end\n')
							output(state.indent .. var_name(tree_.pure_var) .. '_started = true\n')
							generate_op(tree_)
							state = old_state
							output(state.indent .. 'end\n')
						end
					end
				until true
			end
			if all_built then break end
		end
		if tree.k.op.type == 'define' and tree.k.op.var.type == 'pure' then
			local var_tree = treeify.get(tree.k.op.var.in_k)
			local par_tree = var_tree.parent
			local mutual_block = pure_var_datas[par_tree].index[tree.k.op.var]
			if not mutual_block.one or mutual_block.self_recursive then
				output(state.indent .. 'if ' .. var_name(tree.k.op.var) .. '_set then error \'bad\' end\n')
				output(state.indent .. var_name(tree.k.op.var) .. '_val = r_' .. k_name(tree.k) .. '[1]\n')
				output(state.indent .. var_name(tree.k.op.var) .. '_set = true\n')
			elseif mutual_block.one then
				output(state.indent .. 'local ' .. var_name(tree.k.op.var) .. ' = r_' .. k_name(tree.k) .. '[1]\n')
			end
			if mutual_block.one then
				return generate_op(par_tree)
			else
				output(state.indent .. 'return ' .. var_name(tree.k.op.var) .. '_k(' .. var_name(tree.k.op.var) .. '_val)\n')
				return
			end
		end

		for child in pairs(tree.children) do
			if not child.pure_var and #child.use_ins > 1 then
				output(state.indent .. 'local k_' .. k_name(child.k) .. '\n')
			end
		end
		for child in pairs(tree.children) do
			if not child.pure_var and #child.use_ins > 1 then
				output(state.indent .. 'k_' .. k_name(child.k) .. ' = ')
				generate_k_(child)
				output '\n'
			end
		end

		if tree.k.op.type == types.lua_i then
			local deindent = tree.k.op.str:match '^%s*'
			local str = ''
			local first = true
			for line in (tree.k.op.str .. '\n'):gsub('\r\n', '\n'):gsub('\n\r', '\n'):gmatch '([^\n\r]*)[\n\r]' do
				if not first then
					str = str .. state.indent
				end
				str = str .. line:gsub('^' .. deindent, ''):gsub('\t', '  ') .. '\n'
				first = false
			end
			str = str:gsub('%s*$', '')
			return generate_goto(treeify.get(tree.k.op.k), str)
		elseif tree.k.op.type == 'var' then
			if #tree.k.op.k.val_outs > 0 then
				local mutual_block = tree.k.op.var.type == 'pure' and pure_var_datas[treeify.get(tree.k.op.var.in_k).parent].index[tree.k.op.var]
				if tree.k.op.var.type == 'pure' and not mutual_block.one then
					output(state.indent .. 'return ' .. var_name(tree.k.op.var) .. '_lazy(function(...)\n')
					local old_state = state
					state = util.xtend({}, state, {
						indent = state.indent .. '  ';
						names = util.xtend({}, state.names);
					})
					generate_goto(treeify.get(tree.k.op.k), var_name(tree.k.op.var) .. '_val')
					state = old_state
					output(state.indent .. 'end)\n')
				elseif tree.k.op.var.type == 'pure' and mutual_block.one and mutual_block.self_recursive then
					output(state.indent .. 'assert(' .. var_name(tree.k.op.var) .. '_set)\n')
					return generate_goto(treeify.get(tree.k.op.k), var_name(tree.k.op.var) .. '_val')
				else
					return generate_goto(treeify.get(tree.k.op.k), var_name(tree.k.op.var))
				end
			else
				return generate_goto(treeify.get(tree.k.op.k))
			end
		elseif tree.k.op.type == 'if' then
			output(state.indent .. 'if util.assert_type(r_' .. k_name(tree.k.op.cond) .. '[1], extern.types.bool_t, \'if condition\').value then\n')
			local old_state = state
			state = util.xtend({}, state, {
				indent = state.indent .. '  ';
				names = util.xtend({}, state.names);
			})
			generate_goto(treeify.get(tree.k.op.true_k))
			state = old_state
			output(state.indent .. 'else\n')
			local old_state = state
			state = util.xtend({}, state, {
				indent = state.indent .. '  ';
				names = util.xtend({}, state.names);
			})
			generate_goto(treeify.get(tree.k.op.false_k))
			state = old_state
			output(state.indent .. 'end\n')
		elseif tree.k.op.type == 'str' then
			return generate_goto(treeify.get(tree.k.op.k), '{ type = extern.types.str_t; value = ' .. ('%q'):format(tree.k.op.str):gsub('\\\n', '\\n') .. '; }')
		elseif tree.k.op.type == 'apply' then
			output(state.indent .. 'return r_' .. k_name(tree.k.op.fn) .. '[1].fn(')
			generate_k(treeify.get(tree.k.op.k))
			for _, arg in ipairs(tree.k.op.args) do
				output(', util.unpack(r_' .. k_name(arg) .. ')')
			end
			output(')\n')
		elseif tree.k.op.type == 'exit' then
			output(state.indent .. 'return\n')
		elseif tree.k.op.type == 'define' then
			output(state.indent .. 'local ' .. var_name(tree.k.op.var) .. ' = r_' .. k_name(tree.k.op.value) .. '[1]\n')
			return generate_goto(treeify.get(tree.k.op.k), var_name(tree.k.op.var))
		elseif tree.k.op.type == types.return_i then
			output(state.indent .. 'return ret_' .. k_name(tree.k.op.lambda) .. '(util.unpack(r_' .. k_name(tree.k.op.args) .. '))\n')
		elseif tree.k.op.type == types.lambda_i then
			local str = ''
			local old_output = output
			output = function(str_)
				str = str .. str_
			end
			local old_state = state
			state = util.xtend({}, state, {
				indent = state.indent .. '  ';
				names = util.xtend({}, state.names);
			})
			output('{ type = extern.types.fn_t; fn = function(ret_' .. k_name(tree.k))
			for i, arg in ipairs(tree.k.op.args) do
				output(', ' .. var_name(arg))
			end
			if tree.k.op.args.tail then
				output ', ...'
			end
			output(')\n')
			if tree.k.op.args.tail then
				output(state.indent .. 'local ' .. var_name(tree.k.op.args.tail) .. ' = table.pack(...)\n')
				output(state.indent .. var_name(tree.k.op.args.tail) .. '.type = extern.types.list_t\n')
			end
			generate_op(treeify.get(tree.k.op.entry_k))
			output(old_state.indent .. 'end; }')
			output = old_output
			state = old_state
			return generate_goto(treeify.get(tree.k.op.k), str)
		else
			error('unhandled operation type: ' .. util.pp_sym(tree.k.op.type))
		end
	end

	return {
		k = generate_k;
		goto_ = generate_goto;
		op = generate_op;
	}
end
