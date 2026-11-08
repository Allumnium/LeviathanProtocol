class_name ResearchSystem
extends RefCounted

static func ready(progress: Dictionary, content: DefDatabase) -> bool:
	return not progress.research_offer.is_empty() and float(progress.research_points) >= HangarResearch.threshold(progress, content)

## Pure staging helper for remaining travel/settlement callers during extraction.
## Existing fixed offer stream depends on seed and earned IDs, never frame count.
static func allocate_progress(progress: Dictionary, amount: float, seed_value: int, facts: FactView, content: DefDatabase) -> void:
	progress.research_points = float(progress.research_points) + maxf(0, amount)
	HangarResearch.prepare_offer(progress, seed_value, facts.research_option_count(), facts, content)

static func allocate(tx: RunTransaction, content: DefDatabase, amount: float, source := "") -> bool:
	if not tx.error.is_empty():
		return false
	if not is_finite(amount) or amount < 0:
		tx.error = "Research award must be finite and nonnegative."
		return false
	var progress: Dictionary = tx.doc.fleet.research
	var had_offer: bool = not progress.research_offer.is_empty()
	allocate_progress(progress, amount, int(tx.doc.meta.seed), FactView.new(tx.doc, content), content)
	if amount > 0:
		tx.emit_hook("research.earned", {"amount": amount, "source": source})
	if not had_offer and not progress.research_offer.is_empty():
		tx.record("research.offer_prepared", {"options": progress.research_offer, "points": progress.research_points})
	return true

static func choose(tx: RunTransaction, content: DefDatabase, key: String) -> bool:
	if not tx.error.is_empty():
		return false
	key = Content.runtime_id("research", key, "", content)
	var facts := FactView.new(tx.doc, content)
	var progress: Dictionary = tx.doc.fleet.research
	if not facts.can_manage() or not ready(progress, content) or key not in progress.research_offer:
		tx.error = "Choose one of the offered upgrades."
		return false
	if not HangarResearch.eligible(key, progress, content):
		tx.error = "This upgrade is no longer available."
		return false
	if not facts.matches_research(key):
		tx.error = ResearchUpgrades.requirement(key, content)
		return false
	var cost := HangarResearch.threshold(progress, content)
	progress.research_points -= cost
	progress.research_ids.append(key)
	progress.research_offer.clear()
	var definition := GameDefinitions.find("research", key, content)
	if not definition.family_id.is_empty():
		progress.branch_choices[ResearchRules.family_key(definition.family_id, content)] = definition.path_id
	tx.record("research.completed", {"research_id": key, "points": cost})
	return allocate(tx, content, 0, "choice_overflow")
