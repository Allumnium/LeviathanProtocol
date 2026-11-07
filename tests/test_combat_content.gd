extends "res://tests/test_equipment_balance.gd"

const Effects = preload("res://scripts/equipment_effects.gd")

func fixture() -> DefDatabase:
	var db := Content.load_all(["res://packs", "res://tests/fixtures/content/combat_patch"])
	check(db.problems.items.is_empty(), "Patch-only combat tuning loads without Problems: " + db.problems.text())
	return db

func allocation() -> void:
	var shipped := Content.load_all(["res://packs"])
	check(shipped.problems.items.is_empty(), "Shipped combat defs validate")
	var scout := AlienShip.threat_variant("scout", 1).to_snapshot()
	var original := EncounterGenerator.generate(3741, 17, 9, 1, "patrol", 5, false, {}, false)
	var frozen := EncounterGenerator.generate(3741, 17, 9, 1, "relay_defense", 5)
	frozen.arena_layout = "open"
	check(EncounterGenerator.valid(frozen), "Original three-wave deployment is valid")
	check(SharedSupport.repair_rate() == 2, "Warm support cache before content replacement")
	fixture()
	var changed := AlienShip.threat_variant("core:scout", 1)
	check(changed.threat_cost == 18 and changed.stats.integrity == scout.stats[1], "A price patch changes actual tier cost without changing hull")
	var plan := EncounterGenerator.generate(3741, 17, 9, 1, "patrol", 5, false, {}, false)
	check(EncounterGenerator.valid(plan) and plan.budget == original.budget and plan.roster.size() > original.roster.size(), "Cheaper units change real budget allocation at the same seed and threat")
	check(plan.rewards == original.rewards and plan.roster.any(func(entry: Dictionary) -> bool: return entry.role == "scout" and entry.threat_cost == 18), "Repriced scouts are committed without changing encounter rewards")
	check(EncounterGenerator.valid(frozen) and AlienShip.from_snapshot(scout).to_snapshot() == scout, "Committed waves, copy allowance, prices and stats survive later tuning changes")
	plan = EncounterGenerator.generate(3741, 17, 9, 1, "relay_defense", 5)
	check(EncounterGenerator.valid(plan) and plan.wave_count == 2 and plan.rewards.credits == 168, "Template patches change finite waves and actual rewards")
	var originals: int = plan.roster.filter(func(entry: Dictionary) -> bool: return not entry.has("copy_of")).size()
	check(plan.roster.size() == originals * 2, "Authored copy allowance changes expansion without changing originals")
	plan = EncounterGenerator.generate(3741, 17, 9, 1, "bastion_warden", 5)
	check(EncounterGenerator.valid(plan) and plan.warden.cycle_seconds == 10 and plan.warden.warning_seconds == 2, "Existing Warden rules accept authored timing parameters")
	var sim := setup([owned(["mini_turret"])])
	check(sim.encounter.warden.configure(sim, {}) and not Content.get_def("encounter", "boss_framework").story_eligible, "Allocation-only frameworks remain unavailable to story events")
	Content.set_database(shipped)
	check(SharedSupport.repair_rate() == 2 and AlienShip.threat_variant("scout", 1).threat_cost == 36, "Restoring content invalidates tuning caches")
	broken_patches(shipped)

