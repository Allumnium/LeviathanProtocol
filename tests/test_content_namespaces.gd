extends SceneTree

const Loadouts = preload("res://scripts/ship_loadouts.gd")
const Events = preload("res://scripts/expedition_events.gd")
var checks := 0
var failures := 0
var state: Node
var shipped: DefDatabase

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func clone_def(type: String, id: String, owner := "core") -> Dictionary:
	var result := shipped.get_def(type, id, owner).duplicate(true)
	result.erase("id")
	for ref: Dictionary in shipped.schemas.validate(type, result).refs:
		Content._replace(result, ref.path, shipped.resolve_id(ref.type, ref.value, owner))
	result["def"] = type
	result["id"] = id
	return result

func fixture() -> void:
	shipped = Content.load_all(["res://packs"])
	for pack: String in ["amber", "violet"]:
		var folder := "user://namespace_packs/" + pack
		DirAccess.make_dir_recursive_absolute(folder + "/defs")
		FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string(JSON.stringify({
			"id": pack, "name": pack.capitalize(), "version": "1.0.0", "kind": "content",
			"depends": [{"id": "core", "version": ">=1.0"}]}))
		var part := clone_def("part", "laser")
		part.ability_ids = ["ion_pulse"]
		var equipment := clone_def("equipment", "laser")
		equipment.name = pack.capitalize() + " Laser"
		equipment.stats.weapons[0].damage = 7 if pack == "amber" else 11
		var chassis := clone_def("chassis", "drone")
		chassis.name = pack.capitalize() + " Drone"
		chassis.default_loadout = "drone/laser_drone"
		var loadout := clone_def("loadout", "drone/laser_drone")
		loadout.chassis = "drone"
		loadout.name = pack.capitalize() + " Lasers"
		for slot: String in ["fore", "port", "starboard"]:
			loadout.mounts[slot] = "laser"
		var refit := clone_def("loadout", "drone/laser_drone")
		refit.id = "drone/alternate"
		refit.chassis = "drone"
		refit.name = pack.capitalize() + " Mixed"
		refit.mounts.fore = "laser"
		var family := {"def": "research_family", "id": "energy", "label": pack.capitalize() + " Energy", "paths": ["optics", "disruption"]}
		var research := clone_def("research", "applied_energy")
		research.display_name = pack.capitalize() + " Energy"
		research.family_id = "energy"
		research.path_id = "optics"
		research.grants.equipment_ids = ["laser"]
		research.grants.ability_ids = ["ion_pulse"]
		var ability := clone_def("ability", "ion_pulse")
		ability.source_equipment_id = "laser"
		ability.source_research_capability = "laser"
		ability.cooldown_seconds = 17 if pack == "amber" else 19
		var enemy := clone_def("enemy_unit", "scout")
		enemy.cost = 2 if pack == "amber" else 3
		var encounter := clone_def("encounter", "patrol")
		encounter.allocation.required = ["scout"]
		var package := {"def": "fleet_package", "id": "convoy", "members": [
			{"id": "lead", "selected_flagship": true, "count": 1, "position": [0, 0], "spacing": 1},
			{"id": "escorts", "chassis": "drone", "count": 2, "position": [0, 1], "spacing": 1},
			{"id": "core_escort", "chassis": "core:drone", "count": 1, "position": [1, 2], "spacing": 1}]}
		var location := clone_def("location", "start_station", "leviathan")
		location.name = pack.capitalize() + " Home"
		location.trade_id = 20 if pack == "amber" else 21
		location.chassis_stock = ["drone", "core:fighter"]
		location.featured = ["drone"]
		var event := {"def": "event", "id": "first_contact", "trigger": "arrival", "location_id": "start_station",
			"title": pack.capitalize() + " Contact", "text": "A scoped content trial.", "options": [
				{"id": "fight", "label": "BATTLE", "effects": {"combat": {"id": "trial", "template": "patrol", "row": 9}, "rescue_ship": "drone"}}]}
		var start := {"def": "run_start", "id": "charter", "fleet": "convoy", "location": "start_station", "credits": 600, "missiles": 0}
		var core_start := start.duplicate(true)
		core_start.id = "core_start"
		core_start.fleet = "core:convoy"
		core_start.location = "leviathan:start_station"
		# The start explicitly references another pack, so declare that dependency.
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/pack.json"))
		manifest.depends.append({"id": "leviathan", "version": ">=1.0"})
		FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string(JSON.stringify(manifest))
		FileAccess.open(folder + "/defs/content.json", FileAccess.WRITE).store_string(JSON.stringify({
			"defs": [part, equipment, chassis, loadout, refit, family, research, ability, enemy, encounter, package, location, event, start, core_start]}))
	var database := Content.load_all(["res://packs", "user://namespace_packs"])
	check(database.problems.items.is_empty(), "Independent packs with colliding names load: " + database.problems.text())

