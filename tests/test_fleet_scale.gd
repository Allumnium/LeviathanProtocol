extends SceneTree

const Loadouts = preload("res://scripts/ship_loadouts.gd")
var checks := 0
var failures := 0
var state: Node

class ClockSimulation extends BattleSimulation:
	func advance(delta: float) -> void:
		elapsed += delta

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture(persist := false) -> void:
	check(state.start_new_run(1, 851, true, "flagship_science"), "Start large fleet with the smallest base command budget")
	var data: Dictionary = state.hangar_snapshot()
	data.credits = 1000000
	data.research.research_ids.append_array(["fleet_logistics_i", "fleet_logistics_ii", "fleet_logistics_iii"])
	if persist:
		check(state._commit_hangar(data), "Persist earned fleet logistics")
		check(state.command_limit() == 120, "Top research supports thirty fighters plus twenty transports")
		check(state.buy_ships("fighter", 28) and state.buy_ships("transport", 19), "Buy full large squadrons atomically")
		data = state.hangar_snapshot()
	else:
		for index in range(28):
			Loadouts.append_ship(data, "fighter", Loadouts.default_for("fighter"))
		for index in range(19):
			Loadouts.append_ship(data, "transport", Loadouts.default_for("transport"))
		data.squadrons = HangarSquadrons.initial(data)
	# A broad but legal formation avoids stacking all newly bought ships.
	for index in range(data.ships.size()):
		data.ships[index].formation = [(index % 8 - 3.5) * 0.55, (index / 8 - 3) * 0.55]
	HangarSquadrons.sync(data)
	if persist:
		check(state._commit_hangar(data), "Persist large fleet formation")
	else:
		state._apply_hangar(data)
	state.research_completion_notices.clear()

func enemies() -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(40, 1.0, 851):
		result.append(alien)
	return result

func simulation(count := 50) -> BattleSimulation:
	var sim := BattleSimulation.new()
	var ships: Array[FleetShip] = []
	for index in range(mini(count, state.fleet.size())):
		ships.append(state.fleet[index])
	check(sim.setup_owned(ships, enemies(), 0, 0, 851,
		{"credits_only": true, "missiles": 1000, "enemy_roles": true}), "Set up large fully fitted battle")
	return sim

