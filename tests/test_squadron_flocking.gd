extends "res://tests/test_equipment_balance.gd"

func flock_checks() -> void:
	var friends: Array[FleetShip] = [owned(["mini_turret"]), owned(["mini_turret"], 2), owned(["mini_turret"], 3)]
	for ship: HangarShip in friends:
		ship.squadron_id = 7 if ship.id < 3 else 8
	var enemies: Array[RefCounted] = [alien(), alien(), alien("sentinel")]
	var sim := BattleSimulation.new()
	check(sim.setup_owned(friends, enemies, 0, 0, 7731), "Configure friendly and alien squadrons")
	check(sim.players[0].squadron_id == sim.players[1].squadron_id
		and sim.players[0].squadron_id != sim.players[2].squadron_id,
		"Friendly flock membership follows owned squadrons")
	check(not sim.aliens[0].squadron_id.is_empty() and sim.aliens[0].squadron_id == sim.aliens[1].squadron_id
		and sim.aliens[0].squadron_id != sim.aliens[2].squadron_id, "Aliens form role/tier/wave squadrons")
	for team: Array[BattleSimulation.Combatant] in [sim.players, sim.aliens]:
		team[0].position = Vector2.ZERO
		team[1].position = Vector2(0, 100)
		team[2].position = Vector2(0, -200)
		team[0].velocity = Vector2(100, 0)
		team[1].velocity = Vector2(100, 0)
		for member: BattleSimulation.Combatant in team:
			member.speed = 100
		sim._rebuild_spatial_index()
		var desired := Vector2(0, 100)
		var steered: Vector2 = sim._flock_velocity(team[0], desired)
		check(steered.x > 0 and steered.y > 0 and steered.length() <= 100.001,
			"Cohesion and alignment steer both factions at bounded speed")
		check(sim._flock_velocity(team[2], desired) == desired, "Unrelated squadron cannot influence steering")
		var random_state: int = sim.random.state
		sim._members.reverse()
		sim._rebuild_spatial_index()
		check(sim._flock_velocity(team[0], desired).is_equal_approx(steered)
			and sim.random.state == random_state, "Flock aggregates are independent of update order and combat randomness")
		sim._members.reverse()
		team[1].integrity = 0
		if team[1].owned_ship is HangarShip:
			team[1].owned_ship.hull_hp = -1
		sim._rebuild_spatial_index()
		check(sim._flock_velocity(team[0], desired) == desired, "Destroyed members stop influencing their squadron")
		team[1].integrity = team[1].stats.integrity
		if team[1].owned_ship is HangarShip:
			team[1].owned_ship.hull_hp = team[1].owned_ship.hull_max
	var first := sim.players[0]
	first.commanded_target = sim.aliens[0]
	sim._rebuild_spatial_index()
	check(sim._flock_velocity(first, Vector2.RIGHT * 100) == Vector2.RIGHT * 100,
		"Individual explicit orders do not follow uncommanded squadmates")
	first.commanded_target = null
	first.owned_ship.stance = "evade"
	sim._rebuild_spatial_index()
	check(sim._flock_velocity(first, Vector2.LEFT * 100) == Vector2.LEFT * 100,
		"Opposing stances cannot pull a member back into combat")
	first.owned_ship.stance = "seek"
	first.retreat_time = 1
	sim._rebuild_spatial_index()
	check(sim._flock_velocity(first, Vector2.LEFT * 100) == Vector2.LEFT * 100,
		"Shield retreat has priority over squadron cohesion")
	first.retreat_time = 0
	sim.withdrawing = true
	sim._rebuild_spatial_index()
	check(sim._flock_velocity(first, Vector2.LEFT * 100) == Vector2.LEFT * 100,
		"Withdrawal has priority over squadron cohesion")
	sim.withdrawing = false
	first.position = sim.players[1].position
	sim._rebuild_spatial_index()
	check(sim._separation_velocity(first, Vector2.ZERO).length() > 0, "Collision separation remains active")
	var plan := EncounterGenerator.generate(7731, 22, 6, 1, "relay_defense")
	plan.arena_layout = "open"
	var wave_enemies: Array[RefCounted] = []
	for entry: Dictionary in plan.roster:
		if int(entry.wave) == 0:
			wave_enemies.append(AlienShip.from_snapshot(entry))
	check(sim.setup_owned(friends, wave_enemies, 0, 0, 7731, {"encounter_plan": plan, "enemy_roles": true}),
		"Expanded enemy snapshots round-trip into production encounter setup")
	sim.encounter.advance(sim, 6.1)
	var wave_members: Array[BattleSimulation.Combatant] = []
	for member: BattleSimulation.Combatant in sim.aliens:
		if member.alien.wave_index == 1:
			wave_members.append(member)
	check(wave_members.size() >= 2 and wave_members.all(func(member: BattleSimulation.Combatant) -> bool:
		return not member.squadron_id.is_empty()), "Frozen reinforcements join alien squadrons on spawn")
	var warden := AlienShip.warden_variant(false, 1, 0, 1)
	var pylon := AlienShip.warden_variant(true, 1, 0, 1)
	check(sim.setup_owned(friends, [warden, pylon], 0, 0, 7731), "Configure authored boss bodies")
	check(sim.aliens.all(func(member: BattleSimulation.Combatant) -> bool: return member.squadron_id.is_empty()),
		"Boss bodies and pylons stay outside mobile flocks")

