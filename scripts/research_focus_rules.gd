class_name ResearchFocusRules
extends RefCounted

# Keep historical project prices and ledger debits intact when loading older runs.
const PRICING_VERSION := 1
const LEGACY_PRICES := {"laboratory_ii": 40, "laboratory_iii": 80}

static func cost(id: String, progress: Dictionary) -> int:
	if int(progress.get("research_pricing_version", 0)) == 0 and LEGACY_PRICES.has(id):
		return LEGACY_PRICES[id]
	return int(GameDefinitions.find("research", id).get("cost_rp", 0))
