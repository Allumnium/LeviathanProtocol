class_name ResearchUpgrades
extends RefCounted

static func value(modifiers: Dictionary, key: String, fallback := 1.0) -> float:
	return float(modifiers.get(key, {}).get("value", fallback))

static func part_value(ship: FleetShip, part: ShipPart, capability: String, key: String, fallback := 1.0) -> float:
	if ship is HangarShip and capability in capabilities(part):
		return value(ship.research_modifiers, key, fallback)
	return fallback

static func capabilities(part: ShipPart) -> Array:
	if part == null:
		return []
	return part.stats.research_capabilities if part.stats != null else []

static func ship_matches(ship: FleetShip, targets: Array) -> bool:
	if not ship is HangarShip or not ship.is_alive():
		return false
	if "passive_repair" in targets and float(ship.chassis.get("self_repair_hp_per_second", 0)) > 0:
		return true
	for unit: Dictionary in ship.units:
		if unit.hp <= 0:
			continue
		for capability: String in capabilities(unit.part):
			if capability in targets:
				return true
	return false

static func matches(id: String, deployed: Array[FleetShip]) -> bool:
	var targets: Array = GameDefinitions.find("research", id).get("equipment_capabilities_any", [])
	return targets.is_empty() or deployed.any(func(ship: FleetShip) -> bool: return ship_matches(ship, targets))

static func requirement(id: String) -> String:
	var names := {"laser": "lasers", "prismatic": "compatible lasers", "ion": "an Ion Emitter",
		"guided_missile": "guided missiles", "splitting_missile": "splitting missiles", "railgun": "railguns",
		"carrier": "a flight deck", "shield": "shields", "passive_repair": "passive hull repair",
		"repair_aura": "a Repair Drone Hangar", "command": "a Command Uplink",
		"synchronization": "a Tactical Computer", "research": "a research lab"}
	var labels: Array[String] = []
	for capability: String in GameDefinitions.find("research", id).get("equipment_capabilities_any", []):
		labels.append(names.get(capability, capability))
	return "Deploy " + " or ".join(labels) + "." if not labels.is_empty() else ""

static func apply_weapon(weapon: ShipWeaponStats, modifiers: Dictionary) -> void:
	if "laser" in weapon.research_capabilities:
		weapon.damage_per_shot *= value(modifiers, "laser_damage_multiplier")
		weapon.range_units *= value(modifiers, "laser_range_multiplier")
	if "guided_missile" in weapon.research_capabilities:
		weapon.range_units *= value(modifiers, "missile_range_multiplier")
	if "railgun" in weapon.research_capabilities:
		weapon.hull_damage_multiplier = value(modifiers, "railgun_hull_multiplier")
