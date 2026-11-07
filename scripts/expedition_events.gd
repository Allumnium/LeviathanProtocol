extends RefCounted

const TRIGGERS := ["distance", "zone", "arrival", "start", "departure", "story"]
const EFFECT_KEYS := ["detour", "credits", "fuel", "research", "hull_damage", "combat", "flag",
	"discover", "requires_credits", "complete", "rescue_ship", "missiles", "flags", "requires_fuel"]

# Event defs in load order; within a trigger the first ready event fires.
static func catalog() -> Dictionary:
	var events: Array = []
	for record: Dictionary in Content.db().records("event"):
		if record.abstract:
			continue
		var event := Content.view("event", record.qid)
		for option: Dictionary in event.get("options", []):
			if option.get("effects", {}).has("combat"):
				option.effects.combat.id = record.pack + ":" + str(option.effects.combat.id)
		events.append(event)
	return {"version": 1, "events": events}

# Older fixtures only declared `distance_nu`; they remain distance triggers with
# the original Investigate / Continue Course choices.
static func trigger(event: Dictionary) -> String:
	return str(event.get("trigger", "distance"))

static func options(event: Dictionary) -> Array:
	if event.get("options") is Array:
		return event.options
	return [
		{"id": "investigate", "label": "INVESTIGATE", "effects": {"detour": true}},
		{"id": "continue", "label": "CONTINUE COURSE", "effects": {}}]

