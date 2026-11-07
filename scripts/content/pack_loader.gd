class_name PackLoader
extends RefCounted

## Discovers, orders, parses, patches, resolves, validates and freezes packs.
##
## Order: parse; apply patches to authored defs in pack order; resolve
## inheritance; validate schemas; resolve references; compile formulas; run
## type checks; freeze and hash. A pack with errors is disabled with every
## pack that depends on it, and the remaining packs load again without it, so
## a broken patch cannot leave changes behind. Schema errors on a patched path
## are blamed on the patching pack.

const DEFAULT_ROOTS := ["res://packs", "user://packs"]
const DEFAULT_SCHEMA_DIRS := ["res://schemas/defs"]
const ENVELOPE := ["def", "id", "parent", "abstract", "notes"]
const PATCH := "patch"
const PATCH_KEYS := ["def", "id", "notes", "target", "target_def", "set", "append", "remove"]
const FILE_KEYS := ["def", "defs", "notes"]
const ID_PATTERN := "^[a-z][a-z0-9_]*([@/][a-z0-9_]+)*$"
const REF_PATTERN := "^([a-z][a-z0-9_]{1,63}:)?[a-z][a-z0-9_]*([@/][a-z0-9_]+)*$"

var schemas: SchemaRegistry
## Def type -> Callable(def_data: Dictionary, meta: Dictionary, db: DefDatabase)
## returning [{"path", "message", "severity"?}]. Runs after references resolve.
var checks: Dictionary = {}
## Checked against manifests' game_version; empty skips the check.
var game_version: String = str(ProjectSettings.get_setting("application/config/version", ""))
var _id_regex := RegEx.create_from_string(ID_PATTERN)
var _ref_regex := RegEx.create_from_string(REF_PATTERN)


func _init(registry: SchemaRegistry = null) -> void:
	schemas = registry if registry != null else SchemaRegistry.new()
	checks["research"] = preload("res://scripts/content/research_checks.gd").validate


func load_packs(roots: Array = DEFAULT_ROOTS, schema_dirs: Array = DEFAULT_SCHEMA_DIRS) -> DefDatabase:
	var problems := ContentProblems.new()
	for dir_path: String in schema_dirs:
		if DirAccess.dir_exists_absolute(dir_path):
			schemas.load_dir(dir_path, problems)
		else:
			problems.error("Schema folder not found", "", dir_path)
	var manifests := _discover(roots, problems)
	var installed := {}
	for manifest in manifests:
		installed[manifest.id] = manifest
	var disabled := {}
	var order := _order(manifests, problems, disabled)
	var parsed := {}
	for manifest in order:
		var before := problems.errors().size()
		parsed[manifest.id] = _parse_pack(manifest, problems)
		if problems.errors().size() > before:
			disabled[manifest.id] = true
	while true:
		_disable_dependents(order, installed, disabled, problems)
		var enabled: Array[PackManifest] = []
		for manifest in order:
			if not disabled.has(manifest.id):
				enabled.append(manifest)
		var attempt := ContentProblems.new()
		var db := _build(enabled, parsed, attempt)
		var failing: Array[String] = []
		for manifest in enabled:
			if attempt.has_errors(manifest.id):
				failing.append(manifest.id)
		if failing.is_empty():
			problems.merge(attempt)
			db.problems = problems
			for pack_id in installed:
				if not db.has_pack(pack_id):
					db.disabled[pack_id] = installed[pack_id]
			db.freeze()
			return db
		for pack_id in failing:
			disabled[pack_id] = true
			for item in attempt.for_pack(pack_id):
				problems.items.append(item)
	return null


# --- Discovery and order -----------------------------------------------------

func _discover(roots: Array, problems: ContentProblems) -> Array[PackManifest]:
	var found: Array[PackManifest] = []
	var seen := {}
	for root: String in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var folders := Array(DirAccess.get_directories_at(root))
		folders.sort()
		for folder: String in folders:
			var pack_root := root.path_join(folder)
			var manifest_path := pack_root.path_join("pack.json")
			if not FileAccess.file_exists(manifest_path):
				problems.warning("Folder has no pack.json", "", pack_root)
				continue
			var data: Variant = read_json(manifest_path, problems, "")
			if data == null:
				continue
			var manifest := PackManifest.parse(data, pack_root, problems)
			if manifest == null:
				continue
			if seen.has(manifest.id):
				problems.error("Pack id '%s' is already used by %s" % [manifest.id, seen[manifest.id]], "", manifest_path, "", "id")
				continue
			seen[manifest.id] = pack_root
			found.append(manifest)
	return found


