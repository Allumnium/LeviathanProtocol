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
	var detached_list := ShipPartPattern.get_catalog()
	detached_list.clear()
	_check(ShipPartPattern.get_catalog().size() == catalog.size(), "Sorting/filtering a caller's catalog list cannot mutate the shared registry.")
	var laser: ShipPartPattern = catalog.filter(func(pattern: ShipPartPattern) -> bool: return pattern.part_type == ShipPart.Type.MINING_LASER)[0]
	var physical := ShipPart.new(laser.part_type, laser.category, Vector2i.ZERO, laser.cell_offsets, laser.stats)
	physical.stats.weapons[0].damage_per_shot = 999
	_check(laser.stats.weapons[0].damage_per_shot == 1.5, "Physical stat changes cannot mutate cached catalog templates.")
	_check(catalog.size() == 31, "Functional shared, mining and intermediate Energy/Survival equipment plus three lab ranks enter the catalog.")
	var numeric_ids: Array[int] = []
	for definition in GameDefinitions.entries("equipment"):
		var type_id := int(definition.type_id)
		_check(ShipPart.Type.values().has(type_id), "Definition IDs must be reserved in the equipment enum.")
		_check(ShipPart.Type.get(definition.enum_key) == type_id, "Definition identity must match its serialized enum ID.")
		_check(not numeric_ids.has(type_id), "Equipment IDs must be unique.")
		numeric_ids.append(type_id)
		var foundation_type := type_id in [0, 3, 4, 5, 6, 8, 9, 10, ShipPart.Type.CARGO_HOLD]
		_check(state.is_equipment_available(type_id) == foundation_type,
			"Only implemented Foundation equipment is authorized in a fresh run.")
	for pattern in catalog:
		_check(pattern.definition_id == GameDefinitions.equipment(pattern.part_type).id,
			"Live patterns must reference a stable definition.")
	_check(GameDefinitions.entries("research", true).size() == 18, "Shared research, mining, lab ranks and Energy/Survival intermediates are ready.")
	_check(GameDefinitions.entries("abilities", true).size() == 4 and GameDefinitions.find("abilities", "scan").implemented
		and GameDefinitions.find("abilities", "seismic_cut").implemented
		and GameDefinitions.find("abilities", "ion_pulse").implemented and GameDefinitions.find("abilities", "gravity_well").implemented,
		"Scan, Cutter and Disruption controls are ready; future abilities remain gated.")

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
		for part: Dictionary in round_trip.parts:
			for metadata in ["definition_id", "rank", "quarter_turns", "horizontally_flipped"]:
				part.erase(metadata)
		_check(round_trip == fixture, "Legacy IDs/materials/transforms must round-trip unchanged.")
	print("Definition tests finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
