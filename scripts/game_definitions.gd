class_name GameDefinitions
extends RefCounted

# Content revisions are independent of blueprint/archive/run save versions.
const SCHEMA_VERSION := 1
const DATA_PATH := "res://data/definitions.json"
const DOMAINS := [
	"materials", "equipment", "research", "encounters", "nodes", "edges",
	"abilities", "environments", "goods",
]
const REQUIRED_FIELDS := {
	"materials": {"serialized_id": TYPE_FLOAT, "symbol": TYPE_STRING, "target_purchase_price": TYPE_FLOAT},
	"equipment": {"type_id": TYPE_FLOAT, "enum_key": TYPE_STRING, "recipe": TYPE_STRING,
		"capstone": TYPE_BOOL, "regular_slots_only": TYPE_BOOL, "offensive_capstone": TYPE_BOOL,
		"ability_ids": TYPE_ARRAY, "ranks": TYPE_ARRAY},
	"research": {"cost_rp": TYPE_FLOAT, "prerequisite_ids": TYPE_ARRAY, "story_gate_ids": TYPE_ARRAY,
		"family_id": TYPE_STRING, "path_id": TYPE_STRING, "exclusion_ids": TYPE_ARRAY, "grants": TYPE_DICTIONARY},
	"encounters": {"objective_rule": TYPE_STRING, "threat_multiplier": TYPE_FLOAT,
		"required_entity_ids": TYPE_ARRAY, "frozen_roster": TYPE_ARRAY, "finite_waves": TYPE_ARRAY,
		"reward": TYPE_DICTIONARY, "environment_ids": TYPE_ARRAY},
	"nodes": {"inhabited_default": TYPE_BOOL, "combat": TYPE_BOOL, "goods_grade_id": TYPE_STRING},
	"edges": {"duration_seconds": TYPE_ARRAY, "environment_ids": TYPE_ARRAY,
		"mining_potential": TYPE_BOOL, "grants_rp": TYPE_BOOL, "surprise_aliens": TYPE_BOOL},
	"abilities": {"source_equipment_id": TYPE_STRING, "cooldown_seconds": TYPE_FLOAT,
		"target_rule": TYPE_STRING, "capstone": TYPE_BOOL, "cooldown_scope": TYPE_STRING,
		"clock": TYPE_STRING, "initial_cooldown_fraction": TYPE_FLOAT},
	"environments": {"clock": TYPE_STRING, "affects_both_factions": TYPE_BOOL, "tuning": TYPE_DICTIONARY},
	"goods": {"unit_value": TYPE_FLOAT, "freeze_value_on_load": TYPE_BOOL, "settlement_order": TYPE_ARRAY},
}

static var _registry: Dictionary = {}


static func _data() -> Dictionary:
	if not _registry.is_empty():
		return _registry
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var errors := validate(parsed)
	if not errors.is_empty():
		push_error("Invalid game definitions: %s" % "; ".join(errors))
		return {}
	_registry = parsed
	return _registry


static func snapshot() -> Dictionary:
	return _data().duplicate(true)


