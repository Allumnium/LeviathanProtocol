class_name ExpeditionSimulation
extends RefCounted

const State = preload("res://scripts/expedition_state.gd")
const MAX_BOUNDARY_HISTORY := 64

signal boundary_reached(kind: int, details: Dictionary)

var state: State
var tuning: Dictionary = {}
var locations: Dictionary = {}
var accumulator := 0.0
var last_error := ""
var emitted_boundaries: Array[Dictionary] = []
var boundary_sequence := 0


func configure(seed_value: int) -> bool:
	last_error = ""
	var tuning_json := JSON.new()
	if tuning_json.parse(FileAccess.get_file_as_string("res://data/expedition_tuning.json")) != OK \
			or not State.valid_tuning(tuning_json.data):
		return _fail("Invalid expedition tuning data.")
	tuning = tuning_json.data
	var locations_json := JSON.new()
	if locations_json.parse(FileAccess.get_file_as_string(tuning.locations_path)) != OK \
			or not State.valid_locations(locations_json.data):
		return _fail("Invalid expedition location data.")
	locations.clear()
	for location: Dictionary in locations_json.data.locations:
		locations[location.id] = location.duplicate(true)
	var start: Dictionary = locations.get("start_station", {})
	state = State.new()
	if not state.initialize(seed_value, start, tuning):
		state = null
		return _fail("Could not initialize expedition state.")
	for location: Dictionary in locations.values():
		if location.discovered and location.id not in state.discovered_location_ids:
			state.discovered_location_ids.append(location.id)
	accumulator = 0.0
	emitted_boundaries.clear()
	return true


func restore(snapshot: Dictionary) -> bool:
	if not State.valid(snapshot) or tuning.is_empty() or locations.is_empty():
		return _fail("Cannot restore invalid or unconfigured expedition state.")
	if state != null and int(snapshot.seed) != state.seed:
		return _fail("Saved run seed does not match the configured world.")
	var restored := State.new()
	if not restored.restore(snapshot):
		return _fail("Could not restore expedition state.")
	if not is_equal_approx(restored.traveled_days,
			restored.traveled_distance_nu / float(tuning.nav_units_per_day)):
		return _fail("Saved travel clocks are inconsistent.")
	if not is_equal_approx(restored.simulation_seconds,
			float(restored.simulation_tick) * float(tuning.fixed_tick_seconds)):
		return _fail("Saved simulation clock is inconsistent.")
	for id: String in restored.discovered_location_ids:
		if not locations.has(id):
			return _fail("Saved discovery does not exist in this world.")
	for id: String in restored.visited_location_ids:
		if not locations.has(id):
			return _fail("Saved visit does not exist in this world.")
	if not restored.docked_location_id.is_empty():
		var dock: Dictionary = locations.get(restored.docked_location_id, {})
		if dock.is_empty() or dock.kind != "station" or restored.position_nu.distance_to(
				Vector2(dock.position[0], dock.position[1])) > 0.000001:
			return _fail("Saved dock position does not match its station.")
	if not restored.destination_location_id.is_empty():
		var destination: Dictionary = locations.get(restored.destination_location_id, {})
		if destination.is_empty() or not destination.accessible \
				or restored.discovered_location_ids.find(restored.destination_location_id) < 0:
			return _fail("Saved destination is unavailable.")
	state = restored
	accumulator = 0.0
	emitted_boundaries.clear()
	return true


func request_destination(id: String) -> bool:
	if not _configured() or state.travel_state in [
			State.TravelState.SETTLING, State.TravelState.REGROUPING, State.TravelState.DEFEAT,
			State.TravelState.TOWING]:
		return _fail("Cannot change course in the current expedition state.")
	var target: Dictionary = locations.get(id, {})
	if target.is_empty() or not target.accessible:
		return _fail("Destination is not accessible.")
	if id not in state.discovered_location_ids:
		return _fail("Destination has not been discovered.")
	if state.travel_state == State.TravelState.ENGAGED:
		state.destination_location_id = id
		return true
	if state.position_nu.distance_to(Vector2(target.position[0], target.position[1])) <= 0.000001:
		if target.kind == "station":
			state.docked_location_id = id
			state.destination_location_id = ""
			state.travel_state = State.TravelState.DOCKED
			state.departure_choice_pending = false
			_mark_visited(id)
			return true
		return _fail("Destination is already at the fleet's position.")
	state.destination_location_id = id
	state.departure_choice_pending = false
	state.docked_location_id = ""
	state.travel_state = State.TravelState.CRUISING
	accumulator = 0.0
	return true

func begin_departure_choice() -> bool:
	if not _configured() or state.travel_state not in [State.TravelState.DOCKED, State.TravelState.STOPPED] \
			or not state.destination_location_id.is_empty():
		return _fail("Choose the next destination after the current journey ends.")
	state.departure_choice_pending = true
	accumulator = 0.0
	return true


func stop() -> bool:
	if not _configured() or state.travel_state != State.TravelState.CRUISING:
		return _fail("The fleet is not underway.")
	state.stopped_from = state.travel_state
	state.travel_state = State.TravelState.STOPPED
	accumulator = 0.0
	return true


func resume() -> bool:
	if not _configured() or _paused() or state.travel_state != State.TravelState.STOPPED \
			or state.destination_location_id.is_empty():
		return _fail("The expedition cannot resume in its current state.")
	state.travel_state = state.stopped_from
	accumulator = 0.0
	return true


