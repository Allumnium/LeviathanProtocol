extends Control

signal back_requested
signal start_requested(difficulty: int, flagship_id: String)

@onready var difficulty_button: Button = $CenterContainer/SetupModal/Contents/SettingsMargin/SettingsRows/DifficultyRow/DifficultyButton
@onready var difficulty_details: Label = $CenterContainer/SetupModal/Contents/SettingsMargin/SettingsRows/DifficultyDetails
@onready var back_button: TextureButton = $CenterContainer/SetupModal/CloseX
@onready var start_button: Button = $CenterContainer/SetupModal/Contents/Buttons/StartButton
@onready var setup_modal: PanelContainer = $CenterContainer/SetupModal

var selected_difficulty := GameState.Difficulty.MEDIUM
var selected_flagship := 0
var flagship_choices: Array[Dictionary] = []
var flagship_name: Label
var flagship_preview: Control
var flagship_stats: GridContainer
var flagship_description: ResourceText
var flagship_bonuses: ResourceText
var flagship_command: Label
var status: Label


func _ready() -> void:
	add_to_group("modal_ui")
	flagship_choices = SlotCatalog.flagships()
	_build_carousel()
	AudioManager.connect_ui_button(difficulty_button, &"detail")
	AudioManager.connect_ui_button(back_button)
	AudioManager.connect_ui_button(start_button)
	difficulty_button.pressed.connect(_on_difficulty_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	visibility_changed.connect(_on_visibility_changed)
	_update_difficulty_display()
	_update_flagship()
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if visible:
		setup_modal.show()


func _on_difficulty_pressed() -> void:
	match selected_difficulty:
		GameState.Difficulty.MEDIUM:
			selected_difficulty = GameState.Difficulty.HARD
		GameState.Difficulty.HARD:
			selected_difficulty = GameState.Difficulty.EASY
		_:
			selected_difficulty = GameState.Difficulty.MEDIUM
	_update_difficulty_display()


func _update_difficulty_display() -> void:
	difficulty_button.text = ["EASY", "NORMAL", "HARD"][selected_difficulty]
	_update_difficulty_details(selected_difficulty)


func _update_difficulty_details(selected_difficulty: int) -> void:
	match selected_difficulty:
		GameState.Difficulty.EASY:
			difficulty_details.text = (
				"Alien strength: 75%"
			)
		GameState.Difficulty.MEDIUM:
			difficulty_details.text = (
				"Alien strength: 100%"
			)
		GameState.Difficulty.HARD:
			difficulty_details.text = (
				"Alien strength: 150%"
			)
		_:
			push_error("Cannot show details for an unknown difficulty.")


func _on_back_pressed() -> void:
	back_requested.emit()


func _on_start_pressed() -> void:
	start_requested.emit(selected_difficulty, flagship_choices[selected_flagship].id)

func _build_carousel() -> void:
	var contents: VBoxContainer = $CenterContainer/SetupModal/Contents
	var navigation := HBoxContainer.new()
	navigation.name = "FlagshipCarousel"
	contents.add_child(navigation)
	contents.move_child(navigation, 1)
	var previous := Button.new()
	previous.name = "PreviousFlagship"
	previous.text = "<"
	previous.custom_minimum_size = Vector2(28, 24)
	navigation.add_child(previous)
	flagship_name = Label.new()
	flagship_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flagship_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(flagship_name)
	var next := Button.new()
	next.name = "NextFlagship"
	next.text = ">"
	next.custom_minimum_size = Vector2(28, 24)
	navigation.add_child(next)
	for button: Button in [previous, next]:
		AudioManager.connect_ui_button(button, &"detail")
	previous.pressed.connect(_cycle_flagship.bind(-1))
	next.pressed.connect(_cycle_flagship.bind(1))
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.name = "FlagshipDetails"
	scroll.custom_minimum_size.y = 140
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contents.add_child(scroll)
	contents.move_child(scroll, 2)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	flagship_preview = preload("res://scripts/fleet_ship_preview.gd").new()
	flagship_preview.name = "FlagshipPreview"
	flagship_preview.custom_minimum_size = Vector2(120, 120)
	row.add_child(flagship_preview)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	flagship_command = Label.new()
	details.add_child(flagship_command)
	flagship_stats = preload("res://scripts/ship_stat_bars.gd").new()
	flagship_stats.columns = 2
	details.add_child(flagship_stats)
	flagship_bonuses = ResourceText.create("")
	flagship_bonuses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(flagship_bonuses)
	flagship_description = ResourceText.create("")
	flagship_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(flagship_description)
	status = Label.new()
	status.name = "StartStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("ffd28a"))
	status.hide()
	body.add_child(status)
	body.move_child(status, 0)

func _cycle_flagship(direction: int) -> void:
	selected_flagship = posmod(selected_flagship + direction, flagship_choices.size())
	_update_flagship()

func _update_flagship() -> void:
	var chassis: Dictionary = flagship_choices[selected_flagship]
	var ship := HangarShip.new()
	ship.initialize_chassis(chassis.id, 0, true)
	flagship_preview.owned = ship
	flagship_preview.queue_redraw()
	flagship_name.text = "%s   %d / %d" % [chassis.name, selected_flagship + 1, flagship_choices.size()]
	flagship_command.text = "Command Points %d" % chassis.command
	flagship_stats.set_ship(ship)
	flagship_bonuses.set_content(SlotCatalog.chassis_bonuses(chassis))
	var loadouts = preload("res://scripts/ship_loadouts.gd")
	var research := loadouts.starting_research([loadouts.default_for(chassis.id), loadouts.default_for("transport"), loadouts.default_for("fighter")])
	research.erase("foundation")
	flagship_description.set_content(chassis.description + "\n\nStarting research: "
		+ ResearchViewModel.names(HangarResearch.registry(), "research", research))
	$CenterContainer/SetupModal/Contents/FlagshipDetails.scroll_vertical = 0
	status.hide()

func show_start_error(message: String) -> void:
	status.text = "Could not start run: " + message
	status.show()
	$CenterContainer/SetupModal/Contents/FlagshipDetails.scroll_vertical = 0
