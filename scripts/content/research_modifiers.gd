extends RefCounted

# Runtime and pack checks share the inspector registry's primitive schemas.
static func valid(modifier: Variant, materials: Array[String], schemas: SchemaRegistry = null) -> bool:
	if not modifier is Dictionary:
		return false
	var registry := Content.db().schemas if schemas == null else schemas
	if not registry.validate("_research_modifiers", modifier).problems.is_empty():
		return false
	if modifier.id == "extractable_materials":
		for id: String in modifier.values:
			if id not in materials:
				return false
	return true