## Topological order by depends and load_after, ties by ID. Packs in a
## dependency cycle are disabled; a load_after cycle is only a warning.
func _order(manifests: Array[PackManifest], problems: ContentProblems, disabled: Dictionary) -> Array[PackManifest]:
	var by_id := {}
	for manifest in manifests:
		by_id[manifest.id] = manifest
	var placed: Array[PackManifest] = []
	var done := {}
	var warned := {}
	var use_soft := true
	var remaining := manifests.duplicate()
	while not remaining.is_empty():
		var ready: Array[PackManifest] = []
		for manifest: PackManifest in remaining:
			var waits := false
			for dep in manifest.dependency_ids():
				if by_id.has(dep) and not done.has(dep):
					waits = true
			if use_soft:
				for dep in manifest.load_after:
					if by_id.has(dep) and not done.has(dep):
						waits = true
			if not waits:
				ready.append(manifest)
		if ready.is_empty():
			if use_soft:
				use_soft = false
				var stuck := PackedStringArray()
				for manifest: PackManifest in remaining:
					stuck.append(manifest.id)
				for manifest: PackManifest in remaining:
					if not manifest.load_after.is_empty() and not warned.has(manifest.id):
						warned[manifest.id] = true
						problems.warning("load_after forms a loop among %s; ignoring it" % ", ".join(stuck), manifest.id, manifest.root.path_join("pack.json"), "", "load_after")
				continue
			var cyclic: Array = remaining.filter(func(manifest: PackManifest) -> bool: return _in_cycle(manifest, by_id, remaining))
			if cyclic.is_empty():
				cyclic = remaining.duplicate()
			for manifest: PackManifest in cyclic:
				problems.error("Dependency cycle; this pack cannot load", manifest.id, manifest.root.path_join("pack.json"), "", "depends")
				disabled[manifest.id] = true
				placed.append(manifest)
				done[manifest.id] = true
				remaining.erase(manifest)
			continue
		ready.sort_custom(func(a: PackManifest, b: PackManifest) -> bool: return a.id < b.id)
		var next: PackManifest = ready[0]
		placed.append(next)
		done[next.id] = true
		remaining.erase(next)
		use_soft = true
	return placed


## Whether a pack can reach itself through hard dependencies among `remaining`.
static func _in_cycle(start: PackManifest, by_id: Dictionary, remaining: Array) -> bool:
	var pending: Array = Array(start.dependency_ids())
	var seen := {}
	while not pending.is_empty():
		var next: String = pending.pop_back()
		if next == start.id:
			return true
		if seen.has(next) or not by_id.has(next) or not remaining.has(by_id[next]):
			continue
		seen[next] = true
		pending.append_array(Array(by_id[next].dependency_ids()))
	return false


func _disable_dependents(order: Array[PackManifest], installed: Dictionary, disabled: Dictionary, problems: ContentProblems) -> void:
	for manifest in order:
		if disabled.has(manifest.id):
			continue
		var file := manifest.root.path_join("pack.json")
		var reason := ""
		if not game_version.is_empty() and not manifest.game_version.is_empty() and not PackManifest.satisfies(game_version, manifest.game_version):
			reason = "Needs game version %s; this is %s" % [manifest.game_version, game_version]
		for index in manifest.depends.size():
			if not reason.is_empty():
				break
			var dependency: Dictionary = manifest.depends[index]
			var other: PackManifest = installed.get(dependency.id)
			if other == null:
				reason = "Needs pack '%s', which is not installed" % dependency.id
			elif not PackManifest.satisfies(other.version, dependency.version):
				reason = "Needs %s %s; found %s" % [dependency.id, dependency.version, other.version]
			elif disabled.has(dependency.id):
				reason = "Disabled because pack '%s' did not load" % dependency.id
		if not reason.is_empty():
			problems.error(reason, manifest.id, file, "", "depends")
			disabled[manifest.id] = true


# --- Parsing -----------------------------------------------------------------

