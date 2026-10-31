class_name ChassisDefinition
extends RefCounted

const MODIFIERS := ["armor_integrity", "weapon_range"]
var id := ""
var revision := 1
var display_name := ""
var flagship := false
var integrity := 1.0
var command_points := 0
var command_cost := 0
var hull: Array[Vector2i] = []
var regions: Array[Dictionary] = []
var builtins: Array[Dictionary] = []
var _region_cells := {}
var _hull_cells := {}

static func from_data(data: Variant) -> ChassisDefinition:
	if not validate(data).is_empty():
		return null
	var result := ChassisDefinition.new()
	result.id = data.id
	result.revision = int(data.revision)
	result.display_name = data.display_name
	result.flagship = data.flagship
	result.integrity = float(data.integrity)
	result.command_points = int(data.command_points)
	result.command_cost = int(data.command_cost)
	for item: Array in data.hull:
		var cell := Vector2i(int(item[0]), int(item[1]))
		result.hull.append(cell)
		result._hull_cells[cell] = true
	result.regions = _load_groups(data.regions)
	result.builtins = _load_groups(data.builtins)
	for region in result.regions:
		for cell: Vector2i in region.cells:
			result._region_cells[cell] = region.id
	return result

static func _load_groups(groups: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: Dictionary in groups:
		var next := group.duplicate(true)
		var cells: Array[Vector2i] = []
		for item: Array in group.cells:
			cells.append(Vector2i(int(item[0]), int(item[1])))
		next.cells = cells
		result.append(next)
	return result

func has_cell(cell: Vector2i) -> bool:
	return _hull_cells.has(cell)

func region_at(cell: Vector2i) -> String:
	return _region_cells.get(cell, "")

func region_for(cells: Array[Vector2i]) -> String:
	if cells.is_empty():
		return ""
	var region := region_at(cells[0])
	if region.is_empty():
		return ""
	for cell in cells:
		if region_at(cell) != region:
			return ""
	return region

func modifiers_at(cell: Vector2i) -> Dictionary:
	var id_at := region_at(cell)
	for region in regions:
		if region.id == id_at:
			return region.modifiers.duplicate(true)
	return {}

static func validate(data: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not data is Dictionary:
		return ["Chassis must be an object."]
	if not data.get("id") is String or data.get("id", "").is_empty() or not data.get("display_name") is String or data.get("display_name", "").is_empty() or not HexRecipe.integer(data.get("revision"), 1):
		errors.append("Missing chassis identity.")
	if not data.get("flagship") is bool or not (data.get("integrity") is float or data.get("integrity") is int) or not is_finite(float(data.get("integrity", 0))) or data.get("integrity", 0) <= 0:
		errors.append("Invalid chassis integrity or flagship flag.")
	if not HexRecipe.integer(data.get("command_points"), 0) or not HexRecipe.integer(data.get("command_cost"), 0):
		errors.append("Invalid chassis command points/cost.")
	elif data.get("flagship") == true:
		if data.command_points <= 0 or data.command_cost != 0:
			errors.append("Flagships supply command points and consume none.")
	elif data.command_points != 0 or data.command_cost <= 0:
		errors.append("Non-flagships consume command points and supply none.")
	if not data.get("hull") is Array or data.hull.is_empty() or data.hull.size() > 2048:
		return errors + ["Invalid chassis hull."]
	var hull := {}
	var footprint: Array[Vector2i] = []
	for item: Variant in data.hull:
		if not HexRecipe.read_cell(item):
			return errors + ["Invalid hull cell."]
		var cell := Vector2i(int(item[0]), int(item[1]))
		footprint.append(cell)
		hull[cell] = true
	if not HexGrid.connected(footprint):
		errors.append("Chassis hull must be unique connected hexes.")
	var assigned := {}
	var ids := {}
	var region_cells := {}
	var cores := 0
	for field in ["regions", "builtins"]:
		if not data.get(field) is Array or data[field].is_empty():
			errors.append("Missing %s." % field)
			continue
		for group: Variant in data[field]:
			if not group is Dictionary or not group.get("id") is String or group.get("id", "").is_empty() or not group.get("cells") is Array or group.cells.is_empty():
				errors.append("Invalid %s group." % field)
				continue
			if ids.has(group.id):
				errors.append("Repeated chassis group ID.")
			ids[group.id] = true
			var group_cells: Array[Vector2i] = []
			for item: Variant in group.cells:
				if not HexRecipe.read_cell(item):
					errors.append("Invalid %s cell." % field)
					continue
				var cell := Vector2i(int(item[0]), int(item[1]))
				group_cells.append(cell)
				if not hull.has(cell) or assigned.has(cell):
					errors.append("Chassis groups overlap or leave the hull.")
				assigned[cell] = true
				if field == "regions":
					region_cells[cell] = group.id
			if not HexGrid.connected(group_cells):
				errors.append("Chassis group must be connected.")
			if field == "regions":
				if not group.get("modifiers") is Dictionary:
					errors.append("Missing region modifiers.")
					continue
				for modifier: Variant in group.modifiers:
					var value: Variant = group.modifiers[modifier]
					if not modifier in MODIFIERS or not (value is float or value is int) or not is_finite(float(value)) or value < 0 or value > 1:
						errors.append("Unsupported or unbounded region modifier.")
			else:
				if not group.get("equipment_id") is String or not HexRecipe.integer(group.get("rank"), 1, 3) or GameDefinitions.find("equipment", group.get("equipment_id", "")).is_empty():
					errors.append("Unknown built-in equipment.")
				if group.get("equipment_id") == "command_center":
					cores += 1
	if cores != 1:
		errors.append("Chassis requires exactly one built-in command center.")
	for cell: Vector2i in region_cells:
		for neighbor: Vector2i in HexGrid.NEIGHBORS:
			if region_cells.has(cell + neighbor) and region_cells[cell] != region_cells[cell + neighbor]:
				errors.append("Construction regions must have a hex gap.")
				return errors
	return errors
