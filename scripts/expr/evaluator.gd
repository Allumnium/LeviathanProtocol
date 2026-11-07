class_name ExprEvaluator
extends RefCounted

## Compiles a type-checked AST into a tree of closures. Each closure takes an
## Env and returns a value; on a runtime error it records Env.error and returns
## null, and callers stop evaluating once an error is set.


class Env:
	extends RefCounted
	var values: Variant
	var functions: ExprFunctions
	var error: String = ""
	var error_pos: int = -1
	var _scopes: Array[Dictionary] = []

	func _init(root: Variant, registry: ExprFunctions) -> void:
		values = root
		functions = registry

	func fail(message: String, pos: int) -> Variant:
		if error.is_empty():
			error = message
			error_pos = pos
		return null

	func lookup(name: String) -> Variant:
		for index in range(_scopes.size() - 1, -1, -1):
			if _scopes[index].has(name):
				return _scopes[index][name]
		return ExprEvaluator.field(values, name)

	func push(bindings: Dictionary) -> void:
		_scopes.append(bindings)

	func pop() -> void:
		_scopes.pop_back()


## Reads a field from a Dictionary or from an object exposing expr_get(name).
static func field(owner: Variant, name: String) -> Variant:
	if owner is Dictionary:
		return owner.get(name)
	if owner is Object and owner.has_method("expr_get"):
		return owner.expr_get(name)
	return null


static func is_number(value: Variant) -> bool:
	return value is float or value is int


static func type_name(value: Variant) -> String:
	if value == null:
		return "nothing"
	if value is bool:
		return "true/false"
	if is_number(value):
		return "number"
	if value is String or value is StringName:
		return "text"
	if value is Array:
		return "list"
	return "entity"


