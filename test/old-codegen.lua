local res_names = {}
local var_names = {}
local codegen_k
local function var_name(var)
	if not var_names[var] then var_names[var] = 'v' .. tostring(var):sub(10) end
	return var_names[var]
end
local function res_name(k)
	if not res_names[k] then res_names[k] = 'r' .. tostring(k):sub(10) end
	return res_names[k]
end
local function codegen_k_inner(k)
	if k.op then
		if k.op.type == 'var' then
			if k.op.var.namespace == builtins then
				-- return 'return pass(error \'TODO: builtin: ' .. k.op.var.name .. '\')(' .. codegen_k(k.op.k) .. ')'
				return 'return pass(TODO' .. k.op.var.name .. ')(' .. codegen_k(k.op.k) .. ')'
			else
				if not var_names[k.op.var] then return 'really: ' .. k.op.var.name end
				return 'return pass(' .. var_names[k.op.var] .. ')(' .. codegen_k(k.op.k) .. ')'
			end
		elseif k.op.type == types.reify_i then
			return 'return pass(error \'TODO: reify\')(' .. codegen_k(k.op.k) .. ')'
		elseif k.op.type == 'define' then
			return
				'local ' .. var_name(k.op.var) .. ' = ' .. res_name(k.op.value) .. '[1]; ' ..
				'return pass(' .. var_name(k.op.var) .. ')(' .. codegen_k(k.op.k) .. ')'
		elseif k.op.type == 'apply' then
			local str =
				'local fn = ' .. res_name(k.op.fn) .. '[1]; ' ..
				'assert(fn.type == extern.types.fn_t); ' ..
				'return fn.fn(' .. codegen_k(k.op.k)
			for i = 1, k.op.args.n do
				str = str .. ', util.unpack(' .. res_name(k.op.args[i]) .. ')'
			end
			str = str .. ')'
			return str
		elseif k.op.type == types.lambda_i then
			local str = 'return pass({ type = extern.types.fn_t; fn = function(ret_k'
			for i = 1, k.op.args.n do
				str = str .. ', ' .. var_name(k.op.args[i])
			end
			str = str .. ') return pass()(' .. codegen_k(k.op.entry_k) .. ') end; })(' .. codegen_k(k.op.k) .. ')'
			return str
		elseif k.op.type == types.return_i then
			return 'return ret_k(util.unpack(' .. res_name(k.op.args) .. '))'
		elseif k.op.type == 'str' then
			return 'return pass({ type = extern.types.str_t; value = ' .. ('%q'):format(k.op.str) .. '; })(' .. codegen_k(k.op.k) .. ')'
		else
			error('unhandled operation type: ' .. util.pp_sym(k.op.type))
		end
	else
		return 'return util.unpack(' .. res_name(k) .. ')'
	end
end
function codegen_k(k)
	local str = codegen_k_inner(k)
	return 'function(...) local ' .. res_name(k) .. ' = table.pack(...); ' .. str .. ' end'
end
print('return pass(...)(' .. codegen_k(ks[1]) .. ')')
