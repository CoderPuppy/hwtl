local require = require('nsrq')()
local pretty = require './pretty'
local pl = require 'pl.import_into' ()
local util = require './util'

local sexps
if true then
	print('----]] Parsing')
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

	print(pl.pretty.write(res))
	for _, sexp in ipairs(sexps) do
		print(pretty(sexp))
	end
	print()
end

local reify_i = {name = 'reify';}
local set_i = {name = 'set!';}
local macro_t = {name = 'macro';}
local fn_t = {name = 'fn';}
local lua_fn_t = {name = 'lua_fn';}
local number_t = {name = 'number';}

local const_rules, const_rules_ap
const_rules = {
	apply = function(rec, ir, typ)
		error 'todo'
	end;
	[reify_i] = function(rec, ir, typ)
		return function()
			return ir.value
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
	print('----]] Resolving')
	local resolve = require './resolve' {
		constant_folding_rules = const_rules;
		call_rules = {
			[macro_t] = function(ctx)
				return ctx.fn.fn(ctx)
			end;
		};
		backend = backend;
	}
	local builtins = resolve.block('builtins'); do
		builtins.namespace.add_entry {
			type = 'define';
			name = 'define';
			var = {
				name = 'define';
				block = builtins;
				mutable = false;
				value = {
					type = reify_i;
					value = {
						type = macro_t;
						fn = function(ctx)
							assert(ctx.args.n >= 2, 'define expects at least two arguments')
							assert(ctx.args[1].type == 'sym', 'define expects a symbol for the first argument')
							local mutable = false
							for i = 2, ctx.args.n - 1 do
								local arg = ctx.args[i]
								assert(arg.type == 'sym')
								assert(arg.name == '#:mutable')
								mutable = true
							end
							print('define', ctx.ctx.block.namespace.name, ctx.args[1].name)

							local job = resolve.spawn(
								'define: block = ' .. resolve.pp_block(ctx.ctx.block) .. ', name = ' .. ('%q'):format(ctx.args[1].name),
								resolve.resolve, ctx.ctx, ctx.args[ctx.args.n]
							)
							local var = {
								name = ctx.args[1].name;
								block = ctx.ctx.block;
								mutable = mutable;
								value = { type = 'defer'; job = job; };
							}
							ctx.ctx.block.namespace.add_entry {
								type = 'define';
								name = ctx.args[1].name;
								var = var;
							}
							print(ctx.ctx.block.namespace.entries.n)
							return { type = 'var'; var = var; }
						end;
					};
				};
			};
		}
		builtins.namespace.add_entry {
			type = 'define';
			name = 'lambda';
			var = {
				name = 'lambda';
				block = builtins;
				mutable = false;
				value = {
					type = reify_i;
					value = {
						type = macro_t;
						fn = function(ctx)
							assert(ctx.args.n > 2, 'lambda expects two or more arguments')
							assert(ctx.args[1].type == 'list', 'lambda expects a list of symbols for the first argument')
							for i = 1, ctx.args[1].n do
								assert(ctx.args[1][i].type == 'sym', 'lambda expects a list of symbols for the first argument')
							end

							local new_ctx = {}
							new_ctx.block = resolve.block(ctx.ctx.block.name .. '/lambda');

							new_ctx.block.namespace.add_entry {
								type = 'namespace';
								here = { pre = ''; post = ''; };
								there = { pre = ''; post = ''; };
								namespace = ctx.ctx.block.namespace;
							}

							local args = {n = ctx.args[1].n}
							for i = 1 , ctx.args[1].n do
								args[i] = {
									name = ctx.args[1][i].name;
									block = new_ctx.block;
									mutable = false;
								}
								new_ctx.block.namespace.add_entry {
									type = 'define';
									name = args[i].name;
									var = args[i];
								}
							end

							local jobs = {n = ctx.args.n - 1}
							for i = 2, ctx.args.n do
								jobs[i - 1] = resolve.spawn('lambda.body.' .. i - 1, resolve.resolve, new_ctx, ctx.args[i])
							end

							local fn = {}
							fn.type = fn_t
							fn.args = args
							fn.body = {n = jobs.n}
							for i = 1, jobs.n do
								fn.body[i] = { type = 'defer'; job = jobs[i]; }
							end
							return {
								type = reify_i;
								value = fn
							}
						end;
					};
				};
			};
		}
		builtins.namespace.add_entry {
			type = 'define';
			name = 'set!';
			var = {
				name = 'set!';
				block = builtins;
				mutable = false;
				value = {
					type = reify_i;
					value = {
						type = macro_t;
						fn = function(ctx)
							assert(ctx.args.n == 2, 'set! expects two arguments')
							assert(ctx.args[1].type == 'sym', 'set! expects a symbol for the first argument')
							local value = resolve.resolve(ctx.ctx, ctx.args[2])
							local var = resolve.resolve_var(ctx.ctx.block.namespace, ctx.args[1].name)
							assert(var, 'set! expects the variable to exist')
							assert(var.mutable, 'set! expects the variable to be mutable')
							return {
								type = set_i;
								var = var;
								value = value;
							}
						end;
					};
				};
			};
		}
		builtins.namespace.add_entry {
			type = 'define';
			name = 'lua/tonumber';
			var = {
				name = 'lua/tonumber';
				block = builtins;
				mutable = false;
				value = {
					type = reify_i;
					value = {
						type = lua_fn_t;
						fn = tonumber;
					};
				};
			};
		}
		builtins.namespace.add_entry {
			type = 'define';
			name = 'lua/+';
			var = {
				name = 'lua/+';
				block = builtins;
				mutable = false;
				value = {
					type = reify_i;
					value = {
						type = lua_fn_t;
						fn = function(...)
							local n = 0
							for i = 1, select('#', ...) do
								n = n + select(i, ...)
							end
							return n
						end;
					};
				};
			};
		}
		builtins.namespace.add_entry {
			type = 'define';
			name = 'lua/io/read';
			var = {
				name = 'lua/io/read';
				block = builtins;
				mutable = false;
				value = {
					type = reify_i;
					value = {
						type = lua_fn_t;
						fn = io.read;
					};
				};
			};
		}
		builtins.namespace.add_entry {
			type = 'define';
			name = 'log!';
			var = {
				name = 'log!';
				block = builtins;
				mutable = false;
				value = {
					type = reify_i;
					value = {
						type = lua_fn_t;
						fn = print;
					};
				};
			};
		}
		do
			local cache = setmetatable({}, {
				__index = function(self, i)
					local var = {
						name = tostring(i);
						block = builtins;
						mutable = false;
						value = {
							type = reify_i;
							value = {
								type = number_t;
								number = i;
							};
						};
					}
					self[i] = var
					return var
				end;
			})
			builtins.namespace.add_entry {
				type = 'function';
				fn = function(namespace, name, complete_ref)
					if name:match '^-?%d+$' then
						return cache[tonumber(name)]
					end
				end;
			}
		end
	end
	local ground = resolve.block('ground'); do
		ground.namespace.add_entry {
			type = 'namespace';
			namespace = builtins.namespace;
			here = { pre = ''; post = ''; };
			there = { pre = ''; post = ''; };
		}
	end
	print('builtins', tostring(builtins.namespace))
	print('ground', tostring(ground.namespace))
	local ctx = {
		block = ground;
	}
	local jobs = {}
	for i, sexp in ipairs(sexps) do
		jobs[i] = resolve.spawn('test.sexp.' .. tostring(i), resolve.resolve, ctx, sexp)
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
	local vars = {n = 0;}
	local vars_added = {}
	local function add_var(var)
		if vars_added[var] then return end
		util.push(vars, var)
		vars_added[var] = true
	end
	local pp_val, pp_ir
	function pp_val(val)
		if val.type == fn_t then
			local str = 'fn(('
			for i, arg in ipairs(val.args) do
				if i ~= 1 then
					str = str .. ', '
				end
				str = str .. arg.name
			end
			str = str .. ') => {'
			for i, ir in ipairs(val.body) do
				if i ~= 1 then
					str = str .. ' '
				end
				str = str .. pp_ir(ir)
			end
			return str
		elseif val.type == number_t then
			return 'number(' .. val.number .. ')'
		elseif val.type == lua_fn_t then
			return 'lua_fn'
		else
			error('unhandled val type: ' .. util.pp_sym(val.type))
		end
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
		elseif ir.type == set_i then
			return 'set!(' .. resolve.pp_var(ir.var) .. ' = ' .. pp_ir(ir.value) .. ')'
		elseif ir.type == 'str' then
			return 'str(' .. ('%q'):format(ir.str) .. ')'
		else
			error('unhandled ir type: ' .. util.pp_sym(ir.type))
		end
	end
	for _, job in ipairs(jobs) do
		print(job.name, pp_ir(job.res[1]))
	end
	while vars.n > 0 do
		local var = vars[1]
		util.remove_idx(vars, 1)
		if var.value then
			print(resolve.pp_var(var) .. ' = ' .. pp_ir(var.value))
		end
	end
	print()
end
