class_name SchemaExporter
extends RefCounted

## Turns the def schemas into plain JSON Schema (draft-07) for text editors
## such as VS Code. `_common#` refs become file refs, extension keywords become
## descriptions and patterns, and every def type gains the envelope fields.
## def_file and pack schemas dispatch on "def". Run tools/export_schemas.gd
## after editing schemas/defs; test_packs fails while the export is stale.

const OUT_DIR := "res://schemas/json"
const DRAFT := "http://json-schema.org/draft-07/schema#"
const SUFFIX := SchemaRegistry.SCHEMA_SUFFIX
const DEF_FILE := "def_file" + SUFFIX
const PACK_FILE := "pack" + SUFFIX
const PATCH_FILE := PackLoader.PATCH + SUFFIX
const DROPPED := ["$schema", "$id", "x-editor", "x-order", "x-text"]


## File name -> JSON text for every exported schema.
static func render(schema_dirs: Array = Content.SCHEMA_DIRS) -> Dictionary:
	var registry := SchemaRegistry.new()
	var problems := ContentProblems.new()
	for dir_path: String in schema_dirs:
		registry.load_dir(dir_path, problems)
	var types: Array = registry.def_types()
	types.sort()
	var schemas := {}
	for schema_name: String in registry.names():
		var converted: Dictionary = _convert(registry.get_schema(schema_name))
		schemas[schema_name + SUFFIX] = converted if schema_name.begins_with("_") else _def_schema(schema_name, converted)
	schemas[PATCH_FILE] = _patch_schema(types)
	schemas[DEF_FILE] = _def_file_schema(types)
	schemas[PACK_FILE] = _pack_schema()
	var texts := {}
	for file_name: String in schemas:
		texts[file_name] = JSON.stringify(_integers(schemas[file_name]), "\t", false) + "\n"
	return texts


## Writes the rendered files and removes stale ones; returns error messages.
static func write(texts: Dictionary, out_dir: String = OUT_DIR) -> PackedStringArray:
	var errors := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out_dir)
	for file_name: String in DirAccess.get_files_at(out_dir):
		if file_name.ends_with(SUFFIX) and not texts.has(file_name):
			DirAccess.remove_absolute(out_dir.path_join(file_name))
	for file_name: String in texts:
		var file := FileAccess.open(out_dir.path_join(file_name), FileAccess.WRITE)
		if file == null:
			errors.append("Cannot write %s: %s" % [file_name, error_string(FileAccess.get_open_error())])
			continue
		file.store_string(texts[file_name])
		file.close()
	return errors


## File names whose exported text differs from `texts`, plus extra files.
static func stale(texts: Dictionary, out_dir: String = OUT_DIR) -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(out_dir):
		return PackedStringArray(texts.keys())
	var result := PackedStringArray()
	for file_name: String in texts:
		var path := out_dir.path_join(file_name)
		if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path).replace("\r\n", "\n") != texts[file_name]:
			result.append(file_name)
	for file_name: String in DirAccess.get_files_at(out_dir):
		if file_name.ends_with(SUFFIX) and not texts.has(file_name):
			result.append(file_name)
	return result


static func _convert(value: Variant) -> Variant:
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return _convert(item))
	if not value is Dictionary:
		return value
	var result := {}
	var notes := PackedStringArray()
	for key: String in value:
		var item: Variant = value[key]
		match key:
			"$ref":
				result[key] = _file_ref(item)
			"x-pattern-message":
				result["patternErrorMessage"] = item
			"x-ref":
				notes.append("ID of %s %s def." % [_article(item), item])
				if not value.has("pattern") and not value.has("const") and not value.has("enum"):
					result["pattern"] = PackLoader.REF_PATTERN
					result["patternErrorMessage"] = "Use %s %s ID such as name or pack:name" % [_article(item), item]
			"x-expr":
				var spec: Dictionary = item if item is Dictionary else {}
				notes.append("Formula returning %s." % str(spec.get("type", "a value")))
			"x-asset":
				notes.append("Pack-relative %s file." % str(item))
			_:
				if key not in DROPPED and not key.begins_with("x-"):
					result[key] = _convert(item)
	if not notes.is_empty():
		var text := " ".join(notes)
		result["description"] = "%s %s" % [result.description, text] if result.has("description") else text
	return result


static func _article(word: String) -> String:
	return "an" if not word.is_empty() and "aeiou".contains(word[0]) else "a"


static func _file_ref(ref: String) -> String:
	var hash_at := ref.find("#")
	if hash_at <= 0:
		return ref
	return ref.substr(0, hash_at) + SUFFIX + ref.substr(hash_at)


## Adds the envelope (def, id, parent, abstract, notes). Required fields only
## apply to complete defs, because children and templates may inherit them.
static func _def_schema(def_type: String, schema: Dictionary) -> Dictionary:
	var result := {"$schema": DRAFT, "title": "%s def" % def_type}
	var envelope := _envelope(def_type)
	for key: String in schema:
		if key == "properties":
			var properties: Dictionary = envelope.duplicate()
			properties.merge(schema.properties)
			result[key] = properties
		elif key != "required":
			result[key] = schema[key]
	if not result.has("properties"):
		result["properties"] = envelope
	result["required"] = ["id"]
	var required: Array = schema.get("required", [])
	if not required.is_empty():
		result["if"] = {"anyOf": [{"required": ["parent"]}, {"properties": {"abstract": {"const": true}}, "required": ["abstract"]}]}
		result["else"] = {"required": required}
	return result


