class_name BattleSimulation
extends RefCounted

signal weapon_fired
signal shield_hit
signal ship_destroyed(is_player: bool)

enum Phase { COMBAT, SALVAGE, VICTORY, DEFEAT, WITHDRAWN }

const ARENA_RADIUS := 800.0
const DROP_CHANCE := 0.6
const SPEED_PER_THRUST := 4.0
const PLAYER_FORMATION_CENTER := Vector2(-420.0, 0.0)
const PLAYER_FORMATION_COLUMNS := 3
const PLAYER_FORMATION_SPACING := Vector2(54.0, 54.0)
const ALIEN_FORMATION_CENTER := Vector2(420.0, 0.0)
const ALIEN_FORMATION_COLUMNS := 6
const ALIEN_FORMATION_SPACING := Vector2(65.0, 65.0)

class Combatant:
	var owned_ship: FleetShip
	var damage_dealt := 0.0
	var damage_taken := 0.0
	var weapon_damage: Dictionary = {}
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var heading := 0.0
	var is_player := false
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
	var shield_flash := 0.0
	var speed := 100.0
	var radius := 18.0
	var wreck_angular_velocity := 0.0

	func is_alive() -> bool:
		return integrity > 0.0

	func shortest_range() -> float:
		var result := INF
		for weapon in stats.weapons:
			if owned_ship != null and owned_ship.units[weapon.component_index].hp <= 0.0:
				continue
			result = minf(result, weapon.range_units)
		return result if result < INF else 220.0

class Projectile:
	var source: Combatant
	var origin := Vector2.ZERO
	var weapon_name := ""
	var position := Vector2.ZERO
	var target: Combatant
	var damage := 0.0
	var is_player := false

class Beam:
	var source: Combatant
	var origin_position := Vector2.ZERO
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
var players: Array[Combatant] = []
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
var allied_drop_chance := 0.3
var laser_upgrade_level := 0
var withdrawing := false
var retreat_remaining := 10.0
var inactive_seconds := 0.0
var _damage_this_step := false


func setup(
	player_stats: ShipStats,
	fleet: Array[RefCounted],
	seed_value: int = -1,
	player_ship_count: int = 1
) -> bool:
	if player_ship_count <= 0:
		push_error("Battle requires at least one player ship.")
		return false
	if not _validate_stats(player_stats) or fleet.is_empty():
		push_error("Battle requires an armed player ship and a nonempty alien fleet.")
		return false
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	withdrawing = false
	retreat_remaining = 10.0
	inactive_seconds = 0.0
	phase = Phase.COMBAT
	elapsed = 0.0
	_salvage_target = null
	players.clear()
	aliens.clear()
	projectiles.clear()
	beams.clear()
	drops.clear()
	explosions.clear()
	collected_categories.clear()
	for index in range(player_ship_count):
		var player_ship := _create_combatant(player_stats)
		player_ship.is_player = true
		player_ship.position = _get_formation_position(
			index,
			player_ship_count,
			PLAYER_FORMATION_COLUMNS,
			PLAYER_FORMATION_CENTER,
			PLAYER_FORMATION_SPACING
		)
		players.append(player_ship)
	player = players[0]
	for index in range(fleet.size()):
		var definition := fleet[index] as AlienShip
		if definition == null:
			push_error("Battle fleet contains an invalid alien definition.")
			return false
		if not _validate_stats(definition.stats):
			return false
		var alien := _create_combatant(definition.stats)
		alien.alien = definition
		alien.position = _get_formation_position(
			index,
			fleet.size(),
			ALIEN_FORMATION_COLUMNS,
			ALIEN_FORMATION_CENTER,
			ALIEN_FORMATION_SPACING
		)
		alien.heading = PI
		alien.radius = 14.0
		aliens.append(alien)
	return true


