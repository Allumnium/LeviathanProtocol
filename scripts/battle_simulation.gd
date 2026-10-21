class_name BattleSimulation
extends RefCounted

enum Phase { COMBAT, SALVAGE, VICTORY, DEFEAT }

const ARENA_RADIUS := 800.0
const DROP_CHANCE := 0.6

class Combatant:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var heading := 0.0
	var stats: ShipStats
	var integrity := 0.0
	var shields := 0.0
	var alien: AlienShip
	var cooldowns: Array[float] = []
	var _target: WeakRef
	var target: Combatant:
		get:
			return _target.get_ref() as Combatant if _target != null else null
		set(value):
			_target = weakref(value) if value != null else null
	var retreat_time := 0.0
	var retreat_cooldown := 0.0
	var since_damage := 0.0
	var hit_flash := 0.0
	var speed := 100.0
	var radius := 18.0

	func is_alive() -> bool:
		return integrity > 0.0

	func shortest_range() -> float:
		var result := INF
		for weapon in stats.weapons:
			result = minf(result, weapon.range_units)
		return result

class Projectile:
	var position := Vector2.ZERO
	var target: Combatant
	var damage := 0.0

class Beam:
	var source: Combatant
	var target: Combatant
	var lifetime := 0.16

class Drop:
	var position := Vector2.ZERO
	var category := ShipPart.Category.DEFENSE
	var collected := false

class Explosion:
	var position := Vector2.ZERO
	var lifetime := 0.6

var player: Combatant
var aliens: Array[Combatant] = []
var projectiles: Array[Projectile] = []
var beams: Array[Beam] = []
var drops: Array[Drop] = []
var explosions: Array[Explosion] = []
var collected_categories: Array[int] = []
var phase := Phase.COMBAT
var elapsed := 0.0
var random := RandomNumberGenerator.new()
var _salvage_target: Drop


func setup(player_stats: ShipStats, fleet: Array[RefCounted], seed_value: int = -1) -> bool:
	if not _validate_stats(player_stats) or fleet.is_empty():
		push_error("Battle requires an armed player ship and a nonempty alien fleet.")
		return false
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	player = _create_combatant(player_stats)
	player.position = Vector2(-240.0, 0.0)
	for index in range(fleet.size()):
		var definition := fleet[index] as AlienShip
		if definition == null:
			push_error("Battle fleet contains an invalid alien definition.")
			return false
		if not _validate_stats(definition.stats):
			return false
		var alien := _create_combatant(definition.stats)
		alien.alien = definition
		alien.position = Vector2(160.0 + float(index % 3) * 65.0,
			(float(index) - float(fleet.size() - 1) * 0.5) * 52.0)
		alien.heading = PI
		alien.speed = clampf(42.0 + definition.stats.thrust, 46.0, 68.0)
		alien.radius = 14.0
		aliens.append(alien)
	return true


func _validate_stats(stats: ShipStats) -> bool:
	if stats == null or stats.integrity <= 0.0 or stats.weapons.is_empty():
		push_error("A combat ship requires positive integrity and working weapons.")
		return false
	for weapon in stats.weapons:
		if (
			weapon.fire_interval_seconds <= 0.0 or weapon.range_units <= 0.0
			or weapon.damage_per_shot <= 0.0 or weapon.projectiles_per_activation <= 0
		):
			push_error("Battle weapons require positive intervals, ranges, damage and projectile counts.")
			return false
	return true


func _create_combatant(stats: ShipStats) -> Combatant:
	var ship := Combatant.new()
	ship.stats = stats
	ship.integrity = stats.integrity
	ship.shields = stats.shields
	ship.speed = clampf(95.0 + stats.thrust / maxf(stats.weight, 1.0) * 12.0, 95.0, 140.0)
	for weapon in stats.weapons:
		ship.cooldowns.append(0.0)
	return ship


func advance(delta: float) -> void:
	elapsed += delta
	for index in range(beams.size() - 1, -1, -1):
		beams[index].lifetime -= delta
		if beams[index].lifetime <= 0.0:
			beams.remove_at(index)
	for index in range(explosions.size() - 1, -1, -1):
		explosions[index].lifetime -= delta
		if explosions[index].lifetime <= 0.0:
			explosions.remove_at(index)
	if phase == Phase.COMBAT:
		_update_ship(player, delta)
		for alien in aliens:
			if alien.is_alive():
				_update_ship(alien, delta)
		_update_projectiles(delta)
		if not player.is_alive():
			phase = Phase.DEFEAT
		elif living_alien_count() == 0 and projectiles.is_empty():
			phase = Phase.SALVAGE
	elif phase == Phase.SALVAGE:
		_collect_salvage(delta)


func living_alien_count() -> int:
	var count := 0
	for alien in aliens:
		if alien.is_alive():
			count += 1
	return count


func _choose_target(ship: Combatant) -> Combatant:
	if ship != player:
		return player if player.is_alive() else null
	var best: Combatant
	var best_score := INF
	for enemy in aliens:
		if not enemy.is_alive():
			continue
		var score := enemy.integrity + enemy.shields
		if ship.position.distance_to(enemy.position) > ship.shortest_range():
			score += 1000.0
		if score < best_score:
			best = enemy
			best_score = score
	return best


