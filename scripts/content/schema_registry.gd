class_name SchemaRegistry
extends RefCounted

## JSON Schema subset used for def validation, editor forms and VS Code export.
## Supported: type, properties, required, additionalProperties, propertyNames,
## items, enum, const, minimum, maximum, exclusiveMinimum, exclusiveMaximum,
## minLength, maxLength, pattern, minItems, maxItems, uniqueItems, $ref
## ("#/$defs/x" or "<schema>#/$defs/x"), $defs, anyOf, oneOf; plus x-ref,
## x-expr, x-text, x-asset and x-editor. Files whose names start with "_" are
## shared libraries rather than def types.

const SCHEMA_SUFFIX := ".schema.json"
const ANNOTATIONS := ["title", "description", "default", "examples", "$comment", "$schema", "$id", "$defs", "x-editor", "x-text", "x-order"]


## Results of validating one value: problems plus the references, formulas,
## assets and texts found, each with its JSON path.
class Collector:
	extends RefCounted
	var problems: Array[Dictionary] = []
	var refs: Array[Dictionary] = []
	var exprs: Array[Dictionary] = []
	var assets: Array[Dictionary] = []
	var texts: Array[Dictionary] = []

	func fail(path: String, message: String) -> void:
		problems.append({"path": path, "message": message})

	func absorb(other: Collector) -> void:
		problems.append_array(other.problems)
		refs.append_array(other.refs)
		exprs.append_array(other.exprs)
		assets.append_array(other.assets)
		texts.append_array(other.texts)


var _schemas: Dictionary = {}
var _regex: Dictionary = {}


func load_dir(dir_path: String, problems: ContentProblems) -> void:
	var files := DirAccess.get_files_at(dir_path)
	var sorted := Array(files)
	sorted.sort()
	for file_name: String in sorted:
		if not file_name.ends_with(SCHEMA_SUFFIX):
			continue
		var path := dir_path.path_join(file_name)
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			problems.error("Invalid JSON at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()], "", path)
			continue
		if not json.data is Dictionary:
			problems.error("Schema must be an object", "", path)
			continue
		register(file_name.trim_suffix(SCHEMA_SUFFIX), json.data)


func register(schema_name: String, schema: Dictionary) -> void:
	_schemas[schema_name] = schema


func has_schema(schema_name: String) -> bool:
	return _schemas.has(schema_name)


func get_schema(schema_name: String) -> Dictionary:
	return _schemas.get(schema_name, {})


func names() -> Array:
	var result := _schemas.keys()
	result.sort()
	return result


## Def types are schemas that are not shared "_" libraries.
func def_types() -> Array:
	return names().filter(func(schema_name: String) -> bool: return not schema_name.begins_with("_"))


func validate(schema_name: String, value: Variant) -> Collector:
	var out := Collector.new()
	if not _schemas.has(schema_name):
		out.fail("", "No schema for '%s'" % schema_name)
		return out
	_validate(_schemas[schema_name], value, "", schema_name, out)
	return out


## Normalize only schema-declared whole numbers after validation. JSON parses
## numbers as floats; seeds/UIDs deliberately remain strings.
func normalized(schema_name: String, value: Variant) -> Variant:
	return _normalize(_schemas[schema_name], value, schema_name)


func _normalize(spec: Dictionary, value: Variant, root_name: String) -> Variant:
	if value is StringName:
		return str(value)
	if spec.has("$ref"):
		var resolved := resolve_ref(spec["$ref"], root_name)
		return _normalize(resolved[0], value, resolved[1]) if not resolved.is_empty() else value
	for choice: String in ["oneOf", "anyOf"]:
		if spec.has(choice):
			for branch: Dictionary in spec[choice]:
				var trial := Collector.new()
				_validate(branch, value, "", root_name, trial)
				if trial.problems.is_empty():
					return _normalize(branch, value, root_name)
	if spec.get("type") == "integer" or (spec.get("const") is float and SaveValidation.integer(spec["const"])) or spec.get("const") is int:
		return int(value) if SaveValidation.integer(value) else value
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			var child: Variant = spec.get("properties", {}).get(key, spec.get("additionalProperties", {}))
			var normalized_key: Variant = str(key) if key is StringName else key
			result[normalized_key] = _normalize(child, value[key], root_name) if child is Dictionary else value[key]
		return result
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return _normalize(spec.get("items", {}), item, root_name))
	return value


