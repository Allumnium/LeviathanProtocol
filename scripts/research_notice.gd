extends PanelContainer

const UiKit = preload("res://scripts/ui_kit.gd")

var title: ResourceText
var effect: ResourceText
var remaining := 0.0

func _ready() -> void:
	name = "ResearchCompletion"
	theme_type_variation = &"ResearchNotice"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = UiKit.TOAST_Z
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	title = ResourceText.create("")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(title)
	effect = ResourceText.create("")
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(effect)
	hide()

func _process(delta: float) -> void:
	remaining = maxf(0, remaining - delta)
	if remaining == 0 and not GameState.research_completion_notices.is_empty():
		var id: String = GameState.research_completion_notices.pop_front()
		var registry := HangarResearch.view_registry()
		var definition := ResearchViewModel.find(registry, "research", id)
		title.set_content("RP  " + str(definition.display_name) + " complete")
		effect.set_content(ResearchViewModel.description(registry, id))
		remaining = 5.0
		AudioManager.play_ui_sfx(&"research_complete")
	visible = remaining > 0
	if not visible:
		return
	var host := get_parent() as Control
	var header: Control = host.get("command_header")
	var width := maxf(1, host.size.x - 16)
	custom_minimum_size.x = width
	title.custom_minimum_size.x = maxf(1, width - 32)
	effect.custom_minimum_size.x = maxf(1, width - 32)
	size = Vector2(width, get_combined_minimum_size().y)
	position = Vector2(8, header.get_global_rect().end.y - host.global_position.y + 4).round()
	modulate.a = minf(1, minf((5.0 - remaining) / 0.18, remaining / 0.35))
