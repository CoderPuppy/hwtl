local P = require 'lpeg'
local util = require './util'

return function(name, str)
	return P.match(P.P { name;
		main = P.V'init_pos' * P.V'expr'^0/table.pack;
		expr = (
			P.Cg('tmp1', P.V'get_pos') *
			P.Cg('tmp2',
				('(' * P.V'space'^0 * (P.V'expr' * P.V'space'^0)^0 * ')') / function(...)
					local n = select('#', ...)
					local stop = select(n, ...).stop
					return {
						type = 'list';
						n = n;
						stop = util.xtend(stop, { pos = stop.pos + 1; col = stop.col + 1; });
						...
					}
				end +
				P.V'ident' / function(i)
					return { type = 'sym'; name = i; }
				end +
				(P.V'get_pos' * P.C(P.S',\'`' + P.P'#\'' + P.P'#`') * P.V'get_pos' * P.V'expr') / function(start, pre, stop, expr)
					return {
						type = 'list';
						n = 2;
						start = start;
						stop = expr.stop;
						{
							type = 'sym';
							name = 'unquote';
							pos = {
								type = 'parsed';
								start = start;
								stop = stop;
							};
						};
						expr;
					}
				end
			) *
			P.Cg((P.Cb('tmp2') * P.V'get_pos') / function(expr, stop)
				return expr.stop or stop
			end, 'pos') *
			(P.Cb('tmp2') * P.Cb('tmp1') * P.V'get_pos') / function(expr, start, stop)
				if not expr.start then
					expr.start = start
				end
				if not expr.stop then
					expr.stop = stop
				end
				return expr
			end
		);
		get_pos = (P.Cp() * P.Cb'pos') / function(pos1, pos2)
			return { line = pos2.line; col = pos1 - pos2.pos; pos = pos1; }
		end;
		init_pos = P.Cg(P.Cc { line = 1; pos = 1; }, 'pos');
		ident = P.C((P.P(1) - P.S'()[]{};\n\r \t,\'`' - P.P'#|' - P.P'#\'' - P.P'#`') * (P.P(1) - P.S'()[]{};\n\r \t' - P.P'#|')^0);
		comment = 
			(';' * (P.P(1) - P.S'\r\n')^0 * P.V'eol') +
			('#|' * (P.P(1) - P.P'|#')^0 * '|#');
		space = (
			P.V'comment' +
			P.S'\n\r \t'
		)^1;
		eol =
			(P.P'\r\n' + P.P'\n\r' + P.P'\r' + P.P '\n' + -P.P(1)) *
			P.Cg((P.Cb('pos') * P.Cp()) / function(prev, cur)
			end, 'pos');
	}, str)
end
