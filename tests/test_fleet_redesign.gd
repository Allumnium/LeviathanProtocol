extends SceneTree

var checks := 0
var failures := 0
var state: Node
var fleet_completed := false
var battle_completed := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func settle() -> void:
	for frame in range(5):
		await process_frame

func pointer(point: Vector2, pressed: bool, alt := false, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.alt_pressed = alt
	event.shift_pressed = shift
	root.push_input(event, true)
	await settle()

func click(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(control)
	await settle()
	check(control.is_visible_in_tree(), "Pointer action is visible: " + control.name)
	var point := control.get_global_rect().get_center()
	await pointer(point, true)
	await pointer(point, false)

func drag(battle: Control, actor: BattleSimulation.Combatant, offset: Vector2, alt := false, shift := false) -> void:
	var point: Vector2 = battle.visuals.world_transform() * actor.position
	await pointer(point, true, alt, MOUSE_BUTTON_LEFT, shift)
	var motion := InputEventMouseMotion.new()
	motion.position = point + offset * battle.visuals.camera_zoom
	motion.relative = offset * battle.visuals.camera_zoom
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await settle()
	await pointer(motion.position, false, alt)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://" + name + ".png") == OK, "Capture " + name)

func start() -> void:
	check(state.start_new_run(1, 8302), "Start isolated redesign fixture")
	state.pending_intro = false

func fleet_checks() -> void:
	start()
	var ship_id: int = state.fleet[3].id
	var damaged: Dictionary = state.hangar_snapshot()
	damaged.credits = 100000
	damaged.ships[3].hull_hp -= 20
	check(state._commit_hangar(damaged), "Fund and damage one escort")
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	screen.active_tab = "FLEET"
	screen._refresh()
	await settle()
	check(screen.tabs.get_child_count() == 2 and screen.tabs.get_child(0).text == "MAP"
		and screen.tabs.get_child(1).text == "FLEET", "Fleet replaces the separate Ships tab")
	var before: Dictionary = state.hangar_snapshot()
	var board: Control = screen.formation_view
	var positions: Dictionary = board.display_positions.duplicate()
	check(not positions.is_empty() and positions.size() == state.fleet.size(), "Every owned ship receives its saved display position")
	var tactical: Dictionary = state.hangar_snapshot()
	tactical.ships[3].formation = [2, 1]
	HangarSquadrons.sync(tactical)
	check(state._commit_hangar(tactical), "Change the shared saved formation")
	await settle()
	board = screen.formation_view
	check(board.display_positions != positions
		and board.display_positions[ship_id] == Vector2(2, 1), "Fleet canvas reflects changed tactical formation")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(640, 360)
		await settle()
		await capture("shared-fleet-640")
	screen._open_ship_editor(ship_id)
	await settle()
	check(screen.active_tab == "FLEET" and screen.ship_editor.is_visible_in_tree()
		and screen.canvas.owned_id == ship_id and screen.formation_view.is_visible_in_tree(),
		"Selecting a ship opens its existing editor over Fleet")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(root.get_visible_rect().encloses(screen.ship_editor.get_node("ShipEditorPanel").get_global_rect())
			and screen.canvas.size.x > 100 and screen.canvas.size.y > 80
			and screen.ship_editor.find_child("CloseX", true, false).is_visible_in_tree(),
			"Fleet ship editor, mount canvas and shared X fit at " + str(resolution))
		await capture("fleet-editor-%d" % resolution.x)
	var split: Button = screen.refit_panel.get_node("SplitSquadron")
	if DisplayServer.get_name() == "headless":
		split.pressed.emit()
	else:
		await click(split)
	await settle()
	check(HangarSquadrons.for_ship(state.squadrons, ship_id).members.size() == 1, "Fleet editor retains individual split action")
	var original_group: Dictionary = HangarSquadrons.for_ship(state.squadrons, state.fleet[4].id)
	var join: Button = screen.refit_panel.get_node("JoinSquadron_%d" % original_group.id)
	join.pressed.emit()
	await settle()
	check(HangarSquadrons.for_ship(state.squadrons, ship_id).id == original_group.id, "Fleet editor retains compatible join action")
	var repair: Button = screen.ship_editor.find_child("ShipRepair", true, false)
	repair.pressed.emit()
	await settle()
	check(not state.owned_ship(ship_id).needs_repair(), "Fleet editor retains individual paid repair")
	screen._inspect_chassis("fighter")
	if DisplayServer.get_name() == "headless":
		screen.canvas.slot_selected.emit("fore")
	else:
		await click(screen.canvas.slot_buttons.fore)
	check(screen.inspected_item.is_empty() and screen.slot_info.source_text.contains("Mini Turret")
		and not screen.refit_panel.has_node("PartOptions") and not screen.refit_panel.has_node("RemovePart"),
		"Clicking a mount shows read-only equipment details and complete loadouts")
	var change: Button = screen.refit_panel.get_node("Loadout_laser_drone")
	if DisplayServer.get_name() == "headless":
		change.pressed.emit()
	else:
		await click(change)
	await settle()
	check(state.owned_ship(ship_id).mounts.fore.equipment_id == "laser"
		and ship_id in HangarSquadrons.for_ship(state.squadrons, ship_id).overrides,
		"Fleet complete-preset refit updates equipment and squadron override")
	var fit: String = state.ShipLoadouts.default_for("drone").id
	screen.refit_panel.get_node("Loadout_" + fit).pressed.emit()
	await settle()
	check(state.ship_loadout_id(ship_id) == fit and state.owned_ship(ship_id).mounts.has("fore"),
		"Fleet named loadout restores the complete starter fit")
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-fleet-refit.json"
	before = state.hangar_snapshot()
	screen._refit_to("laser_drone")
	check(not screen.editor_feedback.text.is_empty() and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed Fleet refit stays in the editor and surfaces its save error without mutation")
	state.run_save_path = path
	var salvage_id: int = state.fleet[8].id
	screen._open_ship_editor(salvage_id)
	await settle()
	screen.ship_editor.find_child("ShipSalvage", true, false).pressed.emit()
	await settle()
	check(screen.shop.z_index > screen.ship_editor.z_index and state.owned_ship(salvage_id) != null,
		"Fleet salvage requires confirmation above the editor without removing a ship")
	state.run_save_path = "res://project.godot/no-salvage.json"
	var confirm: Button
	for button: Button in screen.shop.find_children("*", "Button", true, false):
		if button.text == "SALVAGE":
			confirm = button
	confirm.pressed.emit()
	await settle()
	check(state.owned_ship(salvage_id) != null and not screen.shop.find_child("SalvageError", true, false).text.is_empty(),
		"Failed salvage keeps the ship and surfaces its error inside the confirmation")
	state.run_save_path = path
	if DisplayServer.get_name() == "headless":
		confirm.pressed.emit()
	else:
		await click(confirm)
	await settle()
	check(state.owned_ship(salvage_id) == null and not screen.ship_editor_open,
		"Confirmed salvage removes only its selected ship and closes inspection")
	var transport_id: int = state.fleet[1].id
	var cargo: Dictionary = state.hangar_snapshot()
	var cargo_uid: String = state.owned_ship(transport_id).mounts.hold.uid
	cargo.equipment[cargo_uid].load = {"kind": "cargo", "quantity": 3, "origin": 0, "unit_value": 3}
	check(state._commit_hangar(cargo), "Save cargo on its real transport equipment UID")
	screen._open_ship_editor(state.fleet[1].id)
	await settle()
	screen.canvas.slot_selected.emit("hold")
	check(screen.slot_info.source_text.contains("Cargo Hold") and screen.slot_info.source_text.contains("Cargo 3 / 10"),
		"Fleet editor includes equipment and carried-cargo details")
	before = state.hangar_snapshot()
	screen._refit_to("survey")
	check(SaveValidation.same(before, state.hangar_snapshot()) and not screen.editor_feedback.text.is_empty(),
		"Fleet rejects a preset replacing a loaded hold without losing cargo or hiding the error")
	screen._close_ship_editor()
	await settle()
	check(not is_instance_valid(screen.ship_editor) and screen.active_tab == "FLEET", "Shared X returns to Fleet rather than switching tabs")
	var docked_group: Dictionary = HangarSquadrons.for_ship(state.squadrons, ship_id)
	screen._select_squadron(int(docked_group.id))
	await settle()
	var count: int = state.fleet.size()
	screen.details.find_child("SquadronBuy", true, false).pressed.emit()
	await settle()
	check(state.fleet.size() == count + 1 and state.ship_loadout_id(state.fleet[-1].id) == docked_group.loadout,
		"Fleet retains fitted group purchases using its default")
	check(state.depart_expedition("refuel_station_1"), "Depart while Fleet remains accessible")
	screen._open_ship_editor(ship_id)
	await settle()
	check(screen.ship_editor.find_child("ShipRepair", true, false).disabled
		and screen.ship_editor.find_child("ShipSalvage", true, false).disabled
		and screen.refit_panel.get_node("Loadout_" + state.ShipLoadouts.default_for("drone").id).disabled,
		"Cruising inspection never grants shipyard repair/salvage/refit services")
	screen._close_ship_editor()
	await settle()
	var group: Dictionary = HangarSquadrons.for_ship(state.squadrons, ship_id)
	screen._select_squadron(int(group.id))
	await settle()
	check(screen.details.find_child("Stance_evade", true, false) != null, "Fleet retains squadron stance actions")
	var fleet_before: Dictionary = state.hangar_snapshot()
	var ship: HangarShip = state.owned_ship(ship_id)
	var local: Vector2 = screen.formation_view.point(ship)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = local
	if DisplayServer.get_name() == "headless":
		screen.formation_view._gui_input(event)
	else:
		await pointer(screen.formation_view.global_position + local, true)
		await pointer(screen.formation_view.global_position + local, false)
	await settle()
	check(not screen.ship_editor_open and screen.selected_squadron_id == 0 and screen.details.has_node("ShipStatBars")
		and SaveValidation.same(fleet_before, state.hangar_snapshot()),
		"Clicking a management ship inspects it without moving its tactical formation")
	screen.queue_free()
	await settle()
	fleet_completed = true

func battle_checks() -> void:
	start()
	var research: Dictionary = state.hangar_snapshot()
	research.research.research_ids.append_array(["applied_energy", "disruption_i"])
	research.research.branch_choices.energy = "disruption"
	check(state._commit_hangar(research), "Save earned ability for deployment gating")
	var flagship: HangarShip = state.get_deployed_fleet()[0]
	for slot: Dictionary in flagship.chassis.slots:
		if SlotCatalog.compatible(slot, SlotCatalog.find_equipment("ion_emitter")):
			check(state.swap_part(flagship.id, slot.id, "ion_emitter"), "Install the earned ability's source")
			break
	var target: int = state.get_reachable_nodes(state.current_node_id)[0]
	check(state.travel_to(target), "Save a real pending encounter")
	var before: Dictionary = state.hangar_snapshot()
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	check(battle.deploying and battle.begin_button.is_visible_in_tree() and not battle.battle_speed_controls.visible,
		"Pending encounter starts in deployment with Begin Combat, not running combat")
	check(battle.objective_label.is_visible_in_tree() and battle.objective_label.get_parent() == battle.battle_readouts,
		"Mission objective remains visible while arranging deployment")
	var sim: BattleSimulation = battle.simulation
	var invalid_positions := {}
	for member: BattleSimulation.Combatant in sim.players:
		invalid_positions[member.owned_ship.id] = member.position
	var first_id: int = sim.players[0].owned_ship.id
	invalid_positions[first_id] = battle.visuals.deployment_area.position
	check(not state.save_battle_deployment(invalid_positions) and SaveValidation.same(before, state.hangar_snapshot()),
		"Deployment transaction rejects ships crossing the area edge, not just centers")
	invalid_positions[first_id] = Vector2(INF, 0)
	check(not state.save_battle_deployment(invalid_positions) and SaveValidation.same(before, state.hangar_snapshot()),
		"Deployment transaction rejects nonfinite positions atomically")
	invalid_positions.erase(first_id)
	check(not state.save_battle_deployment(invalid_positions) and SaveValidation.same(before, state.hangar_snapshot()),
		"Deployment transaction rejects incomplete placement atomically")
	battle.ability_bar.begin_targeting("ion_pulse")
	check(not battle.ability_bar.input_enabled and not battle.ability_bar.targeting
		and battle.ability_bar.auto_button.disabled and battle.ability_bar.pause_aim.disabled,
		"Deployment disables ability targeting, auto-cast and pause-aim controls")
	var combat_before := sim.authoritative_snapshot()
	battle._physics_process(30)
	battle._advance_fixed_simulation(30, 5)
	check(sim.elapsed == 0 and sim.authoritative_snapshot() == combat_before
		and SaveValidation.same(before, state.hangar_snapshot()), "Setup freezes all simulation, support, waves, damage, ammunition and rewards")
	var drone: BattleSimulation.Combatant = sim.players[3]
	var original: Vector2 = drone.position
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await settle()
		await drag(battle, drone, Vector2(15, 10))
		check(drone.position.is_equal_approx(original + Vector2(15, 10))
			and battle.visuals.deployment_selection.size() == 1 and sim.elapsed == 0,
			"Native ship drag moves only the individual without advancing combat")
		var neighbour: BattleSimulation.Combatant = sim.players[4]
		var neighbour_position := neighbour.position
		original = drone.position
		await drag(battle, drone, Vector2(10, -10))
		check(drone.position.is_equal_approx(original + Vector2(10, -10))
			and neighbour.position == neighbour_position and battle.visuals.deployment_selection.size() == 1,
			"Native repeated ship drag remains individual")
		await drag(battle, sim.players[0], Vector2.ZERO, false, true)
		check(battle.visuals.deployment_selection.size() == 2, "Native Shift selection adds another individual")
		var empty: Vector2 = battle.visuals.world_transform() * Vector2(-1800, 450)
		await pointer(empty, true)
		var motion := InputEventMouseMotion.new()
		motion.position = empty + Vector2(12, 10)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await settle()
		check(battle.visuals.deployment_box.has_area(), "Native deployment box selection has visible feedback")
		await pointer(motion.position, false)
		check(battle.visuals.deployment_selection.is_empty() and not battle.visuals.deployment_box.has_area(),
			"Empty-space box deselects and clears its feedback")
		original = drone.position
	var flag: Dictionary
	for candidate: Dictionary in battle.visuals.squadron_flags():
		if candidate.id == drone.squadron_id:
			flag = candidate
	check(not flag.is_empty() and battle._select_flag(flag.rect.get_center())
		and battle.visuals.deployment_selection.size() == 10, "Flag selection operates on the complete squadron")
	battle._deployment_origins.clear()
	for id: String in battle.visuals.deployment_selection:
		battle._deployment_origins[id] = sim.entities[id].position
	battle._move_deployment(Vector2(35, 15))
	check(drone.position.is_equal_approx(original + Vector2(35, 15)), "Squadron movement preserves internal spacing")
	check(battle._select_deployment(drone.position) and battle.visuals.deployment_selection.size() == 1,
		"Individual deployment selection can override one member")
	battle._deployment_origins = {drone.entity_id: drone.position}
	battle._move_deployment(Vector2(10000, -10000))
	check(battle.visuals.deployment_area.has_point(drone.position), "Dragging is bounded to the mission deployment area")
	check(BattleSimulation.deployment_area({"arena_layout": "corridor"}).size.y == 840,
		"Corridor deployment uses the mission's narrower lane")
	battle._move_deployment(Vector2.ZERO)
	if DisplayServer.get_name() != "headless":
		for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await settle()
			check(battle.begin_button.is_visible_in_tree()
				and root.get_visible_rect().encloses(battle.begin_button.get_global_rect())
				and battle.battlefield.size.x > 100, "Begin Combat is usable at " + str(resolution))
			await capture("deployment-%d" % resolution.x)
		root.size = Vector2i(1280, 720)
		await settle()
	var path: String = state.run_save_path
	battle._move_deployment(Vector2(10000, -10000))
	state.run_save_path = "res://project.godot/no-deployment.json"
	battle._begin_combat()
	check(battle.deploying and not battle.deployment_feedback.text.is_empty()
		and SaveValidation.same(before, state.hangar_snapshot()) and sim.elapsed == 0,
		"Begin Combat fails explicitly and retains setup when deployment cannot save")
	state.run_save_path = path
	if DisplayServer.get_name() != "headless":
		await click(battle.begin_button)
	else:
		battle._begin_combat()
	check(not battle.deploying and battle.battle_speed_controls.visible and sim.elapsed == 0
		and battle.ability_bar.input_enabled,
		"Begin Combat saves formation and enables combat exactly once")
	check(sim.players.all(func(member: BattleSimulation.Combatant) -> bool:
		return member.owned_ship == state.owned_ship(member.owned_ship.id)), "Combat actors follow the committed owned ships")
	var saved: Dictionary = state.hangar_snapshot()
	var deployed_positions := {}
	for member: BattleSimulation.Combatant in sim.players:
		deployed_positions[member.owned_ship.id] = member.position
	battle._begin_combat()
	check(SaveValidation.same(saved, state.hangar_snapshot()), "Repeated Begin Combat cannot resave or duplicate rewards")
	battle.queue_free()
	await settle()
	check(state.load_run_checkpoint(), "Continue pending deployment save")
	battle = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_process(false)
	battle.set_physics_process(false)
	await settle()
	check(battle.deploying and battle.simulation.elapsed == 0, "Continue returns to deployment, never a pretend mid-fight restore")
	for member: BattleSimulation.Combatant in battle.simulation.players:
		check(member.position.is_equal_approx(deployed_positions[member.owned_ship.id]), "Continue retains saved tactical placement")
	battle._begin_combat()
	for tick in range(30 * 90):
		battle._advance_fixed_simulation(1.0 / 30, 1)
		if battle.simulation.phase != BattleSimulation.Phase.COMBAT:
			break
	check(battle.simulation.elapsed > 0 and battle.simulation.phase != BattleSimulation.Phase.COMBAT,
		"One bounded deployment-started battle reaches an outcome")
	print("DEPLOYMENT BATTLE: ", JSON.stringify({"players": battle.simulation.players.size(),
		"enemies": battle.simulation.aliens.size(), "seconds": battle.simulation.elapsed,
		"outcome": BattleSimulation.Phase.keys()[battle.simulation.phase]}))
	check(state.settle_battle(battle.simulation) and not state.battle_pending, "Deployment-started battle settles through the existing transaction")
	battle.queue_free()
	await settle()
	battle_completed = true

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://fleet-redesign.json"
	if "--battle-only" not in OS.get_cmdline_user_args():
		await fleet_checks()
		check(fleet_completed, "Fleet integration reaches its completed summary")
	if "--fleet-only" not in OS.get_cmdline_user_args():
		await battle_checks()
		check(battle_completed, "Battle integration reaches its completed summary")
	print("FLEET REDESIGN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
