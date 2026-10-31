class_name LegacyHexGrid
extends RefCounted

# Coordinate validation for old archives only; no rendering or collision API.
const NEIGHBORS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]

static func transform(cell: Vector2i, turns: int, flipped := false) -> Vector2i:
	var result := cell
	for index in range(posmod(turns, 6)):
		result = Vector2i(-result.y, result.x + result.y)
	if flipped:
		result = Vector2i(result.x + result.y, -result.y)
	return result

static func connected(cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return false
	var available := {}
	for cell in cells:
		if available.has(cell):
			return false
		available[cell] = true
	var visited := {}
	var pending: Array[Vector2i] = [cells[0]]
	while not pending.is_empty():
		var next: Vector2i = pending.pop_back()
		if visited.has(next):
			continue
		visited[next] = true
		for offset in NEIGHBORS:
			if available.has(next + offset) and not visited.has(next + offset):
				pending.append(next + offset)
	return visited.size() == available.size()
