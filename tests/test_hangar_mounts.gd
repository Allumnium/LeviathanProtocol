extends SceneTree

var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/playthrough_mount_preferences.json"))
	for chassis: Dictionary in SlotCatalog.chassis():
		for slot: Dictionary in chassis.slots:
			for item: Dictionary in SlotCatalog.equipment(true):
				if item.size == slot.size and previous[chassis.id][slot.id] == item.type:
					check(SlotCatalog.compatible(slot, item), "Previously valid loadouts remain valid: " + chassis.id + "/" + slot.id + "/" + item.id)
				if slot.type == "general" and item.size == slot.size:
					check(SlotCatalog.compatible(slot, item), "General mounts accept every matching-size category")
				if slot.size != item.size:
					check(not SlotCatalog.compatible(slot, item), "Exact size remains mandatory on every chassis")
		if chassis.id in ["corsair", "transport", "frigate", "drone"]:
			var aft: Dictionary = chassis.slots.filter(func(slot: Dictionary) -> bool: return slot.id == "aft")[0]
			check(aft.type == "engine", "Rear engine housing has a positional restriction")
			check(SlotCatalog.compatible(aft, SlotCatalog.find_equipment("thruster")), "Engine mount accepts an extra thruster")
			check(SlotCatalog.compatible(aft, SlotCatalog.find_equipment("hull_plate")), "Engine mount accepts defensive plating")
			check(not SlotCatalog.compatible(aft, SlotCatalog.find_equipment("mini_turret")), "Engine mount rejects a weapon")
	check(SlotCatalog.compatible({"size": "M", "type": "engine"}, SlotCatalog.find_equipment("shield_generator")), "Defensive shields qualify even though the older equipment category was Tech")
	check(not SlotCatalog.compatible({"size": "M", "type": "engine"}, SlotCatalog.find_equipment("ammunition_magazine")), "Engine restriction does not admit unrelated Tech equipment")
	check(not SlotCatalog.compatible({"size": "M", "type": "offense"}, SlotCatalog.find_equipment("research_lab")), "Forward weapon mount rejects a same-size lab")
	check(SlotCatalog.slot_label({"type": "general", "size": "M"}) == "M", "General mount details need only the size")
	state = root.get_node("GameState")
	state.run_save_path = "user://general-mounts.json"
	check(state.start_new_run(1, 42), "Start general-mount transaction fixture")
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.credits = 5000
	fixture.research.research_ids.append("applied_energy")
	check(state._commit_hangar(fixture) and state.buy_chassis("transport"), "Buy actual Transport")
	var transport_id: int = state.fleet[-1].id
	var uids: Array[String] = []
	for id in ["double_laser", "armor_block", "shield_generator", "research_lab"]:
		check(state.buy_equipment(id), "Buy matching-size equipment: " + id)
		var uid := str(state.next_equipment_id - 1)
		uids.append(uid)
		var credits: int = state.credits
		check(state.fit_equipment(transport_id, "port", uid), "Transport left accepts " + id)
		check(state.fit_equipment(transport_id, "starboard", uid), "Transport right accepts " + id)
		check(state.credits == credits and not state.owned_ship(transport_id).mounts.has("port"), "Transfers remain free and unique")
	var before: Dictionary = state.hangar_snapshot()
	check(not state.fit_equipment(transport_id, "aft", uids[0]) and state.hangar_snapshot() == before, "Bad position/size leaves the save unchanged")
	check(state.load_run_checkpoint() and state.owned_ship(transport_id).mounts.starboard.uid == uids[-1], "Cross-category fit survives physical checkpoint reload")
	await ui_checks(transport_id, uids)
	stacking_checks(transport_id)
	print("HANGAR MOUNTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func stacking_checks(transport_id: int) -> void:
	var data: Dictionary = state.hangar_snapshot()
	data.research.research_ids.append_array(["guided_munitions", "siege_i", "command_i", "command_ii"])
	data.research.branch_choices["force_projection"] = "siege"
	data.research.branch_choices["fleet_operations"] = "command"
	check(state._commit_hangar(data), "Unlock existing stackable equipment fixture")
	for side in ["port", "starboard"]:
		check(state.buy_equipment("ammunition_magazine"), "Buy a distinct magazine instance")
		check(state.fit_equipment(transport_id, side, str(state.next_equipment_id - 1)), "Either Transport side accepts a magazine")
	check(state.owned_ship(transport_id).weapon_cycle_rate() == 1.4, "Two real Transport mounts give the requested stacking rate")
	check(state.buy_chassis("frigate"), "Buy Frigate with two large general mounts")
	var frigate_id: int = state.fleet[-1].id
	for location in ["fore", "center"]:
		check(state.buy_equipment("tactical_computer"), "Buy a distinct computer instance")
		check(state.fit_equipment(frigate_id, location, str(state.next_equipment_id - 1)), "Either large Frigate mount accepts a computer")
	var member := BattleSimulation.Combatant.new()
	member.owned_ship = state.owned_ship(frigate_id)
	check(CombatDoctrines.operational(member, ShipPart.Type.TACTICAL_COMPUTER).size() == 2, "Both physical computers contribute to synchronization")
	check(state.load_run_checkpoint() and state.owned_ship(transport_id).weapon_cycle_rate() == 1.4, "Stacked general-mount loadouts survive reload")

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func ui_checks(transport_id: int, uids: Array[String]) -> void:
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.selected_ship_id = transport_id
	screen._queue_refresh()
	await settle()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		for side in ["port", "starboard"]:
			var button: OptionButton = screen.canvas.slot_buttons[side]
			var offered: Array[String] = []
			for index in range(1, button.item_count):
				offered.append(button.get_item_metadata(index).uid)
			for uid: String in uids:
				check(uid in offered, "Both native side menus offer all four matching-size categories")
			check(button.focus_mode == Control.FOCUS_NONE and button.tooltip_text.is_empty(), "General mount retains focus/tooltip preferences")
		check(screen.canvas.slot_buttons.port.get_global_rect().intersects(screen.canvas.slot_buttons.starboard.get_global_rect()) == false, "Broader menus do not overlap controls")
	root.size = Vector2i(1280, 720)
	await settle()
	var button: OptionButton = screen.canvas.slot_buttons.port
	for index in range(1, button.item_count):
		if button.get_item_metadata(index).uid == uids[0]:
			button.get_popup().index_pressed.emit(index)
			break
	await settle()
	check(state.owned_ship(transport_id).mounts.port.uid == uids[0], "Native dropdown fits a weapon in the former Defense mount")
	screen.selected_slot = "port"
	screen._show_details()
	check(not text_under(screen.details).contains("General |"), "General mount has no redundant category text")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/mounts/transport.png")
	screen.queue_free()
	await settle()
	await create_timer(0.5).timeout

func text_under(node: Node) -> String:
	var text: String = node.text if node is Label else ""
	for child in node.get_children():
		text += "\n" + text_under(child)
	return text
