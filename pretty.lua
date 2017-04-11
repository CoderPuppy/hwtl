local util = require './util'
local xtend = util.xtend
local function pretty(sexp, st)
	if not st then st = {
		visited = {};
	} end
	local st_ = xtend({}, st, { visited = xtend({}, st.visited, { [sexp] = true; }); })
	if sexp.type == 'list' then
		local s = '('
		for i = 1, sexp.n do
			if i ~= 1 then
				s = s .. ' '
			end
			s = s .. pretty(sexp[i], st_)
		end
		if sexp.tail then
			s = s .. ' . '
			s = s .. pretty(sexp.tail, st_)
		end
		s = s .. ')'
		return s
	elseif sexp.type == 'sym' then
		return sexp.name
	elseif sexp.type == 'str' then
		return ('%q'):format(sexp.str)
	else
		error('unhandled type: ' .. sexp.type)
	end
end
return pretty
