extends HBoxContainer

var simulation: BattleSimulation
var values: Dictionary = {}

func _ready() -> void:
	name = "BattleTransport"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 6)
	var totals := carried()
	for kind: String in ["cargo", "passengers"]:
		var capacity := "cargo_capacity" if kind == "cargo" else "passenger_capacity"
		if totals[capacity] <= 0:
			continue
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 2)
		add_child(row)
		var icon := Control.new()
		icon.name = kind.capitalize() + "Icon"
		icon.custom_minimum_size = Vector2(12, 12)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		icon.draw.connect(func() -> void: draw_symbol(icon, kind))
		var label := Label.new()
		label.name = kind.capitalize() + "Count"
		label.theme_type_variation = &"HeaderResearch"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		values[kind] = label
	refresh()

func _process(_delta: float) -> void:
	refresh()

func carried() -> Dictionary:
	var data := {"ships": [], "equipment": {}}
	for member: BattleSimulation.Combatant in simulation.players:
		if not member.is_alive() or not member.owned_ship is HangarShip:
			continue
		var ship: HangarShip = member.owned_ship
		data.ships.append(ship.to_hangar_data())
		for instance: Dictionary in ship.mounts.values():
			data.equipment[instance.uid] = instance
	return HangarTrade.summary(data)

func refresh() -> void:
	var totals := carried()
	for kind: String in values:
		var label: Label = values[kind]
		label.text = "x%d" % totals[kind]
	visible = not values.is_empty()

static func draw_symbol(target: Control, kind: String) -> void:
	var color := target.get_theme_color("font_color", "Label")
	if kind == "cargo":
		target.draw_polyline(PackedVector2Array([Vector2(1, 3), Vector2(6, 1), Vector2(11, 3),
			Vector2(11, 9), Vector2(6, 11), Vector2(1, 9), Vector2(1, 3), Vector2(6, 5),
			Vector2(11, 3)]), color, 1)
		target.draw_line(Vector2(6, 5), Vector2(6, 11), color, 1)
	else:
		target.draw_arc(Vector2(6, 3), 2, 0, TAU, 12, color, 1)
		target.draw_polyline(PackedVector2Array([Vector2(2, 11), Vector2(2, 8),
			Vector2(4, 6), Vector2(8, 6), Vector2(10, 8), Vector2(10, 11)]), color, 1)