func support() -> void:
	fixture()
	var sim := setup([owned(["repair_drone_bay"]), owned([], 2)])
	var target := sim.players[1]
	target.position = Vector2(250, 0)
	target.owned_ship.hull_hp -= 10
	sim._refresh_owned_stats(target)
	var before: float = target.owned_ship.hull_hp
	sim.doctrines._heal(sim, sim.player, 1)
	check(is_equal_approx(target.owned_ship.hull_hp - before, 3), "Patched hangar rate and range heal a real ally")
	sim = setup([owned(["repair_station"])])
	sim.player.owned_ship.hull_hp -= 10
	sim._refresh_owned_stats(sim.player)
	before = sim.player.owned_ship.hull_hp
	SharedSupport.repair(sim, 1)
	check(sim.repair_capacity == 30 and is_equal_approx(sim.player.owned_ship.hull_hp - before, 3) and SharedSupport.valid_pool({"capacity": 30, "spent": 3}), "Finite repair allowance, rate and validation use the same parameters")
	sim = setup([owned(["shield_relay"]), owned(["shield_generator"], 2)])
	target = sim.players[1]
	target.position = Vector2(200, 0)
	target.shields = 0
	var total: float = sim.player.shields
	sim.doctrines._relay(sim, sim.player, 1)
	check(is_equal_approx(target.shields, 3) and is_equal_approx(total, sim.player.shields + target.shields), "Patched relay range and rate preserve shield conservation")
	sim.player.shields = 0
	sim.player.since_damage = 2
	sim._update_ship(sim.player, 1)
	check(is_equal_approx(sim.player.shields, 0.6), "Actual shield recharge uses the patched delay and fraction")
	sim = setup([owned(["command_uplink", "tactical_computer"])])
	sim.doctrines._mark(sim, sim.player, 0)
	check(sim.doctrines.marks[sim.player.entity_id].remaining == 6 and sim.doctrines.mark_timers[sim.player.entity_id] == 18, "Mark duration and cooldown use support defs")
	sim._damage(sim.aliens[0], 10, Vector2.ZERO, sim.player, "Probe")
	check(is_equal_approx(sim.player.damage_dealt, 12.5), "Patched mark strength changes actual allied damage")
	sim.player.cooldowns[0] = 5
	sim.doctrines._synchronize(sim, sim.player, 9)
	check(sim.player.cooldowns[0] == 0, "Patched computer interval resets an actual weapon")
	var ship := owned(["ammunition_magazine"])
	check(is_equal_approx(ship.weapon_cycle_rate(), 1.3 + float(ship.chassis.get("weapon_cycle_bonus", 0))), "Patched magazine changes fitted cycling")
	sim = setup([owned(["ion_emitter"])], 100)
	sim._damage(sim.aliens[0], 2, Vector2.ZERO, sim.player, "Ion Emitter")
	check(is_equal_approx(sim.aliens[0].shields, 94), "Patched Ion Emitter multiplier changes actual shield damage")
	check(is_equal_approx(ResearchCombat.ramp_integral(3), 5.25), "Prismatic ramp integrates authored time and strength")
	sim = setup([owned(["shield_generator"])], 0, false, {"pulse_shields": true})
	sim.player.shields = 0
	sim.research_combat.begin_step(sim, 6)
	check(is_equal_approx(sim.player.shields, 6), "Patched pulse interval and fraction restore actual shields")
	var parent := BattleSimulation.Projectile.new()
	parent.source = sim.player
	parent.target = sim.aliens[0]
	parent.position = parent.target.position
	parent.splinter = true
	parent.damage = 10
	parent.speed = 100
	check(sim.research_combat.split(sim, parent) and sim.projectiles.size() == 4 and sim.projectiles.all(func(shot) -> bool: return is_equal_approx(shot.damage, 4)), "Patched split count and damage create actual fragments")
	for pair: Array in [["repair_drone_bay", "3 hull/s"], ["repair_drone_bay", "Range 260"], ["repair_station", "30 hull reserve"], ["shield_relay", "Transfer: 3/s"], ["shield_relay", "Range 210"], ["shield_relay", "after 2s"], ["command_uplink", "+25%"], ["tactical_computer", "9s"], ["ammunition_magazine", "+30%"]]:
		check(Effects.describe(SlotCatalog.find_equipment(pair[0]), {}).contains(pair[1]), "Equipment text follows actual patched behavior: " + pair[1])
	check(Effects.describe(SlotCatalog.find_equipment("laser"), {"prismatic_lasers": true}).contains("2.5x DPS over 3s") and Effects.describe(SlotCatalog.find_equipment("missile_rack"), {"splinter_missiles": true}).contains("4 x 40%"), "Research effect text follows shared primitive parameters")
	ability()
	enemy_support()

