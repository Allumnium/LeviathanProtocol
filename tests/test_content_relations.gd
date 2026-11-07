extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var shipped := PackLoader.new().load_packs(["res://packs"])
	check(shipped.problems.items.is_empty(), "Shipped relationships pass preflight")
	var folder := "user://relations/invalid"
	DirAccess.make_dir_recursive_absolute(folder + "/defs")
	FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string(JSON.stringify({
		"id": "invalid_relations", "name": "Invalid relations", "kind": "content", "version": "1.0.0",
		"depends": [{"id": "core", "version": ">=1.0"}, {"id": "leviathan", "version": ">=1.0"}]}))
	var members: Array = shipped.get_def("fleet_package", "core:convoy").members
	var duplicated := members.duplicate(true)
	duplicated.append(members[0])
	for probe: Dictionary in [
		{"type": "fleet_package", "target": "core:convoy", "set": {"members": duplicated}, "path": "members"},
		{"type": "fleet_package", "target": "core:convoy", "set": {"members[flagship].count": 2}, "path": "members"},
		{"type": "fleet_package", "target": "core:convoy", "set": {"members": [members[1]]}, "path": "members"},
		{"type": "fleet_package", "target": "core:convoy", "set": {"members[flagship].count": 192}, "path": "members"},
		{"type": "chassis", "target": "core:drone", "set": {"default_loadout": "core:flagship_basic/command"}, "path": "default_loadout"},
		{"type": "loadout", "target": "core:drone/gun_drone", "set": {"mounts": {"fore": "core:laser"}}, "path": "mounts"},
		{"type": "loadout", "target": "core:drone/gun_drone", "set": {"mounts.fore": "core:double_laser"}, "path": "mounts.fore"},
		{"type": "equipment", "target": "core:mini_turret", "set": {"size": "XL"}, "path": "mounts.fore"},
		{"type": "equipment", "target": "core:mini_turret", "set": {"availability": "research"}, "path": "members"},
		{"type": "equipment", "target": "core:research_lab", "set": {"availability": "research"}, "path": "members"},
		{"type": "chassis", "target": "core:drone", "set": {"flagship": true}, "path": "members"},
		{"type": "run_start", "target": "leviathan:charter", "set": {"location": "leviathan:derelict_1"}, "path": "location"},
		{"type": "location", "target": "leviathan:start_station", "set": {"accessible": false}, "path": "location"},
		{"type": "event", "target": "leviathan:first_contact", "set": {"options[fight].effects.combat.template": "core:boss_framework"}, "path": "options[fight].effects.combat.template"},
		{"type": "encounter", "target": "core:patrol", "set": {"story_eligible": false}, "path": "options"}
	]:
		FileAccess.open(folder + "/defs/patch.json", FileAccess.WRITE).store_string(JSON.stringify({
			"def": "patch", "id": "broken", "target_def": probe.type, "target": probe.target, "set": probe.set}))
		var db := PackLoader.new().load_packs(["res://packs", "user://relations"])
		check(not db.has_pack("invalid_relations") and db.has_pack("core") and db.has_pack("leviathan")
			and db.content_hash == shipped.content_hash, "Invalid relation rolls back only its patch: " + str(probe.set))
		check(db.problems.errors().any(func(problem: Dictionary) -> bool:
			return problem.pack == "invalid_relations" and problem.def == "broken" and problem.path.begins_with(probe.path)),
			"Problem identifies causal patch and field: " + str(probe.set) + " " + db.problems.text())
	print("CONTENT RELATIONS COMPLETE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
