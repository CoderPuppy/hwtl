local require = require 'nsrq' ()
local util = require './util'

local function prompt(tag, fn, k)
	return fn({
		next = k;
		tag = tag;
		handle = function(self, ...)
			return self.next:ret(true, ...)
		end;
		ret = function(self, ...)
			return self:handle(...)
		end;
	})
end

local function control(tag, fn, k)
	local prompt_k = k
	while prompt_k.tag ~= tag do
		prompt_k = prompt_k.next
	end
	local re_ks = {n = 0;}
	do
		local re_k = k
		while re_k ~= prompt_k do
			re_ks.n = re_ks.n + 1
			re_ks[re_ks.n] = util.xtend({}, re_k)
			re_ks[re_ks.n].next = nil
			re_k = re_k.next
		end
	end
	return fn(function(...)
		local args = table.pack(...)
		local k_ = args[args.n]
		args[args.n] = nil
		args.n = args.n - 1
		local k = k_
		for i = re_ks.n, 1, -1 do
			k = util.xtend({}, re_ks[i], {
				next = k;
			})
		end
		return k:ret(...)
	end, util.xtend({}, prompt_k.next, {
		ret = function(self, ...)
			return prompt_k.next.ret(self, false, ...)
		end;
	}))
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
	return prompt('b', function(k)
		print 'b 1'
		return control('a', function(k_, k)
			return k:ret(k_)
		end, util.xtend({}, k, { ret = function(self, ...)
			print 'b 2'
			return control('b', function(k_, k)
				return k:ret(k_)
			end, util.xtend({}, k, { ret = function(self, ...)
				print 'b 3'
				return k.ret(self, ...)
			end }))
		end }))
	end, util.xtend({}, k, { ret = function(self, ...)
		print 'a 2'
		return k.ret(self, ...)
	end }))
end, { ret = function(self, ...)
	local fn = ...
	return fn({ ret = function(self, ...)
		print('fn k')
		print(debug.traceback())
	end })
end })
