extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var design := Ship.new()
	preload("res://scripts/builtin_ships.gd")._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	for index in range(8):
		design.set_tile_at(Vector2i(100 + index, 100), ShipPart.Category.DEFENSE)
	_check(FleetRules.design_capacity(design) == 3, "Twelve actual cells cost three, regardless of bounding rectangle or connectivity.")
	design.set_tile_at(Vector2i(200, 200), ShipPart.Category.DEFENSE)
	_check(FleetRules.design_capacity(design) == 4, "Thirteenth occupied cell increases cost by one.")
	var owned := FleetShip.new()
	owned.initialize(design, 1, "Capacity fixture")
	_check(FleetRules.ship_capacity(owned) == 4, "Assembled and loose cells both consume capacity.")
	owned.units[owned.units.size() - 1].hp = 0
	_check(FleetRules.ship_capacity(owned) == 3, "Destroyed material cells no longer count as occupied.")
	owned.units[owned.core_index].hp *= 0.5
	_check(FleetRules.ship_capacity(owned) == 3, "Partial component damage retains its full occupied footprint.")
	owned.repair()
	_check(FleetRules.ship_capacity(owned) == 4, "Reconstruction restores occupied-cell cost.")
	# Policy fixtures only: future equipment remains unavailable for purchase.
	for rank in range(1, 4):
		var offsets: Array[Vector2i] = []
		for index in range(3 + 3 * rank):
			offsets.append(Vector2i(index, 0))
		var lab := ShipPart.new(ShipPart.Type.RESEARCH_LAB, ShipPart.Category.CORE, Vector2i.ZERO, offsets, ShipPartStats.new())
		_check(FleetRules.lab_level(lab) == rank, "Lab rank derives from its documented footprint.")
		owned.units.append({"part": lab, "hp": 1.0, "cells": []})
		_check(FleetRules.ship_capacity(owned) == 4 + rank, "Each active lab adds its level to physical hull cost.")
		owned.units.back().hp = 0
		_check(FleetRules.ship_capacity(owned) == 4, "A destroyed lab contributes no active level surcharge.")
		owned.units.pop_back()
	owned.units[owned.core_index].hp = 0
	_check(FleetRules.ship_capacity(owned) == 0, "Destroyed hulls consume no capacity.")
	for act in range(1, 4):
		_check(FleetRules.capacity_for_act(act) == [30, 42, 54][act - 1], "Each act has its intended capacity.")

	var state := root.get_node("GameState")
	state.run_save_path = "user://capacity/run.json"
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 42), "Start isolated capacity campaign.")
	var drone := preload("res://scripts/builtin_ships.gd").drone()
	var per_copy := FleetRules.design_capacity(drone)
	_check(state.used_deployment_capacity() == per_copy * state.fleet.size() and state.can_deploy(), "Starter copies each consume capacity and fit Act I.")
	state.credits = 100000
	while state.used_deployment_capacity() + per_copy <= 30:
		if not state.purchase_ship(drone, "Drone"):
			_check(false, "Construct additional copies in the existing family.")
			break
	_check(state.can_deploy(), "Fleet at or below capacity can depart.")
	_check(state.purchase_ship(drone, "Drone"), "Owned construction is allowed beyond deployment capacity.")
	var excess: FleetShip = state.fleet.back()
	_check(not state.can_deploy() and state.deployment_error().contains("Deployment capacity"), "Over-capacity fleet cannot deploy and receives an actionable reason.")
	var destination: int = state.get_reachable_nodes(0)[0]
	_check(not state.set_destination(destination) and not state.battle_pending, "Direct departure cannot bypass the capacity rule.")
	_check(state.save_run_checkpoint() and state.load_run_checkpoint() and not state.can_deploy(), "Over-capacity owned rosters survive reload without gaining permission to depart.")
	excess = state.fleet.back()
	var excess_id := excess.id
	var map: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	await process_frame
	await process_frame
	_check(map.deploy_button.disabled and map.deploy_button.tooltip_text.contains("Deployment capacity"), "Fleet UI explains over-capacity departure lock.")
	_check(state.set_ship_reserve(excess, true) and state.can_deploy(), "Reserving excess copies immediately restores legal deployment.")
	_check(not map.deploy_button.disabled and map.deploy_button.tooltip_text.is_empty(), "Reserve changes immediately refresh deployment control.")
	map.queue_free()
	current_scene = null
	await process_frame
	var used: int = state.used_deployment_capacity()
	_check(state.load_run_checkpoint() and state.used_deployment_capacity() == used, "Capacity recomputes from persisted physical ships and reserve assignments.")
	_check(state.set_destination(destination), "Legal fleet creates an attempt.")
	var progress: Dictionary = state.encounter_progress[str(destination)]
	_check(not progress.ship_ids.has(excess_id), "Reserved copies contribute neither capacity nor battle participants.")
	_check(state.cancel_battle(), "Cancel capacity fixture battle.")
	var alternate := preload("res://scripts/builtin_ships.gd").drone()
	alternate.set_tile_at(Vector2i(8, 0), ShipPart.Category.DEFENSE)
	_check(state.assign_fleet_design(0, "Alternate", alternate) and state.used_deployment_capacity() == 0,
		"Copies in an inactive family contribute no capacity.")
	_check(state.assign_fleet_design(0, "Drone", drone) and state.used_deployment_capacity() == used,
		"Restoring a family charges all its deployed physical copies again.")
	for node in state.campaign_dag.nodes:
		if node.kind == "boss":
			state.current_node_id = int(node.id)
			_check(state.deployment_capacity() == FleetRules.capacity_for_act(mini(3, int(node.act) + 1)), "Secured act bosses raise the capacity using campaign progression.")
	_check(state.start_new_run(GameState.Difficulty.MEDIUM, 42, false), "Legacy map remains available.")
	state.credits = 100000
	for index in range(5):
		_check(state.purchase_ship(drone, "Drone"), "Legacy construction remains compatible.")
	_check(state.used_deployment_capacity() > 30 and state.can_deploy(), "Legacy map compatibility retains unrestricted deployment.")
	print("Fleet capacity tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
