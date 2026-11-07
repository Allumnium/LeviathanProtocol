class_name ExprParser
extends RefCounted

## Pratt parser producing Dictionary AST nodes, each with "k" (kind) and "pos".

const COMPARISON := ["==", "!=", "<", "<=", ">", ">="]
const BP_OR := 10
const BP_AND := 20
const BP_NOT := 30
const BP_COMPARE := 40
const BP_ADD := 50
const BP_MUL := 60
const BP_UNARY := 70
const BP_POW := 80
const BP_POSTFIX := 90

var error: String = ""
var error_pos: int = -1
var _tokens: Array = []
var _index := 0


func parse(source: String) -> Variant:
	error = ""
	error_pos = -1
	if source.strip_edges().is_empty():
		return _fail("Formula is empty", 0)
	var lexer := ExprLexer.new()
	_tokens = lexer.tokenize(source)
	if not lexer.error.is_empty():
		return _fail(lexer.error, lexer.error_pos)
	_index = 0
	var node: Variant = _expression(0)
	if node == null:
		return null
	if _peek().k != "eof":
		return _fail("Unexpected '%s'" % _text(_peek()), _peek().pos)
	return node


func _peek(offset := 0) -> Dictionary:
	return _tokens[mini(_index + offset, _tokens.size() - 1)]


func _next() -> Dictionary:
	var token := _peek()
	_index = mini(_index + 1, _tokens.size() - 1)
	return token


func _is(kind: String, value: String) -> bool:
	var token := _peek()
	return token.k == kind and token.v == value


func _expect(kind: String, value: String, context: String) -> bool:
	if _is(kind, value):
		_next()
		return true
	var token := _peek()
	var found := "the end" if token.k == "eof" else "'%s'" % _text(token)
	_fail("Expected '%s' %s, found %s" % [value, context, found], token.pos)
	return false


static func _text(token: Dictionary) -> String:
	return str(token.get("s", token.v))


func _fail(message: String, pos: int) -> Variant:
	if error.is_empty():
		error = message
		error_pos = pos
	return null


func _expression(min_bp: int) -> Variant:
	var left: Variant = _prefix()
	if left == null:
		return null
	while true:
		var token := _peek()
		var bp := _infix_bp(token)
		if bp <= min_bp:
			break
		left = _infix(left, bp)
		if left == null:
			return null
	return left


func _infix_bp(token: Dictionary) -> int:
	if token.k == "kw":
		match token.v:
			"or":
				return BP_OR
			"and":
				return BP_AND
			"in":
				return BP_COMPARE
			"not":
				return BP_COMPARE if _peek(1).k == "kw" and _peek(1).v == "in" else 0
		return 0
	if token.k != "op":
		return 0
	if token.v in COMPARISON:
		return BP_COMPARE
	match token.v:
		"+", "-":
			return BP_ADD
		"*", "/", "%":
			return BP_MUL
		"^":
			return BP_POW
		".", "[", "(":
			return BP_POSTFIX
	return 0


func _prefix() -> Variant:
	var token := _next()
	match token.k:
		"num":
			return {"k": "num", "v": float(token.v), "pos": token.pos}
		"str":
			return {"k": "str", "v": token.v, "pos": token.pos}
		"name":
			return {"k": "name", "name": token.v, "pos": token.pos}
		"eof":
			return _fail("Formula ends too early", token.pos)
		"kw":
			match token.v:
				"true", "false":
					return {"k": "bool", "v": token.v == "true", "pos": token.pos}
				"null":
					return {"k": "null", "pos": token.pos}
				"not":
					var operand: Variant = _expression(BP_NOT)
					return null if operand == null else {"k": "unary", "op": "not", "arg": operand, "pos": token.pos}
				"if":
					return _if(token)
			return _fail("Unexpected '%s'" % _text(token), token.pos)
	match token.v:
		"-":
			var operand: Variant = _expression(BP_UNARY)
			return null if operand == null else {"k": "unary", "op": "-", "arg": operand, "pos": token.pos}
		"(":
			var inner: Variant = _expression(0)
			if inner == null or not _expect("op", ")", "to close '('"):
				return null
			return inner
		"[":
			var items: Variant = _arguments("]", "to close the list")
			return null if items == null else {"k": "list", "items": items, "pos": token.pos}
	return _fail("Unexpected '%s'" % _text(token), token.pos)


func _if(token: Dictionary) -> Variant:
	var condition: Variant = _expression(0)
	if condition == null or not _expect("kw", "then", "after the if condition"):
		return null
	var then_branch: Variant = _expression(0)
	if then_branch == null or not _expect("kw", "else", "after the then value"):
		return null
	var else_branch: Variant = _expression(0)
	if else_branch == null:
		return null
	return {"k": "if", "cond": condition, "then": then_branch, "else": else_branch, "pos": token.pos}


func _arguments(closer: String, context: String) -> Variant:
	var items: Array = []
	if _is("op", closer):
		_next()
		return items
	while true:
		var item: Variant = _expression(0)
		if item == null:
			return null
		items.append(item)
		if _is("op", ","):
			_next()
			continue
		if not _expect("op", closer, context):
			return null
		return items
	return null


func _infix(left: Dictionary, bp: int) -> Variant:
	var token := _next()
	if token.k == "kw":
		if token.v == "not":
			_next()
			var negated: Variant = _expression(bp)
			return null if negated == null else _no_chain({"k": "binary", "op": "not in", "l": left, "r": negated, "pos": token.pos})
		var right: Variant = _expression(bp)
		if right == null:
			return null
		var node := {"k": "binary", "op": token.v, "l": left, "r": right, "pos": token.pos}
		return _no_chain(node) if token.v == "in" else node
	match token.v:
		".":
			var field := _next()
			if field.k != "name" and field.k != "kw":
				return _fail("Expected a field name after '.'", field.pos)
			return {"k": "member", "obj": left, "name": field.v, "pos": field.pos}
		"[":
			var index: Variant = _expression(0)
			if index == null or not _expect("op", "]", "to close '['"):
				return null
			return {"k": "index", "obj": left, "index": index, "pos": token.pos}
		"(":
			if left.k != "name":
				return _fail("Only named functions can be called", token.pos)
			var args: Variant = _arguments(")", "to close the call")
			return null if args == null else {"k": "call", "name": left.name, "args": args, "pos": left.pos}
		"^":
			# Right-associative: 2^3^2 is 2^(3^2).
			var exponent: Variant = _expression(bp - 1)
			return null if exponent == null else {"k": "binary", "op": "^", "l": left, "r": exponent, "pos": token.pos}
	var rhs: Variant = _expression(bp)
	if rhs == null:
		return null
	var binary := {"k": "binary", "op": token.v, "l": left, "r": rhs, "pos": token.pos}
	return _no_chain(binary) if token.v in COMPARISON else binary


## Comparisons do not chain: a < b < c is almost always a mistake.
func _no_chain(node: Dictionary) -> Variant:
	if _infix_bp(_peek()) == BP_COMPARE:
		return _fail("Comparisons cannot be chained; join them with 'and'", _peek().pos)
	return node
