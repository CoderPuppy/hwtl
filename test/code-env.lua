local code_env = {}
setmetatable(code_env, { __index = _G })
code_env.util = require '../util'
code_env.extern = setmetatable({
	continuations = require './continuations';
	resolve = require './resolve';
	types = require './types';
}, {
	__index = function(self, key)
		error('bad: ' .. key)
	end;
})
return code_env
