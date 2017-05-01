local pl = require 'pl.import_into' ()
local util = require './util'

local function new_conns()
	return setmetatable({}, {
		__index = function(self, key) local t = {}; self[key] = t; return t end;
		__len = function(self)
			local n = 0
			for k, links in pairs(self) do
				for link in pairs(links) do
					n = n + 1
				end
			end
			return n
		end;
	})
end

return function(opts)
	local continuations = {}

	-- TODO: move this to `resolve.continuation`
	function continuations.new(name)
		local data = {
			name = name;
			flow_ins  = new_conns();
			flow_outs = new_conns();
			val_ins   = new_conns();
			val_outs  = new_conns();
		}
		local fns = {}
		local node = {}
		function fns.gen_links()
			assert(node.op, 'continuation#gen_links: it needs to have an operation')
			for out_k in pairs(node.flow_outs) do
				out_k.flow_ins[node] = {}
			end
			for in_k in pairs(node.val_ins) do
				in_k.val_outs[node] = {}
			end
			data.flow_outs = new_conns()
			data.val_ins   = new_conns()
			local rule = opts.link_rules[node.op.type]
			assert(rule, 'continuation#gen_links: unhandled operation type: ' .. util.pp_sym(node.op.type))
			local links = rule(node)
			for _, link in ipairs(links.flow_outs) do
				node.flow_outs[link.k][link] = true
				link.k.flow_ins[node][link] = true
			end
			for _, link in ipairs(links.val_ins) do
				node.val_ins[link.k][link] = true
				link.k.val_outs[node][link] = true
			end
		end
		return setmetatable(node, {
			__index = function(_, key)
				if fns[key] then
					return fns[key]
				elseif key == 'op' or key == 'flow_ins' or key == 'flow_outs' or key == 'val_outs' or key == 'val_ins' or key == 'name' then
					return data[key]
				else
					error('TODO: get ' .. key)
				end
			end;
			__newindex = function(_, key, val)
				if key == 'op' then
					data[key] = val
				else
					error('TODO: set ' .. key)
				end
			end;
		})
	end

	return continuations
end
