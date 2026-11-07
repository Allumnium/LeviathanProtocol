class_name ExprContexts
extends RefCounted

## Named formula contexts. A schema field declares
## "x-expr": {"type": "bool", "context": "site"}; the context supplies the
## names the formula may read and any extra functions. Systems register their
## contexts as they are added. "static" has no names: literals and the
## standard functions only.

const STATIC := "static"

static var _contexts: Dictionary = {}


static func register(context_name: String, schema: Dictionary, functions: ExprFunctions = null) -> void:
	_ensure()
	_contexts[context_name] = {"schema": schema, "functions": functions}


static func unregister(context_name: String) -> void:
	_ensure()
	if context_name != STATIC:
		_contexts.erase(context_name)


static func has(context_name: String) -> bool:
	_ensure()
	return _contexts.has(context_name)


static func schema(context_name: String) -> Dictionary:
	_ensure()
	return _contexts.get(context_name, {}).get("schema", {})


static func functions(context_name: String) -> ExprFunctions:
	_ensure()
	return _contexts.get(context_name, {}).get("functions")


static func names() -> Array:
	_ensure()
	var result := _contexts.keys()
	result.sort()
	return result


static func compile(text: String, context_name: String, expected_type: String) -> Formula:
	return Formula.compile(text, schema(context_name), expected_type, functions(context_name))


static func _ensure() -> void:
	if not _contexts.has(STATIC):
		_contexts[STATIC] = {"schema": {}, "functions": null}
