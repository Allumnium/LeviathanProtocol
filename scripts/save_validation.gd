class_name SaveValidation
extends RefCounted

# Shared wire-format checks. These do not load a historical run or its economy.
static func integer(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and absf(value) <= 9007199254740991.0 and value == floor(value)

static func bounded_number(value: Variant) -> bool:
	return number(value) and absf(float(value)) <= 9007199254740991.0

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)

static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0]) and number(value[1])

static func node(value: Variant, count: int, allow_none := false) -> bool:
	return integer(value) and value >= (-1 if allow_none else 0) and value < count

static func same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

static func json_value(value: Variant, depth := 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is String:
		return true
	if value is int or value is float:
		return is_finite(value)
	if value is Dictionary:
		for key in value:
			if not key is String or not json_value(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item in value:
			if not json_value(item, depth + 1):
				return false
		return true
	return false
