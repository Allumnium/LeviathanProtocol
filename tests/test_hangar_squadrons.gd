extends SceneTree

const Loadouts = preload("res://scripts/ship_loadouts.gd")
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
	await create_timer(0.2).timeout
	for index in range(4):
		await process_frame

func pointer(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func click(button: Button) -> void:
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(button)
	await settle()
	await pointer(button.get_global_rect().get_center(), true)
	await pointer(button.get_global_rect().get_center(), false)
	await settle()

func group(chassis: String) -> Dictionary:
	for squadron: Dictionary in state.squadrons:
		if squadron.chassis == chassis:
			return squadron
	return {}

func persistence() -> void:
	check(state.start_new_run(1, 7701), "Start squadron fixture")
	var initial: Dictionary = state.hangar_snapshot()
	check(HangarCheckpoint.valid(initial) and initial.squadrons.size() == 3, "Initial homogeneous squadrons cover the fleet")
	check(group("fighter").members == [3, 4] and group("fighter").stance == "seek"
		and group("fighter").overrides.is_empty(), "Starter fighters share the default squadron")
	check(Vector2(group("fighter").formation[0], group("fighter").formation[1]) == Vector2(0, -1.25),
		"Squadron anchor is the existing formation centroid")
	var older := initial.duplicate(true)
	older.erase("squadrons")
	check(HangarCheckpoint.valid(older), "Older physical checkpoints remain readable")
	state._apply_hangar(older)
	check(SaveValidation.same(initial, state.hangar_snapshot()), "Legacy grouping preserves equipment, health, loads and positions")
	var gid: int = group("fighter").id
	check(state.set_squadron_stance(gid, "defend") and state.owned_ship(3).stance == "defend"
		and state.owned_ship(4).squadron_id == gid, "Saved orders apply to every member")
	var ordered: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(ordered, state.hangar_snapshot())
		and state.owned_ship(4).stance == "defend", "Continue restores squadron orders")
	check(state.refit_ship(3, "striker") and group("fighter").overrides.size() == 1, "Individual refit records an override")
	check(state.load_run_checkpoint() and state.refit_ship(3, "interceptor")
		and group("fighter").overrides.is_empty(), "Round-tripped override clears when default is restored")
	check(state.swap_part(3, "fore", "") and state.load_run_checkpoint(), "Custom mount change persists")
	state.credits = 10000
	check(state.buy_ship("drone") and HangarCheckpoint.valid(state.hangar_snapshot()),
		"Purchase preserves round-tripped custom overrides")
	var drone_id: int = state.fleet.back().id
	check(group("drone").members == [drone_id] and state.salvage_hangar_ship(drone_id)
		and group("drone").is_empty(), "Salvaging last member removes its squadron")
	check(state.move_ships({3: Vector2(-2, -2), 4: Vector2(2, 0)})
		and SaveValidation.same(group("fighter").formation, [0, -1]), "Movement saves the group anchor atomically")
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-squadron.json"
	check(not state.set_squadron_stance(gid, "evade")
		and SaveValidation.same(before, state.hangar_snapshot()), "Failed order save changes no live state")
	check(not state.move_ships({3: Vector2.ZERO}) and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed formation save preserves membership and anchor")
	state.run_save_path = path
	check(not state.set_squadron_stance(gid, "unknown") and not state.set_squadron_stance(999, "seek"),
		"Invalid squadron orders fail explicitly")
	for field: String in ["id", "name", "chassis", "stance", "loadout", "formation", "members", "overrides"]:
		var broken := initial.duplicate(true)
		broken.squadrons[0].erase(field)
		check(not HangarCheckpoint.valid(broken), "Reject missing squadron " + field)
	for value: Variant in [null, {}, "squadron", 5]:
		var broken := initial.duplicate(true)
		broken.squadrons = value
		check(not HangarCheckpoint.valid(broken), "Reject malformed squadron collection")
	for value: Variant in [null, [], 4, "squadron"]:
		var broken := initial.duplicate(true)
		broken.squadrons[0] = value
		check(not HangarCheckpoint.valid(broken), "Reject malformed squadron entry")
	var mutations: Array[Dictionary] = [
		{"id": 0}, {"id": 1.5}, {"name": ""}, {"name": "x".repeat(41)},
		{"stance": "attack"}, {"chassis": "fighter"}, {"loadout": "missing"},
		{"members": []}, {"members": [1, 1]}, {"members": [999]}, {"members": [2]},
		{"overrides": [1]}, {"overrides": [1, 1]}, {"overrides": ["1"]}, {"formation": [0, 100]}]
	for mutation: Dictionary in mutations:
		var broken := initial.duplicate(true)
		broken.squadrons[0].merge(mutation, true)
		check(not HangarCheckpoint.valid(broken), "Reject invalid squadron " + str(mutation))
	var broken := initial.duplicate(true)
	broken.squadrons.remove_at(0)
	check(not HangarCheckpoint.valid(broken), "Reject missing fleet membership")
	broken = initial.duplicate(true)
	broken.squadrons.append(broken.squadrons[0].duplicate(true))
	check(not HangarCheckpoint.valid(broken), "Reject duplicate squadron identity and ownership")

func fixture(stance: String, carrier := false) -> BattleSimulation:
	var flagship := HangarShip.new()
	flagship.initialize_chassis("flagship_basic", 1, true)
	flagship.stance = stance
	if carrier:
		flagship.mounts.spine = {"uid": "2", "equipment_id": "flight_deck", "rank": 1}
	flagship.rebuild_units()
	var fighter := HangarShip.new()
	fighter.initialize_chassis("fighter", 2)
	fighter.mounts.fore = {"uid": "1", "equipment_id": "mini_turret", "rank": 1}
	fighter.rebuild_units()
	fighter.hull_hp = fighter.hull_max
	fighter.stance = stance
	fighter.squadron_id = 2
	var stats := ShipStats.new()
	stats.integrity = 10000
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Test gun", 10, 0.01, 1, 200))
	var enemy := AlienShip.new("Test", AlienShip.SCOUT_TEXTURE, stats)
	var ships: Array[FleetShip] = [flagship, fighter]
	var enemies: Array[RefCounted] = [enemy]
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, enemies, 0, 0, 7701, {"credits_only": true, "missiles": 30}), "Set up stance combat")
	sim.players[0].position = Vector2.ZERO
	sim.players[1].position = Vector2(-60, 0)
	sim.players[1].heading = 0
	sim.aliens[0].position = Vector2(100, 0)
	return sim

