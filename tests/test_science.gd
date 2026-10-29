extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _design(rank := 1) -> Ship:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.RESEARCH_LAB, Vector2i(2, 0), rank)
	BUILTINS._add_part(design, ShipPart.Type.MINI_TURRET, Vector2i(0, 2))
	return design

func _owned(rank := 1, id := 1) -> FleetShip:
	var owned := FleetShip.new()
	owned.initialize(_design(rank), id, "Science fixture")
	return owned

func _hook(owned: FleetShip, type: int, origin: Vector2i) -> void:
	# Policy hook fixture only; future support equipment stays unavailable.
	var part := ShipPart.new(type, ShipPart.Category.SPECIAL, origin, [Vector2i.ZERO], ShipPartStats.new())
	owned.units.append({"part": part, "hp": 1.0, "cells": part.get_occupied_cells()})

func _run() -> void:
	for rank in range(1, 4):
		var owned := _owned(rank)
		var lab: ShipPart = owned.units[ScienceRules.active_lab(owned)].part
		_check(lab.rank == rank and lab.cell_offsets.size() == [6, 9, 12][rank - 1], "Physical lab rank has the documented footprint.")
		var copy := Ship.new()
		_check(copy.load_design_data(owned.design.to_design_data()) and copy.parts[1].rank == rank, "Lab rank round-trips without changing its physical recipe.")
		_check(ScienceRules.snapshot([owned]).total_rp == 20 * rank, "Operational labs produce 20/40/60 RP.")
		var science_entry: Dictionary = ScienceRules.snapshot([owned]).labs[0]
		_check(science_entry.rank == rank, "Snapshot records the actual active physical rank.")
		if rank == 3:
			_hook(owned, ShipPart.Type.ANALYSIS_ARRAY, Vector2i(1, 0))
			_hook(owned, ShipPart.Type.ANALYSIS_ARRAY, Vector2i(1, 1))
			_check(ScienceRules.snapshot([owned]).total_rp == 75, "Repeated Analysis sources use the strongest +25% once.")
			_hook(owned, ShipPart.Type.QUANTUM_OBSERVATORY, Vector2i(1, 2))
			_hook(owned, ShipPart.Type.CREW_QUARTERS, Vector2i(6, 0))
			_check(ScienceRules.snapshot([owned]).total_rp == 90, "Separate Observatory bonus reaches 90; Crew never increases RP.")
			owned.units.back().hp = 0
			owned.units[owned.units.size() - 2].hp = 0
			_check(ScienceRules.snapshot([owned]).total_rp == 75, "Destroyed support sources contribute nothing to a new snapshot.")
	var multiple := _design(1)
	BUILTINS._add_part(multiple, ShipPart.Type.RESEARCH_LAB, Vector2i(8, 0), 3)
	var mixed := FleetShip.new()
	mixed.initialize(multiple, 10, "Two labs")
	_check(ScienceRules.snapshot([mixed]).total_rp == 80 and FleetRules.design_capacity(multiple) == 2 + ceili(multiple.tiles.size() / 12.0) + 3,
		"Every living lab contributes to production; hull capacity retains its rank surcharge.")
	_check(ScienceRules.production_rate(ScienceRules.snapshot([mixed])) == 2.5, "Two living labs on one hull produce two RP per day plus the baseline.")
	_check(ScienceRules.matches_deployment(ScienceRules.snapshot([mixed], true), [RunCheckpoint.ship_entry(mixed)]), "Legacy highest-lab snapshots still validate against old physical deployments.")
	mixed.units[ScienceRules.active_lab(mixed)].hp = 0
	_check(ScienceRules.snapshot([mixed]).total_rp == 20, "A surviving lower lab can operate after the higher lab is destroyed.")
	_test_analysis()
	await _test_persistence()
	print("Science tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_analysis() -> void:
	var ships: Array[FleetShip] = [_owned(1, 1), _owned(1, 2)]
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		aliens.append(alien)
	var sim := BattleSimulation.new()
	_check(sim.setup_owned(ships, aliens, 0, 0, 42), "Lab battle initializes.")
	for member in sim.players:
		member.position = Vector2.ZERO
	var target := sim.aliens[0]
	target.position = Vector2(100, 0)
	target.shields = 0
	target.integrity = 100
	sim._update_analysis(0.01)
	sim._damage(target, 10, sim.player.position, sim.player, "Fixture")
	_check(is_equal_approx(target.integrity, 89.5), "Visible target analysis grants +5%, strongest lab source only.")
	var remaining := sim.player.analysis_remaining
	sim._update_analysis(1)
	_check(is_equal_approx(sim.player.analysis_remaining, remaining - 1), "Combat analysis uses the simulation clock and an eight-second refresh.")
	target.position = Vector2(1000, 0)
	sim._damage(target, 10, sim.player.position, sim.player, "Fixture")
	_check(is_equal_approx(target.integrity, 79.5), "Analysis cannot amplify a target outside team sight.")
	target.position = Vector2(100, 0)
	for owned in ships:
		owned.units[ScienceRules.active_lab(owned)].hp = 0
	sim._damage(target, 10, sim.player.position, sim.player, "Fixture")
	_check(is_equal_approx(target.integrity, 69.5), "Destroyed labs immediately lose their combat analysis effect.")

func _test_persistence() -> void:
	var state := root.get_node("GameState")
	state.run_save_path = "user://science/run.json"
	_check(state.start_new_run(1, 42), "Start science campaign.")
	_check(state.is_equipment_available(ShipPart.Type.RESEARCH_LAB) and not state.is_equipment_available(ShipPart.Type.RESEARCH_LAB, 2), "Foundation grants lab I, not larger physical ranks.")
	state.credits = 100000
	_check(state.purchase_ship(_design(), "Scientist"), "A regular-slot science hull constructs at normal cost.")
	var reserve: FleetShip = state.fleet.back()
	_check(state.set_ship_reserve(reserve, true), "Reserve science fixture.")
	_check(state.purchase_ship(_design(), "Scientist"), "Another physical scientist uses the same family.")
	_check(ScienceRules.snapshot(state.get_deployed_fleet()).total_rp == 20, "Owned reserves contribute zero RP.")
	var destination: int = state.get_reachable_nodes(0)[0]
	var expected: float = 1.5 * state.research_travel_time(0, destination)
	_check(state.set_destination(destination), "Science deployment freezes a snapshot.")
	var snapshot: Dictionary = state.encounter_progress[str(destination)].science_snapshot.duplicate(true)
	_check(snapshot.total_rp == 20 and snapshot.labs.size() == 1, "Snapshot contains exactly the deployed operational lab.")
	_check(state.load_run_checkpoint() and state.encounter_progress[str(destination)].science_snapshot == JSON.parse_string(JSON.stringify(snapshot)), "Snapshot survives pending checkpoint reload.")
	var forged := RunCheckpoint.capture(state)
	forged.encounter_progress[str(destination)].erase("science_snapshot")
	_check(not RunCheckpoint.valid(forged), "A lab-bearing deployment cannot discard its frozen snapshot.")
	forged = RunCheckpoint.capture(state)
	forged.encounter_progress[str(destination)].science_snapshot.total_rp = 999
	_check(not RunCheckpoint.valid(forged), "Reject an altered snapshot total.")
	forged = RunCheckpoint.capture(state)
	forged.encounter_progress[str(destination)].science_snapshot.labs[0].rank = 3
	forged.encounter_progress[str(destination)].science_snapshot.labs[0].rp = 60
	forged.encounter_progress[str(destination)].science_snapshot.total_rp = 60
	_check(not RunCheckpoint.valid(forged), "Snapshot rank must match the initial physical deployment, not only its own arithmetic.")
	var scientist: FleetShip
	for owned: FleetShip in state.get_deployed_fleet():
		if ScienceRules.active_lab(owned) >= 0:
			scientist = owned
	scientist.units[ScienceRules.active_lab(scientist)].hp = 0
	var blocker := FileAccess.open("user://science/blocker", FileAccess.WRITE)
	blocker.store_string("file, not a save directory")
	blocker.close()
	var save_path: String = state.run_save_path
	state.run_save_path = "user://science/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	_check(not state.complete_battle() and state.research_points == 0 and state.battle_pending, "A failed save grants no RP and leaves the attempt retryable.")
	Engine.print_error_messages = printed
	state.run_save_path = save_path
	scientist.units[scientist.core_index].hp = 0
	_check(ScienceRules.active_lab(scientist) == -1, "A destroyed host has no operational lab.")
	_check(state.complete_battle() and state.research_points == expected, "Victory pays the starting lab snapshot even after lab and host destruction.")
	Engine.print_error_messages = false
	_check(not state.complete_battle() and state.research_points == expected, "Closed objective victory cannot award the same RP twice.")
	Engine.print_error_messages = printed
	_check(state.load_run_checkpoint() and state.research_points == expected, "RP and ledger settle durably together.")
	_check(state.start_new_run(1, 42), "Start withdrawal fixture.")
	state.credits = 100000
	_check(state.dispatch_arrival() and state.research_points == 0, "Noncombat arrivals grant no RP.")
	_check(state.purchase_ship(_design(), "Scientist") and state.set_destination(state.get_reachable_nodes(0)[0]), "Create withdrawal snapshot.")
	_check(state.commit_field_pickup("rock", [1, 0, 0, 0], {}) and state.research_points == 0, "Rock/field pickups award no RP.")
	_check(state.cancel_battle() and state.research_points == 0, "Withdrawal pays no RP.")
	_check(state.set_destination(state.get_reachable_nodes(0)[0]) and state.cancel_battle(-1, true) and state.research_points == 0, "Failure pays no RP.")