func enemy_support() -> void:
	var players: Array[FleetShip] = [owned(["mini_turret"])]
	var enemies: Array[RefCounted] = [AlienShip.from_def("core:support", 1), AlienShip.from_def("core:sentinel", 1), AlienShip.from_def("core:chrysalis", 2)]
	var sim := BattleSimulation.new()
	check(sim.setup_owned(players, enemies, 0, 0, 3741, {"credits_only": true, "enemy_roles": true}), "Configure authored enemy support roles")
	var support_actor := sim.aliens[0]
	var sentinel := sim.aliens[1]
	var chrysalis := sim.aliens[2]
	support_actor.position = Vector2.ZERO
	sentinel.position = Vector2(140, 0)
	chrysalis.position = Vector2(1000, 0)
	sentinel.integrity -= 5
	var before := sentinel.integrity
	check(is_equal_approx(sim.enemy_roles.sources[support_actor.entity_id].reserve, 18), "Enemy repair reserve uses its own authored tier hull multiplier")
	sim.enemy_roles.advance(sim, 1)
	check(is_equal_approx(sentinel.integrity - before, 1) and is_equal_approx(sim.enemy_roles.protection(sim, support_actor), 0.8), "Shipped enemy repair and Sentinel protection retain their rates and boundaries")
	sim.enemy_roles.advance(sim, 3)
	var drones: Array = sim._members.filter(func(actor) -> bool: return actor.has_tag("summon"))
	check(drones.size() == 1 and is_equal_approx(drones[0].stats.integrity, 3.9) and is_equal_approx(drones[0].stats.weapons[0].damage_per_shot, 0.44), "Chrysalis launches the authored rank-two drone with unchanged hull and damage")
	check(drones.size() == 1 and drones[0].stats.weight == 3 and drones[0].stats.thrust == 12 and drones[0].radius == 6 and sim.enemy_roles.sources[chrysalis.entity_id].cooldown == 6, "Drone mass, thrust, collision geometry and launch cadence remain unchanged")

func ability() -> void:
	var sim := setup([owned(["ion_emitter"]), owned([], 2)], 100)
	var target := sim.aliens[0]
	target.position = Vector2(330, 0)
	sim.players[1].position = Vector2(200, 0) # An ally supplies sight beyond the caster's own sight.
	check(sim.abilities.configure({"credits_only": true, "ability_ids": ["ion_pulse"]}) and sim.abilities.can_cast(sim, "ion_pulse", target.position), "Authored Ion Pulse range reaches a target beyond the shipped range")
	sim.doctrines.charges["fixture"] = {"source": target.entity_id}
	check(sim.abilities.cast(sim, "ion_pulse", target.position) and sim.doctrines.charges.is_empty() and sim.abilities.remaining("ion_pulse") == 18, "Actual patched cast interrupts and starts the authored shared cooldown")
	check(sim.abilities.effects[0].radius == 18 and sim.abilities.effects[0].remaining == 3, "Cast duration and visual radius read authored parameters")
	sim.abilities.advance(sim, 3)
	check(not sim.abilities.suppressed(target) and sim.abilities.remaining("ion_pulse") == 15, "Patched suppression expires on simulation time")
	check(not sim.abilities.configure({"credits_only": true, "ability_ids": ["gravity_well"]}), "Unavailable behavior cannot become a current player option")

