class_name RunSession
extends RefCounted

signal changed(sections: PackedStringArray)

var content: DefDatabase
var frozen: Dictionary
var path := ""
var generation := -1
var content_file_sha := ""
var hooks := RunHooks.new()
var error := ""
var _doc: Dictionary = {}
var _store := AtomicRunStore.new()
var _committing := false
var _validated: Dictionary = {}

func snapshot() -> Dictionary:
	return _doc.duplicate(true)

func begin(reason: String, source: Dictionary = {}) -> RunTransaction:
	return RunTransaction.new(self, _doc if source.is_empty() else source, generation, reason)

func accepts(doc: Variant) -> bool:
	if Content.db() != content or not SaveValidation.json_value(doc):
		return false
	# AtomicRunStore checks main/staged/backup generations repeatedly. Rules are
	# immutable in this session, so identical validated payloads need no repeated
	# fleet reconstruction. Full precision keeps distinct float inputs distinct.
	var key := JSON.stringify(doc, "", true, true).sha256_text()
	if _validated.has(key):
		return true
	var valid: bool = RunDocument.valid(doc) and doc.meta.content_hash == frozen.content_hash \
		and doc.meta.content_sha256 == frozen.sha256 and doc.meta.packs == RunContent.pack_summary(frozen)
	if valid:
		if _validated.size() >= 8:
			_validated.erase(_validated.keys()[0])
		_validated[key] = true
	return valid

func commit_transaction(tx: RunTransaction, expected: int) -> bool:
	if _committing:
		tx.error = "A transaction is already committing."
		return false
	# Dictionary dot assignments can add StringName keys. Normalize them and
	# declared integers at the boundary, without accepting non-JSON objects.
	tx.doc = RunDocument.normalized(tx.doc)
	error = tx.error
	if expected != generation:
		error = "Run changed since this transaction began."
	elif not _doc.is_empty() and tx.doc.get("meta", {}) != _doc.meta:
		error = "A transaction cannot change run identity or content."
	if not error.is_empty():
		tx.error = error
		return false
	_committing = true
	# The active context must already match. Never silently switch a live run here.
	if Content.db() != content:
		error = "The transaction's run content is not active."
	elif content_file_sha.is_empty() or FileAccess.get_sha256(RunRepository.content_path(tx.path, str(tx.doc.meta.id))) != content_file_sha:
		error = "Frozen run content is missing or changed at this save location."
	elif not hooks.drain(tx):
		error = tx.error
	else:
		tx.doc = RunDocument.normalized(tx.doc)
	if error.is_empty() and not _doc.is_empty() and tx.doc.get("meta", {}) != _doc.meta:
		error = "A hook cannot change run identity or content."
	if error.is_empty() and not accepts(tx.doc):
		error = "Invalid run transaction."
	if error.is_empty():
		var result := _store.commit(tx.path, tx.doc, accepts, expected, tx.interrupt_after)
		if not result.ok:
			error = _store.last_error
		else:
			var sections := PackedStringArray()
			for section: String in tx.doc:
				if not SaveValidation.same(_doc.get(section), tx.doc[section]):
					sections.append(section)
			_doc = tx.doc.duplicate(true)
			path = tx.path
			generation = int(result.generation)
			_committing = false
			changed.emit(sections)
			return true
	_committing = false
	tx.error = error
	return false

func restore_document(doc: Dictionary, saved_generation: int) -> void:
	_doc = doc.duplicate(true)
	generation = saved_generation
