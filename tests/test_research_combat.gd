extends SceneTree

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

func text_under(node: Node) -> String:
	var text: String = node.source_text if node is ResourceText else (node.text if node is Label else "")
	for child: Node in node.get_children():
		text += "\n" + text_under(child)
	return text

func changed_pixels(before: Image, after: Image, area: Rect2i) -> int:
	var changed := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.0 / 255:
				changed += 1
	return changed

func image(view: Control) -> Image:
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func fixture(effects: Dictionary = {}, item := "laser", supply := 30) -> BattleSimulation:
	var ship := HangarShip.new()
	ship.initialize_chassis("corsair", 1, true)
	var slot := "aft" if item in ["laser", "mini_turret"] else "port"
	ship.mounts[slot] = {"uid": "1", "equipment_id": item, "rank": 1}
	ship.mounts.starboard = {"uid": "2", "equipment_id": "shield_generator", "rank": 1}
	ship.rebuild_units()
	ship.hull_hp = ship.hull_max
	var stats := ShipStats.new()
	stats.integrity = 100000
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Enemy", 10, 0.01, 1, 200))
	var enemy := AlienShip.new("Research target", AlienShip.SCOUT_TEXTURE, stats)
	var ships: Array[FleetShip] = [ship]
	var enemies: Array[RefCounted] = [enemy]
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, enemies, 0, 0, 9401,
		{"credits_only": true, "missiles": supply, "research_effects": effects}), "Set up research combat fixture")
	sim.player.position = Vector2.ZERO
	sim.player.heading = 0
	sim.player.speed = 0
	sim.player.acceleration = 0
	sim.aliens[0].position = Vector2(150, 0)
	sim.aliens[0].speed = 0
	sim.aliens[0].acceleration = 0
	return sim

func step_laser(sim: BattleSimulation, delta: float) -> void:
	sim.research_combat.begin_step(sim, delta)
	sim._update_ship(sim.player, delta)
	sim.research_combat.end_step(sim)