static func option(event: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in options(event):
		if entry.id == id:
			return entry
	return {}

static func valid(value: Variant, locations: Dictionary) -> bool:
	if not value is Dictionary or value.get("version") != 1 \
			or not value.get("events") is Array or value.events.size() > 128:
		return false
	var ids := {}
	var declared_flags := {}
	for source: Variant in value.events:
		if not source is Dictionary or not source.get("options", []) is Array:
			return false
		for choice: Variant in source.get("options", []):
			if not choice is Dictionary or not choice.get("effects", {}) is Dictionary:
				return false
			var effects: Dictionary = choice.get("effects", {})
			if effects.get("flag") is String:
				declared_flags[effects.flag] = true
			if effects.get("flags", []) is Array:
				for flag: Variant in effects.get("flags", []):
					if flag is String:
						declared_flags[flag] = true
			if effects.get("combat", {}) is Dictionary:
				for outcome in ["victory_flags", "withdrawal_flags"]:
					if effects.get("combat", {}).get(outcome, []) is Array:
						for flag: Variant in effects.get("combat", {}).get(outcome, []):
							if flag is String:
								declared_flags[flag] = true
	var previous_distance := -1.0
	var starts := 0
	for event: Variant in value.events:
		if not event is Dictionary or not event.get("id") is String or event.id.is_empty() \
				or ids.has(event.id) or not event.get("title") is String or event.title.is_empty() \
				or not event.get("text") is String or event.text.is_empty() \
				or trigger(event) not in TRIGGERS:
			return false
		if event.has("requires_flag") and (not event.requires_flag is String or event.requires_flag.is_empty()):
			return false
		for field in ["requires_flags", "excludes_flags"]:
			if not valid_flags(event.get(field, [])):
				return false
		if not valid_condition_references(event, declared_flags):
			return false
		if event.has("text_variants"):
			if not event.text_variants is Array:
				return false
			for variant: Variant in event.text_variants:
				if not variant is Dictionary or not variant.get("text") is String \
						or not valid_flags(variant.get("requires_flags", [])) \
						or not valid_flags(variant.get("excludes_flags", [])) \
						or not variant.get("capability", "") is String or not variant.get("chassis", "") is String:
					return false
				if not valid_condition_references(variant, declared_flags) \
						or (not variant.get("chassis", "").is_empty() and SlotCatalog.find_chassis(variant.chassis).is_empty()):
					return false
		if event.has("art") and not event.art is String:
			return false
		match trigger(event):
			"distance":
				if not SaveValidation.number(event.get("distance_nu")) or event.distance_nu < 0 \
						or event.distance_nu <= previous_distance:
					return false
				previous_distance = float(event.distance_nu)
			"zone":
				if not SaveValidation.vector(event.get("position")) or not SaveValidation.number(event.get("radius")) \
						or event.radius <= 0 or event.radius > 1000:
					return false
			"arrival", "departure":
				var target: Dictionary = locations.get(event.get("location_id", ""), {})
				if target.is_empty():
					return false
			"start":
				starts += 1
				if starts > 1:
					return false
		var needs_detour := false
		var option_ids := {}
		var choices := options(event)
		if choices.is_empty() or choices.size() > 4:
			return false
		for choice: Variant in choices:
			if not choice is Dictionary or not choice.get("id") is String or choice.id.is_empty() \
					or option_ids.has(choice.id) or not choice.get("label") is String or choice.label.is_empty() \
					or not choice.get("effects", {}) is Dictionary:
				return false
			option_ids[choice.id] = true
			if not _valid_effects(choice.get("effects", {}), locations):
				return false
			needs_detour = needs_detour or choice.get("effects", {}).get("detour", false)
		if needs_detour or event.has("destination_id"):
			if not event.get("destination_id") is String:
				return false
			var destination: Dictionary = locations.get(event.destination_id, {})
			if destination.is_empty() or not destination.accessible or destination.kind not in ["poi", "station"]:
				return false
		ids[event.id] = true
	return true

static func valid_condition_references(condition: Dictionary, declared: Dictionary) -> bool:
	if condition.has("requires_flag") and (not condition.requires_flag is String or not declared.has(condition.requires_flag)):
		return false
	for field in ["requires_flags", "excludes_flags"]:
		for flag: String in condition.get(field, []):
			if not declared.has(flag):
				return false
	return true

static func _valid_effects(effects: Dictionary, locations: Dictionary) -> bool:
	for key: Variant in effects:
		if key not in EFFECT_KEYS:
			return false
	for key in ["credits", "requires_credits"]:
		if effects.has(key) and not SaveValidation.integer(effects[key]):
			return false
	if effects.get("requires_credits", 0) < 0:
		return false
	for key in ["fuel", "research", "hull_damage", "requires_fuel"]:
		if effects.has(key) and not SaveValidation.number(effects[key]):
			return false
	if effects.get("research", 0.0) < 0 or effects.get("hull_damage", 0.0) < 0 or effects.get("hull_damage", 0.0) > 0.5:
		return false
	if effects.get("requires_fuel", 0.0) < 0 or not valid_flags(effects.get("flags", [])):
		return false
	if not valid_rewards(effects, true):
		return false
	for key in ["detour", "complete"]:
		if effects.has(key) and not effects[key] is bool:
			return false
	if effects.has("flag") and (not effects.flag is String or effects.flag.is_empty()):
		return false
	if effects.has("discover"):
		if not effects.discover is Array:
			return false
		for id: Variant in effects.discover:
			if not id is String or not locations.has(id):
				return false
	if effects.has("combat"):
		var combat: Variant = effects.combat
		if not combat is Dictionary or not combat.get("id") is String or combat.id.is_empty() or not Content.get_def("encounter", str(combat.get("template", ""))).get("story_eligible", false) \
				or not SaveValidation.integer(combat.get("row")) or combat.row < 1 or combat.row > 24 \
				or not SaveValidation.integer(combat.get("asteroids", 0)) or int(combat.get("asteroids", 0)) not in [0, 1, 2, 3] \
				or not combat.get("nebula", false) is bool:
			return false
		if combat.has("credits") and (not SaveValidation.integer(combat.credits) or combat.credits < 0):
			return false
		if combat.has("strength") and (not SaveValidation.number(combat.strength) or combat.strength < 1.0 or combat.strength > 10.0):
			return false
		if not valid_rewards(combat):
			return false
		for outcome in ["victory_flags", "withdrawal_flags"]:
			if not valid_flags(combat.get(outcome, [])):
				return false
	return true

static func valid_flags(value: Variant) -> bool:
	if not value is Array or value.size() > 32:
		return false
	var seen := {}
	for key: Variant in value:
		if not key is String or key.is_empty() or seen.has(key):
			return false
		seen[key] = true
	return true

static func valid_rewards(rewards: Dictionary, allow_fuel_cost := false) -> bool:
	if rewards.has("missiles") and (not SaveValidation.integer(rewards.missiles) \
			or rewards.missiles < 0 or rewards.missiles > 2147483647):
		return false
	for key in ["research", "fuel"]:
		if rewards.has(key) and (not SaveValidation.number(rewards[key]) \
				or (rewards[key] < 0 and not (key == "fuel" and allow_fuel_cost))):
			return false
	if rewards.has("rescue_ship"):
		if not rewards.rescue_ship is String:
			return false
		var chassis := SlotCatalog.find_chassis(rewards.rescue_ship)
		if chassis.is_empty() or chassis.flagship or preload("res://scripts/ship_loadouts.gd").default_for(rewards.rescue_ship).is_empty():
			return false
	return true

static func flag_ready(event: Dictionary, flags: Dictionary) -> bool:
	if event.has("requires_flag") and not flags.get(event.requires_flag, false):
		return false
	for key: String in event.get("requires_flags", []):
		if not flags.get(key, false):
			return false
	for key: String in event.get("excludes_flags", []):
		if flags.get(key, false):
			return false
	return true

static func boundary_event(events: Array, receipts: Dictionary, flags: Dictionary, kind: String, location_id := "") -> Dictionary:
	for event: Dictionary in events:
		if trigger(event) == kind and not receipts.get(event.id, false) and flag_ready(event, flags) \
				and (location_id.is_empty() or event.get("location_id", "") == location_id):
			return event
	return {}

static func next_event(events: Array, receipts: Dictionary, flags: Dictionary = {}) -> Dictionary:
	for event: Dictionary in events:
		if trigger(event) == "distance" and not receipts.get(event.id, false) and flag_ready(event, flags):
			return event
	return {}

static func arrival_event(events: Array, receipts: Dictionary, flags: Dictionary, location_id: String) -> Dictionary:
	for event: Dictionary in events:
		if trigger(event) == "arrival" and event.location_id == location_id \
				and not receipts.get(event.id, false) and flag_ready(event, flags):
			return event
	return {}

static func start_event(events: Array) -> Dictionary:
	for event: Dictionary in events:
		if trigger(event) == "start":
			return event
	return {}

# Earliest entry distance along a straight step into any pending zone, or {}.
static func zone_entry(events: Array, receipts: Dictionary, flags: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	var best := {}
	var best_distance := INF
	var segment := to - from
	var length := segment.length()
	if length <= 0.0:
		return {}
	var direction := segment / length
	for event: Dictionary in events:
		if trigger(event) != "zone" or receipts.get(event.id, false) or not flag_ready(event, flags):
			continue
		var center := Vector2(event.position[0], event.position[1])
		var radius := float(event.radius)
		var offset := from - center
		if offset.length() <= radius:
			if 0.0 < best_distance:
				best_distance = 0.0
				best = event
			continue
		var b := offset.dot(direction)
		var c := offset.length_squared() - radius * radius
		var discriminant := b * b - c
		if discriminant < 0.0:
			continue
		var entry := -b - sqrt(discriminant)
		if entry >= 0.0 and entry <= length and entry < best_distance:
			best_distance = entry
			best = event
	if best.is_empty():
		return {}
	return {"event": best, "distance": best_distance}

static func find(events: Array, id: String) -> Dictionary:
	for event: Dictionary in events:
		if event.id == id:
			return event
	return {}
