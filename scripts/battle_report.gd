extends PanelContainer

signal closed

func show_report(entries: Array[Dictionary], outcome: String, salvage: int) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 40
	offset_top = 24
	offset_right = -40
	offset_bottom = -24
	var close := preload("res://scenes/close_x_button.tscn").instantiate() as Control
	close.connect("pressed", func() -> void: closed.emit())
	add_child(close)
	var column := VBoxContainer.new()
	add_child(column)
	var title := Label.new()
	title.text = "%s · %d recovered" % [outcome, salvage]
	title.add_theme_font_size_override("font_size", 14)
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var maximum := 1.0
	for entry in entries:
		maximum = maxf(maximum, entry.damage)
	for entry in entries:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var preview := preload("res://scripts/fleet_ship_preview.gd").new()
		preview.owned = entry.ship
		preview.custom_minimum_size = Vector2(68, 68)
		row.add_child(preview)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		var label := Label.new()
		label.text = "%s%s · dealt %.1f / taken %.1f" % [entry.ship.display_name, " — lost" if entry.destroyed else "", entry.damage, entry.taken]
		label.add_theme_font_size_override("font_size", 11)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(label)
		_add_bar(details, entry.damage, maximum)
		for weapon in entry.weapons:
			var weapon_label := Label.new()
			weapon_label.text = "%s  %.1f" % [weapon, entry.weapons[weapon]]
			weapon_label.add_theme_font_size_override("font_size", 10)
			details.add_child(weapon_label)
			_add_bar(details, entry.weapons[weapon], maximum)

func _add_bar(parent: Control, amount: float, maximum: float) -> void:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = amount
	bar.show_percentage = false
	bar.custom_minimum_size.y = 5
	parent.add_child(bar)
