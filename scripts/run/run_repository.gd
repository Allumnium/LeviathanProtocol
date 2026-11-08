class_name RunRepository
extends RefCounted

const ROOT := "user://runs"
var error := ""

static func run_path(id: String) -> String:
	return ROOT.path_join(id).path_join("run.json")

static func content_path(path: String, id: String) -> String:
	# Fixed test paths retain their failure-injection API without overwriting a
	# previous run's immutable content when the fixture starts another run.
	if path.get_file() == "run.json" and path.get_base_dir().get_file() == id:
		return path.get_base_dir().path_join("content.json")
	return path.get_basename() + ".content/" + id + "/content.json"

func create(path: String, doc: Dictionary, frozen: Dictionary, database: DefDatabase) -> RunSession:
	error = ""
	if not RunDocument.valid(doc) or doc.meta.content_hash != frozen.get("content_hash") or doc.meta.content_sha256 != frozen.get("sha256"):
		error = "Initial run state does not match its content."
		return null
	var session := RunSession.new()
	session.path = path
	session.content = database
	session.frozen = frozen.duplicate(true)
	DefDatabase._freeze(session.frozen)
	var target := content_path(path, str(doc.meta.id))
	var absolute := ProjectSettings.globalize_path(target)
	if FileAccess.file_exists(target):
		error = "Run content already exists; choose a new run identity."
		return null
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		error = "Could not create the run content directory."
		return null
	var file := FileAccess.open(target + ".next", FileAccess.WRITE)
	if file == null:
		error = "Could not stage frozen run content."
		return null
	file.store_string(JSON.stringify(frozen))
	file.flush()
	var file_error := file.get_error()
	file.close()
	var staged: Variant = JSON.parse_string(FileAccess.get_file_as_string(target + ".next"))
	if file_error != OK or not staged is Dictionary or staged.get("sha256") != RunContent.digest(staged) \
			or staged.get("sha256") != frozen.sha256:
		error = "Could not verify frozen run content."
		DirAccess.remove_absolute(absolute + ".next")
		return null
	if DirAccess.rename_absolute(absolute + ".next", absolute) != OK:
		error = "Could not publish frozen run content."
		return null
	session.content_file_sha = FileAccess.get_sha256(target)
	var tx := session.begin("run.started", doc)
	tx.emit_hook("run.started")
	if not tx.commit():
		error = tx.error
		DirAccess.remove_absolute(absolute) # Only this new run's unpublished content.
		return null
	return session

func load_run(path: String) -> RunSession:
	error = ""
	var store := AtomicRunStore.new()
	var saved := store.load_latest(path, RunDocument.shape_valid)
	if saved.is_empty():
		error = "No recoverable run was found."
		return null
	var target := content_path(path, str(saved.payload.meta.id))
	var parser := JSON.new()
	var snapshot: Variant = null
	if FileAccess.file_exists(target) and parser.parse(FileAccess.get_file_as_string(target)) == OK:
		snapshot = parser.data
	var restored := RunContent.restore(snapshot)
	if restored.has("error"):
		error = restored.error
		return null
	var session := RunSession.new()
	session.path = path
	session.content = restored.database
	session.frozen = snapshot
	DefDatabase._freeze(session.frozen)
	session.content_file_sha = FileAccess.get_sha256(target)
	var previous := Content.run_database()
	Content.bind_run(session.content)
	saved = store.load_latest(path, session.accepts)
	Content.bind_run(previous)
	if saved.is_empty():
		error = "Run state does not match its frozen content."
		return null
	session.restore_document(RunDocument.normalized(saved.payload), int(saved.generation))
	return session

func list_runs() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return entries
	for id: String in DirAccess.get_directories_at(ROOT):
		if RegEx.create_from_string("^[a-f0-9]{32}$").search(id) == null:
			continue
		var path := run_path(id)
		var saved := AtomicRunStore.new().load_latest(path, RunDocument.shape_valid)
		if saved.is_empty() or saved.payload.meta.id != id:
			continue # Incomplete content-only folders are never resumable runs.
		entries.append({"id": id, "path": path, "scenario": saved.payload.meta.scenario,
			"ended": saved.payload.fleet.ended or saved.payload.fleet.completed,
			"modified": FileAccess.get_modified_time(saved.path), "content_hash": saved.payload.meta.content_hash})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.id < b.id if a.modified == b.modified else a.modified > b.modified)
	return entries

func latest_path() -> String:
	for entry: Dictionary in list_runs():
		if load_run(entry.path) != null:
			return entry.path
	return ""
