class_name PackManifest
extends RefCounted

## pack.json: identity, version, dependencies and Workshop metadata.

const ID_PATTERN := "^[a-z][a-z0-9_]{1,63}$"
const KINDS := ["content", "scenario"]
const KNOWN_KEYS := ["id", "name", "version", "authors", "kind", "game_version", "depends", "load_after", "tags", "steam", "description", "notes"]

var id: String = ""
var name: String = ""
var version: String = "0.0.0"
var authors: PackedStringArray = PackedStringArray()
var kind: String = "content"
var game_version: String = ""
var description: String = ""
## [{"id": String, "version": range String}]
var depends: Array[Dictionary] = []
var load_after: PackedStringArray = PackedStringArray()
var tags: PackedStringArray = PackedStringArray()
var steam: Dictionary = {}
## Absolute directory, such as res://packs/core or user://packs/my_pack.
var root: String = ""
var read_only: bool = false


static func parse(data: Variant, pack_root: String, problems: ContentProblems) -> PackManifest:
	var file := pack_root.path_join("pack.json")
	if not data is Dictionary:
		problems.error("pack.json must be an object", "", file)
		return null
	var manifest := PackManifest.new()
	manifest.root = pack_root
	manifest.read_only = pack_root.begins_with("res://")
	var pack_id: Variant = data.get("id")
	if not pack_id is String or not _matches(ID_PATTERN, pack_id):
		problems.error("Pack id must be 2-64 lowercase letters, digits or _ and start with a letter", "", file, "", "id")
		return null
	manifest.id = pack_id
	var ok := true
	for key in data:
		if key not in KNOWN_KEYS:
			problems.warning("Unknown manifest field '%s'" % key, pack_id, file, "", str(key))
	if not data.get("name") is String or data.name.strip_edges().is_empty():
		problems.error("Pack needs a name", pack_id, file, "", "name")
		ok = false
	else:
		manifest.name = data.name
	if not data.get("version") is String or parse_version(data.version).is_empty():
		problems.error("Version must look like 1.2.0", pack_id, file, "", "version")
		ok = false
	else:
		manifest.version = data.version
	var pack_kind: Variant = data.get("kind", "content")
	if pack_kind not in KINDS:
		problems.error("Kind must be content or scenario", pack_id, file, "", "kind")
		ok = false
	else:
		manifest.kind = pack_kind
	manifest.description = str(data.get("description", ""))
	manifest.game_version = str(data.get("game_version", ""))
	if not manifest.game_version.is_empty() and not valid_range(manifest.game_version):
		problems.error("game_version must be a range such as >=0.5", pack_id, file, "", "game_version")
		ok = false
	for key in ["authors", "load_after", "tags"]:
		var values: Variant = data.get(key, [])
		if not values is Array or not values.all(func(value: Variant) -> bool: return value is String):
			problems.error("%s must be a list of text" % key, pack_id, file, "", key)
			ok = false
			continue
		manifest.set(key, PackedStringArray(values))
	var dependencies: Variant = data.get("depends", [])
	if not dependencies is Array:
		problems.error("depends must be a list", pack_id, file, "", "depends")
		ok = false
	else:
		for index in dependencies.size():
			var entry: Variant = dependencies[index]
			var path := "depends[%d]" % index
			if entry is String:
				entry = {"id": entry, "version": "*"}
			if not entry is Dictionary or not entry.get("id") is String or not _matches(ID_PATTERN, entry.id):
				problems.error("Dependency needs a valid pack id", pack_id, file, "", path)
				ok = false
				continue
			var wanted := str(entry.get("version", "*"))
			if not valid_range(wanted):
				problems.error("Dependency version must be a range such as >=1.0", pack_id, file, "", path + ".version")
				ok = false
				continue
			manifest.depends.append({"id": entry.id, "version": wanted})
	var steam_data: Variant = data.get("steam", {})
	if not steam_data is Dictionary:
		problems.error("steam must be an object", pack_id, file, "", "steam")
		ok = false
	else:
		manifest.steam = steam_data.duplicate(true)
	return manifest if ok else null


func dependency_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in depends:
		ids.append(entry.id)
	return ids


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "version": version, "authors": Array(authors), "kind": kind,
		"game_version": game_version, "description": description, "depends": depends.duplicate(true),
		"load_after": Array(load_after), "tags": Array(tags), "steam": steam.duplicate(true)}


static func _matches(pattern: String, text: String) -> bool:
	var regex := RegEx.create_from_string(pattern)
	return regex.search(text) != null


## "1.2.3" or "1.2" -> [1, 2, 3]; empty when malformed.
static func parse_version(text: String) -> Array[int]:
	var parts := text.strip_edges().split(".")
	if parts.size() < 1 or parts.size() > 3:
		return []
	var result: Array[int] = []
	for part in parts:
		if not part.is_valid_int() or int(part) < 0:
			return []
		result.append(int(part))
	while result.size() < 3:
		result.append(0)
	return result


static func compare_versions(a: Array[int], b: Array[int]) -> int:
	for index in 3:
		if a[index] != b[index]:
			return -1 if a[index] < b[index] else 1
	return 0


## Ranges: "*", "1.2.0" (exact), ">=1.0", ">1.0", "<=2", "<2", "^1.2" (same major),
## "~1.2" (same minor), and space-separated combinations such as ">=1.0 <2".
static func valid_range(text: String) -> bool:
	for clause in _clauses(text):
		if clause == "*":
			continue
		if parse_version(_strip_operator(clause)).is_empty():
			return false
	return true


static func satisfies(version_text: String, range_text: String) -> bool:
	var actual := parse_version(version_text)
	if actual.is_empty():
		return false
	for clause in _clauses(range_text):
		if clause == "*":
			continue
		var wanted := parse_version(_strip_operator(clause))
		if wanted.is_empty():
			return false
		var order := compare_versions(actual, wanted)
		var ok := false
		if clause.begins_with(">="):
			ok = order >= 0
		elif clause.begins_with("<="):
			ok = order <= 0
		elif clause.begins_with(">"):
			ok = order > 0
		elif clause.begins_with("<"):
			ok = order < 0
		elif clause.begins_with("^"):
			ok = order >= 0 and actual[0] == wanted[0]
		elif clause.begins_with("~"):
			ok = order >= 0 and actual[0] == wanted[0] and actual[1] == wanted[1]
		else:
			ok = order == 0
		if not ok:
			return false
	return true


static func _clauses(text: String) -> PackedStringArray:
	var clauses := PackedStringArray()
	for clause in text.strip_edges().split(" ", false):
		clauses.append(clause.strip_edges())
	if clauses.is_empty():
		clauses.append("*")
	return clauses


static func _strip_operator(clause: String) -> String:
	for prefix in [">=", "<=", ">", "<", "^", "~", "="]:
		if clause.begins_with(prefix):
			return clause.substr(prefix.length())
	return clause