func profile() -> void:
	fixture()
	var sim := simulation()
	check(sim.players.size() == 50 and sim.aliens.size() == 40, "Profile starts fifty versus forty")
	var batches: Array[float] = []
	var accumulator := 0.0
	var ticks := 0
	var peak := sim._members.size()
	var started := Time.get_ticks_usec()
	# Fixed 30 Hz simulation, batched as a 60 Hz render/physics frame at 5x.
	for frame in range(720):
		var batch_started := Time.get_ticks_usec()
		accumulator += 5.0 / 60
		while accumulator + 0.00000001 >= 1.0 / 30:
			sim.advance(1.0 / 30)
			accumulator -= 1.0 / 30
			ticks += 1
		batches.append((Time.get_ticks_usec() - batch_started) / 1000.0)
		peak = maxi(peak, sim._members.size())
		if sim.phase != BattleSimulation.Phase.COMBAT:
			break
	batches.sort()
	var seconds := (Time.get_ticks_usec() - started) / 1000000.0
	var summary := {"initial_players": 50, "initial_enemies": 40, "speed": 5, "ticks": ticks,
		"simulation_seconds": sim.elapsed, "cpu_seconds": seconds, "peak_entities": peak,
		"batch_p50_ms": batches[batches.size() / 2], "batch_p95_ms": batches[int(batches.size() * 0.95)],
		"batch_max_ms": batches.back(), "phase": sim.phase}
	print("FLEET SCALE PROFILE: " + JSON.stringify(summary))
	var file := FileAccess.open("user://fleet-scale-profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	check(ticks > 0 and sim.elapsed > 0 and is_finite(seconds), "Profile completes with measured simulation work")

func large_fleet() -> void:
	fixture(true)
	check(state.fleet.size() == 51 and state.used_command() == 120, "Flagship plus thirty fighters and twenty transports fits exactly")
	var before: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot()), "Continue retains large squadrons, fits, ownership and formation")
	check(not state.buy_ship("fighter") and SaveValidation.same(before, state.hangar_snapshot()), "Large fleet command boundary still rejects extra purchases")
	var sim := simulation(51)
	check(sim.players.size() == 51 and sim.living_combatant_count() == 91, "All ninety-one combatants deploy")
	# Chrysalis and reinforcement paths share the same larger live budget.
	var chrysalis: BattleSimulation.Combatant
	for actor in sim.aliens:
		if actor.alien.role_id == "chrysalis":
			chrysalis = actor
			break
	check(chrysalis != null, "Large enemy fixture includes a chrysalis")
	if chrysalis != null:
		var reserve: Dictionary = sim.enemy_roles.sources[chrysalis.entity_id]
		var remaining: int = reserve.remaining
		sim.enemy_roles._launch(sim, chrysalis, reserve)
		check(reserve.remaining == remaining - 1 and sim.living_combatant_count() == 92, "Enemy finite summons work above sixty-four")
	var reinforcement: Dictionary = sim.aliens[0].alien.to_snapshot()
	reinforcement.entity_id = "wave/scale/ship/0"
	reinforcement.wave = 1
	sim.encounter.pending.append(reinforcement)
	sim.encounter.advance(sim, 6)
	check(sim.encounter.pending.is_empty() and sim.entities.has(reinforcement.entity_id), "Frozen reinforcement wave admits above the former shared cap")
	while sim.living_combatant_count() < BattleSimulation.MAX_LIVE_COMBATANTS:
		var actor := BattleSimulation.Combatant.new()
		actor.entity_id = "scale/%d" % sim._members.size()
		actor.integrity = 1
		actor.stats = ShipStats.new()
		actor.stats.weight = 1
		if not sim.register_entity(actor):
			check(false, "Fill live budget")
			break
	var extra := BattleSimulation.Combatant.new()
	extra.entity_id = "scale/headroom"
	extra.integrity = 1
	extra.stats = ShipStats.new()
	extra.stats.weight = 1
	check(not sim.register_entity(extra) and sim.living_combatant_count() == 192, "Full live budget rejects an extra combatant")
	sim.other_entities.back().integrity = 0
	check(sim.register_entity(extra) and sim.living_combatant_count() == 192, "Destroyed actors free live headroom")
	# Aggregate health retains the original denominator and zero hull survives.
	var readout: Control = load("res://scripts/battle_squadron_readout.gd").new()
	readout.simulation = sim
	root.add_child(readout)
	var fighter := sim.players[2]
	var other := sim.players[3]
	var key: int = fighter.owned_ship.squadron_id
	var row: Dictionary = readout.rows[key]
	var maximum: float = row.hull.max_value
	fighter.owned_ship.hull_hp = 0
	other.owned_ship.hull_hp = -1
	readout.refresh()
	check(row.label.source_text.ends_with("29/30") and row.hull.max_value == maximum
		and is_equal_approx(row.hull.value, maximum - fighter.owned_ship.hull_max - other.owned_ship.hull_max),
		"Squadron meter counts zero hull alive and destroyed hull empty against the original capacity")
	var entries: Array[Dictionary] = []
	for actor in sim.players:
		entries.append({"ship": actor.owned_ship, "destroyed": not actor.is_alive(),
			"damage": 10, "taken": 5, "deflected": 2, "repair_damage": 3})
	var report: Control = load("res://scripts/battle_report.gd").new()
	var summaries: Array[Dictionary] = report._summarize_by_slot(entries)
	check(summaries.size() == 3, "Fifty-one friendly ships produce three squadron report rows")
	for summary: Dictionary in summaries:
		if summary.ship.squadron_id == key:
			check(summary.count == 30 and summary.destroyed == 1 and summary.damage == 300
				and summary.taken == 150 and summary.deflected == 60 and summary.repair_damage == 87,
				"Grouped report sums damage/deflection and surviving repair need without concealing losses")
	report.free()
	readout.queue_free()
	# Explicit orders bypass delayed searches, and nearby idle guns keep full cadence.
	check(state.load_run_checkpoint(), "Restore untouched fleet after battle-only health fixtures")
	sim = simulation()
	var gunship := sim.players[2]
	var enemy := sim.aliens[0]
	enemy.integrity = 100000
	enemy.stats.integrity = 100000
	gunship.weapon_search_remaining[0] = 1.0
	gunship.commanded_target = enemy
	gunship.target = enemy
	gunship.position = Vector2.ZERO
	enemy.position = Vector2(50, 0)
	sim._rebuild_spatial_index()
	var before_events := sim.event_log.size()
	sim._update_ship(gunship, 1.0 / 30)
	check(sim.event_log.size() > before_events, "Explicit attack order bypasses distant idle-gun search delay")
	gunship.commanded_target = null
	gunship.cooldowns.fill(1.0)
	gunship.cooldowns[0] = 0.0
	gunship.weapon_search_remaining[0] = 1.0
	before_events = sim.event_log.size()
	sim._update_ship(gunship, 1.0 / 30)
	check(sim.event_log.size() > before_events and gunship.weapon_search_remaining[0] == 0,
		"Nearby target bypasses distant-search delay and clears the idle timer on firing")
	spatial_equivalence(sim)
	var source_ship: HangarShip = sim.players[0].owned_ship
	var old_mount: Dictionary = source_ship.mounts.spine
	source_ship.mounts.spine = {"uid": "cache-fixture", "equipment_id": "repair_drone_bay", "rank": 1}
	source_ship.rebuild_units()
	sim._refresh_owned_stats(sim.players[0])
	check(not CombatDoctrines.operational(sim.players[0], ShipPart.Type.REPAIR_DRONE_BAY).is_empty(),
		"Refreshing physical stats invalidates the support layout cache")
	check(sim._active_lab(sim.players[0]) == ScienceRules.active_lab(source_ship), "Cached science selects the same highest-rank living lab")
	source_ship.hull_hp = 0
	check(not CombatDoctrines.operational(sim.players[0], ShipPart.Type.REPAIR_DRONE_BAY).is_empty(), "Zero-hull support remains operational")
	source_ship.hull_hp = -1
	check(CombatDoctrines.operational(sim.players[0], ShipPart.Type.REPAIR_DRONE_BAY).is_empty(), "Destroyed hosts cannot use cached support sources")
	source_ship.mounts.spine = old_mount
	source_ship.rebuild_units()
	check(state.load_run_checkpoint(), "Restore fleet before the fixed-step pacing check")
	state.battle_pending = true
	state.battle_aliens.assign(enemies())
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	battle.set_physics_process(false)
	battle.set_process(false)
	battle.simulation = ClockSimulation.new()
	battle._advance_fixed_simulation(0.1, 5)
	check(is_equal_approx(battle.simulation.elapsed + battle._simulation_accumulator, 0.5)
		and battle._simulation_accumulator > 1.0 / 30, "Costly frames retain bounded catch-up time instead of discarding 5x time")
	for frame in range(4):
		battle._advance_fixed_simulation(1.0 / 60, 5)
	check(is_equal_approx(battle.simulation.elapsed + battle._simulation_accumulator, 5.0 / 6)
		and battle._simulation_accumulator < 1.0 / 30, "Ordinary frames catch up without losing simulation time")
	var elapsed: float = battle.simulation.elapsed
	battle._advance_fixed_simulation(10, 5)
	check(battle._simulation_accumulator <= 1 and battle.simulation.elapsed - elapsed <= 8.0 / 30 + 0.00001,
		"Large stalls keep both per-frame work and retained backlog bounded")
	battle.queue_free()
	state.battle_pending = false