func lasers() -> void:
	var sim := fixture({"prismatic_lasers": true})
	var weapon := sim.player.stats.weapons[0]
	var base := weapon.get_dps()
	for tick in range(120):
		step_laser(sim, 1.0 / 30)
		check(sim.beams.size() == 1 and sim.beams[0].prismatic, "Continuous beam remains one visible channel, never a pile of flashes")
	check(is_equal_approx(sim.player.damage_dealt, base * 6), "First four seconds integrate the exact linear 1x-to-2x damage ramp")
	check(is_equal_approx(sim.beams[0].intensity, 2), "Full ramp has a visibly stronger beam")
	var damage := sim.player.damage_dealt
	for tick in range(120):
		step_laser(sim, 1.0 / 30)
	check(is_equal_approx(sim.player.damage_dealt - damage, base * 8), "Sustained lock caps at exactly 2x base DPS")
	var snapshot := sim.research_combat.snapshot()
	check(snapshot.channels.size() == 1 and is_equal_approx(snapshot.channels.values()[0].held, 8),
		"Replay includes exact lock duration")
	snapshot.channels.clear()
	check(sim.research_combat.channels.size() == 1, "Diagnostic channels are detached")
	sim.aliens[0].position = Vector2(1000, 0)
	step_laser(sim, 1.0 / 30)
	check(sim.research_combat.channels.is_empty() and sim.beams.is_empty(), "Out-of-range contact stops drawing and drops the lock immediately")
	sim.aliens[0].position = Vector2(150, 0)
	damage = sim.player.damage_dealt
	step_laser(sim, 1)
	check(is_equal_approx(sim.player.damage_dealt - damage, base * 1.125), "Reacquisition starts at 1x rather than carrying a hidden full ramp")
	var extra := sim.add_neutral_target("manual", 10000, Vector2(120, 0))
	check(extra != null and sim.request_attack(sim.player.entity_id, "manual"), "Manual target switch is accepted")
	damage = sim.player.damage_dealt
	step_laser(sim, 1)
	check(sim.research_combat.channels.values()[0].target == "manual"
		and is_equal_approx(sim.player.damage_dealt - damage, base * 1.125), "Changing target resets ramp")
	sim.player.owned_ship.stance = "evade"
	sim.clear_attack_order(sim.player.entity_id)
	step_laser(sim, 0.1)
	check(sim.research_combat.channels.is_empty() and sim.beams.is_empty(), "Evade cannot retain a free continuous beam")
	sim = fixture({"prismatic_lasers": true}, "double_laser")
	base = sim.player.stats.weapons[0].get_dps()
	for tick in range(120):
		step_laser(sim, 1.0 / 30)
	check(is_equal_approx(sim.player.damage_dealt, base * 6), "Double Laser retains its full multiple-emitter damage in the continuous channel")
	sim.research_combat.synchronize(sim.player, 0, sim.player.stats.weapons[0])
	damage = sim.player.damage_dealt
	step_laser(sim, 1.0 / 30)
	check(is_equal_approx(sim.player.damage_dealt - damage, base * 2 / 30
		+ sim.player.stats.weapons[0].damage_per_shot * sim.player.stats.weapons[0].projectiles_per_activation),
		"Tactical synchronization still adds a complete laser salvo")
	sim = fixture({}, "laser")
	step_laser(sim, 0.1)
	check(is_equal_approx(sim.player.damage_dealt, sim.player.stats.weapons[0].damage_per_shot)
		and not sim.beams[0].prismatic, "Unresearched lasers preserve their discrete shot and cooldown")
	sim = fixture({"prismatic_lasers": true}, "mini_turret")
	step_laser(sim, 0.1)
	check(not sim.projectiles.is_empty() and sim.research_combat.channels.is_empty(), "Research does not convert guns")
	sim = fixture({"prismatic_lasers": true})
	sim.visibility_enabled = true
	sim.refresh_visibility()
	step_laser(sim, 1)
	var before := sim.player.damage_dealt
	sim.aliens[0].position = Vector2(400, 0)
	sim.player.stats.weapons[0].range_units = 500
	sim.refresh_visibility()
	step_laser(sim, 1)
	check(sim.player.damage_dealt == before and sim.research_combat.channels.is_empty(),
		"Losing sight drops the lock even while the target remains in weapon range")
	sim = fixture({"prismatic_lasers": true})
	step_laser(sim, 1)
	var origin := sim._get_weapon_origin(sim.player, sim.player.stats.weapons[0])
	check(sim.asteroid_field.add_root("blocker", 8, origin.lerp(sim.aliens[0].position, 0.6),
		Vector2.ZERO, [0, 0, 0, 0]), "Create an actual occluding asteroid")
	sim.asteroid_field.attach(sim)
	step_laser(sim, 1)
	check(sim.research_combat.channels.values()[0].target == "blocker"
		and is_equal_approx(sim.research_combat.channels.values()[0].held, 1),
		"An intervening asteroid receives the beam and resets the target ramp")
	sim.research_combat.begin_step(sim, 0.1)
	sim._update_ship(sim.player, 0.1, false)
	sim.research_combat.end_step(sim)
	check(sim.beams.is_empty() and sim.research_combat.channels.is_empty(),
		"Finishing combat cannot leave continuous weapons firing during collection")
	step_laser(sim, 0.1)
	sim.player.owned_ship.hull_hp = -1
	sim.research_combat.end_step(sim)
	check(sim.beams.is_empty(), "A destroyed beam source cannot retain its channel")
	# Splitting a continuous hit into more simulation steps must not multiply armor.
	var armored := HangarShip.new()
	armored.initialize_chassis("flagship_basic", 9, true)
	var original := armored.hull_hp
	for tick in range(30):
		armored.damage_hull(12.0 / 30, 1.0 / 30)
	check(is_equal_approx(original - armored.hull_hp, 11), "Continuous hull damage scales flat armor by hit fraction, not frame count")