func _update_ship(ship: Combatant, delta: float) -> void:
	if not ship.is_alive():
		return
	ship.since_damage += delta
	ship.hit_flash = maxf(0.0, ship.hit_flash - delta)
	ship.retreat_time = maxf(0.0, ship.retreat_time - delta)
	ship.retreat_cooldown = maxf(0.0, ship.retreat_cooldown - delta)
	if ship.since_damage > 2.5:
		ship.shields = minf(ship.stats.shields, ship.shields + ship.stats.shields * 0.12 * delta)
	if ship.stats.shields > 0.0 and ship.shields <= ship.stats.shields * 0.2:
		if ship.retreat_cooldown <= 0.0:
			ship.retreat_time = 2.5
			ship.retreat_cooldown = 9.0
	ship.target = _choose_target(ship)
	if ship.target == null:
		return
	var offset := ship.target.position - ship.position
	var distance := offset.length()
	var direction := offset.normalized()
	var desired_distance := ship.shortest_range() * 0.92
	var radial_speed := clampf((distance - desired_distance) * 2.5, -ship.speed, ship.speed)
	if ship.retreat_time > 0.0:
		radial_speed = -ship.speed
	var desired := direction * radial_speed
	desired += direction.orthogonal() * ship.speed * 0.24
	var neighbors: Array[Combatant] = [player]
	neighbors.append_array(aliens)
	for other in neighbors:
		if other == ship or not other.is_alive():
			continue
		var separation := ship.position - other.position
		var clearance := ship.radius + other.radius + 12.0
		if separation.length() < clearance:
			if separation.is_zero_approx():
				separation = Vector2.UP
			desired += separation.normalized() * ship.speed * (1.0 - separation.length() / clearance)
	if ship.position.length() > ARENA_RADIUS - 90.0:
		desired -= ship.position.normalized() * ship.speed
	ship.velocity = ship.velocity.move_toward(desired.limit_length(ship.speed), ship.speed * 3.0 * delta)
	ship.position = (ship.position + ship.velocity * delta).limit_length(ARENA_RADIUS)
	ship.heading = lerp_angle(ship.heading, direction.angle(), minf(delta * 5.0, 1.0))
	for index in range(ship.stats.weapons.size()):
		var weapon := ship.stats.weapons[index]
		ship.cooldowns[index] = maxf(0.0, ship.cooldowns[index] - delta)
		if ship.cooldowns[index] > 0.0:
			continue
		if ship.position.distance_to(ship.target.position) > weapon.range_units:
			continue
		if not ship.target.is_alive():
			ship.target = _choose_target(ship)
		if ship.target == null:
			break
		ship.cooldowns[index] = weapon.fire_interval_seconds
		for shot_index in range(weapon.projectiles_per_activation):
			if not ship.target.is_alive():
				ship.target = _choose_target(ship)
			if ship.target == null:
				break
			if ship.position.distance_to(ship.target.position) > weapon.range_units:
				break
			if ship == player:
				var beam := Beam.new()
				beam.source = ship
				beam.target = ship.target
				beams.append(beam)
				_damage(ship.target, weapon.damage_per_shot)
			else:
				var projectile := Projectile.new()
				projectile.position = ship.position
				projectile.target = ship.target
				projectile.damage = weapon.damage_per_shot
				projectiles.append(projectile)


func _update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		if not projectile.target.is_alive():
			projectiles.remove_at(index)
			continue
		var destination := projectile.target.position
		projectile.position = projectile.position.move_toward(destination, 320.0 * delta)
		if projectile.position.distance_to(destination) <= projectile.target.radius:
			_damage(projectile.target, projectile.damage)
			projectiles.remove_at(index)


func _damage(target: Combatant, damage: float) -> void:
	var absorbed := minf(target.shields, damage)
	target.shields -= absorbed
	target.integrity = maxf(0.0, target.integrity - (damage - absorbed))
	target.since_damage = 0.0
	target.hit_flash = 0.12
	if target.is_alive():
		return
	var explosion := Explosion.new()
	explosion.position = target.position
	explosions.append(explosion)
	if target != player and random.randf() < DROP_CHANCE:
		var drop := Drop.new()
		drop.position = target.position
		var roll := random.randf()
		if roll < 0.65:
			drop.category = ShipPart.Category.DEFENSE
		elif roll < 0.9:
			drop.category = ShipPart.Category.OFFENSE
		else:
			drop.category = ShipPart.Category.SPECIAL
		drops.append(drop)


func _collect_salvage(delta: float) -> void:
	if _salvage_target == null or _salvage_target.collected:
		_salvage_target = null
		var nearest := INF
		for drop in drops:
			var distance := player.position.distance_to(drop.position)
			if not drop.collected and distance < nearest:
				nearest = distance
				_salvage_target = drop
	if _salvage_target == null:
		phase = Phase.VICTORY
		player.velocity = Vector2.ZERO
		return
	var direction := _salvage_target.position - player.position
	player.heading = lerp_angle(player.heading, direction.angle(), minf(delta * 6.0, 1.0))
	var previous := player.position
	player.position = player.position.move_toward(_salvage_target.position, player.speed * 1.7 * delta)
	player.velocity = (player.position - previous) / delta
	if player.position.distance_to(_salvage_target.position) <= 5.0:
		_salvage_target.collected = true
		collected_categories.append(_salvage_target.category)
