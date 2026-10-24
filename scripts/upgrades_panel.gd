extends VBoxContainer

const CREDIT_ICON: Texture2D = preload("res://assets/ui/icons/credits.svg")

var label := Label.new()
var purchase := Button.new()
var build_label := Label.new()
var build_purchase := Button.new()

func _ready() -> void:
	add_child(label)
	label.add_theme_font_size_override("font_size", 11)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(purchase)
	purchase.add_theme_font_size_override("font_size", 11)
	preload("res://scripts/fleet_panel.gd").compact_button(purchase)
	purchase.icon = CREDIT_ICON
	purchase.pressed.connect(func() -> void: GameState.purchase_laser_upgrade())
	build_label.add_theme_font_size_override("font_size", 11)
	add_child(build_label)
	build_purchase.add_theme_font_size_override("font_size", 10)
	preload("res://scripts/fleet_panel.gd").compact_button(build_purchase)
	build_purchase.icon = CREDIT_ICON
	build_purchase.pressed.connect(func() -> void: GameState.purchase_build_area_upgrade())
	add_child(build_purchase)
	GameState.upgrades_changed.connect(_refresh)
	GameState.credits_changed.connect(_refresh)
	GameState.tile_inventory_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var side := GameState.build_area_size()
	build_label.text = "BUILD AREA %d X %d" % [side, side]
	build_purchase.text = "%d X %d - 1R 1B 1G 1C / 50" % [side + 2, side + 2]
	build_purchase.disabled = side >= GameState.MAX_BUILD_SIZE or GameState.credits < 50 or GameState.red_tiles_available < 1 or GameState.blue_tiles_available < 1 or GameState.green_tiles_available < 1 or GameState.core_tiles_available < 1
	if side >= GameState.MAX_BUILD_SIZE:
		build_purchase.text = "MAX"
	var level := GameState.laser_upgrade_level
	label.text = "LASERS %d/3 · +%d%% DAMAGE & RATE" % [level, level * 10]
	if level >= 3:
		purchase.text = "MAX"
		purchase.disabled = true
		return
	var red: int = [3, 7, 15][level]
	var credits: int = [20, 50, 100][level]
	purchase.text = "UPGRADE · %dR / %d" % [red, credits]
	purchase.disabled = GameState.red_tiles_available < red or GameState.credits < credits
