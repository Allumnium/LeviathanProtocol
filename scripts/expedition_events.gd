extends RefCounted

const DATA_PATH := "res://data/expedition_events.json"

static func valid(value: Variant, locations: Dictionary) -> bool:
	if not value is Dictionary or value.get("version") != 1 \
			or not value.get("events") is Array or value.events.size() > 128:
		return false
	var ids := {}
	var previous_distance := -1.0
	for event: Variant in value.events:
		if not event is Dictionary or not event.get("id") is String or event.id.is_empty() \
				or ids.has(event.id) or not event.get("title") is String or event.title.is_empty() \
				or not event.get("text") is String or event.text.is_empty() \
				or not SaveValidation.number(event.get("distance_nu")) \
				or event.distance_nu < 0 or event.distance_nu <= previous_distance \
				or not event.get("destination_id") is String:
			return false
		var destination: Dictionary = locations.get(event.destination_id, {})
		if destination.is_empty() or not destination.accessible or destination.kind != "poi":
			return false
		previous_distance = float(event.distance_nu)
		ids[event.id] = true
	return true

static func next_event(events: Array, receipts: Dictionary) -> Dictionary:
	for event: Dictionary in events:
		if not receipts.get(event.id, false):
			return event
	return {}

static func find(events: Array, id: String) -> Dictionary:
	for event: Dictionary in events:
		if event.id == id:
			return event
	return {}
