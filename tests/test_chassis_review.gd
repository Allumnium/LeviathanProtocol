extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var state := root.get_node("GameState")
	check(state.start_new_run(1, 64102), "New chassis run saves successfully")
	var expected := {
		"flagship_basic": ["fore=S:combat", "port=S:combat", "starboard=S:combat", "spine=M:general", "aft_port=S:utility", "aft_starboard=S:utility", "inner_port=S:utility", "inner_starboard=S:utility"],
		"corsair": ["fore=L:combat", "port=M:combat", "starboard=M:combat", "aft=S:general"],
		"fighter": ["fore=S:general", "port=S:offense", "starboard=S:offense"],
		"transport": ["hold=XL:civil", "port=L:utility", "starboard=L:utility", "fore=S:general", "aft=S:general"],
		"frigate": ["fore=S:general", "fore_2=S:general", "fore_3=S:general", "fore_4=S:general", "port=S:combat", "starboard=S:combat", "center=M:general", "aft=S:utility"],
		"drone": ["fore=S:general", "port=S:general", "starboard=S:general", "center=M:general"]
	}
	for id: String in expected:
		var actual: Array[String] = []
		for slot: Dictionary in SlotCatalog.find_chassis(id).slots:
			actual.append("%s=%s:%s" % [slot.id, slot.size, slot.type])
		check(actual == expected[id], "%s exact owner mount specification" % id)
	var flagship: HangarShip = state.fleet[0]
	check(flagship.hull_hp == 320 and flagship.get_stats().thrust == 22, "Flagship high hull and low thrust")
	check(flagship.get_stats().shields == 40, "Flagship built-in level I shield")
	check(state.equipment_inventory.size() == 3, "Only compatible starter equipment retained")
	check(not flagship.mounts.has("inner_port"), "Incompatible starter armor removed without replacement")
	var healthy: Dictionary = state.hangar_snapshot()
	check(healthy.ships[0].builtins.shield == 25, "Built-in shield health persisted without stock UID")
	flagship.damage_cell(Vector2i(2, 0), 50)
	check(flagship.get_stats().shields == 0 and flagship.units[2].hp == 0, "Destroyed built-in shield stops working")
	check(flagship.repair_cost() == 50, "Built-in shield plus chassis damage quoted for repair")
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Damaged built-in shield survives reload")
	flagship = state.fleet[0]
	check(flagship.units[2].hp == 0 and flagship.get_stats().shields == 0, "Reload does not recreate destroyed shield")
	var damaged: Dictionary = state.hangar_snapshot()
	var generation: int = state.hangar_generation
	state.hangar_generation += 1
	check(not state.repair_ship(flagship), "Stale atomic repair explicitly fails")
	check(state.hangar_snapshot() == damaged, "Failed repair changes no credits, hull or builtin health")
	state.hangar_generation = generation
	check(state.repair_ship(state.fleet[0]), "Built-in shield repairs through normal credits transaction")
	check(state.fleet[0].get_stats().shields == 40 and state.credits == int(damaged.credits) - 50, "Repair restores built-in shield with exact quote")
	var invalid: Dictionary = state.hangar_snapshot()
	invalid.ships[0].builtins.erase("shield")
	check(not HangarCheckpoint.valid(invalid), "Missing mandatory builtin shield rejected")
	invalid = state.hangar_snapshot()
	invalid.ships[0].builtins.shield = 26
	check(not HangarCheckpoint.valid(invalid), "Oversized builtin shield HP rejected")
	_test_fighter()
	var scene: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene._open_shop("EQUIPMENT")
	await process_frame
	await process_frame
	var equipment_row: Button
	for row in scene.shop_rows.get_children():
		if row.get_meta("equipment_id", "") == "mini_turret":
			equipment_row = row
	check(equipment_row != null, "Inspectable researched equipment in shop")
	var credits: int = state.credits
	_click(equipment_row.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(state.credits == credits, "Equipment row inspection is not purchase")
	check(scene.inspected_item.get("id", "") == "mini_turret" and scene.inspection != null and not scene.stock.visible, "Equipment click replaces right panel with details")
	check(_text(scene.inspection).contains("damage x") and _text(scene.inspection).contains("HP"), "Equipment details include health and weapon rates")
	_click(Vector2(4, root.get_visible_rect().size.y - 4))
	await process_frame
	check(scene.inspected_item.is_empty() and scene.stock.visible, "Blank click restores stock")
	check(state.buy_equipment("mini_turret"), "Purchase a unique loose item for inspection")
	await process_frame
	await process_frame
	var row: Button = scene.stock.rows.get_child(0)
	_click(row.get_global_rect().get_center())
	await process_frame
	check(scene.inspected_item.get("uid", "") == row.get_meta("inspect_equipment"), "Stock click inspects actual equipment UID")
	check(not scene.stock.visible, "Stock temporarily hidden, not rebuilt")
	scene._clear_inspection()
	scene._open_shop("SHIPS")
	await process_frame
	await process_frame
	var chassis_row: Button
	for host in scene.shop_rows.get_children():
		for child in host.get_children():
			if child is Button and child.get_meta("inspect_chassis", "") == "fighter":
				chassis_row = child
	credits = state.credits
	_click(chassis_row.get_global_rect().get_center())
	await process_frame
	check(state.credits == credits and scene.inspected_item.get("id", "") == "fighter", "Chassis row inspects without buying")
	check(_text(scene.inspection).contains("+30%") and _text(scene.inspection).contains("20%") and _text(scene.inspection).contains("Thrust 38"), "Chassis inspector exposes real bonuses and thrust")
	_click(scene.inspection.get_global_rect().get_center())
	await process_frame
	check(scene.inspection != null, "Inspector contents and scrollbar remain interactive")
	var before_drag: Dictionary = state.hangar_snapshot()
	var installed_uid: String = state.fleet[0].mounts.port.uid
	scene.force_drag(load("res://scripts/hangar_equipment_transfer.gd").payload(installed_uid), Control.new())
	await process_frame
	check(scene.inspected_item.is_empty() and scene.stock.visible and scene.stock.unequip_mode, "Installed drag reveals full-panel unequip target from inspection")
	_click(Vector2(4, root.get_visible_rect().size.y - 4))
	await process_frame
	check(not scene.stock.unequip_mode and scene.stock.filters.visible, "Drag cancellation restores stock controls")
	check(state.hangar_snapshot() == before_drag, "Cancelled inspected-equipment drag is mutation-free")
	scene._inspect_chassis("fighter")
	var unavailable: Button
	for host in scene.shop_rows.get_children():
		for child in host.get_children():
			if child is Button and child.get_meta("inspect_chassis", "") == "frigate":
				unavailable = child
	check(unavailable.disabled and not unavailable.has_node("BuyIcon"), "Unaffordable chassis has no purchase control")
	_click(unavailable.get_global_rect().position + Vector2(20, 10))
	await process_frame
	check(scene.inspected_item.get("id", "") == "frigate", "Unaffordable chassis remains inspectable")
	scene._inspect_chassis("fighter")
	for viewport_size in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		check(scene.inspection.get_global_rect().end.x <= root.get_visible_rect().size.x, "Inspector fits viewport %s" % viewport_size)
		check(scene.inspection.get_child(0).size.x <= scene.inspection.size.x, "Inspector text stays within scroll panel")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/chassis-inspector.png")
	scene.queue_free()
	await process_frame
	print("Chassis review: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_fighter() -> void:
	var fighter := HangarShip.new()
	check(fighter.initialize_chassis("fighter", 2), "Fighter initializes")
	var item := SlotCatalog.find_equipment("mini_turret")
	fighter.mounts.port = {"uid": "test", "equipment_id": item.id, "rank": 1, "hp": item.hit_points}
	fighter.rebuild_units()
	check(is_equal_approx(fighter.get_stats().weapons[0].damage_per_shot, SlotCatalog.stats_for(item.id).weapons[0].damage_per_shot * 1.3), "Fighter weapon damage gets exact 30% bonus")
	check(is_equal_approx(fighter.get_stats().dps, SlotCatalog.stats_for(item.id).weapons[0].get_dps() * 1.3), "Fighter DPS includes bonus")
	var sim := BattleSimulation.new()
	sim.credits_only = true
	var target := BattleSimulation.Combatant.new()
	target.entity_id = "fighter"
	target.owned_ship = fighter
	target.stats = fighter.get_stats()
	target.integrity = fighter.hull_hp
	target.shields = 10000
	var source := BattleSimulation.Combatant.new()
	source.entity_id = "enemy"
	source.stats = ShipStats.new()
	source.integrity = 100
	var random := RandomNumberGenerator.new()
	random.seed = 64102
	sim.random.seed = 64102
	var expected_dodges := 0
	for hit in range(2000):
		if random.randf() < 0.2:
			expected_dodges += 1
		sim._damage(target, 1, Vector2.ZERO, source, "Test beam", false, true)
	check(target.shields == 10000 - (2000 - expected_dodges), "Seeded beam dodge exactly follows 20% per-hit probability")
	check(expected_dodges > 340 and expected_dodges < 460, "Measured dodge frequency within expected 20% tolerance")
	check(sim.event_log.size() == expected_dodges, "Dodges explicitly recorded as combat events")
	var shields := target.shields
	for hit in range(2000):
		if random.randf() < 0.2:
			expected_dodges += 1
		sim._damage(target, 1, Vector2.ZERO, source, "Test projectile", true)
	check(target.shields == 10000 - (4000 - expected_dodges), "Projectiles use the same exact seeded hit dodge")
	check(target.shields < shields, "Non-dodged projectiles still absorb shields first")
	var rng_state := sim.random.state
	shields = target.shields
	sim._damage(target, 1, Vector2.ZERO, source, "Direct damage")
	sim._damage(target, 1, Vector2.ZERO, null, "Asteroid impact")
	sim._damage(target, 1, Vector2.ZERO, source, "Seismic Cut")
	check(target.shields == shields - 3 and sim.random.state == rng_state, "Direct, environmental and ability damage cannot dodge or consume dodge RNG")
	target.owned_ship = HangarShip.new()
	target.owned_ship.initialize_chassis("drone", 3)
	sim._damage(target, 1, Vector2.ZERO, source, "Beam", false, true)
	check(sim.random.state == rng_state, "Zero-dodge chassis preserve existing battle RNG sequence")

func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)

func _text(node: Node) -> String:
	var result := ""
	if node is ResourceText:
		result = node.source_text
	elif node is Label:
		result = node.text
	for child in node.get_children():
		result += "\n" + _text(child)
	return result
