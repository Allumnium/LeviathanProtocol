extends SceneTree

const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

# Demo vertical slice: Haven Dock -> events/battles -> trade/research/repair
# -> Leviathan Protocol broadcast -> Bastion Warden -> demo complete.
const Travel = preload("res://scripts/expedition_state.gd")
var checks := 0
var failures := 0
var state: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func fight() -> int:
	var sim := BattleSimulation.new()
	check(sim.setup_owned(state.get_deployed_fleet(), state.battle_aliens, 0, 0,
			state.battle_simulation_seed(), state.battle_support_context()), "Event battle sets up")
	sim.battle_id = state.battle_identity()
	check(sim.set_objective_targets(state.battle_objective_ids()), "Event battle objectives")
	if not sim.encounter.warden.rules.is_empty():
		var warden = sim.encounter.warden
		var expected := "Destroy Warden" if warden.rules.lance else "Clear escort fleet"
		check(warden.label(sim).begins_with(expected), "Special victory order remains explicit")
		if warden.visible(sim):
			check(warden.label(sim).contains("Protected") == (warden.live_pylons(sim) > 0),
				"Protection readout agrees with actual pylon links")
		var before: Dictionary = warden.snapshot()
		warden.exposed = 3.2
		warden.charging = true
		warden.cycle = 1
		warden.clock = 10
		check(not warden.visible(sim) or (warden.label(sim).contains("Exposed 4s")
			and warden.label(sim).contains("Lance 2s")), "Exact exposure/lance deadlines survive copy reduction")
		warden.exposed = before.exposed
		warden.charging = before.charging
		warden.cycle = before.cycle
		warden.clock = before.clock
	for tick in range(30 * 900):
		sim.advance(1.0 / 30)
		if sim.phase != BattleSimulation.Phase.COMBAT:
			break
	print("DEMO BATTLE %s phase=%d seconds=%.1f" % [state.pending_encounter.get("expedition_event_id"), sim.phase, sim.elapsed])
	check(sim.phase != BattleSimulation.Phase.COMBAT, "Event battle terminates")
	var credits_before: int = state.credits
	check(state.settle_battle(sim), "Event battle settles once")
	check(not state.settle_battle(sim), "Settled battle cannot pay twice")
	if sim.phase == BattleSimulation.Phase.VICTORY:
		check(state.credits > credits_before, "Victory pays credits")
	return sim.phase

func travel(destination: String, choices: Dictionary) -> bool:
	var expedition = state.expedition_simulation
	if not state.depart_expedition(destination):
		check(false, "Depart to " + destination + ": " + state.last_save_error)
		return false
	expedition.set_speed(10)
	for frame in range(20000):
		var result: Dictionary = state.advance_expedition(0.1)
		check(result.ok, "Expedition advances")
		if not result.ok:
			return false
		var pending: String = expedition.state.pending_event_id
		if not pending.is_empty():
			var event: Dictionary = expedition.Events.find(expedition.events, pending)
			var choice: String = choices.get(pending, expedition.Events.options(event)[0].id)
			check(state.resolve_expedition_event(pending, choice), "Resolve " + pending)
			if state.battle_pending:
				check(state.load_run_checkpoint() and state.battle_pending
						and not state.battle_aliens.is_empty(), "Pending event battle survives Continue")
				fight()
				if state.run_ended or state.completed:
					return false
			expedition = state.expedition_simulation
			check(expedition.state.requested_speed == 10, "Fast-forward speed survives %s" % pending)
			expedition.set_speed(10)
			continue
		if expedition.state.destination_location_id.is_empty() and expedition.state.pending_event_id.is_empty():
			return true
	check(false, "Journey to %s finishes" % destination)
	return false

