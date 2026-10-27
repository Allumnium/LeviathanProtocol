extends SceneTree

var failures := 0
const BUILTINS = preload("res://scripts/builtin_ships.gd")

func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func hull(id := 100) -> FleetShip:
	var blueprint := Ship.new()
	BUILTINS._add_part(blueprint, ShipPart.Type.COMMAND_CENTER, Vector2i(20, 20))
	var owned := FleetShip.new()
	owned.initialize(blueprint, id, "Passenger policy fixture")
	return owned
func add(owned: FleetShip, type: int, origin: Vector2i) -> int:
	# Detached policy fixtures use the actual future recipes. They do not enable
	# construction, archived blueprint loading, research or passenger income.
	var definition := GameDefinitions.equipment(type)
	var cells := MaterialRecipe.parse(definition.recipe)
	var offsets: Array[Vector2i] = []
	for cell: Vector2i in cells:
		offsets.append(cell)
	var part := ShipPart.new(type, ShipPart.Category.CORE, origin, offsets, ShipPartStats.new())
	owned.units.append({"part": part, "cells": part.get_occupied_cells(), "hp": float(cells.size()), "max_hp": float(cells.size())})
	return owned.units.size() - 1
func loose(owned: FleetShip, cell: Vector2i) -> int:
	owned.units.append({"part": null, "cells": [cell], "hp": 1.0, "max_hp": 1.0})
	return owned.units.size() - 1
