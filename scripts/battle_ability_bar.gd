extends PanelContainer

signal targeting_changed(enabled: bool)

var simulation: BattleSimulation
var visuals: Control
var targeting := false
var selected_id := "scan"
var source_id := ""
var action_buttons: Dictionary = {}
var auto_button: Button
var pause_aim: Button
var source_picker: OptionButton
var status: Label
var overflow_menu: MenuButton
var _source_ids: Array[String] = []

func _ready() -> void:
	theme_type_variation = &"ContextPanel"
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 2)
	add_child(contents)
	var actions := HBoxContainer.new()
	contents.add_child(actions)
	var ordered: Array[String] = []
	for id in simulation.abilities.state.pins + simulation.abilities.available:
		if simulation.abilities.available.has(id) and not ordered.has(id):
			ordered.append(id)
	for id in ordered.slice(0, 6):
		var button := Button.new()
		button.name = "Ability_" + id
		button.custom_minimum_size = Vector2(64, 24)
		button.pressed.connect(begin_targeting.bind(id))
		actions.add_child(button)
		action_buttons[id] = button
	if ordered.size() > 6:
		var overflow := MenuButton.new()
		overflow_menu = overflow
		overflow.name = "AbilityOverflow"
		overflow.text = "+"
		actions.add_child(overflow)
		for index in range(6, ordered.size()):
			overflow.get_popup().add_item(GameDefinitions.find("abilities", ordered[index]).display_name, index)
		overflow.get_popup().id_pressed.connect(func(index: int) -> void: begin_targeting(ordered[index]))
	var options := HBoxContainer.new()
	contents.add_child(options)
	auto_button = Button.new()
	auto_button.name = "AbilityAuto"
	auto_button.text = "AUTO"
	auto_button.toggle_mode = true
	options.add_child(auto_button)
	auto_button.toggled.connect(func(enabled: bool) -> void:
		if not simulation.issue_command("ability_auto", {"ability": selected_id, "enabled": enabled}):
			status.text = "Save failed"
		refresh())
	source_picker = OptionButton.new()
	source_picker.name = "AbilitySource"
	source_picker.fit_to_longest_item = false
	source_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	source_picker.custom_minimum_size.x = 112
	options.add_child(source_picker)
	source_picker.item_selected.connect(func(index: int) -> void: source_id = "" if index == 0 else _source_ids[index - 1])
	pause_aim = Button.new()
	pause_aim.name = "PauseAim"
	pause_aim.text = "PAUSE AIM"
	pause_aim.toggle_mode = true
	options.add_child(pause_aim)
	pause_aim.toggled.connect(func(enabled: bool) -> void:
		if not simulation.issue_command("ability_pause_aim", {"enabled": enabled}):
			status.text = "Save failed"
		refresh())
	status = Label.new()
	status.name = "AbilityStatus"
	options.add_child(status)
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	for id in action_buttons:
		var button: Button = action_buttons[id]
		var cooldown: float = simulation.abilities.remaining(id)
		button.text = GameDefinitions.find("abilities", id).display_name.to_upper() + (" %d" % ceili(cooldown) if cooldown > 0 else "")
		button.disabled = simulation.phase != BattleSimulation.Phase.COMBAT or cooldown > 0 or simulation.abilities.sources(simulation, 0, id).is_empty()
	if auto_button == null:
		return
	auto_button.set_pressed_no_signal(simulation.abilities.state.auto.get(selected_id, selected_id != "scan"))
	pause_aim.set_pressed_no_signal(simulation.abilities.state.pause_aim)
	var ids: Array[String] = []
	for source in simulation.abilities.sources(simulation, 0, selected_id):
		ids.append(source.entity_id)
	if ids != _source_ids:
		_source_ids = ids
		source_picker.clear()
		source_picker.add_item("AUTO SOURCE")
		for id in ids:
			var source = simulation.entities[id]
			source_picker.add_item(source.owned_ship.display_name if source.owned_ship != null else id)
		if not source_id.is_empty() and not ids.has(source_id):
			source_id = ""
		source_picker.select(ids.find(source_id) + 1)
	if targeting and (simulation.phase != 0 or simulation.abilities.sources(simulation, 0, selected_id).is_empty()):
		cancel_targeting()

func begin_targeting(id: String) -> void:
	if targeting:
		var previous := selected_id
		cancel_targeting()
		if previous == id:
			return
	selected_id = id
	if simulation.abilities.remaining(id) > 0 or simulation.abilities.sources(simulation, 0, id).is_empty():
		return
	targeting = true
	status.text = "Click to scan" if id == "scan" else "Click asteroid" if id == "seismic_cut" else "Click target"
	targeting_changed.emit(true)
	set_preview(visuals.camera_position)

func set_preview(point: Vector2) -> void:
	visuals.ability_preview = {"id": selected_id, "position": point, "valid": simulation.abilities.can_cast(simulation, selected_id, point, source_id),
		"sources": simulation.abilities.sources(simulation, 0, selected_id)}
	visuals.queue_redraw()

func cast_at(point: Vector2) -> bool:
	if not simulation.issue_command("ability_cast", {"ability": selected_id, "position": [point.x, point.y], "source": source_id, "faction": 0}):
		status.text = "Unavailable"
		return false
	cancel_targeting()
	return true

func cancel_targeting() -> void:
	targeting = false
	status.text = ""
	visuals.ability_preview = {}
	visuals.queue_redraw()
	targeting_changed.emit(false)

func menu_open() -> bool:
	return source_picker.get_popup().visible or (overflow_menu != null and overflow_menu.get_popup().visible)
