class_name MaterialRecipe
extends RefCounted

const SYMBOLS := {"O": 0, "D": 1, "T": 2, "C": 3}
const EXCLUSIVE_PAIRS := [
	["focusing_lens", "ion_emitter"], ["beam_lance", "gravitic_snare"], ["stellar_lance", "singularity_projector"],
	["reactive_bulkhead", "repair_drone_bay"], ["shield_relay", "nanoforge"], ["aegis_citadel", "ark_restoration_core"],
	["ammunition_magazine", "flight_deck"], ["railgun", "torpedo_bomber_bay"], ["siege_mass_driver", "hive_carrier_core"],
	["command_uplink", "ecm_suite"], ["tactical_computer", "phase_drive"], ["admiralty_nexus", "ghost_network"]]

static func parse(recipe: String) -> Dictionary:
	var result: Dictionary = {}
	var rows := recipe.split("/")
	if rows.is_empty() or rows[0].is_empty():
		return {}
	for y in range(rows.size()):
		if rows[y].length() != rows[0].length():
			return {}
		for x in range(rows[y].length()):
			var symbol := rows[y][x]
			if symbol == ".":
				continue
			if not SYMBOLS.has(symbol):
				return {}
			result[Vector2i(x, y)] = SYMBOLS[symbol]
	return result

static func direction(offset: Vector2i, turns: int, flipped: bool) -> Vector2i:
	var result := offset
	for _turn in range(posmod(turns, 4)):
		result = Vector2i(-result.y, result.x)
	if flipped:
		result.y = -result.y
	return result

static func transformed(cells: Dictionary, turns: int, flipped: bool) -> Dictionary:
	if cells.is_empty():
		return {}
	var minimum := Vector2i(2147483647, 2147483647)
	var result: Dictionary = {}
	for cell: Vector2i in cells:
		var next := direction(cell, turns, flipped)
		minimum.x = mini(minimum.x, next.x)
		minimum.y = mini(minimum.y, next.y)
		result[next] = cells[cell]
	var normalized: Dictionary = {}
	for cell: Vector2i in result:
		normalized[cell - minimum] = result[cell]
	return normalized

static func signature(cells: Dictionary) -> String:
	if cells.is_empty():
		return ""
	var best := ""
	for turns in range(4):
		for flip in range(2):
			var items: Array[String] = []
			var normalized := transformed(cells, turns, flip == 1)
			for cell: Vector2i in normalized:
				items.append("%d,%d:%d" % [cell.x, cell.y, normalized[cell]])
			items.sort()
			var key := ";".join(items)
			if best.is_empty() or key < best:
				best = key
	return best

static func validate_registry(equipment: Array) -> Array[String]:
	var errors: Array[String] = []
	var signatures: Dictionary = {}
	for entry: Dictionary in equipment:
		var recipes: Array = [{"rank": 1, "recipe": entry.recipe}]
		var declared_ranks: Array[int] = []
		for rank: Dictionary in entry.ranks:
			if declared_ranks.has(int(rank.rank)):
				errors.append("Duplicate declared rank: %s/%d" % [entry.id, int(rank.rank)])
			declared_ranks.append(int(rank.rank))
			if int(rank.rank) == 1:
				if rank.recipe != entry.recipe:
					errors.append("Rank I differs from base recipe: %s" % entry.id)
			else:
				recipes.append(rank)
		var ranks: Array[int] = []
		for recipe: Dictionary in recipes:
			var rank := int(recipe.rank)
			if ranks.has(rank):
				errors.append("Duplicate recipe rank: %s/%d" % [entry.id, rank])
			ranks.append(rank)
			var key := signature(parse(recipe.recipe))
			if key.is_empty():
				errors.append("Empty recipe: %s" % entry.id)
				continue
			if not signatures.has(key):
				signatures[key] = []
			signatures[key].append("%s/%d" % [entry.id, rank])
	for key in signatures:
		var ids: Array = signatures[key]
		if ids.size() < 2:
			continue
		ids.sort()
		var allowed := false
		for pair: Array in EXCLUSIVE_PAIRS:
			var expected := [pair[0] + "/1", pair[1] + "/1"]
			expected.sort()
			allowed = allowed or ids == expected
		if not allowed:
			errors.append("Unexpected canonical recipe collision: %s" % ", ".join(ids))
	for pair: Array in EXCLUSIVE_PAIRS:
		var found := false
		for ids: Array in signatures.values():
			found = found or (ids.has(pair[0] + "/1") and ids.has(pair[1] + "/1"))
		if not found:
			errors.append("Missing exclusive recipe pair: %s/%s" % pair)
	return errors

static func loose_matches(design: Ship, patterns: Array[ShipPartPattern], locked: Dictionary = {}) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var seen: Dictionary = {}
	for pattern in patterns:
		for turns in range(4 if pattern.can_rotate else 1):
			for flip in range(2):
				var offsets := pattern.get_offsets_for_transform(turns, flip == 1)
				if offsets.is_empty():
					continue
				for anchor: Vector2i in design.tiles:
					var origin: Vector2i = anchor - offsets[0]
					var cells: Array[Vector2i] = []
					var valid := true
					for index in range(offsets.size()):
						var cell: Vector2i = origin + offsets[index]
						if locked.has(cell) or design.get_part_at(cell) != null or design.get_tile_category_at(cell) != pattern.tile_categories[index]:
							valid = false
							break
						cells.append(cell)
					if not valid:
						continue
					var labels: Array[String] = []
					for cell in cells:
						labels.append("%d,%d" % [cell.x, cell.y])
					labels.sort()
					var key := "%s:%s" % [pattern.pattern_key(), ";".join(labels)]
					if seen.has(key):
						continue
					seen[key] = true
					matches.append({"pattern": pattern, "origin": origin, "turns": turns, "flipped": flip == 1, "cells": cells})
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.cells.size() != b.cells.size():
			return a.cells.size() > b.cells.size()
		if a.pattern.part_type != b.pattern.part_type:
			return a.pattern.part_type < b.pattern.part_type
		return a.origin.y < b.origin.y if a.origin.y != b.origin.y else a.origin.x < b.origin.x)
	return matches
