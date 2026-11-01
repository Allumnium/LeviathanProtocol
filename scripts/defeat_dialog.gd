extends Control

func show_game_over() -> void:
	$CenterContainer/Panel/Contents/Score.text = RunScore.description(GameState.hangar_snapshot())
	add_to_group("modal_ui")
	show()