static func read_json(path: String, problems: ContentProblems, pack_id: String) -> Variant:
	var json := JSON.new()
	var text := FileAccess.get_file_as_string(path)
	if json.parse(text) != OK:
		# get_error_line() is 0-based; editors count from 1.
		problems.error("Invalid JSON at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()], pack_id, path)
		return null
	return json.data


static func json_files(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	var files := Array(DirAccess.get_files_at(dir_path))
	files.sort()
	for file_name: String in files:
		if file_name.ends_with(".json"):
			result.append(dir_path.path_join(file_name))
	var folders := Array(DirAccess.get_directories_at(dir_path))
	folders.sort()
	for folder: String in folders:
		result.append_array(json_files(dir_path.path_join(folder)))
	return result


func _parse_pack(manifest: PackManifest, problems: ContentProblems) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for file in json_files(manifest.root.path_join("defs")):
		var data: Variant = read_json(file, problems, manifest.id)
		if data == null:
			continue
		if not data is Dictionary:
			problems.error("A def file must be one def or {\"def\": type, \"defs\": [...]}", manifest.id, file)
			continue
		var entries: Array = [data]
		var default_type: Variant = ""
		var listed: bool = data.has("defs")
		if listed:
			if not data.defs is Array:
				problems.error("defs must be a list", manifest.id, file, "", "defs")
				continue
			for key in data:
				if key not in FILE_KEYS:
					problems.error("Unknown file field '%s'; defs go inside \"defs\"" % key, manifest.id, file, "", str(key))
			default_type = data.get("def", "")
			if not default_type is String:
				problems.error("def must be text", manifest.id, file, "", "def")
				continue
			entries = data.defs
		for index in entries.size():
			var where := "defs[%d]" % index if listed else ""
			var entry: Variant = entries[index]
			if not entry is Dictionary:
				problems.error("Each def must be an object", manifest.id, file, "", where)
				continue
			var def_type: Variant = entry.get("def", default_type)
			var def_id: Variant = entry.get("id")
			if not def_id is String or _id_regex.search(def_id) == null:
				problems.error("Def id must be lowercase letters, digits and _, with @ or / for variants", manifest.id, file, "", SchemaRegistry.join(where, "id"))
				continue
			if not def_type is String or def_type.is_empty():
				problems.error("Def needs a \"def\" type", manifest.id, file, def_id, "def")
				continue
			if def_type != PATCH and (not schemas.has_schema(def_type) or def_type.begins_with("_")):
				problems.error("Unknown def type '%s'%s" % [def_type, SchemaRegistry._suggest(def_type, schemas.def_types())], manifest.id, file, def_id, "def")
				continue
			if entry.has("parent") and (not entry.parent is String or _ref_regex.search(entry.parent) == null):
				problems.error("parent must be a def ID", manifest.id, file, def_id, "parent")
				continue
			if entry.has("abstract") and not entry.abstract is bool:
				problems.error("abstract must be true or false", manifest.id, file, def_id, "abstract")
				continue
			if entry.has("notes") and not entry.notes is String:
				problems.error("notes must be text", manifest.id, file, def_id, "notes")
				continue
			records.append({"type": def_type, "id": def_id, "qid": "%s:%s" % [manifest.id, def_id], "pack": manifest.id,
				"file": file, "index": index, "parent": entry.get("parent", ""), "abstract": entry.get("abstract", false),
				"notes": entry.get("notes", ""), "authored": entry})
	return records


# --- Build -------------------------------------------------------------------

func _build(enabled: Array[PackManifest], parsed: Dictionary, problems: ContentProblems) -> DefDatabase:
	var db := DefDatabase.new()
	db.schemas = schemas
	db.setup(enabled)
	var patches: Array[Dictionary] = []
	for manifest in enabled:
		for source: Dictionary in parsed[manifest.id]:
			var entry: Dictionary = source.duplicate(true)
			entry["patched"] = []
			if entry.type == PATCH:
				patches.append(entry)
				continue
			if not db.add_record(entry):
				problems.error("Another %s in this pack already uses this ID" % entry.type, entry.pack, entry.file, entry.id, "id")
	var conflicts := {}
	for patch in patches:
		_apply_patch(db, patch, problems, conflicts)
	for def_type in db.types():
		for entry: Dictionary in db.records(def_type):
			_resolve(db, entry, [], problems)
	for def_type in db.types():
		for entry: Dictionary in db.records(def_type):
			_validate(db, entry, problems)
	for def_type in db.types():
		if not checks.has(def_type):
			continue
		for entry: Dictionary in db.records(def_type):
			if entry.abstract:
				continue
			var found: Array = checks[def_type].call(entry.data, db.meta(def_type, entry.qid), db)
			for item: Dictionary in found:
				var path := str(item.get("path", ""))
				var blame := _blame(db, entry, path)
				for related: String in item.get("related_paths", []):
					if blame.is_empty():
						blame = _blame(db, entry, related)
				for cause: Dictionary in item.get("causes", []):
					if blame.is_empty():
						var record := db.record(cause.type, cause.id)
						if not record.is_empty():
							blame = _blame(db, record, cause.path)
				var source: Dictionary = entry if blame.is_empty() else blame
				problems.add(str(item.get("severity", ContentProblems.ERROR)), item.message, source.pack, source.file, source.id, path)
	return db


static func strip_envelope(authored: Dictionary) -> Dictionary:
	var result := {}
	for key in authored:
		if key not in ENVELOPE:
			result[key] = authored[key]
	return result


func _apply_patch(db: DefDatabase, patch: Dictionary, problems: ContentProblems, conflicts: Dictionary) -> void:
	var authored: Dictionary = patch.authored
	var report := func(message: String, path: String = "", severity: String = ContentProblems.ERROR) -> void:
		problems.add(severity, message, patch.pack, patch.file, patch.id, path)
	var valid := true
	for key in authored:
		if key not in PATCH_KEYS:
			report.call("Unknown patch field%s" % SchemaRegistry._suggest(str(key), PATCH_KEYS), str(key))
			valid = false
	if not authored.get("target") is String or _ref_regex.search(authored.target) == null:
		report.call("target must be a def ID", "target")
		return
	if authored.has("target_def") and (not authored.target_def is String or not schemas.has_schema(authored.target_def)):
		report.call("target_def must be a def type", "target_def")
		return
	var has_op := false
	for op in DefPatcher.OPS:
		if authored.has(op):
			has_op = true
			if not authored[op] is Dictionary:
				report.call("%s must map paths to values" % op, op)
				valid = false
	if not has_op:
		report.call("A patch needs set, append or remove")
		return
	if not valid:
		return
	var target: String = authored.target
	var target_pack: String = DefDatabase.split(target)[0]
	if not target_pack.is_empty() and not db.has_pack(target_pack):
		report.call("Skipped: pack '%s' is not loaded" % target_pack, "target", ContentProblems.WARNING)
		return
	var candidate_types: Array = [authored.target_def] if authored.has("target_def") else db.types()
	var matches: Array[Dictionary] = []
	var first_error := ""
	for def_type in candidate_types:
		var resolution := db.resolve(def_type, target, patch.pack)
		if resolution.has("qid"):
			matches.append(db.record(def_type, resolution.qid))
		elif first_error.is_empty() or not resolution.error.begins_with("No "):
			first_error = resolution.error
	if matches.is_empty():
		report.call(first_error if authored.has("target_def") or not first_error.begins_with("No ") else "No def named '%s'" % target, "target")
		return
	if matches.size() > 1:
		var kinds := PackedStringArray()
		for match_record in matches:
			kinds.append(match_record.type)
		report.call("Several defs are named '%s'; add target_def (%s)" % [target, ", ".join(kinds)], "target")
		return
	var record: Dictionary = matches[0]
	if db.pack_position(record.pack) > db.pack_position(patch.pack):
		report.call("Pack '%s' loads after this patch; add it to depends or load_after" % record.pack, "target")
		return
	var inherited := func(segments: Array) -> Array:
		return DefPatcher.read(_inherited_base(db, record), segments)
	var result := DefPatcher.apply(record.authored, authored, inherited)
	for item: Dictionary in result.problems:
		report.call(item.message, item.path)
	for path: String in result.set_paths:
		var key := "%s|%s" % [record.qid, path]
		if conflicts.has(key) and conflicts[key] != patch.pack:
			report.call("Pack '%s' also sets %s; this patch wins because it loads later" % [conflicts[key], path], "set." + path, ContentProblems.WARNING)
		conflicts[key] = patch.pack
	for path: String in result.changed:
		record.patched.append({"path": path, "pack": patch.pack, "file": patch.file, "id": patch.id})


## The fully resolved parent of a def, built from current authored data.
func _inherited_base(db: DefDatabase, record: Dictionary) -> Dictionary:
	var chain: Array[Dictionary] = []
	var current := record
	var seen := {record.qid: true}
	while not str(current.parent).is_empty():
		var parent := db.record(record.type, current.parent, current.pack)
		if parent.is_empty() or seen.has(parent.qid):
			break
		seen[parent.qid] = true
		chain.push_front(parent)
		current = parent
	var resolved := {}
	for ancestor in chain:
		resolved = DefPatcher.merge(resolved, strip_envelope(ancestor.authored))
	return resolved


func _resolve(db: DefDatabase, record: Dictionary, stack: Array, problems: ContentProblems) -> Dictionary:
	if record.has("resolved"):
		return record.resolved
	var base := {}
	if not str(record.parent).is_empty():
		var resolution := db.resolve(record.type, record.parent, record.pack)
		if not resolution.has("qid"):
			problems.error(resolution.error, record.pack, record.file, record.id, "parent")
		elif resolution.qid in stack or resolution.qid == record.qid:
			var loop := PackedStringArray(stack)
			loop.append(record.qid)
			problems.error("Inheritance loop: %s -> %s" % [" -> ".join(loop), resolution.qid], record.pack, record.file, record.id, "parent")
		else:
			var parent := db.record(record.type, resolution.qid)
			var chain := stack.duplicate()
			chain.append(record.qid)
			base = _resolve(db, parent, chain, problems)
	record["resolved"] = DefPatcher.merge(base, strip_envelope(record.authored))
	return record.resolved


func _validate(db: DefDatabase, record: Dictionary, problems: ContentProblems) -> void:
	var data: Dictionary = record.resolved.duplicate(true)
	if record.abstract:
		record["data"] = data
		return
	var report := func(path: String, message: String, severity: String = ContentProblems.ERROR) -> void:
		var blame := _blame(db, record, path)
		if blame.is_empty():
			problems.add(severity, message, record.pack, record.file, record.id, path)
		else:
			problems.add(severity, "%s (after patch %s:%s changed %s)" % [message, blame.pack, blame.id, record.qid], blame.pack, blame.file, blame.id, path)
	var result := schemas.validate(record.type, data)
	for item in result.problems:
		report.call(item.path, item.message)
	for ref in result.refs:
		var resolution := db.resolve(ref.type, ref.value, record.pack)
		if not resolution.has("qid"):
			report.call(ref.path, resolution.error)
		elif db.record(ref.type, resolution.qid).abstract:
			report.call(ref.path, "'%s' is a template and cannot be used directly" % ref.value)
	for expr in result.exprs:
		var spec: Dictionary = expr.spec
		var context := str(spec.get("context", ExprContexts.STATIC))
		var expected := str(spec.get("type", "any"))
		if expr.get("literal", false):
			db.set_formula(record.type, record.qid, expr.path, Formula.constant(expr.value, expected))
			continue
		if not ExprContexts.has(context):
			report.call(expr.path, "Unknown formula context '%s'" % context)
			continue
		var compiled := ExprContexts.compile(expr.value, context, expected)
		if not compiled.ok():
			report.call(expr.path, compiled.error_text())
			continue
		db.set_formula(record.type, record.qid, expr.path, compiled)
	for asset in result.assets:
		var path := asset_path(db, str(asset.value), record.pack)
		if path.is_empty() or not (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
			report.call(asset.path, "Missing file: %s" % asset.value, ContentProblems.WARNING)
	data["id"] = record.id
	record["data"] = data


## Finds the most recent patch that changed `path` (or a containing path) on
## this def or an ancestor.
func _blame(db: DefDatabase, record: Dictionary, path: String) -> Dictionary:
	var current := record
	var seen := {}
	while not current.is_empty() and not seen.has(current.qid):
		seen[current.qid] = true
		for index in range(current.patched.size() - 1, -1, -1):
			var change: Dictionary = current.patched[index]
			if change.pack == record.pack:
				continue
			if _path_overlaps(change.path, path):
				return change
		current = {} if str(current.parent).is_empty() else db.record(current.type, current.parent, current.pack)
	return {}


static func _path_overlaps(changed: String, problem: String) -> bool:
	if changed == problem or problem.is_empty():
		return true
	for separator in [".", "["]:
		if problem.begins_with(changed + separator) or changed.begins_with(problem + separator):
			return true
	return false


## Maps an asset value to a loadable path: res:// and user:// as written,
## "pack:path" inside that pack, otherwise relative to the def's own pack.
static func asset_path(db: DefDatabase, value: String, from_pack: String) -> String:
	if value.begins_with("res://") or value.begins_with("user://"):
		return value
	var parts := DefDatabase.split(value)
	var pack_id: String = from_pack if parts[0].is_empty() else parts[0]
	var manifest := db.pack(pack_id)
	return "" if manifest == null else manifest.root.path_join(parts[1])