func relay_checks() -> void:
	var sim := setup([owned(["shield_relay"]), owned(["shield_generator"], 2)])
	sim.players[1].shields = 0
	var total: float = sim.player.shields + sim.players[1].shields
	sim.doctrines.advance(sim, 0.25)
	check(sim.doctrines.shield_links.size() == 1 and sim.doctrines.shield_links[0].shields > 0,
		"Only actual relay transfers create blue particle beam sources")
	check(is_equal_approx(total, sim.player.shields + sim.players[1].shields), "Visual transfer sources preserve shield conservation")
	sim.player.shields = 0
	sim.doctrines.advance(sim, 0.25)
	check(sim.doctrines.shield_links.is_empty(), "Empty donors clear expired beam sources")
	sim.player.shields = sim.player.stats.shields
	sim.players[1].position = Vector2(181, 0)
	sim.doctrines.advance(sim, 0.25)
	check(sim.doctrines.shield_links.is_empty(), "Out-of-range targets produce no relay beam")

func motion_checks() -> void:
	var friends: Array[FleetShip] = [owned(["mini_turret"]), owned(["mini_turret"], 2)]
	for ship: HangarShip in friends:
		ship.squadron_id = 7
	var sim := BattleSimulation.new()
	check(sim.setup_owned(friends, [alien(), alien()], 0, 0, 7731), "Configure bounded actual squadron motion")
	for team: Array[BattleSimulation.Combatant] in [sim.players, sim.aliens]:
		for index in range(team.size()):
			var member := team[index]
			member.position = Vector2(-300 if member.is_player else 300, -60 if index == 0 else 60)
			member.heading = (0 if member.is_player else PI) + (PI / 2 if index == 0 else 0)
			member.speed = 100
			member.acceleration = 100
			member.turn_rate = 6
			member.commanded_target = sim.aliens[0] if member.is_player else sim.players[0]
	for tick in range(90):
		sim.advance(1.0 / 30)
	check(sim.phase == BattleSimulation.Phase.COMBAT and is_equal_approx(sim.elapsed, 3),
		"Actual motion check completes its bounded three-second sample")
	for team: Array[BattleSimulation.Combatant] in [sim.players, sim.aliens]:
		var alignment := team[0].velocity.normalized().dot(team[1].velocity.normalized())
		var separation := team[0].position.distance_to(team[1].position)
		check(alignment >= 0.8 and separation <= 180,
			"Same-squadron actual flight aligns and stays cohesive: dot %.3f, spacing %.1f" % [alignment, separation])

func native_effects() -> void:
	var sim := setup([owned(["shield_relay"]), owned(["shield_generator"], 2)], 100, true)
	sim.player.position = Vector2(-140, -70)
	sim.players[1].position = Vector2(0, -70)
	sim.players[1].shields = 0
	sim.aliens[0].position = Vector2(0, 70)
	sim.aliens[0].shield_flash = 0.2
	sim.aliens[1].position = Vector2(140, 70)
	sim.aliens[1].shields = 100
	sim.doctrines.advance(sim, 0.25)
	sim.elapsed = 0.25
	var visual: Control = load("res://scripts/battle_visuals.gd").new()
	visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual.camera_zoom = 1.4
	visual.simulation = sim
	root.add_child(visual)
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for frame in range(4):
			await process_frame
		var before := sim.authoritative_snapshot()
		visual.queue_redraw()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://relay-shields-%d.png" % resolution.x) == OK,
			"Capture blue relay beam and alien silhouette shields")
		check(sim.authoritative_snapshot() == before, "Rendering cannot alter combat")
	var combat_blue := blue_pixels(root.get_texture().get_image())
	sim.phase = BattleSimulation.Phase.VICTORY
	visual.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(blue_pixels(root.get_texture().get_image()) < combat_blue,
		"Blue relay beams disappear after combat instead of showing stale transfers")
	visual.queue_free()
	await process_frame

func blue_pixels(image: Image) -> int:
	image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	var count := 0
	for index in range(0, pixels.size(), 4):
		if pixels[index + 2] > pixels[index] + 40 and pixels[index + 2] > pixels[index + 1] + 10:
			count += 1
	return count

func run() -> void:
	if "--visual-only" not in OS.get_cmdline_user_args():
		flock_checks()
		relay_checks()
		motion_checks()
	if DisplayServer.get_name() != "headless":
		await native_effects()
	print("SQUADRON FLOCKING AND RELAYS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
