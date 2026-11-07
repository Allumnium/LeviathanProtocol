class_name NodeEnvironment
extends RefCounted

const ROCK_COUNTS := [0, 16, 32, 48]
const DENSITY_NAMES := ["Clear", "Sparse", "Medium", "Dense"]

static func generate(run_seed: int, node: Dictionary) -> Dictionary:
	var rng := RngStreams.new(run_seed).fixed("campaign.environment.v1", str(node.id))
	var density := rng.randi_range(0, 3)
	# Keep ports and the opening encounter clear for safe refitting/onboarding.
	if node.get("inhabited", false) or int(node.row) <= 1:
		density = 0
	return {"version": 1, "asteroid_density": density,
		"solar_intensity": rng.randi_range(50, 150) / 100.0,
		"nebula": not node.get("inhabited", false) and rng.randf() < 0.25}

static func valid(value: Variant) -> bool:
	return value is Dictionary and value.get("version") == 1 \
		and SaveValidation.integer(value.get("asteroid_density")) and int(value.asteroid_density) in [0, 1, 2, 3] \
		and AlienShip._finite_number(value.get("solar_intensity")) and value.solar_intensity >= 0.5 \
		and value.solar_intensity <= 1.5 and value.get("nebula") is bool

static func description(value: Dictionary) -> String:
	return "Asteroids: %s\nSolar intensity: %d%%\nNebula: %s (ambient)" % [
		DENSITY_NAMES[int(value.asteroid_density)], roundi(value.solar_intensity * 100),
		"Present" if value.nebula else "None"]