func run() -> void:
	_test_capacity_and_identity()
	_test_luxury()
	_test_exterior()
	_test_validation()
	_test_checkpoint_boundary()
	print("Passenger state tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
func _test_capacity_and_identity() -> void:
	var owned := hull()
	add(owned, ShipPart.Type.PASSENGER_CABIN, Vector2i(-2, 0))
	add(owned, ShipPart.Type.LUXURY_SUITES, Vector2i(3, 0))
	var fleet: Array[FleetShip] = [owned]
	var economy := PassengerRules.register_components({"example_hold": {"quantity": 7}}, fleet)
	var cabin := PassengerRules.component_id(owned.id, 1)
	var suite := PassengerRules.component_id(owned.id, 2)
	check(PassengerRules.valid(economy, fleet) and economy.example_hold.quantity == 7, "Passenger namespace preserves unrelated economic state.")
	check(economy.passengers.components[cabin].capacity == 4 and economy.passengers.components[suite].capacity == 4 \
		and economy.passengers.components[cabin].boarded_luxury == 1 and economy.passengers.components[suite].boarded_luxury == 2, "Both accommodations have four empty places with their own base luxury.")
	economy.passengers.components[cabin].occupied = 3
	economy.passengers.components[suite].occupied = 2
	var saved: Dictionary = JSON.parse_string(JSON.stringify(economy))
	check(PassengerRules.valid(saved, fleet), "Aggregate occupancy and stable component identities round-trip through JSON.")
	owned.display_name = "Renamed and reassigned"
	owned.slot_role = "civic"
	owned.in_reserve = true
	owned.formation = Vector2(9, 7)
	fleet.reverse()
	var rows := PassengerRules.snapshot(fleet, saved)
	check(rows[0].id == cabin and rows[0].occupied == 3 and rows[0].available == 1 and rows[1].id == suite and rows[1].occupied == 2, "Name, role, reserve and formation changes never move occupancy to another component.")
	var copy := hull(101)
	add(copy, ShipPart.Type.PASSENGER_CABIN, Vector2i(-2, 0))
	fleet.append(copy)
	var registered := PassengerRules.register_components(saved, fleet)
	var before := registered.duplicate(true)
	var preview := PassengerRules.snapshot(fleet, registered)
	preview[0].occupied = 0
	check(registered == before and PassengerRules.register_components(registered, fleet) == before, "Preview and repeated component registration never board, disembark or mutate saved occupancy.")
	check(registered.passengers.components[PassengerRules.component_id(101, 1)].occupied == 0 \
		and registered.passengers.components[cabin].occupied == 3, "An identical physical copy starts empty under its own ship ID.")
	owned.units[1].hp = 0.1
	check(PassengerRules.snapshot(fleet, registered)[0].capacity == 4 and PassengerRules.snapshot(fleet, registered)[0].occupied == 3, "Partial damage does not reduce atomic capacity or occupants.")
	owned.units[1].hp = 0
	check(PassengerRules.snapshot(fleet, registered)[0].capacity == 0 and not PassengerRules.valid(registered, fleet), "Destroyed occupied accommodation requires explicit loss settlement before saving.")
	registered.passengers.components[cabin].occupied = 0
	owned.repair()
	check(PassengerRules.valid(registered, fleet) and PassengerRules.snapshot(fleet, registered)[0].occupied == 0, "Reconstruction restores empty capacity without manufacturing passengers.")
	owned.units[owned.core_index].hp = 0
	check(not PassengerRules.valid(registered, fleet), "Host destruction cannot silently discard its remaining occupied suite.")
	registered.passengers.components[suite].occupied = 0
	check(PassengerRules.valid(registered, fleet), "Explicitly settled empty records remain valid on a dead host.")
	var no_ships: Array[FleetShip] = []
	var lost := {"passengers": {"version": 1, "components": {cabin: registered.passengers.components[cabin]}}}
	check(PassengerRules.valid(lost, no_ships), "Empty historical component records can outlive removed hulls.")
	lost.passengers.components[cabin].occupied = 1
	check(not PassengerRules.valid(lost, no_ships), "An occupied orphan cannot be silently removed from its hull.")
func _test_luxury() -> void:
	var owned := hull()
	add(owned, ShipPart.Type.PASSENGER_CABIN, Vector2i(-2, 0))
	add(owned, ShipPart.Type.LUXURY_SUITES, Vector2i(3, 0))
	var deck := add(owned, ShipPart.Type.OBSERVATION_DECK, Vector2i.ZERO)
	check(PassengerRules.observation_recipients(owned, deck) == [1, 2] and PassengerRules.luxury_levels(owned) == {1: 2, 2: 3}, "An exposed deck improves two adjacent accommodations, including an intact severed section.")
	var fleet: Array[FleetShip] = [owned]
	var economy := PassengerRules.register_components({}, fleet)
	var cabin := PassengerRules.component_id(owned.id, 1)
	economy.passengers.components[cabin].occupied = 4
	owned.units[deck].hp = 0.1
	check(PassengerRules.luxury_levels(owned)[1] == 2, "Partial source damage preserves luxury.")
	owned.units[deck].hp = 0
	var rows := PassengerRules.snapshot(fleet, economy)
	check(rows[0].luxury == 1 and rows[0].boarded_luxury == 2 and rows[0].occupied == 4, "Loss of a luxury source changes current luxury without rewriting boarded luxury or occupancy.")
	owned.units[deck].hp = owned.units[deck].max_hp
	for reflected in [false, true]:
		for unit in owned.units:
			var part: ShipPart = unit.part
			if part == null:
				continue
			part.origin = Vector2i(-part.origin.x, part.origin.y) if reflected else Vector2i(-part.origin.y, part.origin.x)
			var offsets: Array[Vector2i] = []
			for cell in part.cell_offsets:
				offsets.append(Vector2i(-cell.x, cell.y) if reflected else Vector2i(-cell.y, cell.x))
			part.cell_offsets.assign(offsets)
			unit.cells = part.get_occupied_cells()
		check(PassengerRules.luxury_levels(owned) == {1: 2, 2: 3} and PassengerRules.valid(economy, fleet), "Rotating/reflection preserves actual adjacency, exterior eligibility and occupied component identity.")
	add(owned, ShipPart.Type.GRAND_PROMENADE, Vector2i(10, 0))
	add(owned, ShipPart.Type.GRAND_PROMENADE, Vector2i(10, 6))
	check(PassengerRules.luxury_levels(owned) == {1: 3, 2: 3}, "Promenade is host-wide, identical sources do not stack and luxury caps at three.")
	var duplicate := hull()
	add(duplicate, ShipPart.Type.PASSENGER_CABIN, Vector2i.ZERO)
	add(duplicate, ShipPart.Type.OBSERVATION_DECK, Vector2i(-1, -2))
	add(duplicate, ShipPart.Type.OBSERVATION_DECK, Vector2i(0, 2))
	add(duplicate, ShipPart.Type.CREW_QUARTERS, Vector2i(2, 0))
	check(PassengerRules.luxury_levels(duplicate)[1] == 2, "Repeated shared edges/decks do not multiply luxury, and Crew never boosts it.")
	var bounded := hull()
	var source := add(bounded, ShipPart.Type.OBSERVATION_DECK, Vector2i.ZERO)
	add(bounded, ShipPart.Type.PASSENGER_CABIN, Vector2i(-2, 0))
	add(bounded, ShipPart.Type.PASSENGER_CABIN, Vector2i(3, 0))
	add(bounded, ShipPart.Type.PASSENGER_CABIN, Vector2i(0, -2))
	check(PassengerRules.observation_recipients(bounded, source) == [2, 3] and PassengerRules.luxury_levels(bounded)[4] == 1, "Deck selection uses stable component order and a strict two-recipient limit.")
	var other := hull(102)
	add(other, ShipPart.Type.PASSENGER_CABIN, Vector2i.ZERO)
	check(PassengerRules.luxury_levels(other)[1] == 1, "Promenade and deck effects never cross between hulls.")
func _test_exterior() -> void:
	var owned := hull()
	var deck := add(owned, ShipPart.Type.OBSERVATION_DECK, Vector2i(1, 1))
	var cabin := add(owned, ShipPart.Type.PASSENGER_CABIN, Vector2i(4, 1))
	var opening := -1
	for x in range(7):
		for y in range(6):
			if x in [0, 6] or y in [0, 5]:
				var index := loose(owned, Vector2i(x, y))
				if x == 6 and y == 3:
					opening = index
	check(not PassengerRules.exterior_edge(owned, owned.units[deck].part) and PassengerRules.luxury_levels(owned)[cabin] == 1, "An enclosed courtyard does not satisfy the deck exterior-edge requirement.")
	owned.units[opening].hp = 0
	check(PassengerRules.exterior_edge(owned, owned.units[deck].part) and PassengerRules.luxury_levels(owned)[cabin] == 2, "Opening a real exterior path updates deck operation immediately.")
	loose(owned, Vector2i(100000, 100000))
	check(PassengerRules.exterior_edge(owned, owned.units[deck].part), "Sparse distant material does not change local exterior connectivity.")
func _test_validation() -> void:
	var owned := hull()
	add(owned, ShipPart.Type.PASSENGER_CABIN, Vector2i.ZERO)
	var fleet: Array[FleetShip] = [owned]
	var original := PassengerRules.register_components({}, fleet)
	var id := PassengerRules.component_id(owned.id, 1)
	for change in [{"occupied": -1}, {"occupied": 5}, {"occupied": 1.5}, {"capacity": 5}, {"boarded_luxury": 0},
		{"boarded_luxury": 4}, {"ship_id": 999}, {"unit_index": 0}, {"equipment_id": "luxury_suites"}, {"people": ["individual"]}]:
		var forged := original.duplicate(true)
		for field in change:
			forged.passengers.components[id][field] = change[field]
		check(not PassengerRules.valid(forged, fleet), "Malformed/fabricated passenger records fail closed: %s" % change)
	var forged := original.duplicate(true)
	forged.passengers.version = 99
	check(not PassengerRules.valid(forged, fleet), "Unknown passenger state versions are rejected.")
func _test_checkpoint_boundary() -> void:
	var state = root.get_node("GameState")
	state.run_save_path = "user://passengers/run.json"
	check(state.start_new_run(1, 42) and state.passenger_manifest().is_empty(), "Existing live starters remain compatible and have no imaginary accommodation.")
	var before: Dictionary = state.economy_state.duplicate(true)
	state.economy_state["passengers"] = {"version": 1, "components": {}}
	check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.economy_state.passengers.components.is_empty(), "The additive empty namespace persists through a real campaign checkpoint.")
	var forged := RunCheckpoint.capture(state)
	var id := PassengerRules.component_id(state.fleet[0].id, 0)
	forged.economy.passengers.components[id] = {"ship_id": state.fleet[0].id, "unit_index": 0, "equipment_id": "passenger_cabin", "capacity": 4, "occupied": 1, "boarded_luxury": 1}
	check(not RunCheckpoint.valid(forged), "Save validation rejects a non-accommodation unit impersonating an occupied cabin.")
	state.economy_state = before
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Older saves without passenger state remain valid.")
	check(not state.is_equipment_available(ShipPart.Type.PASSENGER_CABIN) and not state.purchase_research("civil_hospitality"), "Passenger construction/research stays gated until boarding and losses work.")
