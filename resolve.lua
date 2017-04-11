local pl = require 'pl.import_into' ()
local function new_env()
	local env = {
		includes = {};
	}
	return env
end
local function resolve_var(env, name)
	local var
	while not var do
		for _, include in ipairs(env.includes) do
			local var_ = include(name)
			if var_ then
				if var then
					error('ambiguous var: ' .. name)
				end
				var = var_
			end
		end
		if var then break end
		coroutine.yield { type = 'var'; env = env; name = name; }
	end
	error('TODO: var: ' .. name)
end
local function resolve(env, sexp)
	if sexp.type == 'sym' then
		local var = resolve_var(env, sexp.name)
		error('TODO: var: ' .. sexp.name)
	elseif sexp.type == 'list' then
		local fn = resolve(env, sexp[1])
		error 'TODO: apply'
	else
		error('unhandled sexp type: ' .. sexp.type)
	end
end
local function parallel(...)
	local cos = {}
	for i = 1, select('#', ...) do
		cos[i] = coroutine.create(select(i, ...))
	end
	while true do
		local waits = {n = 0;}
		local any_waiting = false
		for _, co in ipairs(cos) do
			local s = coroutine.status(co)
			if s == 'suspended' then
				local res = table.pack(coroutine.resume(co))
				if res[1] then
					local s_ = coroutine.status(co)
					if s_ == 'suspended' then
						any_waiting = true
						for i = 2, res.n do
							local wait = res[i]
							waits.n = waits.n + 1
							waits[waits.n] = wait
						end
					else
						error('unhandled status: ' .. s)
					end
				else
					error(res[2])
				end
			else
				error('unhandled status: ' .. s)
			end
		end
		if any_waiting then
			print(pl.pretty.write(waits))
			coroutine.yield(table.unpack(waits, 1, waits.n))
		else
			error 'TODO'
		end
	end
end
return {
	env = new_env;
	resolve = resolve;
	resovle_var = resolve_var;
	parallel = parallel;
}
