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

func fixture(stance: String) -> BattleSimulation:
	var flagship := HangarShip.new()
	flagship.initialize_chassis("flagship_basic", 1, true)
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

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://squadrons-test.json"
	persistence()
	combat()
	print("SQUADRONS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
