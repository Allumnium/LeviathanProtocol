extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var registry := GameDefinitions.snapshot()
	_check(GameDefinitions.validate(registry).is_empty(), "Definition registry must validate.")
	if registry.is_empty():
		quit(1)
		return
	_check(GameDefinitions.entries("equipment").size() == 56, "Reserve all 56 stable equipment IDs.")
	_check(GameDefinitions.entries("research").size() == 46, "Define Foundation and 45 research purchases.")
	_check(GameDefinitions.entries("abilities").size() == 20, "Define all 20 abilities.")
	var legacy_names := ["ARMOR_BLOCK", "LASER", "DOUBLE_LASER", "SINGLE_PLATE", "SHIELD",
		"MINI_TURRET", "THRUSTER", "LARGE_THRUSTER", "COMMAND_CENTER"]
	for type_id in range(legacy_names.size()):
		_check(ShipPart.Type[legacy_names[type_id]] == type_id, "Legacy equipment ID must not move.")
	_check(ShipPart.Category.values() == [0, 1, 2, 3], "Material enum values must not move or duplicate.")
	_check(ShipPart.TechCategory.values() == [0, 1, 2], "Legacy technology IDs must not move.")
	_check(GameDefinitions.material_name(3) == "Civic", "Purple material must display as Civic.")
	_check(GameDefinitions.material_name(2) == "Tech", "Legacy SPECIAL material must display as Tech.")
	var tree_script := load("res://scripts/upgrades_panel.gd")
	var tech_tree: Control = tree_script.new()
	_check(tech_tree._category_name(0) == "FOUNDATION", "Starting technology must display as Foundation.")
	tech_tree.free()

	var state := root.get_node("GameState")
	var catalog := ShipPartPattern.get_catalog()
	_check(catalog.size() == 9, "Only the nine working legacy patterns may enter the live catalog.")
	var numeric_ids: Array[int] = []
	for definition in GameDefinitions.entries("equipment"):
		var type_id := int(definition.type_id)
		_check(ShipPart.Type.values().has(type_id), "Definition IDs must be reserved in the equipment enum.")
		_check(ShipPart.Type.get(definition.enum_key) == type_id, "Definition identity must match its serialized enum ID.")
		_check(not numeric_ids.has(type_id), "Equipment IDs must be unique.")
		numeric_ids.append(type_id)
		_check(state.is_equipment_available(type_id) == (type_id < 9),
			"Planned equipment must remain unavailable to the builder.")
	for pattern in catalog:
		_check(pattern.definition_id == GameDefinitions.equipment(pattern.part_type).id,
			"Live patterns must reference a stable definition.")
	_check(GameDefinitions.entries("research", true).is_empty(), "Research purchases must remain gated.")
	_check(GameDefinitions.entries("abilities", true).is_empty(), "Planned abilities must remain gated.")

	var energy := GameDefinitions.find("research", "applied_energy")
	_check(energy.grants.equipment_ids == ["laser", "double_laser"], "Research must support multiple equipment grants.")
	var concept := GameDefinitions.find("research", "energy_manipulation")
	_check(concept.grants.equipment_ids.is_empty() and concept.grants.modifiers.size() == 1,
		"Concept research must support modifiers without an equipment grant.")
	_check(GameDefinitions.find("research", "laboratory_iii").story_gate_ids == ["boss_i_defeated"],
		"Lab III must retain its story gate.")
	_check(GameDefinitions.find("research", "optics_i").exclusion_ids.has("disruption_iii"),
		"Branch commitment must describe downstream exclusions.")
	_check(GameDefinitions.find("goods", "basic").unit_value == 3,
		"Basic goods must retain origin value three.")
	_check(GameDefinitions.find("goods", "rare").settlement_order == ["sell", "refill"],
		"Goods must declare sell-before-refill settlement.")
	_check(GameDefinitions.find("abilities", "scan").range_units == 450,
		"Foundation Scan must preserve its specified range.")
	_check(GameDefinitions.equipment(51).regular_slots_only, "Mining definitions must restrict dedicated support slots.")

	# Mutating a caller's snapshot must not change authoritative definitions.
	energy.grants.equipment_ids.clear()
	_check(GameDefinitions.find("research", "applied_energy").grants.equipment_ids.size() == 2,
		"Definition access must return independent deep copies.")
	var invalid := registry.duplicate(true)
	invalid.schema_version = 999
	_check(not GameDefinitions.validate(invalid).is_empty(), "Reject unsupported definition schemas.")
	invalid = registry.duplicate(true)
	invalid.equipment.append(invalid.equipment[0].duplicate(true))
	_check(not GameDefinitions.validate(invalid).is_empty(), "Reject duplicate stable IDs.")
	invalid = registry.duplicate(true)
	invalid.research[0].grants.equipment_ids.append("missing_component")
	_check(not GameDefinitions.validate(invalid).is_empty(), "Reject dangling research grants.")
	invalid = registry.duplicate(true)
	invalid.research[0].grants.ranks = null
	_check(not GameDefinitions.validate(invalid).is_empty(), "Reject malformed grant lists without crashing.")
	invalid = registry.duplicate(true)
	invalid.goods[0].unit_value = "three"
	_check(not GameDefinitions.validate(invalid).is_empty(), "Reject malformed goods properties.")

	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_blueprints_v1.json"))
	for fixture: Dictionary in fixtures:
		var ship := Ship.new()
		_check(ship.load_design_data(fixture), "Unversioned legacy blueprints must still load.")
		var round_trip: Variant = JSON.parse_string(JSON.stringify(ship.to_design_data()))
		_check(round_trip == fixture, "Legacy IDs/materials/transforms must round-trip unchanged.")
	print("Definition tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
