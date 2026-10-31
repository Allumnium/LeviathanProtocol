class_name LegacyHexShipDesign
extends RefCounted

# Read-only archive representation. Private helpers validate historical data.

const SCHEMA_VERSION := 2
var chassis_id := ""
var chassis_revision := 1
var tiles: Dictionary[Vector2i, int] = {}
# Fitted components store stable recipe identity and transform, never trusted HP,
# modifiers, masks or built-ins. Those are reconstructed from versioned catalogs.
var components: Array[Dictionary] = []
var _chassis: LegacyHexChassisDefinition

func _initialize_for_import(id: String, revision := 1) -> bool:
	var next := LegacyHexChassisCatalog.find(id, revision)
	if next == null:
		return false
	chassis_id = id
	chassis_revision = revision
	_chassis = next
	tiles.clear()
	components.clear()
	return true

func chassis() -> LegacyHexChassisDefinition:
	# Return a new copy to keep the outline immutable to clients.
	return LegacyHexChassisCatalog.find(chassis_id, chassis_revision)

func region_for(cells: Array[Vector2i]) -> String:
	return _chassis.region_for(cells) if _chassis else ""

func _set_tile_for_import(cell: Vector2i, category: int) -> bool:
	if _chassis == null or _chassis.region_at(cell).is_empty() or category < 0 or category > 3:
		return false
	if tiles.get(cell, -1) == category:
		return true
	tiles[cell] = category
	return true

static func component_cells(component: Dictionary) -> Dictionary:
	var recipe := LegacyHexRecipe.find(component.equipment_id, int(component.rank))
	return LegacyHexRecipe.cells(recipe, int(component.turns), component.flipped, component.origin)

func _fit_for_import(equipment_id: String, rank: int, origin: Vector2i, turns := 0, flipped := false) -> bool:
	var recipe := LegacyHexRecipe.find(equipment_id, rank)
	# Command centers belong to chassis, not player construction.
	if recipe.is_empty() or equipment_id == "command_center" or turns < 0 or turns > 5:
		return false
	var layout := LegacyHexRecipe.cells(recipe, turns, flipped, origin)
	var footprint: Array[Vector2i] = []
	footprint.assign(layout.keys())
	if _chassis == null or _chassis.region_for(footprint).is_empty():
		return false
	for cell: Vector2i in layout:
		if tiles.get(cell, -1) != layout[cell]:
			return false
	for fitted in components:
		var existing := component_cells(fitted)
		for cell: Vector2i in layout:
			if existing.has(cell):
				return false
	components.append({"equipment_id": equipment_id, "rank": rank, "recipe_revision": int(recipe.revision),
		"origin": origin, "turns": turns, "flipped": flipped})
	return true

func to_data() -> Dictionary:
	var tile_data: Array = []
	var ordered := tiles.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell: Vector2i in ordered:
		tile_data.append([cell.x, cell.y, tiles[cell]])
	var fitted: Array = []
	for component in components:
		var saved := component.duplicate(true)
		saved.origin = [component.origin.x, component.origin.y]
		fitted.append(saved)
	return {"version": SCHEMA_VERSION, "topology": LegacyHexRecipe.TOPOLOGY, "chassis_id": chassis_id,
		"chassis_revision": chassis_revision, "tiles": tile_data, "components": fitted}

# Transactional loading: malformed/legacy/future data leaves the current design
# untouched. No square coordinates are guessed or silently converted.
func load_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != SCHEMA_VERSION or data.get("topology") != LegacyHexRecipe.TOPOLOGY or not data.get("chassis_id") is String or not LegacyHexRecipe.integer(data.get("chassis_revision"), 1):
		return false
	if not data.get("tiles") is Array or not data.get("components") is Array or data.tiles.size() > 2048 or data.components.size() > 2048:
		return false
	var next := LegacyHexShipDesign.new()
	if not next._initialize_for_import(data.chassis_id, int(data.chassis_revision)):
		return false
	for item: Variant in data.tiles:
		if not item is Array or item.size() != 3 or not LegacyHexRecipe.integer(item[0]) or not LegacyHexRecipe.integer(item[1]) or not LegacyHexRecipe.integer(item[2], 0, 3):
			return false
		var cell := Vector2i(int(item[0]), int(item[1]))
		if next.tiles.has(cell) or not next._set_tile_for_import(cell, int(item[2])):
			return false
	for item: Variant in data.components:
		if not item is Dictionary or not item.get("equipment_id") is String or not LegacyHexRecipe.integer(item.get("rank"), 1, 3) or not LegacyHexRecipe.integer(item.get("turns"), 0, 5) or not item.get("flipped") is bool or not LegacyHexRecipe.read_cell(item.get("origin")):
			return false
		var recipe := LegacyHexRecipe.find(item.equipment_id, int(item.rank))
		if recipe.is_empty() or item.get("recipe_revision") != recipe.revision:
			return false
		if not next._fit_for_import(item.equipment_id, int(item.rank), Vector2i(int(item.origin[0]), int(item.origin[1])), int(item.turns), item.flipped):
			return false
	chassis_id = next.chassis_id
	chassis_revision = next.chassis_revision
	_chassis = next._chassis
	tiles = next.tiles
	components = next.components
	return true
