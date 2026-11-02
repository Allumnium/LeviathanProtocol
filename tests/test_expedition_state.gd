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


func run() -> void:
	var simulation = ExpeditionSimulationClass.new()
	check(simulation.configure(51), "Expedition fixture loads")
	if simulation.state == null:
		quit(1)
		return
	var acts := {}
	for location: Dictionary in simulation.locations.values():
		acts[int(location.act)] = true
	check(simulation.locations.size() == 11 and acts.size() == 3, "Fixture includes all three act regions")
	check(simulation.locations.has("start_station") and simulation.locations.start_station.accessible,
		"Starting station is accessible")
	check(simulation.locations.refuel_station_1.services.has("shipyard")
			and simulation.locations.refuel_station_1.services.has("refuel"),
		"Initial refueling shipyard is usable")
	check(not simulation.locations.act_2_gate.accessible and not simulation.locations.act_3_gate.accessible,
		"Later act gates are explicit and locked")
	check(simulation.locations.has("derelict_1") and simulation.locations.derelict_1.poi_type == "derelict",
		"Fixture has story-neutral optional POI")
	var snapshot: Dictionary = simulation.state.snapshot()
	check(ExpeditionStateClass.valid(snapshot), "Initial state validates")
	var parsed_snapshot := JSON.new()
	parsed_snapshot.parse(JSON.stringify(snapshot))
	check(ExpeditionStateClass.valid(parsed_snapshot.data),
			"Serialized expedition state remains valid after JSON restores integer clocks")
	var restored = ExpeditionStateClass.new()
	check(restored.restore(snapshot) and SaveValidation.same(snapshot, restored.snapshot()),
		"State roundtrips without loss")
	var malformed := snapshot.duplicate(true)
	malformed.fuel = malformed.fuel_capacity + 1
	check(not ExpeditionStateClass.valid(malformed), "Reject over-capacity fuel")
	malformed = snapshot.duplicate(true)
	malformed.research_progress = {"invalid": -0.5}
	check(not ExpeditionStateClass.valid(malformed), "Reject negative research progress")
	malformed = snapshot.duplicate(true)
	malformed.pause_reasons = [ExpeditionStateClass.PauseReason.USER, ExpeditionStateClass.PauseReason.USER]
	check(not ExpeditionStateClass.valid(malformed), "Reject duplicate pause reasons")
	malformed = snapshot.duplicate(true)
	malformed.visited_location_ids = ["unknown"]
	check(not ExpeditionStateClass.valid(malformed), "Reject visits without discovery")
	var locations_data := {"version": 1, "locations": simulation.locations.values()}
	var duplicate_locations := locations_data.duplicate(true)
	duplicate_locations.locations.append(duplicate_locations.locations[0].duplicate(true))
	check(not ExpeditionStateClass.valid_locations(duplicate_locations), "Reject duplicate location IDs")
	check(ExpeditionStateClass.location_by_id(simulation.locations.values(), "refuel_station_1").id == "refuel_station_1",
		"Stable location IDs resolve")
	var start_position := Vector2(simulation.locations.start_station.position[0],
			simulation.locations.start_station.position[1])
	var refuel_position := Vector2(simulation.locations.refuel_station_1.position[0],
			simulation.locations.refuel_station_1.position[1])
	check(start_position.distance_to(refuel_position) < 1000.0,
		"Initial refueling post is within full-tank range")
	print("EXPEDITION_STATE_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
