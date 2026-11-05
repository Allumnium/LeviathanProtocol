extends SceneTree

const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(5):
		await process_frame

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://flagship-selection.json"
	check(SlotCatalog.flagships().size() == 4, "Four flagship choices including original")
	var budgets := {}
	for chassis: Dictionary in SlotCatalog.flagships():
		check(state.start_new_run(1, 351, true, chassis.id), "Start selected " + chassis.id)
		check(state.credits == 700 and state.run_score.credits_earned == 0, "Starting credits are 700, excluded from score")
		check(state.fleet.size() == 13 and state.fleet[0].chassis_id == chassis.id
			and state.fleet[1].chassis_id == "transport" and state.fleet[2].chassis_id == "fighter"
			and state.fleet.slice(3).all(func(ship: HangarShip) -> bool: return ship.chassis_id == "drone"),
			"Starting fleet includes selected flagship, Transport, Fighter and ten Drones")
		check(state.fleet[0].formation == Vector2.ZERO and state.fleet[1].formation == Vector2(0, 1.1)
			and state.fleet[2].formation == Vector2(0, -1.25),
			"Starter formation centers flagship with forward Fighter and rear Transport")
		check(state.command_limit() == int(chassis.command) and state.used_command() == 15, "Selected command budget covers all starter escorts")
		budgets[int(chassis.command)] = true
		check(state.fleet.filter(func(ship: HangarShip) -> bool: return ship.flagship).size() == 1
			and state.get_deployed_fleet().size() == 13, "Exactly one mandatory flagship and all starter ships deploy")
		var fitted := 0
		for owned: HangarShip in state.fleet:
			fitted += owned.mounts.size()
			check(state.ship_loadout_id(owned.id) == ShipLoadouts.default_for(owned.chassis_id).id,
				"%s starts with its default loadout" % owned.chassis_id)
		check(state.equipment_inventory.size() == fitted, "Every starter equipment instance is fitted; there is no stock")
		var generators: int = state.fleet[0].mounts.values().filter(func(item: Dictionary) -> bool:
			return item.equipment_id == "shield_generator").size()
		check(state.fleet[0].get_stats().shields == (40 if chassis.id == "flagship_basic" else 20) + 20 * generators
			and state.can_deploy(), "Defensive flagship has doubled built-in shields; others retain one plus fitted generators")
		check(HangarCheckpoint.valid(state.hangar_snapshot()) and state.save_run_checkpoint()
			and state.load_run_checkpoint() and state.fleet[0].chassis_id == chassis.id, "Selected flagship roundtrips atomically")
		check(state.fleet[1].formation.is_equal_approx(Vector2(0, 1.1))
			and state.fleet[2].formation == Vector2(0, -1.25),
			"Continue retains starter formation positions")
		check(not state.buy_ship(chassis.id), "Cannot buy a second flagship")
		check(state.fleet[0].art_texture is CanvasTexture, "New flagship uses supplied mapped artwork")
		var simulation := BattleSimulation.new()
		var enemies: Array[RefCounted] = [AlienShip.threat_variant("fighter", 0)]
		check(simulation.setup_owned(state.get_deployed_fleet(), enemies, 0, 0, 351, state.battle_support_context()),
			"Selected flagship and all twelve escorts enter combat")
		simulation.player.shields = 0
		simulation._damage(simulation.player, state.fleet[0].hull_hp + 2, Vector2.ZERO, null, "Environment")
		simulation.advance(1.0 / 30.0)
		check(simulation.phase == BattleSimulation.Phase.DEFEAT and simulation.living_player_count() == 12,
			"Every flagship loss ends battle even with all twelve escorts alive")
	check(budgets.size() == 1 and budgets.has(24),
		"All flagship choices have room for the expanded starting fleet")
	var defensive := HangarShip.new()
	defensive.initialize_chassis("flagship_basic", 99, true)
	var ordinary := HangarShip.new()
	ordinary.initialize_chassis("flagship_science", 100, true)
	check(defensive.get_stats().shield_recharge == ordinary.get_stats().shield_recharge * 2
		and defensive.get_stats().weight - defensive.chassis.mass == 2 * (ordinary.get_stats().weight - ordinary.chassis.mass),
		"Two shield equivalents include doubled recharge and shield mass without stock copies")
	var invalid_catalog := {"version": 1, "chassis": SlotCatalog.chassis()}
	invalid_catalog.chassis[0].builtin_shield_count = 0
	check(not SlotCatalog.valid_chassis(invalid_catalog), "Invalid built-in shield count is rejected")
	check(state.start_new_run(1, 351, true, "flagship_basic"), "Restore a living run for transaction rollback checks")
	var before: Dictionary = state.hangar_snapshot()
	check(not state.start_new_run(1, 351, true, "transport") and state.hangar_snapshot() == before,
		"Invalid flagship cannot mutate existing run")
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/failed-new-run.json"
	check(not state.start_new_run(1, 351, true, "flagship_civic") and state.hangar_snapshot() == before,
		"Failed starting save rolls back credits, flagship and physical inventory")
	state.run_save_path = path
	await _test_fitting_views()
	_test_bonuses()
	await _test_carousel()
	print("Flagship selection: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_fitting_views() -> void:
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "SHIPS"
	root.add_child(screen)
	current_scene = screen
	for chassis: Dictionary in SlotCatalog.flagships():
		check(state.start_new_run(1, 351, true, chassis.id), "Initialize flagship fitting view")
		screen.selected_ship_id = state.fleet[0].id
		screen._refresh()
		for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = resolution
			await settle()
			var placed: Array[Rect2] = []
			for button: Button in screen.canvas.slot_buttons.values():
				var rect := button.get_global_rect()
				check(screen.canvas.get_global_rect().encloses(rect)
					and not placed.any(func(other: Rect2) -> bool: return rect.intersects(other)),
					"Selected flagship fitting targets remain within art canvas without overlap")
				placed.append(rect)
			check(root.get_visible_rect().encloses(screen.details_panel.get_global_rect()),
				"Flagship details fit supported viewport")
	screen.queue_free()
	await settle()

# Bonus fixtures isolate one part on the flagship (part removal is free).
func strip_flagship_except(keep: String) -> void:
	for slot_id: String in state.fleet[0].mounts.keys():
		if slot_id != keep:
			check(state.swap_part(state.fleet[0].id, slot_id, ""), "Strip flagship " + slot_id)

func _test_bonuses() -> void:
	check(state.start_new_run(1, 351, true, "flagship_offense"), "Combat bonus fixture")
	strip_flagship_except("port")
	var ship: HangarShip = state.fleet[0]
	var weapon := SlotCatalog.stats_for(ship.mounts.port.equipment_id).weapons[0]
	var stats := ship.get_stats()
	check(is_equal_approx(stats.weapons[0].fire_interval_seconds, weapon.fire_interval_seconds / 1.15)
		and stats.weapons[0].damage_per_shot == weapon.damage_per_shot, "Combat bonus improves rate, not per-shot damage")
	check(is_equal_approx(ship.weapon_cycle_rate(), 1.15), "Combat cycling baseline is +15 percent")
	var magazine := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
	magazine.type = ShipPart.Type.AMMUNITION_MAGAZINE
	ship._append_mount("test_magazine", Vector2.ZERO, magazine)
	check(is_equal_approx(ship.weapon_cycle_rate(), 1.35), "Combat rate stacks additively with magazine cycling")
	ship.rebuild_units()
	var sim := BattleSimulation.new()
	var enemies: Array[RefCounted] = [AlienShip.threat_variant("fighter", 0)]
	check(sim.setup_owned(state.get_deployed_fleet(), enemies, 0, 0, 351, state.battle_support_context()),
		"Flagship enters shared battle")
	var target := sim.player
	target.shields = 2
	var hull := ship.hull_hp
	sim._damage(target, 5, Vector2.ZERO, null, "Environment")
	check(target.shields == 0 and ship.hull_hp == hull - 2 and target.damage_taken == 4,
		"Shields absorb first, special armor reduces remaining hull damage by one")
	var damaged := ship.hull_hp
	sim._damage(target, 0.5, Vector2.ZERO, null, "Environment")
	check(ship.hull_hp == damaged, "Sub-one hits never heal or bypass flat armor")
	for source in ["Laser", "Seismic Cutter", "Collision"]:
		var hp := ship.hull_hp
		sim._damage(target, 10, Vector2.ZERO, null, source)
		check(ship.hull_hp == hp - 9, "Flat armor applies to all hull damage sources: " + source)
	var basic := HangarShip.new()
	basic.initialize_chassis("flagship_basic", 99, true)
	basic.damage_cell(Vector2i.ZERO, 5)
	check(basic.hull_hp == basic.hull_max - 4 and basic.chassis.name == "Defensive Flagship",
		"Defensive flagship shares one flat hull damage reduction and its new name")
	check(state.start_new_run(1, 351, true, "flagship_science"), "Research bonus fixture")
	strip_flagship_except("spine")
	check(state.swap_part(2, "port", "") and state.swap_part(2, "starboard", ""), "Isolate flagship production from starting Transport labs")
	var snapshot := ScienceRules.snapshot(state.get_deployed_fleet())
	check(ScienceRules.production_rate(snapshot) == 1.25 and ScienceRules.journey_rp(snapshot, 3) == 3.75,
		"Research flagship increases host lab output and retains fractions")
	check(ScienceRules.valid(snapshot, [1, 2, 3, 4]), "Research multiplier metadata validates")
	# Move the real lab to a compatible escort to verify host-scoped bonus.
	var escort := HangarShip.new()
	escort.initialize_chassis("drone", 5)
	escort.mounts.center = state.fleet[0].mounts.spine
	state.fleet.append(escort)
	state.fleet[0].mounts.erase("spine")
	state.fleet[0].rebuild_units()
	escort.rebuild_units()
	check(ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet())) == 1, "Research bonus does not follow labs onto escorts")
	check(ScienceRules.journey_rp(snapshot, 3) == 3.75, "Frozen departure snapshot retains host bonus after a transfer")
	check(state.start_new_run(1, 351, true, "flagship_civic"), "Civic bonus fixture")
	var data: Dictionary = state.hangar_snapshot()
	data.equipment["cargo"] = {"equipment_id": "cargo_hold", "load": {"kind": "cargo", "quantity": 10, "unit_value": 10}}
	data.ships[0].mounts.cargo = "cargo"
	data.equipment["cabin"] = {"equipment_id": "passenger_cabin", "load": {"kind": "passengers", "quantity": 4, "unit_value": 8}}
	data.ships[0].mounts.upper_port = "cabin"
	data.equipment["escort_cargo"] = {"equipment_id": "cargo_hold", "load": {"kind": "cargo", "quantity": 10, "unit_value": 10}}
	data.ships[1].mounts.center = "escort_cargo"
	var credits: int = data.credits
	HangarTrade.arrive(data, {"inhabited": true})
	check(data.credits == credits + 120 + 38 + 100 and data.score.credits_earned == 258,
		"Civic bonus increases only host cargo/passenger payouts and actual earned-credit score")
	HangarTrade.arrive(data, {"inhabited": true})
	check(data.credits == credits + 258, "Civic delivery cannot settle twice")

