class_name AsteroidField
extends RefCounted

# A field owns lineage and ore; combat actors are its temporary presentation.
# Resolved parents remain records, never colliders or additional mineral budgets.
const MAX_ROCKS := 96
const MAX_ROOTS := 48
const MASSES := [1, 2, 4, 8]
const BIRTH_GRACE := 0.5
const IMPACT_INTERVAL := 0.75
var records: Dictionary = {}
var roots: Dictionary = {}
var impacts: Dictionary = {}
var extraction := {"rate": 0.0, "materials": []}
var pickup_commit := Callable()
var collected := [0, 0, 0, 0]
var last_commit_failed := false
var retry_remaining := 0.0
var replayed_rejections: Dictionary = {}
var last_replayed_rejection := false

static func generate(seed_value: int, count := 12) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var field := AsteroidField.new()
	for index in range(clampi(count, 0, MAX_ROOTS)):
		var id := "rock/%d" % index
		var mass: int = MASSES[rng.randi_range(0, 3)]
		var ore := [0, 0, 0, 0]
		# Exactly half the roots are empty, within the initial 40-60% target.
		if index % 2 == 0:
			ore[rng.randi_range(0, 3)] = mass * 4
		var angle := rng.randf_range(0, TAU)
		var position := Vector2.from_angle(angle) * rng.randf_range(170, 620)
		if position.distance_to(Vector2(-420, 0)) < 140 or position.distance_to(Vector2(420, 0)) < 140:
			position.y += 200 if position.y >= 0 else -200
		var velocity := Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(3, 12)
		field.add_root(id, mass, position, velocity, ore)
	return field.snapshot()

func add_root(id: String, mass: int, position: Vector2, velocity: Vector2, ore: Array) -> bool:
	if roots.size() >= MAX_ROOTS or records.has(id) or id.is_empty() or mass not in MASSES \
		or not position.is_finite() or not velocity.is_finite() or not _ore(ore):
		return false
	roots[id] = {"mass": mass, "ore": ore.duplicate(), "extraction": {}, "processed": [0, 0, 0, 0], "paid": [0, 0, 0, 0]}
	records[id] = _record(id, "", mass, position, velocity, ore)
	return true

static func _record(root_id: String, parent: String, mass: int, position: Vector2, velocity: Vector2, ore: Array) -> Dictionary:
	return {"root": root_id, "parent": parent, "mass": mass, "hp": mass * 12.0,
		"position": [position.x, position.y], "velocity": [velocity.x, velocity.y], "ore": ore.duplicate(),
		"grace": 0.0, "status": "alive", "claimed": false, "known": {"0": false, "1": false}}

func snapshot() -> Dictionary:
	return {"version": 1, "roots": roots.duplicate(true), "records": records.duplicate(true), "impacts": impacts.duplicate(true)}

func configure(data: Dictionary, policy: Dictionary = {}) -> bool:
	if not valid(data) or not valid_policy(policy):
		return false
	roots = data.roots.duplicate(true)
	records = {}
	var keys: Array = data.records.keys()
	keys.sort()
	for id: String in keys:
		var record: Dictionary = data.records[id].duplicate(true)
		record.mass = int(record.mass)
		record.ore = _integers(record.ore)
		records[id] = record
	for root: Dictionary in roots.values():
		root.mass = int(root.mass)
		for key in ["ore", "processed", "paid"]:
			root[key] = _integers(root[key])
		if not root.extraction.is_empty():
			root.extraction.materials = _integers(root.extraction.materials)
	impacts = data.get("impacts", {}).duplicate(true)
	extraction = policy.duplicate(true) if not policy.is_empty() else {"rate": 0.0, "materials": []}
	extraction.materials = _integers(extraction.materials)
	collected = [0, 0, 0, 0]
	return true