func setup_owned(ships: Array[FleetShip], fleet: Array[RefCounted], salvage_chance: float, upgrade_level: int, seed_value: int = -1) -> bool:
	if ships.is_empty():
		return false
	# Use an armed member for legacy setup validation; disabled weapons may remain
	# aboard other surviving ships in the deployment.
	var armed: FleetShip
	for owned in ships:
		if not owned.get_stats(upgrade_level).weapons.is_empty():
			armed = owned
	if armed == null or not setup(armed.get_stats(upgrade_level), fleet, seed_value, ships.size()):
		return false
	allied_drop_chance = salvage_chance
	laser_upgrade_level = upgrade_level
	var formation_center := Vector2.ZERO
	for owned in ships:
		formation_center += Vector2(owned.formation)
	formation_center /= float(ships.size())
	for index in range(ships.size()):
		var member := players[index]
		member.owned_ship = ships[index]
		member.stats = ships[index].get_stats(upgrade_level)
		member.integrity = member.stats.integrity
		member.shields = member.stats.shields
		member.speed = member.stats.thrust * SPEED_PER_THRUST
		member.cooldowns.clear()
		for weapon in member.stats.weapons:
			member.cooldowns.append(0.0)
			member.weapon_damage[weapon.weapon_name] = 0.0
		member.position = PLAYER_FORMATION_CENTER + (Vector2(ships[index].formation) - formation_center) * 65.0
	return true


func _get_formation_position(
	index: int,
	count: int,
	max_columns: int,
	center: Vector2,
	spacing: Vector2
) -> Vector2:
	var columns := mini(count, max_columns)
	var rows := ceili(float(count) / float(columns))
	var column := index % columns
	var row := floori(float(index) / float(columns))
	return center + Vector2(
		(float(column) - float(columns - 1) * 0.5) * spacing.x,
		(float(row) - float(rows - 1) * 0.5) * spacing.y
	)


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
	ship.speed = maxf(stats.thrust, 0.0) * SPEED_PER_THRUST
	for weapon in stats.weapons:
		ship.cooldowns.append(0.0)
	return ship


func advance(delta: float) -> void:
	elapsed += delta
	_update_shield_flashes(delta)
	_update_wrecks(delta)
	for index in range(beams.size() - 1, -1, -1):
		beams[index].lifetime -= delta
		if beams[index].lifetime <= 0.0:
			beams.remove_at(index)
	for index in range(explosions.size() - 1, -1, -1):
		explosions[index].lifetime -= delta
		if explosions[index].lifetime <= 0.0:
			explosions.remove_at(index)
	if phase == Phase.COMBAT:
		_damage_this_step = false
		var velocities: Array[Vector2] = []
		var members: Array[Combatant] = []
		members.append_array(players)
		members.append_array(aliens)
		for member in members:
			velocities.append(member.velocity)
		for player_ship in players:
			if player_ship.is_alive():
				_update_ship(player_ship, delta)
		for alien in aliens:
			if alien.is_alive():
				_update_ship(alien, delta)
		_update_projectiles(delta)
		var accelerating := false
		for index in range(members.size()):
			if members[index].is_alive() and members[index].velocity.distance_to(velocities[index]) > 0.01 * delta:
				accelerating = true
		inactive_seconds = 0.0 if _damage_this_step or accelerating else inactive_seconds + delta
		if withdrawing:
			retreat_remaining -= delta
		if living_player_count() == 0:
			phase = Phase.DEFEAT
		elif (withdrawing and retreat_remaining <= 0.0) or inactive_seconds >= 10.0:
			phase = Phase.WITHDRAWN
		elif living_alien_count() == 0 and projectiles.is_empty():
			phase = Phase.SALVAGE
	elif phase == Phase.SALVAGE:
		if withdrawing:
			retreat_remaining -= delta
			for member in players:
				if member.is_alive():
					member.heading = rotate_toward(member.heading, PI, delta * 1.5)
					member.velocity = member.velocity.move_toward(Vector2.from_angle(member.heading) * member.speed, member.speed * 2.0 * delta)
					member.position += member.velocity * delta
			if retreat_remaining <= 0.0:
				phase = Phase.WITHDRAWN
			return
		_collect_salvage(delta)


