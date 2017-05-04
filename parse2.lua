local util = require './util'
local utf8 = utf8 or require 'lua-utf8'
local lookahead = 2
return function(src, h)
	local buf = h:read(lookahead)
	local buf_ = buf
	local pos = {
		lin = 1;
		line = 1;
		col = 1;
	}
	local mode = 'sexp'
	local submode
	local block_comment_level
	local block_string_level1, block_string_level2
	local root = {
		type = 'root';
		sexps = {n = 0;};
	}
	local nesting = {n = 1; root}
	local str, str_temp
	local sym
	local start_pos, last_pos
	local function done(s)
		local nest = nesting[nesting.n]
		if nest.type == 'root' then
			util.push(nest.sexps, s)
		elseif nest.type == 'list' then
			if nest.insert == 'tail' then
				nest.sexp.tail = s
				nest.insert = 'done'
			elseif nest.insert == 'list' then
				util.push(nest.sexp, s)
			else
				error 'bad'
			end
		elseif nest.type == 'prefix' then
			util.remove_idx(nesting, nesting.n)
			return done({
				type = 'list';
				n = 2;
				pos = {
					type = 'parsed';
					src = src;
					start = nest.start_pos;
					stop = s.pos.stop;
				};
				{
					type = 'sym';
					pos = {
						type = 'parsed';
						src = src;
						start = nest.start_pos;
						stop = nest.stop_pos;
					};
					name = nest.name;
				};
				s;
			})
		elseif nest.type == 'comment' then
			util.remove_idx(nesting, nesting.n)
		else
			print(nesting[nesting.n].type)
			error 'TODO'
		end
	end
	local function sym_done()
		if not sym then return end
		if sym == '.' and nesting[nesting.n].type == 'list' then
			nesting[nesting.n].insert = 'tail'
		else
			done({
				type = 'sym';
				name = sym;
				pos = {
					type = 'parsed';
					src = src;
					start = start_pos;
					stop = last_pos;
				};
			})
		end
		sym = nil
	end
	while true do
		repeat
			-- print(buf)
			if mode == 'sexp' then
				local rest = buf:match '^#|(.*)$'
				if rest then
					mode = 'block comment'
					block_comment_level = 0
					buf = rest
					break
				end

				local rest = buf:match '^;(.*)$'
				if rest then
					mode = 'line comment'
					buf = rest
					break
				end

				local rest = buf:match '^%s+(.*)$'
				if rest then
					sym_done()
					buf = rest
					break
				end

				local rest = buf:match '^%[([=%[].*)$'
				if rest then
					mode = 'block string'
					submode = 'start'
					str = ''
					block_string_level1 = 0
					start_pos = util.xtend({}, pos)
					buf = rest
					break
				end

				local open_bracket, rest = buf:match '^([%(%[{])(.*)$'
				if open_bracket then
					sym_done()
					util.push(nesting, {
						type = 'list';
						insert = 'list';
						open_bracket = open_bracket;
						close_bracket =
							open_bracket == '(' and ')' or
							open_bracket == '[' and ']' or
							open_bracket == '{' and '}' or
							error 'bad';
						sexp = {
							type = 'list';
							n = 0;
							pos = {
								type = 'parsed';
								src = src;
								start = util.xtend({}, pos);
							};
						};
					})
					buf = rest
					break
				end

				local close_bracket, rest = buf:match '^([%)%]}])(.*)$'
				if close_bracket then
					sym_done()
					assert(nesting[nesting.n].type == 'list', 'trying to close list, got: ' .. tostring(nesting[nesting.n].type))
					assert(nesting[nesting.n].close_bracket == close_bracket)
					local sexp = util.remove_idx(nesting, nesting.n).sexp
					sexp.pos.stop = util.xtend({}, pos)
					done(sexp)
					buf = rest
					break
				end

				local prefix, rest = buf:match '^([\'`,@])(.*)$'
				if not prefix then prefix, rest = buf:match '^(#\')(.*)$' end
				if not prefix then prefix, rest = buf:match '^(#`)(.*)$' end
				if prefix then
					if sym then
						sym = sym .. prefix
					else
						util.push(nesting, {
							type = 'prefix';
							start_pos = util.xtend({}, pos);
							stop_pos = util.xtend({}, pos, {
								lin = pos.lin + #prefix - 1;
								col = pos.col + #prefix - 1;
							});
							name =
								prefix == '\'' and 'quote' or
								prefix == '`' and 'quasiquote' or
								prefix == ',' and 'unquote' or
								prefix == '@' and 'splice' or
								prefix == '#\'' and 'syntax-quote' or
								prefix == '#`' and 'syntax-quasiquote' or
								error 'bad'
						})
					end
					buf = rest
					break
				end

				local rest = buf:match '^#;(.*)$'
				if rest then
					if sym then
						prefix = prefix .. '#;'
					else
						util.push(nesting, {
							type = 'comment';
						})
					end
					buf = rest
					break
				end

				local rest = buf:match '^"(.*)$'
				if rest then
					mode = 'string'
					submode = nil
					str = ''
					start_pos = util.xtend({}, pos)
					buf = rest
					break
				end

				local head, rest = buf:match '^\\(.)(.*)$'
				if not head then head, rest = buf:match '^(.)(.*)$' end
				if head then
					if not sym then
						start_pos = util.xtend({}, pos)
					end
					sym = (sym or '') .. head
					buf = rest
					last_pos = util.xtend({}, pos)
					break
				end
			elseif mode == 'line comment' then
				local head, rest = buf:match '^(.)(.*)$'
				buf = rest
				if head == '\n' or head == '\r' then
					mode = 'sexp'
				end
				break
			elseif mode == 'block comment' then
				local rest = buf:match '^#|(.*)$'
				if rest then
					block_comment_level = block_comment_level + 1
					buf = rest
					break
				end

				local rest = buf:match '^|#(.*)$'
				if rest then
					buf = rest
					if block_comment_level == 0 then
						mode = 'sexp'
					else
						block_comment_level = block_comment_level - 1
					end
					break
				end

				buf = buf:sub(2)
			elseif mode == 'string' then
				if submode == nil then
					local escape, rest = buf:match '^\\(.)(.*)$'
					if escape then
						buf = rest
						if escape == 'n' then
							str = str .. '\n'
						elseif escape == 'r' then
							str = str .. '\r'
						elseif escape == 't' then
							str = str .. '\t'
						elseif escape == 'x' then
							str_temp = ''
							submode = 'hex'
						elseif escape:match '^[0-9]$' then
							str_temp = escape
							submode = 'dec'
						elseif escape == 'u' then
							submode = 'uni{'
						else
							str = str .. escape
						end
						break
					end

					local rest = buf:match '^"(.*)$'
					if rest then
						mode = 'sexp'
						done({
							type = 'str';
							str = str;
							pos = {
								type = 'parsed';
								src = src;
								start = start_pos;
								stop = util.xtend({}, pos);
							};
						})
						buf = rest
						break
					end

					local head, rest = buf:match '^(.)(.*)$'
					if head then
						str = str .. head
						buf = rest
						break
					end
				elseif submode == 'dec' then
					if #str_temp == 3 then
						submode = nil
						str = str .. string.char(tonumber(str_temp))
						break
					end

					local head, rest = buf:match '^(.)(.*)$'
					if head then
						if head:match '%d' then
							str_temp = str_temp .. head
							buf = rest
						else
							str = str .. string.char(tonumber(str_temp))
							submode = nil
						end
						break
					end
				elseif submode == 'hex' then
					local head, rest = buf:match '^([0-9a-fA-F])(.*)$'
					if head then
						str_temp = str_temp .. head
						buf = rest
						if #str_temp == 2 then
							str = str .. string.char(tonumber(str_temp, 16))
							submode = nil
						end
						break
					end
					error 'bad'
				elseif submode == 'uni{' then
					local rest = buf:match '^{(.*)$'
					if rest then
						submode = 'uni'
						str_temp = ''
						buf = rest
						break
					end
					error 'bad'
				elseif submode == 'uni' then
					local head, rest = buf:match '^([0-9a-fA-F}])(.*)$'
					if head then
						buf = rest
						if head == '}' then
							str = str .. utf8.char(tonumber(str_temp, 16))
							submode = nil
						else
							str_temp = str_temp .. head
						end
						break
					end

					error 'bad'
				else
					error('unhandle string submode: ' .. tostring(submode))
				end
			elseif mode == 'block string' then
				if submode == 'start' then
					local head, rest = buf:match '^(.)(.*)$'
					if head == '=' then
						block_string_level1 = block_string_level1 + 1
					elseif head == '[' then
						submode = nil
					else
						error 'bad'
					end
					buf = rest
					break
				elseif submode == nil then
					local head, rest = buf:match '^(.)(.*)$'
					if head == ']' then
						submode = 'stop'
						block_string_level2 = 0
					else
						str = str .. head
					end
					buf = rest
					break
				elseif submode == 'stop' then
					local head, rest = buf:match '^(.)(.*)$'
					if head == '=' then
						block_string_level2 = block_string_level2 + 1
					elseif head == ']' and block_string_level2 == block_string_level1 then
						done({
							type = 'str';
							str = str;
							pos = {
								type = 'parsed';
								src = src;
								start = start_pos;
								stop = util.xtend({}, pos, {
									lin = pos.lin + 1;
									col = pos.col + 1;
								});
							};
						})
						mode = 'sexp'
					else
						str = str .. ']' .. ('='):rep(block_string_level2) .. head
						submode = nil
					end
					buf = rest
					break
				else
					error('unhandled block string submode: ' .. tostring(submode))
				end
			else
				error('unhandled mode: ' .. mode)
			end
			error 'bad'
		until true
		local prev
		for c in buf_:sub(1, lookahead - #buf):gmatch '.' do
			if c == '\n' or c == '\r' then
				if (prev ~= '\n' and prev ~= '\r') or prev == c then
					pos.line = pos.line + 1
					pos.col = 0
				end
			else
				pos.col = pos.col + 1
			end
			prev = c
		end
		pos.lin = pos.lin + lookahead - #buf
		buf_ = buf
		if #buf < lookahead then
			local new = h:read(lookahead - #buf)
			if new then
				buf = buf .. new
			elseif #buf == 0 then
				break
			end
		end
	end
	return root.sexps
end
