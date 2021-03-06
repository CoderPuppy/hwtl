local resolve = require '../resolve'
local continuations = require '../continuations'
local types = require '../types'
require './rules'

local builtins = resolve.namespace('builtins')
local function define(name, op)
	local in_k = continuations.new('builtins.' .. name .. ': in_k')
	local out_k = continuations.new('builtins.' .. name .. ': out_k')
	in_k.op = op
	in_k.op.k = out_k
	in_k.gen_links()
	local var = {
		type = 'pure';
		name = name;
		namespace = builtins;
		in_k = in_k;
		out_k = out_k;
		uses = {};
	}
	out_k.op = {
		type = 'define';
		value = out_k;
		var = var;
	}
	out_k.gen_links()
	builtins.defines[name] = var
end
define('define', {
	type = types.lua_i;
	pure = true;
	str = [[
		{
			type = extern.types.macro_t;
			fn = {
				type = extern.types.fn_t;
				fn = function(k, ctx)
					util.assert_type(ctx, extern.types.call_ctx_t)
					assert(ctx.args.n == 3, 'define expects three arguments')
					assert(ctx.args[1].type == 'sym', 'define expects a symbol for the first argument')
					assert(ctx.args[2].type == 'sym', 'define expects a symbol for the second argument')
					-- print('define', ctx.namespace.name, ctx.args[1].name)

					local typ = ctx.args[1].name
					local name = ctx.args[2].name
					local val = ctx.args[3].name
					assert(typ == 'pure' or typ == 'imm' or typ == 'mut', 'define expects the first argument to be one of `pure`, `imm`, `mut`')

					local in_k, out_k
					local var = {
						type = typ;
						name = name;
						uses = {};
					}
					if typ == 'pure' then
						var.namespace = ctx.namespace
						var.in_k = extern.continuations.new('TODO: var pure in_k: ' .. extern.resolve.pp_var(var))
						var.out_k = extern.continuations.new('TODO: var pure out_k: ' .. extern.resolve.pp_var(var))
						var.out_k.op = {
							type = 'define';
							var = var;
							value = var.out_k;
						}
						ctx.k.op = {
							type = 'var';
							var = var;
							k = ctx.out_k;
						}
						ctx.k.gen_links()
					else
						var.namespace = ctx.out_ns
						var.in_k = ctx.k
						var.out_k = extern.continuations.new('TODO: var imm/mut out_k')
						var.intro_k = ctx.out_k
						var.out_k.op = {
							type = 'define';
							var = var;
							value = var.out_k;
							k = ctx.out_k;
						}
						var.out_k.gen_links()
					end
					local job = extern.resolve.spawn(
						'define: namespace = ' .. ctx.namespace.name .. ', name = ' .. ('%q'):format(ctx.args[1].name),
						extern.resolve.resolve, ctx.namespace, ctx.args[ctx.args.n], var.in_k, var.out_k, ctx.in_ns, extern.resolve.namespace('define out_ns')
					)
					var.namespace.defines[name] = var

					ctx.out_ns.imports[ctx.in_ns] = true

					return k()
				end;
			};
		}
	]];
})
define('lambda', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.macro_t;
			fn = {
				type = extern.types.fn_t;
				fn = function(k, ctx)
					util.assert_type(ctx, extern.types.call_ctx_t)
					assert(ctx.args.n >= 2, 'lambda expects two or more arguments')
					assert(ctx.args[1].type == 'list', 'lambda expects a list of symbols for the first argument')
					for i = 1, ctx.args[1].n do
						assert(ctx.args[1][i].type == 'sym', 'lambda expects a list of symbols for the first argument')
					end
					if ctx.args[1].tail then
						assert(ctx.args[1].tail.type == 'sym', 'TODO: bad tail')
					end

					local namespace = extern.resolve.namespace(ctx.namespace.name .. '/lambda');

					namespace.imports[ctx.namespace] = true

					local ret_k = extern.continuations.new('lambda return')
					local ks = {
						n = ctx.args.n; -- one more than the number of expressions in the body
						[ctx.args.n] = ret_k;
					}
					for i = 2, ctx.args.n do
						ks[i - 1] = extern.continuations.new('lambda.body.' .. i - 1)
					end

					local args = {n = ctx.args[1].n}
					for i = 1, ctx.args[1].n do
						args[i] = {
							type = 'arg';
							name = ctx.args[1][i].name;
							namespace = namespace;
							uses = {};
							intro_k = ks[1];
						}
						namespace.defines[args[i].name] = args[i]
					end
					if ctx.args[1].tail then
						args.tail = {
							type = 'arg';
							name = ctx.args[1].tail.name;
							namespace = namespace;
							uses = {};
							intro_k = ks[1];
						}
						namespace.defines[args.tail.name] = args.tail
					end

					local nss = {
						n = ctx.args.n; -- one more than the number of expressions in the body
						[1] = ctx.in_ns;
					}
					for i = 2, ctx.args.n do
						nss[i] = extern.resolve.namespace('lambda.body.' .. i - 1)
						nss[i].imports[namespace] = true
					end
					for i = 2, ctx.args.n do
						extern.resolve.spawn('lambda.body.' .. i - 1, extern.resolve.resolve, namespace, ctx.args[i], ks[i - 1], ks[i], nss[i - 1], nss[i])
					end

					ret_k.op = {
						type = extern.types.return_i;
						args = ret_k;
						lambda = ctx.k;
					}
					ret_k.gen_links()

					ctx.k.op = {
						type = extern.types.lambda_i;
						args = args;
						entry_k = ks[1];
						ret_k = ret_k;
						k = ctx.out_k;
					}
					ctx.k.gen_links()

					ctx.out_ns.imports[ctx.in_ns] = true
					return k()
				end;
			};
		}
	]];
	fn = function(ctx)
	end;
})
define('if', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.macro_t;
			fn = {
				type = extern.types.fn_t;
				fn = function(k, ctx)
					util.assert_type(ctx, extern.types.call_ctx_t)
					assert(ctx.args.n == 3, 'if expects three arguments')

					local if_k = extern.continuations.new('if')
					extern.resolve.spawn(
						'if cond',
						extern.resolve.resolve,
							ctx.namespace,
							ctx.args[1],
							ctx.k, if_k,
							ctx.in_ns, ctx.out_ns
					)

					local true_k = extern.continuations.new('if true')
					local false_k = extern.continuations.new('if false')

					if_k.op = {
						type = 'if';
						cond = if_k;
						true_k = true_k;
						false_k = false_k;
					}
					if_k.gen_links()

					extern.resolve.spawn(
						'if true',
						extern.resolve.resolve,
							ctx.namespace,
							ctx.args[2],
							true_k, ctx.out_k,
							ctx.out_ns, extern.resolve.namespace('if true')
					)
					extern.resolve.spawn(
						'if false',
						extern.resolve.resolve,
							ctx.namespace,
							ctx.args[3],
							false_k, ctx.out_k,
							ctx.out_ns, extern.resolve.namespace('if false')
					)
				end;
			};
		}
	]];
})
define('while', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.macro_t;
			fn = {
				type = extern.types.fn_t;
				fn = function(k, ctx)
					util.assert_type(ctx, extern.types.call_ctx_t)
					assert(ctx.args.n >= 2, 'while expects two or more arguments')

					local if_k = extern.continuations.new('while')
					extern.resolve.spawn(
						'while cond',
						extern.resolve.resolve,
							ctx.namespace,
							ctx.args[1],
							ctx.k, if_k,
							ctx.in_ns, ctx.out_ns
					)

					local ks = { n = ctx.args.n; } -- one more than the number of expressions
					for i = 1, ks.n - 1 do
						ks[i] = extern.continuations.new('while body.' .. i)
					end
					ks[ks.n] = ctx.k

					local nss = { n = ctx.args.n; } -- one more than the number of expressions
					nss[1] = ctx.out_ns
					for i = 2, nss.n do
						nss[i] = extern.resolve.namespace('while body.' .. i)
						nss[i].imports[ctx.namespace] = true
					end

					if_k.op = {
						type = 'if';
						cond = if_k;
						true_k = ks[1];
						false_k = ctx.out_k;
					}
					if_k.gen_links()

					for i = 2, ctx.args.n do
						extern.resolve.spawn(
							'while body.' .. i - 1,
							extern.resolve.resolve,
								ctx.namespace,
								ctx.args[i],
								ks[i - 1], ks[i],
								nss[i - 1], nss[i]
						)
					end
				end;
			};
		}
	]];
})
define('quote', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.macro_t;
			fn = {
				type = extern.types.fn_t;
				fn = function(k, ctx)
					util.assert_type(ctx, extern.types.call_ctx_t)

					local indent = ''
					local function reify(sexp)
						if sexp.type == 'list' then
							local str = '{'
							local old_indent = indent
							indent = indent .. '  '
							str = str .. '\n' .. indent .. 'type = extern.types.list_t;'
							for i = 1, sexp.n do
								str = str .. '\n' .. indent .. reify(sexp[i]) .. ';'
							end
							assert(not sexp.tail, 'TODO: tail')
							str = str .. '\n}'
							indent = old_indent
							return str
						elseif sexp.type == 'sym' then
							return '{ type = extern.types.sym_t; value = ' .. ('%q'):format(sexp.name) .. '; }'
						elseif sexp.type == 'str' then
							return '{ type = extern.types.str_t; value = ' .. ('%q'):format(sexp.str) .. '; }'
						else
							error('unhandled type: ' .. sexp.type)
						end
					end

					local str = ''
					for i = 1, ctx.args.n do
						if i ~= 1 then
							str = str .. ', '
						end
						str = str .. reify(ctx.args[i])
					end
					assert(not ctx.args.tail, 'TODO: tail')
					ctx.k.op = {
						type = extern.types.lua_i;
						str = str;
						k = ctx.out_k;
					}
					ctx.k.gen_links()

					ctx.out_ns.imports[ctx.in_ns] = true

					return k()
				end;
			};
		}
	]];
})
define('lua/tonumber', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, str, base)
				return k(tonumber(str, base))
			end;
		}
	]];
})
define('+', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, ...)
				local n = 0
				for i = 1, select('#', ...) do
					local n_ = select(i, ...)
					util.assert_type(n_, extern.types.num_t)
					n = n + n_.value
				end
				return k({ type = extern.types.num_t; value = n; })
			end;
		}
	]];
})
define('*', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, ...)
				local n = 1
				for i = 1, select('#', ...) do
					local n_ = select(i, ...)
					util.assert_type(n_, extern.types.num_t)
					n = n * n_.value
				end
				return k({ type = extern.types.num_t; value = n; })
			end;
		}
	]];
})
define('<=', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, ...)
				for i = 1, select('#', ...) - 1 do
					local n1 = select(i, ...)
					local n2 = select(i + 1, ...)
					util.assert_type(n1, extern.types.num_t)
					util.assert_type(n2, extern.types.num_t)
					if n1.value > n2.value then
						return k({ type = extern.types.bool_t; value = false; })
					end
				end
				return k({ type = extern.types.bool_t; value = true; })
			end;
		}
	]];
})
define('=', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, ...)
				for i = 1, select('#', ...) - 1 do
					local n1 = select(i, ...)
					local n2 = select(i + 1, ...)
					util.assert_type(n1, extern.types.num_t)
					util.assert_type(n2, extern.types.num_t)
					if n1.value ~= n2.value then
						return k({ type = extern.types.bool_t; value = false; })
					end
				end
				return k({ type = extern.types.bool_t; value = true; })
			end;
		}
	]];
})
define('lua/io/read',  {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, format)
				util.assert_type(format, extern.types.str_t)
				-- TODO
				return k(io.read(format.value))
			end;
		}
	]];
})
define('unpack', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, l, i, j)
				util.assert_type(l, extern.types.list_t)
				local i = i and util.assert_type(i, extern.types.num_t).value or 1
				local j = j and util.assert_type(j, extern.types.num_t).value or l.n
				return k(table.unpack(l, i, j))
			end;
		}
	]];
})
define('log!', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.fn_t;
			fn = function(k, ...)
				for i = 1, select('#', ...) do
					local v = select(i, ...)
					io.write(util.pp_sym(v.type))
					if v.type == extern.types.num_t then
						print(': ' .. v.value)
					elseif v.type == extern.types.str_t then
						print(': ' .. v.value)
					else
						print(': ' .. pl.pretty.write(v))
					end
				end
				return k()
			end;
		}
	]];
})
define('true', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.bool_t;
			value = true;
		}
	]];
})
define('false', {
	type = types.lua_i;
	str = [[
		{
			type = extern.types.bool_t;
			value = false;
		}
	]];
})
do
	local cache = setmetatable({}, {
		__index = function(self, i)
			local in_k = continuations.new('builtins.' .. i .. ': in_k')
			local out_k = continuations.new('builtins.' .. i .. ': out_k')
			in_k.op = {
				type = types.lua_i;
				str = [[
					{
						type = extern.types.num_t;
						value = ]] .. tostring(i) .. [[;
					}
				]];
				k = out_k;
			}
			in_k.gen_links()
			local var = {
				type = 'pure';
				name = tostring(i);
				namespace = builtins;
				in_k = in_k;
				out_k = out_k;
				uses = {};
			}
			out_k.op = {
				type = 'define';
				value = out_k;
				var = var;
			}
			out_k.gen_links()
			self[i] = var
			builtins.defines[var.name] = var
			return var
		end;
	})
	builtins.add_entry(function(name, complete_ref)
		if name:match '^-?%d+$' then
			return cache[tonumber(name)]
		end
	end)
end
return builtins
