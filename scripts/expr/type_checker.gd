class_name ExprTypeChecker
extends RefCounted

## Static types: number, bool, string, list, entity, any, null. A namespace is a
## Dictionary in the context schema; its leaves are type names. "*" inside a
## namespace types any field name, such as vars.<name>.

const TYPES := ["number", "bool", "string", "list", "entity", "any", "null"]
const ARITHMETIC := ["+", "-", "*", "/", "%", "^"]
const ORDERING := ["<", "<=", ">", ">="]

var errors: Array[Dictionary] = []
var reads: Dictionary = {}
var _functions: ExprFunctions
var _scopes: Array[Dictionary] = []


func check(node: Dictionary, schema: Dictionary, functions: ExprFunctions) -> String:
	errors.clear()
	reads.clear()
	_functions = functions
	_scopes = [schema]
	var result := _value(node)
	return result


func _error(node: Dictionary, message: String) -> String:
	errors.append({"pos": int(node.get("pos", 0)), "message": message})
	return "error"


func _lookup_root(name: String) -> Variant:
	for index in range(_scopes.size() - 1, -1, -1):
		if _scopes[index].has(name):
			return _scopes[index][name]
	return null


func _schema_type(value: Variant) -> String:
	return "namespace" if value is Dictionary else str(value)


func _type(node: Dictionary) -> String:
	var kind: String = node.k
	match kind:
		"num":
			node.t = "number"
		"str":
			node.t = "string"
		"bool":
			node.t = "bool"
		"null":
			node.t = "null"
		"list":
			node.t = "list"
			for item in node.items:
				if _type(item) == "namespace":
					_namespace_misuse(item)
		"name":
			node.t = _name(node)
		"member":
			node.t = _member(node)
		"index":
			node.t = _index(node)
		"unary":
			node.t = _unary(node)
		"binary":
			node.t = _binary(node)
		"if":
			node.t = _if(node)
		"call":
			node.t = _call(node)
		_:
			node.t = _error(node, "Unknown expression")
	return node.t


func _name(node: Dictionary) -> String:
	var found: Variant = _lookup_root(node.name)
	if found == null:
		var known: Array = []
		for scope in _scopes:
			known.append_array(scope.keys())
		if _functions.has(node.name):
			return _error(node, "'%s' is a function; call it with ( )" % node.name)
		return _error(node, "Unknown name '%s'%s" % [node.name, _suggest(node.name, known)])
	node.path = node.name
	if not found is Dictionary:
		reads[node.name] = true
	return _schema_type(found)


func _member(node: Dictionary) -> String:
	var owner := _type(node.obj)
	if owner == "error":
		return owner
	if owner == "namespace":
		var space: Dictionary = _namespace_of(node.obj)
		var path: String = node.obj.path + "." + node.name
		node.path = path
		if space.has(node.name):
			if not space[node.name] is Dictionary:
				reads[path] = true
			return _schema_type(space[node.name])
		if space.has("*"):
			if not space["*"] is Dictionary:
				reads[path] = true
			return _schema_type(space["*"])
		return _error(node, "Unknown field '%s' in %s%s" % [node.name, node.obj.path, _suggest(node.name, space.keys())])
	if owner == "entity" or owner == "any":
		return "any"
	return _error(node, "A %s has no fields" % owner)


func _namespace_of(node: Dictionary) -> Dictionary:
	if node.k == "name":
		return _lookup_root(node.name)
	var parent := _namespace_of(node.obj)
	return parent.get(node.name, parent.get("*", {}))


func _namespace_misuse(node: Dictionary) -> String:
	return _error(node, "'%s' is a group; pick a field, such as %s.<name>" % [node.get("path", "?"), node.get("path", "?")])


func _value(node: Dictionary) -> String:
	var result := _type(node)
	return _namespace_misuse(node) if result == "namespace" else result


func _index(node: Dictionary) -> String:
	var owner := _value(node.obj)
	var index := _value(node.index)
	if owner == "error" or index == "error":
		return "error"
	if owner != "list" and owner != "any":
		return _error(node, "Only lists can be indexed, not a %s" % owner)
	if not _fits(index, "number"):
		return _error(node.index, "List index must be a number")
	return "any"


func _unary(node: Dictionary) -> String:
	var arg := _value(node.arg)
	if arg == "error":
		return arg
	if node.op == "-":
		return "number" if _fits(arg, "number") else _error(node, "Cannot negate a %s" % arg)
	return "bool" if _fits(arg, "bool") else _error(node, "'not' needs true/false, not a %s" % arg)