static func equals(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if is_number(a) and is_number(b):
		return float(a) == float(b)
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	if typeof(a) != typeof(b):
		return false
	if a is Object:
		return a == b
	return a == b


func compile(node: Dictionary) -> Callable:
	var pos: int = node.get("pos", 0)
	match node.k:
		"num", "str", "bool":
			var constant: Variant = node.v
			return func(_env: Env) -> Variant: return constant
		"null":
			return func(_env: Env) -> Variant: return null
		"list":
			var items: Array[Callable] = []
			for item in node.items:
				items.append(compile(item))
			return func(env: Env) -> Variant:
				var values: Array = []
				for item in items:
					values.append(item.call(env))
					if not env.error.is_empty():
						return null
				return values
		"name":
			var name: String = node.name
			return func(env: Env) -> Variant: return env.lookup(name)
		"member":
			var owner := compile(node.obj)
			var field_name: String = node.name
			return func(env: Env) -> Variant:
				var value: Variant = owner.call(env)
				if not env.error.is_empty() or value == null:
					return null
				return ExprEvaluator.field(value, field_name)
		"index":
			return _index(node, pos)
		"unary":
			return _unary(node, pos)
		"binary":
			return _binary(node, pos)
		"if":
			var condition := compile(node.cond)
			var then_branch := compile(node.then)
			var else_branch := compile(node["else"])
			return func(env: Env) -> Variant:
				var test: Variant = condition.call(env)
				if not env.error.is_empty():
					return null
				if not test is bool:
					return env.fail("'if' condition gave %s, not true/false" % ExprEvaluator.type_name(test), pos)
				return then_branch.call(env) if test else else_branch.call(env)
		"call":
			return _call(node, pos)
	return func(env: Env) -> Variant: return env.fail("Unknown expression", pos)


func _index(node: Dictionary, pos: int) -> Callable:
	var owner := compile(node.obj)
	var index := compile(node.index)
	return func(env: Env) -> Variant:
		var list: Variant = owner.call(env)
		var at: Variant = index.call(env)
		if not env.error.is_empty():
			return null
		if not list is Array:
			return env.fail("Only lists can be indexed, not %s" % ExprEvaluator.type_name(list), pos)
		if not ExprEvaluator.is_number(at):
			return env.fail("List index must be a number", pos)
		var i := int(at)
		if i < 0 or i >= list.size():
			return null
		return list[i]


func _unary(node: Dictionary, pos: int) -> Callable:
	var arg := compile(node.arg)
	if node.op == "-":
		return func(env: Env) -> Variant:
			var value: Variant = arg.call(env)
			if not env.error.is_empty():
				return null
			if not ExprEvaluator.is_number(value):
				return env.fail("Cannot negate %s" % ExprEvaluator.type_name(value), pos)
			return -float(value)
	return func(env: Env) -> Variant:
		var value: Variant = arg.call(env)
		if not env.error.is_empty():
			return null
		if not value is bool:
			return env.fail("'not' needs true/false, got %s" % ExprEvaluator.type_name(value), pos)
		return not value


func _binary(node: Dictionary, pos: int) -> Callable:
	var op: String = node.op
	var left := compile(node.l)
	var right := compile(node.r)
	if op == "and" or op == "or":
		var stop_on := op == "or"
		return func(env: Env) -> Variant:
			var a: Variant = left.call(env)
			if not env.error.is_empty():
				return null
			if not a is bool:
				return env.fail("'%s' needs true/false, got %s" % [op, ExprEvaluator.type_name(a)], pos)
			if a == stop_on:
				return a
			var b: Variant = right.call(env)
			if not env.error.is_empty():
				return null
			if not b is bool:
				return env.fail("'%s' needs true/false, got %s" % [op, ExprEvaluator.type_name(b)], pos)
			return b
	return func(env: Env) -> Variant:
		var a: Variant = left.call(env)
		if not env.error.is_empty():
			return null
		var b: Variant = right.call(env)
		if not env.error.is_empty():
			return null
		return ExprEvaluator.apply(op, a, b, env, pos)


static func apply(op: String, a: Variant, b: Variant, env: Env, pos: int) -> Variant:
	match op:
		"==":
			return equals(a, b)
		"!=":
			return not equals(a, b)
		"in", "not in":
			var found := false
			if b is Array:
				for item in b:
					if equals(a, item):
						found = true
						break
			elif (b is String or b is StringName) and (a is String or a is StringName):
				found = str(b).contains(str(a))
			elif b == null:
				found = false
			else:
				return env.fail("'%s' needs a list or text, got %s" % [op, type_name(b)], pos)
			return found if op == "in" else not found
	if op == "+" and (a is String or b is String):
		if a is String and b is String:
			return a + b
		return env.fail("Cannot add %s and %s" % [type_name(a), type_name(b)], pos)
	if not is_number(a) or not is_number(b):
		return env.fail("'%s' needs numbers, got %s and %s" % [op, type_name(a), type_name(b)], pos)
	var x := float(a)
	var y := float(b)
	match op:
		"+":
			return x + y
		"-":
			return x - y
		"*":
			return x * y
		"/":
			return env.fail("Division by zero", pos) if y == 0.0 else x / y
		"%":
			return env.fail("Remainder by zero", pos) if y == 0.0 else fposmod(x, y)
		"^":
			var power := pow(x, y)
			return env.fail("Power has no real result", pos) if is_nan(power) or is_inf(power) else power
		"<":
			return x < y
		"<=":
			return x <= y
		">":
			return x > y
		">=":
			return x >= y
	return env.fail("Unknown operator '%s'" % op, pos)


func _call(node: Dictionary, pos: int) -> Callable:
	var name: String = node.name
	var args: Array[Callable] = []
	for index in node.args.size():
		args.append(compile(node.args[index]))
	return func(env: Env) -> Variant:
		var spec: Dictionary = env.functions.spec(name)
		var declared: Array = spec.params
		var values: Array = []
		for index in args.size():
			var param: String = declared[index] if index < declared.size() else str(spec.get("variadic", ""))
			if param.begins_with("fn:"):
				values.append(ExprEvaluator._thunk(args[index], env))
				continue
			var value: Variant = args[index].call(env)
			if not env.error.is_empty():
				return null
			if not ExprFunctions.value_fits(value, param):
				return env.fail("%s needs a %s, got %s" % [name, param.replace("|", " or "), ExprEvaluator.type_name(value)], pos)
			values.append(float(value) if value is int else value)
		var result: Variant = spec.impl.call(values, env)
		if not env.error.is_empty():
			if env.error_pos < 0:
				env.error_pos = pos
			return null
		return result


## Lazy argument: evaluates `body` with extra root names bound, such as `this`.
static func _thunk(body: Callable, env: Env) -> Callable:
	var thunk := func(bindings: Dictionary) -> Variant:
		env.push(bindings)
		var result: Variant = body.call(env)
		env.pop()
		return result
	return thunk
