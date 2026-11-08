extends SceneTree

const Loadouts = preload("res://scripts/ship_loadouts.gd")
var state: Node
var checks := 0
var failures := 0
var changes := 0
var receipts := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(state.run_save_path)

func group(chassis: String) -> Dictionary:
	for entry: Dictionary in state.squadrons:
		if entry.chassis == chassis:
			return entry
	return {}

func observe_trade(_tx: RunTransaction, _data: Dictionary) -> void:
	receipts += 1

func run() -> void:
	state = root.get_node("GameState")
	Content.load_all(["res://packs"])
	state.run_save_path = "user://run-fleet.json"
	check(state.start_new_run(1, 6241), "Start real run for extracted Fleet/Trade operations")
	state.credits = 10000
	state.current_research_ids.append("civil_hospitality")
	check(state.save_run_checkpoint(), "Fund fleet and earn cabin research")
	state.run_session.changed.connect(func(_sections: PackedStringArray) -> void: changes += 1)
	check(state.run_session.hooks.register("trade.completed", "fleet-test", observe_trade), "Observe transaction trade hooks")
	var count: int = state.fleet.size()
	var gid := int(group("transport").id)
	var price := Loadouts.ship_price("transport", Loadouts.default_for("transport"))
	var credits: int = state.credits
	check(state.buy_ships("transport", 2, gid) and state.fleet.size() == count + 2
		and state.credits == credits - 2 * price and changes == 1 and receipts == 1,
		"Batch purchase publishes once with owning prices, fits and squadron membership")
	var ids: Array = group("transport").members.duplicate()
	var last_id := int(ids.back())
	var uid: String = state.owned_ship(last_id).mounts.hold.uid
	var data: Dictionary = state.hangar_snapshot()
	data.equipment[uid]["load"] = {"kind": "cargo", "quantity": 3, "origin": 0, "unit_value": 3}
	check(state._commit_hangar(data), "Load the last member's physical hold")
	var before: Dictionary = state.run_session.snapshot()
	var durable := bytes()
	var notifications := changes
	check(not state.refit_squadron(gid, "survey") and state.last_save_error.contains("Deliver"), "Late loaded member rejects whole group refit")
	check(SaveValidation.same(before, state.run_session.snapshot()) and bytes() == durable and changes == notifications
		and ids.all(func(id: Variant) -> bool: return state.owned_ship(int(id)).mounts.hold.equipment_id == "cargo_hold"),
		"Rejected group operation rolls back earlier members, allocations, journal and notifications")
	var tx: RunTransaction = state.run_session.begin("rejected-group")
	check(not FleetSystem.refit_squadron(tx, state.run_session.content, gid, "survey", true)
		and not TradeSystem.buy_ammunition(tx, state.run_session.content) and not tx.commit(),
		"Another operation cannot clear an error and commit a partially staged group")
	check(not state.fit_equipment(int(ids[0]), "hold", uid) and state.equipment_inventory[uid].load.quantity == 3,
		"Existing loaded UID cannot be moved between hosts")
	var drones := group("drone")
	var drone_id := int(drones.members[0])
	check(state.refit_ship(drone_id, "laser_drone"), "Create an individual squadron override")
	var retained_uid: String = state.owned_ship(drone_id).mounts.fore.uid
	check(state.refit_squadron(int(drones.id), "courier") and state.ship_loadout_id(drone_id) == "laser_drone"
		and state.owned_ship(drone_id).mounts.fore.uid == retained_uid
		and state.ship_loadout_id(int(drones.members[1])) == "courier", "Group fitting preserves individual overrides and their UIDs")
	check(state.refit_squadron(int(drones.id), "courier", true) and group("drone").overrides.is_empty()
		and state.ship_loadout_id(drone_id) == "courier", "Explicit reset fits all members and clears overrides together")
	data = state.hangar_snapshot()
	data.ships.back().hull_hp = 0.0
	check(state._commit_hangar(data), "Zero hull remains a living loaded escort")
	var equipment: Dictionary = state.equipment_inventory.duplicate(true)
	check(state.repair_squadron(gid) and state.owned_ship(last_id).hull_hp == state.owned_ship(last_id).hull_max
		and SaveValidation.same(equipment, state.equipment_inventory), "Group repair preserves all UIDs and existing loads at zero hull")
	var score: int = state.run_score.credits_earned
	credits = state.credits
	var refund := floori(float(state.owned_ship(last_id).chassis.price) * 0.5)
	check(state.salvage_hangar_ship(last_id) and state.credits == credits + refund
		and state.run_score.credits_earned == score + refund and state.owned_ship(last_id) == null,
		"Salvage refunds and score commit with roster removal")
	check(state.equipment_inventory.has(uid) and not HangarTrade.has_load(state.equipment_inventory[uid]),
		"Salvage retains equipment identity and clears its lost cargo")
	check(not state.salvage_hangar_ship(state.fleet[0].id), "Flagship cannot be salvaged")
	check(state.swap_part(1, "spine", "passenger_cabin"), "Fit earned cabin to flagship")
	var cabin_uid: String = state.owned_ship(1).mounts.spine.uid
	data = state.hangar_snapshot()
	data.equipment[cabin_uid]["load"] = {"kind": "passengers", "quantity": 4, "origin": 0, "unit_value": 4}
	check(state._commit_hangar(data), "Board passengers on a physical UID")
	before = state.run_session.snapshot()
	durable = bytes()
	var path: String = state.run_save_path
	state.run_save_path = "res://project.godot/blocked-fleet.json"
	check(not state.repair_ship(state.fleet[0]) and not state.last_save_error.is_empty(), "Full flagship repair does not create a transaction")
	check(not state.buy_ship("drone") and not state.last_save_error.is_empty(), "Failed storage rejects staged ship purchase")
	check(not state.assign_squadron(int(ids[0])) and not state.last_save_error.is_empty(), "Failed storage rejects staged group split")
	check(not state.move_ships({1: Vector2(0, 1)}) and not state.last_save_error.is_empty(), "Failed storage rejects staged placement")
	check(SaveValidation.same(before, state.run_session.snapshot()) and FileAccess.get_file_as_bytes(path) == durable
		and state.equipment_inventory[cabin_uid].load.quantity == 4, "Failed writes preserve run document, save and passenger ownership")
	state.run_save_path = path
	var owner: DefDatabase = state.run_session.content
	var patched := Content.load_all(["res://packs", "res://tests/fixtures/content/p2"])
	Content.bind_run(patched)
	tx = state.run_session.begin("foreign-global-preview")
	credits = int(tx.doc.fleet.credits)
	check(TradeSystem.buy_ships(tx, owner, "transport", 1, 0, "") and tx.doc.fleet.credits == credits - price,
		"Explicit owner context ignores a different global equipment price and fit cache")
	check(Loadouts.default_for("fighter", owner).id != Loadouts.default_for("fighter", patched).id,
		"Independent catalog queries keep each database's default loadout")
	check(not tx.commit() and SaveValidation.same(before, state.run_session.snapshot()), "Wrong active run cannot publish a preview transaction")
	Content.bind_run(owner)
	var view := FactView.new(before, owner)
	var copy := view.ship(1)
	copy.mounts.clear()
	check(not view.ship(1).mounts.is_empty() and view.can_manage() and view.service_error("shipyard").is_empty(),
		"FactView returns detached rows and station availability from the document")
	check(state.assign_squadron(int(ids[0])) and state.set_squadron_stance(int(HangarSquadrons.for_ship(state.squadrons, int(ids[0])).id), "evade"),
		"Split and orders use transaction-owned squadron data")
	check(state.move_ships({1: Vector2(0, 1)}), "Fleet placement commits through extracted system")
	before = state.run_session.snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.run_session.snapshot())
		and state.owned_ship(1).formation == Vector2(0, 1) and state.equipment_inventory[cabin_uid].load.quantity == 4,
		"Continue retains placement, group orders, journal, score and physical passengers")
	var session: RunSession = state.run_session
	tx = session.begin("fleet-replay-source")
	var replay := session.begin("fleet-replay-preview")
	check(TradeSystem.buy_ships(tx, session.content, "drone", 1, 0, "") and tx.commit(), "Commit deterministic fleet command")
	var expected := session.snapshot()
	tx = replay
	check(TradeSystem.buy_ships(tx, session.content, "drone", 1, 0, "")
		and SaveValidation.same(RunDocument.normalized(tx.doc), expected), "Same input and command reproduce fleet IDs, equipment and receipt exactly")
	check(not tx.commit(), "Replay from earlier state is rejected by stale disk generation")
	print("RUN FLEET COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
