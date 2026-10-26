extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _setup(seed_value: int) -> BattleSimulation:
	var stats := ShipStats.new()
	stats.integrity = 500.0
	stats.thrust = 25.0
	stats.weapons.append(ShipWeaponStats.new("Replay laser", 0.5, 5.0, 1))
	var fleet: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(3, 1.0, seed_value):
		fleet.append(alien)
	var sim := BattleSimulation.new()
	_check(sim.setup(stats, fleet, seed_value), "Replay fixture initializes.")
	sim.battle_id = "replay/%d" % seed_value
	sim.add_neutral_target("rock/1", 10.0, Vector2.ZERO)
	return sim

func _commands(sim: BattleSimulation, withdraw: bool) -> Array[Dictionary]:
	var commands: Array[Dictionary] = [
		{"id": "cleanup", "tick": 10, "type": "neutral_cleanup", "payload": {"enabled": true}},
		{"id": "attack", "tick": 20, "type": "attack", "payload": {"source": sim.player.entity_id, "target": "rock/1"}},
		{"id": "bad-attack", "tick": 25, "type": "attack", "payload": {"source": sim.player.entity_id, "target": "missing"}},
		{"id": "clear", "tick": 40, "type": "clear_attack", "payload": {"source": sim.player.entity_id}}
	]
	if withdraw:
		commands.append({"id": "retreat", "tick": 120, "type": "withdraw", "payload": {}})
	return commands

func _play(sim: BattleSimulation, batch: int, commands: Array[Dictionary]) -> Dictionary:
	for command in commands:
		_check(sim.queue_command(command), "Replay input queues at its simulation tick.")
	var driver: Control = load("res://scenes/auto_battle.tscn").instantiate()
	# Use the production 30 Hz fixed-step clock without entering the scene tree or
	# starting a real deployment. Rendering callbacks never participate.
	driver.simulation = sim
	driver.visuals = driver.get_node("BattleVisuals")
	var budget := 6000
	while sim.phase == BattleSimulation.Phase.COMBAT and budget > 0:
		driver._advance_fixed_simulation(1.0 / 60.0, float(batch))
		budget -= batch
	_check(sim.phase != BattleSimulation.Phase.COMBAT, "Replay must reach a result within the tick budget.")
	var result := {"snapshot": sim.authoritative_snapshot(), "events": sim.event_log.duplicate(true)}
	driver.free()
	return result

func _run() -> void:
	for seed_value in [1, 5]:
		var owned_baseline: Dictionary = {}
		for batch in [1, 2, 8]:
			var owned_sim := _setup(seed_value)
			var ships: Array[FleetShip] = []
			for index in range(3):
				var owned := FleetShip.new()
				owned.initialize(preload("res://scripts/builtin_ships.gd").drone(), index + 1, "Replay Drone")
				ships.append(owned)
			var fleet: Array[RefCounted] = []
			for member in owned_sim.aliens:
				fleet.append(member.alien)
			_check(owned_sim.setup_owned(ships, fleet, 0.3, 0, seed_value), "Owned replay initializes.")
			var actual := _play(owned_sim, batch, [])
			if batch == 1:
				owned_baseline = actual
			else:
				_check(actual == owned_baseline, "Physical component damage and salvage must replay identically.")
	for seed_value in [7, 42, 2468]:
		for withdraw in [false, true]:
			var normal := _setup(seed_value)
			var commands := _commands(normal, withdraw)
			var baseline := _play(normal, 1, commands)
			for batch in [2, 8]:
				var replay := _setup(seed_value)
				# Round-trip exactly as a saved command stream would be loaded.
				var loaded: Array[Dictionary] = []
				for entry in JSON.parse_string(JSON.stringify(commands)):
					loaded.append(entry)
				var actual := _play(replay, batch, loaded)
				_check(actual == baseline, "Normal/accelerated replay must match all state and events (seed %d, batch %d)." % [seed_value, batch])
			var ids: Dictionary = {}
			var types: Dictionary = {}
			for event in normal.event_log:
				_check(not ids.has(event.id), "Event IDs must be unique within a battle.")
				ids[event.id] = true
				types[event.type] = true
			_check(types.has("command") and types.has("objective"), "Replay records commands and objective results.")
			if not withdraw:
				_check(types.has("expenditure"), "Combat replay records weapon expenditures.")
				_check(types.has("destruction"), "Victory replay records destruction snapshots.")

	var sim := _setup(5)
	var command := {"id": "order/1", "tick": 0, "type": "attack", "payload": {"source": sim.player.entity_id, "target": "rock/1"}}
	_check(sim.execute_command(command), "Valid command executes immediately at its boundary.")
	var events_before := sim.event_log.size()
	_check(sim.execute_command(command) and sim.event_log.size() == events_before, "Duplicate command acknowledges without executing twice.")
	command = command.duplicate(true)
	command.payload.target = sim.aliens[0].entity_id
	_check(not sim.execute_command(command) and sim.player.commanded_target.entity_id == "rock/1", "Conflicting command identity changes nothing.")
	var cooldowns := sim.player.cooldowns.duplicate()
	_check(not sim.issue_command("attack", {"source": sim.player.entity_id, "target": "missing"}) and sim.player.cooldowns == cooldowns, "Rejected commands consume no cooldown.")
	_check(not sim.queue_command({"id": "bad", "tick": -1, "type": "withdraw", "payload": {}}), "Negative command ticks are rejected.")
	var snapshot := sim.authoritative_snapshot()
	snapshot.actors[0].integrity = 0
	_check(sim.player.integrity > 0, "Diagnostic snapshots cannot mutate simulation state.")
	print("Battle replay tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)
