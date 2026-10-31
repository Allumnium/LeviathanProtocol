extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	geometry_checks()
	recipe_checks()
	chassis_checks()
	design_checks()
	damage_checks()
	fleet_checks()
	matcher_checks()
	library_checks()
	print("Hex chassis: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func geometry_checks() -> void:
	for q in range(-10, 11):
		for r in range(-10, 11):
			var cell := Vector2i(q, r)
			check(HexGrid.at_point(HexGrid.center(cell, 13), 13) == cell, "Hex picking round trips negative and positive axial cells.")
			for turns in range(6):
				check(HexGrid.transform(HexGrid.transform(cell, turns), -turns) == cell, "Six-way rotation is invertible.")
			check(HexGrid.transform(HexGrid.transform(cell, 0, true), 0, true) == cell, "Reflection is an involution.")
	for offset: Vector2i in HexGrid.NEIGHBORS:
		check(HexGrid.distance(offset) == 1, "All six neighbors share an edge.")
		check(is_equal_approx(HexGrid.center(offset, 1).length(), sqrt(3.0)), "All six neighbor centers are equally spaced.")
	var pair: Array[Vector2i] = [Vector2i.ZERO, Vector2i.RIGHT]
	var outlines := HexGrid.boundaries(pair, 1)
	check(outlines.size() == 1 and outlines[0].size() == 10, "Adjacent hexes cancel only the shared edge.")
	var ring: Array[Vector2i] = []
	ring.assign(HexGrid.NEIGHBORS)
	check(HexGrid.boundaries(ring, 1).size() == 2, "A hole retains its inner boundary.")
	check(not HexGrid.connected([Vector2i.ZERO, Vector2i(2, 0)]), "Disconnected outline is invalid.")
	check(not HexGrid.connected([Vector2i.ZERO, Vector2i.ZERO]), "Duplicate outline cells are invalid.")
	check(is_equal_approx(HexGrid.ray_distance(Vector2i.ZERO, Vector2(-10, 0), Vector2.RIGHT, 1), 10 - sqrt(3.0) / 2), "Hit testing uses actual hex edges.")
	check(HexGrid.ray_distance(Vector2i.ZERO, Vector2(-10, 2), Vector2.RIGHT, 1) == INF, "A ray above the hex misses.")
	check(HexGrid.at_point(Vector2(0.86, 0.9), 1) != Vector2i.ZERO, "Picking rejects the empty corner of a square hex bounding box.")

func recipe_checks() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(HexRecipe.DATA_PATH))
	check(HexRecipe.validate(data).is_empty(), "All explicit hex recipes are connected and unambiguous except legal branch alternatives: %s" % str(HexRecipe.validate(data)))
	check(HexRecipe.catalog().size() == 58, "Every equipment/rank has a hex recipe.")
	var cabin := HexRecipe.find("passenger_cabin")
	check(cabin.cells.size() == 6 and cabin.cells.all(func(item: Array) -> bool: return item[2] == 3), "Cabin keeps all six Civic materials.")
	var sample := HexRecipe.find("research_lab", 2)
	var canonical := HexRecipe.signature(HexRecipe.cells(sample))
	for turn in range(6):
		for flip in [false, true]:
			check(HexRecipe.signature(HexRecipe.cells(sample, turn, flip, Vector2i(-6, 7))) == canonical, "Recipe identity is independent of all twelve hex orientations and translation.")
	var invalid: Dictionary = data.duplicate(true)
	invalid.recipes[0].cells.append(invalid.recipes[0].cells[0].duplicate())
	check(not HexRecipe.validate(invalid).is_empty(), "Duplicate recipe cells are rejected.")

func chassis_checks() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ChassisCatalog.DATA_PATH))
	check(ChassisCatalog.validate(data).is_empty(), "All five chassis satisfy masks, CC, command and gap rules: %s" % str(ChassisCatalog.validate(data)))
	check(data.chassis.size() == 5, "There are five initial chassis prototypes.")
	var invalid: Dictionary = data.chassis[1].duplicate(true)
	invalid.regions[1].cells = [[2, -1]]
	check(not ChassisDefinition.validate(invalid).is_empty(), "Touching regions are rejected even when they do not overlap.")
	invalid = data.chassis[0].duplicate(true)
	invalid.hull.append([200, 200])
	check(not ChassisDefinition.validate(invalid).is_empty(), "Disconnected chassis geometry cannot load.")
	invalid = data.chassis[0].duplicate(true)
	invalid.regions[0].modifiers.weapon_range = INF
	check(not ChassisDefinition.validate(invalid).is_empty(), "Nonfinite region bonuses are rejected.")
	var chassis := ChassisCatalog.find("vanguard")
	check(chassis.flagship and chassis.command_points > 0 and chassis.command_cost == 0, "Flagship supplies command points.")
	check(chassis.region_for([Vector2i(-2, 0), Vector2i(0, 0)]).is_empty(), "A component cannot span two regions.")
	chassis.hull.clear()
	check(not ChassisCatalog.find("vanguard").hull.is_empty(), "Mutating a returned definition cannot alter canonical geometry.")

