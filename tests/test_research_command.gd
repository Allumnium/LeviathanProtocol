extends SceneTree

const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")
const TIERS := ["fleet_logistics_i", "fleet_logistics_ii", "fleet_logistics_iii"]
const BONUSES := [8, 24, 108]
const COSTS := [20, 60, 120]
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

func start() -> void:
	check(state.start_new_run(1, 847), "Start command research fixture")
	var data: Dictionary = state.hangar_snapshot()
	data.credits = 100000
	check(state._commit_hangar(data), "Fund isolated ship purchases")
	check(state.command_limit() == 16 and state.current_research_ids == ["foundation"]
		and state.research_branch_choices.is_empty(), "New Run retains base capacity and no free research/branches")

# Explicit offered cards isolate capacity effects from seeded draw distribution.
func fund_research(amount: float, desired := "") -> void:
	var data: Dictionary = state.hangar_snapshot()
	data.research.research_points = amount
	data.research.research_offer = []
	if not desired.is_empty() and HangarResearch.eligible(desired, data.research):
		var pool := HangarResearch.available(data.research)
		data.research.research_offer = [desired]
		for id: String in pool:
			if id != desired and data.research.research_offer.size() < 3:
				data.research.research_offer.append(id)
	check(state._commit_hangar(data), "Persist earned RP and valid offered-card fixture")

func registry_checks() -> void:
	var registry := GameDefinitions.snapshot()
	check(ResearchRules.validate_registry(registry).is_empty(), "Command research registry validates")
	for index in range(TIERS.size()):
		var node := ResearchViewModel.find(registry, "research", TIERS[index])
		check(node.cost_rp == COSTS[index] and node.family_id.is_empty()
			and node.prerequisite_ids == (["foundation"] if index == 0 else [TIERS[index - 1]])
			and node.story_gate_ids.is_empty(), "Logistics tier has shared sequential progression")
		for value: Variant in [0, -1, 0.5, NAN, INF, "8", null, true, 257]:
			var invalid := registry.duplicate(true)
			ResearchViewModel.find(invalid, "research", TIERS[index]).grants.modifiers[0].value = value
			check(not ResearchRules.validate_registry(invalid).is_empty(), "Reject malformed command bonus: " + str(value))
	for flagship: Dictionary in SlotCatalog.flagships():
		var ids: Array = ["foundation"]
		check(HangarResearch.command_limit(int(flagship.command), ids) == int(flagship.command), "Unresearched flagship keeps base")
		for index in range(TIERS.size()):
			ids.append(TIERS[index])
			check(HangarResearch.command_limit(int(flagship.command), ids) == int(flagship.command) + BONUSES[index],
				"Highest earned tier replaces earlier command bonuses")
	check(HangarResearch.command_limit(0, ["foundation"] + TIERS) == 0, "Research cannot supply a missing flagship")

