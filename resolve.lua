local pl = require 'pl.import_into' ()
local util = require './util'

return function(opts)
	local resolve = {}

	resolve.uniq_vars = setmetatable({}, {
		__index = function(self, namespace)
			local data = {}
			local t = setmetatable({}, {
				__index = data;
				__newindex = function(_, name, var)
					if data[name] and data[name] ~= var then
						error 'bad'
					else
						data[name] = var
					end
				end;
			})
			rawset(self, namespace, t)
			return t
		end;
	})

	local jobs = {n = 0}
	local current_job

	function resolve.spawn(name, ...)
		local job = {
			name = name;
			co = util.create_co('resolve.spawn: ' .. name, table.pack(...));
		}
		jobs.n = jobs.n + 1
		jobs[jobs.n] = job
		return job
	end

	function resolve.run()
		while true do
			local waits = resolve.waits()
			local any = false
			local work = false
			local job_i = 1
			while job_i <= jobs.n do
				local job = jobs[job_i]
				if coroutine.status(job.co) == 'suspended' then
					while true do
						current_job = job
						local res_ = table.pack(coroutine.resume(job.co))
						current_job = nil
						job.waits = nil
						local s = coroutine.status(job.co)
						if s == 'suspended' then
							local cmd = res_[2]
							if cmd.type == 'wait' then
								any = true
								resolve.merge_waits(waits, cmd.waits)
								job.waits = cmd.waits
								break
							else
								work = true
								if cmd.type == 'uniq_var' then
									resolve.uniq_vars[cmd.namespace][cmd.name] = cmd.var
								elseif cmd.type == 'update_ref' then
									cmd.ref.value = cmd.value
								else
									coroutine.yield(cmd)
								end
							end
						elseif s == 'dead' then
							if res_[1] then
								work = true
								job.co = nil
								job.res = table.pack(util.unpack(res_, 2))
								util.remove_idx(jobs, job_i)
								job_i = job_i - 1
								break
							else
								error(res_[2], 0)
							end
						else
							error('unhandled status: ' .. s)
						end
					end
				end
				job_i = job_i + 1
			end
			if any then
				if not #waits then error 'no?' end
				if not work then
					for _, job in ipairs(jobs) do
						if job.waits then
							print(job.name .. ': ' .. resolve.pp_waits(job.waits))
						end
					end
					error('dead lock: ' .. resolve.pp_waits(waits), 0)
				end
			else
				break
			end
		end
	end

	function resolve.namespace(name)
		local namespace = {
			name = name;
		}
		local entries = {n = 0}
		namespace.entries = setmetatable({}, {
			__index = entries;
			__newindex = function(self, i, entry)
				error 'please don\'t'
			end;
		})
		function namespace.add_entry(entry)
			entries.n = entries.n + 1
			entries[entries.n] = entry
		end
		return namespace
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

	function resolve.resolve_var(namespace, name, parent_complete_ref)
		local i = 0
		local jobs = {n = 0}
		local var
		local complete_ref = { name = 'resolve.resolve_var.complete_ref'; value = false; }
		local function found_var(var_)
			if var and var_ ~= var then
				error 'bad'
			end
			var = var_
		end
		while true do
			if parent_complete_ref and parent_complete_ref.value then
				break
			end
			if namespace.entries.n > i then
				for j = i + 1, namespace.entries.n do
					local entry = namespace.entries[j]
					repeat
						if entry.type == 'namespace' then
							if name:sub(1, #entry.here.pre) ~= entry.here.pre then break end
							if entry.here.post ~= '' and name:sub(-#entry.here.post) ~= entry.here.post then break end
							-- TODO: better renaming
							util.push(jobs, resolve.spawn('resolve.resolve_var(' .. namespace.name .. ', ' .. ('%q'):format(name) .. '): namespace(' .. entry.namespace.name .. ')',
								function()
									local var = resolve.resolve_var(
										entry.namespace,
										entry.there.pre ..
										name:sub(#entry.here.pre + 1, -(#entry.here.post + 1))
										.. entry.there.post,
										complete_ref
									)
									return var
								end
							))
						elseif entry.type == 'define' then
							if name == entry.name then
								found_var(entry.var)
							end
						elseif entry.type == 'function' then
							util.push(jobs, resolve.spawn('resolve.resolve_var(' .. namespace.name .. ', ' .. ('%q'):format(name) .. '): function', entry.fn, namespace, name, complete_ref))
						else
							error('unhandled entry type: ' .. entry.type)
						end
					until true
				end
				i = namespace.entries.n
			end
			local waits = resolve.waits()
			waits.vars[namespace][name] = true
			if parent_complete_ref then waits.refs[parent_complete_ref] = true end
			waits.namespace_entries[namespace] = true
			local job_i = 1
			while job_i <= jobs.n do
				local job = jobs[job_i]
				if job.res then
					if job.res[1] then
						found_var(job.res[1])
					end
					util.remove_idx(jobs, job_i)
					job_i = job_i - 1
				else
					waits.jobs[job] = true
				end
				job_i = job_i + 1
			end
			if var then break end
			coroutine.yield { type = 'wait'; waits = waits; }
		end
		if var then
			coroutine.yield {
				type = 'uniq_var';
				namespace = namespace;
				name = name;
				var = var;
			}
		end
		coroutine.yield {
			type = 'update_ref';
			ref = complete_ref;
			value = true;
		}
		return var
	end

	function resolve.pp_var(var)
		local str = ''
		if var.mutable then str = str .. 'mutable ' end
		str = ('%s%q in %s'):format(str, var.name, resolve.pp_block(var.block))
		return str
	end

	function resolve.resolve(ctx, sexp)
		if sexp.type == 'sym' then
			return {
				type = 'var';
				var = resolve.resolve_var(ctx.block.namespace, sexp.name);
			}
		elseif sexp.type == 'list' then
			local fn_ir = resolve.resolve(ctx, sexp[1])
			repeat
				local fn_const = resolve._fold_constants(fn_ir)
				if not fn_const then break end
				local fn_const = fn_const()
				local rule = opts.call_rules[opts.backend.type(fn_const)]
				if not rule then break end
				return rule {
					fn = fn_const;
					args = util.xtend(table.pack(util.unpack(sexp, 2)), { tail = sexp.tail });
					ctx = ctx;
					-- TODO
				}
			until true
			local args_ir = {n = sexp.n - 1}
			for i = 1, args_ir.n do
				args_ir[i] = {
					type = 'defer';
					job = resolve.spawn('resolve.resolve: apply.args.' .. i, resolve.resolve, ctx, sexp[i + 1]);
				}
			end
			return {
				type = 'apply';
				fn = fn_ir;
				args = args_ir;
			}
		elseif sexp.type == 'str' then
			return {
				type = 'str';
				str = sexp.str;
			}
		else
			error('unhandled sexp type: ' .. sexp.type)
		end
	end

	function resolve._fold_constants(ir, typ)
		if ir.type == 'var' then
			if ir.var.mutable then
				error 'TODO'
			else
				-- TODO: are the constaints for constant folding the same (or tighter) as for reording evaluation?
				return resolve._fold_constants(ir.var.value, typ)
			end
		elseif opts.constant_folding_rules[ir.type] then
			return opts.constant_folding_rules[ir.type](resolve._fold_constants, ir, typ)
		end
	end

	function resolve.merge_waits(waits, ...)
		for i = 1, select('#', ...) do
			local waits_ = select(i, ...)
			for namespace in pairs(waits_.namespace_entries) do
				waits.namespace_entries[namespace] = true
			end
			for namespace, t in pairs(waits_.vars) do
				for name in pairs(t) do
					waits.vars[namespace][name] = true
				end
			end
			for job in pairs(waits_.jobs) do
				waits.jobs[job] = true
			end
		end
		return waits
	end

	function resolve.waits()
		local waits = {}
		waits.namespace_entries = {}
		waits.vars = setmetatable({}, {
			__index = function(self, namespace)
				local t = {}
				self[namespace] = t
				return t
			end;
		})
		waits.jobs = {}
		waits.refs = {}
		setmetatable(waits, {
			__len = function(self)
				for namespace in pairs(self.namespace_entries) do
					return true
				end
				for namespace, t in pairs(self.vars) do
					for name in pairs(t) do
						return true
					end
				end
				for job in pairs(self.jobs) do
					return true
				end
				for ref in pairs(self.refs) do
					return true
				end
				return false
			end;
		})
		return waits
	end

	function resolve.pp_waits(waits)
		local strs = {n = 0}
		for namespace in pairs(waits.namespace_entries) do
			strs.n = strs.n + 1
			strs[strs.n] = 'namespace_entries(' .. namespace.name .. ')'
		end
		for namespace, t in pairs(waits.vars) do
			for name in pairs(t) do
				strs.n = strs.n + 1
				strs[strs.n] = 'var(' .. namespace.name .. ', ' .. ('%q'):format(name) .. ')'
			end
		end
		for job in pairs(waits.jobs) do
			strs.n = strs.n + 1
			strs[strs.n] = 'job(' .. job.name .. ')'
		end
		for ref in pairs(waits.refs) do
			strs.n = strs.n + 1
			strs[strs.n] = 'ref(' .. ref.name .. ')'
		end
		return table.concat(strs, ', ')
	end

	function resolve.pp_cmd(cmd)
		if cmd.type == 'uniq_var' then
			return ('uniq_var(%s, %q, %s)'):format(cmd.namespace.name, cmd.name, resolve.pp_var(cmd.var))
		elseif cmd.type == 'wait' then
			return 'wait(' .. resolve.pp_waits(cmd.waits) .. ')'
		else
			error('unhandled cmd type: ' .. cmd.type)
		end
	end

	return resolve
end
