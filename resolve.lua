local pl = require 'pl.import_into' ()
local util = require './util'

return function(opts)
	local resolve = {}

	function resolve.namespace(name)
		local namespace = {
			name = name;
			entries = {};
		}
		return namespace
	end

	function resolve.pp_namespace(namespace)
		return namespace.name
	end

	function resolve.block(name)
		local block = {
			name = name;
			namespace = resolve.namespace(name);
		}
		return block
	end

	function resolve.pp_block(block)
		return block.name
	end

	function resolve.resolve_var(namespace, name)
		local var
		while true do
			local waits = resolve.waits()
			waits.namespace_entries[namespace] = true
			for _, entry in ipairs(namespace.entries) do
				if var then break end
				repeat
					if entry.type == 'namespace' then
						if name:sub(1, #entry.here.pre) ~= entry.here.pre then break end
						if entry.here.post ~= '' and name:sub(-#entry.here.post) ~= entry.here.post then break end
						local co = util.create_co('resolve.resolve_var: namespace', table.pack(
							resolve.resolve_var,
								entry.namespace,
								entry.there.pre .. name:sub(#entry.here.pre + 1, -(#entry.here.post + 1)) .. entry.there.post
						))
						while true do
							local res_ = table.pack(coroutine.resume(co))
							local s = coroutine.status(co)
							if s == 'suspended' then
								local cmd = res_[2]
								if cmd.type == 'wait' then
									resolve.merge_waits(waits, cmd.waits)
									break
								else
									coroutine.yield(cmd)
								end
							elseif s == 'dead' then
								if res_[1] then
									var = res_[2]
									break
								else
									error(res_[2], 0)
								end
							else
								error('unhandled status: ' .. s)
							end
						end
					elseif entry.type == 'define' then
						if name == entry.name then
							var = entry.var
							break
						end
					else
						error('unhandled entry type: ' .. entry.type)
					end
				until true
			end
			if var then break end
			coroutine.yield { type = 'wait'; waits = waits; }
		end
		coroutine.yield {
			type = 'uniq_var';
			namespace = namespace;
			name = name;
			var = var;
		}
		return var
	end

	function resolve.pp_var(var)
		local str = ''
		if var.mutable then str = str .. 'mutable ' end
		str = ('%s%q in %s'):format(str, var.name, resolve.pp_block(var.block))
		return str
	end

	function resolve.resolve(namespace, sexp)
		if sexp.type == 'sym' then
			return {
				type = 'var';
				var = resolve.resolve_var(namespace, sexp.name);
			}
		elseif sexp.type == 'list' then
			local fn = resolve.resolve(namespace, sexp[1])
			print(pl.pretty.write(fn))
			return {
				type = 'apply';
				fn = fn;
				args = table.pack(util.unpack(sexp, 2));
			}
		else
			error('unhandled sexp type: ' .. sexp.type)
		end
	end

	function resolve.merge_waits(waits, ...)
		for i = 1, select('#', ...) do
			local waits_ = select(i, ...)
			for namespace in pairs(waits_.namespace_entries) do
				waits.namespace_entries[namespace] = true
			end
		end
		return waits
	end

	function resolve.waits()
		local waits = {}
		waits.namespace_entries = {}
		setmetatable(waits, {
			__len = function(self)
				for namespace in pairs(self.namespace_entries) do
					return true
				end
				return false
			end;
		})
		return waits
	end

	function resolve.pp_cmd(cmd)
		if cmd.type == 'uniq_var' then
			return ('uniq_var(%s, %q, %s)'):format(resolve.pp_namespace(cmd.namespace), cmd.name, resolve.pp_var(cmd.var))
		elseif cmd.type == 'wait' then
			local strs = {n = 0}
			for namespace in pairs(cmd.waits.namespace_entries) do
				strs.n = strs.n + 1
				strs[strs.n] = 'namespace_entries(' .. resolve.pp_namespace(namespace) .. ')'
			end
			return 'wait(' .. table.concat(strs, ', ') .. ')'
		else
			error('unhandled cmd type: ' .. cmd.type)
		end
	end

	function resolve.parallel(...)
		local cos = util.map(util.cut(util.create_co, 'resolve.parallel', util._))(table.pack(...))
		local ress = {}
		while true do
			local waits = resolve.waits()
			local any = false
			local work = false
			for co_i, co in ipairs(cos) do
				if coroutine.status(co) == 'suspended' then
					while true do
						local res_ = table.pack(coroutine.resume(co))
						local s = coroutine.status(co)
						if s == 'suspended' then
							local cmd = res_[2]
							if cmd.type == 'wait' then
								any = true
								resolve.merge_waits(waits, cmd.waits)
								break
							else
								work = true
								coroutine.yield(cmd)
							end
						elseif s == 'dead' then
							if res_[1] then
								ress[co_i] = table.pack(util.unpack(res_, 2))
								break
							else
								error(res_[2], 0)
							end
						else
							error('unhandled status: ' .. s)
						end
					end
				end
			end
			if any then
				if not #waits then error 'no?' end
				if not work then
					coroutine.yield { type = 'wait'; waits = waits; }
				end
			else
				break
			end
		end
		return table.unpack(ress, 1, cos.n)
	end

	return resolve
end
