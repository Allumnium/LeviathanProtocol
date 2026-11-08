class_name RunContent
extends RefCounted

const FORMAT := "leviathan_content"
const VERSION := 1

static func capture(database: DefDatabase) -> Dictionary:
	var snapshot := {"format": FORMAT, "version": VERSION, "content_hash": database.content_hash,
		"packs": [], "schemas": {}, "records": []}
	for pack: PackManifest in database.packs:
		var manifest := pack.to_dict()
		manifest["root"] = pack.root
		manifest["hash"] = pack_hash(database, pack)
		snapshot.packs.append(manifest)
	for name: String in database.schemas.names():
		snapshot.schemas[name] = database.schemas.get_schema(name).duplicate(true)
	for type: String in database.types():
		for record: Dictionary in database.records(type):
			snapshot.records.append({"type": type, "id": record.id, "pack": record.pack,
				"abstract": record.abstract, "file": record.file, "data": record.data.duplicate(true)})
	snapshot["sha256"] = digest(snapshot)
	return snapshot

static func pack_hash(database: DefDatabase, pack: PackManifest) -> String:
	var body := {"manifest": pack.to_dict(), "defs": {}}
	for type: String in database.types():
		for record: Dictionary in database.records(type):
			if record.pack == pack.id:
				body.defs[type + "/" + record.qid] = record.data
	return JSON.stringify(JSON.parse_string(JSON.stringify(body)), "", true).sha256_text()

static func pack_summary(frozen: Dictionary) -> Array:
	return frozen.packs.map(func(pack: Dictionary) -> Dictionary:
		return {"id": pack.id, "version": pack.version, "hash": pack.hash})

static func digest(snapshot: Dictionary) -> String:
	var body := snapshot.duplicate(true)
	body.erase("sha256")
	# Hash the JSON representation rather than GDScript's int/float distinction.
	# The same integral number can come from a schema or a parsed save.
	return JSON.stringify(JSON.parse_string(JSON.stringify(body)), "", true).sha256_text()

## Reconstructs resolved rules without consulting installed packs or their files.
## Missing art is permitted; damaged rules/references/formulas fail closed.
static func restore(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary or not SaveValidation.json_value(snapshot) \
			or snapshot.get("format") != FORMAT or snapshot.get("version") != VERSION \
			or not snapshot.get("packs") is Array or not snapshot.get("schemas") is Dictionary \
			or not snapshot.get("records") is Array or snapshot.get("sha256") != digest(snapshot):
		return {"error": "Frozen content is missing or damaged."}
	var problems := ContentProblems.new()
	var packs: Array[PackManifest] = []
	var pack_ids := {}
	for entry: Variant in snapshot.packs:
		if not entry is Dictionary or not entry.get("root") is String:
			return {"error": "Frozen pack metadata is invalid."}
		var authored: Dictionary = entry.duplicate(true)
		authored.erase("root")
		authored.erase("hash")
		var pack := PackManifest.parse(authored, entry.root, problems)
		if pack == null or pack_ids.has(pack.id):
			return {"error": "Frozen pack metadata is invalid."}
		pack_ids[pack.id] = true
		packs.append(pack)
	var database := DefDatabase.new()
	database.schemas = SchemaRegistry.new()
	for name: Variant in snapshot.schemas:
		if not name is String or not snapshot.schemas[name] is Dictionary:
			return {"error": "Frozen schemas are invalid."}
		database.schemas.register(name, snapshot.schemas[name].duplicate(true))
	database.setup(packs)
	var id_pattern := RegEx.create_from_string(PackLoader.ID_PATTERN)
	for entry: Variant in snapshot.records:
		if not entry is Dictionary or not entry.get("type") is String or not entry.get("id") is String \
				or not entry.get("pack") is String or not pack_ids.has(entry.pack) \
				or not entry.get("abstract") is bool or not entry.get("data") is Dictionary \
				or id_pattern.search(entry.id) == null or not database.schemas.has_schema(entry.type):
			return {"error": "Frozen definition metadata is invalid."}
		var record: Dictionary = entry.duplicate(true)
		record["qid"] = entry.pack + ":" + entry.id
		record["index"] = database.records(entry.type).size()
		record["parent"] = ""
		record["notes"] = ""
		if not database.add_record(record):
			return {"error": "Frozen definitions contain a duplicate identity."}
	for type: String in database.types():
		for record: Dictionary in database.records(type):
			if record.abstract:
				continue
			var data: Dictionary = record.data.duplicate(true)
			if data.get("id") != record.id:
				return {"error": "Frozen definition identity does not match its record."}
			data.erase("id")
			var collected := database.schemas.validate(type, data)
			if not collected.problems.is_empty():
				return {"error": "Invalid frozen definition %s: %s" % [record.qid, collected.problems[0].message]}
			for ref: Dictionary in collected.refs:
				if not database.has_def(ref.type, ref.value, record.pack):
					return {"error": "Frozen reference is unavailable: %s / %s" % [record.qid, ref.path]}
			for expr: Dictionary in collected.exprs:
				var expected := str(expr.spec.get("type", "any"))
				if not expr.get("literal", false) and not ExprContexts.has(str(expr.spec.get("context", ExprContexts.STATIC))):
					return {"error": "Frozen formula context is unavailable: " + record.qid}
				var formula := Formula.constant(expr.value, expected) if expr.get("literal", false) else \
					ExprContexts.compile(expr.value, str(expr.spec.get("context", ExprContexts.STATIC)), expected)
				if not formula.ok():
					return {"error": "Frozen formula is invalid: %s / %s" % [record.qid, expr.path]}
				database.set_formula(type, record.qid, expr.path, formula)
	var loader := PackLoader.new()
	for type: String in database.types():
		if not loader.checks.has(type):
			continue
		for record: Dictionary in database.records(type):
			if record.abstract:
				continue
			var issues: Array = loader.checks[type].call(record.data, database.meta(type, record.qid), database)
			for issue: Dictionary in issues:
				if issue.get("severity", ContentProblems.ERROR) == ContentProblems.ERROR:
					return {"error": "Invalid frozen relationship %s: %s" % [record.qid, issue.message]}
	database.freeze()
	if database.content_hash != snapshot.get("content_hash"):
		return {"error": "Frozen content hash does not match its definitions."}
	for pack: PackManifest in database.packs:
		if pack_hash(database, pack) != snapshot.packs[database.pack_position(pack.id)].get("hash"):
			return {"error": "Frozen pack hash does not match its definitions: " + pack.id}
	return {"database": database}
