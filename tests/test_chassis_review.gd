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
	check(flagship.get_stats().shields == 20, "Flagship level I shields")
	check(state.equipment_inventory.size() == 7, "Flagship and Fighters receive seven compatible starter equipment instances")
	check(not flagship.mounts.has("inner_port"), "Incompatible starter armor removed without replacement")
	var healthy: Dictionary = state.hangar_snapshot()
	check(healthy.version == 2 and not healthy.ships[0].has("builtins"), "Schema2 has no builtin component health")
	for instance: Dictionary in healthy.equipment.values():
		check(not instance.has("hp"), "Schema2 equipment has no component health")
	flagship.damage_cell(Vector2i(1, 0), 50)
	check(flagship.get_stats().shields == 20 and flagship.hull_hp == 270, "Hits damage hull only and builtin shield remains operational")
	check(flagship.repair_cost() == 50, "Repair quote counts hull damage only")
	check(state.save_run_checkpoint() and state.load_run_checkpoint(), "Hull damage survives reload")
	flagship = state.fleet[0]
	check(flagship.hull_hp == 270 and flagship.get_stats().shields == 20, "Reload preserves hull damage and operational shield")
	var damaged: Dictionary = state.hangar_snapshot()
	var generation: int = state.hangar_generation
	state.hangar_generation += 1
	check(not state.repair_ship(flagship), "Stale atomic repair explicitly fails")
	check(state.hangar_snapshot() == damaged, "Failed repair changes no credits or hull")
	state.hangar_generation = generation
	check(state.repair_ship(state.fleet[0]), "Hull repairs through normal credits transaction")
	check(state.fleet[0].hull_hp == 320 and state.fleet[0].get_stats().shields == 20 and state.credits == int(damaged.credits) - 50, "Repair restores only hull with exact quote")
	var invalid: Dictionary = state.hangar_snapshot()
	invalid.ships[0]["builtins"] = {"shield": 25}
	check(not HangarCheckpoint.valid(invalid), "Schema2 rejects retired builtin health")
	invalid = state.hangar_snapshot()
	invalid.equipment.values()[0]["hp"] = 25
	check(not HangarCheckpoint.valid(invalid), "Schema2 rejects retired equipment health")
	_test_stat_ranges()
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
	check(_text(scene.inspection).contains("damage x") and not _text(scene.inspection).contains("HP")
		and not _text(scene.inspection).contains("Command Center") and not _text(scene.inspection).contains("Built-in Engine"),
		"Equipment preview includes weapon rates, never component HP or implicit engine/core")
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
	check(_text(scene.inspection).contains("+30%") and _text(scene.inspection).contains("20%") and _text(scene.inspection).contains("Maneuverability"), "Chassis inspector exposes real bonuses and maneuverability")
	check(scene.inspection.find_child("ShipStatBars", true, false).bars.size() == 3
		and not _text(scene.inspection).contains("HP") and not _text(scene.inspection).contains("Command Center")
		and not _text(scene.inspection).contains("Built-in Engine"), "Unshielded chassis preview omits shield bar and implicit component descriptions")
	check(not scene.inspection.find_child("ShipStatBars", true, false).bars.has("shields")
		and not _text(scene.inspection).contains("DPS"), "Unarmed unshielded chassis preview hides zero shield and DPS details")
	scene._inspect_chassis("flagship_basic")
	check(_text(scene.inspection).contains("Shields 20") and not _text(scene.inspection).contains("Built-in")
		and not _text(scene.inspection).contains("Mounts") and not _text(scene.inspection).contains("HP"),
		"Chassis descriptions show shield amount without builtin or mounting-point listings")
	scene._inspect_chassis("fighter")
	await process_frame
	await process_frame
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
		var stat_panel: ShipStatBars = scene.inspection.find_child("ShipStatBars", true, false)
		for key: String in stat_panel.bars:
			var label: ResourceText = stat_panel.bars[key].get_parent().get_node("StatValue")
			var measured: String = label.source_text.replace("Shields", "O")
			check(label.get_theme_font("normal_font").get_string_size(measured, HORIZONTAL_ALIGNMENT_LEFT, -1,
				label.get_theme_font_size("normal_font_size")).x <= label.size.x,
				"Exact %s numeric text fits inspector at %s" % [key, viewport_size])
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/chassis-inspector.png")
	scene.active_tab = "SHIPS"
	scene.buy_open = false
	scene._refresh()
	await process_frame
	await process_frame
	scene._inspect_equipment("mini_turret", 1)
	_click(scene.canvas.slot_buttons.port.get_global_rect().get_center())
	await process_frame
	check(scene.slot_info.visible and scene.slot_info.source_text.contains("Mini Turret"), "Art selection still updates installed-part details after inspection")
	check(scene.inspected_item.is_empty() and scene.stock.visible, "Art click exits catalog inspection and restores stock")
	_click(scene.canvas.slot_buttons.fore.get_global_rect().get_center())
	await process_frame
	check(scene.stats_grid.visible and not scene.slot_info.visible, "Empty mount restores ship stats without inspection interference")
	var ship: HangarShip = state.owned_ship(scene.selected_ship_id)
	var values: Dictionary = ShipStatBars.values(ship)
	var ranges := ShipStatBars.comparison_ranges()
	for key: String in scene.stats_grid.bars:
		check(is_equal_approx(scene.stats_grid.bars[key].value, ShipStatBars.percentage(values[key], ranges[key])),
			"Ships editor uses actual outfitted %s comparison" % key)
	check(_text(scene.stats_grid).contains("Hull %d / %d" % [roundi(ship.hull_hp), roundi(ship.hull_max)]),
		"Ships editor displays rounded actual current/max hull")
	scene.active_tab = "FLEET"
	scene._refresh()
	await process_frame
	await process_frame
	var fleet_bars: ShipStatBars = scene.details.find_child("ShipStatBars", true, false)
	check(fleet_bars != null and fleet_bars.bars.size() == 4, "Fleet single selection shows shared four-stat bars")
	for key: String in fleet_bars.bars:
		check(is_equal_approx(fleet_bars.bars[key].value, ShipStatBars.percentage(values[key], ranges[key])),
			"Fleet selected ship uses actual outfitted %s comparison" % key)
	scene.queue_free()
	await process_frame
	print("Chassis review: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_fighter() -> void:
	var fighter := HangarShip.new()
	check(fighter.initialize_chassis("fighter", 2), "Fighter initializes")
	var item := SlotCatalog.find_equipment("mini_turret")
	fighter.mounts.port = {"uid": "test", "equipment_id": item.id, "rank": 1}
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

func _test_stat_ranges() -> void:
	var helper = load("res://scripts/ship_stat_bars.gd")
	var ranges: Dictionary = helper.comparison_ranges()
	check(SlotCatalog.chassis().size() == 9 and ranges.size() == 4, "Comparison covers all nine base chassis including four flagships and four stats")
	var measured := {}
	var movement_average := 0.0
	for chassis: Dictionary in SlotCatalog.chassis():
		var ship := HangarShip.new()
		ship.initialize_chassis(chassis.id, 0, int(chassis.command) > 0)
		var stats := ship.get_stats()
		movement_average += (stats.top_speed + stats.acceleration + stats.turn_rate) / SlotCatalog.chassis().size()
	var score_average := 0.0
	for chassis: Dictionary in SlotCatalog.chassis():
		var ship := HangarShip.new()
		ship.initialize_chassis(chassis.id, 0, int(chassis.command) > 0)
		var stats := ship.get_stats()
		var score := 50.0 * (stats.top_speed + stats.acceleration + stats.turn_rate) / movement_average
		check(is_equal_approx(helper.maneuverability(stats), score), "Maneuverability normalizes against aggregated chassis-wide means")
		score_average += helper.maneuverability(stats) / SlotCatalog.chassis().size()
		var base := {"hull": ship.hull_hp, "maneuverability": score, "mass": stats.weight, "shields": stats.shields}
		for key: String in base:
			var value: float = base[key]
			measured[key] = Vector2(minf(measured[key].x, value), maxf(measured[key].y, value)) if measured.has(key) else Vector2(value, value)
	for key: String in measured:
		check(ranges[key].is_equal_approx(measured[key]), "Comparison derives real base " + key)
	check(is_equal_approx(score_average, 50), "Average base chassis maneuverability is exactly 50")
	var fractional := HangarShip.new()
	fractional.initialize_chassis("fighter", 3)
	fractional.hull_hp = 75.6
	var numeric_panel: ShipStatBars = helper.new()
	root.add_child(numeric_panel)
	numeric_panel.set_ship(fractional)
	check(not numeric_panel.bars.has("shields") and not _text(numeric_panel).contains("DPS"), "Zero shields and zero DPS are independently omitted")
	fractional.mounts.fore = {"uid": "stat-weapon", "equipment_id": "mini_turret", "rank": 1}
	fractional.rebuild_units()
	numeric_panel.set_ship(fractional)
	check(not numeric_panel.bars.has("shields") and _text(numeric_panel).contains("DPS"), "Armed unshielded ship shows DPS but no shield bar")
	check(_text(numeric_panel).contains("Hull 76 / 100"), "Fractional hull rounds only for display")
	check(fractional.hull_hp == 75.6, "Integer descriptions never round backend state")
	var decimal := RegEx.new()
	decimal.compile("\\d+\\.\\d+")
	check(decimal.search(_text(numeric_panel)) == null, "Ship descriptions contain no decimal values")
	for hidden in ["Thrust", "Speed", "Acceleration", "Turn"]:
		check(not _text(numeric_panel).contains(hidden), "Movement detail consolidated: " + hidden)
	numeric_panel.queue_free()
	var flagship := HangarShip.new()
	flagship.initialize_chassis("flagship_basic", 0, true)
	check(flagship.get_stats().weight == float(flagship.chassis.mass) + SlotCatalog.stats_for(flagship.chassis.builtin_shield).weight,
		"Flagship base mass includes builtin shield, not just catalog chassis mass")
	for key: String in ranges:
		var limits: Vector2 = ranges[key]
		check(limits.x < limits.y, "Chassis have distinct comparison extrema: " + key)
		var panel: ShipStatBars = helper.new()
		root.add_child(panel)
		panel.set_ship(flagship)
		var bar: TextureProgressBar = panel.bars[key]
		check(bar.texture_progress.resource_path == "res://assets/ui/Progress_Cp.png"
			and bar.texture_under.resource_path == "res://assets/ui/Progress_Cp_Bg.png"
			and bar.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Required native bar textures/filter: " + key)
		for pair: Vector2 in [Vector2(limits.x, 10), Vector2((limits.x + limits.y) * 0.5, 55), Vector2(limits.y, 100)]:
			bar.value = helper.percentage(pair.x, limits)
			check(is_equal_approx(bar.value, pair.y), "Measured native %s percentage equals %s" % [key, pair.y])
		check(helper.percentage(limits.x - 100, limits) == 10 and helper.percentage(limits.y + 100, limits) == 100,
			"Outfitted/damaged %s clamps without changing numeric data" % key)
		panel.queue_free()
