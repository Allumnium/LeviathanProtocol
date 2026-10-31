class_name HexRecipeMatcher
extends RefCounted

var _by_material := {}
var patterns: Array[ShipPartPattern] = []

func _init(allowed: Array[ShipPartPattern]) -> void:
	patterns = allowed.duplicate()
	for pattern in patterns:
		if pattern.definition_id == "command_center":
			continue
		var recipe := HexRecipe.find(pattern.definition_id, pattern.rank)
		var seen := {}
		for turns in range(6):
			for flipped in [false, true]:
				var layout := HexRecipe.cells(recipe, turns, flipped)
				var items: Array[String] = []
				for cell: Vector2i in layout:
					items.append("%d,%d:%d" % [cell.x, cell.y, layout[cell]])
				items.sort()
				var signature := ";".join(items)
				if seen.has(signature):
					continue
				seen[signature] = true
				for anchor: Vector2i in layout:
					var category: int = layout[anchor]
					if not _by_material.has(category):
						_by_material[category] = []
					_by_material[category].append({"equipment_id": pattern.definition_id, "rank": pattern.rank,
						"turns": turns, "flipped": flipped, "layout": layout, "anchor": anchor})

func matches(design: HexShipDesign, changed: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	var component_cells: Array[Dictionary] = []
	for component in design.components:
		component_cells.append(HexShipDesign.component_cells(component))
	for candidate: Dictionary in _by_material.get(design.tiles.get(changed, -1), []):
		var origin: Vector2i = changed - candidate.anchor
		var footprint: Array[Vector2i] = []
		var valid := true
		for offset: Vector2i in candidate.layout:
			var cell := origin + offset
			if design.tiles.get(cell, -1) != candidate.layout[offset]:
				valid = false
				break
			footprint.append(cell)
		if not valid or design.region_for(footprint).is_empty():
			continue
		for occupied in component_cells:
			var overlap := 0
			for cell: Vector2i in occupied:
				if cell in footprint:
					overlap += 1
			if overlap > 0 and (overlap != occupied.size() or occupied.size() >= footprint.size()):
				valid = false
				break
		if not valid:
			continue
		var ordered: Array[String] = []
		for cell in footprint:
			ordered.append("%d,%d" % [cell.x, cell.y])
		ordered.sort()
		var key := "%s/%d:%s" % [candidate.equipment_id, candidate.rank, ";".join(ordered)]
		if seen.has(key):
			continue
		seen[key] = true
		result.append({"equipment_id": candidate.equipment_id, "rank": candidate.rank,
			"origin": origin, "turns": candidate.turns, "flipped": candidate.flipped, "size": footprint.size()})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.size != b.size:
			return a.size > b.size
		return HexRecipe.key(a.equipment_id, a.rank) < HexRecipe.key(b.equipment_id, b.rank))
	return result

func assemble_unique(design: HexShipDesign, changed: Vector2i) -> Array[Dictionary]:
	var largest := choices(design, changed)
	if largest.is_empty():
		return []
	# Equal-size alternatives (especially exclusive branches) require a click.
	if largest.size() != 1:
		return largest
	var selected := largest[0]
	design.assemble(selected.equipment_id, selected.rank, selected.origin, selected.turns, selected.flipped)
	return []

func choices(design: HexShipDesign, changed: Vector2i) -> Array[Dictionary]:
	var found := matches(design, changed)
	var result: Array[Dictionary] = []
	var seen := {}
	for candidate in found:
		if candidate.size != found[0].size:
			break
		var key := HexRecipe.key(candidate.equipment_id, candidate.rank)
		if not seen.has(key):
			result.append(candidate)
			seen[key] = true
	return result
