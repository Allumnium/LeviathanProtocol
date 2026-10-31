class_name CampaignContent
extends RefCounted

const VERSION := 1
const GOODS := {"Basic": 3, "Uncommon": 6, "Rare": 10}
const STAGING := ["Relay Outpost", "Refuge Dock", "Last Light Anchorage"]
const BOSSES := ["Bastion Warden", "Brood Architect", "Leviathan"]
const THEMES := ["The Broken Lanes", "The Graveyard Current", "The Whispering Dark"]
const STORIES := {
	"haven": {"title": "Haven Anchorage", "text": "An expedition leaves Haven to trace a moving anomaly through failing jump lanes. Settlements report coordinated attacks. Follow the signal and keep the fleet together."},
	"relay": {"title": "Relay Outpost", "text": "The relay has decoded a repeating command. The scattered guardians share a signal network. Beyond this outpost, the Bastion Warden guards the inner route."},
	"warden_brief": {"title": "Bastion Warden briefing", "text": "Destroy the Warden body. Two pylons reduce its damage taken by 20% each. Its lance warns for 3 seconds; move clear or interrupt with focused damage."},
	"refuge": {"title": "Refuge Dock", "text": "Refuge crews describe ship nurseries made from missing vessels. The Leviathan is repurposing ships and settlements. Their records identify the brood network's controlling signal."},
	"architect_brief": {"title": "Brood Architect briefing", "text": "The nursery's guardian formation controls the next passage. Clear the marked hostiles to expose the Leviathan's approach. Refuge Dock offers full preparation services."},
	"last_light": {"title": "Last Light Anchorage", "text": "The anomaly is an ancient autonomous ark. Its corrupted preservation system consumes the settlements it was built to protect. Sever its command network to end the assimilation. Last Light is the final preparation stop."},
	"leviathan_brief": {"title": "Leviathan briefing", "text": "The ark's guardian formation holds the final passage. Clear the marked hostiles. This is your final opportunity to refit and safely leave civilian cargo or passengers at port."},
	"ending": {"title": "The signal falls silent", "text": "The expedition has broken through the guardian network. The corrupted command signal falls silent, leaving the surviving settlements a chance to rebuild."},
}


static func populate(geometry: Dictionary, seed_value: int) -> Dictionary:
	var graph := geometry.duplicate(true)
	graph.content_version = VERSION
	graph.routes = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d/campaign-content/v1" % seed_value)
	for node in graph.nodes:
		var act := maxi(0, int(node.act) - 1)
		var port_row := 4 if act == 0 else 3
		var inhabited: bool = node.kind in ["start", "staging"] or (node.kind == "noncombat" and int(node.local_row) == port_row)
		var type: String = node.kind
		if type == "combat":
			type = "elite" if node.elite else "patrol"
		elif type == "noncombat":
			type = "port" if inhabited else ["salvage", "survey", "signal"][rng.randi_range(0, 2)]
		node.type = type
		node.inhabited = inhabited
		node.goods_grade = ["Basic", "Uncommon", "Rare"][act] if inhabited else "Basic"
		node.goods_unit_value = GOODS[node.goods_grade]
		node.services = ["repair", "refit", "materials", "offload", "disembark"] if inhabited else []
		node.story_ids = []
		node.material_reward = [3, 2, 1, 0] if type == "salvage" else [0, 0, 0, 0]
		node.name = "%s %d.%d" % [type.capitalize(), act + 1, int(node.local_row)]
		if type == "start":
			node.name = "Haven Anchorage"
			node.story_ids = ["haven"]
		elif type == "staging":
			node.name = STAGING[act]
			node.story_ids = [["relay", "warden_brief"], ["refuge", "architect_brief"], ["last_light", "leviathan_brief"]][act]
		elif type == "boss":
			node.name = BOSSES[act] + " approach"
			if act == 2:
				node.story_ids = ["ending"]
	for edge in graph.edges:
		var exits := 0
		for candidate in graph.edges:
			if candidate[0] == edge[0]:
				exits += 1
		var hazard := "none"
		# Only the first exit of a fork can be charted hazardous; others stay safe.
		var first := true
		for route in graph.routes:
			if route.from == edge[0]:
				first = false
		if exits > 1 and first and rng.randf() < 0.4:
			hazard = ["debris", "ion_storm", "gravity"][rng.randi_range(0, 2)]
		graph.routes.append({"from": edge[0], "to": edge[1], "hazard": hazard,
			"duration": 0 if hazard == "none" else rng.randi_range(20, 40),
			"seed": str(rng.randi()), "mining_potential": "low" if hazard == "debris" else "none",
			"active": false})
	return graph


static func valid(graph: Dictionary) -> bool:
	if graph.get("content_version") != VERSION or not graph.get("routes") is Array:
		return false
	for node in graph.nodes:
		if node.get("type") not in ["start", "patrol", "elite", "boss", "staging", "port", "salvage", "survey", "signal"]:
			return false
		if not node.get("name") is String or not node.get("inhabited") is bool or not GOODS.has(node.get("goods_grade")):
			return false
		if node.get("goods_unit_value") != GOODS[node.goods_grade] or not node.get("services") is Array or not node.get("story_ids") is Array:
			return false
		var should_inhabit: bool = node.type in ["start", "port", "staging"]
		if node.inhabited != should_inhabit or (not node.inhabited and not node.services.is_empty()):
			return false
		if node.inhabited and node.services != ["repair", "refit", "materials", "offload", "disembark"]:
			return false
		if node.kind == "combat" and node.type != ("elite" if node.elite else "patrol"):
			return false
		if node.kind in ["start", "staging", "boss"] and node.type != node.kind:
			return false
		if node.kind == "noncombat":
			var port_row := 4 if int(node.act) == 1 else 3
			if int(node.local_row) == port_row and node.type != "port":
				return false
			if node.type not in ["port", "salvage", "survey", "signal"]:
				return false
		for id in node.story_ids:
			if not STORIES.has(id):
				return false
		var required_story: Array = []
		if node.kind == "start":
			required_story = ["haven"]
		elif node.kind == "staging":
			required_story = [["relay", "warden_brief"], ["refuge", "architect_brief"], ["last_light", "leviathan_brief"]][int(node.act) - 1]
		elif node.kind == "boss" and int(node.act) == 3:
			required_story = ["ending"]
		if node.story_ids != required_story:
			return false
		if not node.get("material_reward") is Array or node.material_reward.size() != 4:
			return false
		for amount in node.material_reward:
			if not SaveValidation.integer(amount) or amount < 0 or amount > 6:
				return false
		if not SaveValidation.same(node.material_reward, [3, 2, 1, 0] if node.type == "salvage" else [0, 0, 0, 0]):
			return false
	if graph.routes.size() != graph.edges.size():
		return false
	var safe: Dictionary = {}
	var hazardous: Dictionary = {}
	for index in range(graph.routes.size()):
		var route: Variant = graph.routes[index]
		if not route is Dictionary or route.get("from") != graph.edges[index][0] or route.get("to") != graph.edges[index][1]:
			return false
		if route.get("hazard") not in ["none", "debris", "ion_storm", "gravity"] or route.get("active") != false:
			return false
		if not SaveValidation.integer(route.get("duration")) or not route.get("seed") is String or not route.seed.is_valid_int():
			return false
		if route.hazard == "none":
			if route.duration != 0:
				return false
			safe[int(route.from)] = true
		else:
			if route.duration < 20 or route.duration > 40:
				return false
			hazardous[int(route.from)] = true
		if route.get("mining_potential") not in ["none", "low"]:
			return false
	for source in hazardous:
		if not safe.has(source):
			return false
	return true