func runtime_checks() -> void:
	check(not GameDefinitions.snapshot().is_empty(), "Runtime registry accepts scoped duplicate primitive metadata")
	check(Content.runtime_id("research", "applied_energy") == "applied_energy"
		and Content.runtime_id("research", "applied_energy", "amber") == "amber:applied_energy", "Core shorthand and owner-relative references remain distinct")
	check(Loadouts.default_for("amber:drone").mounts.fore == "amber:laser"
		and Loadouts.default_for("violet:drone").mounts.fore == "violet:laser", "Each chassis resolves its own default loadout and mounts")
	check(Content.db().get_def("loadout", "amber:drone/laser_drone").mounts.fore == "laser", "Runtime projections preserve authored data")
	var writable := Content.view("loadout", "amber:drone/laser_drone")
	writable.mounts.fore = "core:mini_turret"
	check(Content.view("loadout", "amber:drone/laser_drone").mounts.fore == "amber:laser", "Writable projections do not mutate the cached view")
	check(state.start_new_run(1, 3741, true, "flagship_basic", "amber:core_start") and state.fleet.size() == 13
		and state.fleet[3].chassis_id == "drone", "Explicit references to the core fleet cannot be rebound by a pack's local namesakes")
	check(state.start_new_run(1, 3741, true, "core:flagship_basic", "amber:charter"), "Actual New Run resolves a scoped starter, package, chassis and fit")
	if state.run_id.is_empty():
		return
	var escort: HangarShip = state.fleet[1]
	check(state.fleet.size() == 4 and state.fleet.back().chassis_id == "drone" and escort.chassis_id == "amber:drone"
		and escort.mounts.fore.equipment_id == "amber:laser"
		and state.expedition_simulation.state.docked_location_id == "amber:start_station", "Owned ship, inventory and starting dock store stable qualified identities")
	check(escort.get_stats().weapons[0].damage_per_shot == 7 and SlotCatalog.stats_for("violet:laser").weapons[0].damage_per_shot == 11,
		"Colliding physical equipment retains independent actual weapon stats")
	var before: Dictionary = state.hangar_snapshot()
	var save_path: String = state.run_save_path
	state.run_save_path = "res://project.godot/blocked-namespace.json"
	check(not state.refit_ship(escort.id, "amber:drone/alternate") and SaveValidation.same(before, state.hangar_snapshot()), "Failed scoped refit rolls back ship, equipment UIDs and squadron")
	state.run_save_path = save_path
	check(state.refit_ship(escort.id, "amber:drone/alternate") and state.ship_loadout_id(escort.id) == "amber:drone/alternate", "Actual station refit accepts a qualified loadout")
	for pack: String in ["amber", "violet"]:
		var research_id := pack + ":applied_energy"
		var data: Dictionary = state.hangar_snapshot()
		data.research.research_points = HangarResearch.threshold(data.research)
		data.research.research_offer = [research_id]
		check(state._commit_hangar(data) and state.choose_research(research_id), "Actual research choice commits " + research_id)
		check(state.research_branch_choices.get(pack + ":energy") == "optics"
			and state.research_grants().ability_ids.has(pack + ":ion_pulse"), "Scoped family and ability grants remain independent: " + pack)
		var plan := EncounterGenerator.generate(3741, pack + ":trial", 9, 1, pack + ":patrol", 5)
		check(EncounterGenerator.valid(plan) and plan.roster[0].definition_id == pack + ":scout", "An encounter resolves its mandatory enemy in its own pack: " + pack)
		check(AlienShip.from_snapshot(plan.roster[0]).to_snapshot() == plan.roster[0], "Scoped enemy snapshots reconstruct exactly: " + pack)
	check(state.research_branch_choices.size() == 2 and state.current_research_ids.has("amber:applied_energy")
		and state.current_research_ids.has("violet:applied_energy") and not state.current_research_ids.has("applied_energy"), "Same local research name does not grant or lock another pack's project")
	before = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot()), "Continue restores scoped fittings, UIDs, research, grants and family commitments")
	var abilities := BattleAbilities.new()
	check(abilities.configure({"credits_only": true, "ability_ids": state.research_grants().ability_ids})
		and GameDefinitions.find("abilities", "amber:ion_pulse").cooldown_seconds == 17
		and GameDefinitions.find("abilities", "violet:ion_pulse").cooldown_seconds == 19, "Same-named granted abilities configure independently")
	var event := Events.find(state.expedition_simulation.events, "amber:first_contact")
	check(event.location_id == "amber:start_station" and event.options[0].effects.combat.id == "amber:trial"
		and event.options[0].effects.combat.template == "amber:patrol", "Scoped events resolve their own location, template and explicit combat identity")
	state.expedition_simulation._admit_event(event)
	check(state.resolve_expedition_event("amber:first_contact", "fight") and state.pending_encounter.node_id == "amber:trial"
		and state.fleet.back().chassis_id == "amber:drone" and state.pending_encounter.roster[0].definition_id == "amber:scout", "Actual scoped event choice commits its rescue and enemy composition")
	before = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot())
		and state.expedition_simulation.state.event_receipts.get("amber:first_contact", false)
		and not state.expedition_simulation.state.event_receipts.get("violet:first_contact", false), "Continue preserves scoped event receipts and frozen encounter without resolving its namesake")
	Content.set_database(shipped)
	check(SlotCatalog.find_chassis("amber:drone").is_empty() and Loadouts.default_for("drone").id == "gun_drone"
		and not GameDefinitions.snapshot().is_empty(), "Replacing the database clears scoped catalog and projection caches")

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://namespaces.json"
	fixture()
	var native := "--native-only" in OS.get_cmdline_user_args()
	if failures == 0:
		if native:
			await native_checks()
		else:
			runtime_checks()
	print("CONTENT NAMESPACES %sCOMPLETE: %d checks, %d failures" % ["NATIVE " if native else "", checks, failures])
	quit(1 if failures else 0)

