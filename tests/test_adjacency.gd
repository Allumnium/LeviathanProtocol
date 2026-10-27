extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> Ship:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.CREW_QUARTERS, Vector2i(2, 2))
	for cell in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 3), Vector2i(3, 3)]:
		BUILTINS._add_part(design, ShipPart.Type.MINI_TURRET, cell)
	BUILTINS._add_part(design, ShipPart.Type.RESEARCH_LAB, Vector2i(4, 2))
	return design
func run() -> void:
	var owned := FleetShip.new()
	check(owned.initialize(fixture(), 99, "Crew test"), "Crew constructs as real equipment.")
	var original := owned.get_stats()
	check(AdjacencyRules.recipients(owned.units, 1) == [2, 3, 4], "Automatic choice is stable and limited to three recipients.")
	check(is_equal_approx(original.weapons[0].get_dps(), 1.12) and is_equal_approx(original.weapons[3].get_dps(), 1), "Only the chosen three weapons gain firing rate.")
	var source: ShipPart = owned.units[1].part
	source.crew_manual = true
	source.crew_recipients.assign([Vector2i(1, 1), Vector2i(2, 0)])
	check(AdjacencyRules.recipients(owned.units, 1) == [5, 6], "Manual recipients override automatic choice.")
	check(ScienceRules.snapshot([owned]).total_rp == 20, "Crew adjacency never boosts RP.")
	var reloaded := Ship.new()
	check(reloaded.load_design_data(JSON.parse_string(JSON.stringify(owned.design.to_design_data()))) and reloaded.parts[1].crew_manual \
		and reloaded.parts[1].crew_recipients == source.crew_recipients, "Manual choice survives JSON and physical design reload.")
	var forged := owned.design.to_design_data()
	forged.parts[1].crew_recipients = [[1, 1], [1, 1]]
	check(not Ship.new().load_design_data(forged), "Duplicate recipient metadata is rejected.")
	var shifted := reloaded.to_design_data()
	for tile in shifted.tiles:
		tile[0] += 3
		tile[1] += 4
	for part in shifted.parts:
		part.origin[0] += 3
		part.origin[1] += 4
	check(reloaded.load_design_data(shifted) and reloaded.parts[1].crew_recipients == source.crew_recipients, "Relative links survive whole-ship translation.")
	var ships: Array[FleetShip] = [owned]
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		aliens.append(alien)
	var sim := BattleSimulation.new()
	sim.setup_owned(ships, aliens, 0, 0, 42)
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(100, 0)
	sim._update_analysis(0.01)
	var remaining := sim.player.analysis_remaining
	sim._update_analysis(1.0)
	check(is_equal_approx(remaining - sim.player.analysis_remaining, 1.12), "Crew accelerates lab combat refresh only.")
	sim.player.cooldowns[3] = sim.player.stats.weapons[3].fire_interval_seconds * 0.5
	owned.units[1].hp = 0
	sim._refresh_owned_stats(sim.player)
	check(is_equal_approx(sim.player.cooldowns[3], 0.5), "Source loss removes the rate bonus from an ongoing cooldown, preserving activation progress.")
	remaining = sim.player.analysis_remaining
	sim._update_analysis(1.0)
	check(is_equal_approx(remaining - sim.player.analysis_remaining, 1), "Source destruction removes analysis rate immediately.")
	check(is_equal_approx(owned.get_stats().weapons[3].get_dps(), 1), "Source destruction removes weapon rate.")
	owned.repair()
	check(AdjacencyRules.recipients(owned.units, 1) == [5, 6], "Reconstruction restores exactly the selected links.")
	_test_geometry_and_stacking()
	_test_shield_timing()
	await _test_editor()
	print("Adjacency tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_geometry_and_stacking() -> void:
	var crew := ShipPart.new(ShipPart.Type.CREW_QUARTERS, 3, Vector2i.ZERO, [Vector2i.ZERO, Vector2i.RIGHT], ShipPartStats.new())
	var engine := ShipPart.new(ShipPart.Type.THRUSTER, 0, Vector2i(0, 1), [Vector2i.ZERO, Vector2i.RIGHT], ShipPartStats.new(40, 0, 0, 10))
	var duplicate := ShipPart.new(ShipPart.Type.CREW_QUARTERS, 3, Vector2i(0, 2), [Vector2i.ZERO, Vector2i.RIGHT], ShipPartStats.new())
	var diagonal := ShipPart.new(ShipPart.Type.LASER, 0, Vector2i(2, -1), [Vector2i.ZERO], ShipPartStats.with_weapon("Fixture", 0, 1, 1, 1))
	var units: Array[Dictionary] = []
	for part in [crew, engine, duplicate, diagonal]:
		units.append({"part": part, "cells": part.get_occupied_cells(), "hp": 1.0})
	var stats := ShipStats.from_units(units, Vector2.ZERO)
	check(not AdjacencyRules.touches(crew, diagonal), "Diagonal corners are not adjacent.")
	check(AdjacencyRules.rates(units) == {1: 1.12}, "Repeated touching edges and identical Crew sources do not stack.")
	check(is_equal_approx(stats.engine_rate, 1.12) and is_equal_approx(stats.shield_recharge, 44.8), "Crew improves engine response and shield recharge without capacity changes.")
	var baseline := ShipStats.new()
	baseline.thrust = stats.thrust
	baseline.weight = stats.weight
	check(is_equal_approx(stats.top_speed, baseline.top_speed), "Crew does not change mass-sensitive top speed.")
	check(is_equal_approx(stats.acceleration, baseline.acceleration * 1.12) and is_equal_approx(stats.turn_rate, baseline.turn_rate * 1.12), "Engine rate reaches acceleration and turning.")
	check(is_equal_approx(AdjacencyRules.ordinary_rate({"crew": 0.12, "energy": 0.1, "future": 0.2}), 1.3), "Different named ordinary bonuses add with a 30% ceiling.")
	units[0].hp = 0
	check(AdjacencyRules.rates(units) == {1: 1.12}, "Surviving strongest source persists when another source dies.")
	units[2].hp = 0
	check(AdjacencyRules.rates(units).is_empty(), "Last source destruction removes links immediately.")
	units[0].hp = 1
	units[1].hp = 0
	check(AdjacencyRules.rates(units).is_empty(), "Destroyed recipients receive no bonus.")

func _test_editor() -> void:
	var state = root.get_node("GameState")
	state.start_new_run(1, 42)
	state.ship.load_design_data(fixture().to_design_data())
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	await process_frame
	var editor: Control = map.find_child("BuildTilemapArea", true, false)
	check(editor != null, "Builder exposes Crew link controls.")
	if editor != null:
		editor._refresh_assembly_menu()
		check(editor.crew_links_menu.item_count == 1, "Crew sources appear in visible link selection.")
		editor._crew_link_action(1, 102)
		check(state.ship.parts[1].crew_manual and state.ship.parts[1].crew_recipients.size() == 2, "Clicking an automatic recipient switches to an adjustable manual set.")
		editor._undo()
		check(not state.ship.parts[1].crew_manual, "Undo restores automatic choice.")
		editor._redo()
		check(state.ship.parts[1].crew_manual, "Redo restores selected recipients.")
		state.ship.parts[1].crew_recipients.append(Vector2i(90, 90))
		editor._crew_link_action(1, 105)
		check(state.ship.parts[1].crew_recipients.size() == 3 and not state.ship.parts[1].crew_recipients.has(Vector2i(90, 90)), "Removed targets do not prevent selecting a replacement.")
		state.credits = 100000
		check(state.purchase_ship(state.ship, "Crew test"), "Configured Crew hull constructs through run authorization.")
		check(state.save_run_checkpoint() and state.load_run_checkpoint() and state.fleet.back().design.parts[1].crew_manual \
			and state.fleet.back().design.parts[1].crew_recipients.size() == 3, "Physical selection survives a full campaign checkpoint reload.")
	map.queue_free()
	await process_frame

func _test_shield_timing() -> void:
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.SHIELD, Vector2i(2, 0))
	BUILTINS._add_part(design, ShipPart.Type.CREW_QUARTERS, Vector2i(2, 3))
	BUILTINS._add_part(design, ShipPart.Type.MINI_TURRET, Vector2i(0, 2))
	var owned := FleetShip.new()
	owned.initialize(design, 100, "Shield fixture")
	var ships: Array[FleetShip] = [owned]
	var aliens: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(1, 1.0, 42):
		aliens.append(alien)
	var sim := BattleSimulation.new()
	sim.setup_owned(ships, aliens, 0, 0, 42)
	sim.player.shields = 0
	sim.player.since_damage = 2.4
	sim._update_ship(sim.player, 0.05, false)
	check(is_zero_approx(sim.player.shields), "Crew cannot shorten the shield damage-interruption delay.")
	sim.player.since_damage = 5
	sim._update_ship(sim.player, 0.05, false)
	check(is_equal_approx(sim.player.shields, sim.player.stats.shields * 0.04 * 1.12 * 0.05), "Combat recharge uses the boosted rate after the unchanged delay.")
