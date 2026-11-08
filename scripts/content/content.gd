class_name Content
extends RefCounted

## Static access to the loaded content. Loads lazily on first use, so tests,
## tools and the editor need no autoload. Problems are pushed to the console.

const ROOTS := ["res://packs", "user://packs"]
const SCHEMA_DIRS := ["res://schemas/defs"]

## Def type -> Callable used as PackLoader.checks for every load.
static var checks: Dictionary = {}
static var _db: DefDatabase
static var _run_db: DefDatabase
static var _view_db: DefDatabase
static var _views: Dictionary = {}

# The shipped game owns these shorthand scopes. Other packs keep qualified
# runtime IDs, even when their local name happens to be unique today.
const DEFAULT_PACKS := {"location": "leviathan", "event": "leviathan", "run_start": "leviathan"}


static func db() -> DefDatabase:
	return _run_db if _run_db != null else installed()


static func installed() -> DefDatabase:
	if _db == null:
		load_all()
	return _db


## Transitional binding for static runtime readers. Reloading installed packs
## never changes this run's definitions; systems will receive context directly.
static func bind_run(database: DefDatabase) -> void:
	_run_db = database


static func run_database() -> DefDatabase:
	return _run_db


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
	_run_db = null # Explicit tool/fixture replacement, unlike an installed reload.


static func qualified_id(def_type: String, ref: String, from_pack := "", content: DefDatabase = null) -> String:
	content = db() if content == null else content
	var scope := str(DEFAULT_PACKS.get(def_type, "core")) if from_pack.is_empty() else from_pack
	var qid := content.resolve_id(def_type, ref, scope)
	# Unique names remain convenient at tool/API boundaries; stored runtime
	# identities use runtime_id, so a later installed pack cannot rebind them.
	return content.resolve_id(def_type, ref) if qid.is_empty() and from_pack.is_empty() else qid


static func runtime_id(def_type: String, ref: String, from_pack := "", content: DefDatabase = null) -> String:
	content = db() if content == null else content
	var qid := qualified_id(def_type, ref, from_pack, content)
	if qid.is_empty():
		return ""
	var record := content.record(def_type, qid)
	return str(record.id) if record.pack == DEFAULT_PACKS.get(def_type, "core") else qid


static func get_def(def_type: String, id: String, from_pack := "", content: DefDatabase = null) -> Dictionary:
	content = db() if content == null else content
	var qid := qualified_id(def_type, id, from_pack, content)
	return {} if qid.is_empty() else content.get_def(def_type, qid)


static func has_def(def_type: String, id: String) -> bool:
	return not get_def(def_type, id).is_empty()


static func all(def_type: String) -> Array[Dictionary]:
	return db().all(def_type)


## Writable runtime projections of every concrete def in load order.
static func copies(def_type: String, content: DefDatabase = null) -> Array:
	content = db() if content == null else content
	var result := []
	for record: Dictionary in content.records(def_type):
		if not record.abstract:
			result.append(view(def_type, record.qid, "", content))
	return result


## A writable runtime projection: scoped references, identity and asset paths
## are resolved once per database. Authored/frozen pack data stays untouched.
static func view(def_type: String, id: String, from_pack := "", content: DefDatabase = null) -> Dictionary:
	content = db() if content == null else content
	if _view_db != content:
		_view_db = content
		_views.clear()
	var qid := qualified_id(def_type, id, from_pack, content)
	if qid.is_empty():
		return {}
	var key := def_type + "|" + qid
	if _views.has(key):
		return _views[key].duplicate(true)
	var record := content.record(def_type, qid)
	if record.is_empty() or record.abstract:
		return {}
	var result: Dictionary = record.data.duplicate(true)
	result.erase("id")
	var collected := content.schemas.validate(def_type, result)
	for ref: Dictionary in collected.refs:
		_replace(result, ref.path, runtime_id(ref.type, ref.value, record.pack, content))
	for asset: Dictionary in collected.assets:
		_replace(result, asset.path, PackLoader.asset_path(content, asset.value, record.pack))
	result["id"] = runtime_id(def_type, qid, "", content)
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
