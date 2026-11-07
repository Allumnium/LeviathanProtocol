class_name ContentProblems
extends RefCounted

## Load and validation problems with enough location detail for the editor and
## command-line tools: severity, pack, file, def, JSON path and message.

const ERROR := "error"
const WARNING := "warning"

var items: Array[Dictionary] = []


func add(severity: String, message: String, pack := "", file := "", def := "", path := "") -> void:
	items.append({"severity": severity, "pack": pack, "file": file, "def": def, "path": path, "message": message})


func error(message: String, pack := "", file := "", def := "", path := "") -> void:
	add(ERROR, message, pack, file, def, path)


func warning(message: String, pack := "", file := "", def := "", path := "") -> void:
	add(WARNING, message, pack, file, def, path)


func merge(other: ContentProblems) -> void:
	items.append_array(other.items)


func errors() -> Array[Dictionary]:
	return items.filter(func(item: Dictionary) -> bool: return item.severity == ERROR)


func warnings() -> Array[Dictionary]:
	return items.filter(func(item: Dictionary) -> bool: return item.severity == WARNING)


func has_errors(pack := "") -> bool:
	for item in items:
		if item.severity == ERROR and (pack.is_empty() or item.pack == pack):
			return true
	return false


func for_pack(pack: String) -> Array[Dictionary]:
	return items.filter(func(item: Dictionary) -> bool: return item.pack == pack)


static func format(item: Dictionary) -> String:
	var where := PackedStringArray()
	if not str(item.file).is_empty():
		where.append(str(item.file))
	elif not str(item.pack).is_empty():
		where.append(str(item.pack))
	if not str(item.def).is_empty():
		where.append(str(item.def))
	if not str(item.path).is_empty():
		where.append(str(item.path))
	return "%s %s: %s" % [item.severity, " ".join(where), item.message]


func text() -> String:
	var lines := PackedStringArray()
	for item in items:
		lines.append(format(item))
	return "\n".join(lines)