## Resolves a $ref relative to `root_name`; returns [schema, root_name] or [].
func resolve_ref(ref: String, root_name: String) -> Array:
	var target_root := root_name
	var pointer := ref
	var hash_index := ref.find("#")
	if hash_index > 0:
		target_root = ref.substr(0, hash_index).trim_suffix(SCHEMA_SUFFIX)
		pointer = ref.substr(hash_index)
	elif hash_index < 0:
		target_root = ref.trim_suffix(SCHEMA_SUFFIX)
		pointer = "#"
	if not _schemas.has(target_root):
		return []
	var node: Variant = _schemas[target_root]
	for part in pointer.trim_prefix("#").split("/", false):
		if not node is Dictionary or not node.has(part):
			return []
		node = node[part]
	return [node, target_root] if node is Dictionary else []


static func join(path: String, key: String) -> String:
	return key if path.is_empty() else path + "." + key


static func item_path(path: String, index: int, item: Variant) -> String:
	var label := str(index)
	if item is Dictionary and item.get("id") is String and not str(item.id).is_empty():
		label = item.id
	return "%s[%s]" % [path, label]


static func json_type(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "boolean"
	if value is int:
		return "integer"
	if value is float:
		return "integer" if is_finite(value) and value == floorf(value) and absf(value) < 9.0e15 else "number"
	if value is String or value is StringName:
		return "string"
	if value is Array:
		return "array"
	if value is Dictionary:
		return "object"
	return "unknown"


static func _type_matches(actual: String, expected: String) -> bool:
	return actual == expected or (expected == "number" and actual == "integer")


static func describe(json_kind: String) -> String:
	match json_kind:
		"string":
			return "text"
		"boolean":
			return "true/false"
		"integer":
			return "a whole number"
		"number":
			return "a number"
		"array":
			return "a list"
		"object":
			return "an object"
		"null":
			return "nothing"
	return json_kind


static func same_value(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b


func _pattern(pattern: String) -> RegEx:
	if not _regex.has(pattern):
		_regex[pattern] = RegEx.create_from_string(pattern)
	return _regex[pattern]


func _validate(schema: Dictionary, value: Variant, path: String, root_name: String, out: Collector) -> void:
	if schema.has("$ref"):
		var resolved := resolve_ref(str(schema["$ref"]), root_name)
		if resolved.is_empty():
			out.fail(path, "Schema reference '%s' not found" % schema["$ref"])
			return
		_validate(resolved[0], value, path, resolved[1], out)
	if schema.has("x-expr"):
		_expr(schema["x-expr"], value, path, out)
		return
	if schema.has("anyOf") or schema.has("oneOf"):
		var exclusive := schema.has("oneOf")
		var branches: Array = schema["oneOf"] if exclusive else schema["anyOf"]
		var passing: Array[Collector] = []
		var best: Collector = null
		for branch: Dictionary in branches:
			var trial := Collector.new()
			_validate(branch, value, path, root_name, trial)
			if trial.problems.is_empty():
				passing.append(trial)
			elif best == null or trial.problems.size() < best.problems.size():
				best = trial
		if passing.is_empty():
			if best != null and branches.size() == 1:
				out.absorb(best)
			else:
				out.fail(path, "Does not match any allowed form" + ("" if best == null or best.problems.is_empty() else " (closest: %s)" % best.problems[0].message))
			return
		if exclusive and passing.size() > 1:
			out.fail(path, "Matches more than one allowed form")
			return
		out.absorb(passing[0])
	var kind := json_type(value)
	if schema.has("type"):
		var expected: Variant = schema.type
		var allowed: Array = expected if expected is Array else [expected]
		if not allowed.any(func(entry: Variant) -> bool: return _type_matches(kind, str(entry))):
			var names: Array = allowed.map(func(entry: Variant) -> String: return describe(str(entry)))
			out.fail(path, "Expected %s, got %s" % [" or ".join(names), describe(kind)])
			return
	if schema.has("const") and not same_value(value, schema["const"]):
		out.fail(path, "Must be %s" % JSON.stringify(schema["const"]))
		return
	if schema.has("enum"):
		var options: Array = schema["enum"]
		if not options.any(func(option: Variant) -> bool: return same_value(value, option)):
			var shown := ", ".join(options.map(func(option: Variant) -> String: return JSON.stringify(option)))
			out.fail(path, "Must be one of %s" % shown)
			return
	match kind:
		"string":
			_string(schema, str(value), path, out)
		"integer", "number":
			_number(schema, float(value), path, out)
		"array":
			_array(schema, value, path, root_name, out)
		"object":
			_object(schema, value, path, root_name, out)


func _string(schema: Dictionary, text: String, path: String, out: Collector) -> void:
	if schema.has("minLength") and text.length() < int(schema.minLength):
		out.fail(path, "Needs at least %d characters" % int(schema.minLength) if int(schema.minLength) > 1 else "Must not be empty")
	if schema.has("maxLength") and text.length() > int(schema.maxLength):
		out.fail(path, "At most %d characters" % int(schema.maxLength))
	if schema.has("pattern") and _pattern(str(schema.pattern)).search(text) == null:
		out.fail(path, str(schema.get("x-pattern-message", "Does not match the pattern %s" % schema.pattern)))
	if schema.has("x-ref"):
		out.refs.append({"path": path, "type": str(schema["x-ref"]), "value": text})
	if schema.has("x-asset"):
		out.assets.append({"path": path, "kind": str(schema["x-asset"]), "value": text})
	if schema.has("x-text"):
		out.texts.append({"path": path, "value": text})


func _number(schema: Dictionary, number: float, path: String, out: Collector) -> void:
	if not is_finite(number):
		out.fail(path, "Must be a finite number")
	if schema.has("minimum") and number < float(schema.minimum):
		out.fail(path, "Must be at least %s" % schema.minimum)
	if schema.has("maximum") and number > float(schema.maximum):
		out.fail(path, "Must be at most %s" % schema.maximum)
	if schema.has("exclusiveMinimum") and number <= float(schema.exclusiveMinimum):
		out.fail(path, "Must be greater than %s" % schema.exclusiveMinimum)
	if schema.has("exclusiveMaximum") and number >= float(schema.exclusiveMaximum):
		out.fail(path, "Must be less than %s" % schema.exclusiveMaximum)


func _array(schema: Dictionary, values: Array, path: String, root_name: String, out: Collector) -> void:
	if schema.has("minItems") and values.size() < int(schema.minItems):
		out.fail(path, "Needs at least %d entries" % int(schema.minItems) if int(schema.minItems) > 1 else "Must not be empty")
	if schema.has("maxItems") and values.size() > int(schema.maxItems):
		out.fail(path, "At most %d entries" % int(schema.maxItems))
	if schema.get("uniqueItems", false):
		for index in values.size():
			for other in index:
				if same_value(values[index], values[other]) or (values[index] is Dictionary and values[index] == values[other]):
					out.fail(item_path(path, index, values[index]), "Duplicate entry")
					break
	if schema.get("items") is Dictionary:
		for index in values.size():
			_validate(schema["items"], values[index], item_path(path, index, values[index]), root_name, out)


func _object(schema: Dictionary, value: Dictionary, path: String, root_name: String, out: Collector) -> void:
	var properties: Dictionary = schema.get("properties", {})
	for key in schema.get("required", []):
		if not value.has(key):
			out.fail(join(path, str(key)), "Missing required field")
	var extra: Variant = schema.get("additionalProperties", true)
	for key in value:
		var child_path := join(path, str(key))
		if schema.get("propertyNames") is Dictionary:
			_validate(schema.propertyNames, str(key), child_path, root_name, out)
		if properties.has(key):
			_validate(properties[key], value[key], child_path, root_name, out)
		elif extra is Dictionary:
			_validate(extra, value[key], child_path, root_name, out)
		elif extra == false:
			out.fail(child_path, "Unknown field%s" % _suggest(str(key), properties.keys()))


func _expr(spec: Variant, value: Variant, path: String, out: Collector) -> void:
	var expected := "any"
	if spec is Dictionary:
		expected = str(spec.get("type", "any"))
	elif spec is String:
		expected = spec
	if value is String:
		out.exprs.append({"path": path, "spec": spec if spec is Dictionary else {"type": expected}, "value": value})
		return
	var literal_ok := false
	if value is bool:
		literal_ok = ExprTypeChecker.fits("bool", expected)
	elif value is int or value is float:
		literal_ok = ExprTypeChecker.fits("number", expected)
	elif value == null:
		literal_ok = ExprTypeChecker.fits("null", expected)
	if not literal_ok:
		out.fail(path, "Expected a formula or %s value" % expected.replace("|", " or "))
		return
	out.exprs.append({"path": path, "spec": spec if spec is Dictionary else {"type": expected}, "value": value, "literal": true})


static func _suggest(name: String, known: Array) -> String:
	var best := ""
	var best_score := 0.55
	for candidate in known:
		var score := name.similarity(str(candidate))
		if score > best_score:
			best_score = score
			best = str(candidate)
	return "" if best.is_empty() else ". Did you mean '%s'?" % best
