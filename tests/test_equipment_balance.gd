extends SceneTree

var checks := 0
var failures := 0
var rows: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

# Add compatible fixture mounts without changing authored player chassis.
func owned(parts: Array, id := 1, research: Array = []) -> HangarShip:
	var result := HangarShip.new()
	result.initialize_chassis("corsair", id, id == 1)
	var fitted := parts.duplicate()
	if fitted.all(func(key: String) -> bool: return SlotCatalog.find_equipment(key).stats.weapons.is_empty()):
		fitted.append("mini_turret") # Combat setup requires a fleet with a weapon.
	for item_id: String in fitted:
		var item := SlotCatalog.find_equipment(item_id)
		var slot := "fixture_%d" % result.mounts.size()
		result.chassis.slots.append({"id": slot, "type": item.type, "size": item.size, "rect": [240, 240, 32, 32]})
		result.mounts[slot] = {"uid": "%d-%d" % [id, result.mounts.size()], "equipment_id": item_id, "rank": 1}
	result.rebuild_units()
	result.hull_hp = result.hull_max
	result.research_modifiers = ResearchRules.resolve(["foundation"] + research, HangarResearch.catalog()).modifiers
	return result

func alien(role := "fighter", shields := 0.0) -> AlienShip:
	var stats := ShipStats.new()
	stats.integrity = 100000
	stats.shields = shields
	stats.weight = 10
	stats.collision_radius = 12
	stats.weapons.append(ShipWeaponStats.new("Target", 100, 0.01, 1, 1))
	var result := AlienShip.new("Balance target", AlienShip.SCOUT_TEXTURE, stats)
	result.role_id = role
	return result

func setup(fleet: Array[FleetShip], shields := 0.0, cover := false, effects: Dictionary = {}) -> BattleSimulation:
	var sim := BattleSimulation.new()
	var enemies: Array[RefCounted] = [alien("fighter", shields)]
	if cover:
		enemies.append(alien("sentinel"))
	check(sim.setup_owned(fleet, enemies, 0, 0, 9401,
		{"credits_only": true, "missiles": 30, "enemy_roles": cover, "research_effects": effects}), "Configure bounded equipment fixture")
	for index in range(sim.players.size()):
		sim.players[index].position = Vector2(0, index * 10)
		sim.players[index].speed = 0
		sim.players[index].acceleration = 0
		sim.players[index].heading = 0
	for index in range(sim.aliens.size()):
		sim.aliens[index].position = Vector2(150, index * 80)
		sim.aliens[index].speed = 0
		sim.aliens[index].acceleration = 0
	sim.player.commanded_target = sim.aliens[0]
	return sim

func marks() -> void:
	for copies in [1, 2]:
		for researched in [false, true]:
			var parts: Array = ["command_uplink"] if copies == 1 else ["command_uplink", "command_uplink"]
			var host := owned(parts, 1, ["command_i"] if researched else [])
			var sim := setup([host])
			sim.doctrines._mark(sim, sim.player, 0)
			var expected: float = 1.0 + copies * (0.3 if researched else 0.2)
			check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), expected), "Copies add mark strength with and without research")
			sim._damage(sim.aliens[0], 10, Vector2.ZERO, sim.player, "Probe")
			check(is_equal_approx(sim.player.damage_dealt, expected * 10), "Actual allied hit uses additive mark strength")
			sim.doctrines.advance(sim, 5.01)
			check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1), "Mark expiration removes all copy contributions")
	var first := owned(["command_uplink", "command_uplink"])
	var second := owned(["command_uplink"], 2, ["command_i"])
	var sim := setup([first, second])
	for member in sim.players:
		sim.doctrines._mark(sim, member, 0)
	check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1.7), "Overlapping allied hosts add contributions instead of multiplying or taking the first")
	sim._damage(sim.aliens[0], 10, Vector2.ZERO, sim.players[1], "Probe")
	check(is_equal_approx(sim.players[1].damage_dealt, 17), "Another allied attacker benefits from the complete shared mark")
	sim.players[1].faction = BattleSimulation.Faction.ALIEN
	check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1.4), "Enemy marks do not amplify allied attacks")
	sim.players[1].faction = BattleSimulation.Faction.PLAYER
	second.hull_hp = 0
	check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1.7), "Zero-hull living host still contributes")
	second.hull_hp = -0.01
	check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1.4), "Destroyed host immediately stops contributing")
	var indices := CombatDoctrines.operational(sim.player, ShipPart.Type.COMMAND_UPLINK).duplicate()
	first.units[indices[0]].hp = 0
	sim._refresh_owned_stats(sim.player)
	check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1.2), "Refreshing lost support copies removes only their contribution")
	first.units[indices[1]].hp = 0
	sim._refresh_owned_stats(sim.player)
	check(is_equal_approx(sim.doctrines.mark_multiplier(sim, sim.player, sim.aliens[0]), 1), "No active uplinks means no remaining amplification")

