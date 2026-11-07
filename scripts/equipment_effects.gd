extends RefCounted

# Descriptions compose engine behavior parameters with the same fitted stats
# and earned modifiers used in combat. No equipment-name overrides.
static func describe(item: Dictionary, modifiers: Dictionary) -> String:
	if item.has("load_kind"):
		return "%d %s" % [item.load_capacity, item.load_kind]
	match int(item.part_type):
		ShipPart.Type.RESEARCH_LAB:
			return "%s RP/day" % ScienceRules.format_rp(float(item.rank) * ResearchUpgrades.value(modifiers, "research_output_multiplier"))
		ShipPart.Type.AMMUNITION_MAGAZINE:
			return "+%s%% weapon cycling" % number(float(parameters("ammunition_cycle").bonus) * 100)
		ShipPart.Type.TACTICAL_COMPUTER:
			return "Cooldown reset / %ss per computer\nWaits for unshielded target" % number(float(parameters("synchronization").interval) / ResearchUpgrades.value(modifiers, "synchronization_multiplier"))
		ShipPart.Type.COMMAND_UPLINK:
			var data := parameters("mark")
			return "Mark: +%s%% per uplink\n%ss / %ss" % [number((ResearchUpgrades.value(modifiers, "mark_damage_multiplier", float(data.damage_multiplier)) - 1) * 100), number(data.duration), number(data.cooldown)]
		ShipPart.Type.REPAIR_STATION:
			return "Repair %s hull/s\n%s hull reserve per encounter" % [number(SharedSupport.repair_rate()), number(SharedSupport.repair_reserve())]
		ShipPart.Type.REPAIR_DRONE_BAY:
			return "%s hull/s shared per hangar\nSelf + allies | Range %s" % [number(float(parameters("repair_aura").rate) * ResearchUpgrades.value(modifiers, "repair_aura_multiplier")), number(parameters("repair_aura").range)]
		ShipPart.Type.SHIELD_RELAY:
			return "%s shields | %s/s after %ss\nTransfer: %s/s each | Range %s" % [number(item.stats.shields), number(float(item.stats.shields) * float(parameters("shield").recharge_fraction)), number(parameters("shield").delay), number(parameters("shield_relay").rate), number(parameters("shield_relay").range)]
		ShipPart.Type.ION_EMITTER:
			var weapon: Dictionary = item.stats.weapons[0]
			var base_dps: float = float(weapon.damage) * float(weapon.count) / float(weapon.interval)
			return "Shield DPS %s | Hull DPS %s\nRange %s" % [number(base_dps * float(parameters("ion_damage").shield_multiplier)), number(base_dps * float(parameters("ion_damage").hull_multiplier)), number(weapon.range)]
		ShipPart.Type.NANOFORGE:
			return "Deferred"
	if item.get("availability") == "unavailable":
		return "Unavailable"
	var values: Dictionary = item.stats
	var effects: PackedStringArray = []
	if "prismatic" in item.get("research_capabilities", []) and modifiers.has("prismatic_lasers"):
		effects.append("Continuous / 1x to %sx DPS over %ss" % [number(parameters("prismatic").max_multiplier), number(parameters("prismatic").ramp_seconds)])
	if "splitting_missile" in item.get("research_capabilities", []) and modifiers.has("splinter_missiles"):
		var fraction := float(parameters("splinter").damage_fraction)
		effects.append("Splits: %s x %s damage" % [number(parameters("splinter").count), "half" if is_equal_approx(fraction, 0.5) else (number(fraction * 100) + "%")])
	if float(values.shields) > 0 and modifiers.has("pulse_shields"):
		effects.append("Pulse: %s%% shields / %ss" % [number(float(parameters("pulse_shield").fraction) * 100), number(parameters("pulse_shield").interval)])
	if not values.weapons.is_empty():
		var dps := 0.0
		var reach := 0.0
		for weapon: ShipWeaponStats in SlotCatalog.stats_for(item.id, int(item.rank)).weapons:
			ResearchUpgrades.apply_weapon(weapon, modifiers)
			dps += weapon.get_dps()
			reach = maxf(reach, weapon.range_units)
		effects.append("DPS %.1f | Range %.0f" % [dps, reach])
		var missile_cost := 0
		var charge := 0.0
		for weapon: Dictionary in values.weapons:
			missile_cost += int(weapon.get("missiles", 0)) * int(weapon.count)
			charge = maxf(charge, float(weapon.get("charge", 0)))
		if missile_cost > 0:
			effects.append("%d missiles / salvo" % missile_cost)
		if charge > 0:
			effects.append("%ss charge" % number(charge))
	if values.shields > 0:
		effects.append("Shields %.0f | %.1f recharge/s after %ss" % [values.shields, float(values.shields) * float(parameters("shield").recharge_fraction), number(parameters("shield").delay)])
	if values.thrust > 0:
		effects.append("Thrust %.0f" % values.thrust)
	if values.integrity > 0:
		effects.append("Integrity +%.0f" % values.integrity)
	return " | ".join(effects)

static func parameters(behavior: String) -> Dictionary:
	return SharedSupport.parameters(behavior)

static func number(value: float) -> String:
	return ScienceRules.format_rp(snappedf(value, 0.01))
