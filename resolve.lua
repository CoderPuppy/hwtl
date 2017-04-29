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
			assert(type(entry) == 'function', 'resolve.namespace#add_entry: entry must be a function')
			entries.n = entries.n + 1
			entries[entries.n] = entry
		end
		return namespace
	end

	function resolve.race(parent_complete_ref)
		local race = {
			parent_complete_ref = parent_complete_ref;
			complete_ref = { name = 'resolve.race.complete_ref'; value = false; };
			jobs = {n = 0};
			ress = {n = 0};
		}
		function race.found(...)
			util.push(race.ress, table.pack(...))
		end
		function race.run(waits)
			if race.parent_complete_ref and race.parent_complete_ref.value then
				return true
			end
			if not waits then
				waits = resolve.waits()
			end
			if race.parent_complete_ref then waits.refs[race.parent_complete_ref] = true end
			local job_i = 1
			while job_i <= race.jobs.n do
				local job = race.jobs[job_i]
				if job.res then
					if job.res[1] then
						util.push(race.ress, job.res)
					end
					util.remove_idx(race.jobs, job_i)
					job_i = job_i - 1
				else
					waits.jobs[job] = true
				end
				job_i = job_i + 1
			end
			if race.ress.n > 0 then return true end
			coroutine.yield { type = 'wait'; waits = waits; }
			return false
		end
		function race.done()
			coroutine.yield {
				type = 'update_ref';
				ref = race.complete_ref;
				value = true;
			}
		end
		return race
	end

	function resolve.resolve_var(namespace, name, parent_complete_ref)
		local i = 0
		local race = resolve.race(parent_complete_ref)
		while true do
			if namespace.entries.n > i then
				for j = i + 1, namespace.entries.n do
					util.push(race.jobs, resolve.spawn(
						'resolve.resolve_var(' .. namespace.name .. ', ' .. ('%q'):format(name) .. ')',
						namespace.entries[j], name, race.complete_ref
					))
				end
				i = namespace.entries.n
			end
			local waits = resolve.waits()
			waits.vars[namespace][name] = true
			waits.namespace_entries[namespace] = true
			if race.run(waits) then break end
		end
		race.done()
		local var
		for _, res in ipairs(race.ress) do
			if var and var ~= res[1] then
				error 'bad'
			end
			var = res[1]
		end
		if var then
			coroutine.yield {
				type = 'uniq_var';
				namespace = namespace;
				name = name;
				var = var;
			}
		end
		return var
	end

	function resolve.pp_var(var)
		local str = ''
		if var.mutable then str = str .. 'mutable ' end
		str = ('%s%q in %s'):format(str, var.name, var.namespace.name)
		return str
	end

	function resolve.resolve(namespace, sexp, k, out_k, in_ns, out_ns)
		assert(namespace, 'resolve.resolve: namespace required')
		assert(sexp, 'resolve.resolve: sexp required')
		assert(k, 'resolve.resolve: k required')
		assert(out_k, 'resolve.resolve: out_k required')
		assert(in_ns, 'resolve.resolve: in_ns required')
		assert(out_ns, 'resolve.resolve: out_ns required')
		if sexp.type == 'sym' then
			local var = resolve.resolve_var(in_ns, sexp.name)
			k.op = {
				type = 'var';
				var = var;
				k = out_k;
			}
			k.gen_links()
			var.uses[k] = true
			out_ns.add_entry(function(name, complete_ref)
				return resolve.resolve_var(in_ns, name, complete_ref)
			end)
		elseif sexp.type == 'list' then
			local fn_k = opts.continuations.new('resolve.resolve: apply.after-fn')
			local inter_ns = resolve.namespace('resolve.resolve: apply.inter_ns')
			inter_ns.add_entry(function(name, complete_ref)
				return resolve.resolve_var(namespace, name, complete_ref)
			end)
			resolve.resolve(namespace, sexp[1], k, fn_k, in_ns, inter_ns)
			repeat
				local fn_const = resolve._fold_constants(fn_k)
				if not fn_const then break end
				local fn_const = fn_const()
				local rule = opts.call_rules[opts.backend.type(fn_const)]
				if not rule then break end
				return rule {
					fn = fn_const;
					args = util.xtend(table.pack(util.unpack(sexp, 2)), { tail = sexp.tail });
					namespace = namespace;
					k = fn_k;
					out_k = out_k;
					in_ns = in_ns;
					out_ns = out_ns;
					-- TODO
				}
			until true
			local ap_k
			if sexp.n == 1 then
				ap_k = fn_k
			else
				ap_k = opts.continuations.new('resolve.resolve: apply.ap')
			end
			local arg_ks = {
				n = sexp.n; -- one more than the number of arguments
				[1] = fn_k;
				[sexp.n] = ap_k;
			}
			local arg_nss = {
				n = sexp.n; -- one more than the number of arguments
				[1] = inter_ns;
				[sexp.n] = out_ns;
			}
			for i = 2, sexp.n - 1 do
				arg_ks[i] = opts.continuations.new('resolve.resolve: apply.args.' .. tostring(i))
				arg_nss[i] = resolve.namespace('resolve.resolve: apply.args.' .. tostring(i))
				arg_nss[i].add_entry(function(name, complete_ref)
					return resolve.resolve_var(namespace, name, complete_ref)
				end)
			end
			for i = 1, sexp.n - 1 do
				resolve.spawn('resolve.resolve: apply.args.' .. i, resolve.resolve, namespace, sexp[i + 1], arg_ks[i], arg_ks[i + 1], arg_nss[i], arg_nss[i + 1])
			end
			ap_k.op = {
				type = 'apply';
				fn = fn_k;
				args = {n = sexp.n - 1;};
				k = out_k;
			}
			for i = 2, arg_ks.n do
				ap_k.op.args[i - 1] = arg_ks[i]
			end
			ap_k.gen_links()
		elseif sexp.type == 'str' then
			k.op = {
				type = 'str';
				str = sexp.str;
				k = out_k;
			}
			k.gen_links()
		else
			error('unhandled sexp type: ' .. sexp.type)
		end
	end

	function resolve._fold_constants(k, typ)
		local consts = {n = 0}
		-- TODO: all the incoming paths may not have appeared yet
		for in_k, links in pairs(k.flow_ins) do
			local const = opts.constant_folding_rules[in_k.op.type]
			if not const then error('need a constant folding rule for ' .. util.pp_sym(in_k.op.type)) end
			local const = const(resolve._fold_constants, in_k, k, typ)
			if const then
				util.push(consts, const)
			end
		end
		if consts.n == 0 then
			return nil
		elseif consts.n == 1 then
			return consts[1]
		else
			error 'TODO'
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
			for k in pairs(waits_.continuations) do
				waits.continuations[k] = true
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
		waits.continuations = {}
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
				for k in pairs(self.continuations) do
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
		for k in pairs(waits.continuations) do
			strs.n = strs.n + 1
			strs[strs.n] = 'continuation(' .. k.name .. ')'
		end
		return table.concat(strs, ', ')
	end

	function resolve.pp_cmd(cmd)
		if cmd.type == 'uniq_var' then
			return ('uniq_var(%s, %q, %s)'):format(cmd.namespace.name, cmd.name, resolve.pp_var(cmd.var))
		elseif cmd.type == 'wait' then
			return 'wait(' .. resolve.pp_waits(cmd.waits) .. ')'
		elseif cmd.type == 'update_ref' then
			return 'update_ref(' .. cmd.ref.name .. ', ' .. tostring(cmd.ref.val) .. ')'
		else
			error('unhandled cmd type: ' .. cmd.type)
		end
	end

	return resolve
end