func missiles() -> void:
	var sim := fixture({"splinter_missiles": true}, "missile_rack", 1)
	sim.aliens[0].position = Vector2(200, 0)
	step_laser(sim, 0.01)
	check(sim.projectiles.size() == 1 and sim.missile_supply == 0 and sim.projectiles[0].splinter,
		"Partial final salvo launches one researched parent and spends one missile")
	var parent := sim.projectiles[0]
	var damage := parent.damage
	sim._update_projectiles(0.01)
	check(sim.projectiles.size() == 1, "Parent remains intact until within 100 units")
	parent.position = Vector2(110, 0)
	sim._update_projectiles(0.01)
	check(sim.projectiles.size() == 3 and sim.projectiles.all(func(shot: BattleSimulation.Projectile) -> bool:
		return shot.fragment and shot.interceptable and not shot.splinter and is_equal_approx(shot.damage, damage * 0.5)),
		"Parent becomes exactly three interceptable half-damage fragments with no recursive splitting")
	check(sim.missile_supply == 0 and is_equal_approx(sim._pending_projectile_damage(parent.target), damage * 1.5),
		"Split replaces pending damage exactly without extra ammunition spending")
	check(sim.event_log.filter(func(entry: Dictionary) -> bool: return entry.type == "missile_split").size() == 1,
		"Replay records one split event per parent")
	for tick in range(120):
		sim._update_projectiles(1.0 / 30)
	check(sim.projectiles.is_empty() and is_equal_approx(sim.player.damage_dealt, damage * 1.5),
		"Single-target fragments deal the exact combined 150% damage then disappear")
	sim = fixture({}, "missile_rack", 1)
	step_laser(sim, 0.01)
	parent = sim.projectiles[0]
	parent.position = Vector2(70, 0)
	sim._update_projectiles(0.01)
	check(sim.projectiles.size() == 1 and not sim.projectiles[0].splinter, "Unresearched rack keeps its original projectile")
	sim = fixture({"splinter_missiles": true}, "missile_rack", 1)
	step_laser(sim, 0.01)
	parent = sim.projectiles[0]
	parent.guidance_lost = true
	parent.position = Vector2(70, 0)
	check(not sim.research_combat.split(sim, parent), "Lost guidance cannot acquire split targets")
	sim = fixture({"splinter_missiles": true}, "missile_rack", 1)
	sim.aliens[0].position = Vector2(300, 0)
	step_laser(sim, 0.01)
	parent = sim.projectiles[0]
	parent.position = Vector2(210, 0)
	check(sim.research_combat.split(sim, parent), "Normal non-fog battles split at full Missile Rack range")
	sim = fixture({"splinter_missiles": true}, "missile_rack", 1)
	var second := sim.add_neutral_target("second", 10000, Vector2(170, 15))
	second.faction = BattleSimulation.Faction.ALIEN
	second.tags.assign({"combatant": true})
	var third := sim.add_neutral_target("third", 10000, Vector2(180, -15))
	third.faction = BattleSimulation.Faction.ALIEN
	third.tags.assign({"combatant": true})
	step_laser(sim, 0.01)
	parent = sim.projectiles[0]
	parent.position = parent.target.position - Vector2(90, 0)
	sim._update_projectiles(0.01)
	var targets := {}
	for shot: BattleSimulation.Projectile in sim.projectiles:
		targets[shot.target.entity_id] = true
	check(targets.size() == 3, "Splinters distribute over up to three nearby hostile targets")
	var defender := HangarShip.new()
	defender.initialize_chassis("fighter", 2)
	defender.mounts.port = {"uid": "pd", "equipment_id": "point_defense_turret", "rank": 1}
	defender.rebuild_units()
	var actor := sim._create_combatant(defender.get_stats())
	actor.owned_ship = defender
	actor.faction = BattleSimulation.Faction.ALIEN
	actor.position = Vector2(150, 0)
	check(SharedSupport.intercept(sim, actor, actor.stats.weapons[0], actor.position)
		and sim.projectiles.size() == 2, "Existing point defense can destroy an individual splinter")
	sim = fixture({"splinter_missiles": true}, "missile_rack", 1)
	step_laser(sim, 0.01)
	parent = sim.projectiles[0]
	parent.position = Vector2(70, 0)
	sim.visibility_enabled = true
	sim.aliens[0].position = Vector2(280, 0)
	parent.position = Vector2(190, 0)
	sim.refresh_visibility()
	check(not sim.research_combat.split(sim, parent), "Splitting never acquires an unseen primary target")
	sim.aliens[0].position = Vector2(240, 0)
	parent.position = Vector2(150, 0)
	var hidden := sim.add_neutral_target("hidden", 10000, Vector2(300, 0))
	hidden.faction = BattleSimulation.Faction.ALIEN
	hidden.tags.assign({"combatant": true})
	sim.refresh_visibility()
	sim._update_projectiles(0.01)
	check(sim.projectiles.size() == 3 and sim.projectiles.all(func(shot: BattleSimulation.Projectile) -> bool:
		return shot.target != hidden), "Fragments cannot reveal or retarget to an unseen neighboring hostile")

