local resolve = require './resolve'
local util = require '../util'
local types = require './types'

local graphviz = {}

function graphviz.pp_node(id, attrs)
	io.write('"' .. id .. '" [')
	local first = true
	for k, v in pairs(attrs) do
		if not first then
			io.write ', '
		end
		io.write(k .. '=' .. v)
		first = false
	end
	io.write '];'
	print()
	return id
end
function graphviz.pp_edge(id1, id2, attrs)
	io.write('"' .. id1 .. '" -> "' .. id2 .. '" [')
	local first = true
	for k, v in pairs(attrs) do
		if not first then
			io.write ', '
		end
		io.write(k .. '=' .. v)
		first = false
	end
	io.write '];'
	print()
end

local pp_ks = {}
local pp_vars = {}
function graphviz.pp_var(var)
	local id = tostring(var)
	if pp_vars[var] then return id end
	pp_vars[var] = true
	local attrs = {}

	attrs.label = '"var(ns = ' .. var.namespace.name .. ', name = ' .. var.name .. ', type = ' .. var.type .. ')"'

	if var.type == 'arg' then
		graphviz.pp_edge(id, graphviz.pp_k(var.intro_k), { label = '"intro k"' })
	else
		graphviz.pp_edge(id, graphviz.pp_k(var.in_k), { label = '"in k"' })
		graphviz.pp_edge(id, graphviz.pp_k(var.out_k), { label = '"out k"' })
	end

	return graphviz.pp_node(id, attrs)
end
function graphviz.pp_k(k)
	local id = tostring(k)
	if pp_ks[k] then return id end
	pp_ks[k] = true
	local attrs = {}

	if k.op then
		if k.op.type == 'var' then
			attrs.label = 'var'
			graphviz.pp_edge(graphviz.pp_var(k.op.var), id, {dir = 'none'})
			graphviz.pp_edge(id, graphviz.pp_k(k.op.k), {})
		elseif k.op.type == types.reify_i then
			attrs.label = 'reify'
			local val_id = graphviz.pp_val(k.op.value)
			graphviz.pp_edge(id, val_id, {label = 'value'})
			graphviz.pp_edge(id, graphviz.pp_k(k.op.k), {})
		elseif k.op.type == 'apply' then
			attrs.label = 'apply'
			graphviz.pp_edge(id, graphviz.pp_k(k.op.fn), { label = 'fn' })
			for i = 1, k.op.args.n do
				graphviz.pp_edge(id, graphviz.pp_k(k.op.args[i]), { label = '"args.' .. i .. '"' })
			end
			graphviz.pp_edge(id, graphviz.pp_k(k.op.k), {})
		elseif k.op.type == 'str' then
			attrs.label = '"str: ' .. k.op.str:gsub('"', '\\"') .. '"'
			graphviz.pp_edge(id, graphviz.pp_k(k.op.k), {})
		elseif k.op.type == 'define' then
			attrs.label = 'define'
			graphviz.pp_edge(id, graphviz.pp_var(k.op.var), {})
			graphviz.pp_edge(id, graphviz.pp_k(k.op.value), { label = 'value' })
			if k.op.var.type ~= 'pure' then
				graphviz.pp_edge(id, graphviz.pp_k(k.op.k), {})
			end
		elseif k.op.type == types.lua_i then
			attrs.label = 'lua'
			graphviz.pp_edge(id, graphviz.pp_k(k.op.k), {})
		elseif k.op.type == types.lambda_i then
			attrs.label = 'lambda'
			for i, arg in ipairs(k.op.args) do
				graphviz.pp_edge(id, graphviz.pp_var(arg), { label = '"arg ' .. i .. '"' })
			end
			graphviz.pp_edge(id, graphviz.pp_k(k.op.entry_k), { label = '"entry k"' })
			graphviz.pp_edge(id, graphviz.pp_k(k.op.ret_k), { label = '"return k"' })
			graphviz.pp_edge(id, graphviz.pp_k(k.op.k), {})
		elseif k.op.type == types.return_i then
			attrs.label = 'return'
			graphviz.pp_edge(id, graphviz.pp_k(k.op.args), {})
		elseif k.op.type == 'exit' then
			attrs.label = 'exit'
		elseif k.op.type == 'if' then
			attrs.label = 'if'
			graphviz.pp_edge(id, graphviz.pp_k(k.op.cond), { label = 'cond' })
			graphviz.pp_edge(id, graphviz.pp_k(k.op.true_k), { label = 'true' })
			graphviz.pp_edge(id, graphviz.pp_k(k.op.false_k), { label = 'false' })
		else
			error('unhandled op type: ' .. util.pp_sym(k.op.type))
		end
	else
		attrs.label = '"' .. ('unbuilt: ' .. k.name):gsub('"', '\\"') .. '"'
	end

	return graphviz.pp_node(id, attrs)
end
function graphviz.pp_val(val)
	local id = tostring({})
	local attrs = {}
	if val.type == types.fn_t then
		attrs.label = 'fn'
		for i, arg in ipairs(val.args) do
			graphviz.pp_edge(id, graphviz.pp_var(arg), { label = '"arg.' .. i .. '"' })
		end
		graphviz.pp_edge(id, graphviz.pp_k(val.k), { label = 'k' })
		graphviz.pp_edge(id, graphviz.pp_k(val.ret_k), { label = '"ret k"' })
	elseif val.type == number_t then
		attrs.label = '"number(' .. val.number .. ')"'
	elseif val.type == types.macro_t then
		attrs.label = 'macro'
	else
		error('unhandled val type: ' .. util.pp_sym(val.type))
	end
	return graphviz.pp_node(id, attrs)
end
function graphviz.pp_ir(ir)
	if ir.type == 'var' then
		add_var(ir.var)
		return 'var(' .. resolve.pp_var(ir.var) .. ')'
	elseif ir.type == 'apply' then
		local str = 'apply(' .. graphviz.pp_ir(ir.fn)
		for _, arg in ipairs(ir.args) do
			str = str .. ', ' .. graphviz.pp_ir(arg)
		end
		str = str .. ')'
		return str
	elseif ir.type == 'defer' then
		return 'defer(' .. ir.job.name .. ' = ' .. graphviz.pp_ir(ir.job.res[1]) .. ')'
	elseif ir.type == types.reify_i then
		return 'reify(' .. graphviz.pp_val(ir.value) .. ')'
	elseif ir.type == 'str' then
		return 'str(' .. ('%q'):format(ir.str) .. ')'
	else
		error('unhandled ir type: ' .. util.pp_sym(ir.type))
	end
end

return graphviz
