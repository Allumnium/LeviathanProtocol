class_name DefDatabase
extends RefCounted

## Resolved, validated and frozen defs from the enabled packs.
##
## IDs: a def is "pack:local" (qualified) or "local". An unqualified lookup
## from a pack checks that pack, then its dependencies; ambiguity fails.
## Without a pack, an unqualified ID must be unique across all packs.
## Returned def data is read-only; duplicate it before changing it.

const QUALIFIED_SEPARATOR := ":"

## Enabled packs in load order.
var packs: Array[PackManifest] = []
## Pack id -> PackManifest for installed packs that did not load.
var disabled: Dictionary = {}
var problems: ContentProblems = ContentProblems.new()
var schemas: SchemaRegistry
var content_hash: String = ""
var _records: Dictionary = {}
var _by_qid: Dictionary = {}
var _by_local: Dictionary = {}
var _pack_index: Dictionary = {}
var _visible: Dictionary = {}
var _formulas: Dictionary = {}


func setup(enabled: Array[PackManifest]) -> void:
	packs = enabled
	_pack_index.clear()
	_visible.clear()
	for index in packs.size():
		_pack_index[packs[index].id] = index
	for manifest in packs:
		var order := PackedStringArray()
		var queue: Array[String] = []
		queue.append_array(Array(manifest.dependency_ids()))
		while not queue.is_empty():
			var next: String = queue.pop_front()
			if next in order or next == manifest.id or not _pack_index.has(next):
				continue
			order.append(next)
			queue.append_array(Array(packs[_pack_index[next]].dependency_ids()))
		_visible[manifest.id] = order


## Adds a record {type, id, qid, pack, file, index, ...}; false when the
## qualified ID is already taken for that type.
func add_record(record: Dictionary) -> bool:
	var def_type: String = record.type
	if not _by_qid.has(def_type):
		_by_qid[def_type] = {}
		_by_local[def_type] = {}
		_records[def_type] = []
	if _by_qid[def_type].has(record.qid):
		return false
	_by_qid[def_type][record.qid] = record
	if not _by_local[def_type].has(record.id):
		_by_local[def_type][record.id] = []
	_by_local[def_type][record.id].append(record)
	_records[def_type].append(record)
	return true


func types() -> Array:
	var result := _records.keys()
	result.sort()
	return result


func has_pack(pack_id: String) -> bool:
	return _pack_index.has(pack_id)


func pack(pack_id: String) -> PackManifest:
	return packs[_pack_index[pack_id]] if _pack_index.has(pack_id) else null


func pack_position(pack_id: String) -> int:
	return _pack_index.get(pack_id, -1)


static func split(ref: String) -> Array:
	var separator := ref.find(QUALIFIED_SEPARATOR)
	return ["", ref] if separator < 0 else [ref.substr(0, separator), ref.substr(separator + 1)]


## {"qid": String} on success, otherwise {"error": message}.
func resolve(def_type: String, ref: String, from_pack: String = "") -> Dictionary:
	var parts := split(ref)
	var by_qid: Dictionary = _by_qid.get(def_type, {})
	if not parts[0].is_empty():
		if not _pack_index.has(parts[0]):
			return {"error": "Pack '%s' is not loaded" % parts[0], "pack_missing": true}
		return {"qid": ref} if by_qid.has(ref) else {"error": _missing(def_type, parts[1])}
	var local: String = parts[1]
	var candidates: Array = _by_local.get(def_type, {}).get(local, [])
	if candidates.is_empty():
		return {"error": _missing(def_type, local)}
	if from_pack.is_empty():
		if candidates.size() == 1:
			return {"qid": candidates[0].qid}
		return {"error": _ambiguous(def_type, local, candidates)}
	var own := "%s:%s" % [from_pack, local]
	if by_qid.has(own):
		return {"qid": own}
	var visible: PackedStringArray = _visible.get(from_pack, PackedStringArray())
	var found: Array = candidates.filter(func(record: Dictionary) -> bool: return record.pack in visible)
	if found.size() == 1:
		return {"qid": found[0].qid}
	if found.size() > 1:
		return {"error": _ambiguous(def_type, local, found)}
	return {"error": "%s from pack %s; add that pack to depends or write the full ID" % [_missing(def_type, local), candidates[0].pack]}