static func entries(domain: String, implemented_only := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _data().get(domain, []):
		if not implemented_only or entry.implemented:
			result.append(entry.duplicate(true))
	return result


static func find(domain: String, id: String) -> Dictionary:
	for entry: Dictionary in _data().get(domain, []):
		if entry.id == id:
			return entry.duplicate(true)
	return {}


static func equipment(type_id: int) -> Dictionary:
	for entry: Dictionary in _data().get("equipment", []):
		if int(entry.type_id) == type_id:
			return entry.duplicate(true)
	return {}


static func material_name(serialized_id: int) -> String:
	for entry: Dictionary in _data().get("materials", []):
		if int(entry.serialized_id) == serialized_id:
			return entry.display_name
	return "Unknown"


static func validate(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		return ["Registry must be an object."]
	if value.get("schema_version") != SCHEMA_VERSION:
		errors.append("Unsupported definition schema version.")
	if not value.get("content_revision") is String or value.get("content_revision", "").is_empty():
		errors.append("Missing content revision.")
	var ids: Dictionary = {}
	for domain in DOMAINS:
		ids[domain] = {}
		if not value.get(domain) is Array:
			errors.append("Missing definition array: %s" % domain)
			continue
		for entry in value[domain]:
			if not entry is Dictionary:
				errors.append("Definition must be an object: %s" % domain)
				continue
			var id: Variant = entry.get("id")
			if not id is String or id.is_empty():
				errors.append("Missing stable ID: %s" % domain)
				continue
			if ids[domain].has(id):
				errors.append("Duplicate %s ID: %s" % [domain, id])
			ids[domain][id] = true
			if not _positive_integer(entry.get("revision")):
				errors.append("Invalid revision: %s/%s" % [domain, id])
			if not entry.get("implemented") is bool or not entry.get("display_name") is String:
				errors.append("Missing status/name: %s/%s" % [domain, id])
			for field in REQUIRED_FIELDS[domain]:
				var expected: int = REQUIRED_FIELDS[domain][field]
				var actual := typeof(entry.get(field))
				if actual != expected and not (expected == TYPE_FLOAT and actual == TYPE_INT):
					errors.append("Invalid field: %s/%s/%s" % [domain, id, field])
	# Stop before reference checks when the envelope is malformed.
	if not errors.is_empty():
		return errors
	var type_ids: Dictionary = {}
	for entry in value.equipment:
		var type_id: Variant = entry.get("type_id")
		if not _nonnegative_integer(type_id) or type_ids.has(type_id):
			errors.append("Invalid or duplicate equipment type ID: %s" % entry.id)
		type_ids[type_id] = true
		if not entry.get("recipe") is String or not _valid_recipe(entry.get("recipe", "")):
			errors.append("Invalid material recipe: %s" % entry.id)
		for ability_id in entry.get("ability_ids", []):
			_check_reference(ids, "abilities", ability_id, errors)
		for rank in entry.get("ranks", []):
			if not rank is Dictionary or not _positive_integer(rank.get("rank")) or not rank.get("recipe") is String or not _valid_recipe(rank.recipe):
				errors.append("Invalid equipment rank: %s" % entry.id)
	if errors.is_empty():
		errors.append_array(MaterialRecipe.validate_registry(value.equipment))
	for entry in value.research:
		if not _nonnegative_integer(entry.get("cost_rp")) or not entry.get("grants") is Dictionary:
			errors.append("Invalid research cost/grants: %s" % entry.id)
			continue
		for key in ["prerequisite_ids", "exclusion_ids"]:
			for id in entry.get(key, []):
				_check_reference(ids, "research", id, errors)
		for key in ["equipment_ids", "ability_ids", "ranks", "modifiers"]:
			if not entry.grants.get(key) is Array:
				errors.append("Missing grant array: %s/%s" % [entry.id, key])
		if not errors.is_empty():
			return errors
		for id in entry.grants.get("equipment_ids", []):
			_check_reference(ids, "equipment", id, errors)
		for id in entry.grants.get("ability_ids", []):
			_check_reference(ids, "abilities", id, errors)
		for rank in entry.grants.get("ranks", []):
			if rank is Dictionary:
				_check_reference(ids, "equipment", rank.get("equipment_id"), errors)
				if not _positive_integer(rank.get("rank")):
					errors.append("Invalid granted rank: %s" % entry.id)
			else:
				errors.append("Invalid rank grant: %s" % entry.id)
	if errors.is_empty():
		errors.append_array(ResearchRules.validate_registry(value))
	for entry in value.abilities:
		_check_reference(ids, "equipment", entry.get("source_equipment_id"), errors)
		if not _nonnegative_integer(entry.get("cooldown_seconds")):
			errors.append("Invalid cooldown: %s" % entry.id)
	for entry in value.nodes:
		if entry.get("goods_grade_id", "") != "":
			_check_reference(ids, "goods", entry.goods_grade_id, errors)
	for domain in ["encounters", "edges"]:
		for entry in value[domain]:
			for id in entry.get("environment_ids", []):
				_check_reference(ids, "environments", id, errors)
	for entry in value.goods:
		if not _nonnegative_integer(entry.get("unit_value")):
			errors.append("Invalid goods unit value: %s" % entry.id)
	return errors


static func _check_reference(ids: Dictionary, domain: String, id: Variant, errors: Array[String]) -> void:
	if not id is String or not ids[domain].has(id):
		errors.append("Unknown %s reference: %s" % [domain, id])


static func _positive_integer(value: Variant) -> bool:
	return _nonnegative_integer(value) and value > 0


static func _nonnegative_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(value)


static func _valid_recipe(recipe: String) -> bool:
	if recipe.is_empty():
		return false
	var rows := recipe.split("/")
	var width := rows[0].length()
	var occupied := false
	for row in rows:
		if row.length() != width or row.is_empty():
			return false
		for symbol in row:
			if symbol not in ["O", "D", "T", "C", "."]:
				return false
			occupied = occupied or symbol != "."
	return occupied
