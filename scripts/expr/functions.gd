class_name ExprFunctions
extends RefCounted

## Whitelisted formula functions. Each spec has params (type names, "a|b"
## unions or "fn:<type>" for lazily evaluated arguments), returns, an impl
## Callable(args: Array, env: ExprEvaluator.Env) -> Variant, and optionally
## variadic, min_args, binds (extra root names for lazy arguments) and help.

var _specs: Dictionary = {}


static func standard() -> ExprFunctions:
	var registry := ExprFunctions.new()
	registry.register("min", [], "number", func(a: Array, _env: Variant) -> Variant: return a.reduce(func(x: float, y: Variant) -> float: return minf(x, float(y)), INF), {"variadic": "number", "min_args": 2, "help": "Smallest value"})
	registry.register("max", [], "number", func(a: Array, _env: Variant) -> Variant: return a.reduce(func(x: float, y: Variant) -> float: return maxf(x, float(y)), -INF), {"variadic": "number", "min_args": 2, "help": "Largest value"})
	registry.register("clamp", ["number", "number", "number"], "number", func(a: Array, _env: Variant) -> Variant: return clampf(a[0], a[1], a[2]), {"help": "clamp(x, low, high)"})
	registry.register("abs", ["number"], "number", func(a: Array, _env: Variant) -> Variant: return absf(a[0]))
	registry.register("floor", ["number"], "number", func(a: Array, _env: Variant) -> Variant: return floorf(a[0]))
	registry.register("ceil", ["number"], "number", func(a: Array, _env: Variant) -> Variant: return ceilf(a[0]))
	registry.register("round", ["number"], "number", func(a: Array, _env: Variant) -> Variant: return roundf(a[0]))
	registry.register("sqrt", ["number"], "number", _sqrt)
	registry.register("lerp", ["number", "number", "number"], "number", func(a: Array, _env: Variant) -> Variant: return lerpf(a[0], a[1], a[2]), {"help": "lerp(from, to, weight)"})
	registry.register("between", ["number", "number", "number"], "bool", func(a: Array, _env: Variant) -> Variant: return a[0] >= a[1] and a[0] <= a[2], {"help": "between(x, low, high), inclusive"})
	registry.register("len", ["list|string"], "number", func(a: Array, _env: Variant) -> Variant: return float(a[0].length() if a[0] is String else a[0].size()))
	return registry


static func _sqrt(args: Array, env: Variant) -> Variant:
	if args[0] < 0.0:
		return env.fail("sqrt of a negative number", -1)
	return sqrt(args[0])


func register(name: String, params: Array, returns: String, impl: Callable, options: Dictionary = {}) -> void:
	var spec := options.duplicate()
	spec.params = params
	spec.returns = returns
	spec.impl = impl
	_specs[name] = spec


func has(name: String) -> bool:
	return _specs.has(name)


func spec(name: String) -> Dictionary:
	return _specs.get(name, {})


func names() -> Array:
	var result := _specs.keys()
	result.sort()
	return result


## A registry extended with more functions; the original is unchanged.
func extended() -> ExprFunctions:
	var copy := ExprFunctions.new()
	copy._specs = _specs.duplicate()
	return copy


## Runtime check for arguments whose static type was "any".
static func value_fits(value: Variant, expected: String) -> bool:
	for kind in expected.split("|"):
		match kind:
			"any":
				return true
			"number":
				if value is float or value is int:
					return true
			"bool":
				if value is bool:
					return true
			"string":
				if value is String or value is StringName:
					return true
			"list":
				if value is Array:
					return true
			"entity":
				if value is Dictionary or value is Object:
					return true
			"null":
				if value == null:
					return true
	return false