func resolve_id(def_type: String, ref: String, from_pack: String = "") -> String:
	return str(resolve(def_type, ref, from_pack).get("qid", ""))


func _missing(def_type: String, local: String) -> String:
	var known: Array = _by_local.get(def_type, {}).keys()
	var best := ""
	var best_score := 0.55
	for candidate: String in known:
		var score := local.similarity(candidate)
		if score > best_score:
			best_score = score
			best = candidate
	return "No %s named '%s'%s" % [def_type, local, "" if best.is_empty() else ". Did you mean '%s'?" % best]


static func _ambiguous(def_type: String, local: String, candidates: Array) -> String:
	var names := PackedStringArray()
	for record: Dictionary in candidates:
		names.append(record.qid)
	return "'%s' could be %s %s; write the full ID" % [local, def_type, " or ".join(names)]


func record(def_type: String, ref: String, from_pack: String = "") -> Dictionary:
	var qid := resolve_id(def_type, ref, from_pack)
	return {} if qid.is_empty() else _by_qid[def_type][qid]


func has_def(def_type: String, ref: String, from_pack: String = "") -> bool:
	var found := record(def_type, ref, from_pack)
	return not found.is_empty() and not found.abstract


## The def's read-only data, including "id", or {} when missing or abstract.
func get_def(def_type: String, ref: String, from_pack: String = "") -> Dictionary:
	var found := record(def_type, ref, from_pack)
	return {} if found.is_empty() or found.abstract else found.data


## Concrete defs of a type in load order: pack, file path, then file order.
func all(def_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _records.get(def_type, []):
		if not entry.abstract:
			result.append(entry.data)
	return result


func records(def_type: String) -> Array:
	return _records.get(def_type, [])


func ids(def_type: String, qualified: bool = false) -> PackedStringArray:
	var result := PackedStringArray()
	for entry: Dictionary in _records.get(def_type, []):
		if not entry.abstract:
			result.append(entry.qid if qualified else entry.id)
	return result


## Where a def came from: type, id, qid, pack, file, index, parent, abstract, notes.
func meta(def_type: String, ref: String, from_pack: String = "") -> Dictionary:
	var found := record(def_type, ref, from_pack)
	if found.is_empty():
		return {}
	var result := {}
	for key in ["type", "id", "qid", "pack", "file", "index", "parent", "abstract", "notes"]:
		result[key] = found.get(key)
	return result


func set_formula(def_type: String, qid: String, path: String, formula: Formula) -> void:
	_formulas["%s|%s|%s" % [def_type, qid, path]] = formula


## The compiled formula for an x-expr field, or null when the field is absent.
func formula(def_type: String, ref: String, path: String, from_pack: String = "") -> Formula:
	var qid := resolve_id(def_type, ref, from_pack)
	return _formulas.get("%s|%s|%s" % [def_type, qid, path])


func freeze() -> void:
	var canonical := {"packs": [], "defs": {}}
	for manifest in packs:
		canonical.packs.append([manifest.id, manifest.version])
	for def_type in types():
		var entries := {}
		for entry: Dictionary in _records[def_type]:
			entry.erase("authored")
			entry.erase("resolved")
			entry.erase("patched")
			_freeze(entry.data)
			if not entry.abstract:
				entries[entry.qid] = entry.data
		canonical.defs[def_type] = entries
	content_hash = JSON.stringify(canonical, "", true).sha256_text().substr(0, 16)


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value:
			_freeze(item)
		value.make_read_only()