func spatial_equivalence(sim: BattleSimulation) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 931
	for actor in sim._members:
		actor.position = Vector2(rng.randf_range(-500, 500), rng.randf_range(-500, 500))
		actor.speed = 800
	sim._rebuild_spatial_index(1.0 / 30)
	# Match a tick where earlier actors have already crossed an index boundary.
	for actor in sim._members:
		actor.position += Vector2.from_angle(rng.randf_range(-PI, PI)) * actor.speed / 30
	for actor in sim._members:
		var expected := Vector2(31, -17)
		var cell := sim._spatial_cell(actor.position)
		for x in range(cell.x - 1, cell.x + 2):
			for y in range(cell.y - 1, cell.y + 2):
				for other: BattleSimulation.Combatant in sim._spatial_cells.get(Vector2i(x, y), []):
					if other == actor or not other.is_alive():
						continue
					var offset := actor.position - other.position
					var clearance := actor.radius + other.radius + 12.0
					if offset.length_squared() >= clearance * clearance:
						continue
					var distance := sqrt(offset.length_squared())
					if offset.is_zero_approx():
						offset = Vector2.UP
						distance = 1
					expected += offset / distance * actor.speed * (1.0 - distance / clearance)
		check(sim._separation_velocity(actor, Vector2(31, -17)) == expected,
			"Fine separation query preserves the original neighbors and floating-point sum order")
		var nearby: Array[BattleSimulation.Combatant] = sim.nearby_players(actor.position, 90)
		var all: Array[BattleSimulation.Combatant] = sim.players.filter(func(player: BattleSimulation.Combatant) -> bool:
			return player.position.distance_squared_to(actor.position) < 8100)
		check(nearby.size() == all.size() and nearby.all(func(player: BattleSimulation.Combatant) -> bool: return all.has(player)),
			"Fine escort query preserves player membership across moving cell boundaries")
	for actor in sim.aliens:
		if sim.enemy_roles.role(actor) not in ["support", "sentinel", "chrysalis"]:
			continue
		var nearest := INF
		var anchor: BattleSimulation.Combatant
		for ally in sim.aliens:
			if ally == actor or not ally.is_alive() or sim.enemy_roles.role(ally) not in ["fighter", "scout"]:
				continue
			var distance := actor.position.distance_squared_to(ally.position)
			if distance < nearest:
				nearest = distance
				anchor = ally
		var expected := Vector2(0.2, -0.7)
		if anchor != null:
			var offset := 65.0 if sim.enemy_roles.role(actor) == "sentinel" else 100.0
			expected = actor.position.direction_to(anchor.position - Vector2.from_angle(anchor.heading) * offset)
		check(sim.enemy_roles.steering(sim, actor, Vector2(0.2, -0.7)) == expected,
			"Cached anchor membership preserves nearest-escort steering")

