extends RefCounted

# Engine primitives and their accepted parameters, shared by pack validation
# and runtime registry checks. Content selects and tunes these operations.

static func valid(modifier: Variant, materials: Array[String]) -> bool:
	if not modifier is Dictionary:
		return false
	match modifier.get("id", ""):
		"laser_damage_multiplier", "laser_range_multiplier", "missile_range_multiplier", "fragment_damage_multiplier", "railgun_hull_multiplier", "carrier_launch_multiplier", "carrier_damage_multiplier", "passive_repair_multiplier", "repair_aura_multiplier", "mark_damage_multiplier", "synchronization_multiplier", "research_output_multiplier":
			return _number(modifier.get("value")) and modifier.value > 1 and modifier.value <= 2
		"cruise_fuel_multiplier":
			return _number(modifier.get("value")) and modifier.value > 0 and modifier.value < 1
		"cruise_speed_multiplier":
			return _number(modifier.get("value")) and modifier.value > 1 and modifier.value <= 2
		"travel_credits_per_day":
			return _number(modifier.get("value")) and modifier.value > 0 and modifier.value <= 100 \
				and modifier.value == floor(modifier.value)
		"energy_efficiency":
			return _number(modifier.get("value")) and modifier.value > 0 and modifier.value <= 0.3 \
				and modifier.get("ordinary_efficiency_cap") == 0.3 and modifier.get("targets") is Array \
				and _unique_strings(modifier.targets) and modifier.targets.size() == 2 \
				and modifier.targets.has("beam") and modifier.targets.has("shield")
		"cargo_hold_capacity":
			return _number(modifier.get("value")) and modifier.value > 0 and modifier.value == floor(modifier.value) \
				and modifier.get("refill_existing") is bool and not modifier.refill_existing
		"scan_spectroscopy":
			return modifier.get("value") is bool
		"prismatic_lasers", "splinter_missiles", "pulse_shields":
			return modifier.get("value") is bool
		"extractable_materials":
			if not modifier.get("values") is Array or modifier.values.is_empty() or not _unique_strings(modifier.values):
				return false
			for id: String in modifier.values:
				if id not in materials:
					return false
			return true
	return false


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _unique_strings(values: Array) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if not value is String or value.is_empty() or seen.has(value):
			return false
		seen[value] = true
	return true
