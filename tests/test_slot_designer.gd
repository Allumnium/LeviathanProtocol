extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(3):
		await process_frame

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.pressed = pressed
		event.button_index = MOUSE_BUTTON_LEFT
		root.push_input(event, true)
	await settle()

func run() -> void:
	root.size = Vector2i(640, 360)
	root.gui_embed_subwindows = true
	var foundation := ResearchRules.resolve(["foundation"])
	var energy := ResearchRules.resolve(["foundation", "applied_energy"])
	check(SlotCatalog.chassis().size() == 5, "Five supplied chassis are available.")
	for chassis in SlotCatalog.chassis():
		var texture: Texture2D = load(chassis.art)
		check(texture.get_size() == Vector2(512, 512), "Use the owner's full-resolution chassis image.")
		var design := SlotShipDesign.new()
		check(design.initialize(chassis.id), "Initialize art/slot design.")
		for slot: Dictionary in chassis.slots:
			for item in SlotCatalog.equipment():
				check(SlotCatalog.compatible(slot, item) == (slot.size == item.size and slot.type == item.type), "Require exact equipment size and category.")
	var design := SlotShipDesign.new()
	design.initialize("drone")
	check(design.equip("fore", "mini_turret", 1, foundation), "Starter tech installs directly, without materials.")
	var before := design.to_data()
	check(not design.equip("fore", "hull_plate", 1, foundation) and design.to_data() == before, "Wrong type cannot alter the design.")
	check(not design.equip("center", "mini_turret", 1, foundation) and design.to_data() == before, "Smaller equipment cannot fill a larger slot.")
	check(not design.equip("fore", "laser", 1, foundation) and design.to_data() == before, "Unresearched equipment cannot be installed.")
	check(design.equip("fore", "laser", 1, energy), "Research enables matching equipment.")
	var restored := SlotShipDesign.new()
	check(restored.load_data(JSON.parse_string(JSON.stringify(design.to_data()))), "Slot IDs and equipment identities round-trip through JSON.")
	check(not restored.authorization_error(foundation).is_empty(), "Imported/reloaded equipment does not bypass research.")
	var invalid := restored.to_data()
	invalid.equipment.fore.rank = 1.5
	before = restored.to_data()
	check(not restored.load_data(invalid) and restored.to_data() == before, "Invalid loads leave the current design intact.")
	check(not Ship.new().load_design_data(design.to_data()) and not HexShipDesign.new().load_data(design.to_data()), "Slot designs cannot be interpreted as square or hex coordinates.")
	var library := SlotDesignLibrary.new()
	library.path = "user://slot_tests/library.json"
	check(library.load_library() and library.save_design("Drone test", design), "Atomic slot library saves named blueprints separately.")
	var stale := SlotDesignLibrary.new()
	stale.path = library.path
	check(stale.load_library(), "Concurrent library can read current generation.")
	check(library.save_design("New revision", design) and not stale.save_design("Stale", design), "Stale writes cannot overwrite another library revision.")
	check(library.get_design("Drone test").to_data() == design.to_data(), "Saved slot loadouts retain exact placement.")
	var state := root.get_node("GameState")
	state.current_research_ids.assign(["foundation"])
	state.research_changed.emit()
	var old_ship: Dictionary = state.ship.to_design_data()
	var credits: int = state.credits
	var menu := load("res://scenes/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await settle()
	await click(menu.ship_designer_button)
	await settle()
	var designer: Control = current_scene
	check(designer.get_script().resource_path == "res://scripts/slot_ship_designer.gd", "Main menu opens the image/slot Designer.")
	designer.library.path = "user://slot_tests/ui.json"
	designer.library.load_library()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		for index in range(designer.chassis_picker.item_count):
			designer._switch_chassis(index)
			await settle()
			var canvas: SlotShipCanvas = designer.canvas
			check(canvas.image_rect.size.y > 200 and Rect2(Vector2.ZERO, canvas.size).encloses(canvas.image_rect), "Whole chassis fits without scrolling.")
			var occupied: Array[Rect2] = []
			for id: String in canvas.slot_buttons:
				var button := canvas.slot_buttons[id]
				check(Rect2(Vector2.ZERO, canvas.size).encloses(button.get_rect()), "Every slot control fits the canvas.")
				check(button.tooltip_text.is_empty() and button.focus_mode == Control.FOCUS_NONE, "Dropdowns have no tooltips or focus boxes.")
				for rect in occupied:
					check(not rect.intersects(button.get_rect()), "Slot dropdowns never overlap at tested sizes.")
				occupied.append(button.get_rect())
				for item_index in range(1, button.item_count):
					var entry: Dictionary = button.get_item_metadata(item_index)
					var item := SlotCatalog.find_equipment(entry.id, entry.rank)
					check(SlotCatalog.compatible(designer.design.slot(id), item), "Popup contains only the mount's exact type and size.")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless" and resolution == Vector2i(1280, 720):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/ui-review/slots-%s.png" % designer.design.chassis_id)
	designer._switch_chassis(4)
	await settle()
	var button: OptionButton = designer.canvas.slot_buttons.fore
	await click(button)
	check(button.get_popup().visible and designer.details.text.contains("Offense / S"), "Clicking the on-ship dropdown opens options and selects its inline details.")
	var chosen := -1
	for index in range(button.item_count):
		if button.get_item_metadata(index).id == "mini_turret":
			chosen = index
	check(chosen >= 0 and not button.is_item_disabled(chosen), "Starter equipment is enabled in the actual dropdown.")
	var started := Time.get_ticks_usec()
	button.get_popup().index_pressed.emit(chosen)
	await settle()
	check(designer.design.equipment.fore.id == "mini_turret" and designer.details.text.contains("Mini Turret"), "Selecting equipment updates the slot and full details.")
	check(Time.get_ticks_usec() - started < 500000, "Dropdown fitting and frame settling avoid multi-second stalls.")
	designer._equip("fore", "laser", 1)
	check(designer.design.equipment.fore.id == "mini_turret", "Direct UI actions also enforce research.")
	state.current_research_ids.append("applied_energy")
	state.research_changed.emit()
	await settle()
	designer._equip("fore", "laser", 1)
	check(designer.design.equipment.fore.id == "laser", "Research changes update choices without restarting Designer.")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/ui-review/slots-equipped-drone.png")
	designer.name_input.text = "UI drone"
	designer.save_design()
	var saved: Dictionary = designer.design.to_data()
	designer._equip("fore", "", 1)
	check(designer.load_design("UI drone") and designer.design.to_data() == saved, "Save/Load restores chosen chassis and equipment.")
	check(state.ship.to_design_data() == old_ship and state.credits == credits, "Designer does not mutate campaign ships or spend credits.")
	check(root.gui_get_focus_owner() == null, "No keyboard focus navigation is introduced.")
	designer.queue_free()
	current_scene = null
	await settle()
	print("Slot Designer: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