func shields() -> void:
	var sim := fixture({"pulse_shields": true})
	var capacity := sim.player.stats.shields
	sim.player.shields = 0
	sim.player.since_damage = 0
	sim.research_combat.begin_step(sim, 7.9)
	check(sim.player.shields == 0, "Shields do not pulse early")
	sim.research_combat.begin_step(sim, 0.1)
	check(is_equal_approx(sim.player.shields, capacity * 0.25) and sim.research_combat.pulse_rings.size() == 1,
		"At eight seconds the exact quarter-shield recovery works even under recent fire")
	sim.player.shields = capacity - 1
	sim.research_combat.begin_step(sim, 8)
	check(sim.player.shields == capacity and sim.event_log[-1].details.restored == 1, "Pulse caps at capacity and logs actual restored shields")
	sim.player.shields = 0
	sim.abilities.effects.append({"id": "ion_pulse", "target": sim.player.entity_id, "remaining": 10.0})
	sim.research_combat.begin_step(sim, 8)
	check(sim.player.shields == 0, "Ion suppression blocks a shield pulse")
	sim.abilities.effects.clear()
	sim.research_combat.begin_step(sim, 0.1)
	check(sim.player.shields == 0, "Blocked pulse does not bank an instant extra activation")
	sim.player.owned_ship.hull_hp = -1
	sim.research_combat.begin_step(sim, 8)
	check(sim.player.shields == 0 and not sim.research_combat.shield_clocks.has(sim.player.entity_id),
		"Destroyed ships cannot pulse")
	sim = fixture({})
	sim.player.shields = 0
	sim.research_combat.begin_step(sim, 8)
	check(sim.player.shields == 0 and sim.research_combat.pulse_rings.is_empty(), "Unresearched shields keep their old recharge behavior")

func persistence() -> void:
	check(state.start_new_run(1, 9402), "Start research persistence fixture")
	var initial: Dictionary = state.hangar_snapshot()
	for field: String in ResearchCombat.EFFECTS:
		check(not state.battle_support_context().research_effects.get(field, false), "New runs do not silently receive " + field)
	var fixture: Dictionary = initial.duplicate(true)
	fixture.research.research_ids.append_array(["applied_energy", "energy_manipulation", "guided_munitions", "siege_i", "bastion_ii"])
	fixture.research.branch_choices = {"force_projection": "siege", "survival": "bastion"}
	check(state._commit_hangar(fixture), "Existing stable research IDs validate with new behavioral grants")
	check(state.energy_efficiency() == 0 and state.battle_support_context().research_effects.size() == 3,
		"Deployment uses all three researched behaviors instead of the old flat energy percentage")
	check(state.load_run_checkpoint() and state.battle_support_context().research_effects.size() == 3,
		"Continue derives effects from earned research, without new save fields")
	check(not state.choose_research("carrier_i") and not state.choose_research("renewal_i"),
		"Behavioral upgrades retain exclusive branch choices")
	var registry := HangarResearch.view_registry()
	for pair: Array in [["energy_manipulation", "continuous"], ["siege_i", "splits into 3"], ["bastion_ii", "25%"]]:
		check(ResearchViewModel.effect_summary(registry, pair[0]).contains(pair[1]),
			"Research tree and completion banner disclose " + pair[0])
	var before: Dictionary = state.hangar_snapshot()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/no-research.json"
	check(not state._commit_hangar(initial) and SaveValidation.same(before, state.hangar_snapshot())
		and state.battle_support_context().research_effects.size() == 3, "Failed research save leaves deployed effect grants unchanged")
	state.run_save_path = path
	for value: Variant in [null, [], true, {"unknown": true}, {"prismatic_lasers": 1}, {"pulse_shields": "yes"}]:
		check(not ResearchCombat.valid(value), "Reject malformed research-effect context")
	var invalid := fixture({})
	var ships: Array[FleetShip] = [invalid.player.owned_ship]
	var enemies: Array[RefCounted] = [invalid.aliens[0].alien]
	check(not invalid.setup_owned(ships, enemies, 0, 0, 1, {"research_effects": {"unknown": true}}),
		"Invalid battle effect metadata fails explicitly")

