class_name LegacySquareRunReader
extends RefCounted

# Inspect old verified envelopes; never resume, promote staged files or convert.
var path := "user://run_checkpoint.json"
var generation := 0
var decoded: Dictionary = {}

func load_checkpoint() -> bool:
	var latest := AtomicRunStore.new().load_latest(path, RunCheckpoint.valid)
	if latest.is_empty():
		return false
	var candidate := RunCheckpoint.decode(latest.payload)
	if candidate.is_empty():
		return false
	decoded = candidate
	generation = int(latest.generation)
	return true
