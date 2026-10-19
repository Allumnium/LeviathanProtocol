extends Control

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"


func _ready() -> void:
	_resolve_battle()


func _resolve_battle() -> void:
	await get_tree().create_timer(3.0).timeout
	if not GameState.complete_battle():
		return

	var error := get_tree().change_scene_to_file(MAP_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the game map. Error code: %s" % error)
