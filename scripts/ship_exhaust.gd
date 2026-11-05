extends RefCounted

const NOZZLES := {
	"flagship_basic": [Vector2(128, 480), Vector2(194, 500), Vector2(318, 500), Vector2(384, 480)],
	"flagship_civic": [Vector2(148, 484), Vector2(219, 484), Vector2(293, 484), Vector2(364, 484)],
	"flagship_science": [Vector2(168, 449), Vector2(209, 477), Vector2(303, 477), Vector2(344, 449)],
	"flagship_offense": [Vector2(200, 475), Vector2(312, 475)],
	"corsair": [Vector2(178, 510), Vector2(334, 510)],
	"fighter": [Vector2(204, 480), Vector2(308, 480)],
	"transport": [Vector2(194, 493), Vector2(318, 493)],
	"frigate": [Vector2(188, 500), Vector2(324, 500)],
	"drone": [Vector2(256, 485)],
}

static func origins(owned: HangarShip, rect: Rect2) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not NOZZLES.has(owned.chassis_id):
		push_error("Missing exhaust anchors for chassis: %s" % owned.chassis_id)
		return points
	for nozzle: Vector2 in NOZZLES[owned.chassis_id]:
		points.append(rect.position + nozzle * rect.size / 512)
	return points

static func draw(target: CanvasItem, owned: HangarShip, rect: Rect2, elapsed: float,
		strength := 1.0, visible_at := Callable(), particle_count := 12) -> void:
	if not owned.is_alive():
		return
	var scale := rect.size / 512
	var phase := float(owned.id % 11) / 11.0
	for origin in origins(owned, rect):
		for index in range(particle_count):
			var age := fposmod(elapsed * 8.0 + phase + float(index) / particle_count, 1.0)
			var point := origin + Vector2(sin(index * 2.4) * age * 12,
				age * (40 + strength * 56)) * scale
			if visible_at.is_valid() and not visible_at.call(point):
				continue
			var tint := Color(0.35, 0.75, 1.0).lerp(Color(0.9, 0.98, 1.0), 1.0 - age)
			var extent := Vector2.ONE * (8 if age < 0.45 else 4) * scale
			target.draw_rect(Rect2(point - extent * 0.5, extent), Color(tint, (1.0 - age) * 0.85))