func replay() -> void:
	var baseline: Dictionary = {}
	var baseline_events: Array = []
	for weapon: String in ["laser", "missile_rack"]:
		for batch in [1, 2, 8]:
			var sim := fixture({"prismatic_lasers": true, "pulse_shields": true, "splinter_missiles": true}, weapon)
			for step in range(240 / batch):
				for tick in range(batch):
					sim.advance(1.0 / 30)
			if batch == 1:
				baseline = sim.authoritative_snapshot()
				baseline_events = sim.event_log.duplicate(true)
			else:
				check(SaveValidation.same(baseline, sim.authoritative_snapshot()) and baseline_events == sim.event_log,
					"Research effects and ammunition replay identically at different render batches: " + weapon)
			if weapon == "missile_rack":
				check(sim.event_log.any(func(event: Dictionary) -> bool: return event.type == "missile_split")
					and sim.missile_supply < 30, "Missile replay actually exercises splitting and finite ammunition")

func ui() -> void:
	state.research_completion_notices.clear()
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	screen.active_tab = "MAP"
	screen._refresh()
	await settle()
	check(screen._part_effect(SlotCatalog.find_equipment("laser")).contains("Continuous")
		and screen._part_effect(SlotCatalog.find_equipment("missile_rack")).contains("3 x half")
		and screen._part_effect(SlotCatalog.find_equipment("shield_generator")).contains("25%"),
		"Installed-part inspection reports researched behaviors, not only unchanged catalog DPS")
	# Card descriptions and layout are verified in test_research_choices.gd.
	screen.queue_free()
	await settle()
	if DisplayServer.get_name() == "headless":
		return
	root.size = Vector2i(1280, 720)
	var view: Control = load("res://scripts/battle_visuals.gd").new()
	view.simulation = fixture({"prismatic_lasers": true, "pulse_shields": true})
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_process(false)
	view.stars.clear()
	view.camera_position = Vector2(70, 0)
	view.camera_zoom = 2
	await settle()
	var clean := await image(view)
	for tick in range(120):
		step_laser(view.simulation, 1.0 / 30)
	var beam_image := await image(view)
	var pixels: Transform2D = root.get_stretch_transform() * view.get_global_transform_with_canvas() * view.world_transform()
	var center: Vector2 = pixels * Vector2(75, 0)
	check(changed_pixels(clean, beam_image, Rect2i(Vector2i(center) - Vector2i(16, 16), Vector2i(32, 32))) > 30,
		"Native prismatic channel visibly spans the space between source and target")
	beam_image.save_png("res://.local/research-prismatic.png")
	view.simulation.beams.clear()
	view.simulation.research_combat.channels.clear()
	clean = await image(view)
	view.simulation.player.shields = 0
	view.simulation.research_combat.begin_step(view.simulation, 4)
	check(not view.simulation.research_combat.pulse_rings.is_empty(), "Native pulse fixture restores shields at the eight-second boundary")
	var pulse_image := await image(view)
	center = pixels * view.simulation.player.position
	var radius := ceili((view.simulation.player.radius + 6) * pixels.x.length()) + 12
	check(changed_pixels(clean, pulse_image, Rect2i(Vector2i(center) - Vector2i.ONE * radius, Vector2i.ONE * radius * 2)) > 50,
		"Native shield recovery draws an expanding cyan pulse, not a text popup")
	pulse_image.save_png("res://.local/research-shield-pulse.png")
	view.simulation = fixture({"splinter_missiles": true}, "missile_rack", 1)
	step_laser(view.simulation, 0.01)
	var parent: BattleSimulation.Projectile = view.simulation.projectiles[0]
	parent.position = parent.target.position - Vector2(90, 0)
	view.simulation._update_projectiles(0.01)
	var shots: Array[BattleSimulation.Projectile] = view.simulation.projectiles.duplicate()
	view.simulation.projectiles.clear()
	clean = await image(view)
	view.simulation.projectiles.assign(shots)
	var fragment_image := await image(view)
	center = pixels * parent.position
	check(changed_pixels(clean, fragment_image, Rect2i(Vector2i(center) - Vector2i(40, 40), Vector2i(80, 80))) > 30,
		"Native split missile displays separate amber fragments")
	fragment_image.save_png("res://.local/research-splinters.png")
	view.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://research-combat-test.json"
	lasers()
	missiles()
	shields()
	persistence()
	replay()
	await ui()
	print("RESEARCH COMBAT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