func _binary(node: Dictionary) -> String:
	var op: String = node.op
	var left := _value(node.l)
	var right := _value(node.r)
	if left == "error" or right == "error":
		return "error"
	if op == "and" or op == "or":
		if not _fits(left, "bool"):
			return _error(node.l, "'%s' needs true/false on the left, not a %s" % [op, left])
		if not _fits(right, "bool"):
			return _error(node.r, "'%s' needs true/false on the right, not a %s" % [op, right])
		return "bool"
	if op == "+" and (left == "string" or right == "string"):
		if (left == "string" or left == "any") and (right == "string" or right == "any"):
			return "string"
		return _error(node, "Cannot add a %s and a %s" % [left, right])
	if op in ARITHMETIC:
		if not _fits(left, "number") or not _fits(right, "number"):
			return _error(node, "'%s' needs numbers, not %s and %s" % [op, left, right])
		return "number"
	if op in ORDERING:
		if not _fits(left, "number") or not _fits(right, "number"):
			return _error(node, "'%s' compares numbers, not %s and %s" % [op, left, right])
		return "bool"
	if op == "==" or op == "!=":
		if left != right and left != "any" and right != "any" and left != "null" and right != "null":
			return _error(node, "Comparing a %s with a %s is always %s" % [left, right, "false" if op == "==" else "true"])
		return "bool"
	if op == "in" or op == "not in":
		if right != "list" and right != "string" and right != "any":
			return _error(node.r, "'%s' needs a list or text on the right, not a %s" % [op, right])
		if right == "string" and not _fits(left, "string"):
			return _error(node.l, "Only text can be found inside text")
		return "bool"
	return _error(node, "Unknown operator '%s'" % op)


func _if(node: Dictionary) -> String:
	var condition := _value(node.cond)
	var then_type := _value(node.then)
	var else_type := _value(node["else"])
	if condition == "error" or then_type == "error" or else_type == "error":
		return "error"
	if not _fits(condition, "bool"):
		return _error(node.cond, "'if' needs a true/false condition, not a %s" % condition)
	return unify(then_type, else_type, node)


func unify(a: String, b: String, node: Dictionary) -> String:
	if a == b:
		return a
	if a == "null":
		return b
	if b == "null":
		return a
	if a == "any" or b == "any":
		return "any"
	return _error(node, "Branches give a %s and a %s; make them the same kind" % [a, b])


func _call(node: Dictionary) -> String:
	if not _functions.has(node.name):
		if _lookup_root(node.name) != null:
			return _error(node, "'%s' is a value, not a function" % node.name)
		return _error(node, "Unknown function '%s'%s" % [node.name, _suggest(node.name, _functions.names())])
	var spec: Dictionary = _functions.spec(node.name)
	var args: Array = node.args
	var params: Array = spec.params
	var variadic: String = spec.get("variadic", "")
	var minimum: int = spec.get("min_args", params.size())
	var maximum: int = -1 if not variadic.is_empty() else params.size()
	if args.size() < minimum or (maximum >= 0 and args.size() > maximum):
		var expected := str(minimum) if minimum == maximum else ("%d or more" % minimum if maximum < 0 else "%d-%d" % [minimum, maximum])
		return _error(node, "%s takes %s values, got %d" % [node.name, expected, args.size()])
	var failed := false
	for index in args.size():
		var param: String = params[index] if index < params.size() else variadic
		if param.begins_with("fn:"):
			_scopes.append(spec.get("binds", {}))
			var lazy := _value(args[index])
			_scopes.pop_back()
			if lazy == "error":
				failed = true
			elif not _fits(lazy, param.substr(3)):
				failed = true
				_error(args[index], "%s needs a %s here, not a %s" % [node.name, param.substr(3), lazy])
			continue
		var actual := _value(args[index])
		if actual == "error":
			failed = true
		elif not _fits(actual, param):
			failed = true
			_error(args[index], "%s needs a %s here, not a %s" % [node.name, param.replace("|", " or "), actual])
	return "error" if failed else str(spec.returns)


## Whether a statically typed value may be used where `expected` is needed;
## "any" defers the check to evaluation. `expected` may be a union, "a|b".
static func _fits(actual: String, expected: String) -> bool:
	if actual == "any" or expected == "any":
		return true
	return actual in expected.split("|")


static func fits(actual: String, expected: String) -> bool:
	return _fits(actual, expected)


static func _suggest(name: String, known: Array) -> String:
	var best := ""
	var best_score := 0.55
	for candidate in known:
		var text := str(candidate)
		if text == "*":
			continue
		var score := name.similarity(text)
		if score > best_score:
			best_score = score
			best = text
	return "" if best.is_empty() else ". Did you mean '%s'?" % best
