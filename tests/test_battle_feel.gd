extends "res://tests/test_equipment_balance.gd"

const Loadouts = preload("res://scripts/ship_loadouts.gd")

var audit: Dictionary = {"formations": [], "abilities": {}, "progression": {}}
var state: Node
var meters_completed := false

func settle() -> void:
	for frame in range(5):
		await process_frame

func capture(label: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://" + label + ".png") == OK, "Capture " + label)

func missiles() -> void:
	var sim := setup([owned(["missile_rack"])])
	sim._update_ship(sim.player, 0.01)
	check(sim.projectiles.size() == 5 and sim.missile_supply == 25, "Five physical missiles spend five ammo")
	var origins := {}
	for shot in sim.projectiles:
		origins[shot.origin] = true
		check(shot.damage == 12 and shot.interceptable and shot.speed == 200, "Each cluster member retains damage, interception and guidance speed")
	check(origins.size() == 5, "Five missiles launch from distinct positions")
	check(is_equal_approx(sim.player.cooldowns[0], 8), "Cluster starts an eight-second cooldown")
	sim._update_ship(sim.player, 7.98)
	check(sim.projectiles.size() == 5, "No second cluster before cooldown")
	sim._update_ship(sim.player, 0.03)
	check(sim.projectiles.size() == 10 and sim.missile_supply == 20, "Next cooldown releases another five missiles")
	sim = setup([owned(["missile_rack"])])
	sim.missile_supply = 2
	sim._update_ship(sim.player, 0.01)
	check(sim.projectiles.size() == 2 and sim.missile_supply == 0, "Partial final cluster spends remaining ammo only")
	sim._update_ship(sim.player, 9)
	check(sim.projectiles.size() == 2, "Empty rack cannot fire")
	sim = setup([owned(["missile_rack"])])
	sim._update_ship(sim.player, 0.01)
	for tick in range(120):
		sim._update_projectiles(1.0 / 60)
	check(is_equal_approx(sim.player.damage_dealt, 60), "Five guided physical hits deliver the 60-damage burst")
	var defender := sim.aliens[0]
	sim = setup([owned(["missile_rack"])])
	sim._update_ship(sim.player, 0.01)
	defender = sim.aliens[0]
	defender.tags["interceptor"] = true
	check(SharedSupport.intercept(sim, defender, ShipWeaponStats.new("Interception", 1, 1, 1, 500), defender.position)
		and sim.projectiles.size() == 4 and sim.missile_supply == 25, "Interception removes one real missile without refund")
	sim = setup([owned(["missile_rack"], 1, ["guided_munitions", "siege_i", "siege_ii"])], 0, false, {"splinter_missiles": true})
	sim._update_ship(sim.player, 0.01)
	for shot in sim.projectiles.duplicate():
		shot.position = shot.target.position - Vector2(20, 0)
		check(sim.research_combat.split(sim, shot), "Cluster parents retain splitting research")
		sim.projectiles.erase(shot)
	check(sim.projectiles.size() == 15 and sim.missile_supply == 25, "Five parents produce fifteen fragments without extra ammo")

func ability_audit() -> void:
	var active: Array[String] = []
	for node: Dictionary in HangarResearch.view_registry().research:
		for id: String in node.grants.ability_ids:
			if id not in active:
				active.append(id)
	check(active == ["ion_pulse"], "Ion Pulse is the only active research-granted ability")
	var sim := setup([owned(["ion_emitter"])], 100)
	check(sim.abilities.configure({"ability_ids": ["ion_pulse"]}), "Configure synthetic earned-ability audit")
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(500, 0)
	var ability := GameDefinitions.find("abilities", "ion_pulse")
	var weapon: ShipWeaponStats = sim.player.stats.weapons[0]
	check(weapon.range_units > ability.range_units, "Weapon reach exceeds active ability reach")
	check(not sim.abilities.can_cast(sim, "ion_pulse", sim.aliens[0].position), "Long weapon range does not grant a long-range pulse")
	sim.aliens[0].position = Vector2(150, 0)
	sim.doctrines.charges["audit"] = {"source": sim.aliens[0].entity_id}
	check(sim.abilities.cast(sim, "ion_pulse", sim.aliens[0].position), "Close pulse can cast")
	check(sim.doctrines.charges.is_empty() and sim.abilities.suppressed(sim.aliens[0]), "Pulse interrupts charge and suppresses recovery")
	check(sim.player.damage_dealt == 0 and sim.abilities.remaining("ion_pulse") == 24, "Pulse deals no damage and uses a fleet cooldown")
	audit.abilities = {"research_granted": active, "pulse_range": ability.range_units,
		"emitter_range": weapon.range_units, "cooldown": 24, "suppression_seconds": 4,
		"note": "Synthetic earned-ability probe; no research was granted in the natural opening."}

func opening() -> void:
	check(state.start_new_run(1, 8302), "Start natural opening audit")
	state.pending_intro = false
	audit.progression = {"starting_credits": state.credits, "starting_missiles": state.missiles,
		"initial_research": state.research_points, "initial_threshold": HangarResearch.threshold(state.run_progress_snapshot()),
		"purchases": []}
	for key in ["drone", "fighter", "transport"]:
		var fit := Loadouts.purchase_for(key, state.current_research_ids)
		audit.progression.purchases.append({"chassis": key, "fit": fit.get("id", ""), "price": Loadouts.ship_price(key, fit)})
	check(state.depart_expedition("refuel_station_1") and state.expedition_simulation.set_speed(10), "Travel the natural opening route")
	for frame in range(1200):
		var result: Dictionary = state.advance_expedition(1.0 / 60)
		if not result.ok:
			check(false, "Natural travel failed")
			break
		var event_id: String = state.expedition_simulation.state.pending_event_id
		if not event_id.is_empty():
			var event: Dictionary = state.expedition_simulation.Events.find(state.expedition_simulation.events, event_id)
			var options: Array = state.expedition_simulation.Events.options(event)
			var choice := "continue" if options.any(func(option: Dictionary) -> bool: return option.id == "continue") else str(options[0].id)
			check(state.resolve_expedition_event(event_id, choice), "Resolve authored opening choice")
		if state.battle_pending:
			break
	check(state.battle_pending, "Reach real first battle")
	audit.progression["prebattle_rp"] = state.research_points
	audit.progression["prebattle_offer"] = state.research_offer.duplicate()
	var baseline: Dictionary = state.hangar_snapshot().duplicate(true)
	for layout in ["default", "reversed_wing"]:
		check(state._commit_hangar(baseline.duplicate(true)), "Restore identical fleet, equipment, seed and encounter")
		var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
		root.add_child(battle)
		current_scene = battle
		battle.set_process(false)
		battle.set_physics_process(false)
		await settle()
		var sim: BattleSimulation = battle.simulation
		if layout == "reversed_wing":
			# Reverse the complete legal formation around its initial centroid.
			var center := Vector2.ZERO
			for member in sim.players:
				center += member.position
			center /= sim.players.size()
			for member in sim.players:
				member.position = center * 2 - member.position
				member.previous_position = member.position
		battle._begin_combat()
		check(not battle.deploying, "Begin saves legal " + layout + " deployment")
		var first_fire := -1.0
		var first_close := -1.0
		var snapshots: Array = []
		for tick in range(30 * 90):
			battle._advance_fixed_simulation(1.0 / 30, 1)
			if first_fire < 0 and sim.event_log.any(func(event: Dictionary) -> bool: return event.type == "expenditure"):
				first_fire = sim.elapsed
			if first_close < 0 and sim.players.any(func(member: BattleSimulation.Combatant) -> bool:
				return member.is_alive() and sim.aliens.any(func(enemy: BattleSimulation.Combatant) -> bool:
					return enemy.is_alive() and member.position.distance_to(enemy.position) <= 300)):
				first_close = sim.elapsed
			if tick % 150 == 0:
				snapshots.append({"seconds": sim.elapsed, "players": sim.players.map(func(member: BattleSimulation.Combatant) -> Array:
					return [member.entity_id, member.position.x, member.position.y, member.is_alive()])})
			if layout == "default" and tick in [150, 450]:
				battle.visuals.queue_redraw()
				await capture("opening-overview-%d" % tick)
			if sim.phase != BattleSimulation.Phase.COMBAT:
				break
		check(sim.phase != BattleSimulation.Phase.COMBAT, "Bounded opening resolves: " + layout)
		var hull_damage := 0.0
		var dealt := 0.0
		for member in sim.players:
			hull_damage += member.owned_ship.hull_max - maxf(0, member.owned_ship.hull_hp)
			dealt += member.damage_dealt
		audit.formations.append({"layout": layout, "seconds": sim.elapsed, "phase": sim.phase,
			"survivors": sim.living_player_count(), "hull_damage": hull_damage, "damage_dealt": dealt,
			"first_fire": first_fire, "first_pair_within_300": first_close, "positions": snapshots})
		check(is_equal_approx(state.research_points, audit.progression.prebattle_rp), "Battle time grants no lab RP")
		check(state.settle_battle(sim), "Settle measured battle through production")
		audit.progression["postbattle_rp"] = state.research_points
		audit.progression["postbattle_offer"] = state.research_offer.duplicate()
		battle.queue_free()
		await settle()

func progression_audit() -> void:
	check(state.start_new_run(1, 8302), "Start normal purchase audit")
	var before_dps := 0.0
	for ship: HangarShip in state.get_deployed_fleet():
		before_dps += ship.get_stats().dps
	var pool := HangarResearch.available(state.run_progress_snapshot(), state.get_deployed_fleet())
	check(state.buy_ship("drone") and state.buy_ship("drone"), "Starting funds and shipyard permit two actual fitted Drone purchases")
	var after_dps := 0.0
	for ship: HangarShip in state.get_deployed_fleet():
		after_dps += ship.get_stats().dps
	check(state.fleet.size() == 15 and state.credits == 194 and after_dps > before_dps, "Purchases debit actual fit prices and add working fleet damage")
	audit.progression = {"baseline_nominal_dps": before_dps, "two_drone_nominal_dps": after_dps,
		"credits_remaining": state.credits, "initial_eligible_research_pool": pool}

func meter_capture() -> void:
	var sim := setup([owned(["missile_rack", "shield_relay"])], 50)
	sim.aliens[0].position = Vector2(320, 0)
	sim.player.owned_ship.hull_hp *= 0.55
	sim.player.previous_position = sim.player.position
	sim.aliens[0].integrity *= 0.65
	sim.aliens[0].shields = 20
	sim.aliens[0].previous_position = sim.aliens[0].position
	sim._update_ship(sim.player, 0.01)
	check(sim.projectiles.size() == 5, "Native cluster fixture contains five physical missiles")
	sim.player.shields = 0
	sim._update_projectiles(0.3)
	sim.elapsed = 0.3
	var visual: Control = load("res://scripts/battle_visuals.gd").new()
	visual.simulation = sim
	root.add_child(visual)
	visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual.camera_position = Vector2(135, 0)
	var before := sim.authoritative_snapshot()
	RenderingServer.set_default_clear_color(Color("05090f"))
	for entry in [[Vector2i(640, 360), 0.45], [Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 2.0]]:
		root.size = entry[0]
		var zoom: float = entry[1]
		visual.camera_zoom = zoom
		visual.queue_redraw()
		await capture("ship-bars-cluster-" + str(zoom))
	check(SaveValidation.same(before, sim.authoritative_snapshot()), "Rendering, zoom and resize preserve authoritative combat state")
	visual.queue_free()
	await settle()
	meters_completed = true

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://battle-feel.json"
	if "--progression-only" in OS.get_cmdline_user_args():
		progression_audit()
	if "--native-only" not in OS.get_cmdline_user_args():
		if "--progression-only" not in OS.get_cmdline_user_args():
			missiles()
			ability_audit()
	if DisplayServer.get_name() != "headless" and "--progression-only" not in OS.get_cmdline_user_args():
		if "--meters-only" not in OS.get_cmdline_user_args():
			await opening()
		await meter_capture()
		check((audit.formations.size() == 2 or "--meters-only" in OS.get_cmdline_user_args()) and meters_completed, "Requested native sections completed")
	var report := "user://battle-feel-meters.json" if "--meters-only" in OS.get_cmdline_user_args() else "user://battle-feel-audit.json"
	if "--progression-only" in OS.get_cmdline_user_args():
		report = "user://battle-feel-progression.json"
	var file := FileAccess.open(report, FileAccess.WRITE)
	file.store_string(JSON.stringify(audit, "\t"))
	print("BATTLE FEEL: %d checks, %d failures; results %s" % [checks, failures, report])
	quit(1 if failures else 0)
