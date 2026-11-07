class_name DefPatcher
extends RefCounted

## Applies patch defs and resolves inheritance.
##
## Patches change authored defs before inheritance, so a patch to a template
## reaches every def that inherits from it. When an operation needs an array
## the def only inherits, the inherited array is copied into the def first.
## Paths: "a.b", "list[item_id]" (the entry whose id matches) and "list[2]".

const OPS := ["set", "append", "remove"]


## Parses "stats.weapons[0].damage" into [{key}, {key}, {index}, {key}].
## Returns [] for a malformed path.
static func parse_path(path: String) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var index := 0
	var length := path.length()
	if length == 0:
		return segments
	while index < length:
		var start := index
		while index < length and path[index] != "." and path[index] != "[":
			index += 1
		var key := path.substr(start, index - start)
		if key.is_empty() and (segments.is_empty() or start > 0 and path[start - 1] == "."):
			return []
		if not key.is_empty():
			segments.append({"key": key})
		while index < length and path[index] == "[":
			var close := path.find("]", index)
			if close < 0:
				return []
			var inner := path.substr(index + 1, close - index - 1)
			if inner.is_empty():
				return []
			if inner.is_valid_int():
				segments.append({"index": int(inner)})
			else:
				segments.append({"select": inner})
			index = close + 1
		if index < length:
			if path[index] != ".":
				return []
			index += 1
			if index >= length:
				return []
	return segments


static func merge(base: Variant, over: Variant) -> Variant:
	if not over is Dictionary:
		return over.duplicate(true) if over is Array else over
	var result: Dictionary = base.duplicate(true) if base is Dictionary else {}
	for key in over:
		var value: Variant = over[key]
		if value == null:
			result.erase(key)
		elif value is Dictionary:
			result[key] = merge(result.get(key), value)
		else:
			result[key] = value.duplicate(true) if value is Array else value
	return result


## Reads a value along parsed segments; returns [found, value].
static func read(root: Variant, segments: Array) -> Array:
	var node: Variant = root
	for segment: Dictionary in segments:
		var step := _step(node, segment)
		if step.is_empty():
			return [false, null]
		node = step[1]
	return [true, node]


static func _step(node: Variant, segment: Dictionary) -> Array:
	if segment.has("key"):
		if node is Dictionary and node.has(segment.key):
			return [segment.key, node[segment.key]]
		return []
	if not node is Array:
		return []
	var position := _position(node, segment)
	return [] if position < 0 else [position, node[position]]


static func _position(values: Array, segment: Dictionary) -> int:
	if segment.has("index"):
		var position: int = segment.index
		return position if position >= 0 and position < values.size() else -1
	for position in values.size():
		var item: Variant = values[position]
		if item is Dictionary and str(item.get("id", "")) == segment.select:
			return position
	return -1


## Applies one patch to `authored` (mutated in place). `inherited` returns the
## resolved parent value for a parsed path as [found, value], used to copy an
## inherited array before changing it. Returns problems as {path, message, op}
## and the paths set, for conflict reporting.
static func apply(authored: Dictionary, patch: Dictionary, inherited: Callable) -> Dictionary:
	var problems: Array[Dictionary] = []
	var set_paths: PackedStringArray = PackedStringArray()
	var changed: PackedStringArray = PackedStringArray()
	for op in OPS:
		var entries: Dictionary = patch.get(op, {})
		var keys := entries.keys()
		for path: String in keys:
			var segments := parse_path(path)
			var where := "%s.%s" % [op, path]
			if segments.is_empty() or not segments[0].has("key"):
				problems.append({"path": where, "message": "Path must look like a.b, list[id] or list[2]"})
				continue
			var message := ""
			match op:
				"set":
					message = _op_set(authored, segments, entries[path], inherited)
					if message.is_empty():
						set_paths.append(path)
				"append":
					message = _op_append(authored, segments, entries[path], inherited)
				"remove":
					message = _op_remove(authored, segments, entries[path], inherited)
			if message.is_empty():
				changed.append(path)
			else:
				problems.append({"path": where, "message": message})
	return {"problems": problems, "set_paths": set_paths, "changed": changed}


## Walks to the container holding the last segment, creating objects and
## copying inherited arrays as needed. Returns [container, last_segment,
## inside_array] or [message].
static func _container(authored: Dictionary, segments: Array, inherited: Callable) -> Array:
	var node: Variant = authored
	var inside_array := false
	for position in segments.size() - 1:
		var segment: Dictionary = segments[position]
		var next: Dictionary = segments[position + 1]
		var child: Variant = _child(node, segment, segments.slice(0, position + 1), inherited, next.has("key"), inside_array)
		if child is String:
			return [child]
		if segment.has("index") or segment.has("select"):
			inside_array = true
		node = child
	return [node, segments[segments.size() - 1], inside_array]