func actions() -> void:
	check(state.start_new_run(1, 7702), "Start group-action fixture")
	state.credits = 10000
	var gid: int = group("fighter").id
	check(state.refit_ship(3, "striker") and state.refit_squadron(gid, "escort"),
		"Squadron changes its default loadout")
	check(state.ship_loadout_id(3) == "striker" and state.ship_loadout_id(4) == "escort"
		and group("fighter").loadout == "escort" and group("fighter").overrides == [3],
		"Group refit preserves explicit per-ship overrides")
	var price := Loadouts.ship_price("fighter", Loadouts.find("fighter", "escort")) * 2
	var credits: int = state.credits
	var generation: int = state.hangar_generation
	check(state.buy_ships("fighter", 2, gid) and state.fleet.size() == 6 and state.credits == credits - price
		and state.hangar_generation == generation + 1, "Buy N charges one exact quote in one atomic save")
	check(state.ship_loadout_id(5) == "escort" and state.ship_loadout_id(6) == "escort"
		and group("fighter").members == [3, 4, 5, 6] and group("fighter").overrides == [3],
		"Bought ships inherit the selected squadron default with unique equipment")
	check(HangarCheckpoint.valid(state.hangar_snapshot()), "Bulk fitted purchase maintains unique ownership")
	check(state.set_squadron_stance(gid, "defend") and state.assign_squadron(3),
		"Split an individual ship into a new same-class squadron")
	var split := HangarSquadrons.for_ship(state.squadrons, 3)
	var split_id: int = split.id
	check(split_id != gid and split.members == [3] and split.stance == "defend" and split.loadout == "escort"
		and split.overrides == [3], "Split preserves orders, actual fit and override")
	check(not state.assign_squadron(2, gid) and not state.assign_squadron(3, 999)
		and not state.assign_squadron(3, split_id), "Reject incompatible, unknown and unchanged assignments")
	check(state.assign_squadron(3, gid) and HangarSquadrons.find(state.squadrons, split_id).is_empty()
		and state.owned_ship(3).stance == "defend", "Rejoin removes the empty group and restores inherited orders")
	state.owned_ship(3).hull_hp -= 11.25
	state.owned_ship(4).hull_hp -= 20.25
	var cost: int = state.squadron_repair_cost(gid)
	credits = state.credits
	generation = state.hangar_generation
	check(cost == 33 and state.repair_squadron(gid) and state.credits == credits - cost
		and state.hangar_generation == generation + 1
		and state.owned_ship(3).hull_hp == state.owned_ship(3).hull_max
		and state.owned_ship(4).hull_hp == state.owned_ship(4).hull_max,
		"Group repair quotes summed rounded hull damage and commits once")
	check(state.refit_squadron(gid, "escort", true) and group("fighter").overrides.is_empty()
		and state.ship_loadout_id(3) == "escort", "Reset overrides explicitly refits every member")
	for count: Variant in [0, -1, 1.5, "2", null, INF, 2147483648]:
		var before: Dictionary = state.hangar_snapshot()
		check(not state.buy_ships("fighter", count, gid) and SaveValidation.same(before, state.hangar_snapshot()),
			"Invalid quantity changes no resources or ownership")
	var before: Dictionary = state.hangar_snapshot()
	check(not state.buy_ships("fighter", 12, gid) and SaveValidation.same(before, state.hangar_snapshot()),
		"Bulk command overflow rejects the entire purchase")
	state.credits = 0
	before = state.hangar_snapshot()
	check(not state.buy_ships("fighter", 2, gid) and SaveValidation.same(before, state.hangar_snapshot()),
		"Bulk affordability checks the complete quote")
	check(state.refit_squadron(gid, "interceptor") and state.credits == 0, "Group refits remain free at zero credits")
	state.credits = 10000
	state.owned_ship(4).hull_hp -= 10
	before = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-group.json"
	check(not state.refit_squadron(gid, "striker") and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed group refit leaves default, IDs, fits, hull and credits unchanged")
	check(not state.buy_ships("fighter", 2, gid) and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed bulk purchase rolls back every new ID and ownership change")
	check(not state.repair_squadron(gid) and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed group repair preserves all damage and credits")
	check(not state.assign_squadron(3) and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed assignment preserves complete membership and anchors")
	state.run_save_path = path
	check(state.refit_squadron(gid, "striker") and state.load_run_checkpoint()
		and group("fighter").loadout == "striker" and group("fighter").overrides.is_empty(),
		"Complete group defaults and membership survive Continue")
	# Cargo on an unchanged hold survives a group refit.
	var transport: HangarShip = state.owned_ship(2)
	transport.mounts.hold["load"] = {"kind": "cargo", "quantity": 10, "unit_value": 3, "origin": 0}
	var transport_gid: int = group("transport").id
	check(state.refit_squadron(transport_gid, "tender") and HangarTrade.has_load(state.owned_ship(2).mounts.hold),
		"Group refit never replaces a retained occupied hold")
	# A later occupied mount rejects earlier staged weapon changes too.
	check(state.swap_part(1, "spine", "passenger_cabin"), "Fit a cabin override")
	state.owned_ship(1).mounts.spine["load"] = {"kind": "passengers", "quantity": 4, "unit_value": 3, "origin": 0}
	before = state.hangar_snapshot()
	check(not state.refit_squadron(int(group("flagship_basic").id), "gunline", true) and state.last_save_error.contains("Deliver")
		and SaveValidation.same(before, state.hangar_snapshot()), "Loaded mount rolls back all earlier staged refits")
	var bars := ShipStatBars.new()
	root.add_child(bars)
	var ships: Array[HangarShip] = [state.owned_ship(3), state.owned_ship(4)]
	ships[0].hull_hp -= 15
	bars.set_squadron(ships)
	check(is_equal_approx(bars.bars.hull.value,
		100 * (ships[0].hull_hp + ships[1].hull_hp) / (ships[0].hull_max + ships[1].hull_max)),
		"Squadron hull bar uses summed current/max integrity, including partial damage")
	ships.assign([state.owned_ship(1), state.owned_ship(2)])
	bars.set_squadron(ships)
	var readouts: Array[String] = []
	for label: Node in bars.find_children("*", "RichTextLabel", true, false):
		readouts.append(label.source_text)
	check("Cargo 10 / 10" in readouts and "Passengers 4 / 4" in readouts,
		"Squadron transport readouts sum real loads without losing per-instance ownership")
	bars.queue_free()

func combat() -> void:
	var sim := fixture("seek")
	var fighter: BattleSimulation.Combatant = sim.players[1]
	sim._update_ship(fighter, 0.1)
	check(fighter.target == sim.aliens[0] and not sim.projectiles.is_empty(), "Seek retains automatic targeting and firing")
	sim = fixture("defend")
	fighter = sim.players[1]
	sim.aliens[0].position = Vector2(400, 0)
	sim._update_ship(fighter, 0.1)
	check(fighter.target == null and sim.projectiles.is_empty(), "Defenders ignore enemies beyond flagship guard radius")
	sim.aliens[0].position = Vector2(100, 0)
	fighter.target_refresh_remaining = 0
	sim._update_ship(fighter, 0.1)
	check(fighter.target == sim.aliens[0] and not sim.projectiles.is_empty(), "Defenders engage nearby flagship threats")
	sim = fixture("defend")
	fighter = sim.players[1]
	fighter.position = Vector2(300, 0)
	fighter.heading = PI
	sim.aliens[0].position = Vector2(600, 0)
	for tick in range(60):
		sim._update_ship(fighter, 1.0 / 30)
	check(fighter.position.x < 260 and fighter.target == null, "Idle defenders return toward their flagship formation anchor")
	sim = fixture("defend")
	fighter = sim.players[1]
	fighter.position = Vector2(400, 0)
	fighter.heading = PI
	for tick in range(60):
		sim._update_ship(fighter, 1.0 / 30)
	check(fighter.target == sim.aliens[0] and fighter.position.x < 360,
		"Defenders intercept nearby flagship threats rather than remaining at a distant anchor")
	sim = fixture("evade")
	fighter = sim.players[1]
	fighter.heading = PI
	for tick in range(60):
		sim._update_ship(fighter, 1.0 / 30)
	check(fighter.position.x < -90 and fighter.target == null and sim.projectiles.is_empty()
		and sim.missile_supply == 30, "Evade moves away from visible enemies without firing or expenditure")
	check(sim.request_attack(fighter.entity_id, sim.aliens[0].entity_id), "Manual attack can override passive stance")
	fighter.position = Vector2(-60, 0)
	fighter.heading = 0
	sim._update_ship(fighter, 0.1)
	check(fighter.target == sim.aliens[0] and not sim.projectiles.is_empty(), "Explicit attack fires despite Evade")
	sim.aliens[0].integrity = -1
	sim._update_ship(fighter, 0.1)
	check(fighter.commanded_target == null and fighter.target == null, "Dead manual target immediately restores Evade")
	sim = fixture("evade")
	fighter = sim.players[1]
	fighter.heading = PI
	var velocity := fighter.velocity
	var heading := fighter.heading
	sim._update_ship(fighter, 0.1)
	var acceleration := fighter.velocity - velocity * exp(-sim.PASSIVE_DRAG_PER_SECOND * 0.1)
	check(absf(acceleration.cross(Vector2.from_angle(fighter.heading))) < 0.01
		and absf(angle_difference(heading, fighter.heading)) <= fighter.turn_rate * 0.1 + 0.001,
		"Stance movement retains forward thrust and bounded turning")
	check(sim.authoritative_snapshot().actors.any(func(actor: Dictionary) -> bool:
		return actor.get("stance") == "evade" and actor.get("squadron") == 2),
		"Authoritative replay captures squadron orders")
	sim = fixture("evade", true)
	sim.doctrines.carriers.advance(sim, 0.1)
	check(sim.doctrines.carriers.sorties.is_empty() and sim.doctrines.pool.carriers["2"].spent == 0,
		"Evade never spends carrier replacements")
	check(sim.request_attack(sim.players[0].entity_id, sim.aliens[0].entity_id), "Manual carrier attack is accepted")
	sim.doctrines.carriers.advance(sim, 0.1)
	check(sim.doctrines.carriers.sorties.size() == 1, "Manual attack can deliberately launch an evading carrier's craft")
	sim = fixture("defend", true)
	sim.aliens[0].position = Vector2(400, 0)
	sim.doctrines.carriers.advance(sim, 0.1)
	check(sim.doctrines.carriers.sorties.is_empty(), "Defending carrier holds its sorties for nearby threats")
	sim.aliens[0].position = Vector2(100, 0)
	sim.doctrines.carriers.advance(sim, 0.1)
	check(sim.doctrines.carriers.sorties.size() == 1, "Defending carrier launches against a flagship threat")
	if not sim.doctrines.carriers.sorties.is_empty():
		var craft: BattleSimulation.Combatant = sim.doctrines.carriers.sorties[0].actor
		sim.aliens[0].position = Vector2(400, 0)
		check(not sim._auto_candidate(craft, sim.aliens[0]), "Defensive sorties cannot pursue threats outside the guard radius")

func ui() -> void:
	check(state.start_new_run(1, 7703), "Start squadron UI fixture")
	state.credits = 10000
	var gid: int = group("fighter").id
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	screen.active_tab = "FLEET"
	screen.selected_ship_id = 0
	screen._refresh()
	await settle()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		await click(screen.roster.find_child("Squadron_%d" % gid, true, false))
		check(screen.formation_view.selected_ids == [3, 4], "Roster selects a whole squadron at " + str(resolution))
		var roster_scroll: ScrollContainer = screen.roster.get_parent()
		check(screen.roster.size.x <= roster_scroll.size.x + 1 and roster_scroll.scroll_horizontal == 0,
			"Squadron roster has no horizontal clipping at " + str(resolution))
		for squadron: Dictionary in state.squadrons:
			var card: Button = screen.roster.find_child("Squadron_%d" % squadron.id, true, false)
			check(card.icon != null and not card.text.contains(squadron.name),
				"Squadron roster identifies class with artwork, not repeated long names")
		var stance: Button = screen.details.find_child("Stance_defend", true, false)
		check(stance != null and stance.focus_mode == Control.FOCUS_NONE and stance.tooltip_text.is_empty(),
			"Squadron commands have no tooltips or keyboard focus")
		for button: Node in screen.details.find_children("*", "Button", true, false):
			check(button.size.x <= screen.details_panel.size.x
				and button.get_minimum_size().x <= screen.details.size.x + 1,
				"Squadron command fits panel width: %s at %s" % [button.name, resolution])
		await click(stance)
		check(group("fighter").stance == "defend", "Pointer applies squadron stance at " + str(resolution))
		await click(screen.details.find_child("Stance_seek", true, false))
		check(group("fighter").stance == "seek", "Pointer restores Seek at " + str(resolution))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/squadrons-fleet-%d.png" % resolution.x)
	root.size = Vector2i(1280, 720)
	await settle()
	await click(screen.details.find_child("SquadronLoadout_striker", true, false))
	check(group("fighter").loadout == "striker" and state.ship_loadout_id(3) == "striker"
		and state.ship_loadout_id(4) == "striker", "Pointer refits the selected block")
	await click(screen.details.find_child("BuyMore", true, false))
	check(screen.squadron_buy_count == 2, "Pointer changes buy quantity")
	var generation: int = state.hangar_generation
	await click(screen.details.find_child("SquadronBuy", true, false))
	check(group("fighter").members.size() == 4 and state.hangar_generation == generation + 1,
		"Pointer buys N fitted members with one commit")
	check(screen.formation_view.selected_ids.size() == 4, "Refresh expands block selection to new members")
	check(state.start_new_run(1, 7704), "Reset formation fixture")
	await settle()
	screen._select_squadron(gid)
	await settle()
	var board: Control = screen.formation_view
	board.camera = Vector2(12, -5)
	board.zoom = 1.3
	var camera: Vector2 = board.camera
	var zoom: float = board.zoom
	var owned: HangarShip = state.owned_ship(3)
	var point: Vector2 = board.point(owned)
	var rect: Rect2 = board.ship_rect(owned)
	if board._hit(point) != 3:
		for y in range(int(rect.position.y), int(rect.end.y)):
			for x in range(int(rect.position.x), int(rect.end.x)):
				if board._hit(Vector2(x, y)) == 3:
					point = Vector2(x, y)
					break
			if board._hit(point) == 3:
				break
	check(board._hit(point) == 3, "Formation pointer hits actual fighter art")
	generation = state.hangar_generation
	await pointer(board.global_position + point, true)
	var motion := InputEventMouseMotion.new()
	motion.position = board.global_position + point + Vector2(0, 33.8)
	motion.relative = Vector2(0, 33.8)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await pointer(motion.position, false)
	await settle()
	check(state.hangar_generation == generation + 1 and is_equal_approx(state.owned_ship(3).formation.y, -0.75)
		and is_equal_approx(state.owned_ship(4).formation.y, -0.75)
		and state.owned_ship(4).formation - state.owned_ship(3).formation == Vector2(2.5, 0),
		"Real block drag preserves spacing and saves once")
	check(screen.formation_view.camera == camera and screen.formation_view.zoom == zoom,
		"Block move refresh preserves pan and zoom")
	check(state.load_run_checkpoint() and SaveValidation.same(group("fighter").formation, [0, -0.75]),
		"Block anchor persists after Continue")
	await settle()
	board = screen.formation_view
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-block.json"
	point = board.point(state.owned_ship(3))
	await pointer(board.global_position + point, true)
	motion = InputEventMouseMotion.new()
	motion.position = board.global_position + point + Vector2(0, 20)
	motion.relative = Vector2(0, 20)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await pointer(motion.position, false)
	await settle()
	check(SaveValidation.same(before, state.hangar_snapshot()) and not screen.feedback.text.is_empty(),
		"Failed real block drag reports the save failure and restores every position")
	state.run_save_path = path
	board = screen.formation_view
	var empty: Vector2 = board.global_position + board.size - Vector2(12, 12)
	await pointer(empty, true)
	await pointer(empty, false)
	await settle()
	check(screen.formation_view.selected_ids.is_empty() and screen.selected_ship_id == 0,
		"Empty-space click deselects the squadron")
	board = screen.formation_view
	rect = board.ship_rect(state.owned_ship(3)).grow(2)
	await pointer(board.global_position + rect.position, true)
	motion = InputEventMouseMotion.new()
	motion.position = board.global_position + rect.end
	motion.relative = rect.size
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await pointer(motion.position, false)
	await settle()
	check(screen.formation_view.selected_ids == [3, 4], "Box selection expands one member into a whole squadron")
	screen._open_ship_editor(3)
	await settle()
	await click(screen.refit_panel.find_child("SplitSquadron", true, false))
	var split_id: int = HangarSquadrons.for_ship(state.squadrons, 3).id
	check(split_id != gid, "Ships pointer splits a member without moving it")
	await click(screen.refit_panel.find_child("JoinSquadron_%d" % gid, true, false))
	check(HangarSquadrons.for_ship(state.squadrons, 3).id == gid, "Ships pointer rejoins a compatible squadron")
	screen.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://squadrons-test.json"
	persistence()
	actions()
	combat()
	await ui()
	print("SQUADRONS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
