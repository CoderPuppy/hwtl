local rules = require './rules'
return require '../continuations' {
	link_rules = rules.link_rules;
}
