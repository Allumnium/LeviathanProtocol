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

func blueprint(id: String) -> HexShipDesign:
	var design := HexShipDesign.new()
	check(design.initialize(id), "Initialize chassis " + id)
	return design

func fit(design: HexShipDesign, equipment: String, turns := 0, flipped := false) -> bool:
	var recipe := HexRecipe.find(equipment, 1)
	for region in design.chassis().regions:
		for origin: Vector2i in region.cells:
			var layout := HexRecipe.cells(recipe, turns, flipped, origin)
			var cells: Array[Vector2i] = []
			cells.assign(layout.keys())
			if design.region_for(cells).is_empty():
				continue
			var overlap := false
			for cell: Vector2i in layout:
				overlap = overlap or design.tiles.has(cell)
			if overlap:
				continue
			for cell: Vector2i in layout:
				design.set_tile(cell, layout[cell])
			return design.fit(equipment, 1, origin, turns, flipped)
	return false

func enemies() -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for alien in AlienShip.create_random_fleet(2, 1.0, 94):
		result.append(alien)
	return result

func fleet() -> HexFleet:
	var result := HexFleet.new()
	var flag := blueprint("vanguard")
	check(fit(flag, "laser"), "Fit flagship weapon within one region.")
	check(result.construct(flag) == 1, "Construct flagship.")
	var escort := blueprint("wren")
	check(fit(escort, "laser"), "Fit escort weapon.")
	check(result.construct(escort) == 2, "Construct escort.")
	return result

