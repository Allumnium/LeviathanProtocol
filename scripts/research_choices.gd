extends Control

signal closed
signal chosen

const UiKit = preload("res://scripts/ui_kit.gd")
var buttons: Dictionary = {}
var cards: Dictionary = {}
var requirements: Dictionary = {}
var feedback: Label
var panel: PanelContainer
var busy := false

func _ready() -> void:
	name = "ResearchChoices"
	var dialog := UiKit.dialog(self, "ResearchUpgradeSelection", "Choose an upgrade", "",
		null, _close, UiKit.DIALOG_Z, 900)
	dialog.root.set_meta("close_target", true)
	panel = dialog.panel
	var row := HBoxContainer.new()
	row.name = "UpgradeCards"
	row.add_theme_constant_override("separation", 8)
	dialog.column.add_child(row)
	var registry := HangarResearch.view_registry()
	for id: String in GameState.research_offer:
		var definition := GameDefinitions.find("research", id)
		var card := PanelContainer.new()
		card.name = "Card_" + id
		card.theme_type_variation = &"ContextPanel"
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 180
		row.add_child(card)
		cards[id] = card
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 12)
		card.add_child(body)
		var title := UiKit.label(str(definition.display_name), &"HeaderResearch")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.custom_minimum_size.y = 38
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.add_child(title)
		var description := UiKit.label(ResearchViewModel.description(registry, id), &"ResearchDescriptionText")
		description.size_flags_vertical = SIZE_EXPAND_FILL
		description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(description)
		# Branch commitments are a choice consequence, rather than a prerequisite diagram.
		if not definition.family_id.is_empty() and not GameState.research_branch_choices.has(ResearchRules.family_key(definition.family_id)):
			var family := Content.get_def("research_family", definition.family_id)
			var branch := UiKit.label("Locks other " + str(family.get("label", definition.family_id)).to_lower() + " paths.", &"ResearchDescriptionText")
			branch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(branch)
		var choose := UiKit.button("CHOOSE", _choose.bind(id))
		choose.name = "Choose_" + id
		body.add_child(choose)
		buttons[id] = choose
		var requirement := UiKit.label(ResearchUpgrades.requirement(id), &"ResearchDescriptionText")
		requirement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		requirement.add_theme_color_override("font_color", Color("ffd28a"))
		body.add_child(requirement)
		requirements[id] = requirement
	feedback = UiKit.label("", &"ResearchDescriptionText")
	feedback.add_theme_color_override("font_color", Color("ffb0a0"))
	dialog.column.add_child(feedback)
	resized.connect(_resize_cards)
	_resize_cards()
	GameState.fleet_changed.connect(_refresh_matches)
	_refresh_matches()

func _refresh_matches() -> void:
	var deployed := GameState.get_deployed_fleet()
	for id: String in buttons:
		var matches := ResearchUpgrades.matches(id, deployed)
		buttons[id].disabled = not matches
		requirements[id].visible = not matches

func _resize_cards() -> void:
	if panel == null:
		return
	panel.custom_minimum_size.x = maxf(1, minf(900, get_parent_control().size.x - 48))

func _choose(id: String) -> void:
	if busy:
		return
	busy = true
	if not GameState.choose_research(id):
		feedback.text = GameState.last_save_error
		_refresh_matches()
		busy = false
		return
	chosen.emit()
	queue_free()

func _close() -> void:
	closed.emit()
	queue_free()
