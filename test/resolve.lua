local rules = require './rules'
return require '../resolve' {
	continuations = require './continuations';
	constant_folding_rules = rules.const_rules;
	call_rules = rules.call_rules;
	backend = {
		-- TODO: unboxed values
		type = function(v) return v.type end;
	};
}
