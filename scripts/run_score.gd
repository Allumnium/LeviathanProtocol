class_name RunScore
extends RefCounted

const RESEARCH_POINTS := 100
const DAMAGE_PER_POINT := 10.0
const CREDITS_PER_POINT := 10
const LEVIATHAN_POINTS := 20000

static func initial() -> Dictionary:
	return {"swarm_damage": 0.0, "credits_earned": 0}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2:
		return false
	var damage: Variant = value.get("swarm_damage")
	var credits: Variant = value.get("credits_earned")
	return (damage is float or damage is int) and is_finite(float(damage)) and damage >= 0 \
		and (credits is float or credits is int) and is_finite(float(credits)) \
		and credits >= 0 and credits == floor(credits) and credits <= 2147483647

static func earn_credits(data: Dictionary, amount: int) -> void:
	assert(amount >= 0)
	data.credits += amount
	if data.has("score"):
		data.score.credits_earned += amount

static func breakdown(data: Dictionary) -> Dictionary:
	if not data.has("score"):
		return {}
	var projects := 0
	for id: String in data.research.research_ids:
		if id != "foundation":
			projects += 1
	var research := projects * RESEARCH_POINTS
	var damage := floori(float(data.score.swarm_damage) / DAMAGE_PER_POINT)
	var credits := floori(float(data.score.credits_earned) / CREDITS_PER_POINT)
	var bonus := LEVIATHAN_POINTS if data.completed else 0
	return {"research": research, "damage": damage, "credits": credits, "leviathan": bonus,
		"total": research + damage + credits + bonus}

static func description(data: Dictionary) -> String:
	var points := breakdown(data)
	if points.is_empty():
		return "Score unavailable for runs started before this update."
	var text := "RUN SCORE  %d\n\nResearch  %d x 100 = %d\nSwarm damage  %d / 10 = %d\nCredits earned  %d / 10 = %d" % [
		points.total, int(points.research / RESEARCH_POINTS), points.research,
		roundi(data.score.swarm_damage), points.damage, int(data.score.credits_earned), points.credits]
	if points.leviathan > 0:
		text += "\nLeviathan defeated  +%d" % points.leviathan
	return text
