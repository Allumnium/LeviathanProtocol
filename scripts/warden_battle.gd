extends RefCounted

var rules: Dictionary = {}
var clock := 0.0
var charging := false
var cycle := 0
var finished_cycle := 0
var charge_damage := 0.0
var origin := Vector2.ZERO
var direction := Vector2.LEFT
var exposed := 0.0
var pylons_broken := false
var flash := 0.0

static func valid_plan(plan: Dictionary) -> bool:
	var value: Variant = plan.get("warden")
	if not value is Dictionary or not value.get("body_id") is String or not value.get("pylon_ids") is Array \
		or not value.get("lance") is bool:
		return false
	var boss: bool = value.lance
	if plan.get("template_id") != ("bastion_warden" if boss else "pylon_escort") or int(plan.get("wave_count", 0)) != 1:
		return false
	for key in ["cycle_seconds", "warning_seconds", "vulnerability_seconds", "lance_damage", "range", "half_width"]:
		if not AlienShip._finite_number(value.get(key)):
			return false
	if value.cycle_seconds != 12 or value.warning_seconds != 3 or value.vulnerability_seconds != 6 \
		or value.lance_damage <= 0 or value.lance_damage > 30 or value.range != 520 or value.half_width != 22:
		return false
	if value.pylon_ids.size() != (2 if boss else 1):
		return false
	var ids := {}
	var body := false
	for entry: Dictionary in plan.roster:
		if entry.kind not in ["ship", "organ"] or int(entry.wave) != 0:
			return false
		if entry.entity_id == value.body_id:
			body = entry.kind == "ship" and entry.get("role", "") == ("warden" if boss else "fighter") and entry.name == ("Bastion Warden" if boss else "Fighter")
		if entry.kind == "organ":
			if entry.get("role", "") != "pylon" or entry.name != "Shield Pylon" or not value.pylon_ids.has(entry.entity_id):
				return false
			ids[entry.entity_id] = true
	if not body or ids.size() != value.pylon_ids.size():
		return false
	var unique := {}
	for id in value.pylon_ids:
		if not id is String or unique.has(id) or not ids.has(id) or id == value.body_id:
			return false
		unique[id] = true
	return true

func configure(sim, plan: Dictionary) -> bool:
	rules = plan.get("warden", {}).duplicate(true)
	clock = 0
	charging = false
	cycle = 0
	finished_cycle = 0
	charge_damage = 0
	exposed = 0
	pylons_broken = false
	flash = 0
	origin = Vector2.ZERO
	direction = Vector2.LEFT
	if rules.is_empty():
		return true
	if not valid_plan(plan):
		return false
	var body = sim.entities.get(rules.body_id)
	if body == null:
		return false
	body.position = Vector2(360 if rules.lance else 100, 0)
	body.previous_position = body.position
	if rules.lance:
		body.radius = 26
	for index in range(rules.pylon_ids.size()):
		var pylon = sim.entities.get(rules.pylon_ids[index])
		if pylon == null:
			return false
		pylon.position = body.position + Vector2(-30, -100 if index == 0 else 100)
		pylon.previous_position = pylon.position
		pylon.radius = 12
	return true

func live_pylons(sim) -> int:
	var count := 0
	for id in rules.get("pylon_ids", []):
		var member = sim.entities.get(id)
		if member != null and member.is_alive():
			count += 1
	return count

func protection(sim, target) -> float:
	if rules.is_empty() or target.entity_id != rules.body_id:
		return 1.0
	return (1.0 - 0.2 * live_pylons(sim)) * (1.25 if exposed > 0 else 1.0)

func on_damage(sim, target, actual: float) -> void:
	if rules.is_empty():
		return
	if rules.pylon_ids.has(target.entity_id):
		_check_pylons(sim)
	if target.entity_id == rules.body_id and charging:
		charge_damage += actual
		if charge_damage + 0.000001 >= target.stats.integrity * 0.06:
			charging = false
			finished_cycle = cycle
			sim._record_event("warden_interrupt", {"cycle": cycle})

