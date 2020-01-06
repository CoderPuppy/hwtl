local prompts, stop

local function prompt(tag, fn, k)
	local p = {}
	prompts = {
		tag = tag;
		k = k;
		p = p;
		next = prompts;
	}
	if stop then
		stop = stop + 1
	end
	print('open prompt', tag)
	return (fn(function(...)
		if stop == 0 then
			print('stop', tag)
			stop = nil
			return ...
		end
		assert(prompts.p == p)
		print('close prompt', tag, stop)
		if stop then
			stop = stop - 1
		end
		return (k(...))
	end))
end

local function control(tag, fn, k)
	local pf = prompts
	local pt = pf
	local n = 0
	while pt.tag ~= tag do
		n = n + 1
		pt = pt.next
		if not pt then
			error('no prompt for tag: ' .. tostring(tag))
		end
	end
	prompts = pt.next
	if stop then
		stop = stop - n - 1
	end
	return (fn(function(...)
		print('control k', tag)
		local args = table.pack(...)
		local k_ = args[args.n]
		args[args.n] = nil
		args.n = args.n - 1
		local pc = prompts
		local to_copy = {n = 0;}
		local src = pf
		while src ~= pt do
			to_copy.n = to_copy.n + 1
			to_copy[to_copy.n] = src
			src = src.next
		end
		local old_stop = stop
		stop = to_copy.n
		for i = to_copy.n, 1, -1 do
			local to_copy = to_copy[i]
			prompts = {
				tag = to_copy.tag;
				k = to_copy.k;
				p = to_copy.p;
				next = prompts;
			}
		end
		local res = table.pack(k(table.unpack(args, 1, args.n)))
		stop = old_stop
		assert(prompts == pc)
		return (k_(table.unpack(res, 1, res.n)))
	end, pt.k))
end

--[[
(prompt 'a
	(print "a 1")
	(prompt 'b
		(print "b 1")
		(control 'a k k)
		(print "b 2")
		(control 'b k k)
		(print "b 3")
	)
	(print "a 2")
)
(lambda ()
	(prompt 'b
		(print "b 2")
		(control 'b k k)
		(print "b 3")
	)
	(print "a 2")
)
(lambda ()
	(lambda ()
		(print "b 3")
	)
	(print "a 2")
)
]]
prompt('a', function(k)
	print 'a 1'
	return (prompt('b', function(k)
		print 'b 1'
		return (control('a', function(k_, k)
			return (k(k_))
		end, function(...)
			print 'b 2'
			return (control('b', function(k_, k)
				return (k(k_))
			end, function(...)
				print 'b 3'
				return (k(...))
			end))
		end))
	end, function(...)
		print 'a 2'
		return (k(...))
	end))
end, function(...)
	local fn = ...
	return (fn(function(...)
		print('fn k')
		print(debug.traceback())
	end))
end)