func design_checks() -> void:
	var design := HexShipDesign.new()
	check(design.initialize("vanguard"), "Create a chassis design.")
	check(not design.set_tile(Vector2i(-1, 0), 0), "Gap structure cannot accept material.")
	check(not design.set_tile(Vector2i(-1, 3), 0), "Built-in command center cannot be overwritten.")
	check(not design.set_tile(Vector2i(200, 0), 0), "Construction cannot expand the chassis.")
	var recipe := HexRecipe.find("research_lab")
	for turns in range(6):
		for flip in [false, true]:
			var current := HexShipDesign.new()
			current.initialize("vanguard")
			var anchor := Vector2i.ZERO
			for q in range(0, 5):
				for r in range(-2, 3):
					var candidate := HexRecipe.cells(recipe, turns, flip, Vector2i(q, r))
					var footprint: Array[Vector2i] = []
					footprint.assign(candidate.keys())
					if not current.chassis().region_for(footprint).is_empty():
						anchor = Vector2i(q, r)
			var layout := HexRecipe.cells(recipe, turns, flip, anchor)
			for cell: Vector2i in layout:
				check(current.set_tile(cell, layout[cell]), "Recipe fits within a flagship region in every orientation.")
			check(current.fit("research_lab", 1, anchor, turns, flip), "Fit hex equipment by its explicit identity.")
			check(not current.fit("research_lab", 1, anchor, turns, flip), "Equipment cannot overlap an existing component.")
			var copy := HexShipDesign.new()
			check(copy.load_data(JSON.parse_string(JSON.stringify(current.to_data()))), "Every orientation round-trips through JSON.")
			check(copy.to_data() == current.to_data(), "Loading retains recipe identity, rank, reflection and six-way orientation.")
			var bad := current.to_data()
			bad.tiles.append([200, 0, 0])
			check(not copy.load_data(bad) and copy.to_data() == current.to_data(), "Failed design load is atomic.")
			check(copy.remove_tile(layout.keys()[0]) and copy.components.is_empty(), "Removing one constituent dissolves only the fitted component.")
	var square := Ship.new()
	var before := square.to_design_data()
	check(not design.load_data(before) and not square.load_design_data(design.to_data()), "Hex and legacy square formats cannot silently reinterpret each other.")

func damage_checks() -> void:
	var design := HexShipDesign.new()
	design.initialize("vanguard")
	var state := HexShipState.new()
	check(state.initialize(design), "Construct immutable physical chassis state.")
	var engine := Vector2i(-8, 0)
	var index := state.component_at(engine)
	var hp: float = state.units[index].hp
	state.damage_cell(engine, 2)
	check(state.chassis_integrity == state.max_chassis_integrity - 1 and state.units[index].hp == hp - 1, "Equipment hit splits equally between component and chassis.")
	var bare := Vector2i(-1, 0)
	state.damage_cell(bare, 3)
	check(state.chassis_integrity == state.max_chassis_integrity - 4, "Bare structural hex takes full hull damage.")
	check(state.has_cell(engine) and state.has_cell(bare), "Damage leaves the entire chassis outline intact.")
	state.chassis_integrity = 0
	check(state.is_alive(), "Zero chassis integrity is alive, as requested.")
	var copy := HexShipState.new()
	check(copy.load_data(JSON.parse_string(JSON.stringify(state.to_data()))) and copy.is_alive(), "Zero integrity and component HP survive reload.")
	copy.damage_cell(bare, 0.01)
	check(not copy.is_alive() and not copy.has_cell(engine), "Below zero breaks the whole chassis at once.")
	check(copy.repair_chassis(100) == 0 and not copy.is_alive(), "Ordinary repair cannot resurrect a broken chassis.")
	state.chassis_integrity = state.max_chassis_integrity
	state.damage_cell(Vector2i(-1, 3), 100)
	check(not state.is_alive() and state.chassis_integrity > 0, "Destroying the fixed command center kills an otherwise intact chassis.")
	var old := copy.to_data()
	var bad := old.duplicate(true)
	bad.health[0].hp = INF
	check(not copy.load_data(bad) and copy.to_data() == old, "Malformed physical health cannot partially mutate live state.")

