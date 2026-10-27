extends Control

signal purchase_requested(research_id: String)

var registry: Dictionary = {}
var state_override: Dictionary = {} # Dependency injection for isolated UI checks.
var nodes: Array[Dictionary] = []
var card_buttons: Dictionary = {}
var group_headers: Dictionary = {}
var collapsed: Dictionary = {}
var selected_id := "foundation"
var list_scroll: ScrollContainer
var list: VBoxContainer
var groups_host: VBoxContainer
var summary_host: VBoxContainer
var details_dialog: PanelContainer
var review_action: Button
var rp_label: Label

func _ready() -> void:
	if registry.is_empty():
		registry = GameDefinitions.snapshot()
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 4)
	rp_label = _label("RESEARCH", 12)
	box.add_child(rp_label)
	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list_scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)
	GameState.research_changed.connect(refresh)
	refresh()

func bind_external_panels(groups: VBoxContainer, summary: VBoxContainer) -> void:
	groups_host = groups
	summary_host = summary
	refresh()

func set_external_panels_visible(value: bool) -> void:
	if groups_host != null:
		groups_host.visible = value
	if summary_host != null:
		summary_host.visible = value

func _label(text: String, font_size := 10) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", ThemeDB.fallback_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", ThemeDB.fallback_font)
	button.add_theme_font_size_override("font_size", 10)
	button.custom_minimum_size.y = 24
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18252d")
	style.border_color = Color("637985")
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var variant := style.duplicate()
		if state == "hover":
			variant.bg_color = Color("2b4351")
		button.add_theme_stylebox_override(state, variant)
	return button

