extends SceneTree

const ExpeditionStateClass = preload("res://scripts/expedition_state.gd")
const ExpeditionSimulationClass = preload("res://scripts/expedition_simulation.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _simulation():
	var simulation = ExpeditionSimulationClass.new()
	check(simulation.configure(81), "Configure deterministic navigation")
	return simulation


func _advance_seconds(simulation, seconds: float, frame_seconds := 1.0 / 60.0) -> void:
	var frames := int(ceil(seconds / frame_seconds))
	for _frame in range(frames):
		var delta := minf(frame_seconds, seconds)
		if seconds <= 0.0:
			break
		if not simulation.advance(delta):
			check(false, "Advance valid simulation time")
			return
		seconds -= delta
		if simulation.state.travel_state in [ExpeditionStateClass.TravelState.DOCKED,
				ExpeditionStateClass.TravelState.STOPPED] and simulation.state.destination_location_id.is_empty():
			break


func run() -> void:
	var runs: Array = []
	for speed in ExpeditionStateClass.SPEEDS:
		var simulation = _simulation()
		check(simulation.request_destination("refuel_station_1"), "Select discovered non-adjacent destination")
		check(simulation.set_speed(speed), "Set supported speed %d" % speed)
		_advance_seconds(simulation, 30.0 / float(speed))
		runs.append(simulation)
	for index in range(1, runs.size()):
		check(is_equal_approx(runs[0].state.traveled_distance_nu, runs[index].state.traveled_distance_nu),
			"Equal simulated seconds produce equal distance")
		check(is_equal_approx(runs[0].state.fuel, runs[index].state.fuel),
			"Fuel depends on distance, not speed")
		check(is_equal_approx(runs[0].state.traveled_days, runs[index].state.traveled_days),
			"Travel days depend on distance, not speed")
	var reroute = _simulation()
	check(reroute.request_destination("refuel_station_1"), "Start initial course")
	for _tick in range(97):
		check(reroute.advance(1.0 / 30.0), "Advance before reroute")
	var old_position: Vector2 = reroute.state.position_nu
	check(reroute.request_destination("derelict_1"), "Reroute to discovered POI")
	check(reroute.state.position_nu == old_position, "Reroute begins at current position")
	check(reroute.state.destination_location_id == "derelict_1", "Reroute replaces previous destination")
	check(reroute.stop(), "Stop cruise independently of pause")
	var stopped_position: Vector2 = reroute.state.position_nu
	check(reroute.advance(2.0) and reroute.state.position_nu == stopped_position,
		"Stopped travel does not move")
	check(reroute.resume(), "Resume stopped route")
	check(reroute.set_pause(ExpeditionStateClass.PauseReason.USER, true), "Pause simulation")
	var paused_tick: int = reroute.state.simulation_tick
	check(reroute.advance(2.0) and reroute.state.simulation_tick == paused_tick,
		"Pause freezes authoritative ticks")
	check(reroute.set_pause(ExpeditionStateClass.PauseReason.EVENT, true), "Add independent event pause")
	check(reroute.set_pause(ExpeditionStateClass.PauseReason.USER, false)
			and not reroute.resume(), "Clearing user pause does not clear event pause")
	check(reroute.set_pause(ExpeditionStateClass.PauseReason.EVENT, false)
			and reroute.state.pause_reasons.is_empty()
			and reroute.advance(1.0 / 30.0), "Simulation resumes only after all pause reasons clear")
	var paused_route = _simulation()
	check(paused_route.set_pause(ExpeditionStateClass.PauseReason.USER, true)
			and paused_route.request_destination("refuel_station_1"),
		"Route may be planned while the player has paused")
	var paused_route_position: Vector2 = paused_route.state.position_nu
	check(paused_route.advance(1.0) and paused_route.state.position_nu == paused_route_position,
		"Planning does not move a paused fleet")
	check(paused_route.set_pause(ExpeditionStateClass.PauseReason.USER, false)
			and paused_route.advance(1.0 / 30.0)
			and paused_route.state.position_nu != paused_route_position,
		"New route starts only after the remaining pause clears")
	var boundary = _simulation()
	boundary.state.fuel = 0.35
	check(boundary.request_destination("refuel_station_1"), "Select course for fuel boundary")
	check(boundary.set_speed(20), "Enable fast-forward")
	for _frame in range(20):
		if not boundary.advance(1.0 / 60.0):
			check(false, "Advance to fuel boundary")
			break
		if boundary.state.travel_state == ExpeditionStateClass.TravelState.STOPPED:
			break
	check(is_equal_approx(boundary.state.fuel, 0.0), "Fuel is clipped at zero")
	check(ExpeditionStateClass.PauseReason.FUEL in boundary.state.pause_reasons,
		"Fuel exhaustion pauses explicitly")
	check(boundary.state.requested_speed == 1, "Fuel interruption reduces requested speed to 1x")
	check(boundary.state.position_nu.distance_to(Vector2.ZERO) <= 3.5001,
		"Fast-forward cannot skip fuel boundary")
	check(not boundary.emitted_boundaries.is_empty()
			and boundary.emitted_boundaries[-1].kind == ExpeditionStateClass.BoundaryKind.FUEL_EMPTY,
		"Fuel boundary emits exactly one typed interruption")
	var arrival = _simulation()
	check(arrival.request_destination("refuel_station_1"), "Select station destination")
	check(arrival.set_speed(20), "Enable fast station travel")
	for _frame in range(1000):
		if not arrival.advance(1.0 / 60.0):
			check(false, "Advance station approach")
			break
		if arrival.state.travel_state == ExpeditionStateClass.TravelState.DOCKED:
			break
	check(arrival.state.travel_state == ExpeditionStateClass.TravelState.DOCKED
			and arrival.state.docked_location_id == "refuel_station_1",
		"Station arrival docks once at physical destination")
	check(arrival.state.position_nu.distance_to(Vector2(240.0, -35.0)) < 0.0001,
		"Arrival clips position to destination")
	check(arrival.request_destination("settlement_1"), "A second course is available after arrival")
	var continuing_position: Vector2 = arrival.state.position_nu
	check(arrival.advance(1.0 / 30.0) and arrival.state.position_nu != continuing_position,
		"Prior arrival history does not suppress later travel")
	var in_flight_snapshot: Dictionary = arrival.state.snapshot()
	var continued = _simulation()
	check(continued.restore(in_flight_snapshot), "Restore an in-flight navigation snapshot")
	check(continued.state.position_nu == arrival.state.position_nu
			and continued.state.destination_location_id == arrival.state.destination_location_id
			and is_equal_approx(continued.state.traveled_days, arrival.state.traveled_days),
		"Continue preserves route position and travel clock")
	var invalid_snapshot := in_flight_snapshot.duplicate(true)
	invalid_snapshot.discovered_location_ids.append("missing_location")
	check(not continued.restore(invalid_snapshot), "Reject saves with unknown location IDs")
	invalid_snapshot = in_flight_snapshot.duplicate(true)
	invalid_snapshot.simulation_seconds += 1.0
	check(not continued.restore(invalid_snapshot), "Reject inconsistent fixed-step simulation clock")
	invalid_snapshot = in_flight_snapshot.duplicate(true)
	invalid_snapshot.seed = "82"
	check(not continued.restore(invalid_snapshot), "Reject a checkpoint from another world seed")
	var engaged = _simulation()
	check(engaged.request_destination("refuel_station_1"), "Set route before engagement")
	engaged.state.travel_state = ExpeditionStateClass.TravelState.ENGAGED
	check(engaged.request_destination("settlement_1")
			and engaged.state.travel_state == ExpeditionStateClass.TravelState.ENGAGED,
		"Combat route changes do not bypass the active threat")
	check(not engaged.set_speed(20), "Threat speed remains capped at 1x")
	check(engaged.cancel_destination()
			and engaged.state.travel_state == ExpeditionStateClass.TravelState.ENGAGED
			and engaged.state.destination_location_id.is_empty(),
		"Canceling route does not cancel combat")
	print("EXPEDITION_NAVIGATION_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
