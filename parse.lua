local util = require './util'
local concat = util.concat

local function makeErr(src, msg)
	return { msg = msg; state = src:state(); traceback = debug.traceback(msg, 1); }
end

local function spaceList(parse)
	return function(src)
		local vals = {n = 0;}
		local err = {}

		local first, err_ = src:try(parse)
		err = concat(err, err_)
		if first then
			vals[1] = first
			vals.n = 1
			while true do
				if not src:consume '%s+' then
					break
				end

				local val, err_ = src:try(parse)
				err = concat(err, err_)
				if val then
					vals.n = vals.n + 1
					vals[vals.n] = val
				else
					break
				end
			end
		end

		return vals, err
	end
end

local function str(src)
	local str = ''
	local done = false
	while not done do
		repeat
			local s = src:consume '[^\\"]+'
			if s then
				str = str .. s
				break
			end

			if src:consume '\\"' then
				str = str .. '"'
				break
			end

			if src:consume '\\t' then
				str = str .. '\t'
				break
			end

			if src:consume '\\n' then
				str = str .. '\n'
				break
			end

			local code = src:consume '\\u{([0-9a-zA-Z]+)}'
			if code then
				str = str .. utf8.char(tonumber(code))
				break
			end

			done = true
		until true
	end
	return str, {}
end

local function expr(src)
	src:consume '%s*'

	local start = src:state()

	local open = src:consume '[%(%[{]'
	if open then
		local vals, err = spaceList(expr)(src)

		vals.type = 'list'
		vals.start = start

		src:consume '%s*';
		if (open == '(' and src:consume '%)') or (open == '[' and src:consume '%]') or (open == '{' and src:consume '}') then
			vals.stop = src:state()
			return vals, err
		else
			return nil, concat(err, {makeErr(src, 'bad parens')})
		end
	end

	local name = src:consume '([^%s\',`#"%(%)%[%]{}][^%s%(%)%[%]{}]*)'
	if name then
		return { type = 'sym'; name = name; start = start; stop = src:state(); }, {}
	end

	if src:consume '"' then
		local s, err = str(src)
		if not s then return nil, err end
		if not src:consume '"' then return nil, {makeErr(src, 'bad string')} end
		return { type = 'str'; str = s; start = start; stop = src:state() }, err
	end

	if src:consume '#`' then
		local i, err = expr(src)
		if not i then return nil, err end
		return { type = 'list'; n = 2; { type = 'sym'; name = 'syntax-quasiquote'; }; i; }, err
	end

	if src:consume '#\'' then
		local i, err = expr(src)
		if not i then return nil, err end
		return { type = 'list'; n = 2; { type = 'sym'; name = 'syntax-quote'; }; i; }, err
	end

	if src:consume '`' then
		local i, err = expr(src)
		if not i then return nil, err end
		return { type = 'list'; n = 2; { type = 'sym'; name = 'quasiquote'; }; i; }, err
	end

	if src:consume '\'' then
		local i, err = expr(src)
		if not i then return nil, err end
		return { type = 'list'; n = 2; { type = 'sym'; name = 'quote'; }; i; }, err
	end

	if src:consume ',' then
		local i, err = expr(src)
		if not i then return nil, err end
		return { type = 'list'; n = 2; { type = 'sym'; name = 'unquote'; }; i; }, err
	end

	local level = src:consume '%[(=*)%['
	if level then
		local s = src:consume('(.-)%]' .. level .. '%]')
		return { type = 'str'; str = s; }, {}
	end

	return nil, {makeErr(src, 'unparsable')}
end

return {
	expr = expr;
	spaceList = spaceList;
}
