extends SceneTree

# Fleet-command foundation: ships are bought fully fitted from named loadouts
# and refitted at shipyards; there is no equipment stock.
const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")
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

func settle() -> void:
	for index in range(4):
		await process_frame

func loose_equipment() -> int:
	var mounted := {}
	for owned: HangarShip in state.fleet:
		for instance: Dictionary in owned.mounts.values():
			mounted[instance.uid] = true
	return state.equipment_inventory.keys().filter(func(uid: String) -> bool: return not mounted.has(uid)).size()

func ship(chassis_id: String) -> HangarShip:
	for owned: HangarShip in state.fleet:
		if owned.chassis_id == chassis_id and not owned.flagship:
			return owned
	return null

func run() -> void:
	root.size = Vector2i(1280, 720)
	state = root.get_node("GameState")
	state.run_save_path = "user://ship-refit-test.json"
	# Data: every ship class has valid, fully compatible loadouts.
	for chassis: Dictionary in SlotCatalog.chassis():
		var options: Array = ShipLoadouts.for_chassis(chassis.id)
		check(not options.is_empty(), "%s has named loadouts" % chassis.id)
		for loadout: Dictionary in options:
			for slot_id: String in loadout.mounts:
				var item := ShipLoadouts.item_for(str(loadout.mounts[slot_id]))
				check(SlotCatalog.compatible(ShipLoadouts.slot_by_id(chassis, slot_id), item) and ShipLoadouts.obtainable(item),
						"%s/%s/%s fits and is obtainable" % [chassis.id, loadout.id, slot_id])
	check(not ShipLoadouts.obtainable(SlotCatalog.find_equipment("gravitic_snare")), "Deferred parts are not offered")
	check(ShipLoadouts.obtainable(SlotCatalog.find_equipment("railgun")), "Parts are available without research")

	check(state.start_new_run(1, 808), "Start refit fixture")
	for owned: HangarShip in state.fleet:
		check(state.ship_loadout_id(owned.id) == ShipLoadouts.default_for(owned.chassis_id).id
				and owned.hull_hp == owned.hull_max, "%s starts fully fitted with its default loadout" % owned.chassis_id)
	check(loose_equipment() == 0, "There is no loose equipment stock")
	check(not state.has_method("buy_equipment") and not state.has_method("sell_equipment") and not state.has_method("buy_chassis"),
			"Equipment buying/selling and chassis buying are gone")

	# Refit a whole loadout for free, even in credit debt.
	var fighter := ship("fighter")
	var striker: Dictionary = ShipLoadouts.find("fighter", "striker")
	var fee: int = state.refit_quote(fighter.id, striker.mounts)
	state.credits = -10
	var credits: int = state.credits
	check(fee == 0 and state.refit_ship(fighter.id, "striker") and state.credits == credits
			and state.ship_loadout_id(fighter.id) == "striker", "Loadout refit is free even in credit debt")
	check(not state.refit_ship(fighter.id, "striker") and state.credits == credits - fee, "Refitting to the fitted loadout is rejected for free")
	check(loose_equipment() == 0, "Replaced parts are scrapped, not stocked")
	# Swap one part; removing is free; incompatible parts are rejected.
	credits = state.credits
	check(state.swap_part(fighter.id, "fore", "hull_plate")
			and state.credits == credits - ShipLoadouts.part_fee(SlotCatalog.find_equipment("hull_plate"))
			and ship("fighter").mounts.fore.equipment_id == "hull_plate" and state.ship_loadout_id(fighter.id).is_empty(),
			"Single-part swap is free even in credit debt")
	credits = state.credits
	var hull_max := ship("fighter").hull_max
	check(state.swap_part(fighter.id, "fore", "") and state.credits == credits, "Removing a part is free")
	fighter = ship("fighter")
	check(not fighter.mounts.has("fore")
			and fighter.hull_max < hull_max and fighter.hull_hp <= fighter.hull_max, "Removing a part updates hull")
	check(not state.swap_part(fighter.id, "port", "cargo_hold") and not state.swap_part(fighter.id, "port", "shield_generator"),
			"Parts must fit the mount's size and type")
	# Loaded cargo must deliver before its hold is replaced.
	var transport := ship("transport")
	transport.mounts.hold["load"] = {"kind": "cargo", "quantity": 10, "unit_value": 3, "origin": 0}
	credits = state.credits
	check(not state.swap_part(transport.id, "hold", "") and state.credits == credits
			and state.last_save_error.contains("Deliver"), "A loaded hold cannot be removed")
	check(state.refit_ship(transport.id, "tender") and HangarTrade.has_load(ship("transport").mounts.hold),
			"Refits keep an unchanged loaded hold and its cargo")
	ship("transport").mounts.hold.erase("load")
	state.credits = 500
	# Ships are bought fitted.
	var drone_price := ShipLoadouts.ship_price("drone", ShipLoadouts.default_for("drone"))
	credits = state.credits
	var count: int = state.fleet.size()
	check(state.buy_ship("drone") and state.fleet.size() == count + 1 and state.credits == credits - drone_price,
			"Buy Ships charges the fitted price")
	var drone := state.fleet.back() as HangarShip
	check(state.ship_loadout_id(drone.id) == "gun_drone" and drone.hull_hp == drone.hull_max, "Bought ships arrive with their default loadout")
	state.credits = 10
	check(not state.buy_ship("corsair") and state.fleet.size() == count + 1, "Unaffordable ships are rejected atomically")
	state.credits = 5000
	check(state.load_run_checkpoint() and state.ship_loadout_id(state.fleet.back().id) == "gun_drone" and loose_equipment() == 0,
			"Refits and purchases persist with no stock")
	# Shipyard access is required.
	var expedition = state.expedition_simulation
	for authored: Dictionary in expedition.events:
		expedition.state.event_receipts[authored.id] = true
	check(state.depart_expedition("settlement_1"), "Leave the shipyard")
	credits = state.credits
	check(not state.refit_ship(state.fleet[2].id, "escort") and not state.buy_ship("drone") and state.credits == credits,
			"Refits and purchases require a docked shipyard")

	# UI: Map is home; Ships has a refit panel instead of stock.
	check(state.start_new_run(1, 809), "Start UI fixture")
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	check(screen.tabs.get_child(0).text == "MAP" and screen.active_tab == "MAP" and screen.graph != null,
			"Map is the first tab and the home screen")
	screen.active_tab = "FLEET"
	screen._refresh()
	await settle()
	check(screen.roster.find_child("BuyShips", true, false) != null and screen.roster.find_child("BuyEquipment", true, false) == null,
			"Fleet offers Buy Ships")
	screen.roster.find_child("BuyShips", true, false).pressed.emit()
	await settle()
	var offer: HBoxContainer = screen.shop_rows.get_child(0)
	check(str(offer.get_child(1).find_child("ItemName", true, false).source_text).contains("("), "Ship offers name their loadout")
	screen.selected_ship_id = state.fleet[2].id
	screen.active_tab = "SHIPS"
	screen.buy_open = false
	screen._refresh()
	await settle()
	var panel: Control = screen.details.find_child("RefitPanel", true, false)
	check(panel != null and screen.details.find_children("*", "ScrollContainer", true, false).is_empty(),
			"Ships shows a refit panel without stock or scrolling")
	check(panel.find_child("Loadout_interceptor", true, false).disabled
			and not panel.find_child("Loadout_striker", true, false).disabled, "Fitted loadout is marked; others can be chosen")
	check(panel.find_child("Loadout_striker", true, false).text == "Striker",
		"Loadout choice has no refit price")
	panel.find_child("Loadout_striker", true, false).pressed.emit()
	await settle()
	check(state.ship_loadout_id(state.fleet[2].id) == "striker", "Loadout button refits the ship")
	screen.canvas.slot_selected.emit("fore")
	await settle()
	panel = screen.details.find_child("RefitPanel", true, false)
	var options: Control = panel.find_child("PartOptions", true, false)
	check(options != null and options.get_child_count() >= 3, "Clicking a mount lists its compatible parts")
	panel.find_child("Part_hull_plate", true, false).pressed.emit()
	await settle()
	check(state.fleet[2].mounts.fore.equipment_id == "hull_plate", "Part button swaps that mount")
	screen.details.find_child("RemovePart", true, false).pressed.emit()
	await settle()
	check(not state.fleet[2].mounts.has("fore") and screen.selected_slot == "fore"
			and screen.details.find_child("PartOptions", true, false) != null, "An emptied mount stays selected with its part options")
	screen.details.find_child("Part_laser", true, false).pressed.emit()
	await settle()
	check(state.fleet[2].mounts.fore.equipment_id == "laser", "An empty mount can be filled from the picker")
	for viewport_size: Vector2i in [Vector2i(640, 360), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await settle()
		panel = screen.details.find_child("RefitPanel", true, false)
		check(screen.details_panel.get_global_rect().grow(1).encloses(panel.find_child("PartOptions", true, false).get_global_rect()),
				"Part options fit the panel at %s" % viewport_size)
	root.size = Vector2i(1280, 720)
	screen.details.find_child("BackToLoadouts", true, false).pressed.emit()
	await settle()
	check(screen.details.find_child("LoadoutHeading", true, false).text.ends_with("CUSTOM"),
			"A ship matching no named loadout is labelled custom")
	print("SHIP_REFIT_CHECKS=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
