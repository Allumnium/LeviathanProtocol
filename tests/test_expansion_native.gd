extends "res://tests/test_act1_content.gd"

var screen: Control
var captures := 0

func frames() -> void:
	for index in range(5):
		await process_frame

func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "Native pointer target exists")
	if control == null:
		return
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await frames()
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = motion.position
	press.global_position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	press = press.duplicate()
	press.pressed = false
	press.button_mask = 0
	root.push_input(press, true)
	await frames()

func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://" + label + ".png") == OK, "Capture " + label)
	captures += 1

func event_sizes(label: String) -> void:
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await frames()
		var panel: Control = screen.encounter_modal.find_child("EncounterPanel", true, false)
		check(root.get_visible_rect().encloses(panel.get_global_rect()), "Event panel fits " + str(resolution))
		for button: Button in screen.encounter_modal.find_children("Choice_*", "Button", true, false):
			check(panel.get_global_rect().encloses(button.get_global_rect()), "Choice fits " + button.name)
		await capture(label + "-" + str(resolution.x))

func show_screen(tab := "MAP") -> void:
	state.pending_intro = false
	screen = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = tab
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await frames()

func close_screen() -> void:
	screen.queue_free()
	await frames()

func story_ui() -> void:
	opening()
	await show_screen()
	await event_sizes("meridian-departure")
	await click(screen.encounter_modal.find_child("Choice_leave", true, false))
	check(state.expedition_simulation.state.flags.get("meridian_left", false), "Pointer commits leave choice")
	state.advance_expedition(0)
	screen._show_encounter()
	await frames()
	await click(screen.encounter_modal.find_child("Choice_continue", true, false))
	state.advance_expedition(0)
	screen._show_encounter()
	await event_sizes("protocol")
	await click(screen.encounter_modal.find_child("Choice_acknowledge", true, false))
	check(state.research_choice_ready(), "Pointer broadcast reaches research choice")
	check(state.expedition_simulation.state.flags.get("leviathan_protocol", false), "Pointer broadcast grants gate access")
	await close_screen()
	check(state.start_new_run(1, 52), "Start disabled fuel-choice UI")
	state.expedition_simulation.state.pending_event_id = "corporate_convoy"
	state.expedition_simulation.state.pause_reasons.append(Travel.PauseReason.ENCOUNTER)
	state.expedition_simulation.state.fuel = 9
	await show_screen()
	var transfer: Button = screen.encounter_modal.find_child("Choice_transfer", true, false)
	check(transfer.disabled, "Insufficient-fuel choice is visibly disabled")
	root.size = Vector2i(640, 360)
	await capture("fuel-disabled-640")
	await click(transfer)
	check(pending() == "corporate_convoy", "Disabled fuel choice cannot commit")
	await click(screen.encounter_modal.find_child("Choice_decline", true, false))
	check(pending().is_empty(), "Free fallback remains usable")
	await close_screen()

func equipment_ui() -> void:
	check(state.start_new_run(1, 61), "Start equipment UI fixture")
	state.credits = 10000
	check(state.buy_ship("frigate"), "Buy legal host for new autocannon fit")
	await show_screen("FLEET")
	var cases := [["drone", "courier", "center", "Cargo Pod"], ["fighter", "skirmisher", "fore", "Light Shield"],
		["transport", "passenger_liner", "hold", "Passenger Berth"], ["frigate", "brawler", "center", "Autocannon"]]
	for entry: Array in cases:
		var ship: HangarShip = state.fleet.filter(func(s: HangarShip) -> bool: return s.chassis_id == entry[0])[0]
		screen._select_ship(ship.id)
		await frames()
		root.size = Vector2i(1280, 720)
		await click(screen.find_child("Loadout_" + entry[1], true, false))
		check(state.ship_loadout_id(ship.id) == entry[1], "Pointer refits " + entry[1])
		for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await frames()
			var detail: Control = screen.find_child("ShipEquipment_" + entry[2], true, false)
			var scroll := detail.get_parent()
			while scroll != null:
				if scroll is ScrollContainer:
					scroll.ensure_control_visible(detail)
				scroll = scroll.get_parent()
			await frames()
			check(detail.is_visible_in_tree() and root.get_visible_rect().intersects(detail.get_global_rect()), "New equipment detail scrolls into view")
			await capture(entry[1] + "-" + str(resolution.x))
	await close_screen()

func measured_defense() -> void:
	opening()
	choose("meridian_departure", "return")
	reach("first_contact")
	choose("first_contact", "fight")
	root.size = Vector2i(1280, 720)
	var battle_screen: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle_screen)
	current_scene = battle_screen
	battle_screen.set_process(false)
	battle_screen.set_physics_process(false)
	await frames()
	var sim: BattleSimulation = battle_screen.simulation
	battle_screen._begin_combat()
	check(not battle_screen.deploying, "Begin actual Meridian combat")
	for tick in range(30 * 90):
		battle_screen._advance_fixed_simulation(1.0 / 30, 1)
		if tick == 300:
			battle_screen.visuals.queue_redraw()
			await capture("meridian-defense")
		if sim.phase != BattleSimulation.Phase.COMBAT:
			break
	check(sim.phase == BattleSimulation.Phase.VICTORY, "Bounded ordinary opening clears Meridian")
	print("MERIDIAN BATTLE: seconds=%.3f survivors=%d phase=%d" % [sim.elapsed, sim.living_player_count(), sim.phase])
	check(state.settle_battle(sim), "Settle measured Meridian battle")
	battle_screen.queue_free()
	await frames()
	protocol("meridian_saved_report")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://expansion-native.json"
	if DisplayServer.get_name() == "headless":
		check(false, "Native rendering required")
	else:
		if "--details-only" not in OS.get_cmdline_user_args():
			await story_ui()
		await equipment_ui()
		if "--details-only" not in OS.get_cmdline_user_args() and "--ui-only" not in OS.get_cmdline_user_args():
			await measured_defense()
	var expected := 12 if "--details-only" in OS.get_cmdline_user_args() else (19 if "--ui-only" in OS.get_cmdline_user_args() else 20)
	check(captures == expected, "All requested native captures completed")
	print("EXPANSION NATIVE: %d checks, %d failures; %d captures; COMPLETE" % [checks, failures, captures])
	quit(0 if failures == 0 else 1)