static func valid_policy(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not _number(value.get("rate")) or value.rate < 0 or value.rate > 1 or not value.get("materials") is Array:
		return false
	var seen := []
	for category in value.materials:
		if not _integer(category) or int(category) not in [0, 1, 2, 3] or seen.has(int(category)):
			return false
		seen.append(int(category))
	return true

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("roots") is Dictionary or not data.get("records") is Dictionary \
		or data.roots.size() > MAX_ROOTS or data.records.size() > MAX_ROOTS * 15 or not data.get("impacts", {}) is Dictionary:
		return false
	var live := 0
	for key in data.records:
		var r: Variant = data.records[key]
		if not key is String or key.is_empty() or not r is Dictionary or not r.get("root") is String or not data.roots.has(r.root) \
			or not r.get("parent") is String or not _integer(r.get("mass")) or int(r.mass) not in MASSES \
			or not _number(r.get("hp")) or r.hp < 0 or r.hp > r.mass * 12 or not _vector(r.get("position")) or not _vector(r.get("velocity")) \
			or not _ore(r.get("ore")) or not _number(r.get("grace")) or r.grace < 0 or r.grace > BIRTH_GRACE \
			or r.get("status") not in ["alive", "pending", "split", "terminal"] or not r.get("claimed") is bool \
			or not r.get("known") is Dictionary or not r.known.get("0") is bool or not r.known.get("1") is bool:
			return false
		if r.status == "alive":
			if r.hp <= 0 or r.claimed:
				return false
			live += 1
		elif r.hp != 0 or (r.status == "terminal" and r.mass != 1) or (r.status in ["split", "pending"] and r.mass == 1) \
			or (r.claimed and r.status != "terminal"):
			return false
		if r.parent.is_empty():
			if key != r.root:
				return false
		else:
			if not data.records.has(r.parent):
				return false
			var parent: Dictionary = data.records[r.parent]
			if parent.get("status") != "split" or parent.get("root") != r.root or parent.get("mass", 0) != r.mass * 2 \
				or key not in [r.parent + "/0", r.parent + "/1"]:
				return false
		if r.status == "split":
			var a: Variant = data.records.get(key + "/0")
			var b: Variant = data.records.get(key + "/1")
			if not a is Dictionary or not b is Dictionary or a.get("parent") != key or b.get("parent") != key \
				or not _ore(a.get("ore")) or not _ore(b.get("ore")):
				return false
			for category in range(4):
				if a.ore[category] + b.ore[category] != r.ore[category]:
					return false
	if live > MAX_ROCKS:
		return false
	for key in data.roots:
		var root: Variant = data.roots[key]
		var r: Variant = data.records.get(key)
		if not root is Dictionary or not r is Dictionary or r.get("parent") != "" or r.get("root") != key \
			or root.get("mass") != r.mass or not _ore(root.get("ore")) or root.ore != r.ore \
			or not _ore(root.get("processed")) or not _ore(root.get("paid")) or not valid_policy(root.get("extraction")):
			return false
		var processed := [0, 0, 0, 0]
		for fragment: Dictionary in data.records.values():
			if fragment.root == key and fragment.claimed:
				for category in range(4):
					processed[category] += fragment.ore[category]
		for category in range(4):
			if root.processed[category] != processed[category] or processed[category] > root.ore[category]:
				return false
			var rate: float = root.extraction.get("rate", 0.0) if _eligible(root.extraction, category) else 0.0
			if root.paid[category] != floori(processed[category] * rate + 0.0000001):
				return false
	for key in data.get("impacts", {}):
		if not key is String or not _number(data.impacts[key]) or data.impacts[key] < 0 or data.impacts[key] > IMPACT_INTERVAL:
			return false
	return true

func attach(sim) -> void:
	for id: String in records:
		var r: Dictionary = records[id]
		if r.status != "alive":
			continue
		var actor = sim.add_neutral_target(id, float(r.hp), _vec(r.position))
		if actor == null:
			continue
		actor.tags["asteroid"] = true
		actor.radius = 8.0 * sqrt(float(r.mass))
		actor.stats.collision_radius = actor.radius
		actor.stats.weight = r.mass
		actor.velocity = _vec(r.velocity)
		actor.resource_contents = {"materials": r.ore.duplicate()}
		for team in [0, 1]:
			if r.known[str(team)]:
				sim.abilities.resource_knowledge[team][id] = actor.resource_contents.duplicate(true)

func remember(sim) -> void:
	for id: String in records:
		var r: Dictionary = records[id]
		if r.status == "alive" and sim.entities.has(id):
			var actor = sim.entities[id]
			r.hp = maxf(0, actor.integrity)
			r.position = [actor.position.x, actor.position.y]
			r.velocity = [actor.velocity.x, actor.velocity.y]
		for team in [0, 1]:
			if sim.abilities.resource_knowledge.get(team, {}).has(id):
				r.known[str(team)] = true

func on_damage(sim, actor, _source, _weapon: String) -> void:
	if not records.has(actor.entity_id):
		return
	var r: Dictionary = records[actor.entity_id]
	var root: Dictionary = roots[r.root]
	if root.extraction.is_empty():
		root.extraction = MiningRules.snapshot(sim, _source, _weapon) if sim.mining_enabled else extraction.duplicate(true)
	r.hp = maxf(actor.integrity, 0)
	if actor.is_alive():
		return
	r.position = [actor.position.x, actor.position.y]
	r.velocity = [actor.velocity.x, actor.velocity.y]
	r.status = "pending" if r.mass > 1 else "terminal"
	actor.targetable = false
	actor.wreck_motion_remaining = 0
	remember(sim)

func advance(sim, delta: float) -> void:
	retry_remaining = maxf(0, retry_remaining - delta)
	for key in impacts.keys():
		impacts[key] = maxf(0, impacts[key] - delta)
		if impacts[key] <= 0:
			impacts.erase(key)
	for id: String in records:
		var r: Dictionary = records[id]
		if r.status != "alive":
			continue
		var actor = sim.entities.get(id)
		if actor == null or not actor.is_alive():
			continue
		r.grace = maxf(0, r.grace - delta)
		actor.position += actor.velocity * delta
		if actor.position.length() > 780:
			actor.position = actor.position.normalized() * 780
			actor.velocity = actor.velocity.bounce(actor.position.normalized())
		if r.grace <= 0:
			_collisions(sim, actor, r)
	remember(sim)
	_flush_fractures(sim)
	_collect_nearby(sim)

func _collisions(sim, rock, r: Dictionary) -> void:
	for ship in sim._members:
		if not rock.is_alive():
			break
		if not ship.is_alive() or not ship.has_tag("combatant") or ship.has_tag("asteroid"):
			continue
		var offset: Vector2 = ship.position - rock.position
		var radius: float = ship.radius + rock.radius
		if offset.length_squared() > radius * radius:
			continue
		var normal := offset.normalized() if offset.length_squared() > 0.0001 else Vector2.RIGHT
		# Separate even during cooldown; overlap cannot repeatedly grind a hull.
		ship.position = rock.position + normal * (radius + 0.5)
		var key: String = rock.entity_id + "|" + ship.entity_id
		if impacts.has(key):
			continue
		impacts[key] = IMPACT_INTERVAL
		sim._damage(ship, 6.0 * r.mass, rock.position, null, "Asteroid impact")
		sim._damage(rock, 3.0 * r.mass, ship.position, null, "Impact")
		rock.velocity -= normal * minf(rock.velocity.dot(normal), 0.0)

func _flush_fractures(sim) -> void:
	var live := 0
	for r: Dictionary in records.values():
		if r.status == "alive":
			live += 1
	for id: String in records.keys():
		var r: Dictionary = records[id]
		if r.status != "pending" or live + 2 > MAX_ROCKS:
			continue
		r.status = "split"
		var mass := int(r.mass) / 2
		var normal := Vector2.from_angle(float((id + "/split").hash() & 0xffff) / 65536.0 * TAU)
		var first := []
		var second := []
		for amount in r.ore:
			first.append(int(amount) / 2)
			second.append(int(amount) - int(amount) / 2)
		for index in range(2):
			var child_id := id + "/%d" % index
			var direction := normal * (-1 if index == 0 else 1)
			var pos := _vec(r.position) + direction * (8.0 * sqrt(mass) + 1)
			var velocity := _vec(r.velocity) + direction * 12.0
			var child := _record(r.root, id, mass, pos, velocity, first if index == 0 else second)
			child.grace = BIRTH_GRACE
			child.known = r.known.duplicate()
			records[child_id] = child
			var actor = sim.add_neutral_target(child_id, mass * 12.0, pos)
			actor.tags["asteroid"] = true
			actor.radius = 8.0 * sqrt(mass)
			actor.stats.collision_radius = actor.radius
			actor.stats.weight = mass
			actor.velocity = velocity
			actor.resource_contents = {"materials": child.ore.duplicate()}
			for team in [0, 1]:
				if child.known[str(team)]:
					sim.abilities.resource_knowledge[team][child_id] = actor.resource_contents.duplicate(true)
		live += 2

func _collect_nearby(sim) -> void:
	if retry_remaining > 0:
		return
	var nearby: Array[String] = []
	for id: String in records:
		var r: Dictionary = records[id]
		if r.status != "terminal" or r.claimed or not recoverable(r):
			continue
		for player in sim.players:
			if player.is_alive() and player.position.distance_to(_vec(r.position)) <= player.radius + 24:
				nearby.append(id)
				break
	if not nearby.is_empty():
		collect_many(nearby, sim)
		if last_commit_failed:
			if not last_replayed_rejection:
				sim.record_pickup_rejection(pickup_key(nearby))
			retry_remaining = 1.0

func recoverable(record: Dictionary) -> bool:
	var policy: Dictionary = roots[record.root].extraction
	return policy.get("rate", 0) > 0 and policy.get("materials", []).any(func(c: Variant) -> bool: return record.ore[int(c)] > 0)

func collect(id: String, sim) -> bool:
	return collect_many([id], sim)

func collect_many(ids: Array[String], sim) -> bool:
	last_commit_failed = false
	last_replayed_rejection = false
	remember(sim)
	var proposal := propose_pickups(ids)
	if proposal.is_empty():
		return false
	var key := pickup_key(ids)
	if replayed_rejections.has(key):
		var command_id: String = replayed_rejections[key]
		replayed_rejections.erase(key)
		sim._record_event("command", {"command_id": command_id, "accepted": true})
		last_replayed_rejection = true
		last_commit_failed = true
		return false
	var next: Dictionary = proposal.field
	var materials: Array = proposal.materials
	if pickup_commit.is_valid() and not pickup_commit.call(key, materials, next):
		last_commit_failed = true
		return false
	records = next.records
	roots = next.roots
	for category in range(4):
		collected[category] += materials[category]
	return true

func propose_pickup(id: String) -> Dictionary:
	return propose_pickups([id])

static func pickup_key(ids: Array[String]) -> String:
	if ids.size() == 1:
		return ids[0]
	var sorted := ids.duplicate()
	sorted.sort()
	return "batch/" + JSON.stringify(sorted).sha256_text()

func propose_pickups(ids: Array[String]) -> Dictionary:
	if ids.is_empty():
		return {}
	var next := snapshot()
	var materials := [0, 0, 0, 0]
	for id: String in ids:
		if not next.records.has(id) or next.records[id].status != "terminal" or next.records[id].claimed:
			return {}
		var r: Dictionary = next.records[id]
		var root: Dictionary = next.roots[r.root]
		r.claimed = true
		for category in range(4):
			root.processed[category] += r.ore[category]
			var rate: float = root.extraction.get("rate", 0.0) if _eligible(root.extraction, category) else 0.0
			var total := floori(root.processed[category] * rate + 0.0000001)
			materials[category] += total - int(root.paid[category])
			root.paid[category] = total
	return {"field": next, "materials": materials}

# First physical rock intersected by a projectile segment, independent of visibility.
func intercept(sim, start: Vector2, finish: Vector2):
	var nearest = null
	var distance := INF
	for id: String in records:
		if records[id].status != "alive":
			continue
		var rock = sim.entities.get(id)
		if rock == null or not rock.is_alive():
			continue
		var point := Geometry2D.get_closest_point_to_segment(rock.position, start, finish)
		var d := start.distance_squared_to(point)
		if point.distance_squared_to(rock.position) <= rock.radius * rock.radius and d < distance:
			nearest = rock
			distance = d
	return nearest

static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _integers(value: Array) -> Array:
	return value.map(func(item: Variant) -> int: return int(item))

static func _eligible(policy: Dictionary, category: int) -> bool:
	for item in policy.get("materials", []):
		if int(item) == category:
			return true
	return false

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and value == floor(value)

static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) and absf(value[0]) <= 100000 and absf(value[1]) <= 100000

static func _ore(value: Variant) -> bool:
	return value is Array and value.size() == 4 and value.all(func(amount: Variant) -> bool: return _integer(amount) and amount >= 0 and amount <= 1000000)
