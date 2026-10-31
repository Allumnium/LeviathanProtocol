extends SceneTree

var failures := 0
var checks := 0

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

func click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
	await settle()

func run() -> void:
	root.size = Vector2i(640, 360)
	var scene := load("res://scenes/hex_chassis_prototype.tscn").instantiate() as Control
	root.add_child(scene)
	await settle()
	var board: HexBuildArea = scene.board
	check(board.size.x > 400 and board.size.y > 200, "Prototype canvas has usable space at 640x360.")
	for entry in ChassisCatalog.entries():
		var design := HexShipDesign.new()
		design.initialize(entry.id)
		board.set_design(design)
		await settle()
		for cell in design.chassis().hull:
			check(Rect2(Vector2.ZERO, board.size).has_point(board.cell_position(cell)), "Every chassis fits without scrolling.")
	var design := HexShipDesign.new()
	design.initialize("vanguard")
	board.set_design(design)
	await settle()
	var local := board.cell_position(Vector2i(2, 0))
	var started := Time.get_ticks_usec()
	await click(board.global_position + local)
	check(design.tiles.get(Vector2i(2, 0)) == 0, "Native pointer hit testing paints the chosen hex.")
	check(Time.get_ticks_usec() - started < 500000, "Material placement and frame settling take under 500ms.")
	await click(board.global_position + board.cell_position(Vector2i(-1, 0)))
	check(design.tiles.size() == 1, "Pointer painting cannot fill the structural gap.")
	await click(board.global_position + board.cell_position(Vector2i(-1, 3)))
	check(design.tiles.size() == 1, "Pointer painting cannot overwrite built-in equipment.")
	await click(board.global_position + local, MOUSE_BUTTON_WHEEL_UP)
	check(board.cell_at(local) == Vector2i(2, 0), "Zoom preserves the hex under the pointer.")
	await click(board.global_position + local, MOUSE_BUTTON_RIGHT)
	check(design.tiles.is_empty(), "Right pointer erases material after zooming.")
	check(board.focus_mode == Control.FOCUS_NONE and root.gui_get_focus_owner() == null, "Canvas actions do not create UI focus boxes.")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/ui-review/hex-chassis-prototype.png")
	scene.queue_free()
	await settle()
	print("Hex builder: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