func relays() -> void:
	for copies in [1, 2]:
		var parts: Array = ["shield_generator", "shield_relay"]
		if copies == 2:
			parts.append("shield_relay")
		var sim := setup([owned(parts), owned(["shield_generator"], 2)])
		var donor := sim.player
		var receiver := sim.players[1]
		donor.shields = donor.stats.shields
		var total := donor.shields
		receiver.shields = 0
		sim.doctrines._relay(sim, donor, 1)
		check(is_equal_approx(donor.stats.shields, 20 + 10 * copies), "Each relay adds ten shields alongside a shield generator")
		check(is_equal_approx(receiver.shields, 2 * copies) and is_equal_approx(donor.shields + receiver.shields, total), "Relay copies add transfer rate and conserve shields")
		sim.doctrines._relay(sim, donor, 100)
		check(is_equal_approx(receiver.shields / receiver.stats.shields, donor.shields / donor.stats.shields)
			and is_equal_approx(donor.shields + receiver.shields, total), "Large transfer step stops at equal fractions and conserves shields")
		receiver.shields = receiver.stats.shields
		var before := donor.shields
		sim.doctrines._relay(sim, donor, 1)
		check(donor.shields == before and receiver.shields == 20, "Full recipients are never overfilled")
		donor.shields = 0
		receiver.shields = 0
		sim.doctrines._relay(sim, donor, 1)
		check(receiver.shields == 0, "Empty donor cannot generate shields")
		donor.shields = 20
		receiver.position = Vector2(181, 0)
		sim.doctrines._relay(sim, donor, 1)
		check(receiver.shields == 0, "Transfer stays inside the existing 180 range")
	var sim := setup([owned(["shield_relay"]), owned(["shield_generator"], 2)])
	sim.players[1].shields = 0
	sim.doctrines._relay(sim, sim.player, 1)
	check(sim.player.stats.shields == 10 and is_equal_approx(sim.players[1].shields, 2)
		and is_equal_approx(sim.player.shields, 8), "Relay supplies and transfers its own shield pool without a generator")
	sim.player.shields = 0
	sim.players[1].shields = 0
	sim.player.since_damage = 4
	sim._update_ship(sim.player, 1)
	check(is_equal_approx(sim.player.shields, 0.4), "Relay shields use normal four-percent recharge after the existing delay")
	sim.doctrines._relay(sim, sim.player, 1)
	check(sim.players[1].shields > 0 and is_equal_approx(sim.player.shields + sim.players[1].shields, 0.4), "Recovered shields become transferable without creating extra energy")
	sim = setup([owned(["shield_generator", "shield_relay"]), owned([], 2)])
	sim.doctrines._relay(sim, sim.player, 1)
	check(sim.players[1].shields == 0, "Recipient without shield capacity receives nothing")