func settle() -> void:
	for frame in range(5):
		await process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://" + name + ".png") == OK, "Save native fleet-scale capture")

func click(button: Button) -> void:
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(button)
	await settle()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func native_management() -> void:
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		screen.active_tab = "SHIPS"
		screen._refresh()
		await settle()
		check(screen.roster.find_child("ShipSquadron_3", true, false) != null
			and screen.roster.get_node("ShipTiles_3").get_child_count() == 30,
			"Ships groups all thirty fighters under their named squadron")
		var last: int = state.squadrons[2].members.back()
		await click(screen.roster.find_child("Ship%d" % last, true, false))
		check(screen.selected_ship_id == last and screen.canvas.owned_id == last, "Native pointer selects a scrolled large-squadron member")
		await capture("scale-ships-%d" % resolution.x)
		screen.active_tab = "FLEET"
		screen._refresh()
		await settle()
		await click(screen.roster.find_child("Squadron_3", true, false))
		check(screen.formation_selection.size() == 30 and screen.details.find_child("SquadronStatBars", true, false) != null,
			"Native Fleet selects the whole thirty-ship squadron and its aggregate health")
		await capture("scale-fleet-%d" % resolution.x)
	screen.queue_free()
	await settle()

func native_ui() -> void:
	fixture(true)
	if "--battle-only" not in OS.get_cmdline_user_args():
		await native_management()
	# Native battle profile includes the actual fixed-step runner, visuals and HUD.
	state.fleet.pop_back()
	state.battle_pending = true
	state.battle_aliens.assign(enemies())
	state.battle_speed = 5
	root.size = Vector2i(1280, 720)
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	battle.set_physics_process(false)
	battle.set_process(false)
	await settle()
	var objective_ids: Array[String] = []
	for actor in battle.simulation.aliens:
		objective_ids.append(actor.entity_id)
	check(battle.simulation.set_objective_targets(objective_ids), "Native profile targets the full frozen fixture roster")
	battle.simulation.enemy_roles.configure(battle.simulation, true)
	var source_image: Image = battle.simulation.players[0].owned_ship.art_texture.get_image()
	source_image.convert(Image.FORMAT_RGBA8)
	var mask: Image = battle.visuals._shield_mask(battle.simulation.players[0].owned_ship.art_texture).get_image()
	var mask_matches := true
	for y in range(0, source_image.get_height(), maxi(1, source_image.get_height() / 8)):
		for x in range(0, source_image.get_width(), maxi(1, source_image.get_width() / 8)):
			mask_matches = mask_matches and mask.get_pixel(x, y) == Color(1, 1, 1, source_image.get_pixel(x, y).a)
	check(mask_matches, "Fast shield-mask creation preserves the source alpha and white silhouette")
	check(battle.simulation.players.size() == 50 and battle.simulation.aliens.size() == 40, "Native profile starts fifty versus forty at 5x")
	var started := Time.get_ticks_usec()
	var frames := 0
	var frame_times: Array[float] = []
	var previous_frame := started
	var requested_seconds := 0.0
	while battle.simulation.phase == BattleSimulation.Phase.COMBAT and frames < 720:
		var frame_started := Time.get_ticks_usec()
		var frame_delta := 1.0 / 60 if frames == 0 or "--fixed-budget" in OS.get_cmdline_user_args() else (frame_started - previous_frame) / 1000000.0
		previous_frame = frame_started
		requested_seconds += frame_delta * 5
		battle._advance_fixed_simulation(frame_delta, 5.0)
		battle._update_auto_camera(frame_delta)
		battle.objective_label.text = battle.simulation.encounter.label(battle.simulation)
		battle.visuals.queue_redraw()
		await process_frame
		frame_times.append((Time.get_ticks_usec() - frame_started) / 1000.0)
		frames += 1
	frame_times.sort()
	var summary := {"speed": 5, "paced": "--fixed-budget" not in OS.get_cmdline_user_args(), "resolution": [1280, 720], "frames": frames,
		"simulation_seconds": battle.simulation.elapsed, "wall_seconds": (Time.get_ticks_usec() - started) / 1000000.0,
		"combat_seconds": battle.simulation._combat_elapsed,
		"requested_simulation_seconds": requested_seconds, "pending_seconds": battle._simulation_accumulator,
		"dropped_seconds": maxf(0, requested_seconds - battle.simulation.elapsed - battle._simulation_accumulator),
		"frame_p50_ms": frame_times[frames / 2], "frame_p95_ms": frame_times[int(frames * 0.95)], "frame_max_ms": frame_times.back()}
	summary["effective_combat_speed"] = summary.combat_seconds / summary.wall_seconds
	print("NATIVE FLEET SCALE PROFILE: " + JSON.stringify(summary))
	var profile_file := FileAccess.open("user://fleet-scale-native-profile.json", FileAccess.WRITE)
	profile_file.store_string(JSON.stringify(summary, "\t"))
	check(frames >= 30 and battle.simulation.tick_index >= 75, "Native large battle profile completes sustained simulation work")
	check(summary.dropped_seconds < 1.0 / 30 + 0.00000001 and summary.pending_seconds <= 1.0,
		"Native 5x preserves requested simulation time within the bounded catch-up budget")
	if "--performance-only" in OS.get_cmdline_user_args():
		battle.queue_free()
		await settle()
		return
	var entries: Array[Dictionary] = []
	for actor in battle.simulation.players:
		entries.append({"ship": actor.owned_ship, "destroyed": not actor.is_alive(), "damage": actor.damage_dealt,
			"taken": actor.damage_taken, "deflected": actor.damage_deflected(), "repair_damage": actor.owned_ship.repair_cost() if actor.is_alive() else 0})
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		battle.squadron_readout.refresh()
		check(root.get_visible_rect().encloses(battle.squadron_readout.get_global_rect())
			and not battle._battlefield_input(battle.squadron_readout.get_global_rect().get_center()),
			"Squadron HUD stays on screen and consumes clicks instead of issuing battlefield orders")
		await capture("scale-battle-%d" % resolution.x)
		var report: Control = load("res://scripts/battle_report.gd").new()
		battle.squadron_readout.hide()
		battle.add_child(report)
		var materials: Array[int] = []
		report.show_report(entries, "Victory", materials)
		await settle()
		check(report.find_child("FleetTable", true, false).get_child_count() == 16, "Native large report has three squadron rows")
		var grid: GridContainer = report.find_child("FleetTable", true, false)
		var last_row: Control = grid.get_child(12)
		check(root.get_visible_rect().encloses(last_row.get_global_rect()), "All three squadron report names fit at the supported resolution")
		await capture("scale-report-%d" % resolution.x)
		report.queue_free()
		await settle()
		battle.squadron_readout.show()
	battle.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://fleet-scale.json"
	if DisplayServer.get_name() != "headless":
		await native_ui()
	elif "--profile" in OS.get_cmdline_user_args():
		profile()
	else:
		large_fleet()
		if "--checks-only" not in OS.get_cmdline_user_args():
			profile()
	print("FLEET SCALE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
