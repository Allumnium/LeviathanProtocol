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

func _ready() -> void:
	if registry.is_empty():
		registry = GameDefinitions.snapshot()
	tree_canvas = load("res://scripts/research_tree_canvas.gd").new()
	add_child(tree_canvas)
	tree_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree_canvas.node_selected.connect(_select)
	GameState.research_changed.connect(refresh)
	GameState.travel_plan_changed.connect(_refresh_production)
	refresh(true)

func bind_external_panels(groups: VBoxContainer, summary: VBoxContainer) -> void:
	groups_host = groups
	summary_host = summary
	refresh()

func set_external_panels_visible(value: bool) -> void:
	if groups_host != null:
		groups_host.visible = value
	if summary_host != null:
		summary_host.visible = value

func _label(text: String) -> Label:
	var label := Label.new()
	label.size.x = 100
	label.text = text
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
		"branch_choices": GameState.research_branch_choices, "research_points": GameState.research_points,
		"research_focus": GameState.research_focus, "research_progress": GameState.research_progress}

func refresh(fit := false) -> void:
	if tree_canvas == null:
		return
	var state := _state()
	if state_override.is_empty():
		var progress := GameState.run_progress_snapshot()
		for node: Dictionary in registry.research:
			node.cost_rp = ResearchFocusRules.cost(node.id, progress)
	nodes = ResearchViewModel.nodes(registry, state.research_ids, state.story_flags, state.branch_choices, int(state.research_points))
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
	groups_host.add_child(_label("PRODUCTION"))
	var science := ScienceRules.snapshot(GameState.get_deployed_fleet())
	groups_host.add_child(_label(ScienceRules.production_label(science) + "\n+ 0.5 baseline"))
	groups_host.add_child(_label("%.1f RP/day" % ScienceRules.production_rate(science)))
	var destination := GameState.planned_destination_node_id
	if destination < 0:
		groups_host.add_child(_label("RP/day x travel days"))
		return
	var duration := GameState.research_travel_time(GameState.current_node_id, destination)
	groups_host.add_child(_label("%s days" % ScienceRules.format_rp(duration)))
	groups_host.add_child(_label("%s RP on arrival" % ScienceRules.format_rp(ScienceRules.journey_rp(science, duration))))
func _select(id: String) -> void:
	selected_id = id
	tree_canvas.select(id)
	_refresh_summary()

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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summary_host.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.add_child(_label(ResearchViewModel.effect_summary(registry, selected_id)))
	var required: Dictionary = row.requirements
	if not required.missing_prerequisites.is_empty():
		body.add_child(_label("Requires: " + ResearchViewModel.names(registry, "research", required.missing_prerequisites)))
	for gate: String in required.missing_story_gates:
		body.add_child(_label(ResearchViewModel.GATE_NAMES.get(gate, gate)))
	if row.status == "Excluded":
		body.add_child(_label("Path locked"))
	var definition := ResearchViewModel.find(registry, "research", selected_id)
	if not definition.family_id.is_empty() and not required.owned:
		body.add_child(_label("Locks other %s path" % ResearchViewModel.GROUP_NAMES[definition.family_id]))
	var state := _state()
	var focused: bool = state.get("research_focus", "") == selected_id
	if required.owned:
		pass
	else:
		summary_host.add_child(_label("%s / %d RP" % [ScienceRules.format_rp(float(state.get("research_progress", {}).get(selected_id, 0))), int(row.cost)]))
		focus_button = _button("FOCUSED" if focused else "SET FOCUS")
		focus_button.disabled = focused or not row.nearby or (state_override.is_empty() and (GameState.battle_pending or GameState.run_ended))
		focus_button.pressed.connect(func() -> void: focus_requested.emit(selected_id))
		summary_host.add_child(focus_button)
	feedback = _label("")
	feedback.hide()
	summary_host.add_child(feedback)

func show_failure() -> void:
	refresh()
	feedback.text = "Save failed. Retry."
	feedback.show()