func _clear(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _state() -> Dictionary:
	if not state_override.is_empty():
		return state_override
	return {"research_ids": GameState.current_research_ids, "story_flags": GameState.story_flags,
		"branch_choices": GameState.research_branch_choices, "research_points": GameState.research_points}

func refresh() -> void:
	if list == null:
		return
	close_details()
	var state := _state()
	nodes = ResearchViewModel.nodes(registry, state.research_ids, state.story_flags, state.branch_choices, int(state.research_points))
	_clear(list)
	card_buttons.clear()
	group_headers.clear()
	rp_label.text = "RESEARCH · %d RP" % int(state.research_points)
	var visible_ids: Array = nodes.map(func(node: Dictionary) -> String: return node.id)
	if not visible_ids.has(selected_id):
		selected_id = "" if nodes.is_empty() else nodes[0].id
	var groups: Array[String] = []
	for node in nodes:
		if not groups.has(node.group):
			groups.append(node.group)
	groups.sort_custom(func(a: String, b: String) -> bool:
		var a_near := nodes.any(func(n: Dictionary) -> bool: return n.group == a and n.nearby)
		var b_near := nodes.any(func(n: Dictionary) -> bool: return n.group == b and n.nearby)
		return a_near if a_near != b_near else ResearchViewModel.GROUP_NAMES[a] < ResearchViewModel.GROUP_NAMES[b])
	for group in groups:
		var members: Array[Dictionary] = []
		members.assign(nodes.filter(func(n: Dictionary) -> bool: return n.group == group))
		var nearby := members.any(func(n: Dictionary) -> bool: return n.nearby)
		if not collapsed.has(group):
			collapsed[group] = group != "shared" and not nearby
		var header := _button(("▸ " if collapsed[group] else "▾ ") + ResearchViewModel.GROUP_NAMES[group] + (" · next" if nearby else ""))
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.pressed.connect(func() -> void:
			collapsed[group] = not collapsed[group]
			refresh())
		list.add_child(header)
		group_headers[group] = header
		if collapsed[group]:
			continue
		var paths: Array[String] = []
		for member in members:
			if not paths.has(member.path):
				paths.append(member.path)
		for path in paths:
			if not path.is_empty():
				list.add_child(_label(path.capitalize() + " — choose one path", 10))
			var columns := HBoxContainer.new()
			columns.add_theme_constant_override("separation", 4)
			list.add_child(columns)
			var max_depth := 0
			for member in members:
				max_depth = maxi(max_depth, int(member.depth))
			for depth in range(max_depth + 1):
				var tier := VBoxContainer.new()
				tier.custom_minimum_size.x = 78
				columns.add_child(tier)
				tier.add_child(_label("Tier %d" % (depth + 1), 9))
				for member in members:
					if member.path != path or int(member.depth) != depth:
						continue
					var card := _button("%s\n%d RP\n%s" % [member.name, member.cost, member.status])
					card.custom_minimum_size = Vector2(78, 62)
					card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					card.tooltip_text = ResearchViewModel.details(registry, member.id, visible_ids)
					if member.nearby:
						card.modulate = Color("a7e2bc")
					elif member.status == "Excluded":
						card.modulate = Color("c29292")
					card.pressed.connect(_select.bind(member.id))
					tier.add_child(card)
					card_buttons[member.id] = card
	if nodes.size() <= 1:
		list.add_child(_label("No further research is available yet. New options appear when their systems are ready.", 10))
	_refresh_groups(groups)
	_refresh_summary()

func _refresh_groups(groups: Array[String]) -> void:
	if groups_host == null:
		return
	_clear(groups_host)
	groups_host.add_child(_label("RESEARCH FAMILIES", 11))
	groups_host.add_child(_label("%d RP available" % int(_state().research_points)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	groups_host.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for group in groups:
		var button := _button(ResearchViewModel.GROUP_NAMES[group])
		button.pressed.connect(func() -> void:
			collapsed[group] = false
			refresh()
			call_deferred("_scroll_group", group))
		box.add_child(button)

func _scroll_group(group: String) -> void:
	if group_headers.has(group):
		list_scroll.ensure_control_visible(group_headers[group])

func _select(id: String) -> void:
	selected_id = id
	_refresh_summary()
	open_details()

func _refresh_summary() -> void:
	if summary_host == null:
		return
	_clear(summary_host)
	summary_host.add_child(_label("RESEARCH DETAILS", 11))
	for node in nodes:
		if node.id != selected_id:
			continue
		summary_host.add_child(_label("%s\n%d RP\n%s" % [node.name, node.cost, node.status], 11))
		var button := _button("VIEW GRANTS")
		button.pressed.connect(open_details)
		summary_host.add_child(button)
	summary_host.add_child(_label("Review grants and branch locks."))

func open_details() -> void:
	if selected_id.is_empty():
		return
	if is_instance_valid(details_dialog):
		details_dialog.queue_free()
	details_dialog = PanelContainer.new()
	details_dialog.name = "ResearchDetails"
	details_dialog.add_to_group("modal_ui")
	details_dialog.z_index = 30
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("18252d")
	panel_style.border_color = Color("8295a3")
	panel_style.set_border_width_all(2)
	panel_style.set_content_margin_all(6)
	details_dialog.add_theme_stylebox_override("panel", panel_style)
	var scene := get_tree().current_scene
	(scene if scene != null else get_parent()).add_child(details_dialog)
	details_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	details_dialog.offset_left = 16
	details_dialog.offset_top = 16
	details_dialog.offset_right = -16
	details_dialog.offset_bottom = -16
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	details_dialog.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	box.add_child(_label("RESEARCH REVIEW", 14))
	var scroll := ScrollContainer.new()
	scroll.name = "ReviewScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var visible_ids: Array = nodes.map(func(node: Dictionary) -> String: return node.id)
	var text := _label(ResearchViewModel.details(registry, selected_id, visible_ids), 12)
	scroll.add_child(text)
	var selected: Dictionary = {}
	for node in nodes:
		if node.id == selected_id:
			selected = node
	box.add_child(_label("Current state: " + selected.get("status", "Unavailable"), 11))
	var definition := ResearchViewModel.find(registry, "research", selected_id)
	if not definition.get("family_id", "").is_empty():
		var opposite_paths: Array[String] = []
		for excluded: String in definition.exclusion_ids:
			var other := ResearchViewModel.find(registry, "research", excluded)
			if not opposite_paths.has(other.path_id):
				opposite_paths.append(other.path_id)
		box.add_child(_label("Commits %s to %s; locks every %s tier. No respec this run." % [ResearchViewModel.GROUP_NAMES[definition.family_id],
			String(definition.path_id).capitalize(), ", ".join(opposite_paths).capitalize()], 11))
	if not selected.is_empty():
		var requirements: Dictionary = selected.requirements
		if not requirements.missing_prerequisites.is_empty():
			box.add_child(_label("Still needed: " + ResearchViewModel.names(registry, "research", requirements.missing_prerequisites)))
		if not requirements.conflicts.is_empty():
			box.add_child(_label("Locked by: " + ResearchViewModel.names(registry, "research", requirements.conflicts)))
		if selected.status == "Need RP":
			box.add_child(_label("Need %d more RP." % (int(selected.cost) - int(_state().research_points))))
	# An actual acquisition handler is connected only when its transaction/effects
	# are ready. This UI alone never authorizes or spends research points.
	if not purchase_requested.get_connections().is_empty() and selected.get("status") == "Ready":
		review_action = _button("RESEARCH FOR %d RP" % int(selected.cost))
		review_action.pressed.connect(func() -> void:
			purchase_requested.emit(selected_id)
			close_details())
		box.add_child(review_action)
	else:
		review_action = null
		if purchase_requested.get_connections().is_empty() and selected.get("status") != "Owned":
			box.add_child(_label("Research purchases are not available yet.", 10))
	var close := _button("CLOSE")
	close.pressed.connect(close_details)
	box.add_child(close)

func close_details() -> void:
	review_action = null
	if is_instance_valid(details_dialog):
		details_dialog.hide()
		details_dialog.queue_free()

func _exit_tree() -> void:
	close_details()
