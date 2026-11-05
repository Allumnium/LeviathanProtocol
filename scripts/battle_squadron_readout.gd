extends VBoxContainer

var simulation: BattleSimulation
var enemies := false
var rows: Dictionary = {}
var refresh_remaining := 0.0
var column: VBoxContainer
var registered: Dictionary = {}

func _ready() -> void:
	name = "EnemyReadout" if enemies else "SquadronReadout"
	var heading := Label.new()
	heading.text = "ENEMIES" if enemies else "ALLIES"
	heading.theme_type_variation = &"ResearchDescriptionText"
	add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(column)
	refresh()

func _register(actor: BattleSimulation.Combatant) -> void:
	if registered.has(actor.entity_id):
		return
	if enemies and simulation.visibility_enabled and not simulation.team_can_see(0, actor):
		return
	var key: Variant
	var title: String
	if enemies:
		if actor.alien == null:
			return
		key = actor.squadron_id if not actor.squadron_id.is_empty() else actor.entity_id
		title = actor.alien.display_name
	elif actor.owned_ship is HangarShip:
		var ship: HangarShip = actor.owned_ship
		key = ship.squadron_id if ship.squadron_id > 0 else -ship.id
		title = "%s #%d" % [ship.chassis.name, ship.squadron_id] if ship.squadron_id > 0 else ship.display_name
	else:
		key = actor.entity_id
		title = actor.owned_ship.display_name if actor.owned_ship != null else "Allied craft"
	registered[actor.entity_id] = true
	if not rows.has(key):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		column.add_child(box)
		var label := ResourceText.create("")
		label.theme_type_variation = &"ResearchDescriptionText"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
		rows[key] = {"actors": [], "label": label, "hull": meter(box), "shields": meter(box, true),
			"name": title, "box": box}
	rows[key].actors.append(actor)

func meter(parent: Control, shield := false) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	preload("res://scripts/integrity_bars.gd").configure(bar, shield)
	parent.add_child(bar)
	return bar

func _process(delta: float) -> void:
	refresh_remaining -= delta
	if refresh_remaining <= 0:
		refresh_remaining = 0.1
		refresh()

func refresh() -> void:
	if simulation == null or column == null:
		return
	var faction := BattleSimulation.Faction.ALIEN if enemies else BattleSimulation.Faction.PLAYER
	for actor: BattleSimulation.Combatant in simulation._members:
		if actor.faction == faction and actor.has_tag("combatant"):
			_register(actor)
	for row: Dictionary in rows.values():
		var living := 0
		var total := 0
		var hull := 0.0
		var hull_max := 0.0
		var shields := 0.0
		var shields_max := 0.0
		for actor: BattleSimulation.Combatant in row.actors:
			if enemies and simulation.visibility_enabled and not simulation.team_can_see(0, actor):
				continue
			total += 1
			hull_max += actor.owned_ship.hull_max if actor.owned_ship is HangarShip else actor.stats.integrity
			shields_max += actor.stats.shields
			if actor.is_alive():
				living += 1
				hull += maxf(0, actor.owned_ship.hull_hp if actor.owned_ship is HangarShip else actor.integrity)
				shields += actor.shields
		row.box.visible = total > 0
		var text := "%s  %d/%d" % [row.name, living, total]
		if row.label.source_text != text:
			row.label.set_content(text)
		row.hull.max_value = maxf(1, hull_max)
		row.hull.value = hull
		row.shields.visible = shields_max > 0
		row.shields.max_value = maxf(1, shields_max)
		row.shields.value = shields
