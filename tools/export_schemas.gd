extends SceneTree

## Writes editor JSON Schemas to schemas/json from schemas/defs.
## godot --headless --path . --script res://tools/export_schemas.gd


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var texts := SchemaExporter.render()
	var changed := SchemaExporter.stale(texts)
	var errors := SchemaExporter.write(texts)
	for message in errors:
		printerr(message)
	print("EXPORT_SCHEMAS: %d files, %d changed, %d errors -> %s" % [texts.size(), changed.size(), errors.size(), SchemaExporter.OUT_DIR])
	quit(1 if not errors.is_empty() else 0)