func cancel_destination() -> bool:
	if not _configured() or state.travel_state not in [State.TravelState.CRUISING, State.TravelState.STOPPED,
			State.TravelState.ENGAGED] \
			or state.destination_location_id.is_empty():
		return _fail("There is no cancellable destination.")
	state.destination_location_id = ""
	if state.travel_state != State.TravelState.ENGAGED:
		state.docked_location_id = ""
		state.travel_state = State.TravelState.STOPPED
		state.stopped_from = State.TravelState.CRUISING
	accumulator = 0.0
	return true


func set_speed(multiplier: int) -> bool:
	if not _configured() or multiplier not in State.SPEEDS:
		return _fail("Unsupported expedition speed.")
	if state.travel_state in [State.TravelState.ENGAGED, State.TravelState.SETTLING,
			State.TravelState.REGROUPING] and multiplier != 1:
		return _fail("Threat and regroup phases are limited to 1x.")
	state.requested_speed = multiplier
	return true


func set_pause(reason: int, enabled: bool) -> bool:
	if not _configured() or reason < 0 or reason >= State.PauseReason.size():
		return _fail("Invalid pause reason.")
	if enabled and reason not in state.pause_reasons:
		state.pause_reasons.append(reason)
	elif not enabled and reason in state.pause_reasons:
		state.pause_reasons.erase(reason)
	if _paused():
		accumulator = 0.0
	return true


func advance(real_delta: float) -> bool:
	if not _configured() or not SaveValidation.number(real_delta) or real_delta < 0.0:
		return _fail("Invalid expedition frame duration.")
	if _paused() or state.departure_choice_pending or state.travel_state == State.TravelState.DEFEAT:
		return true
	var effective_speed := 1 if state.travel_state in [State.TravelState.ENGAGED,
			State.TravelState.SETTLING, State.TravelState.REGROUPING] else state.requested_speed
	accumulator += real_delta * float(effective_speed)
	var tick := float(tuning.fixed_tick_seconds)
	var prior_boundary_sequence := boundary_sequence
	while accumulator + 0.000000001 >= tick:
		accumulator -= tick
		state.simulation_tick += 1
		state.simulation_seconds += tick
		if state.travel_state == State.TravelState.CRUISING:
			if not _advance_cruise(tick):
				return false
			if boundary_sequence != prior_boundary_sequence:
				accumulator = 0.0
				break
		elif state.travel_state == State.TravelState.STOPPED:
			pass
	if accumulator < 0.0:
		accumulator = 0.0
	return true


func _advance_cruise(delta: float) -> bool:
	var destination: Dictionary = locations.get(state.destination_location_id, {})
	if destination.is_empty():
		return _fail("Active destination is missing from the world.")
	var target := Vector2(destination.position[0], destination.position[1])
	var to_target := target - state.position_nu
	var distance_remaining := to_target.length()
	if distance_remaining <= 0.000001:
		_arrive(destination)
		return true
	var step_distance := minf(float(tuning.cruise_units_per_sim_second) * delta, distance_remaining)
	var fuel_distance := state.fuel / float(tuning.fuel_per_nav_unit)
	var distance := minf(step_distance, fuel_distance)
	if distance > 0.0:
		var delta_position := to_target.normalized() * distance
		state.position_nu += delta_position
		state.fuel = maxf(0.0, state.fuel - distance * float(tuning.fuel_per_nav_unit))
		state.traveled_distance_nu += distance
		state.traveled_days += distance / float(tuning.nav_units_per_day)
	if distance + 0.000001 < step_distance or (state.fuel <= 0.000001 and distance_remaining - distance > 0.000001):
		state.fuel = 0.0
		state.stopped_from = State.TravelState.CRUISING
		state.travel_state = State.TravelState.STOPPED
		state.requested_speed = 1
		if State.PauseReason.FUEL not in state.pause_reasons:
			state.pause_reasons.append(State.PauseReason.FUEL)
		_emit_boundary(State.BoundaryKind.FUEL_EMPTY, {
			"position_nu": [state.position_nu.x, state.position_nu.y],
			"destination_id": state.destination_location_id
		})
		return true
	if distance_remaining - distance <= 0.000001:
		state.position_nu = target
		_arrive(destination)
	return true


func _arrive(location: Dictionary) -> void:
	var id: String = location.id
	var kind := State.BoundaryKind.DOCK if location.kind == "station" else State.BoundaryKind.ARRIVAL
	state.destination_location_id = ""
	state.docked_location_id = id if location.kind == "station" else ""
	state.travel_state = State.TravelState.DOCKED if location.kind == "station" else State.TravelState.STOPPED
	state.stopped_from = State.TravelState.CRUISING
	state.requested_speed = 1
	state.departure_choice_pending = true
	_mark_visited(id)
	_emit_boundary(kind, {"location_id": id, "position_nu": [state.position_nu.x, state.position_nu.y]})


func _mark_visited(id: String) -> void:
	if id not in state.discovered_location_ids:
		state.discovered_location_ids.append(id)
	if id not in state.visited_location_ids:
		state.visited_location_ids.append(id)


func _emit_boundary(kind: int, details: Dictionary) -> void:
	boundary_sequence += 1
	var event := {"kind": kind, "tick": state.simulation_tick, "details": details.duplicate(true)}
	if emitted_boundaries.size() >= MAX_BOUNDARY_HISTORY:
		emitted_boundaries.pop_front()
	emitted_boundaries.append(event)
	boundary_reached.emit(kind, details.duplicate(true))


func _paused() -> bool:
	return not state.pause_reasons.is_empty()


func _configured() -> bool:
	return state != null and not tuning.is_empty() and not locations.is_empty()


func _fail(message: String) -> bool:
	last_error = message
	return false
