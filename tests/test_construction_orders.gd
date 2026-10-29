extends SceneTree

const BUILTINS = preload("res://scripts/builtin_ships.gd")
var state: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for _frame in range(3):
		await process_frame

func click(control: Control, offset := Vector2.ZERO) -> void:
	var point := control.get_global_rect().get_center() if offset == Vector2.ZERO else control.global_position + offset
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
	await settle()

func run() -> void:
	state = root.get_node("GameState")
	_test_atomic_order()
	_test_support_order()
	await _test_window()
	print("Construction order tests finished: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _test_atomic_order() -> void:
	state.run_save_path = "user://construction-orders/run.json"
	check(state.start_new_run(1, 42), "Start isolated batch campaign.")
	var design := BUILTINS.drone()
	var required: Array[int] = state.get_design_material_costs(design)
	state.red_tiles_available = required[0] * 2 + 1
	state.blue_tiles_available = required[1] + 2
	state.green_tiles_available = 0
	state.core_tiles_available = required[3] * 5
	state.credits = 10000
	state.fleet[2].in_reserve = true
	state.fleet[2].formation.x = 1000
	var quote: Dictionary = state.construction_order_quote(design, 5)
	var expected := 0
	for category in range(4):
		expected += maxi(0, required[category] * 5 - state.get_available_tile_count(category)) * state.MATERIAL_PRICES[category]
	check(quote.credits == expected and quote.stock[0] == required[0] * 2 + 1, "Whole-order quote uses finite stock once and credits only for aggregate shortages.")
	var before := RunCheckpoint.capture(state)
	var good: String = state.run_save_path
	var blocker := FileAccess.open("user://construction-orders/blocker", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	state.run_save_path = "user://construction-orders/blocker/run.json"
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	check(not state.purchase_ships(design, "Drone", "regular", 5), "Failed order save rejects every hull.")
	Engine.print_error_messages = printed
	check(RunCheckpoint.capture(state) == before, "Failed batch preserves IDs, stock, credits, roster and fleet.")
	state.run_save_path = good
	var next_id: int = state.next_ship_id
	check(state.purchase_ships(design, "Drone", "regular", 5) and state.fleet.size() == before.fleet.size() + 5
		and state.credits == 10000 - expected and state.next_ship_id == next_id + 5, "One successful batch creates every hull at the aggregate quote.")
	for index in range(5):
		check(state.fleet[before.fleet.size() + index].id == next_id + index, "Batch hull IDs are unique and contiguous.")
	check(state.fleet[before.fleet.size()].formation.x < 10, "Hidden reserves do not push a new order far outside the visible formation.")
	for category in range(4):
		check(state.get_available_tile_count(category) == before.inventory[category] - quote.stock[category], "Stock is consumed exactly once.")
	check(state.load_run_checkpoint() and state.fleet.size() == before.fleet.size() + 5 and state.credits == 10000 - expected,
		"Reload preserves the complete order.")
	state.credits = 0
	before = RunCheckpoint.capture(state)
	check(not state.purchase_ships(design, "Drone", "regular", 20) and not state.purchase_ships(design, "Drone", "regular", 0)
		and RunCheckpoint.capture(state) == before, "Unaffordable and invalid quantities do not partially build ships.")

func _test_support_order() -> void:
	check(state.start_new_run(1, 42), "Start support batch fixture.")
	state.credits = 10000
	var design := Ship.new()
	BUILTINS._add_part(design, ShipPart.Type.COMMAND_CENTER, Vector2i.ZERO)
	BUILTINS._add_part(design, ShipPart.Type.CARGO_HOLD, Vector2i(2, 0))
	check(state.purchase_ships(design, "Tender", "civic", 3), "Dedicated-slot batch construction creates physical support copies.")
	var copies: Array = state.fleet.filter(func(owned: FleetShip) -> bool: return owned.display_name.begins_with("Tender"))
	check(copies.size() == 3 and copies.all(func(owned: FleetShip) -> bool: return owned.slot_role == "regular" and state.is_ship_deployed(owned)), "Cargo copies share a general family without singleton restrictions.")
	check(state.load_run_checkpoint(), "Support batch roster persists.")
	check(state.purchase_ships(design, "Tender", "regular", 2) and state.is_ship_deployed(state.fleet.back()), "Further cargo orders use their existing general family.")

func _test_window() -> void:
	root.gui_embed_subwindows = true
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		check(state.start_new_run(1, 42), "Start construction UI fixture.")
		state.credits = 10000
		for entry in state.story_archive():
			state.story_flags["seen/" + entry.id] = true
		var map: Control = load("res://scenes/game_map.tscn").instantiate()
		root.add_child(map)
		current_scene = map
		await settle()
		var fleet: Control = map.panel_tabs.get_node("Fleet")
		check(not fleet.slot_widgets[0].has("salvage"), "Shop slots have no salvage/minus controls.")
		await click(fleet.slot_widgets[0].construct)
		var modal: Control = fleet.action_review.find_child("ConstructionModal", true, false)
		var quantity: SpinBox = modal.find_child("OrderQuantity", true, false)
		quantity.value = 3
		await settle()
		await click(quantity, Vector2(quantity.size.x - 5, quantity.size.y * 0.25))
		check(quantity.value == 4, "Quantity arrow accepts actual mouse input.")
		await click(quantity.get_line_edit())
		quantity.get_line_edit().select_all()
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.keycode = KEY_5
			event.unicode = 53
			event.pressed = pressed
			root.push_input(event, true)
		await settle()
		check(quantity.value == 5, "Typing a quantity updates the order immediately.")
		quantity.value = 3
		await settle()
		var panel_rect := modal.get_global_rect()
		check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(panel_rect), "Construction window fits %s without scrolling." % resolution)
		check(modal.find_child("ConstructionPreview", true, false).get_global_rect().end.x
			< modal.find_child("OrderBreakdown", true, false).get_global_rect().position.x, "Preview/base/equipment stay left of order costs.")
		var total: HBoxContainer = modal.find_child("OrderBreakdown", true, false).get_children().back()
		check(total.get_children().back().text == str(state.construction_order_quote(fleet.slots[0].design, 3).credits), "Changing quantity updates the displayed total.")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/construction-order"))
			root.get_texture().get_image().save_png("res://.local/construction-order/order-%dx%d.png" % [resolution.x, resolution.y])
		await click(modal.find_child("CloseX", true, false))
		check(not is_instance_valid(fleet.action_review), "The shared X dismisses construction without spending.")
		await click(fleet.slot_widgets[0].construct)
		quantity = fleet.action_review.find_child("OrderQuantity", true, false)
		quantity.value = 3
		await settle()
		var count: int = state.fleet.size()
		await click(fleet.action_review.find_child("ConfirmAction", true, false))
		check(state.fleet.size() == count + 3 and not is_instance_valid(fleet.action_review), "Construct commits the selected quantity and closes the window.")
		fleet.board.selected_ships.assign([state.fleet[0]])
		fleet.board.selection_changed.emit()
		await settle()
		var owned: FleetShip = state.fleet[0]
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/construction-order/actions-%dx%d.png" % [resolution.x, resolution.y])
		await click(fleet.ship_actions.find_child("SalvageAction", true, false))
		check(not state.fleet.has(owned) and state.fleet.size() == count + 2 and not is_instance_valid(fleet.action_review),
			"Salvage immediately removes exactly the selected physical hull without confirmation.")
		map.free()
		current_scene = null
