local require = require('nsrq')()
local pretty = require './pretty'
local pl = require 'pl.import_into' ()
local util = require './util'

local sexps
if true then
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
	sexps = res.vals[1]

	-- print(pl.pretty.write(res))
	for _, sexp in ipairs(sexps) do
		-- print(pretty(sexp))
	end
	-- print()
end

local reify_i = {name = 'reify';}
local macro_t = {name = 'macro';}
local fn_t = {name = 'fn';}
local lua_fn_t = {name = 'lua_fn';}
local number_t = {name = 'number';}

local const_rules, const_rules_ap
const_rules = {
	apply = function(rec, ir, typ)
		error 'todo'
	end;
	[reify_i] = function(rec, k, out_k, typ)
		-- TODO: handle `typ`
		return function()
			return k.op.value
		end
	end;
}
const_rules_ap = {
}

local backend = {
	-- TODO: unboxed values
	type = function(v) return v.type end;
}

if true then
	-- print('----]] Resolving')
	local continuations = require './continuations' {
		out_rule = function(k)
			if k.op then
				if k.op.type == reify_i then
					return { main = function(fn)
						local res
						res, k.op.k = fn(k.op.k)
						return res
					end; }
				elseif k.op.type == 'var' then
					return { main = function(fn)
						local res
						res, k.op.k = fn(k.op.k)
						return res
					end; }
				elseif k.op.type == 'str' then
					return { main = function(fn)
						local res
						res, k.op.k = fn(k.op.k)
						return res
					end; }
				elseif k.op.type == 'apply' then
					return {}
				elseif k.op.type == 'define' then
					return { main = function(fn)
						local res
						res, k.op.k = fn(k.op.k)
						return res
					end; }
				else
					error('TODO: ' .. util.pp_sym(k.op.type))
				end
			else
				return {}
			end
		end;
	}
	local resolve = require './resolve' {
		continuations = continuations;
		constant_folding_rules = const_rules;
		call_rules = {
			[macro_t] = function(ctx)
				return ctx.fn.fn(ctx)
			end;
		};
		backend = backend;
	}
	local builtins = resolve.namespace('builtins'); do
		local function define(name, value)
			local in_k = continuations.new('builtins.' .. name .. ': in_k')
			local out_k = continuations.new('builtins.' .. name .. ': out_k')
			in_k.op = {
				type = reify_i;
				value = value;
				k = out_k;
			}
			in_k.gen_outs()
			local var = {
				type = 'const';
				name = name;
				namespace = builtins;
				in_k = in_k;
				out_k = out_k;
				uses = {};
			}
			builtins.add_entry(function(name_)
				if name_ == name then
					return var
				end
			end)
		end
		define('define', {
			type = macro_t;
			fn = function(ctx)
				assert(ctx.args.n == 3, 'define expects three arguments')
				assert(ctx.args[1].type == 'sym', 'define expects a symbol for the first argument')
				assert(ctx.args[2].type == 'sym', 'define expects a symbol for the second argument')
				-- print('define', ctx.namespace.name, ctx.args[1].name)

				local typ = ctx.args[1].name
				local name = ctx.args[2].name
				local val = ctx.args[3].name
				assert(typ == 'const' or typ == 'imm' or typ == 'mut', 'define expects the first argument to be one of `const`, `imm`, `mut`')

				local in_k, out_k
				local var = {
					type = typ;
					name = name;
					uses = {};
				}
				if typ == 'const' then
					var.namespace = ctx.namespace
					var.in_k = continuations.new('TODO: var const in_k')
					var.out_k = continuations.new('TODO: var const out_k')
					ctx.k.op = {
						type = 'var';
						var = var;
						k = ctx.out_k;
					}
					ctx.k.gen_outs()
				else
					var.namespace = ctx.out_ns
					var.in_k = ctx.k
					var.out_k = continuations.new('TODO: var imm/mut out_k')
					var.out_k.op = {
						type = 'define';
						var = var;
						value = var.out_k.use_val(var.out_k);
						k = ctx.out_k;
					}
					var.out_k.gen_outs()
				end
				local job = resolve.spawn(
					'define: namespace = ' .. ctx.namespace.name .. ', name = ' .. ('%q'):format(ctx.args[1].name),
					resolve.resolve, ctx.namespace, ctx.args[ctx.args.n], var.in_k, var.out_k, ctx.in_ns, resolve.namespace('define out_ns')
				)
				var.namespace.add_entry(function(name_)
					if name_ == name then
						return var
					end
				end)

				ctx.out_ns.add_entry(function(name, complete_ref)
					return resolve.resolve_var(ctx.in_ns, name, complete_ref)
				end)
			end;
		})
		define('lambda', {
			type = macro_t;
			fn = function(ctx)
				assert(ctx.args.n > 2, 'lambda expects two or more arguments')
				assert(ctx.args[1].type == 'list', 'lambda expects a list of symbols for the first argument')
				for i = 1, ctx.args[1].n do
					assert(ctx.args[1][i].type == 'sym', 'lambda expects a list of symbols for the first argument')
				end

				local namespace = resolve.namespace(ctx.namespace.name .. '/lambda');

				namespace.add_entry(function(name, complete_ref)
					return resolve.resolve_var(ctx.namespace, name, complete_ref)
				end)

				local ret_k = continuations.new('lambda return')
				local ks = {
					n = ctx.args.n; -- one more than the number of expressions in the body
					[ctx.args.n] = ret_k;
				}
				for i = 2, ctx.args.n do
					ks[i - 1] = continuations.new('lambda.body.' .. i - 1)
				end

				local args = {n = ctx.args[1].n}
				for i = 1 , ctx.args[1].n do
					args[i] = {
						type = 'arg';
						name = ctx.args[1][i].name;
						namespace = namespace;
						uses = {};
						intro_k = ks[1];
					}
					namespace.add_entry(function(name_)
						if name_ == args[i].name then
							return args[i]
						end
					end)
				end

				local nss = {
					n = ctx.args.n; -- one more than the number of expressions in the body
					[1] = ctx.in_ns;
				}
				for i = 2, ctx.args.n do
					nss[i] = resolve.namespace('lambda.body.' .. i - 1)
					nss[i].add_entry(function(name, complete_ref)
						return resolve.resolve_var(namespace, name, complete_ref)
					end)
				end
				for i = 2, ctx.args.n do
					resolve.spawn('lambda.body.' .. i - 1, resolve.resolve, namespace, ctx.args[i], ks[i - 1], ks[i], nss[i - 1], nss[i])
				end

				local fn = {}
				fn.type = fn_t
				fn.args = args
				fn.k = ks[1]
				fn.ret_k = ret_k
				ctx.k.op = {
					type = reify_i;
					value = fn;
					k = ctx.out_k;
				}

				ctx.out_ns.add_entry(function(name, complete_ref)
					return resolve.resolve_var(ctx.in_ns, name, complete_ref)
				end)
			end;
		})
		define('lua/tonumber', {
			type = lua_fn_t;
			fn = tonumber;
		})
		define('lua/+', {
			type = lua_fn_t;
			fn = function(...)
				local n = 0
				for i = 1, select('#', ...) do
					n = n + select(i, ...)
				end
				return n
			end;
		})
		define('lua/io/read',  {
			type = lua_fn_t;
			fn = io.read;
		})
		define('log!', {
			type = lua_fn_t;
			fn = print;
		})
		do
			local cache = setmetatable({}, {
				__index = function(self, i)
					local in_k = continuations.new('builtins.' .. i .. ': in_k')
					local out_k = continuations.new('builtins.' .. i .. ': out_k')
					in_k.op = {
						type = reify_i;
						value = {
							type = number_t;
							number = i;
						};
						k = out_k;
					}
					in_k.gen_outs()
					local var = {
						type = 'const';
						name = tostring(i);
						namespace = builtins;
						in_k = in_k;
						out_k = out_k;
						uses = {};
					}
					self[i] = var
					return var
				end;
			})
			builtins.add_entry(function(name, complete_ref)
				if name:match '^-?%d+$' then
					return cache[tonumber(name)]
				end
			end)
		end
	end
	local ground = resolve.namespace('ground'); do
		ground.add_entry(function(name, complete_ref)
			return resolve.resolve_var(builtins, name, complete_ref)
		end)
	end
	-- print('builtins', tostring(builtins))
	-- print('ground', tostring(ground))
	local ks = {n = sexps.n + 1}
	for i = 1, sexps.n + 1 do
		ks[i] = continuations.new('test.' .. tostring(i))
	end
	local nss = {n = sexps.n + 1}
	for i = 1, sexps.n + 1 do
		nss[i] = resolve.namespace('test.' .. tostring(i))
		nss[i].add_entry(function(name, complete_ref)
			return resolve.resolve_var(ground, name, complete_ref)
		end)
	end
	local jobs = {}
	for i, sexp in ipairs(sexps) do
		jobs[i] = resolve.spawn('test.sexp.' .. tostring(i), resolve.resolve, ground, sexp, ks[i], ks[i + 1], nss[i], nss[i + 1])
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
	local function pp_node(id, attrs)
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
	local function pp_edge(id1, id2, attrs)
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
	local pp_var, pp_k, pp_val
	function pp_var(var)
		local id = tostring(var)
		if pp_vars[var] then return id end
		pp_vars[var] = true
		local attrs = {}

		attrs.label = '"var(ns = ' .. var.namespace.name .. ', name = ' .. var.name .. ', type = ' .. var.type .. ')"'

		if var.type == 'arg' then
			pp_edge(id, pp_k(var.intro_k), { label = '"intro k"' })
		else
			pp_edge(id, pp_k(var.in_k), { label = '"in k"' })
			pp_edge(id, pp_k(var.out_k), { label = '"out k"' })
		end

		return pp_node(id, attrs)
	end
	function pp_k(k)
		local id = tostring(k.node)
		if pp_ks[k] then return id end
		pp_ks[k] = true
		local attrs = {}

		if k.op then
			if k.op.type == 'var' then
				attrs.label = 'var'
				pp_edge(pp_var(k.op.var), id, {dir = 'none'})
				pp_edge(id, pp_k(k.op.k), {})
			elseif k.op.type == reify_i then
				attrs.label = 'reify'
				local val_id = pp_val(k.op.value)
				pp_edge(id, val_id, {label = 'value'})
				pp_edge(id, pp_k(k.op.k), {})
			elseif k.op.type == 'apply' then
				attrs.label = 'apply'
				pp_edge(id, pp_k(k.op.fn), { label = 'fn' })
				for i = 1, k.op.args.n do
					pp_edge(id, pp_k(k.op.args[i]), { label = '"args.' .. i .. '"' })
				end
				pp_edge(id, pp_k(k.op.k), {})
			elseif k.op.type == 'str' then
				attrs.label = '"str: ' .. k.op.str:gsub('"', '\\"') .. '"'
				pp_edge(id, pp_k(k.op.k), {})
			elseif k.op.type == 'define' then
				attrs.label = 'define'
				pp_edge(id, pp_var(k.op.var), {})
				pp_edge(id, pp_k(k.op.value), { label = 'value' })
				pp_edge(id, pp_k(k.op.k), {})
			else
				error('unhandled op type: ' .. util.pp_sym(k.op.type))
			end
		else
			local str = 'unbuilt: '
			local first = true
			for name in pairs(k.names) do
				if not first then
					str = str .. ', '
				end
				str = str .. name
				first = false
			end
			attrs.label = '"' .. str:gsub('"', '\\"') .. '"'
		end

		return pp_node(id, attrs)
	end
	function pp_val(val)
		local id = tostring({})
		local attrs = {}
		if val.type == fn_t then
			attrs.label = 'fn'
			for i, arg in ipairs(val.args) do
				pp_edge(id, pp_var(arg), { label = '"arg.' .. i .. '"' })
			end
			pp_edge(id, pp_k(val.k), { label = 'k' })
			pp_edge(id, pp_k(val.ret_k), { label = '"ret k"' })
		elseif val.type == number_t then
			attrs.label = '"number(' .. val.number .. ')"'
		elseif val.type == lua_fn_t then
			attrs.label = 'lua_fn'
		elseif val.type == macro_t then
			attrs.label = 'macro'
		else
			error('unhandled val type: ' .. util.pp_sym(val.type))
		end
		return pp_node(id, attrs)
	end
	function pp_ir(ir)
		if ir.type == 'var' then
			add_var(ir.var)
			return 'var(' .. resolve.pp_var(ir.var) .. ')'
		elseif ir.type == 'apply' then
			local str = 'apply(' .. pp_ir(ir.fn)
			for _, arg in ipairs(ir.args) do
				str = str .. ', ' .. pp_ir(arg)
			end
			str = str .. ')'
			return str
		elseif ir.type == 'defer' then
			return 'defer(' .. ir.job.name .. ' = ' .. pp_ir(ir.job.res[1]) .. ')'
		elseif ir.type == reify_i then
			return 'reify(' .. pp_val(ir.value) .. ')'
		elseif ir.type == 'str' then
			return 'str(' .. ('%q'):format(ir.str) .. ')'
		else
			error('unhandled ir type: ' .. util.pp_sym(ir.type))
		end
	end
	print'digraph {'
	for i = 1, ks.n do
		local k = ks[i]
		local names = 'names: '
		local first = true
		for name in pairs(k.names) do
			if not first then
				names = names .. ', '
			end
			names = names .. name
			first = false
		end
		pp_edge(
			pp_node(tostring {}, {label = '"' .. names:gsub('"', '\\"') .. '"'}),
			pp_k(k),
			{}
		)
	end
	print'}'
	-- print()
end
