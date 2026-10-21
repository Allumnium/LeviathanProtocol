extends Control

const GAME_MAP_SCENE_PATH := "res://scenes/game_map.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

@onready var difficulty_selector: OptionButton = $CenterContainer/SetupModal/Contents/DifficultySelector
@onready var difficulty_details: Label = $CenterContainer/SetupModal/Contents/DifficultyDetails
@onready var back_button: Button = $CenterContainer/SetupModal/Contents/Buttons/BackButton
@onready var start_button: Button = $CenterContainer/SetupModal/Contents/Buttons/StartButton


func _ready() -> void:
	difficulty_selector.add_item("EASY - 75%", GameState.Difficulty.EASY)
	difficulty_selector.add_item("MEDIUM - 100%", GameState.Difficulty.MEDIUM)
	difficulty_selector.add_item("HARD - 150%", GameState.Difficulty.HARD)
	difficulty_selector.select(1)
	difficulty_selector.item_selected.connect(_on_difficulty_selected)
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	_update_difficulty_details(GameState.Difficulty.MEDIUM)


func _on_difficulty_selected(index: int) -> void:
	_update_difficulty_details(difficulty_selector.get_item_id(index))


func _update_difficulty_details(selected_difficulty: int) -> void:
	match selected_difficulty:
		GameState.Difficulty.EASY:
			difficulty_details.text = "ALIEN SHIP STATS ARE 75% OF BASE VALUES."
		GameState.Difficulty.MEDIUM:
			difficulty_details.text = "ALIEN SHIP STATS ARE AT BASE VALUES."
		GameState.Difficulty.HARD:
			difficulty_details.text = "ALIEN SHIP STATS ARE 150% OF BASE VALUES."
		_:
			push_error("Cannot show details for an unknown difficulty.")


func _on_back_pressed() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)


func _on_start_pressed() -> void:
	var selected_difficulty := difficulty_selector.get_selected_id()
	if not GameState.start_new_run(selected_difficulty):
		return

	var error := get_tree().change_scene_to_file(GAME_MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not open the game map scene. Error code: %s" % error)
