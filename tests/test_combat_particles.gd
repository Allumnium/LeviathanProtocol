extends "res://tests/test_equipment_balance.gd"

func run() -> void:
	var sim := setup([owned(["missile_rack", "repair_drone_bay"]), owned(["beam_lance"], 2)])
	sim.player.owned_ship.hull_hp -= 50
	sim.players[1].owned_ship.hull_hp -= 50
	var visual: Control = load("res://scripts/battle_visuals.gd").new()
	visual.size = Vector2(1280, 720)
	visual.camera_zoom = 1.4
	visual.simulation = sim
	root.add_child(visual)
	await process_frame
	visual.set_process(false)
	sim._update_ship(sim.player, 0.01)
	sim.doctrines.advance(sim, 0.1)
	sim._update_projectiles(0.1)
	sim.elapsed = 0.1
	var random_state: int = sim.random.state
	var before := sim.authoritative_snapshot()
	visual._update_weapon_particles()
	check(not visual._weapon_particles.is_empty() and not sim.doctrines.healing_links.is_empty(), "Weapons and active healing have particle sources")
	check(sim.random.state == random_state and sim.authoritative_snapshot() == before, "Cosmetic particles cannot alter battle state or random stream")
	var particles: Array = visual._weapon_particles.duplicate(true)
	visual._update_weapon_particles()
	check(visual._weapon_particles == particles, "Pause preserves particles without additional emission")
	for index in range(1000):
		visual._add_weapon_particle(Vector2.ZERO, Vector2.ZERO, Color.WHITE, 0.2, 1)
	check(visual._weapon_particles.size() == visual.MAX_WEAPON_PARTICLES, "Weapon particles have a fixed upper bound")
	sim.elapsed += 1
	sim.projectiles.clear()
	visual._update_weapon_particles()
	check(visual._weapon_particles.is_empty() and visual._particle_tracks.is_empty(), "Expired trails and projectile references are removed")
	var shot := BattleSimulation.Projectile.new()
	shot.position = Vector2(10000, 10000)
	shot.source = sim.player
	shot.target = sim.aliens[0]
	sim.projectiles.append(shot)
	sim.elapsed += 0.1
	visual._update_weapon_particles()
	check(visual._weapon_particles.is_empty(), "Offscreen shots create no particles")
	sim.visibility_enabled = true
	sim.refresh_visibility()
	shot.position = Vector2(500, 0)
	sim.elapsed += 0.1
	visual._update_weapon_particles()
	check(visual._weapon_particles.is_empty(), "Hidden shots create no visible trails")
	var replacement := setup([owned(["laser"])])
	visual.simulation = replacement
	visual._update_weapon_particles()
	check(visual._weapon_particles.is_empty() and visual._particle_tracks.is_empty(), "New encounters clear old cosmetic state")
	visual.queue_free()
	await process_frame
	print("COMBAT PARTICLES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