func _update_wrecks(delta: float) -> void:
	var members: Array[Combatant] = []
	members.append_array(players)
	members.append_array(aliens)
	for member in members:
		if member.is_alive():
			continue
		member.position += member.velocity * delta
		member.heading = wrapf(
			member.heading + member.wreck_angular_velocity * delta,
			-PI,
			PI
		)


func _update_shield_flashes(delta: float) -> void:
	for member in players:
		member.shield_flash = maxf(0.0, member.shield_flash - delta)
	for member in aliens:
		member.shield_flash = maxf(0.0, member.shield_flash - delta)


func living_alien_count() -> int:
	var count := 0
	for alien in aliens:
		if alien.is_alive():
			count += 1
	return count


func living_player_count() -> int:
	var count := 0
	for player_ship in players:
		if player_ship.is_alive():
			count += 1
	return count


func _choose_target(ship: Combatant) -> Combatant:
	var enemies: Array[Combatant] = []
	if ship.is_player:
		enemies = aliens
	else:
		enemies = players
	var best: Combatant
	var best_score := INF
	for enemy in enemies:
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
	var desired_distance := ship.shortest_range() * 0.92 if not ship.stats.weapons.is_empty() else 220.0
	var radial_speed := clampf((distance - desired_distance) * 2.5, -ship.speed, ship.speed)
	if ship.retreat_time > 0.0:
		radial_speed = -ship.speed
	var desired := direction * radial_speed
	desired += direction.orthogonal() * ship.speed * 0.24
	var neighbors: Array[Combatant] = []
	neighbors.append_array(players)
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
	if withdrawing and ship.is_player:
		direction = -direction
		desired = direction * ship.speed
	ship.heading = rotate_toward(ship.heading, direction.angle(), delta * 1.5)
	# Reverse thrust is one fifth of forward thrust in the ship's local frame.
	var forward := Vector2.from_angle(ship.heading)
	var lateral := forward.orthogonal()
	var forward_speed := clampf(desired.dot(forward), -ship.speed * 0.2, ship.speed)
	desired = forward * forward_speed + lateral * desired.dot(lateral)
	ship.velocity = ship.velocity.move_toward(desired.limit_length(ship.speed), ship.speed * 2.0 * delta)
	# Enforce the reverse cap even while braking or rotating.
	var reverse := ship.velocity.dot(forward)
	if reverse < -ship.speed * 0.2:
		ship.velocity += forward * (-ship.speed * 0.2 - reverse)
	ship.position = (ship.position + ship.velocity * delta).limit_length(ARENA_RADIUS)
	for index in range(ship.stats.weapons.size()):
		var weapon := ship.stats.weapons[index]
		if ship.owned_ship != null and ship.owned_ship.units[weapon.component_index].hp <= 0.0:
			continue
		ship.cooldowns[index] = maxf(0.0, ship.cooldowns[index] - delta)
		if ship.cooldowns[index] > 0.0:
			continue
		var weapon_origin := _get_weapon_origin(ship, weapon)
		if weapon_origin.distance_to(ship.target.position) > weapon.range_units:
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
			if weapon_origin.distance_to(ship.target.position) > weapon.range_units:
				break
			if shot_index == 0:
				weapon_fired.emit()
			if ship.is_player and not weapon.is_projectile_weapon:
				var beam := Beam.new()
				beam.source = ship
				beam.origin_position = weapon_origin
				beam.target = ship.target
				beams.append(beam)
				_damage(ship.target, weapon.damage_per_shot, weapon_origin, ship, weapon.weapon_name)
			else:
				var projectile := Projectile.new()
				projectile.source = ship
				projectile.origin = weapon_origin
				projectile.weapon_name = weapon.weapon_name
				projectile.position = weapon_origin
				projectile.target = ship.target
				projectile.damage = weapon.damage_per_shot
				projectile.is_player = ship.is_player
				projectiles.append(projectile)