func settle() -> void:
	await create_timer(0.2).timeout
	for frame in 4:
		await process_frame

func click(button: Button) -> void:
	check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "Pointer target is available")
	if not is_instance_valid(button):
		return
	await reveal(button)
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.global_position = motion.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func reveal(control: Control) -> void:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
			ancestor.scroll_vertical += 16
		ancestor = ancestor.get_parent()
	await settle()

func text_under(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children():
		result += text_under(child)
	return result

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://" + name + ".png") == OK, "Capture " + name)

func native_checks() -> void:
	check(DisplayServer.get_name() != "headless", "Namespace UI requires native rendering")
	if DisplayServer.get_name() == "headless":
		return
	check(state.start_new_run(1, 3741, true, "flagship_basic", "amber:charter"), "Start native scoped fleet")
	state.pending_intro = false
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	screen.active_tab = "FLEET"
	root.size = Vector2i(1280, 720)
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	check(screen._station_stock("chassis_stock", ["fighter", "drone"])[0] == "amber:drone", "Scoped station stock and featured priority use its owning pack")
	var escort: int = state.fleet[1].id
	screen._select_ship(escort)
	await settle()
	var button: Button = screen.find_child("Loadout_" + "amber:drone/alternate".validate_node_name(), true, false)
	await click(button)
	check(state.ship_loadout_id(escort) == "amber:drone/alternate", "Pointer refit preserves the qualified loadout identity")
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await settle()
		var fitted: Button = screen.find_child("Loadout_" + "amber:drone/alternate".validate_node_name(), true, false)
		await reveal(fitted)
		check(fitted.is_visible_in_tree() and fitted.text.contains("Amber Mixed") and fitted.disabled
			and root.get_visible_rect().encloses(fitted.get_global_rect()), "Scoped fitted option is visible at " + str(size))
		await capture("namespace-fit-%d" % size.x)
	var data: Dictionary = state.hangar_snapshot()
	data.research.research_points = 20
	data.research.research_offer = ["amber:applied_energy", "violet:applied_energy"]
	check(state._commit_hangar(data), "Offer same-named projects in the production UI")
	screen._show_research_choices()
	await settle()
	var dialog: Control = screen.research_dialog
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await settle()
		check(text_under(dialog).contains("Amber Energy") and text_under(dialog).contains("Violet Energy")
			and root.get_visible_rect().encloses(dialog.panel.get_global_rect()), "Independent authored cards fit at " + str(size))
		await capture("namespace-research-%d" % size.x)
	await click(dialog.buttons["violet:applied_energy"])
	check(state.current_research_ids.has("violet:applied_energy") and not state.current_research_ids.has("amber:applied_energy")
		and state.research_branch_choices.get("violet:energy") == "optics", "Pointer choice commits only the selected pack's research and family")
	await click(screen.tabs.get_child(0))
	screen.map_selected_id = "refuel_station_1"
	screen._render_map_details()
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await settle()
		var destination: Dictionary = state.expedition_simulation.locations.refuel_station_1
		var distance: float = state.expedition_simulation.state.position_nu.distance_to(Vector2(destination.position[0], destination.position[1]))
		var expected := "ETA %ds at 8x" % ceili(distance / state.expedition_cruise_rate() / ExpeditionState.MAP_SPEED)
		check(text_under(screen.map_details).contains(expected) and screen.map_details.is_visible_in_tree(), "Selected trip ETA matches the fixed Map speed at " + str(size))
		await capture("map-eta-%d" % size.x)
	screen.queue_free()
	await settle()
	check(state.load_run_checkpoint() and state.ship_loadout_id(escort) == "amber:drone/alternate"
		and state.current_research_ids.has("violet:applied_energy"), "Native pointer fit and choice survive Continue")
