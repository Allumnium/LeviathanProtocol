extends SceneTree

# Player-like progression: normal credit/research APIs, no free unlocks, repairs
# paid from earnings and every combat outcome produced by the real simulation.
var state: Node
var failures := 0
var checks := 0
var summaries: Array[Dictionary] = []
var science_build := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func item_score(item: Dictionary, slot: Dictionary, trade: bool) -> float:
	var stats := SlotCatalog.stats_for(item.id, int(item.rank))
	if slot.type == "offense":
		var dps := 0.0
		for weapon in stats.weapons:
			dps += weapon.get_dps()
		return dps
	if slot.type == "defense":
		return stats.integrity
	if slot.type == "tech":
		if stats.shields > 0:
			return 100 + stats.shields
		if item.id == "repair_drone_bay":
			return 60
		if item.id == "nanoforge":
			return 50
		return stats.thrust
	if item.id == "cargo_hold":
		if science_build:
			return 0
		return 100 if trade else 10
	if item.id == "passenger_cabin":
		return 100 if trade else 1
	if item.id == "research_lab":
		return 20 * int(item.rank) if science_build else 50
	return 0

func outfit(ship_id: int, trade: bool) -> void:
	var original: HangarShip = state.owned_ship(ship_id)
	for slot: Dictionary in original.chassis.slots:
		var owned: HangarShip = state.owned_ship(ship_id)
		var current: Dictionary = owned.mounts.get(slot.id, {})
		var score := -1.0 if current.is_empty() else item_score(SlotCatalog.find_equipment(current.equipment_id, int(current.rank)), slot, trade)
		var best := {}
		for item in SlotCatalog.equipment():
			if not SlotCatalog.compatible(slot, item) or not SlotCatalog.unlocked(item, state.research_grants()):
				continue
			var value := item_score(item, slot, trade)
			if value > score and value > 0:
				score = value
				best = item
		if best.is_empty():
			continue
		var uid := ""
		for instance: Dictionary in state.equipment_inventory.values():
			if instance.equipment_id == best.id and int(instance.rank) == int(best.rank) and state.equipment_location(instance.uid).is_empty():
				uid = instance.uid
				break
		if uid.is_empty() and state.buy_equipment(best.id, int(best.rank)):
			uid = str(state.next_equipment_id - 1)
		if not uid.is_empty():
			check(state.fit_equipment(ship_id, slot.id, uid), "Fit researched owned equipment")

func prepare(trade: bool) -> void:
	var ids: Array[int] = []
	for owned: HangarShip in state.fleet:
		ids.append(owned.id)
	for id in ids:
		var owned: HangarShip = state.owned_ship(id)
		if owned.needs_repair() and state.credits >= owned.repair_cost():
			check(state.repair_ship(owned), "Pay repairs from campaign earnings")
	if not state.is_shipyard_node(state.current_node_id):
		return
	# Keep the flagship's research lab; trade uses the support ships' civic mounts.
	outfit(1, false)
	for id in ids:
		if id != 1:
			outfit(id, trade)
	var shopping := ["fighter", "transport", "corsair", "fighter"] if trade else ["fighter", "corsair", "fighter", "frigate"]
	if science_build:
		shopping = ["frigate", "fighter", "corsair"]
	for key in shopping:
		if state.fleet.any(func(owned: FleetShip) -> bool: return (owned as HangarShip).chassis_id == key):
			continue
		var chassis := SlotCatalog.find_chassis(key)
		# Do not buy an empty hull with no money left for its initial guns.
		if state.credits < int(chassis.price) + 160:
			continue
		if state.buy_chassis(key):
			outfit(state.fleet[-1].id, trade)

func focus(trade: bool) -> void:
	if not state.research_focus.is_empty():
		return
	var sequence := ["applied_energy", "civil_hospitality", "energy_manipulation", "guided_munitions", "field_engineering", "renewal_i", "optics_ii"] if trade else ["applied_energy", "guided_munitions", "energy_manipulation", "field_engineering", "renewal_i", "optics_ii"]
	if science_build:
		sequence = ["applied_energy", "laboratory_ii", "laboratory_iii", "energy_manipulation", "field_engineering", "renewal_i", "optics_ii", "guided_munitions"]
	for key: String in sequence:
		if HangarResearch.eligible(key, state.run_progress_snapshot()):
			check(state.set_research_focus(key), "Set available research focus")
			return

func play(seed_value: int, trade: bool, science := false) -> void:
	science_build = science
	state.run_save_path = "user://natural-%d-%s-%s.json" % [seed_value, trade, science]
	check(state.start_new_run(1, seed_value), "Natural campaign starts")
	var fights := 0
	var seconds := 0.0
	var rows := 0
	while not state.completed and not state.run_ended and rows < 24:
		focus(trade)
		prepare(trade)
		var routes: Array = state.get_reachable_nodes(state.current_node_id)
		var target: int = routes[0]
		for candidate: int in routes:
			if state.campaign_node(candidate).get("elite", false):
				continue
			if state.campaign_node(target).get("elite", false) or state.research_travel_time(state.current_node_id, candidate) > state.research_travel_time(state.current_node_id, target):
				target = candidate
		check(state.travel_to(target), "Natural journey departs")
		if state.battle_pending:
			fights += 1
			var sim := BattleSimulation.new()
			check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0, state.battle_simulation_seed(), state.battle_support_context()), "Natural battle setup")
			sim.battle_id = state.battle_identity()
			check(sim.set_objective_targets(state.battle_objective_ids()), "Natural objectives")
			for tick in range(30 * 240):
				sim.advance(1.0 / 30)
				if sim.phase != BattleSimulation.Phase.COMBAT:
					break
			seconds += sim.elapsed
			print("NATURAL seed=%d trade=%s row=%d ships=%d credits=%d phase=%d seconds=%.1f" % [seed_value, trade, state.campaign_node(target).row, state.fleet.size(), state.credits, sim.phase, sim.elapsed])
			check(sim.phase != BattleSimulation.Phase.COMBAT, "Natural combat terminates")
			check(state.settle_battle(sim), "Natural outcome saved")
			if sim.phase != BattleSimulation.Phase.VICTORY:
				break
		check(state.load_run_checkpoint(), "Natural arrival reloads")
		rows += 1
	var summary := {"seed": seed_value, "trade": trade, "science": science, "completed": state.completed, "ended": state.run_ended, "rows": rows, "fights": fights, "ships": state.fleet.size(), "credits": state.credits, "seconds": seconds, "research": state.current_research_ids.duplicate(), "daily_rp": ScienceRules.production_rate(ScienceRules.snapshot(state.get_deployed_fleet()))}
	summaries.append(summary)
	print("NATURAL SUMMARY ", JSON.stringify(summary))
	check(state.completed, "Natural campaign reaches final victory")
	if science:
		check(state.current_research_ids.has("laboratory_iii") and summary.daily_rp >= 4.5, "Science fleet actually purchases and runs upgraded labs")

func run() -> void:
	state = root.get_node("GameState")
	for seed_value in [42, 1357, 12345]:
		play(seed_value, false)
		play(seed_value, true)
		play(seed_value, false, true)
	var file := FileAccess.open("res://.local/hangar/natural-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summaries, "\t"))
	file.close()
	print("NATURAL CAMPAIGNS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
