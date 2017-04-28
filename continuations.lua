local pl = require 'pl.import_into' ()

return function(opts)
	local continuations = {}

	local function make_use(node, use)
		if not use then
			use = {}
		end
		setmetatable(use, {
			__index = function(_, key)
				if key == 'op' or key == 'names' or key == 'ins' or key == 'outs' or key == 'gen_outs' or key == 'use_val' or key == 'val_uses' then
					return node[key]
				elseif key == 'node' then
					return node
				else
					print('TODO: ' .. tostring(key))
				end
			end;
			__newindex = function(_, key, val)
				if key == 'op' then
					node[key] = val
				else
					error('TODO: ' .. tostring(key))
				end
			end;
			__pairs = function(self)
				return function(self, prev_key)
					local key
					if prev_key == nil then
						key = 'names'
					elseif prev_key == 'names' then
						key = 'op'
					end
					if key then
						return key, self[key]
					end
				end, self
			end;
			__eq = function() error 'nope' end;
		})
		node.uses[use] = true
		return use
	end

	function continuations.new(name)
		local node = {}
		node.names = {[name] = true}
		node.ins = {}
		node.outs = {}
		node.uses = {}
		node.val_uses = {}
		local use = make_use(node)
		function node.gen_outs()
			for out_k in pairs(node.outs) do
				out_k.ins[use] = nil
			end
			node.outs = {}
			local outs = opts.out_rule(use)
			for name, out in pairs(outs) do
				local out_k = out(function(v) return v, v end)
				node.outs[out_k] = true
				out_k.ins[use] = true
			end
		end
		function node.use_val(k)
			k.val_uses[use] = true
			return k
		end
		return use
	end

	function continuations.merge(k, ...)
		for i = 1, select('#', ...) do
			local k_ = select(i, ...)
			for name in pairs(k_.names) do
				k.names[name] = true
			end
			if k_.op then
				if k.op then error 'bad' end
				k.op = k_.op
				k.node.outs = k_.outs
			end
			for in_k in pairs(k_.ins) do
				k.ins[in_k] = true
			end
		end
		return k
	end

	return continuations
end
