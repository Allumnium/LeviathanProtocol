class_name LegacyHexRecipe
extends RefCounted

# Frozen archive footprints only. No active matching, grants or material rules.

const DATA_PATH := "res://data/legacy/hex_recipes.json"
const TOPOLOGY := "hex_axial_v1"
static var _recipes: Dictionary = {}

static func key(equipment_id: String, rank := 1) -> String:
	return "%s/%d" % [equipment_id, rank]

static func catalog() -> Dictionary:
	if _recipes.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		var errors := validate(data)
		if not errors.is_empty():
			push_error("Invalid hex recipes: %s" % "; ".join(errors))
			return {}
		for recipe: Dictionary in data.recipes:
			_recipes[key(recipe.equipment_id, int(recipe.rank))] = recipe
	return _recipes.duplicate(true)

static func find(equipment_id: String, rank := 1) -> Dictionary:
	if _recipes.is_empty():
		catalog()
	return _recipes.get(key(equipment_id, rank), {}).duplicate(true)

# The JSON lists axial cells explicitly. Legacy square blueprints never enter
# this path. Material counts and equipment IDs survive; geometry is hex-native.
static func cells(recipe: Dictionary, turns := 0, flipped := false, origin := Vector2i.ZERO) -> Dictionary:
	var result := {}
	for item: Array in recipe.get("cells", []):
		result[origin + LegacyHexGrid.transform(Vector2i(int(item[0]), int(item[1])), turns, flipped)] = int(item[2])
	return result

static func integer(value: Variant, minimum := -4096, maximum := 4096) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value == floorf(float(value)) and value >= minimum and value <= maximum

static func read_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and integer(value[0]) and integer(value[1])

static func validate(data: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not data is Dictionary or data.get("schema_version") != 1 or data.get("topology") != TOPOLOGY or not data.get("recipes") is Array:
		return ["Unsupported hex recipe schema."]
	var seen := {}
	if data.recipes.size() != 58:
		return ["Incomplete frozen hex recipe catalog."]
	for entry: Variant in data.recipes:
		if not entry is Dictionary or not entry.get("equipment_id") is String or not integer(entry.get("rank"), 1, 3) or not integer(entry.get("revision"), 1):
			errors.append("Invalid recipe identity.")
			continue
		var id := key(entry.equipment_id, int(entry.rank))
		if entry.equipment_id.is_empty() or seen.has(id):
			errors.append("Unknown or repeated recipe: %s" % id)
		seen[id] = true
		if not entry.get("cells") is Array or entry.cells.is_empty() or entry.cells.size() > 64:
			errors.append("Invalid cells: %s" % id)
			continue
		var layout := {}
		var valid := true
		for item: Variant in entry.cells:
			if not item is Array or item.size() != 3 or not integer(item[0], -32, 32) or not integer(item[1], -32, 32) or not integer(item[2], 0, 3):
				valid = false
				break
			var cell := Vector2i(int(item[0]), int(item[1]))
			if layout.has(cell):
				valid = false
			layout[cell] = int(item[2])
		var footprint: Array[Vector2i] = []
		footprint.assign(layout.keys())
		if not valid or not LegacyHexGrid.connected(footprint):
			errors.append("Duplicate, disconnected or invalid cells: %s" % id)
			continue
	return errors