func sample(item: String, profile: String, old_damage := -1.0, research: Array = []) -> Dictionary:
	var effects := {"splinter_missiles": true} if "siege_i" in research else {}
	var sim := setup([owned([item], 1, research)], 100000.0 if profile == "shielded" else 0.0, profile == "protected", effects)
	if old_damage > 0:
		sim.player.stats.weapons[0].damage_per_shot = old_damage
	var target := sim.aliens[0]
	for tick in range(360):
		var delta := 1.0 / 30
		sim.elapsed += delta
		if profile == "moving":
			target.position = Vector2(150, sin(sim.elapsed * 2) * 60)
		sim.research_combat.begin_step(sim, delta)
		sim._update_ship(sim.player, delta)
		sim.doctrines.advance(sim, delta)
		sim._update_projectiles(delta)
		sim.research_combat.end_step(sim)
	var row := {"weapon": item, "profile": profile, "old_damage": old_damage, "research": research,
		"seconds": 12, "damage": sim.player.damage_dealt, "shield_damage": target.shield_damage_taken,
		"hull_damage": 100000.0 - target.integrity, "missiles_spent": 30 - sim.missile_supply,
		"activations": sim.event_log.filter(func(entry: Dictionary) -> bool: return entry.type == "expenditure").size(),
		"impacts": sim.event_log.filter(func(entry: Dictionary) -> bool: return entry.type == "beam_impact").size()}
	rows.append(row)
	return row

func weapons() -> void:
	for item: String in ["ion_emitter", "missile_rack", "beam_lance"]:
		for profile: String in ["stationary", "shielded", "moving", "protected"]:
			var old_hit: float = {"ion_emitter": 2.0, "missile_rack": 3.0, "beam_lance": 12.0}[item]
			var before := sample(item, profile, old_hit)
			var after := sample(item, profile)
			check(before.activations > 0 and before.activations == after.activations, "Tuning preserves actual firing cadence: " + item + "/" + profile)
			check(is_equal_approx(after.damage, before.damage * 4), "Approved damage change is realized through actual hits: " + item + "/" + profile)
			check(before.missiles_spent == after.missiles_spent, "Tuning never changes ammunition spending")
			if item == "missile_rack":
				check(after.missiles_spent == after.activations * 3 and after.missiles_spent > 0, "Each three-shot salvo spends exactly three missiles")
			if item == "beam_lance":
				check(after.impacts > 0 if profile != "moving" else after.impacts < after.activations, "Lance charge hits stationary targets and can miss movers")
	for item: String in ["double_laser", "railgun"]:
		for profile: String in ["stationary", "shielded", "moving", "protected"]:
			sample(item, profile)
	var ion := setup([owned(["ion_emitter"])], 6)
	ion._update_ship(ion.player, 0.01)
	check(ion.aliens[0].shields == 0 and is_equal_approx(ion.player.damage_dealt, 8.5), "Ion shield-breaking overflow keeps the existing reduced hull damage")
	var split := sample("missile_rack", "stationary", -1, ["guided_munitions", "siege_i", "siege_ii"])
	var plain := sample("missile_rack", "stationary")
	check(is_equal_approx(split.damage, plain.damage * 1.8) and split.missiles_spent == plain.missiles_spent, "Researched fragments improve damage without extra ammunition")
	var lance := sample("beam_lance", "stationary", -1, ["applied_energy", "optics_ii"])
	var base := sample("beam_lance", "stationary")
	check(is_equal_approx(lance.damage, base.damage * 1.15), "Lance gains its laser research damage once")
	var intercepted := setup([owned(["missile_rack"])])
	intercepted._update_ship(intercepted.player, 0.01)
	var defender := intercepted.aliens[0]
	defender.tags["interceptor"] = true
	var defense := ShipWeaponStats.new("Interception", 1, 1, 1, 500)
	check(SharedSupport.intercept(intercepted, defender, defense, defender.position) and intercepted.projectiles.size() == 2
		and intercepted.missile_supply == 27, "Stronger missiles remain interceptable without refunding spent ammunition")

func run() -> void:
	marks()
	relays()
	if not "--support-only" in OS.get_cmdline_user_args():
		weapons()
	var file := FileAccess.open("user://equipment-comparison.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	print("EQUIPMENT BALANCE: %d checks, %d failures; %d bounded 12-second samples" % [checks, failures, rows.size()])
	quit(1 if failures else 0)