func run() -> void:
	# All twelve recipe transforms keep behavior; no turns become weapon facing.
	var reference: ShipStats
	for turns in range(6):
		for flipped in [false, true]:
			var design := blueprint("vanguard")
			check(fit(design, "laser", turns, flipped), "A rotated/reflected laser fits a region.")
			var ship := HexBattleShip.new()
			check(ship.initialize_hex(design, 1, "Orientation test"), "Bind hex equipment to combat.")
			var stats := ship.get_stats()
			if reference == null:
				reference = stats
			check(is_equal_approx(stats.dps, reference.dps) and is_equal_approx(stats.thrust, reference.thrust), "Recipe transform never changes DPS or thrust.")
			check(is_equal_approx(stats.weapons[0].range_units, reference.weapons[0].range_units), "Range bonus is independent of recipe facing.")
			var fitted: Dictionary = ship.units.filter(func(unit: Dictionary) -> bool: return unit.equipment_id == "laser")[0]
			var pattern := ShipPartPattern.get_catalog().filter(func(item: ShipPartPattern) -> bool: return item.definition_id == "laser" and item.rank == 1)[0] as ShipPartPattern
			check(is_equal_approx(stats.weapons[0].range_units, pattern.stats.weapons[0].range_units * (1 + fitted.modifiers.weapon_range)), "Chassis range bonus is applied once.")
			check(fitted.part.hex_cells and fitted.part.quarter_turns == 0, "Footprint transforms carry no functional rotation.")
			check(fitted.part.facing(pattern) == Vector2i.ZERO, "Hex equipment exposes no firing or exhaust direction.")
			var mount := Vector2.ZERO
			for cell: Vector2i in fitted.cells:
				mount += ship.local_cell_position(cell)
			check(stats.weapons[0].mount_offset.is_equal_approx(mount / fitted.cells.size()), "Weapon mount uses flat hex positions.")
	# Six neighbors, without introducing square diagonals or mixed-topology links.
	var source := ShipPart.new(ShipPart.Type.CREW_QUARTERS, 3, Vector2i.ZERO, [Vector2i.ZERO], ShipPartStats.new())
	source.hex_cells = true
	for offset in HexGrid.NEIGHBORS:
		var target := ShipPart.new(ShipPart.Type.LASER, 0, offset, [Vector2i.ZERO], ShipPartStats.new())
		target.hex_cells = true
		check(AdjacencyRules.touches(source, target), "Every hex edge counts as adjacency.")
		target.hex_cells = false
		check(not AdjacencyRules.touches(source, target), "Mixed topologies never share adjacency.")
	var diagonal := ShipPart.new(ShipPart.Type.LASER, 0, Vector2i.ONE, [Vector2i.ZERO], ShipPartStats.new())
	diagonal.hex_cells = true
	check(not AdjacencyRules.touches(source, diagonal), "Axial (1,1) is not adjacent.")
	# Armor region efficiency affects component HP, never the whole chassis pool.
	var armored := blueprint("vanguard")
	check(fit(armored, "armor_block"), "Fit armor in a construction region.")
	var armor_ship := HexBattleShip.new()
	check(armor_ship.initialize_hex(armored, 1, "Armor"), "Bind regional armor.")
	var armor: Dictionary = armor_ship.units.filter(func(unit: Dictionary) -> bool: return unit.equipment_id == "armor_block" and not unit.builtin)[0]
	check(is_equal_approx(armor.max_hp, ShipStats.component_integrity(armor.cells.size(), armor.part) * (1 + armor.modifiers.armor_integrity)), "Armor integrity bonus applies once to equipment HP.")
	check(armor_ship.state.chassis_integrity == armored.chassis().integrity, "Armor region does not inflate chassis HP.")
	var support_design := blueprint("vanguard")
	for equipment in ["repair_station", "laser", "crew_quarters", "research_lab"]:
		check(fit(support_design, equipment), "Fit hex support component: " + equipment)
	var support_ship := HexBattleShip.new()
	check(support_ship.initialize_hex(support_design, 1, "Support"), "Bind real support equipment.")
	var support_sim := BattleSimulation.new()
	check(support_sim.setup_owned([support_ship], enemies(), 0.3, 0, 50), "Shared support accepts hex units.")
	var station_index := -1
	for index in range(support_ship.units.size()):
		if support_ship.units[index].equipment_id == "repair_station":
			station_index = index
	var recipient := -1
	for index in range(support_ship.units.size()):
		var part: ShipPart = support_ship.units[index].part
		if part != null and AdjacencyRules.touches(support_ship.units[station_index].part, part):
			recipient = index
			break
	check(recipient >= 0, "Repair station has a real hex-adjacent recipient.")
	if recipient >= 0:
		var target_unit := support_ship.units[recipient]
		target_unit.hp -= 0.5
		var damaged: float = target_unit.hp
		var structural_hp := support_ship.state.chassis_integrity
		SharedSupport.repair(support_sim, 1.0)
		check(target_unit.hp > damaged and support_sim.repair_spent > 0, "Shared finite repair pool repairs physical hex equipment.")
		check(support_ship.state.chassis_integrity == structural_hp, "Equipment repair does not fabricate chassis repair.")
	check(ScienceRules.active_lab(support_ship) >= 0, "Living hex lab participates in existing science rules.")
	var owned := fleet()
	var ships := owned.battle_ships()
	check(ships.size() == 2 and ships[0].is_flagship(), "All owned living ships deploy with flagship.")
	var flagship := ships[0] as HexBattleShip
	check(flagship.state == owned.ships[1], "Combat shares persistent physical ship health.")
	check(not Ship.new().load_design_data(flagship.design.to_design_data()), "Runtime design cannot leak into square save loader.")
	var core := flagship.units[flagship.core_index]
	var hp: float = core.hp
	var hull_hp := flagship.state.chassis_integrity
	var result := flagship.damage_cell(core.cells[0], 2)
	check(is_equal_approx(core.hp, hp - 1) and is_equal_approx(flagship.state.chassis_integrity, hull_hp - 1) and result.damage == 2, "Equipment hit splits damage evenly.")
	var bare := Vector2i.ZERO
	for cell in flagship.hull_cells:
		if flagship.state.component_at(cell) < 0:
			bare = cell
			break
	hull_hp = flagship.state.chassis_integrity
	flagship.damage_cell(bare, 3)
	check(flagship.state.chassis_integrity == hull_hp - 3, "Bare chassis takes full damage.")
	var radius := flagship.get_stats().collision_radius
	var random := RandomNumberGenerator.new()
	random.seed = 485
	for angle in range(36):
		var origin := Vector2.RIGHT.rotated(angle * TAU / 36) * 200
		var hit := flagship.hit_cell(origin, random)
		check(flagship.has_cell(hit), "Ray hits a real hull hex from every approach.")
		var ray := (flagship.local_cell_position(hit) - origin).normalized()
		var distance := flagship._ray_distance(origin, ray, hit)
		check(is_finite(distance), "Hit intersects flat hex polygon.")
		for blocker in flagship.hull_cells:
			check(flagship._ray_distance(origin, ray, blocker) >= distance - 0.001, "Scatter never selects an occluded hex.")
	# Destroy equipment, reconstruct hardware, retain the lost-content latch.
	var weapon: Dictionary = flagship.units.filter(func(unit: Dictionary) -> bool: return unit.equipment_id == "laser")[0]
	flagship.damage_cell(weapon.cells[0], weapon.hp * 2)
	check(weapon.hp == 0 and weapon.get("load_lost", false), "Destroyed equipment loses its contents.")
	check(flagship.has_cell(weapon.cells[0]) and flagship.get_stats().collision_radius == radius, "Destroying equipment leaves the fixed chassis solid.")
	weapon.hp = weapon.max_hp * 0.25
	var restored := HexFleet.new()
	check(restored.load_data(JSON.parse_string(JSON.stringify(owned.to_data()))), "Damaged battle health persists in explicit hex fleet schema.")
	check(restored.ships[1].units.filter(func(unit: Dictionary) -> bool: return unit.equipment_id == "laser")[0].get("load_lost", false), "Reconstruction/reload cannot restore lost passengers or cargo.")
	# Chassis at exactly zero remains a valid combatant; strictly negative dies.
	flagship.state.chassis_integrity = 0
	var simulation := BattleSimulation.new()
	check(simulation.setup_owned(ships, enemies(), 0.3, 0, 119), "Battle accepts a living chassis at zero integrity.")
	check(simulation.players[0].is_alive() and simulation.players[0].integrity == 0, "Zero is alive without fabricated hull HP.")
	flagship.damage_cell(bare, 0.1)
	for alien in simulation.aliens:
		alien.integrity = 0
	simulation.advance(1.0 / 60)
	check(simulation.phase == BattleSimulation.Phase.DEFEAT and ships[1].is_alive(), "Flagship death beats simultaneous victory even with a living escort.")
	check(simulation.authoritative_snapshot().actors[0].hex.chassis_integrity < 0, "Replay diagnostics retain actual negative chassis HP and hex identity.")
	# Deployment guards reject reserve, duplicate flagship, missing flagship, command overflow.
	owned = fleet()
	ships = owned.battle_ships()
	check(not BattleSimulation.new().setup_owned([ships[1]], enemies(), 0.3, 0, 1), "No deployment without flagship.")
	check(not BattleSimulation.new().setup_owned([ships[0], ships[0]], enemies(), 0.3, 0, 1), "No duplicate physical flagship.")
	ships[1].in_reserve = true
	check(not BattleSimulation.new().setup_owned(ships, enemies(), 0.3, 0, 1), "Reserve state is rejected for hex fleets.")
	ships[1].in_reserve = false
	var legacy := FleetShip.new()
	check(not BattleSimulation.new().setup_owned([ships[0], legacy], enemies(), 0.3, 0, 1), "Mixed square/hex deployment is rejected.")
	var hit_sim := BattleSimulation.new()
	check(hit_sim.setup_owned(ships, enemies(), 1.0, 0, 52), "Start engine damage test.")
	check(hit_sim.players[0].position.distance_to(hit_sim.players[1].position) > hit_sim.players[0].radius + hit_sim.players[1].radius, "Hex formation spacing accommodates the flagship's larger hull.")
	var target := hit_sim.players[0]
	var physical := (target.owned_ship as HexBattleShip).state
	var previous_hp := physical.chassis_integrity
	target.shields = 5
	hit_sim._damage(target, 3, target.position + Vector2(200, 0))
	check(target.shields == 2 and physical.chassis_integrity == previous_hp, "Battle shields absorb damage before chassis/component split.")
	hit_sim._damage(target, 4, target.position + Vector2(200, 0))
	check(target.shields == 0 and physical.chassis_integrity < previous_hp, "Unshielded engine damage reaches shared chassis state.")
	# Core loss is lethal even with otherwise intact hull and live escorts.
	var flag_adapter := ships[0] as HexBattleShip
	var command: Dictionary = flag_adapter.units[flag_adapter.core_index]
	flag_adapter.damage_cell(command.cells[0], command.hp * 2)
	check(not target.is_alive() and physical.chassis_integrity > 0, "Command-center loss kills a positive-integrity chassis.")
	hit_sim.advance(1.0 / 60)
	check(hit_sim.phase == BattleSimulation.Phase.DEFEAT, "Command-center loss ends actual battle.")
	owned = fleet()
	ships = owned.battle_ships()
	var oversized: Array[FleetShip] = [ships[0]]
	for index in range(7):
		var escort := HexBattleShip.new()
		escort.initialize_hex(blueprint("wren"), index + 2, "Escort")
		oversized.append(escort)
	check(not BattleSimulation.new().setup_owned(oversized, enemies(), 0.3, 0, 1), "Command budget is enforced in actual battle setup.")
	# Deterministic engine integration, real movement/fire/damage, no model-only shortcut.
	var a := BattleSimulation.new()
	var b := BattleSimulation.new()
	check(a.setup_owned(fleet().battle_ships(), enemies(), 0.3, 0, 475), "Start hex skirmish A.")
	check(b.setup_owned(fleet().battle_ships(), enemies(), 0.3, 0, 475), "Start hex skirmish B.")
	for tick in range(3600):
		a.advance(1.0 / 60)
		b.advance(1.0 / 60)
		if a.phase != BattleSimulation.Phase.COMBAT:
			break
	check(a.phase == b.phase and a.authoritative_snapshot() == b.authoritative_snapshot(), "Seeded hex combat replays identically.")
	check(not a.event_log.is_empty(), "Real hex combat produces authoritative events.")
	check(a.players[0].position != BattleSimulation.PLAYER_FORMATION_CENTER, "Built-in thrusters propel the hull independent of recipe orientation.")
	check(a.players.any(func(member: BattleSimulation.Combatant) -> bool: return member.damage_dealt > 0) and a.players.any(func(member: BattleSimulation.Combatant) -> bool: return member.damage_taken > 0), "Hex skirmish exchanges real weapon damage in both directions.")
	await render_check(ships)
	print("Hex battle tests finished: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func render_check(ships: Array[FleetShip]) -> void:
	var simulation := BattleSimulation.new()
	check(simulation.setup_owned(ships, enemies(), 0.3, 0, 84), "Render the same hex combat adapter.")
	var visuals: Control = load("res://scripts/battle_visuals.gd").new()
	visuals.theme = preload("res://themes/ui_theme.tres")
	root.size = Vector2i(1280, 720)
	await process_frame
	visuals.size = root.get_visible_rect().size
	visuals.simulation = simulation
	visuals.camera_position = simulation.players[0].position
	var footprint := simulation.players[0].stats.footprint_size
	visuals.camera_zoom = minf(visuals.size.x / footprint.x, visuals.size.y / footprint.y) * 0.8
	root.transparent_bg = false
	RenderingServer.set_default_clear_color(Color("090e12"))
	root.add_child(visuals)
	for frame in range(4):
		await process_frame
	check(visuals._owned_render_cache.is_empty(), "Hex render bypasses square hull and equipment sprites.")
	check(visuals.get_theme_default_font() == visuals.theme.default_font, "Hex battle labels use the shared theme's default font.")
	check(visuals.get_theme_font_size("font_size", "HexEquipmentLabel") == 13, "Starhull equipment labels use their crisp native pixel size.")
	check(visuals._get_tile_texture(0) == preload("res://themes/hex_material_palette.tres").offense, "Hex combat salvage uses supplied hex material art.")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/ui-review/hex-battle.png")
	visuals.queue_free()
	await process_frame
