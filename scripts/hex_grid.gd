class_name HexGrid
extends RefCounted

# Point-up hexes, axial (q, r). Positive q is the ship's forward/right axis.
const NEIGHBORS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const CORNERS := [Vector2i(1, -1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(0, -2)]
const ROOT_THREE := 1.7320508075688772

static func center(cell: Vector2i, radius: float) -> Vector2:
	return Vector2(ROOT_THREE * (cell.x + cell.y * 0.5), 1.5 * cell.y) * radius

static func at_point(point: Vector2, radius: float) -> Vector2i:
	assert(radius > 0)
	var r := point.y / (1.5 * radius)
	var q := point.x / (ROOT_THREE * radius) - r * 0.5
	var s := -q - r
	var qi := roundi(q)
	var ri := roundi(r)
	var si := roundi(s)
	if absf(qi - q) > absf(ri - r) and absf(qi - q) > absf(si - s):
		qi = -ri - si
	elif absf(ri - r) > absf(si - s):
		ri = -qi - si
	return Vector2i(qi, ri)

static func distance(a: Vector2i, b: Vector2i = Vector2i.ZERO) -> int:
	var d := a - b
	return maxi(absi(d.x), maxi(absi(d.y), absi(d.x + d.y)))

static func transform(cell: Vector2i, turns: int, flipped := false) -> Vector2i:
	var result := cell
	for index in range(posmod(turns, 6)):
		result = Vector2i(-result.y, result.x + result.y)
	if flipped:
		result = Vector2i(result.x + result.y, -result.y)
	return result

static func corner_key(cell: Vector2i, index: int) -> Vector2i:
	return Vector2i(2 * cell.x + cell.y, 3 * cell.y) + CORNERS[posmod(index, 6)]

static func corner_point(key: Vector2i, radius: float) -> Vector2:
	return Vector2(key.x * ROOT_THREE * 0.5, key.y * 0.5) * radius

static func polygon(cell: Vector2i, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(6):
		result.append(corner_point(corner_key(cell, index), radius))
	return result

static func bounds(cells: Array[Vector2i], radius: float) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var result := Rect2(center(cells[0], radius), Vector2.ZERO)
	for cell in cells:
		for vertex in polygon(cell, radius):
			result = result.expand(vertex)
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

# Integer vertex keys cancel shared edges exactly: no float seams or convex fill.
# Inner holes retain their own boundary rather than becoming construction space.
static func boundaries(cells: Array[Vector2i], radius: float) -> Array[PackedVector2Array]:
	var edges := {}
	for cell in cells:
		for index in range(6):
			var a := corner_key(cell, index)
			var b := corner_key(cell, index + 1)
			var forward := Vector4i(a.x, a.y, b.x, b.y)
			var reverse := Vector4i(b.x, b.y, a.x, a.y)
			if edges.has(reverse):
				edges.erase(reverse)
			else:
				edges[forward] = true
	var outgoing := {}
	for edge: Vector4i in edges:
		var start := Vector2i(edge.x, edge.y)
		if outgoing.has(start):
			return []
		outgoing[start] = Vector2i(edge.z, edge.w)
	var result: Array[PackedVector2Array] = []
	while not outgoing.is_empty():
		var start: Vector2i = outgoing.keys()[0]
		var cursor := start
		var loop := PackedVector2Array()
		while outgoing.has(cursor):
			loop.append(corner_point(cursor, radius))
			var next: Vector2i = outgoing[cursor]
			outgoing.erase(cursor)
			cursor = next
			if cursor == start:
				break
		if cursor != start or loop.size() < 3:
			return []
		result.append(loop)
	return result

static func ray_distance(cell: Vector2i, origin: Vector2, direction: Vector2, radius: float) -> float:
	var shape := polygon(cell, radius)
	if Geometry2D.is_point_in_polygon(origin, shape):
		return 0
	if direction.is_zero_approx():
		return INF
	var nearest := INF
	var ray := direction.normalized()
	for index in range(6):
		var edge := shape[(index + 1) % 6] - shape[index]
		var denominator := ray.cross(edge)
		if absf(denominator) < 0.000001:
			continue
		var relative := shape[index] - origin
		var along_ray := relative.cross(edge) / denominator
		var along_edge := relative.cross(ray) / denominator
		if along_ray >= 0 and along_edge >= 0 and along_edge <= 1:
			nearest = minf(nearest, along_ray)
	return nearest
