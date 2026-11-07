class_name Content
extends RefCounted

## Static access to the loaded content. Loads lazily on first use, so tests,
## tools and the editor need no autoload. Problems are pushed to the console.

const ROOTS := ["res://packs", "user://packs"]
const SCHEMA_DIRS := ["res://schemas/defs"]

## Def type -> Callable used as PackLoader.checks for every load.
static var checks: Dictionary = {}
static var _db: DefDatabase
static var _view_db: DefDatabase
static var _views: Dictionary = {}

# The shipped game owns these shorthand scopes. Other packs keep qualified
# runtime IDs, even when their local name happens to be unique today.
const DEFAULT_PACKS := {"location": "leviathan", "event": "leviathan", "run_start": "leviathan"}


static func db() -> DefDatabase:
	if _db == null:
		load_all()
	return _db


## Not named reload: Content.reload() would call Script.reload() instead.
static func load_all(roots: Array = ROOTS, schema_dirs: Array = SCHEMA_DIRS) -> DefDatabase:
	var loader := PackLoader.new()
	loader.checks.merge(checks, true)
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


static func qualified_id(def_type: String, ref: String, from_pack := "") -> String:
	var scope := str(DEFAULT_PACKS.get(def_type, "core")) if from_pack.is_empty() else from_pack
	var qid := db().resolve_id(def_type, ref, scope)
	# Unique names remain convenient at tool/API boundaries; stored runtime
	# identities use runtime_id, so a later installed pack cannot rebind them.
	return db().resolve_id(def_type, ref) if qid.is_empty() and from_pack.is_empty() else qid


static func runtime_id(def_type: String, ref: String, from_pack := "") -> String:
	var qid := qualified_id(def_type, ref, from_pack)
	if qid.is_empty():
		return ""
	var record := db().record(def_type, qid)
	return str(record.id) if record.pack == DEFAULT_PACKS.get(def_type, "core") else qid


static func get_def(def_type: String, id: String, from_pack := "") -> Dictionary:
	var qid := qualified_id(def_type, id, from_pack)
	return {} if qid.is_empty() else db().get_def(def_type, qid)


static func has_def(def_type: String, id: String) -> bool:
	return not get_def(def_type, id).is_empty()


static func all(def_type: String) -> Array[Dictionary]:
	return db().all(def_type)


## Writable runtime projections of every concrete def in load order.
static func copies(def_type: String) -> Array:
	var result := []
	for record: Dictionary in db().records(def_type):
		if not record.abstract:
			result.append(view(def_type, record.qid))
	return result


## A writable runtime projection: scoped references, identity and asset paths
## are resolved once per database. Authored/frozen pack data stays untouched.
static func view(def_type: String, id: String, from_pack := "") -> Dictionary:
	if _view_db != db():
		_view_db = db()
		_views.clear()
	var qid := qualified_id(def_type, id, from_pack)
	if qid.is_empty():
		return {}
	var key := def_type + "|" + qid
	if _views.has(key):
		return _views[key].duplicate(true)
	var record := db().record(def_type, qid)
	if record.is_empty() or record.abstract:
		return {}
	var result: Dictionary = record.data.duplicate(true)
	result.erase("id")
	var collected := db().schemas.validate(def_type, result)
	for ref: Dictionary in collected.refs:
		_replace(result, ref.path, runtime_id(ref.type, ref.value, record.pack))
	for asset: Dictionary in collected.assets:
		_replace(result, asset.path, PackLoader.asset_path(db(), asset.value, record.pack))
	result["id"] = runtime_id(def_type, qid)
	_views[key] = result
	return result.duplicate(true)


static func _replace(root: Dictionary, path: String, value: String) -> void:
	var steps := DefPatcher.parse_path(path)
	var parent: Variant = root
	for index in steps.size():
		var step: Dictionary = steps[index]
		var key: Variant
		if step.has("key"):
			key = step.key
		elif step.has("index"):
			key = step.index
		else:
			key = -1
			for position in parent.size():
				if parent[position] is Dictionary and parent[position].get("id") == step.select:
					key = position
					break
		if index == steps.size() - 1:
			parent[key] = value
		else:
			parent = parent[key]


static func formula(def_type: String, id: String, path: String) -> Formula:
	return db().formula(def_type, id, path)
