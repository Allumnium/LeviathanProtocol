extends SceneTree

## Loads packs and prints every Problem; exits 1 on errors.
## godot --headless --path . --script res://tools/validate_packs.gd [-- [--strict] [--user] [root ...]]
## --strict also fails on warnings; --user adds user://packs; extra roots are
## either pack folders containing pack.json or containers of pack folders.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var strict := args.has("--strict")
	var roots: Array = ["res://packs"]
	if args.has("--user"):
		roots.append("user://packs")
	for arg in args:
		if not arg.begins_with("--"):
			roots.append(arg)
	var started := Time.get_ticks_usec()
	var loader := PackLoader.new()
	loader.checks.merge(Content.checks, true)
	var db := loader.load_packs(roots, Content.SCHEMA_DIRS)
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	for item in db.problems.items:
		print(ContentProblems.format(item))
	var defs := 0
	for def_type: String in db.types():
		defs += db.all(def_type).size()
	var errors := db.problems.errors().size()
	var warnings := db.problems.warnings().size()
	var pack_ids := PackedStringArray()
	for pack in db.packs:
		pack_ids.append("%s %s" % [pack.id, pack.version])
	print("VALIDATE_PACKS: %d packs (%s), %d defs, %d errors, %d warnings, %d disabled, %.0f ms" % [
		db.packs.size(), ", ".join(pack_ids), defs, errors, warnings, db.disabled.size(), elapsed])
	quit(1 if errors > 0 or (strict and warnings > 0) else 0)
