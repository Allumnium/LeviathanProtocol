extends VBoxContainer

const UI = preload("res://scripts/fleet_panel.gd")
var fleet_panel: Control
var material_labels: Array[Label] = []
var buy_buttons: Array[Button] = []
var construction_cost := Label.new()
var construct := Button.new()
var repair_name := Label.new()
var repair := Button.new()

func _ready() -> void:
	add_theme_constant_override("separation", 5)
	var title := Label.new()
	title.text = "SHOP"
	title.add_theme_font_override("font", preload("res://assets/fonts/TKCLSCR2.TTF"))
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)
	for category in range(3):
		var row := HBoxContainer.new()
		add_child(row)
		var swatch := ColorRect.new()
		swatch.color = [Color("dc6464"), Color("5e91ca"), Color("64bd8b")][category]
		swatch.custom_minimum_size = Vector2(10, 10)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var count := Label.new()
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		count.add_theme_font_size_override("font_size", 10)
		row.add_child(count)
		material_labels.append(count)
		var buy := Button.new()
		buy.text = "+1 · %d CR" % GameState.MATERIAL_PRICES[category]
		_style_action(buy)
		buy.pressed.connect(func() -> void: GameState.purchase_material(category))
		row.add_child(buy)
		buy_buttons.append(buy)
	add_child(HSeparator.new())
	construction_cost.add_theme_font_size_override("font_size", 9)
	construction_cost.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(construction_cost)
	construct.text = "CONSTRUCT"
	_style_action(construct)
	construct.size_flags_horizontal = Control.SIZE_SHRINK_END
	construct.pressed.connect(func() -> void:
		if fleet_panel != null:
			GameState.purchase_saved_ship(fleet_panel.selected_title))
	add_child(construct)
	add_child(HSeparator.new())
	repair_name.add_theme_font_size_override("font_size", 9)
	repair_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(repair_name)
	_style_action(repair)
	repair.size_flags_horizontal = Control.SIZE_SHRINK_END
	repair.pressed.connect(func() -> void:
		if fleet_panel != null and fleet_panel.board.selected != null:
			GameState.repair_ship(fleet_panel.board.selected))
	add_child(repair)
	for event in [GameState.credits_changed, GameState.tile_inventory_changed, GameState.fleet_changed, GameState.build_area_changed]:
		event.connect(refresh)

func bind_fleet(panel: Control) -> void:
	fleet_panel = panel
	panel.selected_design_changed.connect(refresh)
	panel.selected_ship_changed.connect(refresh)
	refresh()

func _style_action(button: Button) -> void:
	UI.compact_button(button)
	button.custom_minimum_size = Vector2(108, 30)
	button.add_theme_font_size_override("font_size", 9)

func refresh() -> void:
	for category in range(3):
		material_labels[category].text = "%s  %d" % [["Red", "Blue", "Green"][category], GameState.get_available_tile_count(category)]
		buy_buttons[category].disabled = GameState.battle_pending or GameState.credits < GameState.MATERIAL_PRICES[category]
	var design: Ship = fleet_panel.selected_design if fleet_panel != null else null
	construct.disabled = design == null
	construction_cost.text = "Select a saved design"
	construct.tooltip_text = ""
	if design != null:
		var counts := GameState._get_ship_tile_counts(design)
		construction_cost.text = "%d cr · %dR %dB %dG" % [design.cost, counts[0], counts[1], counts[2]]
		construct.tooltip_text = GameState.construction_error(design)
		construct.disabled = not construct.tooltip_text.is_empty()
	var owned: FleetShip = fleet_panel.board.selected if fleet_panel != null else null
	repair_name.text = "No ship selected"
	repair.text = "REPAIR"
	repair.disabled = true
	if owned != null:
		var hp := 0.0
		var max_hp := 0.0
		for unit in owned.units:
			hp += unit.hp
			max_hp += unit.max_hp
		repair_name.text = "%s · %d%% hull" % [owned.display_name, roundi(hp / maxf(max_hp, 1) * 100)]
		var price := owned.repair_cost()
		repair.text = "REPAIR · %d CR" % price
		repair.disabled = GameState.battle_pending or price == 0 or price > GameState.credits
