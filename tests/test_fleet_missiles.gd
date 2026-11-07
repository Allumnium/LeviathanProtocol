extends SceneTree

const Loadouts = preload("res://scripts/ship_loadouts.gd")
const Events = preload("res://scripts/expedition_events.gd")
const Travel = preload("res://scripts/expedition_state.gd")
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
	await create_timer(0.25).timeout
	for index in range(4):
		await process_frame

func click(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = motion.position
	press.global_position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	release.button_mask = 0
	root.push_input(release, true)
	await settle()

func fixture(supply: int) -> BattleSimulation:
	var ship := HangarShip.new()
	check(ship.initialize_chassis("corsair", 1), "Initialize missile test ship")
	ship.mounts.port = {"uid": "1", "equipment_id": "missile_rack", "rank": 1}
	ship.mounts.starboard = {"uid": "2", "equipment_id": "missile_rack", "rank": 1}
	ship.rebuild_units()
	ship.hull_hp = ship.hull_max
	var stats := ShipStats.new()
	stats.integrity = 10000
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Test gun", 10, 0.01, 1, 200))
	var enemy := AlienShip.new("Test", load(AlienShip.definition("core:scout").art), stats)
	var ships: Array[FleetShip] = [ship]
	var enemies: Array[RefCounted] = [enemy]
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, enemies, 0, 0, 73, {"credits_only": true, "missiles": supply}),
		"Initialize finite fleet missile supply")
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(100, 0)
	sim.aliens[0].integrity = 10000
	return sim

func combat() -> void:
	var sim := fixture(4)
	check(sim.player.stats.weapons.all(func(weapon: ShipWeaponStats) -> bool:
		return weapon.missiles_per_projectile == 1 and weapon.copy().missiles_per_projectile == 1),
		"Catalog and every copied fitted weapon retain missile cost")
	sim._update_ship(sim.player, 0.01)
	check(sim.projectiles.size() == 4 and sim.missile_supply == 0,
		"Multiple launchers share one fleet pool and fire a partial final salvo")
	var fired := sim.projectiles.size()
	sim._update_ship(sim.player, 10)
	check(sim.projectiles.size() == fired and sim.missile_supply == 0,
		"Empty launchers stop without underflow or free missiles")
	check(sim.authoritative_snapshot().missiles == 0
		and sim.event_log.filter(func(entry: Dictionary) -> bool: return entry.type == "missile_spent").size() == 4,
		"Replay state and deterministic events include exact consumption")
	sim = fixture(10)
	sim.aliens[0].position = Vector2(2000, 0)
	sim._update_ship(sim.player, 0.01)
	check(sim.missile_supply == 10 and sim.projectiles.is_empty(), "No ammunition spent without an in-range target")
	sim = fixture(0)
	var gun := SlotCatalog.stats_for("mini_turret").weapons[0].copy()
	gun.component_index = sim.player.stats.weapons[0].component_index
	sim.player.stats.weapons.append(gun)
	sim.player.cooldowns.append(0)
	sim._update_ship(sim.player, 0.01)
	check(not sim.projectiles.is_empty() and sim.projectiles.all(func(shot: BattleSimulation.Projectile) -> bool:
		return shot.weapon_name == "Mini Turret") and sim.missile_supply == 0,
		"Non-missile weapons still fire when the fleet supply is empty")
	sim = fixture(0)
	sim.aliens[0].stats.weapons = [SlotCatalog.stats_for("missile_rack").weapons[0]]
	sim.aliens[0].cooldowns = [0.0]
	sim._update_ship(sim.aliens[0], 0.01)
	check(sim.projectiles.size() == 5 and sim.missile_supply == 0, "Alien five-missile clusters never consume the player's pool")
	var replay_a := fixture(9)
	var replay_b := fixture(9)
	for tick in range(60):
		replay_a.advance(1.0 / 30)
		replay_b.advance(1.0 / 30)
	check(SaveValidation.same(replay_a.authoritative_snapshot(), replay_b.authoritative_snapshot())
		and replay_a.event_log == replay_b.event_log,
		"Finite-ammunition replay remains deterministic")
	var invalid := fixture(1)
	var ships: Array[FleetShip] = [invalid.player.owned_ship]
	var enemies: Array[RefCounted] = [invalid.aliens[0].alien]
	for supply: Variant in [-1, 1.5, NAN, INF, "5", null, 2147483648]:
		check(not invalid.setup_owned(ships, enemies, 0, 0, 1, {"missiles": supply}),
			"Reject malformed battle supply")