func _get_weapon_origin(ship: Combatant, weapon: ShipWeaponStats) -> Vector2:
	return ship.position + weapon.mount_offset.rotated(ship.heading)


func _update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		if not projectile.target.is_alive():
			projectiles.remove_at(index)
			continue
		var destination := projectile.target.position
		projectile.position = projectile.position.move_toward(destination, 320.0 * delta)
		if projectile.position.distance_to(destination) <= projectile.target.radius:
			_damage(projectile.target, projectile.damage, projectile.origin, projectile.source, projectile.weapon_name)
			projectiles.remove_at(index)


func _damage(target: Combatant, damage: float, origin: Vector2 = Vector2.ZERO, source: Combatant = null, weapon_name: String = "") -> void:
	if not target.is_alive():
		return
	var absorbed := minf(target.shields, damage)
	target.shields -= absorbed
	var actual := absorbed
	if target.owned_ship != null and damage > absorbed:
		var owned := target.owned_ship
		var local_origin := (origin - target.position).rotated(-target.heading)
		var cell := owned.hit_cell(local_origin, random)
		var result := owned.damage_cell(cell, damage - absorbed)
		actual += result.damage
		for removed_cell in result.removed:
			if random.randf() < allied_drop_chance:
				var drop := Drop.new()
				drop.category = owned.design.tiles[removed_cell]
				drop.position = target.position + owned.local_cell_position(removed_cell).rotated(target.heading)
				drops.append(drop)
		var remaining := owned.get_stats(laser_upgrade_level)
		target.integrity = remaining.integrity if owned.is_alive() else 0.0
		target.stats.shields = remaining.shields
		target.stats.thrust = remaining.thrust
		target.shields = minf(target.shields, remaining.shields)
		target.speed = remaining.thrust * SPEED_PER_THRUST
	else:
		var hull_damage := minf(target.integrity, damage - absorbed)
		target.integrity -= hull_damage
		actual += hull_damage
	if actual > 0.0:
		_damage_this_step = true
	target.damage_taken += actual
	if source != null:
		source.damage_dealt += actual
		source.weapon_damage[weapon_name] = source.weapon_damage.get(weapon_name, 0.0) + actual
	target.since_damage = 0.0
	if absorbed > 0.0:
		target.shield_flash = 0.2
		shield_hit.emit()
	if target.is_alive():
		return
	if target.velocity.length_squared() < 1.0:
		target.velocity = Vector2.from_angle(random.randf_range(0.0, TAU)) * random.randf_range(8.0, 20.0)
	target.wreck_angular_velocity = random.randf_range(-0.45, 0.45)
	if absf(target.wreck_angular_velocity) < 0.12:
		target.wreck_angular_velocity = 0.12 if target.wreck_angular_velocity >= 0.0 else -0.12
	var explosion := Explosion.new()
	explosion.position = target.position
	explosions.append(explosion)
	ship_destroyed.emit(target.is_player)
	if not target.is_player and random.randf() < DROP_CHANCE:
		var drop := Drop.new()
		drop.position = target.position
		var roll := random.randf()
		if roll < 0.60:
			drop.category = ShipPart.Category.DEFENSE
		elif roll < 0.84:
			drop.category = ShipPart.Category.OFFENSE
		elif roll < 0.96:
			drop.category = ShipPart.Category.SPECIAL
		else:
			drop.category = ShipPart.Category.CORE
		drops.append(drop)


func _collect_salvage(delta: float) -> void:
	collected_categories.append(drops)
	phase = Phase.VICTORY


func get_living_player() -> Combatant:
	if player != null and player.is_alive():
		return player
	for player_ship in players:
		if player_ship.is_alive():
			return player_ship
	return null


func request_withdrawal() -> void:
	if phase in [Phase.COMBAT, Phase.SALVAGE] and not withdrawing:
		withdrawing = true
		retreat_remaining = 10.0
