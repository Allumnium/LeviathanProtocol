class_name TransactionLedger
extends RefCounted

const KINDS := ["arrival", "casualty", "cargo_sale", "victory", "ore_pickup", "enemy_salvage", "node_reward", "port_service"]


static func apply(checkpoint: Dictionary, kind: String, source_id: String,
	credits_delta: int, material_delta: Array, rp_delta: int, details: Dictionary = {}, economy_after: Variant = null) -> Dictionary:
	if kind not in KINDS or source_id.is_empty() or checkpoint.get("run_id", "").is_empty():
		return {}
	if material_delta.size() != 4:
		return {}
	if economy_after != null and not economy_after is Dictionary:
		return {}
	var materials: Array[int] = []
	for amount in material_delta:
		if not RunProgressData._integer(amount):
			return {}
		materials.append(int(amount))
	var event_id: String = checkpoint.run_id + "/" + kind + "/" + source_id
	# Normalize caller/loaded numeric types before hashing event identity.
	var normalized_details: Variant = JSON.parse_string(JSON.stringify(details))
	var normalized_economy: Variant = JSON.parse_string(JSON.stringify(economy_after))
	var fingerprint := JSON.stringify(JSON.parse_string(JSON.stringify(
		[kind, credits_delta, materials, rp_delta, normalized_details, normalized_economy]))).sha256_text()
	if checkpoint.ledger.has(event_id):
		if checkpoint.ledger[event_id].fingerprint != fingerprint:
			return {} # The same identity cannot describe a different economic event.
		return {"checkpoint": checkpoint.duplicate(true), "replayed": true}
	var result := checkpoint.duplicate(true)
	if normalized_economy != null:
		result.economy = normalized_economy
	var before := {"credits": int(result.progress.credits), "materials": result.inventory.duplicate(),
		"rp": int(result.progress.research_points)}
	# Bound arithmetic to JSON's exact integer range, including signed debt.
	if absf(float(before.credits)) + absf(float(credits_delta)) > 9007199254740991.0:
		return {}
	if absf(float(before.rp)) + absf(float(rp_delta)) > 9007199254740991.0:
		return {}
	result.progress.credits = int(before.credits) + credits_delta
	result.progress.research_points = int(before.rp) + rp_delta
	if result.progress.research_points < 0:
		return {}
	for index in range(4):
		if absf(float(result.inventory[index])) + absf(float(materials[index])) > 9007199254740991.0:
			return {}
		result.inventory[index] = int(result.inventory[index]) + materials[index]
		if result.inventory[index] < 0:
			return {}
	var after := {"credits": result.progress.credits, "materials": result.inventory.duplicate(),
		"rp": result.progress.research_points}
	result.ledger[event_id] = {"kind": kind, "source_id": source_id, "fingerprint": fingerprint,
		"credits_delta": credits_delta, "material_delta": materials, "rp_delta": rp_delta,
		"details": normalized_details, "economy_after": normalized_economy, "before": before, "after": after}
	return {"checkpoint": result, "replayed": false}


static func valid(ledger: Variant, run_id: String) -> bool:
	if not ledger is Dictionary:
		return false
	for id in ledger:
		var entry: Variant = ledger[id]
		if not id is String or not entry is Dictionary or entry.get("kind") not in KINDS:
			return false
		if not entry.get("source_id") is String or entry.source_id.is_empty():
			return false
		if id != run_id + "/" + entry.kind + "/" + entry.source_id:
			return false
		if not entry.get("fingerprint") is String or entry.fingerprint.length() != 64:
			return false
		if not RunProgressData._integer(entry.get("credits_delta")) or not RunProgressData._integer(entry.get("rp_delta")):
			return false
		if not entry.get("material_delta") is Array or entry.material_delta.size() != 4:
			return false
		if not entry.get("details") is Dictionary:
			return false
		for balance in [entry.get("before"), entry.get("after")]:
			if not balance is Dictionary or not RunProgressData._integer(balance.get("credits")):
				return false
			if not RunProgressData._integer(balance.get("rp")) or balance.rp < 0:
				return false
			if not balance.get("materials") is Array or balance.materials.size() != 4:
				return false
			for amount in balance.materials:
				if not RunProgressData._integer(amount) or amount < 0:
					return false
		var test := {"run_id": run_id, "ledger": {}, "progress": {"credits": entry.before.credits,
			"research_points": entry.before.rp}, "inventory": entry.before.materials}
		var replay := apply(test, entry.kind, entry.source_id, int(entry.credits_delta), entry.material_delta,
			int(entry.rp_delta), entry.details, entry.get("economy_after"))
		if replay.is_empty() or replay.checkpoint.ledger[id].fingerprint != entry.fingerprint:
			return false
		# Compare normalized numeric values, not int/JSON-float container identity.
		if JSON.parse_string(JSON.stringify(replay.checkpoint.ledger[id].after)) != JSON.parse_string(JSON.stringify(entry.after)):
			return false
	return true
