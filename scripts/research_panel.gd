extends Control

signal focus_requested(research_id: String)

var registry: Dictionary = {}
var state_override: Dictionary = {}
var nodes: Array[Dictionary] = []
var card_buttons: Dictionary = {}

var selected_id := "applied_energy"

var groups_host: VBoxContainer
var summary_host: VBoxContainer
var focus_button: Button
var feedback: Label
var tree_canvas: Control
var view_state: Dictionary = {}

func _ready() -> void:
	if registry.is_empty():
		registry = GameDefinitions.snapshot()
	tree_canvas = load("res://scripts/research_tree_canvas.gd").new()
	if not view_state.is_empty():
		selected_id = view_state.selected_id
		tree_canvas.camera_position = view_state.camera_position
		tree_canvas.camera_zoom = view_state.camera_zoom
		tree_canvas.initial_view_fitted = true
	add_child(tree_canvas)
	tree_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree_canvas.node_selected.connect(_select)
	tree_canvas.node_activated.connect(_activate)
	GameState.research_changed.connect(refresh)
	GameState.travel_plan_changed.connect(_refresh_production)
	refresh(view_state.is_empty())

func bind_external_panels(groups: VBoxContainer, summary: VBoxContainer) -> void:
	groups_host = groups
	summary_host = summary
	refresh()

func set_external_panels_visible(value: bool) -> void:
	if groups_host != null:
		groups_host.visible = value
	if summary_host != null:
		summary_host.visible = value

func _label(text: String) -> ResourceText:
	var label := ResourceText.create(text)
	label.size.x = 100
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 26
	button.theme_type_variation = &"ResearchButton"
	button.focus_mode = Control.FOCUS_NONE
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button

func _clear(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _state() -> Dictionary:
	if not state_override.is_empty():
		return state_override
	return {"research_ids": GameState.current_research_ids, "story_flags": GameState.story_flags,
		"branch_choices": GameState.research_branch_choices,
		"research_focus": GameState.research_focus, "research_progress": GameState.research_progress}

func refresh(fit := false) -> void:
	if tree_canvas == null:
		return
	var state := _state()
	if state_override.is_empty():
		var progress := GameState.run_progress_snapshot()
		for node: Dictionary in registry.research:
			node.cost_rp = ResearchFocusRules.cost(node.id, progress)
	nodes = ResearchViewModel.nodes(registry, state.research_ids, state.story_flags, state.branch_choices)
	nodes.assign(nodes.filter(func(row: Dictionary) -> bool: return row.id != "foundation"))
	if not nodes.any(func(row: Dictionary) -> bool: return row.id == selected_id):
		selected_id = "" if nodes.is_empty() else nodes[0].id
	tree_canvas.populate(nodes, registry, selected_id, state.get("research_focus", ""), state.get("research_progress", {}), fit)
	card_buttons = tree_canvas.buttons
	_refresh_production()
	_refresh_summary()

func _refresh_production() -> void:
	if groups_host == null:
		return
	_clear(groups_host)
	var science := ScienceRules.snapshot(GameState.get_deployed_fleet())
	groups_host.add_child(_label(ScienceRules.production_label(science)))
	groups_host.add_child(_label("%s RP/day" % ScienceRules.format_rp(ScienceRules.production_rate(science))))
	var simulation = GameState.expedition_simulation
	if simulation != null:
		groups_host.add_child(_label("1 day = %d NU\nTravel only" % int(simulation.tuning.nav_units_per_day)))
		return
	var destination := GameState.planned_destination_node_id
	if destination < 0:
		groups_host.add_child(_label("Choose a destination to preview research"))
		return
	var duration := GameState.research_travel_time(GameState.current_node_id, destination)
	groups_host.add_child(_label("%s days" % ScienceRules.format_rp(duration)))
	var output := ScienceRules.journey_rp(science, duration)
	var focus := GameState.research_focus
	if focus.is_empty():
		groups_host.add_child(_label("%s RP stored on arrival" % ScienceRules.format_points(output)))
		return
	var research: Dictionary = GameState.hangar_snapshot().research
	var required := ResearchFocusRules.cost(focus, research)
	var current := float(GameState.research_progress.get(focus, 0))
	var available := output + GameState.research_points + current - floorf(current)
	var allocated := minf(floorf(available), maxf(0, required - floorf(current)))
	var project_name := str(GameDefinitions.find("research", focus).display_name)
	groups_host.add_child(_label("%s RP to %s on arrival" % [ScienceRules.format_points(allocated), project_name]))
	if available > allocated:
		groups_host.add_child(_label("%s excess RP stored" % ScienceRules.format_points(available - allocated)))
func _select(id: String) -> void:
	selected_id = id
	tree_canvas.select(id)
	_refresh_summary()

func _activate(id: String) -> void:
	_select(id)
	if focus_button != null and not focus_button.disabled:
		focus_requested.emit(id)

func _refresh_summary() -> void:
	if summary_host == null:
		return
	_clear(summary_host)
	focus_button = null

	var row: Dictionary = {}
	for candidate in nodes:
		if candidate.id == selected_id:
			row = candidate
	if row.is_empty():
		return
	summary_host.add_child(_label(row.name))
	var body := VBoxContainer.new()
	body.name = "ResearchDescription"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_host.add_child(body)
	var description := ResearchViewModel.description(registry, selected_id)
	if not description.is_empty():
		var description_label := _label(description)
		description_label.theme_type_variation = &"ResearchDescriptionText"
		body.add_child(description_label)
	var required: Dictionary = row.requirements
	var state := _state()
	var focused: bool = state.get("research_focus", "") == selected_id
	if required.owned:
		pass
	else:
		summary_host.add_child(_label("%s / %d RP" % [ScienceRules.format_points(float(state.get("research_progress", {}).get(selected_id, 0))), int(row.cost)]))
		focus_button = _button("SET FOCUS")
		focus_button.visible = not focused
		focus_button.disabled = focused or not row.nearby or (state_override.is_empty() and (GameState.battle_pending or GameState.run_ended))
		AudioManager.connect_ui_button(focus_button)
		focus_button.pressed.connect(func() -> void: focus_requested.emit(selected_id))
		summary_host.add_child(focus_button)
	feedback = Label.new()
	feedback.hide()
	summary_host.add_child(feedback)

func show_failure() -> void:
	refresh()
	feedback.text = "Save failed. Retry."
	feedback.show()
