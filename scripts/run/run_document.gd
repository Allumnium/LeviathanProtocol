class_name RunDocument
extends RefCounted

const FLEET_FIELDS := ["credits", "missiles", "ships", "equipment", "squadrons", "next_ship_id", "next_equipment_id",
	"research", "pending", "ended", "completed", "pending_encounter", "battle_reserves"]
const GRAPH_FIELDS := ["current", "destination", "planned", "visited", "journey_rp", "navigation"]
static var _schema: SchemaRegistry

static func schema() -> SchemaRegistry:
	if _schema == null:
		_schema = SchemaRegistry.new()
		_schema.register("run", JSON.parse_string(FileAccess.get_file_as_string("res://schemas/run/run.schema.json")))
	return _schema

## Temporary adapter removed as P3 extracts the remaining gameplay systems.
## Existing semantic validation remains in use until its invariants move here.
static func from_hangar(data: Dictionary, frozen: Dictionary, scenario: String, previous: Dictionary = {}) -> Dictionary:
	var doc := previous.duplicate(true)
	if doc.is_empty():
		doc = {"meta": {"format": "leviathan_run", "version": 1, "id": data.run_id, "seed": data.seed,
			"difficulty": data.difficulty, "scenario": scenario, "mode": "story",
			"content_hash": frozen.content_hash, "content_sha256": frozen.sha256, "packs": RunContent.pack_summary(frozen)},
			"rng": RngStreams.new(data.seed).snapshot(), "factions": {}, "actors": {}, "quests": {},
			"pressures": {}, "director": {}, "chronicle": [], "vars": {}, "sites": {}}
		for location: Dictionary in Content.copies("location"):
			doc.sites[location.id] = location
	doc.meta.id = data.run_id
	doc.meta.seed = data.seed
	doc.meta.difficulty = data.difficulty
	doc["fleet"] = {}
	for key: String in FLEET_FIELDS:
		doc.fleet[key] = data.get(key, {} if key == "battle_reserves" else null)
	doc["galaxy"] = {"campaign": {}}
	for key: String in GRAPH_FIELDS:
		if data.has(key):
			doc.galaxy.campaign[key] = data[key]
	doc["travel"] = data.get("expedition", {})
	doc["clock"] = {"seconds": doc.travel.get("simulation_seconds", 0.0), "travel_days": doc.travel.get("traveled_days", 0.0)}
	doc["stats"] = data.get("score", {})
	return doc.duplicate(true)

static func to_hangar(doc: Dictionary) -> Dictionary:
	var data := {"format": "physical_hangar", "version": 2, "run_id": doc.meta.id,
		"seed": doc.meta.seed, "difficulty": doc.meta.difficulty}
	data.merge(doc.fleet.duplicate(true))
	data.merge(doc.galaxy.get("campaign", {}).duplicate(true))
	if not doc.travel.is_empty():
		data["expedition"] = doc.travel.duplicate(true)
	if not doc.stats.is_empty():
		data["score"] = doc.stats.duplicate(true)
	return data

static func shape_valid(doc: Variant) -> bool:
	return doc is Dictionary and SaveValidation.json_value(doc) and schema().validate("run", doc).problems.is_empty()

static func normalized(doc: Dictionary) -> Dictionary:
	return schema().normalized("run", doc)

static func valid(doc: Variant) -> bool:
	if not shape_valid(doc) or doc.rng.seed != doc.meta.seed or not doc.meta.seed.is_valid_int() or int(doc.meta.seed) < 0:
		return false
	if not is_equal_approx(doc.clock.seconds, doc.travel.get("simulation_seconds", 0.0)) \
			or not is_equal_approx(doc.clock.travel_days, doc.travel.get("traveled_days", 0.0)):
		return false
	var rng := RngStreams.new()
	for index in doc.chronicle.size():
		if doc.chronicle[index].id != index + 1:
			return false
	return rng.restore(doc.rng) and HangarCheckpoint.valid(to_hangar(doc))
