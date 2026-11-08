class_name RunTransaction
extends RefCounted

var doc: Dictionary
var hooks: Array[Dictionary] = []
var error := ""
var reason := ""
var closed := false
var _processing := false
var path := ""
var interrupt_after := "" # Focused durability/failure injection.
var _owner: RefCounted
var _generation: int

func _init(owner: RefCounted, source: Dictionary, generation: int, command: String) -> void:
	_owner = owner
	doc = source.duplicate(true)
	_generation = generation
	reason = command
	path = owner.path

func emit_hook(name: String, data: Dictionary = {}) -> void:
	if (not closed or _processing) and not name.is_empty():
		hooks.append({"name": name, "data": data.duplicate(true)})

func record(name: String, data: Dictionary = {}) -> void:
	if (closed and not _processing) or name.is_empty():
		return
	doc.chronicle.append({"id": doc.chronicle.size() + 1, "type": name,
		"seconds": doc.clock.seconds, "data": data.duplicate(true)})
	emit_hook(name, data)

func rng(stream: String, scope := "") -> StableRng:
	var streams := RngStreams.new()
	streams.restore(doc.rng)
	var result := streams.rng(stream, scope)
	doc.rng = streams.snapshot()
	return result

func commit() -> bool:
	if closed:
		error = "Transaction is already closed."
		return false
	# Hooks may enqueue more hooks, but cannot recursively commit this transaction.
	closed = true
	_processing = true
	var result: bool = _owner.commit_transaction(self, _generation)
	_processing = false
	return result