func persistence() -> void:
	check(state.start_new_run(1, 4242) and state.missiles == int(Content.get_def("run_start", "leviathan:charter").missiles),
		"New runs receive a finite initial supply")
	var initial: Dictionary = state.hangar_snapshot()
	for supply: Variant in [-1, 1.5, NAN, INF, "5", null, 2147483648]:
		var broken := initial.duplicate(true)
		broken.missiles = supply
		check(not HangarCheckpoint.valid(broken), "Reject malformed saved missile supply")
	var older := initial.duplicate(true)
	older.erase("missiles")
	check(HangarCheckpoint.valid(older), "Existing checkpoints without ammunition remain readable")
	state._apply_hangar(older)
	check(state.missiles == 0, "Loading an absent supply never fabricates ammunition")
	state._apply_hangar(initial)
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-ammo.json"
	check(not state.buy_missiles() and state.hangar_snapshot() == initial,
		"Failed ammunition purchase leaves credits, fleet and ammunition unchanged")
	state.run_save_path = path
	check(state.buy_missiles() and state.missiles == int(Content.get_def("run_start", "leviathan:charter").missiles) + state.missile_quote().count
		and state.credits == int(initial.credits) - state.missile_quote().price,
		"Station purchases add the quoted pack at the exact price")
	var committed: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(committed, state.hangar_snapshot()),
		"Purchased ammunition persists across Continue")
	state.credits = 0
	check(not state.buy_missiles() and not state.last_save_error.is_empty(),
		"Unaffordable purchases fail explicitly")
	state.credits = -1
	check(not state.buy_missiles(), "Credit debt cannot buy ammunition")
	state.credits = 100
	state.missiles = 2147483647
	var overflow: Dictionary = state.hangar_snapshot()
	check(not state.buy_missiles() and state.hangar_snapshot() == overflow
		and state.last_save_error.contains("limit"), "Storage overflow fails without charging credits")
	state.missiles = 10
	check(state.depart_expedition("refuel_station_1"), "Leave dock")
	check(not state.buy_missiles() and state.last_save_error.contains("Dock"),
		"Passing stations or flying cannot buy ammunition")
	for phase: int in [BattleSimulation.Phase.VICTORY, BattleSimulation.Phase.DEFEAT, BattleSimulation.Phase.WITHDRAWN]:
		check(state.start_new_run(1, 4242), "Start settlement fixture")
		state.expedition_simulation.state.flags.merge({"meridian_incident": true, "meridian_reported": true})
		state.expedition_simulation.state.pending_event_id = "distress_call"
		state.expedition_simulation.state.pause_reasons.append(Travel.PauseReason.ENCOUNTER)
		check(state.resolve_expedition_event("distress_call", "defend"), "Admit settlement battle")
		var sim := BattleSimulation.new()
		check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
			state.battle_simulation_seed(), state.battle_support_context()), "Deployment receives saved supply")
		sim.battle_id = state.battle_identity()
		sim.phase = phase
		sim.missile_supply -= 7
		var before: Dictionary = state.hangar_snapshot()
		state.run_save_path = "res://project.godot/no-ammo.json"
		check(not state.settle_battle(sim) and state.hangar_snapshot() == before,
			"Failed settlement retains live supply for a safe retry")
		state.run_save_path = path
		check(state.settle_battle(sim) and state.missiles == int(Content.get_def("run_start", "leviathan:charter").missiles) - 7,
			"Victory, defeat and withdrawal each settle spent missiles exactly once")
		check(not state.settle_battle(sim) and state.missiles == int(Content.get_def("run_start", "leviathan:charter").missiles) - 7,
			"Duplicate settlement cannot consume twice")
		check(state.load_run_checkpoint() and state.missiles == int(Content.get_def("run_start", "leviathan:charter").missiles) - 7,
			"Outcome ammunition survives Continue")
		if phase != BattleSimulation.Phase.VICTORY:
			check(not state.expedition_simulation.state.event_receipts.has("distress_call"),
				"Retryable arrival combat keeps spent ammunition")
			state.expedition_simulation.state.pending_event_id = "distress_call"
			state.expedition_simulation.state.pause_reasons.append(Travel.PauseReason.ENCOUNTER)
			check(state.resolve_expedition_event("distress_call", "defend")
				and state.battle_support_context().missiles == int(Content.get_def("run_start", "leviathan:charter").missiles) - 7,
				"Re-entering the encounter uses the reduced saved supply")
	for malformed: Variant in [-1, 1.5, INF, "3"]:
		check(not Events.valid_rewards({"missiles": malformed}), "Reject malformed salvage ammunition")