func _check_pylons(sim) -> void:
	if not pylons_broken and live_pylons(sim) == 0:
		pylons_broken = true
		exposed = float(rules.vulnerability_seconds)
		sim._record_event("warden_exposed", {"seconds": exposed})

func advance(sim, delta: float) -> void:
	if rules.is_empty():
		return
	clock += delta
	exposed = maxf(0, exposed - delta)
	flash = maxf(0, flash - delta)
	_check_pylons(sim)
	var body = sim.entities.get(rules.body_id)
	if body == null or not body.is_alive() or not rules.lance:
		charging = false
		return
	var next_cycle := int(floor((clock + float(rules.warning_seconds) + 0.000001) / float(rules.cycle_seconds)))
	if next_cycle > cycle:
		cycle = next_cycle
		charge_damage = 0
		charging = true
		origin = body.position
		direction = Vector2.from_angle(body.heading)
		var target = null
		var nearest := INF
		for player in sim.players:
			if sim.can_attack(body, player) and body.position.distance_to(player.position) < minf(240.0, nearest):
				target = player
				nearest = body.position.distance_to(player.position)
		if target == null:
			charging = false
			finished_cycle = cycle
			return
		direction = origin.direction_to(target.position)
		body.heading = direction.angle()
		body.velocity = Vector2.ZERO
		sim.inactive_seconds = 0
		sim._record_event("warden_charge", {"cycle": cycle, "origin": [origin.x, origin.y], "direction": [direction.x, direction.y]})
	if charging and clock + 0.000001 >= cycle * float(rules.cycle_seconds):
		charging = false
		finished_cycle = cycle
		flash = 0.3
		var hit: Array[String] = []
		for member in sim._members:
			if not member.is_alive() or not member.targetable or member.faction == body.faction or member.has_tag("drop"):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(member.position, origin, origin + direction * float(rules.range))
			if member.position.distance_to(closest) <= member.radius + float(rules.half_width):
				sim._damage(member, float(rules.lance_damage), origin, body, "Warden Lance")
				hit.append(member.entity_id)
		sim._record_event("warden_lance", {"cycle": cycle, "hit": hit})

func visible(sim) -> bool:
	var body = sim.entities.get(rules.get("body_id", ""))
	return body != null and body.is_alive() and (not sim.visibility_enabled or sim.team_can_see(0, body))

func braced(member) -> bool:
	return charging and member.entity_id == rules.get("body_id", "")

func avoidance(sim, member, desired: Vector2) -> Vector2:
	if not charging or member.faction != 0 or not visible(sim):
		return desired
	var relative: Vector2 = member.position - origin
	var along := relative.dot(direction)
	var across := direction.cross(relative)
	if along < -member.radius or along > float(rules.range) + member.radius or absf(across) > float(rules.half_width) + member.radius + 30:
		return desired
	var side := signf(across) if absf(across) > 1 else (1.0 if member.entity_id.hash() % 2 == 0 else -1.0)
	return (desired + Vector2(-direction.y, direction.x) * side * member.speed * 2).limit_length(member.speed)

func label(sim) -> String:
	var text := "WARDEN: Destroy body" if rules.get("lance", false) else "PYLON ESCORT: Clear fleet"
	if not visible(sim):
		return text
	if exposed > 0:
		text += " | Exposed %ds" % ceili(exposed)
	if charging:
		text += " | Lance %ds" % ceili(maxf(0, cycle * float(rules.cycle_seconds) - clock - 0.000001))
	return text

func snapshot() -> Dictionary:
	return {"clock": clock, "charging": charging, "cycle": cycle, "finished_cycle": finished_cycle,
		"charge_damage": charge_damage, "origin": [origin.x, origin.y], "direction": [direction.x, direction.y],
		"exposed": exposed, "pylons_broken": pylons_broken, "flash": flash}
