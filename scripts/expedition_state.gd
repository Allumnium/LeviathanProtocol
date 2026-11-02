class_name ExpeditionState
extends RefCounted

const FORMAT := "continuous_expedition"
const VERSION := 1
const SPEEDS := [1, 5, 10, 20]
const SERVICES := ["shipyard", "refuel", "trade", "communications"]
const LOCATION_KINDS := ["station", "poi", "gate"]

enum TravelState { DOCKED, CRUISING, STOPPED, ENGAGED, SETTLING, REGROUPING, TOWING, DEFEAT }
enum PauseReason { USER, EVENT, FUEL, RESEARCH, SAVE_ERROR }
enum BoundaryKind { ARRIVAL, DOCK, FUEL_EMPTY, RESEARCH_COMPLETE, THREAT_DETECTED, DISCOVERY, SAVE_FAILURE, FLAGSHIP_DESTROYED }

var seed := 0
var simulation_tick := 0
var simulation_seconds := 0.0
var position_nu := Vector2.ZERO
var docked_location_id := ""
var destination_location_id := ""
var travel_state := TravelState.DOCKED
var stopped_from := TravelState.CRUISING
var requested_speed := 1
var pause_reasons: Array[int] = []
var fuel := 100.0
var fuel_capacity := 100.0
var traveled_distance_nu := 0.0
var traveled_days := 0.0
var research_focus := ""
var research_progress: Dictionary = {}
var discovered_location_ids: Array[String] = []
var visited_location_ids: Array[String] = []
var flags: Dictionary[String, bool] = {}
var event_receipts: Dictionary[String, bool] = {}
var departure_choice_pending := false


func snapshot() -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"seed": str(seed),
		"simulation_tick": simulation_tick,
		"simulation_seconds": simulation_seconds,
		"position_nu": [position_nu.x, position_nu.y],
		"docked_location_id": docked_location_id,
		"destination_location_id": destination_location_id,
		"travel_state": travel_state,
		"stopped_from": stopped_from,
		"requested_speed": requested_speed,
		"pause_reasons": pause_reasons.duplicate(),
		"fuel": fuel,
		"fuel_capacity": fuel_capacity,
		"traveled_distance_nu": traveled_distance_nu,
		"traveled_days": traveled_days,
		"research_focus": research_focus,
		"research_progress": research_progress.duplicate(true),
		"discovered_location_ids": discovered_location_ids.duplicate(),
		"visited_location_ids": visited_location_ids.duplicate(),
		"flags": flags.duplicate(),
		"event_receipts": event_receipts.duplicate(),
		"departure_choice_pending": departure_choice_pending
	}


func restore(value: Dictionary) -> bool:
	if not valid(value):
		return false
	seed = int(value.seed)
	simulation_tick = int(value.simulation_tick)
	simulation_seconds = float(value.simulation_seconds)
	position_nu = Vector2(value.position_nu[0], value.position_nu[1])
	docked_location_id = value.docked_location_id
	destination_location_id = value.destination_location_id
	travel_state = int(value.travel_state) as TravelState
	stopped_from = int(value.stopped_from) as TravelState
	requested_speed = int(value.requested_speed)
	pause_reasons.assign(value.pause_reasons)
	fuel = float(value.fuel)
	fuel_capacity = float(value.fuel_capacity)
	traveled_distance_nu = float(value.traveled_distance_nu)
	traveled_days = float(value.traveled_days)
	research_focus = value.research_focus
	research_progress = value.research_progress.duplicate(true)
	discovered_location_ids.assign(value.discovered_location_ids)
	visited_location_ids.assign(value.visited_location_ids)
	flags.assign(value.flags)
	event_receipts.assign(value.event_receipts)
	departure_choice_pending = value.get("departure_choice_pending", false)
	return true


func initialize(seed_value: int, start_location: Dictionary, tuning: Dictionary) -> bool:
	if seed_value < 0 or start_location.is_empty() or not valid_tuning(tuning):
		return false
	seed = seed_value
	position_nu = Vector2(start_location.position[0], start_location.position[1])
	docked_location_id = start_location.id
	fuel = float(tuning.fuel_capacity)
	fuel_capacity = float(tuning.fuel_capacity)
	discovered_location_ids.assign([start_location.id])
	visited_location_ids.assign([start_location.id])
	return true


