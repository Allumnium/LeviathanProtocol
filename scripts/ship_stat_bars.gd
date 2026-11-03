class_name ShipStatBars
extends GridContainer

const KEYS := ["hull", "maneuverability", "mass", "shields"]
const TITLES := ["Hull", "Maneuverability", "Mass", "Shields"]
var bars: Dictionary[String, TextureProgressBar] = {}
static var _ranges: Dictionary = {}
static var _movement_average := 0.0

static func movement_total(stats: ShipStats) -> float:
	return stats.top_speed + stats.acceleration + stats.turn_rate

static func maneuverability(stats: ShipStats) -> float:
	if _movement_average == 0.0:
		var chassis := SlotCatalog.chassis()
		assert(not chassis.is_empty(), "Maneuverability requires chassis reference stats")
		for entry: Dictionary in chassis:
			var ship := HangarShip.new()
			var initialized := ship.initialize_chassis(entry.id, 0, int(entry.command) > 0)
			assert(initialized, "Maneuverability requires valid chassis")
			_movement_average += movement_total(ship.get_stats()) / chassis.size()
		assert(_movement_average > 0.0, "Maneuverability requires positive reference movement")
	# Weight normalized movement factors by their means, then divide by their sum.
	return 50.0 * movement_total(stats) / _movement_average

static func values(ship: HangarShip) -> Dictionary:
	var stats := ship.get_stats()
	return {"hull": ship.hull_hp, "maneuverability": maneuverability(stats),
		"mass": stats.weight, "shields": stats.shields}

static func comparison_ranges() -> Dictionary:
	if not _ranges.is_empty():
		return _ranges.duplicate(true)
	for chassis: Dictionary in SlotCatalog.chassis():
		var ship := HangarShip.new()
		var initialized := ship.initialize_chassis(chassis.id, 0, int(chassis.command) > 0)
		assert(initialized, "Ship stat comparison requires valid base chassis")
		var base := values(ship)
		for key: String in KEYS:
			if not _ranges.has(key):
				_ranges[key] = Vector2(base[key], base[key])
			else:
				_ranges[key] = Vector2(minf(_ranges[key].x, base[key]), maxf(_ranges[key].y, base[key]))
	for key: String in KEYS:
		assert(_ranges[key].y > _ranges[key].x, "Ship stat comparison requires differing chassis values: " + key)
	return _ranges.duplicate(true)

static func percentage(value: float, limits: Vector2) -> float:
	assert(limits.y > limits.x, "Ship stat comparison range must not be equal")
	return clampf(10.0 + 90.0 * (value - limits.x) / (limits.y - limits.x), 10.0, 100.0)

func _init() -> void:
	name = "ShipStatBars"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 4)

func set_ship(ship: HangarShip, comparison := true) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	bars.clear()
	var actual := values(ship) if comparison else {"hull": ship.hull_hp, "shields": ship.get_stats().shields}
	var ranges := comparison_ranges() if comparison else {}
	for index in range(KEYS.size()):
		var key: String = KEYS[index]
		if not comparison and key in ["mass", "maneuverability"]:
			continue
		if key == "shields" and actual[key] <= 0:
			continue
		var cell := VBoxContainer.new()
		cell.name = key.capitalize() + "Stat"
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		add_child(cell)
		var numeric := str(roundi(actual[key]))
		if key == "hull":
			numeric = "%d / %d" % [roundi(ship.hull_hp), roundi(ship.hull_max)]
		var label := ResourceText.create("%s %s" % [TITLES[index], numeric])
		label.name = "StatValue"
		label.theme_type_variation = &"ShipStatText"
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.add_child(label)
		label.resized.connect(_fit_value.bind(label))
		label.theme_changed.connect(_fit_value.bind(label))
		# Shields in the hangar are available capacity, not a saved combat charge.
		if not comparison and key == "shields":
			continue
		var bar := TextureProgressBar.new()
		bar.name = key.capitalize() + "Bar"
		bar.texture_progress = preload("res://assets/ui/Progress_Cp.png")
		bar.texture_under = preload("res://assets/ui/Progress_Cp_Bg.png")
		bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bar.nine_patch_stretch = true
		bar.custom_minimum_size = Vector2(0, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.step = 0.0
		bar.value = percentage(actual[key], ranges[key]) if comparison \
			else 100.0 * clampf(ship.hull_hp / maxf(1.0, ship.hull_max), 0.0, 1.0)
		cell.add_child(bar)
		bars[key] = bar
	var stats := ship.get_stats()
	if stats.dps > 0:
		_add_readout("DPS %d" % roundi(stats.dps))
	var summary := ship.hangar_summary()
	var loads := {}
	if not comparison:
		var equipment := {}
		for instance: Dictionary in ship.mounts.values():
			equipment[instance.uid] = instance
		loads = HangarTrade.summary({"ships": [ship.to_hangar_data()], "equipment": equipment})
	if summary.cargo > 0:
		_add_readout("Cargo\n%d" % summary.cargo if comparison \
			else "Cargo %d / %d" % [loads.cargo, summary.cargo])
	if summary.passengers > 0:
		_add_readout("Passengers\n%d" % summary.passengers if comparison \
			else "Passengers %d / %d" % [loads.passengers, summary.passengers])

func _add_readout(value: String) -> void:
	var label := ResourceText.create(value)
	label.theme_type_variation = &"ShipStatText"
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(label)
	label.resized.connect(_fit_value.bind(label))
	label.theme_changed.connect(_fit_value.bind(label))

func _fit_value(label: ResourceText) -> void:
	if label.size.x <= 0:
		return
	var font := label.get_theme_font("normal_font")
	var font_size := get_theme_font_size("normal_font_size", "ShipStatText")
	var measured := label.source_text.replace("Shields", "O")
	while font_size > 1 and font.get_string_size(measured, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	if label.get_theme_font_size("normal_font_size") != font_size:
		label.add_theme_font_size_override("normal_font_size", font_size)
