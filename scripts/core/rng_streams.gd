class_name RngStreams
extends RefCounted

## Named, persisted random streams. Each draw site asks for a generator keyed by
## (seed, stream, scope, counter); counters advance per request and are saved
## with the run, so reloading reproduces later draws exactly.

var run_seed: String = ""
var counters: Dictionary = {}


func _init(seed_value: Variant = "") -> void:
	run_seed = str(seed_value)


func rng(stream: String, scope: String = "") -> StableRng:
	var counter_key := stream + "/" + scope
	var counter := int(counters.get(counter_key, 0))
	counters[counter_key] = counter + 1
	return StableRng.from_parts([run_seed, stream, scope, counter])


## A generator that never advances counters, for draws that must stay stable
## for a given subject, such as a grammar-generated name for an entity.
func fixed(stream: String, scope: String) -> StableRng:
	return StableRng.from_parts([run_seed, stream, scope, "fixed"])


func counter(stream: String, scope: String = "") -> int:
	return int(counters.get(stream + "/" + scope, 0))


func snapshot() -> Dictionary:
	var keys := counters.keys()
	keys.sort()
	var saved := {}
	for key in keys:
		saved[key] = counters[key]
	return {"seed": run_seed, "counters": saved}


func restore(data: Variant) -> bool:
	if not data is Dictionary or not data.get("seed") is String or not data.get("counters") is Dictionary:
		return false
	var restored := {}
	for key in data.counters:
		var value: Variant = data.counters[key]
		if not key is String or not (value is int or value is float) or int(value) < 0 or float(value) != floorf(float(value)):
			return false
		restored[key] = int(value)
	run_seed = data.seed
	counters = restored
	return true