func interface() -> void:
	check(state.start_new_run(1, 4242), "Start ammunition UI")
	root.size = Vector2i(1280, 720)
	state.pending_intro = false
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	for viewport: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport
		for tab: String in ["MAP", "FLEET", "SHIPS"]:
			screen.active_tab = tab
			screen._refresh()
			await settle()
			check(screen.missile_readout.text == "MISSILES %d" % state.missiles
				and screen.get_global_rect().encloses(screen.missile_readout.get_global_rect()),
				"Exact supply fits %s at %s" % [tab, viewport])
			check(screen.missile_buy_button.visible
				and screen.get_global_rect().encloses(screen.missile_buy_button.get_global_rect())
				and not screen.missile_buy_button.get_global_rect().intersects(screen.travel_fuel.get_global_rect()),
				"Docked pack action fits without fuel overlap")
			var price_text := screen.missile_buy_button.get_node("ResourceText") as ResourceText
			check(price_text.get_line_count() == 1, "Pack quantity and exact credit price stay on one line")
			if DisplayServer.get_name() != "headless" and viewport == Vector2i(640, 360) and tab == "MAP":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.local/missiles-map-640.png")
	var before: int = state.missiles
	await click(screen.missile_buy_button)
	check(state.missiles == before + state.missile_quote().count
		and screen.missile_readout.text == "MISSILES %d" % state.missiles, "Purchase refreshes the exact supply")
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-ammo.json"
	before = state.missiles
	screen._on_buy_missiles_pressed()
	check(state.missiles == before and not screen.expedition_status_override.is_empty()
		and Travel.PauseReason.SAVE_ERROR in state.expedition_simulation.state.pause_reasons,
		"Failed UI purchase reports the error and exposes save retry without success")
	state.run_save_path = path
	screen._on_expedition_retry_pressed()
	check(state.depart_expedition("refuel_station_1"), "Leave UI dock")
	screen._refresh_expedition_controls()
	check(not screen.missile_buy_button.visible and screen.missile_readout.visible,
		"Departure hides purchase, not the supply instrument")
	screen.queue_free()
	await settle()
	check(state.start_new_run(1, 4242), "Start salvage choice layout")
	state.pending_intro = false
	state.expedition_simulation.state.pending_event_id = "derelict_salvage"
	state.expedition_simulation.state.pause_reasons.append(Travel.PauseReason.ENCOUNTER)
	screen = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	for viewport: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport
		await settle()
		var panel: Control = screen.encounter_modal.find_child("EncounterPanel", true, false)
		check(screen.get_global_rect().encloses(panel.get_global_rect()),
			"Salvage choice with exact fuel and ammunition rewards fits at %s" % viewport)
	screen.queue_free()
	await settle()
	check(state.start_new_run(1, 4242), "Start battle supply instrument")
	state.missiles = 0
	state.expedition_simulation.state.flags.merge({"meridian_incident": true, "meridian_reported": true})
	state.expedition_simulation.state.pending_event_id = "distress_call"
	state.expedition_simulation.state.pause_reasons.append(Travel.PauseReason.ENCOUNTER)
	check(state.resolve_expedition_event("distress_call", "defend"), "Admit instrument battle")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	battle.set_process(false)
	await settle()
	check(battle.simulation.initial_missiles == 0, "Frozen setup receives the empty saved supply")
	for viewport: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport
		battle.pause_button.set_pressed_no_signal(false)
		battle._physics_process(0)
		await settle()
		check(battle.missile_readout.text == "MISSILES 0"
			and battle.get_global_rect().encloses(battle.missile_readout.get_global_rect())
			and (not battle.battle_speed_controls.is_visible_in_tree()
				or not battle.missile_readout.get_global_rect().intersects(battle.battle_speed_controls.get_global_rect()))
			and not battle.missile_readout.get_global_rect().intersects(battle.get_node("SettingsButton").get_global_rect()),
			"Battle empty-supply readout fits without speed overlap at %s" % viewport)
		if DisplayServer.get_name() != "headless" and viewport == Vector2i(640, 360):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/missiles-battle-640.png")
	battle.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://fleet-missiles.json"
	combat()
	persistence()
	await interface()
	print("FLEET MISSILES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
