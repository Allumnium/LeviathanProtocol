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
	for chassis: Dictionary in SlotCatalog.chassis():
		for slot: Dictionary in chassis.slots:
			for item: Dictionary in SlotCatalog.equipment(true):
				var categories: Array = {"general": ["offense", "defense", "civic", "tech"],
					"combat": ["offense", "defense"], "offense": ["offense"],
					"utility": ["civic", "tech", "defense"], "civil": ["civic", "tech"]}[slot.type]
				if item.size == slot.size:
					check(SlotCatalog.compatible(slot, item) == (item.type in categories), "Owner-confirmed mount categories: " + chassis.id + "/" + slot.id + "/" + item.id)
				if slot.type == "general" and item.size == slot.size:
					check(SlotCatalog.compatible(slot, item), "General mounts accept every matching-size category")
				if slot.size != item.size:
					check(not SlotCatalog.compatible(slot, item), "Exact size remains mandatory on every chassis")
		if chassis.id in ["corsair", "transport", "frigate"]:
			var aft: Dictionary = chassis.slots.filter(func(slot: Dictionary) -> bool: return slot.id == "aft")[0]
			check(aft.type == ("utility" if chassis.id == "frigate" else "general"), "Rear mount uses confirmed category")
			check(SlotCatalog.compatible(aft, SlotCatalog.find_equipment("thruster")), "Engine mount accepts an extra thruster")
			check(SlotCatalog.compatible(aft, SlotCatalog.find_equipment("hull_plate")), "Engine mount accepts defensive plating")
			check(SlotCatalog.compatible(aft, SlotCatalog.find_equipment("mini_turret")) == (chassis.id != "frigate"), "Rear weapon fitting follows chassis category")
	check(SlotCatalog.compatible({"size": "M", "type": "engine"}, SlotCatalog.find_equipment("shield_generator")), "Defensive shields qualify even though the older equipment category was Tech")
	check(not SlotCatalog.compatible({"size": "M", "type": "engine"}, SlotCatalog.find_equipment("ammunition_magazine")), "Engine restriction does not admit unrelated Tech equipment")
	check(not SlotCatalog.compatible({"size": "M", "type": "offense"}, SlotCatalog.find_equipment("research_lab")), "Forward weapon mount rejects a same-size lab")
	check(SlotCatalog.slot_label({"type": "general", "size": "M"}) == "M", "General mount details need only the size")
	state = root.get_node("GameState")
	state.run_save_path = "user://general-mounts.json"
	check(state.start_new_run(1, 42), "Start general-mount transaction fixture")
	var fixture: Dictionary = state.hangar_snapshot()
	fixture.credits = 5000
	fixture.research.research_ids.append_array(["applied_energy", "bastion_ii", "command_i", "command_ii"])
	fixture.research.branch_choices["survival"] = "bastion"
	fixture.research.branch_choices["fleet_operations"] = "command"
	check(state._commit_hangar(fixture) and state.buy_ship("transport"), "Buy actual Transport")
	var transport_id: int = state.fleet[-1].id
	var uids: Array[String] = []
	check(state.swap_part(transport_id, "port", ""), "Clear starting plate for transfer fixture")
	for key in ["armor_block@2", "shield_relay", "tactical_computer"]:
		check(state.swap_part(transport_id, "port", key), "Transport left accepts " + key)
		var uid: String = state.owned_ship(transport_id).mounts.port.uid
		uids.append(uid)
		var credits: int = state.credits
		check(state.fit_equipment(transport_id, "starboard", uid), "Transport right accepts " + key)
		check(state.credits == credits and not state.owned_ship(transport_id).mounts.has("port"), "Transfers remain free and unique")
	var before: Dictionary = state.hangar_snapshot()
	check(not state.fit_equipment(transport_id, "aft", uids[-1]) and state.hangar_snapshot() == before, "Bad position/size leaves the save unchanged")
	check(state.load_run_checkpoint() and state.owned_ship(transport_id).mounts.starboard.uid == uids[-1], "Cross-category fit survives physical checkpoint reload")
	await ui_checks(transport_id, uids)
	stacking_checks(transport_id)
	print("HANGAR MOUNTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func stacking_checks(transport_id: int) -> void:
	var data: Dictionary = state.hangar_snapshot()
	data.research.research_ids.append_array(["guided_munitions", "siege_i"])
	data.research.branch_choices["force_projection"] = "siege"
	data.research.branch_choices["fleet_operations"] = "command"
	check(state._commit_hangar(data), "Unlock existing stackable equipment fixture")
	check(state.buy_ship("drone"), "Buy a general M magazine host")
	var drone_id: int = state.fleet[-1].id
	check(state.swap_part(drone_id, "center", "ammunition_magazine"), "General Drone center accepts a magazine")
	check(state.owned_ship(drone_id).weapon_cycle_rate() == 1.2, "Real general mount supplies ship-wide cycling")
	for location in ["port", "starboard"]:
		if state.owned_ship(transport_id).mounts.get(location, {}).get("equipment_id", "") != "tactical_computer":
			check(state.swap_part(transport_id, location, "tactical_computer"), "Either large Transport utility mount accepts a computer")
	var member := BattleSimulation.Combatant.new()
	member.owned_ship = state.owned_ship(transport_id)
	check(CombatDoctrines.operational(member, ShipPart.Type.TACTICAL_COMPUTER).size() == 2, "Both physical computers contribute to synchronization")
	check(state.load_run_checkpoint() and state.owned_ship(drone_id).weapon_cycle_rate() == 1.2, "General-mount cycling survives reload")
	member.owned_ship = state.owned_ship(transport_id)
	check(CombatDoctrines.operational(member, ShipPart.Type.TACTICAL_COMPUTER).size() == 2, "Stacked utility-mount loadouts survive reload")

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func ui_checks(transport_id: int, uids: Array[String]) -> void:
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "FLEET"
	root.add_child(screen)
	current_scene = screen
	screen.selected_ship_id = transport_id
	screen.selected_squadron_id = 0
	screen._queue_refresh()
	await settle()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		for side in ["port", "starboard"]:
			check(screen.details.has_node("ShipEquipment_" + side), "Both side mounts expose fitted equipment in right panel")
		check(not screen.refit_panel.has_node("PartOptions"), "General mounts do not expose custom part pickers")
	check(not text_under(screen.details).contains("General |"), "Equipment has no redundant category text")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/mounts/transport.png")
	screen.queue_free()
	await settle()
	await create_timer(0.5).timeout

func text_under(node: Node) -> String:
	var text: String = node.source_text if node is ResourceText else (node.text if node is Label else "")
	for child in node.get_children():
		text += "\n" + text_under(child)
	return text
