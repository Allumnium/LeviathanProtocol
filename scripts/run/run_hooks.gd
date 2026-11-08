class_name RunHooks
extends RefCounted

const LIMIT := 64
var _handlers: Dictionary = {}

func register(hook: String, id: String, handler: Callable, priority := 0) -> bool:
	if hook.is_empty() or id.is_empty() or not handler.is_valid():
		return false
	if not _handlers.has(hook):
		_handlers[hook] = []
	if _handlers[hook].any(func(entry: Dictionary) -> bool: return entry.id == id):
		return false
	_handlers[hook].append({"id": id, "handler": handler, "priority": priority})
	_handlers[hook].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.id < b.id if a.priority == b.priority else a.priority < b.priority)
	return true

func drain(tx) -> bool:
	var index := 0
	while index < tx.hooks.size():
		if index >= LIMIT:
			tx.error = "Hook cascade exceeded %d events; transaction cancelled." % LIMIT
			return false
		var event: Dictionary = tx.hooks[index]
		index += 1
		for entry: Dictionary in _handlers.get(event.name, []):
			entry.handler.call(tx, event.data.duplicate(true))
			if not tx.error.is_empty():
				return false
	return true
