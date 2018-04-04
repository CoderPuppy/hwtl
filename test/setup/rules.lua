local rules = require '../rules'
local types = require '../types'
local util = require '../../util'
local code_env = require '../code-env'
local treeify = require '../codegen/treeify'

util.xtend(rules.const_rules, {
	apply = function(rec, ir, typ)
		error 'TODO'
	end;
	[types.reify_i] = function(rec, k, out_k, typ)
		-- TODO: handle `typ`
		return function()
			return k.op.value
		end
	end;
	[types.lua_i] = function(rec, k, out_k, typ)
		local fn, err = load('return ' .. k.op.str, nil, nil, code_env)
		if err then error(err) end
		local ok, res = pcall(fn)
		if ok then
			return function() return res end
		else
			error(res)
		end
	end;
	var = function(rec, k, out_k, typ)
		if k.op.var.type == 'pure' then
			-- TODO: check that the variable can be used here
			return rec(k.op.var.out_k, typ)
		end
	end;
	[types.lambda_i] = function(rec, k, out_k, typ)
		-- TODO
	end;
})

util.xtend(rules.link_rules, {
	[types.reify_i] = function(k)
		return {
			flow_outs = {
				closed = true;
				{ k = k.op.k; };
			};
			val_ins = {};
		}
	end;
	var = function(k)
		return {
			flow_outs = {
				closed = true;
				{ k = k.op.k; };
			};
			val_ins = {};
		}
	end;
	str = function(k)
		return {
			flow_outs = {
				closed = true;
				{ k = k.op.k; };
			};
			val_ins = {};
		}
	end;
	apply = function(k)
		local val_ins = { n = 0; }
		util.push(val_ins, { k = k.op.fn; })
		for i = 1, k.op.args.n do
			util.push(val_ins, { k = k.op.args[i]; })
		end
		return {
			flow_outs = {
				closed = false;
				{ k = k.op.k; };
			};
			val_ins = val_ins;
		}
	end;
	define = function(k)
		local flow_outs = { closed = true; n = 0; }
		if k.op.var.type ~= 'pure' then
			util.push(flow_outs, { k = k.op.k; })
		end
		return {
			flow_outs = flow_outs;
			val_ins = { { k = k.op.value; }; };
		}
	end;
	[types.lua_i] = function(k)
		return {
			flow_outs = {
				closed = true;
				{ k = k.op.k; };
			};
			val_ins = {};
		}
	end;
	[types.lambda_i] = function(k)
		return {
			flow_outs = {
				closed = true;
				{ k = k.op.k; };
				{ k = k.op.entry_k; };
			};
			val_ins = {};
		}
	end;
	[types.return_i] = function(k)
		return {
			flow_outs = { closed = false; };
			val_ins = { { k = k.op.args; }; };
		}
	end;
	['if'] = function(k)
		return {
			flow_outs = {
				closed = true;
				{ k = k.op.true_k; };
				{ k = k.op.false_k; };
			};
			val_ins = { { k = k.op.cond; }; };
		}
	end;
	exit = function(k)
		return {
			flow_outs = { closed = true; };
			val_ins = {};
		}
	end;
})

util.xtend(rules.call_rules, {
	[types.macro_t] = function(ctx)
		assert(ctx.fn.fn.type == types.fn_t)
		return ctx.fn.fn.fn(function(...) return ... end, util.xtend({ type = types.call_ctx_t; }, ctx))
	end;
})

util.xtend(rules.treeify_rules, {
	var = function(tree)
		if tree.k.op.var.intro_k then
			treeify.ensure_inside(tree, tree.k.op.var.intro_k)
		end

		if tree.k.op.var.type == 'pure' and #tree.k.op.k.val_outs > 0 then
			treeify.explore(tree.k.op.var.in_k, tree).pure_var = tree.k.op.var
		end
	end;
	['if'] = function(tree) end;
	str = function(tree) end;
	apply = function(tree) end;
	exit = function(tree) end;
	[types.lua_i] = function(tree) end;
	define = function(tree)
		if tree.k.op.var.type == 'pure' then
			treeify.ensure_inside(tree, tree.k.op.var.in_k)
		end
	end;
	[types.return_i] = function(tree)
		treeify.ensure_inside(tree, tree.k.op.lambda)
	end;
	[types.lambda_i] = function(tree) end;
})
