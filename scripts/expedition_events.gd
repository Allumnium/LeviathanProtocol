extends RefCounted

const DATA_PATH := "res://data/expedition_events.json"
const TRIGGERS := ["distance", "zone", "arrival", "start"]
const COMBAT_TEMPLATES := ["patrol", "elite", "relay_defense", "pylon_escort", "bastion_warden"]
const EFFECT_KEYS := ["detour", "credits", "fuel", "research", "hull_damage", "combat", "flag",
	"discover", "requires_credits", "complete", "rescue_ship", "missiles"]

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
			"arrival":
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
			if destination.is_empty() or not destination.accessible or destination.kind != "poi":
				return false
		ids[event.id] = true
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
	for key in ["fuel", "research", "hull_damage"]:
		if effects.has(key) and not SaveValidation.number(effects[key]):
			return false
	if effects.get("research", 0.0) < 0 or effects.get("hull_damage", 0.0) < 0 or effects.get("hull_damage", 0.0) > 0.5:
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
		if not combat is Dictionary or combat.get("template") not in COMBAT_TEMPLATES \
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
	return not event.has("requires_flag") or flags.get(event.requires_flag, false)

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