static func _child(node: Variant, segment: Dictionary, prefix: Array, inherited: Callable, wants_object: bool, inside_array: bool) -> Variant:
	if segment.has("key"):
		if not node is Dictionary:
			return "'%s' is not inside an object" % segment.key
		if not wants_object:
			return _array_at(node, segment.key, prefix, inherited, inside_array, false)
		var existing: Variant = node.get(segment.key)
		if existing is Dictionary:
			return existing
		if existing != null:
			return "'%s' is not an object" % segment.key
		# Objects merge during inheritance, so a partial object is enough here.
		var created := {}
		node[segment.key] = created
		return created
	if not node is Array:
		return "Not a list"
	var position := _position(node, segment)
	if position < 0:
		return "No entry %s" % _label(segment)
	return node[position]


## The array at node[key], copying an inherited array into the def first.
## `create` allows a new empty array when neither the def nor its parent has one.
static func _array_at(node: Dictionary, key: String, segments: Array, inherited: Callable, inside_array: bool, create: bool) -> Variant:
	var existing: Variant = node.get(key)
	if existing is Array:
		return existing
	if existing != null:
		return "'%s' is not a list" % key
	var result: Array = []
	if not node.has(key) and not inside_array:
		var source: Array = inherited.call(segments)
		if source[0] and source[1] is Array:
			result = source[1].duplicate(true)
		elif source[0]:
			return "'%s' is not a list" % key
		elif not create:
			return "No list at '%s'" % key
	elif not create:
		return "No list at '%s'" % key
	node[key] = result
	return result


static func _label(segment: Dictionary) -> String:
	return "[%d]" % segment.index if segment.has("index") else "[%s]" % segment.select


static func _op_set(authored: Dictionary, segments: Array, value: Variant, inherited: Callable) -> String:
	var found := _container(authored, segments, inherited)
	if found.size() == 1:
		return found[0]
	var container: Variant = found[0]
	var last: Dictionary = found[1]
	var inside_array: bool = found[2]
	var copy: Variant = value.duplicate(true) if value is Array or value is Dictionary else value
	if last.has("key"):
		if not container is Dictionary:
			return "Not an object"
		if value == null and inside_array:
			container.erase(last.key)
		else:
			# A stored null removes the inherited field when inheritance resolves.
			container[last.key] = copy
		return ""
	if not container is Array:
		return "Not a list"
	var position := _position(container, last)
	if position < 0:
		return "No entry %s" % _label(last)
	if value == null:
		container.remove_at(position)
	else:
		container[position] = copy
	return ""


static func _list(authored: Dictionary, segments: Array, inherited: Callable, create: bool) -> Variant:
	var found := _container(authored, segments, inherited)
	if found.size() == 1:
		return found[0]
	var container: Variant = found[0]
	var last: Dictionary = found[1]
	var inside_array: bool = found[2]
	if last.has("key"):
		if not container is Dictionary:
			return "Not an object"
		return _array_at(container, last.key, segments, inherited, inside_array, create)
	if not container is Array:
		return "Not a list"
	var position := _position(container, last)
	if position < 0:
		return "No entry %s" % _label(last)
	if not container[position] is Array:
		return "Entry %s is not a list" % _label(last)
	return container[position]


static func _op_append(authored: Dictionary, segments: Array, value: Variant, inherited: Callable) -> String:
	var target: Variant = _list(authored, segments, inherited, true)
	if target is String:
		return target
	var values: Array = value if value is Array else [value]
	for entry in values:
		target.append(entry.duplicate(true) if entry is Array or entry is Dictionary else entry)
	return ""


static func _op_remove(authored: Dictionary, segments: Array, value: Variant, inherited: Callable) -> String:
	var target: Variant = _list(authored, segments, inherited, false)
	if target is String:
		return target
	var values: Array = value if value is Array else [value]
	var missing := PackedStringArray()
	for entry in values:
		var removed := false
		for position in range(target.size() - 1, -1, -1):
			var item: Variant = target[position]
			var matches := SchemaRegistry.same_value(item, entry)
			if not matches and item is Dictionary:
				matches = (entry is String and str(item.get("id", "")) == entry) or (entry is Dictionary and item == entry)
			if matches:
				target.remove_at(position)
				removed = true
		if not removed:
			missing.append(JSON.stringify(entry))
	return "" if missing.is_empty() else "Nothing to remove: %s" % ", ".join(missing)