func _test_carousel() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu._on_play_pressed()
	await settle()
	var setup: Control = menu.game_setup
	check(setup.visible and setup.flagship_choices.size() == 4, "New Run opens four-option flagship carousel")
	var next: Button = setup.find_child("NextFlagship", true, false)
	var previous: Button = setup.find_child("PreviousFlagship", true, false)
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for index in range(4):
			setup.selected_flagship = index
			setup._update_flagship()
			await settle()
			var chassis: Dictionary = setup.flagship_choices[index]
			check(setup.flagship_preview.owned.chassis_id == chassis.id
				and setup.flagship_command.text == "Command Points %d" % chassis.command,
				"Carousel refreshes correct preview, command and stats")
			check(not setup.flagship_bonuses.source_text.contains("Built-in")
				and not setup.flagship_description.source_text.to_lower().contains("shield generator")
				and setup.find_child("FlagshipDetails", true, false).find_children("*", "ResourceText", true, false).all(
					func(text: ResourceText) -> bool: return not text.source_text.contains("Mounts:")),
				"Selector shows shields through stats without built-in or mount listings")
			check(root.get_visible_rect().encloses(setup.setup_modal.get_global_rect())
				and root.get_visible_rect().encloses(setup.start_button.get_global_rect()), "Selection modal and Start fit supported viewport")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.local/flagship-choice-%s-%d.png" % [chassis.id, resolution.x])
	setup.selected_flagship = 3
	next.pressed.emit()
	check(setup.selected_flagship == 0, "Next wraps carousel")
	previous.pressed.emit()
	check(setup.selected_flagship == 3, "Previous wraps carousel")
	var emitted := []
	setup.start_requested.disconnect(menu._on_start_run_requested)
	setup.start_requested.connect(func(difficulty: int, id: String) -> void: emitted.append([difficulty, id]))
	setup.start_button.pressed.emit()
	check(emitted == [[1, "flagship_offense"]], "Start carries both difficulty and selected flagship")
	setup.show_start_error("test save error")
	check(setup.status.visible and setup.status.text.contains("test save error"), "Setup surfaces save failure")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(root.get_visible_rect().encloses(setup.setup_modal.get_global_rect())
			and root.get_visible_rect().encloses(setup.start_button.get_global_rect()), "Save error never pushes Start outside viewport")
	setup.back_button.pressed.emit()
	check(not setup.visible and menu.menu_ui.visible, "Shared X cancels without creating a run")
	menu.queue_free()
	await settle()
