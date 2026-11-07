class_name Content
extends RefCounted

## Static access to the loaded content. Loads lazily on first use, so tests,
## tools and the editor need no autoload. Problems are pushed to the console.

const ROOTS := ["res://packs", "user://packs"]
const SCHEMA_DIRS := ["res://schemas/defs"]

## Def type -> Callable used as PackLoader.checks for every load.
static var checks: Dictionary = {}
static var _db: DefDatabase


static func db() -> DefDatabase:
	if _db == null:
		reload()
	return _db


static func reload(roots: Array = ROOTS, schema_dirs: Array = SCHEMA_DIRS) -> DefDatabase:
	var loader := PackLoader.new()
	loader.checks = checks
	_db = loader.load_packs(roots, schema_dirs)
	for item in _db.problems.items:
		if item.severity == ContentProblems.ERROR:
			push_error(ContentProblems.format(item))
		else:
			push_warning(ContentProblems.format(item))
	return _db


## Replaces the loaded content, such as a fixture database in tests; null
## makes the next call load again.
static func set_database(database: DefDatabase) -> void:
	_db = database


static func get_def(def_type: String, id: String) -> Dictionary:
	return db().get_def(def_type, id)


static func has_def(def_type: String, id: String) -> bool:
	return db().has_def(def_type, id)


static func all(def_type: String) -> Array[Dictionary]:
	return db().all(def_type)


static func formula(def_type: String, id: String, path: String) -> Formula:
	return db().formula(def_type, id, path)
