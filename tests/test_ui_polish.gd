extends SceneTree

var failures := 0
var checks := 0
var state: Node
var screen: Control
var mouse := Vector2.ZERO

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func settle() -> void:
	for i in range(4):
		await process_frame

func button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func motion(position: Vector2, pressed := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - mouse
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse = position
	root.push_input(event, true)

func drag(start: Vector2, finish: Vector2) -> void:
	motion(start)
	button(start, true)
	await process_frame
	motion(finish, true)
	await process_frame
	button(finish, false)
	await settle()

func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/ui-polish/" + name + ".png")

func star_layout(field: Control) -> Array:
	var result: Array = []
	for star in field._area_stars:
		result.append([star.world_offset, star.depth, star.radius, star.color, star.phase,
			star.speed, star.animation_frame_offset, star.animation_speed, star.is_sparkle])
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/ui-polish"))
	root.size = Vector2i(1280, 720)
	var ui_theme: Theme = load("res://themes/ui_theme.tres")
	var button_style := ui_theme.get_stylebox("normal", "Button") as StyleBoxFlat
	var hover_style := ui_theme.get_stylebox("hover", "TacticalButton") as StyleBoxFlat
	var pressed_style := ui_theme.get_stylebox("pressed", "TacticalButton") as StyleBoxFlat
	check(button_style != null and button_style.bg_color.a == 1.0
		and button_style.border_color != hover_style.border_color
		and hover_style.border_width_left > button_style.border_width_left
		and pressed_style.content_margin_top > button_style.content_margin_top,
		"Tactical buttons have distinct hover and pressed feedback")
	var panel_style := ui_theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	check(panel_style != null and panel_style.corner_radius_top_left <= 6
		and panel_style.border_width_left == 1,
		"Panel containers use a subtle, low-chamfer shared frame")
	check(ui_theme.get_stylebox("normal", "LineEdit") != null
		and ui_theme.get_stylebox("normal", "TextEdit") != null,
		"Single-line and multiline text boxes use shared themed surfaces")
	var save_dialog: PopupPanel = load("res://scenes/save_design_dialog.tscn").instantiate()
	check(save_dialog.theme == ui_theme
		and save_dialog.get_node("Contents/ShipNameInput") is LineEdit,
		"Ship-name editor field inherits the shared UI theme")
	save_dialog.free()
	state = root.get_node("GameState")
	state.run_save_path = "user://ui-polish.json"
	check(state.start_new_run(1, 151), "Start isolated UI fixture")
	var data: Dictionary = state.hangar_snapshot()
	data.credits = 5000
	check(state._commit_hangar(data) and state.buy_chassis("transport"), "Buy escort")
	screen = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await settle()
	check(screen.active_tab == "FLEET", "Fleet opens first")
	var credits_icon: TextureRect = screen.find_child("CreditsIcon", true, false)
	var science_icon: TextureRect = screen.find_child("ScienceIcon", true, false)
	check(credits_icon != null and credits_icon.texture.resource_path == "res://assets/credits.png"
		and science_icon != null and screen.header.text == str(state.credits)
		and screen.research_rate.text.ends_with(" RP/day"),
		"Header uses the credits icon and current science production")
	check(absf(science_icon.global_position.y + science_icon.size.y / 2.0
		- screen.research_rate.global_position.y - screen.research_rate.size.y / 2.0) <= 1.0,
		"Science icon and production value align vertically")
	var board: Control = screen.formation_view
	board.camera = Vector2(20, -15)
	board.zoom = 1.2
	board.queue_redraw()
	await settle()
	var first: Vector2 = board.point(state.fleet[0])
	var second: Vector2 = board.point(state.fleet[1])
	var origin := board.global_position
	await drag(origin + first - Vector2(40, 50), origin + second + Vector2(40, 50))
	board = screen.formation_view
	check(board.selected_ids.size() == 2 and screen.selected_ship_id == 0, "Native box select selects both ships")
	check(board.camera == Vector2(20, -15) and is_equal_approx(board.zoom, 1.2), "Selection preserves camera")
	await capture("group-selected")
	var before_a: Vector2 = state.fleet[0].formation
	var before_b: Vector2 = state.fleet[1].formation
	var background_position: Vector2 = board.starfield._get_star_position(board.starfield._stars[0])
	var start: Vector2 = board.global_position + board.point(state.fleet[0])
	check(board._hit(board.point(state.fleet[0])) == state.fleet[0].id, "Ship center is a native hit target")
	await drag(start, start + Vector2(40, 20))
	board = screen.formation_view
	check(not state.fleet[0].formation.is_equal_approx(before_a), "Native group drag moves ships")
	check((state.fleet[1].formation - state.fleet[0].formation).is_equal_approx(before_b - before_a), "Group drag preserves spacing")
	check(board.selected_ids.size() == 2 and board.camera == Vector2(20, -15) and is_equal_approx(board.zoom, 1.2), "Move retains selection, pan and zoom")
	check(board.starfield._get_star_position(board.starfield._stars[0]).is_equal_approx(background_position), "Moving ships does not reshuffle stationary stars")
	var saved: Dictionary = state.hangar_snapshot()
	check(state.load_run_checkpoint(), "Load moved formation")
	check(state.hangar_snapshot().ships == saved.ships, "Group positions persist")
	saved = state.hangar_snapshot()
	var blocker := FileAccess.open("user://blocked-save", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	var save_path: String = state.run_save_path
	state.run_save_path = "user://blocked-save/run.json"
	check(not state.move_ships({1: Vector2.ZERO}), "Group move reports failed save")
	check(state.hangar_snapshot() == saved, "Failed group save preserves whole fleet")
	state.run_save_path = save_path
	check(not state.move_ships({1: Vector2(6, 0)}) and state.hangar_snapshot() == saved, "Out-of-bounds group move is rejected atomically")
	await settle()
	board = screen.formation_view
	var empty: Vector2 = board.global_position + Vector2(20, 20)
	await drag(empty, empty)
	check(screen.selected_ship_id == 0 and screen.formation_view.selected_ids.is_empty(), "Empty-space click deselects")
	check(screen.details.get_child(1).text.begins_with("REPAIR ALL"), "Empty selection offers repair all")
	state.fleet[0].hull_hp -= 10
	state.fleet[1].hull_hp -= 15
	check(state.save_run_checkpoint(), "Damage fixture")
	screen._refresh()
	await settle()
	var credits: int = state.credits
	check(state.fleet_repair_cost() == 25, "Repair-all quote sums hull damage")
	state.run_save_path = "user://blocked-save/run.json"
	var damaged: Dictionary = state.hangar_snapshot()
	check(not state.repair_all_ships() and state.hangar_snapshot() == damaged, "Failed repair-all save restores credits and every ship")
	state.run_save_path = save_path
	state.credits = 0
	check(not state.repair_all_ships() and state.fleet_repair_cost() == 25, "Unaffordable repair all cannot partially repair")
	state.credits = credits
	screen.details.get_child(1).pressed.emit()
	await settle()
	check(state.credits == credits - 25 and state.fleet_repair_cost() == 0, "Repair all repairs fleet and charges once")
	check(screen.details.get_child(1).disabled, "Full fleet disables repair all")
	var escort_id: int = state.fleet[1].id
	screen._confirm_salvage(escort_id)
	await settle()
	check(state.owned_ship(escort_id) != null and screen.shop != null, "Salvage waits for confirmation")
	await capture("salvage-confirm")
	screen.shop.find_child("CloseX", true, false).pressed.emit()
	await settle()
	check(state.owned_ship(escort_id) != null, "X cancels salvage")
	screen._confirm_salvage(escort_id)
	await settle()
	for candidate in screen.shop.find_children("*", "Button", true, false):
		if candidate.text == "SALVAGE":
			candidate.pressed.emit()
			break
	await settle()
	check(state.owned_ship(escort_id) == null and screen.shop == null, "Confirm salvages escort")
	screen._confirm_salvage(1)
	check(screen.shop == null, "Flagship cannot be salvaged")
	var item := SlotCatalog.find_equipment("mini_turret")
	var texture := SlotCatalog.equipment_texture(item)
	var bounds := Rect2(10, 20, 80, 80)
	var fitted := SlotCatalog.fitted_art_rect(texture, bounds, item.art_mount)
	check((fitted.position + Vector2(62, 65) * fitted.size.x / 124).is_equal_approx(bounds.get_center()), "Turret circular base aligns to mount center")
	check(is_equal_approx(fitted.size.x / 124 * 82, bounds.size.x), "Turret base diameter matches mount")
	board = screen.formation_view
	var starfield: Control = board.starfield
	var star = starfield._stars[0]
	var star_position: Vector2 = starfield._get_star_position(star)
	starfield._process(0.1)
	check(starfield._get_star_position(star).is_equal_approx(star_position), "Space stars stay stationary")
	var click := InputEventMouseButton.new()
	click.position = star_position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	starfield._gui_input(click)
	check(star.click_flash_remaining > 0, "Stars respond to clicks")
	var layout := star_layout(starfield)
	check(layout.size() == 220, "Area has a stable pool independent of visible star count")
	for action in range(3):
		screen._refresh()
		await settle()
		check(star_layout(screen.formation_view.starfield) == layout, "UI refresh preserves every generated star")
	screen.active_tab = "SHIPS"
	screen.selected_ship_id = 1
	screen._refresh()
	await settle()
	check(star_layout(screen.canvas.starfield) == layout, "Ships uses the same area layout")
	root.size = Vector2i(640, 360)
	await settle()
	check(star_layout(screen.canvas.starfield) == layout, "Resize preserves the area pool")
	root.size = Vector2i(1280, 720)
	await settle()
	check(star_layout(screen.canvas.starfield) == layout, "Resize back restores the same stars")
	screen.canvas.starfield.set_area(state.run_seed, state.current_node_id + 1)
	check(star_layout(screen.canvas.starfield) != layout, "Another map node has its own layout")
	screen.canvas.starfield.set_area(state.run_seed, state.current_node_id)
	check(star_layout(screen.canvas.starfield) == layout, "Returning to a node recreates its original layout")
	check(state.load_run_checkpoint(), "Reload node checkpoint")
	screen.queue_free()
	await settle()
	screen = load("res://scenes/game_map.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await settle()
	check(star_layout(screen.formation_view.starfield) == layout, "Reopening screen after Continue recreates the area")
	screen.active_tab = "MAP"
	screen._refresh()
	await settle()
	var graph: Control = screen.graph
	check(star_layout(graph.starfield) == layout, "Map uses the same node seed")
	check(not screen.get_theme_color("background_color", "SlotCanvas").r > 0.03, "Space background stays dark")
	var target: int = state.get_reachable_nodes(state.current_node_id)[0]
	graph.start_travel(target)
	check(graph._travel_duration >= 2 and graph._travel_duration <= 3, "Distance-scaled travel takes 2-3 seconds")
	graph.set_process(false)
	graph._process(graph._travel_duration * 0.25)
	check(graph._ship_world_position.is_equal_approx(graph._travel_start.lerp(graph._travel_end, 0.25)), "Travel flies linearly at a steady speed")
	graph._traveling = false
	graph.set_process(true)
	screen._begin_travel(target)
	check(screen.traveling and graph._traveling, "Actual Travel starts flight before changing scene")
	var generation: int = state.hangar_generation
	screen._begin_travel(target)
	check(state.hangar_generation == generation, "Double travel cannot settle twice")
	await create_timer(0.6).timeout
	check(is_instance_valid(graph) and graph._travel_elapsed > 0 and graph._traveling, "Flight remains visible en route")
	await capture("map-flight")
	await create_timer(3.0).timeout
	check(current_scene != screen or not screen.traveling, "Flight finishes and resumes destination")
	print("UI POLISH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