func refit() -> void:
	if not state.can_use_shipyard():
		return
	state.repair_all_ships()
	var fighter := SlotCatalog.find_chassis("fighter")
	var fighter_price := ShipLoadouts.ship_price("fighter", ShipLoadouts.default_for("fighter"))
	if state.credits > fighter_price + 200:
		check(state.buy_ship("fighter"), "Buy an escort fighter")
	if not state.current_research_ids.has("applied_energy"):
		return
	# Upgrade mini turrets to lasers once researched, like a player refitting.
	for owned in state.fleet:
		for slot_id: String in owned.mounts.keys():
			if owned.mounts[slot_id].equipment_id == "mini_turret" and state.credits > 100:
				check(state.swap_part(owned.id, slot_id, "laser"), "Refit a turret to a laser")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://expedition-demo-test.json"
	check(state.start_new_run(1, 4242), "Start demo run")
	var expedition = state.expedition_simulation
	check(expedition.state.pending_event_id.is_empty() and not state.pending_intro,
			"Briefing is a UI intro, not a simulation interruption")
	check(not expedition.location_accessible(expedition.locations.act_2_gate),
			"Bastion Gate starts locked")
	# Trade: a docked shipyard sells a hold; leaving a port loads it.
	var transport: HangarShip
	for owned in state.fleet:
		if owned.chassis_id == "transport":
			transport = owned
	check(transport.mounts.has("hold") and transport.mounts.hold.equipment_id == "cargo_hold",
			"Starter Transport carries a cargo hold")
	check(transport.mounts.values().filter(func(item: Dictionary) -> bool:
			return item.equipment_id in ["hull_plate", "armor_block"]).size() >= 2,
			"Starter Transport fills armor-compatible mounts with plates")
	var hold_uid: String = transport.mounts.hold.uid
	check(not state.research_choice_ready(), "Research begins without a funded choice")
	# Docked waiting freezes expedition time and passive repair.
	var flagship: HangarShip = state.fleet[0]
	flagship.hull_hp -= 50
	check(expedition.state.travel_state == Travel.TravelState.DOCKED
			and not expedition.state.departure_choice_pending, "Docked fleets are never forced to choose a destination")
	var hull_before := flagship.hull_hp
	state.advance_expedition(10.0)
	check(flagship.hull_hp == hull_before, "Docked waiting cannot self-repair the hull")
	check(state.research_points == 0.0, "Docked time earns no research")
	flagship.hull_hp = flagship.hull_max
	check(travel("refuel_station_1", {"derelict_signal": "continue"}), "First leg reaches Kessler")
	check(state.research_points > 0.0
		or state.current_research_ids.has("applied_energy"), "Travel distance fills the research bar")
	check(not HangarTrade.has_load(state.equipment_inventory[hold_uid]), "Haven cargo delivered at Kessler")
	check(state.expedition_simulation.state.event_receipts.get("first_contact", false), "First contact battle happened")
	refit()
	check(travel("derelict_1", {"derelict_salvage": "strip"}), "Detour to derelict field")
	check(HangarTrade.has_load(state.equipment_inventory[hold_uid]), "Cargo stays aboard at uninhabited POI")
	check(travel("settlement_1", {}), "Reach settlement")
	check(travel("distress_1", {"distress_call": "defend"}), "Answer distress call")
	check(state.expedition_simulation.state.flags.get("leviathan_protocol", false)
			and state.expedition_simulation.location_accessible(state.expedition_simulation.locations.act_2_gate),
			"Leviathan Protocol broadcast unlocks the Bastion Gate")
	check(travel("refuel_station_1", {}), "Return to Kessler")
	refit()
	if state.station_service_error("refuel").is_empty() and state.expedition_simulation.state.fuel < 99:
		check(state.refuel_expedition(), "Refuel at Kessler")
	check(travel("meridian_outpost", {"asteroid_corridor": "blast"}), "Reach Meridian Outpost")
	refit()
	travel("act_2_gate", {})
	for attempt in range(3):
		if state.completed or state.run_ended:
			break
		# A withdrawn boss fight stays at the gate and can be faced again.
		check(not state.expedition_simulation.retry_event_here().is_empty()
				and state.expedition_simulation.readmit_arrival_event(), "Warden can be faced again after withdrawing")
		check(state.resolve_expedition_event("bastion_warden", "engage"), "Re-engage the Warden")
		fight()
	check(state.completed and not state.run_ended, "Warden victory completes the demo")
	check(state.current_research_ids.has("applied_energy"), "Demo route completes at least one research project")
	check(state.load_run_checkpoint() and state.completed, "Completed demo persists")
	# Empty tanks never strand the convoy: a quoted tow may leave credit debt.
	check(state.start_new_run(1, 77), "Start rescue fixture")
	expedition = state.expedition_simulation
	for authored: Dictionary in expedition.events:
		expedition.state.event_receipts[authored.id] = true
	expedition.state.fuel = 5.0
	state.credits = 10
	check(state.depart_expedition("meridian_outpost"), "Depart on an empty tank")
	expedition.set_speed(10)
	for frame in range(400):
		state.advance_expedition(0.1)
		if state.stranded():
			break
	var quote: Dictionary = state.rescue_quote()
	check(state.stranded() and not quote.is_empty() and quote.location_id == "start_station",
			"Fuel exhaustion strands the fleet with a tow quote to the nearest refueling station")
	check(state.accept_rescue() and not state.stranded()
			and expedition.state.docked_location_id == "start_station"
			and is_equal_approx(expedition.state.fuel, expedition.state.fuel_capacity)
			and state.credits == 10 - int(quote.fee) and state.credits < 0,
			"Accepted tow docks, refuels and records disclosed debt")
	check(state.load_run_checkpoint() and state.credits < 0
			and state.expedition_simulation.state.docked_location_id == "start_station", "Rescue debt persists")
	print("Expedition demo checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