func broken_patches(shipped: DefDatabase) -> void:
	var folder := "user://combat_bad/invalid/defs"
	DirAccess.make_dir_recursive_absolute(folder)
	DirAccess.remove_absolute(folder + "/encounter.json") # Remove this suite's previous inherited fixture, if rerun.
	FileAccess.open("user://combat_bad/invalid/pack.json", FileAccess.WRITE).store_string(JSON.stringify({"id": "invalid_combat", "name": "Bad combat fixture", "version": "1.0.0", "kind": "content", "depends": [{"id": "core", "version": ">=1.0"}]}))
	for probe: Dictionary in [
		{"type": "enemy_unit", "target": "scout", "set": {"cost": 0}},
		{"type": "enemy_unit", "target": "scout", "set": {"tiers": [{"rank": 0, "cost": 1, "hull": 1, "damage": 1, "weight": 1, "thrust": 1}]}},
		{"type": "encounter_tuning", "target": "default", "set": {"material_weights": [1, 1, 1, 1]}},
		{"type": "support", "target": "repair_aura", "set": {"parameters.rate": 0}},
		{"type": "ability", "target": "ion_pulse", "set": {"parameters": {"movement_rate": 0.5}}},
		{"type": "encounter", "target": "bastion_warden", "set": {"warden.base_template": "core:bastion_warden"}},
		{"type": "encounter", "target": "patrol", "set": {"allocation.waves": 2}},
		{"type": "encounter", "target": "bastion_warden", "set": {"warden.rules.warning_seconds": 20}}
	]:
		FileAccess.open(folder + "/patch.json", FileAccess.WRITE).store_string(JSON.stringify({"def": "patch", "id": "broken", "target": "core:" + probe.target, "target_def": probe.type, "set": probe.set}))
		var db := PackLoader.new().load_packs(["res://packs", "user://combat_bad"])
		check(db.has_pack("core") and not db.has_pack("invalid_combat") and db.content_hash == shipped.content_hash, "Malformed combat patch rolls back without damaging core: " + probe.type + "/" + probe.target)
		check(db.problems.errors().any(func(problem: Dictionary) -> bool: return problem.pack == "invalid_combat" and problem.def == "broken"), "Problems identify the causal combat patch")
	FileAccess.open(folder + "/patch.json", FileAccess.WRITE).store_string(JSON.stringify({"def": "enemy_unit", "id": "field_scout", "parent": "core:scout", "display_name": "Field Scout", "cost": 8}))
	FileAccess.open(folder + "/encounter.json", FileAccess.WRITE).store_string(JSON.stringify({"def": "encounter", "id": "field_trial", "parent": "core:patrol", "allocation": {"type": "standard", "generator": "roster", "required": ["invalid_combat:field_scout"], "waves": 1, "wave_unit": "core:scout", "extras": []}}))
	var custom := Content.load_all(["res://packs", "user://combat_bad"])
	check(custom.problems.items.is_empty(), "Inherited custom enemy and encounter IDs load without a runtime name whitelist")
	var plan := EncounterGenerator.generate(3741, 17, 9, 1, "invalid_combat:field_trial", 5)
	check(EncounterGenerator.valid(plan) and plan.roster[0].name == "Field Scout" and AlienShip.from_snapshot(plan.roster[0]).display_name == "Field Scout", "Custom named enemies allocate and restore through explicit definition IDs")
	Content.set_database(shipped)

func frames() -> void:
	for index in range(5):
		await process_frame

func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "Native pointer target is visible")
	if control == null:
		return
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await frames()
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = motion.position
	press.global_position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	press = press.duplicate()
	press.pressed = false
	press.button_mask = 0
	root.push_input(press, true)
	await frames()

func native() -> void:
	fixture()
	var state := root.get_node("GameState")
	state.run_save_path = "user://combat-content-native.json"
	check(state.start_new_run(1, 61, true, "flagship_science"), "Start a production science convoy with patched support")
	state.pending_intro = false
	state.credits = 10000
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "FLEET"
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	root.size = Vector2i(1280, 720)
	await frames()
	var flagship: int = state.fleet.filter(func(ship: HangarShip) -> bool: return ship.flagship)[0].id
	screen._select_ship(flagship)
	await frames()
	await click(screen.find_child("Loadout_fleet_observatory", true, false))
	check(state.ship_loadout_id(flagship) == "fleet_observatory", "Pointer commits a complete support fit")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await frames()
		var detail: Control = screen.find_child("ShipEquipment_outer_port", true, false)
		var effect: ResourceText = detail.get_child(1)
		var ancestor := detail.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				ancestor.ensure_control_visible(effect)
				ancestor.scroll_vertical += 16 # Clear the skin's lower frame lip.
			ancestor = ancestor.get_parent()
		await frames()
		check(effect.source_text.contains("3 hull/s") and effect.source_text.contains("Range 260") and effect.is_visible_in_tree() and root.get_visible_rect().encloses(effect.get_global_rect()), "Production equipment details display patched rate/range at " + str(resolution))
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://combat-content-%d.png" % resolution.x) == OK, "Capture native authored readout")
	screen.queue_free()
	await frames()
	check(state.load_run_checkpoint() and state.ship_loadout_id(flagship) == "fleet_observatory", "Pointer fit survives Continue with authored support")

func run() -> void:
	if "--native-only" in OS.get_cmdline_user_args():
		check(DisplayServer.get_name() != "headless", "Native display required")
		if DisplayServer.get_name() != "headless":
			await native()
	else:
		allocation()
		support()
	Content.load_all(["res://packs"])
	print("COMBAT CONTENT %sCOMPLETE: %d checks, %d failures" % ["NATIVE " if "--native-only" in OS.get_cmdline_user_args() else "", checks, failures])
	quit(1 if failures else 0)
