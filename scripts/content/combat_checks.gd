extends RefCounted

# Cross-definition checks run after schema/reference validation. Keep malformed
# neighboring records safe, and identify causal paths for patch rollback.
static func validate(data: Dictionary, meta: Dictionary, db: DefDatabase) -> Array:
	if not shape_valid(data, meta.type, db):
		return []
	var problems: Array = []
	match meta.type:
		"enemy_unit":
			var ranks := {}
			for tier: Dictionary in data.tiers:
				if ranks.has(int(tier.rank)):
					problems.append({"path": "tiers", "message": "Enemy tier ranks must be unique."})
				ranks[int(tier.rank)] = true
			if not ranks.has(0):
				problems.append({"path": "tiers", "message": "An enemy unit needs rank zero."})
		"encounter_tuning":
			var weight := 0.0
			for value: float in data.material_weights:
				weight += value
			if not is_equal_approx(weight, 1):
				problems.append({"path": "material_weights", "message": "Material weights must total one."})
			for ref: String in data.allowed_units:
				var unit := db.get_def("enemy_unit", ref, meta.pack)
				if not shape_valid(unit, "enemy_unit", db):
					continue
				var ranks := {}
				for tier: Dictionary in unit.tiers:
					ranks[int(tier.rank)] = true
				if unit.cost <= 0 or unit.kind != "ship" or ranks.size() != 3:
					problems.append({"path": "allowed_units", "causes": [{"type": "enemy_unit", "id": db.resolve_id("enemy_unit", ref, meta.pack), "path": "cost"}, {"type": "enemy_unit", "id": db.resolve_id("enemy_unit", ref, meta.pack), "path": "kind"}, {"type": "enemy_unit", "id": db.resolve_id("enemy_unit", ref, meta.pack), "path": "tiers"}], "message": "Allocation units need a positive price, ship kind and all three ranks."})
		"encounter":
			if not data.implemented:
				if data.story_eligible:
					problems.append({"path": "story_eligible", "related_paths": ["implemented"], "message": "Story encounters must be implemented."})
				return problems
			if not data.has("allocation"):
				return [{"path": "implemented", "message": "Implemented encounters need allocation parameters."}]
			if not data.has("reward_multiplier"):
				problems.append({"path": "implemented", "message": "Implemented encounters need a reward multiplier."})
			var required: Array = data.allocation.get("required", []) + ([data.allocation.wave_unit] if data.allocation.has("wave_unit") else [])
			for ref: String in required:
				var unit := db.get_def("enemy_unit", ref, meta.pack)
				if shape_valid(unit, "enemy_unit", db) and (unit.kind != "ship" or unit.cost <= 0):
					problems.append({"path": "allocation.required", "related_paths": ["allocation.wave_unit"], "causes": [{"type": "enemy_unit", "id": db.resolve_id("enemy_unit", ref, meta.pack), "path": "cost"}, {"type": "enemy_unit", "id": db.resolve_id("enemy_unit", ref, meta.pack), "path": "kind"}], "message": "Required and reinforcement units need positive prices and ship kind."})
			if data.allocation.generator == "warden":
				if not data.has("warden"):
					return [{"path": "allocation.generator", "message": "The Warden generator needs its existing body/pylon plan."}]
				var base := db.get_def("encounter", data.warden.base_template, meta.pack)
				if shape_valid(base, "encounter", db) and (base.get("allocation", {}).get("generator") != "roster" or base.get("allocation", {}).get("waves") != 1):
					problems.append({"path": "warden.base_template", "causes": [{"type": "encounter", "id": db.resolve_id("encounter", data.warden.base_template, meta.pack), "path": "allocation.generator"}, {"type": "encounter", "id": db.resolve_id("encounter", data.warden.base_template, meta.pack), "path": "allocation.waves"}], "message": "Warden base templates must use a single-wave roster generator."})
				if data.warden.rules.warning_seconds >= data.warden.rules.cycle_seconds:
					problems.append({"path": "warden.rules.warning_seconds", "related_paths": ["warden.rules.cycle_seconds"], "message": "The warning must fit inside a lance cycle."})
				if data.warden.boss and data.warden.body_cost_fraction + data.warden.pylons * data.warden.pylon_cost >= 1:
					problems.append({"path": "warden.body_cost_fraction", "related_paths": ["warden.pylon_cost", "warden.pylons"], "message": "Body and pylon costs must leave some escort budget."})
		"ability":
			if data.implemented:
				if not data.has("range_units") or not data.has("radius_units"):
					problems.append({"path": "implemented", "message": "Implemented abilities need range and radius parameters."})
				if not data.has("behavior") or not data.has("parameters"):
					return [{"path": "implemented", "message": "Implemented abilities need a registered behavior and parameters."}]
				var result := db.schemas.validate("_ability_behaviors", {"behavior": data.behavior, "parameters": data.parameters})
				if not result.problems.is_empty():
					problems.append({"path": "parameters", "related_paths": ["behavior"], "message": "Parameters do not match the selected ability behavior."})
			elif data.availability != "unavailable":
				problems.append({"path": "availability", "related_paths": ["implemented"], "message": "Unimplemented abilities must stay unavailable."})
		"support":
			if meta.pack == "core" and data.id != data.behavior:
				problems.append({"path": "behavior", "message": "Core support records bind the named engine behavior; patch its parameters instead."})
	return problems

static func shape_valid(data: Dictionary, type: String, db: DefDatabase) -> bool:
	if data.is_empty():
		return false
	var authored := data.duplicate(true)
	authored.erase("id")
	return db.schemas.validate(type, authored).problems.is_empty()