static func _envelope(def_type: String) -> Dictionary:
	return {
		"def": {"const": def_type, "description": "Def type; optional when the file sets it."},
		"id": {"type": "string", "pattern": PackLoader.ID_PATTERN,
			"patternErrorMessage": "Use lowercase letters, digits and _, with @ or / for variants"},
		"parent": {"type": "string", "pattern": PackLoader.REF_PATTERN, "description": "Def to inherit fields from."},
		"abstract": {"type": "boolean", "description": "A template for other defs; never used directly."},
		"notes": {"type": "string", "description": "Designer notes; ignored by the game."},
	}


static func _patch_schema(types: Array) -> Dictionary:
	var operation := {"type": "object", "description": "Path such as stats.hull, slots[gun] or tags[2] -> value."}
	return {
		"$schema": DRAFT,
		"title": "patch def",
		"description": "Changes another def without copying it.",
		"type": "object",
		"properties": {
			"def": {"const": PackLoader.PATCH},
			"id": _envelope(PackLoader.PATCH).id,
			"notes": _envelope(PackLoader.PATCH).notes,
			"target": {"type": "string", "pattern": PackLoader.REF_PATTERN, "description": "Def to change, such as laser or core:laser."},
			"target_def": {"enum": types, "description": "Def type of the target when its ID is shared."},
			"set": operation,
			"append": operation,
			"remove": operation,
		},
		"required": ["id", "target"],
		"anyOf": [{"required": ["set"]}, {"required": ["append"]}, {"required": ["remove"]}],
		"additionalProperties": false,
	}


## A file holds one def, or {"def": type, "defs": [...]} where entries may
## override the type.
static func _def_file_schema(types: Array) -> Dictionary:
	var all_types: Array = types.duplicate()
	all_types.append(PackLoader.PATCH)
	all_types.sort()
	var dispatch := []
	var by_file_type := []
	for def_type: String in all_types:
		dispatch.append({"if": {"properties": {"def": {"const": def_type}}, "required": ["def"]}, "then": {"$ref": def_type + SUFFIX}})
		by_file_type.append({
			"if": {"properties": {"def": {"const": def_type}}, "required": ["def"]},
			"then": {"properties": {"defs": {"items": {"if": {"required": ["def"]}, "then": {"$ref": "#/definitions/any_def"}, "else": {"$ref": def_type + SUFFIX}}}}},
		})
	by_file_type.append({"if": {"not": {"required": ["def"]}}, "then": {"properties": {"defs": {"items": {"$ref": "#/definitions/typed_def"}}}}})
	return {
		"$schema": DRAFT,
		"title": "Leviathan def file",
		"description": "One def, or {\"def\": type, \"defs\": [...]}.",
		"type": "object",
		"if": {"required": ["defs"]},
		"then": {
			"properties": {
				"def": {"enum": all_types, "description": "Def type of every entry that does not set its own."},
				"defs": {"type": "array"},
				"notes": {"type": "string", "description": "Designer notes; ignored by the game."},
			},
			"additionalProperties": false,
			"allOf": by_file_type,
		},
		"else": {"$ref": "#/definitions/typed_def"},
		"definitions": {
			"any_def": {"type": "object", "properties": {"def": {"enum": all_types}}, "allOf": dispatch},
			"typed_def": {"allOf": [{"$ref": "#/definitions/any_def"}, {"required": ["def"]}]},
		},
	}


static func _pack_schema() -> Dictionary:
	var pack_id := {"type": "string", "pattern": PackManifest.ID_PATTERN,
		"patternErrorMessage": "Use 2-64 lowercase letters, digits or _, starting with a letter"}
	var version_range := {"type": "string", "description": "Version range such as >=1.0, ^1.2 or *."}
	var texts := {"type": "array", "items": {"type": "string"}}
	return {
		"$schema": DRAFT,
		"title": "Leviathan pack manifest",
		"type": "object",
		"properties": {
			"id": pack_id,
			"name": {"type": "string", "minLength": 1},
			"version": {"type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$", "patternErrorMessage": "Use a version such as 1.2.0"},
			"authors": texts,
			"kind": {"enum": PackManifest.KINDS},
			"game_version": version_range,
			"depends": {"type": "array", "items": {"anyOf": [pack_id, {
				"type": "object",
				"properties": {"id": pack_id, "version": version_range},
				"required": ["id"],
				"additionalProperties": false,
			}]}},
			"load_after": texts,
			"tags": texts,
			"steam": {"type": "object"},
			"description": {"type": "string"},
			"notes": {"type": "string"},
		},
		"required": ["id", "name", "version"],
		"additionalProperties": false,
	}


## JSON parsing yields floats; write whole numbers without a decimal point.
static func _integers(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9007199254740992.0:
		return int(value)
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return _integers(item))
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _integers(value[key])
		return result
	return value