static func valid_tuning(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	var bounds := {
		"nav_units_per_day": Vector2(1.0, 10000.0),
		"cruise_units_per_sim_second": Vector2(0.1, 100.0),
		"tactical_units_per_nav_unit": Vector2(0.1, 100.0),
		"fuel_capacity": Vector2(1.0, 100000.0),
		"fuel_per_nav_unit": Vector2(0.0001, 1000.0),
		"fixed_tick_seconds": Vector2(1.0 / 120.0, 0.1),
		"arrival_radius": Vector2(0.1, 100.0)
	}
	for key: String in bounds:
		if not SaveValidation.number(value.get(key)) or float(value[key]) < bounds[key].x \
				or float(value[key]) > bounds[key].y:
			return false
	return value.get("locations_path") is String and value.locations_path.begins_with("res://data/")


static func valid_locations(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("locations") is Array:
		return false
	if value.locations.is_empty() or value.locations.size() > 4096:
		return false
	var ids: Dictionary = {}
	for location: Variant in value.locations:
		if not location is Dictionary or not location.get("id") is String or location.id.is_empty() \
				or ids.has(location.id) or not location.get("name") is String or location.name.is_empty():
			return false
		if not SaveValidation.integer(location.get("act")) or int(location.act) < 1 or int(location.act) > 3 \
				or location.get("kind") not in LOCATION_KINDS or not SaveValidation.vector(location.get("position")):
			return false
		if absf(float(location.position[0])) > 100000.0 or absf(float(location.position[1])) > 100000.0:
			return false
		if not location.get("services") is Array or not location.get("discovered") is bool \
				or not location.get("accessible") is bool or not location.get("safe") is bool \
				or not location.get("region") is String or location.region.is_empty():
			return false
		var service_set: Dictionary = {}
		for service: Variant in location.services:
			if not service is String or service not in SERVICES or service_set.has(service):
				return false
			service_set[service] = true
		if location.kind == "station":
			if not location.get("station_key") is String or location.station_key.is_empty() \
					or location.services.is_empty():
				return false
		elif not location.services.is_empty():
			return false
		if location.kind == "gate" and (not location.get("required_flag") is String
				or location.required_flag.is_empty() or location.accessible or location.discovered):
			return false
		if location.kind == "poi" and location.get("poi_type") not in ["derelict", "asteroid_field",
				"distress", "anomaly", "hidden"]:
			return false
		ids[location.id] = true
	var start := location_by_id(value.locations, "start_station")
	var refuel := location_by_id(value.locations, "refuel_station_1")
	return not start.is_empty() and start.kind == "station" and start.accessible \
			and "refuel" in start.services and not refuel.is_empty() \
			and refuel.kind == "station" and refuel.accessible and "refuel" in refuel.services


static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != FORMAT \
			or not SaveValidation.integer(value.get("version")) or int(value.version) != VERSION:
		return false
	if not value.get("seed") is String or not value.seed.is_valid_int() or int(value.seed) < 0:
		return false
	for key in ["simulation_tick", "travel_state", "stopped_from", "requested_speed"]:
		if not SaveValidation.integer(value.get(key)):
			return false
	var travel_state := int(value.travel_state)
	if not value.get("departure_choice_pending", false) is bool:
		return false
	if value.get("departure_choice_pending", false) and (
			travel_state not in [TravelState.DOCKED, TravelState.STOPPED]
			or not str(value.get("destination_location_id", "")).is_empty()):
		return false
	var stopped_from := int(value.stopped_from)
	if value.simulation_tick < 0 or travel_state < 0 or travel_state >= TravelState.size() \
			or stopped_from < 0 or stopped_from >= TravelState.size() \
			or int(value.requested_speed) not in SPEEDS:
		return false
	if not SaveValidation.number(value.get("simulation_seconds")) or value.simulation_seconds < 0 \
			or not SaveValidation.vector(value.get("position_nu")):
		return false
	for key in ["docked_location_id", "destination_location_id", "research_focus"]:
		if not value.get(key) is String:
			return false
	if not value.get("pause_reasons") is Array or not value.get("research_progress") is Dictionary \
			or not value.get("discovered_location_ids") is Array or not value.get("visited_location_ids") is Array \
			or not value.get("flags") is Dictionary or not value.get("event_receipts") is Dictionary:
		return false
	for key in ["fuel", "fuel_capacity", "traveled_distance_nu", "traveled_days"]:
		if not SaveValidation.number(value.get(key)) or value[key] < 0:
			return false
	if value.fuel_capacity <= 0 or value.fuel > value.fuel_capacity:
		return false
	var pause_set: Dictionary = {}
	for reason: Variant in value.pause_reasons:
		if not SaveValidation.integer(reason) or int(reason) < 0 or int(reason) >= PauseReason.size() \
				or pause_set.has(int(reason)):
			return false
		pause_set[int(reason)] = true
	var unique_discovered: Dictionary = {}
	for id: Variant in value.discovered_location_ids:
		if not id is String or id.is_empty() or unique_discovered.has(id):
			return false
		unique_discovered[id] = true
	var unique_visited: Dictionary = {}
	for id: Variant in value.visited_location_ids:
		if not id is String or id.is_empty() or unique_visited.has(id) or not unique_discovered.has(id):
			return false
		unique_visited[id] = true
	if not value.docked_location_id.is_empty() and not unique_visited.has(value.docked_location_id):
		return false
	if travel_state == TravelState.DOCKED:
		if value.docked_location_id.is_empty() or not value.destination_location_id.is_empty():
			return false
	elif not value.docked_location_id.is_empty():
		return false
	if travel_state in [TravelState.CRUISING, TravelState.TOWING] \
			and value.destination_location_id.is_empty():
		return false
	if travel_state == TravelState.STOPPED:
		if stopped_from not in [TravelState.CRUISING, TravelState.TOWING]:
			return false
	elif travel_state == TravelState.DEFEAT \
			and (not value.destination_location_id.is_empty() or not value.docked_location_id.is_empty()):
		return false
	for key: Variant in value.flags:
		if not key is String or key.is_empty() or not value.flags[key] is bool:
			return false
	for key: Variant in value.event_receipts:
		if not key is String or key.is_empty() or not value.event_receipts[key] is bool:
			return false
	for key: Variant in value.research_progress:
		if not key is String or key.is_empty() or not SaveValidation.number(value.research_progress[key]) \
				or value.research_progress[key] < 0:
			return false
	return SaveValidation.json_value(value.research_progress)


static func location_by_id(locations: Array, id: String) -> Dictionary:
	for location: Dictionary in locations:
		if location.id == id:
			return location
	return {}
