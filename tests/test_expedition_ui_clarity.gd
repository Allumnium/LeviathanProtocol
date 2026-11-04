extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func settle() -> void:
	for index in range(4):
		await process_frame

func run() -> void:
	var fixture := {"ships": [{"hull_hp": 0, "mounts": {"hold": "cargo", "cabin": "people"}}],
		"equipment": {
			"cargo": {"equipment_id": "cargo_hold", "load": {"kind": "cargo", "quantity": 3}},
			"people": {"equipment_id": "passenger_cabin", "load": {"kind": "passengers", "quantity": 2}},
			"loose": {"equipment_id": "cargo_hold", "load": {"kind": "cargo", "quantity": 10}}}}
	check(HangarTrade.summary(fixture) == {"cargo": 3, "cargo_capacity": 10,
		"passengers": 2, "passenger_capacity": 4},
		"Trade totals count actual partial loads on installed equipment, including living zero-hull ships")
	fixture.ships[0].hull_hp = -1
	check(HangarTrade.summary(fixture) == {"cargo": 0, "cargo_capacity": 0,
		"passengers": 0, "passenger_capacity": 0}, "Destroyed ships contribute neither loads nor capacity")
	fixture.ships[0].hull_hp = 1
	fixture.equipment.cargo.load = {}
	fixture.equipment.people.load = {}
	check(HangarTrade.summary(fixture).cargo == 0 and HangarTrade.summary(fixture).passengers == 0
		and HangarTrade.summary(fixture).cargo_capacity == 10,
		"Empty and delivered loads keep capacity without inventing cargo")
	var state := root.get_node("GameState")
	state.run_save_path = "user://expedition-ui-clarity.json"
	check(state.start_new_run(1, 921), "Start isolated clarity fixture")
	state.pending_intro = false
	for event: Dictionary in state.expedition_simulation.events:
		state.expedition_simulation.state.event_receipts[event.id] = true
	var screen: Control = load("res://scenes/game_map.tscn").instantiate()
	root.size = Vector2i(1280, 720)
	root.add_child(screen)
	current_scene = screen
	screen.set_process(false)
	await settle()
	var map: Control = screen.graph
	var simulation = state.expedition_simulation
	check(map.services_for(simulation.locations.start_station) == ["shipyard", "refuel", "trade"]
		and map.services_for(simulation.locations.settlement_1) == ["refuel", "trade"]
		and map.services_for(simulation.locations.derelict_1).is_empty(),
		"Station symbols show only their declared services; POIs gain no invented services")
	check(map.services_for({"kind": "station", "services": ["trade", "shipyard"]}) == ["shipyard", "trade"],
		"Service symbols use consistent order independent of catalog order")
	check(map.service_key.get_child_count() == 3
		and map.service_key.get_child(0).get_child(1).text == "Shipyard"
		and map.service_key.get_child(1).get_child(1).text == "Refuel"
		and map.service_key.get_child(2).get_child(1).text == "Trade",
		"Map symbols retain a visible named key rather than depending on tooltips")
	var map_snapshot: Dictionary = state.hangar_snapshot()
	map.user_moved = true
	var map_position: Vector2 = map.camera_position
	var map_zoom: float = map.camera_zoom
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		map._process(0)
		await settle()
		check(map.get_global_rect().grow(1).encloses(map.service_key.get_global_rect()),
			"Named map service key fits its canvas at %s" % resolution)
		var station: Dictionary = simulation.locations.start_station
		var marker := Rect2(map.to_screen(Vector2(station.position[0], station.position[1]))
			- Vector2.ONE * 9, Vector2.ONE * 18)
		var badges: Array[Rect2] = map.service_rects(station)
		check(badges.size() == 3 and not badges[0].intersects(marker)
			and not badges[0].intersects(badges[1]) and not badges[1].intersects(badges[2]),
			"Service symbols do not cover station artwork or one another at %s" % resolution)
		check(map.camera_position == map_position and map.camera_zoom == map_zoom
			and state.hangar_snapshot() == map_snapshot,
			"Service presentation preserves manual map view and gameplay state")
		check(map.location_label_rects.size() == simulation.state.discovered_location_ids.size(),
			"Service badges do not displace any initially discovered destination name at %s" % resolution)
		for label_rect: Rect2 in map.location_label_rects.values():
			check(not label_rect.intersects(map.service_key.get_rect())
				and not badges.any(func(rect: Rect2) -> bool: return rect.intersects(label_rect)),
				"Destination names remain separate from service symbols and key")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/checks/map-services-%d.png" % resolution.x)
	root.size = Vector2i(1280, 720)
	await settle()
	await create_timer(0.22).timeout
	check(root.get_node("AudioManager").UI_SFX[&"panel_open"].resource_path.ends_with("/panel-open.mp3"),
		"Panel entrances use the supplied sound on the existing effects bus")
	var panels: Array[Control] = [screen.command_header, screen.roster_panel, screen.details_panel,
		screen.find_child("CommandFooter", true, false)]
	for index in range(panels.size()):
		var panel: Control = panels[index]
		var slide: Container = panel.get_parent()
		check(slide.edge == [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN][index],
			"Each management frame enters from its nearest screen edge")
		check(slide.relevant and is_zero_approx(slide.progress) and panel.visible,
			"Meaningful controls and information keep their panel available after entrance")
	var slide: Container = screen.details_panel.get_parent()
	var content: VBoxContainer = screen.details
	var saved_children: Array[Node] = content.get_children()
	var original_center: Rect2 = screen.center.get_rect()
	var snapshot: Dictionary = state.hangar_snapshot()
	for child in saved_children:
		content.remove_child(child)
	slide._process(0)
	check(not slide.relevant and screen.details_panel.visible and slide.motion.is_running(),
		"An empty panel slides out instead of disappearing immediately")
	slide.motion.custom_step(0.09)
	await process_frame
	check(slide.progress > 0 and slide.progress < 1 and screen.details_panel.position.x > 0,
		"Exit translates the entire right panel toward the right edge")
	await create_timer(0.22).timeout
	check(not screen.details_panel.visible and is_equal_approx(slide.progress, 1),
		"Empty panel finishes fully offscreen and cannot intercept input")
	check(screen.center.get_rect() == original_center and state.hangar_snapshot() == snapshot,
		"Panel motion preserves canvas layout and saved gameplay state")
	for child in saved_children:
		content.add_child(child)
	slide._process(0)
	var entrance: Tween = slide.motion
	check(slide.relevant and screen.details_panel.visible,
		"Restoring meaningful information starts a fresh entrance")
	slide._process(0)
	check(slide.motion == entrance, "Routine updates do not replay entrance motion or sound")
	for child in saved_children:
		content.remove_child(child)
	slide._process(0)
	for child in saved_children:
		content.add_child(child)
	slide._process(0)
	await create_timer(0.22).timeout
	check(screen.details_panel.visible and is_zero_approx(slide.progress),
		"Rapid relevance changes reverse smoothly and leave the panel in its correct position")
	check(screen.voyage_summary.text == "Cargo\n0 / 10\nPassengers\n0 / 0",
		"Map summary shows carried quantities and installed capacities, not voyage counters or duplicate fuel")
	check(screen.map_details.get_child_count() == 1, "New-run map has one short introductory hint")
	state.tutorials_enabled = false
	screen._render_map_details()
	check(screen.map_details.get_child_count() == 0, "Disabled tutorials remove introductory map text")
	state.tutorials_enabled = true
	check(screen._set_course("refuel_station_1"), "Set course and board cargo atomically")
	check(state.last_event_result == "10 cargo loaded" and screen.voyage_summary.text.begins_with("Cargo\n10 / 10"),
		"Boarding feedback counts goods, and map summary updates immediately")
	check(screen.map_details.get_child_count() == 0, "Successful course removes introductory instructions")
	var before: Dictionary = state.hangar_snapshot()
	state.run_save_path = "res://project.godot/no-save.json"
	check(not screen._set_course("settlement_1"), "Failed course save is rejected")
	check(state.equipment_inventory == before.equipment
		and screen.voyage_summary.text.begins_with("Cargo\n10 / 10"),
		"Failed save leaves displayed loads and ownership unchanged")
	state.run_save_path = "user://expedition-ui-clarity.json"
	screen._on_expedition_retry_pressed()
	check(state.load_run_checkpoint(), "Continue restores loaded expedition")
	screen._refresh()
	await settle()
	check(screen.voyage_summary.text.begins_with("Cargo\n10 / 10"), "Continue restores actual carried quantity")
	check(state.expedition_simulation.set_speed(10), "Speed up delivery fixture")
	var income_before: int = state.credits
	screen._advance_expedition(100)
	check(state.credits > income_before, "Arrival delivers physical cargo")
	check(screen.delivery_readout.visible and screen.delivery_readout.source_text == "+%d cr" % (state.credits - income_before)
		and screen.instrument_seconds.transport > 0,
		"Committed delivery shows exact income beside the wallet and cues the transport source")
	var duplicate_delivery := false
	var toasts := screen.get_node_or_null("Toasts")
	if toasts != null:
		for toast: Node in toasts.get_children():
			for line: Node in toast.get_children():
				if line is Label and line.text.contains("Delivery paid"):
					duplicate_delivery = true
	check(not duplicate_delivery, "Delivery does not repeat its wallet feedback as a prose toast")
	screen._refresh_expedition_controls()
	check(screen.voyage_summary.text.begins_with("Cargo\n0 / 10"), "Delivery clears carried quantity but retains capacity")
	var feedback_camera: Vector2 = screen.graph.camera_position
	var feedback_zoom: float = screen.graph.camera_zoom
	var feedback_state: Dictionary = state.hangar_snapshot()
	screen._update_instrument_feedback(0.2)
	check(screen.voyage_summary.self_modulate != Color.WHITE,
		"Delivery cue is visible on the transport readout without relying on audio")
	screen._refresh()
	await settle()
	check(screen.delivery_readout.visible and screen.delivery_income == state.credits - income_before,
		"Routine refresh preserves the earned-income cue without replaying delivery")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		screen._update_instrument_feedback(0)
		check(screen.get_global_rect().grow(1).encloses(screen.delivery_readout.get_global_rect())
			and screen.delivery_readout.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and screen.delivery_readout.size.x >= screen.delivery_readout.get_theme_font("normal_font").get_string_size(
				"+%d " % screen.delivery_income, HORIZONTAL_ALIGNMENT_LEFT, -1,
				screen.delivery_readout.get_theme_font_size("normal_font_size")).x
				+ screen.delivery_readout.get_theme_font_size("normal_font_size"),
			"Wallet income stays inside the viewport and cannot intercept input at %s" % resolution)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/checks/instrument-feedback/income-%d.png" % resolution.x)
	check(screen.graph.camera_position == feedback_camera and screen.graph.camera_zoom == feedback_zoom
		and state.hangar_snapshot() == feedback_state,
		"Income and instrument cues preserve map view and saved gameplay state")
	screen._update_instrument_feedback(2)
	check(not screen.delivery_readout.visible and screen.voyage_summary.self_modulate == Color.WHITE
		and screen.delivery_income == 0, "Delivery feedback expires and restores the unmodified instrument")
	root.size = Vector2i(1280, 720)
	screen.active_tab = "FLEET"
	screen._refresh()
	await settle()
	var board: Control = screen.formation_view
	board.set_process(false)
	check(board.station.visible and board.station.texture is CanvasTexture
		and SurfaceArt.diffuse(board.station.texture).resource_path == board.STATION_ART,
		"Docked Fleet uses the supplied mapped large station")
	var start_angle: float = board.station_angle
	board._process(15.0)
	check(is_equal_approx(fposmod(board.station_angle - start_angle, TAU), PI),
		"Station rotates half a revolution in fifteen real-time seconds")
	check(board.surface_material.get_shader_parameter("station_light").w > 0
		and board.station.material.get_shader_parameter("emission_energy") > 0,
		"Station emits light onto Fleet surfaces and retains self emission")
	var original_position: Vector2 = board.station.position
	board.camera += Vector2(30, 20)
	board.zoom = 1.5
	board._update_station()
	check(board.station.position != original_position and is_equal_approx(board.station.scale.x,
		220.0 * 1.5 / board.station.texture.get_width()), "Station follows Fleet pan and zoom")
	var angle_before_move: float = board.station_angle
	var moved_ship: HangarShip = state.fleet[0]
	check(state.move_ships({moved_ship.id: moved_ship.formation + Vector2(0.1, 0)}),
		"Commit Fleet drag-release move")
	await settle()
	board = screen.formation_view
	board.set_process(false)
	check(absf(angle_difference(angle_before_move, board.station_angle)) < 0.1
		and is_equal_approx(board.station.rotation, board.station_angle),
		"Fleet rebuild after drag release preserves station rotation instead of resetting it")
	var refresh_angle: float = board.station_angle
	screen._refresh()
	board = screen.formation_view
	board.set_process(false)
	check(is_equal_approx(board.station_angle, refresh_angle),
		"Selection and other immediate UI refreshes preserve the exact station angle")
	if DisplayServer.get_name() != "headless":
		board.camera = Vector2.ZERO
		board.zoom = 1.0
		board._update_station()
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/checks/docked-station.png")
	check(state.depart_expedition("settlement_1"), "Depart station fixture")
	board._update_station()
	check(not board.station.visible and board.surface_material.get_shader_parameter("station_light") == Vector4.ZERO,
		"Departure removes station scenery and light immediately")
	screen.active_tab = "RESEARCH"
	screen._refresh()
	await settle()
	var production := ""
	for child: Node in screen.roster.get_children():
		if child is ResourceText:
			production += child.source_text + "\n"
	check(production.contains("Travel only") and not production.contains("RP stored")
		and not production.contains("on arrival") and not production.contains("Choose a destination")
		and not production.contains("PRODUCTION"),
		"Research explains distance-only accrual without duplicating the header bank or legacy arrival previews")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		screen.active_tab = "MAP"
		screen._refresh()
		await settle()
		check(screen.roster_panel.get_global_rect().encloses(screen.voyage_summary.get_global_rect()),
			"Carried totals fit the side panel at %s" % resolution)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/checks/clarity-map-%d.png" % resolution.x)
		for event_id: String in ["free_trader", "asteroid_corridor", "nebula_study"]:
			var event: Dictionary = state.expedition_simulation.Events.find(state.expedition_simulation.events, event_id)
			screen._show_encounter(event)
			await settle()
			var panel: Control = screen.encounter_modal.find_child("EncounterPanel", true, false)
			check(screen.get_global_rect().encloses(panel.get_global_rect()),
				"Known event costs fit the encounter at %s: %s" % [resolution, event_id])
			for choice: Button in panel.find_child("DialogActions", true, false).get_children():
				check(panel.get_global_rect().encloses(choice.get_global_rect()),
					"Cost-bearing action stays inside the encounter panel")
			if resolution.x == 640 and event_id == "nebula_study" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.local/checks/clarity-nebula-640.png")
			screen._dismiss_intro()
			await settle()
	var audio := root.get_node("AudioManager")
	var encounter: Dictionary = state.pending_encounter.duplicate(true)
	for boss: bool in [false, true]:
		state.pending_encounter = {"template_id": "bastion_warden" if boss else "patrol"}
		screen.entering_battle = false
		screen._sync_music()
		screen._enter_battle()
		var player: AudioStreamPlayer = audio._music_player
		check(audio._current_music_track == (&"boss" if boss else &"battle") and player.playing,
			"Battle music starts synchronously with entry, before the shutters finish")
		screen._sync_music()
		screen._enter_battle()
		audio.play_battle_music(boss)
		check(audio._music_player == player,
			"Transition updates, duplicate entry and battle initialization do not restart music")
		for child in root.get_children():
			if child.get_script() == screen.SceneFadeScript:
				child.queue_free()
		await settle()
	state.pending_encounter = encounter
	var banked: Dictionary = state.hangar_snapshot()
	banked.research.research_focus = ""
	banked.research.research_points = 7.5
	check(state._commit_hangar(banked), "Save banked RP UI fixture")
	screen.entering_battle = false
	screen._refresh()
	await settle()
	check(screen.research_status.text == "7 RP" and not screen.research_progress.visible,
		"No-focus Research button shows only spendable whole RP without a project bar")
	var graph_before: Control = screen.graph
	state.research_points = 8.5
	screen._update_expedition_readouts()
	check(screen.research_status.text == "8 RP" and screen.graph == graph_before,
		"Travel refreshes the RP balance in place without rebuilding the map")
	screen.active_tab = "RESEARCH"
	screen._refresh()
	await settle()
	var research: Control = screen.research_panel
	research.state_override = {"research_ids": ["foundation"], "story_flags": {},
		"branch_choices": {}, "research_focus": "applied_energy",
		"research_progress": {"applied_energy": 2}}
	research.refresh()
	research._select("applied_energy")
	check(not research.focus_button.visible and research.card_buttons.applied_energy.has_node("Focus"),
		"Focused research uses a distinct shape on its tree node instead of a redundant disabled FOCUSED button")
	research.show_failure()
	check(research.feedback.visible and research.feedback.text == "Save failed. Retry.",
		"Visual focus presentation retains explicit save failures")
	var research_snapshot: Dictionary = state.hangar_snapshot()
	var camera_before: Vector2 = research.tree_canvas.camera_position
	var zoom_before: float = research.tree_canvas.camera_zoom
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var cue: Line2D = research.card_buttons.applied_energy.get_node("Focus")
		check(cue.points.size() == 5 and cue.points[0] == cue.points[-1]
			and Rect2(Vector2.ZERO, research.card_buttons.applied_energy.size).has_point(cue.points[2]),
			"Research focus has a bounded closed shape independent of color at %s" % resolution)
		var detail_viewport: ScrollContainer = research.summary_host.get_parent()
		detail_viewport.ensure_control_visible(research.feedback)
		await settle()
		check(screen.details_panel.get_global_rect().encloses(detail_viewport.get_global_rect())
			and detail_viewport.get_global_rect().encloses(research.feedback.get_global_rect()),
			"Research details scroll within their frame and save errors remain reachable at %s" % resolution)
		check(research.tree_canvas.camera_position == camera_before
			and research.tree_canvas.camera_zoom == zoom_before and state.hangar_snapshot() == research_snapshot,
			"Research presentation and resize preserve pan/zoom and saved state")
	research.state_override.research_focus = ""
	research.refresh()
	check(research.focus_button.visible and research.focus_button.text == "SET FOCUS"
		and not research.card_buttons.applied_energy.has_node("Focus"),
		"Unfocused research restores the discoverable action and removes the focus shape")
	var transport: HangarShip
	for owned: HangarShip in state.fleet:
		if owned.chassis_id == "transport":
			transport = owned
	screen.active_tab = "SHIPS"
	screen.selected_ship_id = transport.id
	screen.selected_slot = ""
	screen._refresh()
	await settle()
	var hull_before: float = transport.hull_hp
	var load_before: Dictionary = transport.mounts.hold.get("load", {}).duplicate(true)
	transport.hull_hp = transport.hull_max * 0.25
	transport.mounts.hold.load = {"kind": "cargo", "quantity": 3, "origin": 0, "unit_value": 3}
	screen._show_details()
	check(screen.stats_grid.bars.size() == 1 and is_equal_approx(screen.stats_grid.bars.hull.value, 25),
		"Default ship hull instrument measures its own exact condition, not normalized chassis strength")
	var cargo: ResourceText = screen.stats_grid.get_child(screen.stats_grid.get_child_count() - 1)
	check(cargo.source_text == "Cargo 3 / 10",
		"Default ship transport instrument shows carried cargo against capacity")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(screen.center.get_global_rect().grow(1).encloses(screen.stats_grid.get_global_rect()),
			"Operational ship stats fit at %s: center %s, stats %s" % [
				resolution, screen.center.get_global_rect(), screen.stats_grid.get_global_rect()])
	transport.hull_hp = 0
	screen._show_details()
	check(screen.stats_grid.bars.hull.value == 0,
		"Living zero-hull ships do not receive the comparison bar's misleading ten-percent floor")
	transport.hull_hp = -1
	screen._show_details()
	check(screen.stats_grid.bars.hull.value == 0,
		"Destroyed ships retain an empty hull condition instrument")
	transport.hull_hp = hull_before
	transport.mounts.hold.load = load_before
	screen._show_details()
	screen.selected_slot = "hold"
	screen._show_details()
	screen._render_refit_panel()
	check(screen.slot_info.source_text.contains("Cargo Hold") and screen.slot_info.source_text.contains("10 cargo"),
		"Selected equipment retains its full name and gameplay effect")
	var duplicate_effect := false
	for child in screen.refit_panel.get_children():
		if child is ResourceText and child.source_text.contains("10 cargo"):
			duplicate_effect = true
	check(not duplicate_effect, "Refit options do not repeat the installed-part effect already shown below the ship")
	var notice: Control = screen.get_node("ResearchCompletion")
	notice.set_process(false)
	state.research_completion_notices.clear()
	state.research_completion_notices.append("laboratory_ii")
	notice._process(0)
	notice._process(0.2)
	check(notice.visible and notice.title.source_text.contains("Laboratory II")
		and notice.effect.source_text == "Labs generate research while traveling.",
		"Research completion banner identifies the upgrade and its real gameplay effect")
	check(notice.get_theme_stylebox("panel").texture.resource_path.ends_with("Popup_GameTips.png")
		and notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and not notice.is_in_group("modal_ui"),
		"Completion uses supplied popup artwork without blocking input or becoming a modal")
	var banner_state: Dictionary = state.hangar_snapshot()
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		notice._process(0)
		check(screen.get_global_rect().grow(1).encloses(notice.get_global_rect())
			and notice.size.x >= screen.size.x - 17
			and notice.get_global_rect().grow(1).encloses(notice.effect.get_global_rect()),
			"Wide completion banner and effect fit at %s" % resolution)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/checks/research-notice/banner-%d.png" % resolution.x)
	screen._refresh()
	await settle()
	check(notice.visible and notice.remaining > 0 and state.hangar_snapshot() == banner_state,
		"Ordinary refresh preserves the completion banner without changing speed or saved state")
	state.research_completion_notices.append("laboratory_iii")
	notice._process(5)
	check(notice.visible and notice.title.source_text.contains("Laboratory III"),
		"Consecutive completions queue instead of overwriting the visible upgrade")
	notice._process(6)
	check(not notice.visible and state.research_completion_notices.is_empty(),
		"Completion banner expires without requiring dismissal")
	print("EXPEDITION_UI_CLARITY_CHECKS=%d failures=%d" % [checks, failures])
	screen.queue_free()
	await settle()
	quit(1 if failures else 0)