func progression_and_capacity() -> void:
	start()
	check(not state.choose_research(TIERS[1]) and not state.choose_research(TIERS[2]), "Cannot skip logistics tiers")
	fund_research(19.5)
	check(not state.choose_research(TIERS[0]) and state.research_points == 19.5
		and state.command_limit() == 16, "Partial research gives no command capacity")
	var before: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot()), "Continue preserves partial research")
	fund_research(20, TIERS[0])
	var path: String = state.run_save_path
	before = state.hangar_snapshot()
	state.research_completion_notices.clear()
	state.run_save_path = "res://project.godot/no-command-research.json"
	check(not state.choose_research(TIERS[0]) and state.command_limit() == 16
		and state.research_completion_notices.is_empty() and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed completion leaves RP, capacity, research and notices unchanged")
	state.run_save_path = path
	check(state.choose_research(TIERS[0]) and state.command_limit() == 24
		and state.research_branch_choices.is_empty() and state.research_completion_notices == [TIERS[0]],
		"Completion grants capacity once without committing a combat branch")
	var group: Dictionary = HangarSquadrons.for_ship(state.squadrons, 3)
	var count: int = (state.command_limit() - state.used_command()) / 2
	check(state.buy_ships("fighter", count, int(group.id)), "Group purchase can use researched capacity beyond the base")
	while state.used_command() < state.command_limit():
		if not state.buy_ship("drone"):
			check(false, "Fill final command point")
			break
	check(state.used_command() == 24 and state.deployment_error().is_empty(), "Fleet can deploy exactly at researched capacity")
	before = state.hangar_snapshot()
	check(not state.buy_ship("drone") and state.last_save_error.contains("command")
		and SaveValidation.same(before, state.hangar_snapshot()), "Single purchase over capacity is atomic")
	check(not state.buy_ships("fighter", 2, int(group.id)) and SaveValidation.same(before, state.hangar_snapshot()),
		"Group purchase over capacity is atomic")
	var invalid := before.duplicate(true)
	invalid.research.research_ids = ["foundation"]
	check(not HangarCheckpoint.valid(invalid), "Checkpoint rejects expanded fleet without earned capacity")
	check(state.load_run_checkpoint() and SaveValidation.same(before, state.hangar_snapshot())
		and state.command_limit() == 24, "Continue accepts expanded fleet and derives capacity")
	var rescue := before.duplicate(true)
	var compensation := ShipLoadouts.ship_price("transport", ShipLoadouts.default_for("transport"))
	check(state._rescue_ship(rescue, "transport").contains("command full")
		and rescue.ships.size() == before.ships.size() and rescue.credits == before.credits + compensation,
		"Full researched fleet receives disclosed rescue compensation")
	for index in [1, 2]:
		fund_research(HangarResearch.threshold(state.run_progress_snapshot()), TIERS[index])
		check(state.choose_research(TIERS[index]) and state.command_limit() == 16 + BONUSES[index], "Earn next logistics tier")
		check(state.load_run_checkpoint() and state.command_limit() == 16 + BONUSES[index], "Continue retains higher tier capacity")
		if index == 1:
			rescue = state.hangar_snapshot()
			check(state._rescue_ship(rescue, "transport").contains("joined") and HangarCheckpoint.valid(rescue)
				and state._commit_hangar(rescue), "Rescue uses newly earned room and saves the fully fitted ship")
	before = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/no-command-purchase.json"
	check(not state.buy_ships("fighter", 2, int(group.id)) and SaveValidation.same(before, state.hangar_snapshot()),
		"Failed expanded-fleet purchase rolls back money, ownership, equipment and squadrons")
	state.run_save_path = path
	# Logistics stays independent of the active mutually exclusive combat families.
	for pair: Array in [["applied_energy", "optics_ii", "disruption_i"], ["field_engineering", "renewal_i", "bastion_ii"],
		["guided_munitions", "siege_i", "carrier_i"]]:
		var data: Dictionary = state.hangar_snapshot()
		data.research.research_ids.append(pair[0])
		check(state._commit_hangar(data), "Earn combat branch prerequisite beside logistics")
		if pair[0] == "applied_energy":
			check(state.swap_part(1, "fore", "laser"), "Fit laser capability for energy choice")
		elif pair[0] == "guided_munitions":
			check(state.swap_part(1, "spine", "missile_rack"), "Fit missile capability for siege choice")
		fund_research(HangarResearch.threshold(state.run_progress_snapshot()), pair[1])
		check(state.choose_research(pair[1]) and not state.choose_research(pair[2])
			and state.command_limit() == 124, "Exclusive combat branch remains exclusive beside shared fleet growth")

func settle() -> void:
	for index in range(5):
		await process_frame

func click(button: Button) -> void:
	check(button.is_visible_in_tree() and not button.disabled, "Native target is visible and enabled")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func text_under(node: Node) -> String:
	var text: String = node.source_text if node is ResourceText else (node.text if node is Label else "")
	for child in node.get_children():
		text += "\n" + text_under(child)
	return text

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("user://" + filename) == OK, "Save native command research capture")

func native_ui() -> void:
	start()
	fund_research(20, TIERS[0])
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await settle()
	screen.set_process(false)
	screen._maybe_show_research_choices()
	await settle()
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var dialog: Control = screen.research_dialog
		check(dialog.buttons.has(TIERS[0]) and root.get_visible_rect().encloses(dialog.panel.get_global_rect()),
			"Logistics card is available in native offer at " + str(resolution))
		await capture("command-research-%d.png" % resolution.x)
	await click(screen.research_dialog.buttons[TIERS[0]])
	check(state.current_research_ids.has(TIERS[0]) and state.command_limit() == 24, "Native Choose grants logistics capacity")
	screen.active_tab = "FLEET"
	screen._refresh()
	await settle()
	check(text_under(screen.roster).contains("Command %d / 24" % state.used_command()), "Fleet displays earned command capacity")
	await capture("command-fleet.png")
	screen.queue_free()
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	state.run_save_path = "user://research-command.json"
	if DisplayServer.get_name() == "headless":
		registry_checks()
		progression_and_capacity()
	else:
		await native_ui()
	print("RESEARCH COMMAND: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
