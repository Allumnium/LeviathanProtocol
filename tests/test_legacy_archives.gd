extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	validation_checks()
	square_library_checks()
	square_checkpoint_checks()
	slot_library_checks()
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LegacyHexRecipe.DATA_PATH))
	check(LegacyHexRecipe.validate(frozen).is_empty(), "Frozen archive footprints validate without the active recipe/research registry.")
	var invalid_catalog := frozen.duplicate(true)
	invalid_catalog.recipes.pop_back()
	check(not LegacyHexRecipe.validate(invalid_catalog).is_empty(), "Incomplete frozen catalogs are rejected.")
	invalid_catalog = frozen.duplicate(true)
	invalid_catalog.recipes[1] = invalid_catalog.recipes[0].duplicate(true)
	check(not LegacyHexRecipe.validate(invalid_catalog).is_empty(), "Duplicate historical identities are rejected.")
	invalid_catalog = frozen.duplicate(true)
	invalid_catalog.recipes[0].cells[0] = [20, 20, 0]
	check(not LegacyHexRecipe.validate(invalid_catalog).is_empty(), "Disconnected historical footprints are rejected.")
	var old_square: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_blueprints_v1.json"))
	for payload: Dictionary in old_square:
		check(Ship.new().load_design_data(payload), "Existing square blueprints remain readable.")
		check(not SlotShipDesign.new().load_data(payload), "Square coordinates cannot become slot loadouts.")
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_hex_blueprint_v2.json"))
	var old_hex := LegacyHexShipDesign.new()
	check(old_hex.load_data(payload), "Read a genuine version-two hex blueprint after removing its editor.")
	check(old_hex.chassis_id == "wren" and old_hex.components[0].equipment_id == "laser" and old_hex.tiles.size() == 3, "Historical chassis, coordinates and equipment identity are retained.")
	var original := old_hex.to_data()
	for field in ["chassis_revision", "topology", "components", "tiles"]:
		var invalid := payload.duplicate(true)
		match field:
			"chassis_revision": invalid[field] = 999
			"topology": invalid[field] = "chassis_slots_v1"
			"components": invalid[field][0].equipment_id = "unknown"
			"tiles": invalid[field].append([4096, 4096, 0])
		check(not old_hex.load_data(invalid) and old_hex.to_data() == original, "Rejected historical data leaves the prior archive intact: " + field)
	var next := SlotShipDesign.new()
	next.initialize("drone")
	check(not next.load_data(payload) and not old_hex.load_data(next.to_data()) and not Ship.new().load_design_data(next.to_data()), "All three design schemas retain explicit boundaries.")
	var path := "user://legacy_reader_test/library.json"
	var bundle := {"version": 2, "topology": "hex_axial_v1", "designs": {"Historical Wren": payload}}
	var store := AtomicRunStore.new()
	check(store.commit(path, bundle, LegacyHexDesignLibrary.valid).ok, "Create the historical checksummed archive envelope in isolated test storage.")
	var bytes := FileAccess.get_file_as_bytes(path)
	var library := LegacyHexDesignLibrary.new()
	library.path = path
	check(library.load_library() and library.get_design("Historical Wren").to_data() == original, "Read the original hex library format without conversion.")
	check(FileAccess.get_file_as_bytes(path) == bytes and not library.has_method("save_design"), "Legacy archive reads never rewrite user files or offer the retired writer.")
	check(store.commit(path, bundle, LegacyHexDesignLibrary.valid, library.generation).ok, "Keep a valid historical backup generation.")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("corrupt primary")
	file.close()
	check(library.load_library() and library.get_design("Historical Wren") != null, "Read-only compatibility still recovers a verified backup.")
	print("Legacy archive tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func validation_checks() -> void:
	for value: Variant in [0, -12, 42.0, 9007199254740991.0]:
		check(SaveValidation.integer(value), "Preserve integral JSON numbers.")
	for value: Variant in [null, true, "1", 1.5, INF, NAN, 9007199254740992.0]:
		check(not SaveValidation.integer(value), "Reject non-integral or unsafe JSON numbers.")
	check(SaveValidation.bounded_number(0.5) and not SaveValidation.bounded_number(INF), "Fractional RP remains valid; infinity does not.")
	check(SaveValidation.vector([1.5, -2]) and not SaveValidation.vector([0, NAN]), "Coordinates require two finite numbers.")
	check(SaveValidation.node(-1.0, 3, true) and not SaveValidation.node(-1, 3) and not SaveValidation.node(3, 3), "Node bounds and the optional sentinel are preserved.")
	check(SaveValidation.json_value({"nested": [null, true, 1.25]}) and not SaveValidation.json_value({"nested": Vector2.ZERO}), "Commands accept JSON values only.")
	var nested: Variant = 0
	for index in range(34):
		nested = [nested]
	check(not SaveValidation.json_value(nested), "Reject excessive nesting.")
	check(SaveValidation.same({"a": 1}, {"a": 1.0}), "Wire equality accepts JSON numeric representation.")

func square_library_checks() -> void:
	var designs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_blueprints_v1.json"))
	var path := "user://square_designs.json"
	var payload := {"version": 1, "designs": [{"name": "Historical Drone", "ship": designs[0]}]}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	var reader := LegacySquareDesignLibrary.new()
	reader.path = path
	check(reader.load_library() and reader.get_design("Historical Drone") != null, "Original square library remains readable.")
	check(FileAccess.get_file_as_bytes(path) == bytes and not reader.has_method("save_design"), "Square library has no writer and preserves bytes.")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version":1,"designs":[{"name":"","ship":{}}]}')
	file.close()
	check(not reader.load_library() and reader.get_design("Historical Drone") != null, "Malformed libraries cannot replace the last readable archive.")

func square_checkpoint_checks() -> void:
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_square_run_v2.json"))
	check(RunCheckpoint.valid(payload) and payload.fleet.size() == 3, "Frozen original checkpoint retains three square ships.")
	var path := "user://square_run_checkpoint.json"
	var store := AtomicRunStore.new()
	check(store.commit(path, payload, RunCheckpoint.valid).ok, "Prepare an original-format checksummed checkpoint.")
	var bytes := FileAccess.get_file_as_bytes(path)
	var reader := LegacySquareRunReader.new()
	reader.path = path
	check(reader.load_checkpoint() and reader.decoded.fleet.size() == 3, "Read old run without installing it into the physical campaign.")
	check(FileAccess.get_file_as_bytes(path) == bytes and not RunCheckpoint.new().has_method("capture"), "Checkpoint reader preserves the old file and has no capture writer.")
	check(not HangarCheckpoint.valid(payload), "Square runs cannot be mistaken for physical saves.")
	check(store.commit(path, payload, RunCheckpoint.valid, reader.generation, "after_stage").ok, "Prepare a staged historical generation.")
	var staged := FileAccess.get_file_as_bytes(path + ".next")
	check(reader.load_checkpoint() and reader.generation == 2, "Read the newest verified staged archive.")
	check(FileAccess.get_file_as_bytes(path) == bytes and FileAccess.get_file_as_bytes(path + ".next") == staged, "Read-only recovery never promotes or rewrites staged files.")
	var invalid := payload.duplicate(true)
	invalid.fleet[0].hp[0] = INF
	check(not RunCheckpoint.valid(invalid), "Historical damaged-unit records still fail validation.")

func slot_library_checks() -> void:
	var design := SlotShipDesign.new()
	design.initialize("drone")
	var payload := {"version": 3, "format": SlotShipDesign.FORMAT, "designs": {"Prototype": design.to_data()}}
	var path := "user://prototype_slot_designs.json"
	check(AtomicRunStore.new().commit(path, payload, SlotDesignLibrary.valid).ok, "Prepare the prototype slot archive.")
	var bytes := FileAccess.get_file_as_bytes(path)
	var reader := SlotDesignLibrary.new()
	reader.path = path
	check(reader.load_library() and reader.get_design("Prototype") != null, "Prototype loadouts remain readable after removing Designer.")
	check(FileAccess.get_file_as_bytes(path) == bytes and not reader.has_method("save_design"), "Prototype archives are read-only too.")
