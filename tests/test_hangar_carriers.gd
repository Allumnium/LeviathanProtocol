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

func carrier(kind := "flight_deck", uid := "1") -> HangarShip:
	var ship := HangarShip.new()
	ship.initialize_chassis("flagship_basic" if kind == "flight_deck" else "corsair", 1, true)
	var item := SlotCatalog.find_equipment(kind)
	ship.mounts["port" if kind == "flight_deck" else "fore"] = {"uid": uid, "equipment_id": kind, "rank": 1, "hp": item.hit_points}
	ship.rebuild_units()
	return ship

func simulation(ship: HangarShip, pool: Dictionary = {}) -> BattleSimulation:
	var stats := ShipStats.new()
	stats.integrity = 5000
	stats.weight = 10
	stats.weapons.append(ShipWeaponStats.new("Test target", 100, 0.01, 1, 1))
	var enemy := AlienShip.new("Test target", AlienShip.SCOUT_TEXTURE, stats)
	var fleet: Array[RefCounted] = [enemy]
	var ships: Array[FleetShip] = [ship]
	var sim := BattleSimulation.new()
	check(sim.setup_owned(ships, fleet, 0, 0, 751, {"credits_only": true, "doctrine_pool": pool}), "Carrier-only fleet starts without a dummy gun")
	if sim.players.is_empty():
		return sim
	sim.player.position = Vector2.ZERO
	sim.aliens[0].position = Vector2(100, 0)
	return sim

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://carrier-tests.json"
	check(state.start_new_run(1, 1357), "Start physical carrier fixture")
	var original: Dictionary = state.hangar_snapshot()
	check(not state.buy_equipment("flight_deck") and state.hangar_snapshot() == original, "Locked bay cannot be bought or debit credits")
	check(not state.set_research_focus("carrier_i"), "Carrier research requires Guided Munitions")
	var fixture := original.duplicate(true)
	fixture.credits = 5000
	fixture.research.research_ids.append_array(["guided_munitions", "carrier_i", "carrier_ii"])
	fixture.research.branch_choices["force_projection"] = "carrier"
	check(state._commit_hangar(fixture), "Research-gated carrier fixture validates")
	check(state.buy_equipment("flight_deck"), "Shipyard sells physical researched Flight Deck")
	var deck_uid := str(state.next_equipment_id - 1)
	check(not state.fit_equipment(1, "fore", deck_uid), "Wrong type/size does not accept a deck")
	check(state.fit_equipment(1, "port", deck_uid), "Exact M offense accepts owned deck")
	check(state.buy_chassis("corsair") and state.buy_equipment("torpedo_bomber_bay"), "Buy bomber host and researched bay")
	var bomber_uid := str(state.next_equipment_id - 1)
	var corsair: HangarShip = state.fleet[-1]
	check(state.fit_equipment(corsair.id, "fore", bomber_uid), "Exact L offense accepts bomber bay")
	check(state.load_run_checkpoint() and not state.equipment_location(deck_uid).is_empty(), "Equipment ownership survives reload")
	check(HangarResearch.registry().research.any(func(row: Dictionary) -> bool: return row.id == "carrier_ii"), "Carrier branch is in the actual tree")
	check(SlotCatalog.find_equipment("flight_deck").size == "M" and SlotCatalog.find_equipment("torpedo_bomber_bay").size == "L", "Draft mounts provide exact fitting opportunities")
	var sim := simulation(carrier())
	sim.doctrines.advance(sim, 0.1)
	check(sim.doctrines.carriers.sorties.size() == 1 and sim.doctrines.pool.carriers["1"].spent == 1, "Launch spends exactly one replacement")
	var craft: BattleSimulation.Combatant = sim.doctrines.carriers.sorties[0].actor
	check(craft.has_tag("interceptor") and craft.sortie_ammo == 12, "Interceptor has a finite weapon allowance")
	craft.position = Vector2(30, 0)
	craft.sortie_ammo = 1
	craft.cooldowns[0] = 0
	sim._update_ship(craft, 0.01)
	var dealt := craft.damage_dealt
	check(craft.sortie_ammo == 0 and dealt > 0, "Last interceptor shot spends its final activation")
	check(sim.player.damage_dealt == dealt, "Craft damage is attributed to its host report")
	craft.cooldowns[0] = 0
	sim._update_ship(craft, 0.01)
	check(craft.damage_dealt == dealt, "Empty sortie cannot fire again")
	sim.doctrines.advance(sim, 0.1)
	check(not craft.is_alive(), "Spent sortie leaves combat")
	for index in range(30):
		sim.doctrines.advance(sim, 4)
		check(sim.doctrines.carriers.sorties.size() <= 2, "Active craft count stays bounded")
		for job: Dictionary in sim.doctrines.carriers.sorties:
			job.actor.integrity = 0
	check(sim.doctrines.pool.carriers["1"].spent == 6, "Destroyed craft never exceed six replacements")
	var restored := simulation(carrier(), JSON.parse_string(JSON.stringify(sim.doctrines.pool)))
	restored.doctrines.advance(restored, 60)
	check(restored.doctrines.carriers.sorties.is_empty(), "Retry does not refill a spent bay")
	var moved := carrier()
	moved.mounts["starboard"] = moved.mounts["port"]
	moved.mounts.erase("port")
	moved.rebuild_units()
	var transferred := simulation(moved, sim.doctrines.pool)
	transferred.doctrines.advance(transferred, 60)
	check(transferred.doctrines.carriers.sorties.is_empty(), "Moving the same UID cannot refill replacements")
	var fresh := simulation(carrier())
	fresh.doctrines.advance(fresh, 0.1)
	var orphan: BattleSimulation.Combatant = fresh.doctrines.carriers.sorties[0].actor
	fresh.player.owned_ship.units[2].hp = 0
	fresh._refresh_owned_stats(fresh.player)
	check(not orphan.is_alive() and fresh.doctrines.carriers.sorties.is_empty(), "Bay destruction disables its active sorties")
	var bomber := simulation(carrier("torpedo_bomber_bay"))
	bomber.doctrines.advance(bomber, 0.1)
	var strike: BattleSimulation.Combatant = bomber.doctrines.carriers.sorties[0].actor
	strike.position = Vector2(30, 0)
	check(strike.has_tag("bomber") and strike.sortie_ammo == 2, "Bomber has two torpedoes")
	bomber._update_ship(strike, 0.01)
	check(bomber.projectiles.size() == 1 and bomber.projectiles[0].interceptable and strike.sortie_ammo == 1, "Bomber launches an interceptable torpedo")
	counter_checks(bomber, strike)
	for index in range(1000):
		bomber.advance(1.0 / 30)
	check(bomber.player.damage_dealt > 0 and bomber.player.weapon_damage.has("Bomber Torpedo"), "Natural simulated sorties damage enemies and enter host reports")
	var capped := simulation(carrier())
	for index in range(63):
		var actor := BattleSimulation.Combatant.new()
		actor.entity_id = "cap/%d" % index
		actor.stats = ShipStats.new()
		actor.integrity = 1
		actor.faction = 1
		check(capped.register_entity(actor), "Register bounded entity fixture")
	capped.doctrines.advance(capped, 10)
	check(capped.doctrines.carriers.sorties.is_empty() and capped.doctrines.pool.carriers["1"].spent == 0, "Entity cap blocks launch without spending craft")
	pool_checks(sim.doctrines.pool, deck_uid)
	await native_checks()
	print("HANGAR CARRIERS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func counter_checks(sim: BattleSimulation, bomber: BattleSimulation.Combatant) -> void:
	# The same interception API serves enemy/allied point defense; it must check IFF.
	var defender_ship := HangarShip.new()
	defender_ship.initialize_chassis("drone", 2)
	var item := SlotCatalog.find_equipment("point_defense_turret")
	var mount: String = defender_ship.chassis.slots[0].id
	defender_ship.mounts[mount] = {"uid": "20", "equipment_id": item.id, "rank": 1, "hp": item.hit_points}
	defender_ship.rebuild_units()
	var defender := sim._create_combatant(defender_ship.get_stats())
	defender.owned_ship = defender_ship
	defender.faction = 1
	defender.entity_id = "test/point_defense"
	defender.position = Vector2(80, 0)
	check(sim.register_entity(defender), "Register actual point-defense counter")
	var shot: BattleSimulation.Projectile = sim.projectiles[0]
	shot.position = defender.position
	check(SharedSupport.intercept(sim, defender, defender.stats.weapons[0], defender.position), "Hostile point defense intercepts a bomber torpedo")
	check(sim.projectiles.is_empty(), "Intercepted torpedo cannot deal hull damage")
	defender.position = bomber.position
	check(SharedSupport.weapon_target(sim, defender, defender.stats.weapons[0], defender.position) == bomber, "Point defense prioritizes visible hostile craft")
	defender_ship.hull_hp = -1
	var screen_sim := simulation(carrier())
	screen_sim.doctrines.advance(screen_sim, 0.1)
	var interceptor: BattleSimulation.Combatant = screen_sim.doctrines.carriers.sorties[0].actor
	var missile := BattleSimulation.Projectile.new()
	missile.source = screen_sim.aliens[0]
	missile.target = screen_sim.player
	missile.interceptable = true
	missile.position = interceptor.position
	missile.damage = 10
	screen_sim.projectiles.append(missile)
	check(SharedSupport.intercept(screen_sim, interceptor, interceptor.stats.weapons[0], interceptor.position), "Interceptors screen hostile missile locks")
	missile.source = screen_sim.player
	missile.target = screen_sim.aliens[0]
	screen_sim.projectiles.append(missile)
	check(not SharedSupport.intercept(screen_sim, interceptor, interceptor.stats.weapons[0], interceptor.position), "Interceptors preserve friendly missiles")

func pool_checks(pool: Dictionary, uid: String) -> void:
	check(CombatDoctrines.valid_pool(pool), "Finite carrier reserve validates")
	for field in ["spent", "capacity", "equipment_id"]:
		var invalid := pool.duplicate(true)
		invalid.carriers["1"][field] = -1 if field != "equipment_id" else "missile_rack"
		check(not CombatDoctrines.valid_pool(invalid), "Reject invalid carrier reserve " + field)
	var data: Dictionary = state.hangar_snapshot()
	var reserve := pool.duplicate(true)
	reserve.carriers = {uid: pool.carriers["1"].duplicate(true)}
	data.battle_reserves["1"] = reserve
	check(state._commit_hangar(data) and state.load_run_checkpoint(), "Spent reserves round-trip through atomic physical saves")
	var before: Dictionary = state.hangar_snapshot()
	var invalid := before.duplicate(true)
	invalid.battle_reserves["1"].carriers[uid].equipment_id = "torpedo_bomber_bay"
	invalid.battle_reserves["1"].carriers[uid].capacity = 4
	invalid.battle_reserves["1"].carriers[uid].spent = 4
	check(not state._commit_hangar(invalid) and state.hangar_snapshot() == before, "Reject equipment/reserve identity mismatch without mutation")

func native_checks() -> void:
	root.size = Vector2i(1280, 720)
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await process_frame
	await process_frame
	screen.selected_ship_id = 1
	screen.selected_slot = "port"
	screen._show_details()
	check(text_under(screen.details).contains("6 craft / 2 active"), "Selected bay explains its finite allowance inline")
	screen.queue_free()
	await process_frame
	for step in range(3):
		if state.battle_pending:
			break
		check(state.travel_to(state.get_reachable_nodes(state.current_node_id)[0]), "Reach actual carrier encounter")
	check(state.battle_pending, "Actual carrier battle is pending")
	var battle: Control = load("res://scenes/auto_battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	await process_frame
	for tick in range(30):
		battle.simulation.advance(1.0 / 30)
	await process_frame
	check(battle.simulation.doctrines.carriers.available(battle.simulation).y > 0, "Actual battle launches physical inventory craft")
	check(battle.repair_label.text.contains("CRAFT:"), "Battle shows remaining/active craft without another window")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/carriers/battle.png")
	battle.queue_free()
	await process_frame
	# Let the music crossfade release the outgoing stream before test shutdown.
	await create_timer(0.5).timeout

func text_under(node: Node) -> String:
	var result: String = node.text if node is Label else ""
	for child in node.get_children():
		result += "\n" + text_under(child)
	return result
