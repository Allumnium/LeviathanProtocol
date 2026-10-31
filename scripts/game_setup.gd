extends Control

signal back_requested
signal start_requested(difficulty: int)

@onready var difficulty_button: Button = $CenterContainer/SetupModal/Contents/SettingsMargin/SettingsRows/DifficultyRow/DifficultyButton
@onready var difficulty_details: Label = $CenterContainer/SetupModal/Contents/SettingsMargin/SettingsRows/DifficultyDetails
@onready var back_button: TextureButton = $CenterContainer/SetupModal/CloseX
@onready var start_button: Button = $CenterContainer/SetupModal/Contents/Buttons/StartButton
@onready var setup_modal: PanelContainer = $CenterContainer/SetupModal

var selected_difficulty := GameState.Difficulty.MEDIUM


func _ready() -> void:
	difficulty_button.pressed.connect(_on_difficulty_pressed)
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	visibility_changed.connect(_on_visibility_changed)
	_update_difficulty_display()
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
	start_requested.emit(selected_difficulty)