func fleet_checks() -> void:
	var fleet := HexFleet.new()
	var escort := HexShipDesign.new()
	escort.initialize("wren")
	check(fleet.construct(escort) == 0, "A non-flagship cannot start a fleet.")
	var flagship := HexShipDesign.new()
	flagship.initialize("vanguard")
	var flag_id := fleet.construct(flagship)
	check(flag_id > 0 and not fleet.defeated(), "The first flagship establishes a valid fleet.")
	check(fleet.construct(flagship) == 0, "A second physical flagship is prohibited.")
	for index in range(6):
		check(fleet.construct(escort) > 0, "Fleet size is not constrained by the old three-slot model.")
	check(fleet.command_used() == 12 and fleet.construct(escort) == 0, "Command costs come from chassis and cannot exceed flagship points.")
	check(not fleet.salvage(flag_id), "The mandatory flagship cannot be salvaged.")
	var upgraded := HexShipDesign.new()
	upgraded.initialize("ark")
	check(fleet.replace_flagship(upgraded) and fleet.flagship_id() == flag_id and fleet.command_points() == 16, "Flagship replacement is atomic and retains physical fleet identity.")
	check(fleet.construct(escort) > 0 and fleet.construct(escort) > 0, "Additional command points support more ships.")
	var before := fleet.to_data()
	check(not fleet.replace_flagship(flagship) and fleet.to_data() == before, "A smaller flagship cannot strand the existing fleet above its command budget.")
	var copy := HexFleet.new()
	check(copy.load_data(JSON.parse_string(JSON.stringify(before))) and copy.command_used() == 16 and copy.ships.size() == 9, "Unlimited fleet and its single flagship survive JSON reload.")
	var corrupt := before.duplicate(true)
	corrupt.ships.append(corrupt.ships[0].duplicate(true))
	check(not copy.load_data(corrupt) and copy.to_data() == before, "Duplicate physical ship identities cannot load and leave fleet unchanged.")
	fleet.ships[flag_id].damage_cell(Vector2i(0, 0), 10000)
	check(fleet.defeated() and not fleet.replace_flagship(upgraded), "Flagship destruction ends the fleet and cannot be undone by replacement.")

func matcher_checks() -> void:
	var matcher := HexRecipeMatcher.new(ShipPartPattern.get_catalog())
	for turns in range(6):
		for flipped in [false, true]:
			var design := HexShipDesign.new()
			design.initialize("vanguard")
			var recipe := HexRecipe.find("research_lab", 2)
			var layout := {}
			for q in range(0, 5):
				for r in range(-2, 3):
					var candidate := HexRecipe.cells(recipe, turns, flipped, Vector2i(q, r))
					var footprint: Array[Vector2i] = []
					footprint.assign(candidate.keys())
					if not design.region_for(footprint).is_empty():
						layout = candidate
			check(not layout.is_empty(), "Each rank-II lab orientation fits a flagship region.")
			for cell: Vector2i in layout:
				design.set_tile(cell, layout[cell])
				matcher.assemble_unique(design, cell)
			check(design.components.any(func(component: Dictionary) -> bool: return component.equipment_id == "research_lab" and component.rank == 2), "Local matcher finds the exact rotated/reflected ranked recipe and upgrades whole smaller components.")
	var ambiguous := HexShipDesign.new()
	ambiguous.initialize("vanguard")
	var alternatives: Array[Dictionary] = []
	for cell: Vector2i in HexRecipe.cells(HexRecipe.find("focusing_lens")):
		ambiguous.set_tile(cell, HexRecipe.cells(HexRecipe.find("focusing_lens"))[cell])
		alternatives = matcher.assemble_unique(ambiguous, cell)
	check(alternatives.any(func(item: Dictionary) -> bool: return item.equipment_id == "ion_emitter") and alternatives.any(func(item: Dictionary) -> bool: return item.equipment_id == "focusing_lens"), "Shared branch recipes require an explicit equipment choice instead of arbitrary auto assembly.")
	check(not ambiguous.components.any(func(component: Dictionary) -> bool: return component.equipment_id in ["focusing_lens", "ion_emitter"]), "Ambiguous branch identity is never chosen implicitly.")
	var before := ambiguous.to_data()
	check(not ambiguous.assemble("laser", 1, Vector2i.ZERO) and ambiguous.to_data() == before, "Failed replacement assembly preserves all existing component identities.")

func library_checks() -> void:
	var library := HexDesignLibrary.new()
	library.path = "user://hex_library_model/%d.json" % Time.get_ticks_usec()
	check(library.load_library(), "A fresh hex archive loads empty without touching legacy paths.")
	var design := HexShipDesign.new()
	design.initialize("wren")
	check(library.save_design("Wren", design), "Atomic archive write saves a valid versioned design.")
	var stale := HexDesignLibrary.new()
	stale.path = library.path
	check(stale.load_library(), "A second archive reader loads the current generation.")
	check(library.save_design("Second", design), "Multiple designs are independent named entries, not limited slots.")
	check(not stale.save_design("Stale", design) and not stale.designs.has("Stale"), "Concurrent stale saves fail without mutating archive memory or dropping newer designs.")
	var restored := HexDesignLibrary.new()
	restored.path = library.path
	check(restored.load_library() and restored.designs.size() == 2, "Both named designs persist after reload.")
	check(restored.get_design("Wren").to_data() == design.to_data(), "Library returns validated independent blueprint copies.")
	var corrupted := FileAccess.open(library.path, FileAccess.WRITE)
	corrupted.store_string("broken")
	corrupted.close()
	check(restored.load_library() and restored.designs.size() == 1, "A corrupt main archive recovers the last verified backup.")
	var bad := HexDesignLibrary.new()
	bad.path = "user://hex_library_model/corrupt-%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(bad.path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	check(not bad.save_design("Replacement", design) and FileAccess.get_file_as_string(bad.path) == "broken", "Unrecoverable archives cannot be silently overwritten as an empty library.")
