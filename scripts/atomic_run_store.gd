class_name AtomicRunStore
extends RefCounted

const VERSION := 1
var last_error := ""


func load_latest(path: String, validator: Callable) -> Dictionary:
	var best: Dictionary = {}
	for suffix in ["", ".next", ".bak"]:
		var candidate := _read(path + suffix, validator)
		if candidate.is_empty():
			continue
		if best.is_empty() or candidate.generation > best.generation:
			best = candidate
	return best


func commit(path: String, payload: Dictionary, validator: Callable, expected_generation := -1, interrupt_after := "") -> Dictionary:
	last_error = ""
	if not validator.call(payload):
		return _failure("Invalid checkpoint.")
	var latest := load_latest(path, validator)
	var generation := 0 if latest.is_empty() else int(latest.generation)
	if expected_generation >= 0 and generation != expected_generation:
		return _failure("Checkpoint changed since it was loaded.")
	# Never overwrite the only durable newest state when recovering a staged commit.
	if not latest.is_empty() and latest.path == path + ".next":
		if not _promote(path, validator):
			return _failure("Could not recover the staged checkpoint.")
	if interrupt_after == "before_stage":
		return _failure("Interrupted before commit.")
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return _failure("Could not create checkpoint directory.")
	var serialized := JSON.stringify(payload)
	var envelope := {"version": VERSION, "generation": generation + 1,
		"payload": serialized, "sha256": serialized.sha256_text()}
	var file := FileAccess.open(path + ".next", FileAccess.WRITE)
	if file == null:
		return _failure("Could not stage checkpoint: %s" % error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or _read(path + ".next", validator).is_empty():
		# A failed stage is never a commit. Leave older complete generations intact.
		DirAccess.remove_absolute(absolute + ".next")
		return _failure("Could not verify staged checkpoint.")
	# Commit point: the complete verified .next contains both amounts and ledger.
	# Recovery selects it even if the process stops before/between the renames.
	if interrupt_after == "after_stage":
		return {"ok": true, "generation": generation + 1}
	_promote(path, validator, interrupt_after == "after_backup")
	return {"ok": true, "generation": generation + 1}


func _read(path: String, validator: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var envelope: Variant = json.data
	if not envelope is Dictionary or envelope.get("version") != VERSION:
		return {}
	var generation: Variant = envelope.get("generation")
	if not SaveValidation.integer(generation) or generation < 1:
		return {}
	if not envelope.get("payload") is String or not envelope.get("sha256") is String:
		return {}
	if envelope.payload.sha256_text() != envelope.sha256:
		return {}
	if json.parse(envelope.payload) != OK:
		return {}
	var payload: Variant = json.data
	if not payload is Dictionary or not validator.call(payload):
		return {}
	return {"generation": int(generation), "payload": payload, "path": path}


func _promote(path: String, validator: Callable, stop_after_backup := false) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		if _read(path, validator).is_empty():
			# Preserve a good backup when replacing a corrupt main file.
			if DirAccess.remove_absolute(absolute) != OK:
				return false
		else:
			if FileAccess.file_exists(path + ".bak"):
				if DirAccess.remove_absolute(absolute + ".bak") != OK:
					return false
			if DirAccess.rename_absolute(absolute, absolute + ".bak") != OK:
				return false
	if stop_after_backup:
		return false
	return DirAccess.rename_absolute(absolute + ".next", absolute) == OK


func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "generation": -1}
