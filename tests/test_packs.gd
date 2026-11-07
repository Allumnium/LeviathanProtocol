extends SceneTree

const FIXTURES := "res://tests/fixtures/content"
const GOOD := FIXTURES + "/good"
const BROKEN := FIXTURES + "/broken"
const SCHEMAS := FIXTURES + "/schemas"

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func run() -> void:
	ExprContexts.register("fixture", {"credits": "number", "danger": "number", "flag": "bool"})
	check_versions()
	check_paths_and_merge()
	check_schema_keywords()
	check_good_packs()
	check_broken_packs()
	check_content_facade()
	check_shipped_packs()
	ExprContexts.unregister("fixture")
	print("test_packs: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func load_roots(roots: Array) -> DefDatabase:
	return PackLoader.new().load_packs(roots, [SCHEMAS])


func find_problem(db: DefDatabase, pack: String, def: String, path: String, fragment: String, severity := ContentProblems.ERROR) -> bool:
	for item in db.problems.items:
		if item.severity == severity and item.pack == pack and item.def == def and item.path == path and str(item.message).contains(fragment):
			return true
	return false


func check_versions() -> void:
	check(PackManifest.satisfies("1.2.0", ">=1.0 <2"), "range >=1.0 <2 accepts 1.2.0")
	check(not PackManifest.satisfies("2.0.0", ">=1.0 <2"), "range >=1.0 <2 rejects 2.0.0")
	check(PackManifest.satisfies("1.4.0", "^1.2") and not PackManifest.satisfies("2.1.0", "^1.2"), "caret keeps the major version")
	check(PackManifest.satisfies("1.2.5", "~1.2") and not PackManifest.satisfies("1.3.0", "~1.2"), "tilde keeps the minor version")
	check(PackManifest.satisfies("1.2.0", "1.2") and PackManifest.satisfies("0.1.0", "*"), "exact and wildcard ranges")
	check(PackManifest.parse_version("1.x").is_empty() and not PackManifest.valid_range(">=one"), "malformed versions are rejected")


func check_paths_and_merge() -> void:
	var segments := DefPatcher.parse_path("a.b[c][2].d")
	check(segments == [{"key": "a"}, {"key": "b"}, {"select": "c"}, {"index": 2}, {"key": "d"}], "path parses keys, selectors and indices")
	for bad in ["", "a..b", "[0]", "a[", "a.", "a[]", "a[0]b"]:
		check(DefPatcher.parse_path(bad).is_empty(), "malformed path '%s' is rejected" % bad)
	var merged: Dictionary = DefPatcher.merge({"a": {"b": 1, "c": 2}, "l": [1, 2], "gone": 1}, {"a": {"c": null, "d": 3}, "l": [3], "gone": null})
	check(merged == {"a": {"b": 1, "d": 3}, "l": [3]}, "objects merge, arrays replace and null removes")


func check_schema_keywords() -> void:
	var registry := SchemaRegistry.new()
	registry.register("thing", {
		"type": "object",
		"propertyNames": {"pattern": "^[a-z_]+$"},
		"additionalProperties": {"type": "integer"},
		"properties": {
			"mode": {"oneOf": [{"type": "number"}, {"type": "integer"}]},
			"fixed": {"const": "yes"},
			"list": {"type": "array", "uniqueItems": true, "maxItems": 3},
		},
	})
	var result := registry.validate("thing", {"mode": 2, "fixed": "no", "list": [1, 1, 2, 3], "Extra": 4, "count": 1.5})
	var messages := {}
	for item in result.problems:
		messages[item.path] = messages.get(item.path, "") + item.message + ";"
	check(str(messages.get("mode", "")).contains("more than one"), "oneOf rejects a value matching two forms")
	check(str(messages.get("fixed", "")).contains("Must be \"yes\""), "const is enforced")
	check(str(messages.get("list[1]", "")).contains("Duplicate"), "uniqueItems reports the repeated entry")
	check(str(messages.get("list", "")).contains("At most 3"), "maxItems is enforced")
	check(str(messages.get("Extra", "")).contains("pattern"), "propertyNames checks keys")
	check(str(messages.get("count", "")).contains("whole number"), "additionalProperties schema checks extra values")
	check(registry.validate("thing", {"mode": 2.5, "fixed": "yes", "x": 3}).problems.is_empty(), "a valid object passes")


func check_good_packs() -> void:
	var db := load_roots([GOOD])
	check(db.problems.errors().is_empty(), "good packs load without errors: %s" % db.problems.text())
	check(db.problems.warnings().size() == 2 and find_problem(db, "base", "brick", "icon", "Missing file", ContentProblems.WARNING), "missing art is a warning")
	check(db.packs.map(func(m: PackManifest) -> String: return m.id) == ["base", "addon"], "dependencies load first")
	check(db.ids("widget") == PackedStringArray(["scout", "brick", "brick@2", "group/drone", "raider"]), "concrete defs keep load and file order")
	check(db.get_def("widget", "hull_template").is_empty() and db.meta("widget", "hull_template").abstract, "abstract templates are excluded")
	check(db.meta("widget", "hull_template").notes == "Shared hull", "notes are kept as metadata")
	var scout := db.get_def("widget", "scout")
	check(scout.stats == {"hull": 25.0, "speed": 7.0}, "patch sets a field and a template patch propagates")
	check(scout.tags == ["light", "patched"], "append copies the inherited list first")
	check(scout.slots == [{"id": "fore", "size": 2.0}, {"id": "aft", "size": 2.0}], "patch selects list entries by id")
	check(scout.kind == "small" and scout.id == "scout", "inherited fields and id are present")
	var brick := db.get_def("widget", "brick")
	check(not brick.has("kind") and brick.tags == ["heavy"], "null removes inherited fields and lists replace")
	check(brick.slots == [{"id": "fore", "size": 1.0}], "remove takes list entries by id")
	var brick2 := db.get_def("widget", "brick@2")
	check(brick2.stats == {"hull": 40.0, "speed": 7.0} and brick2.slots == brick.slots, "variants inherit patched parents")
	var raider := db.get_def("widget", "addon:raider")
	check(raider.parts == ["blaster", "base:shield"] and raider.slots == [{"id": "mid", "size": 3.0}], "dependent packs inherit across packs")
	check(db.resolve_id("gadget", "blaster", "addon") == "base:blaster", "unqualified references search dependencies")
	check(db.get_def("gadget", "shield").mode == {"rate": 0.5} and db.get_def("gadget", "lance").power == 5.0, "single-def files and nested files load")
	check(db.get_def("widget", "group/drone").name == "Drone", "slash variants are valid IDs")
	var weight := db.formula("widget", "scout", "weight")
	check(weight != null and is_equal_approx(weight.number({"credits": 500}), 6.0), "formula fields compile and evaluate")
	var enabled := db.formula("widget", "scout", "enabled_if")
	check(enabled.test({"danger": 1}) and not enabled.test({"danger": 5}), "condition fields evaluate")
	check(db.formula("widget", "brick", "weight").number() == 2.0, "literal numbers become constant formulas")
	check(db.formula("widget", "group/drone", "enabled_if").test(), "literal conditions become constant formulas")
	check(db.formula("widget", "raider", "weight") == null, "absent formula fields have no formula")
	check(scout.is_read_only() and scout.stats.is_read_only() and scout.slots[0].is_read_only(), "defs are frozen")
	check(db.content_hash.length() == 16 and db.content_hash == load_roots([GOOD]).content_hash, "content hash is stable")


func check_broken_packs() -> void:
	var db := load_roots([GOOD, BROKEN])
	var enabled := db.packs.map(func(m: PackManifest) -> String: return m.id)
	enabled.sort()
	check(enabled == ["addon", "base", "conflict_mod", "optional_patch"], "only healthy packs load: %s" % [enabled])
	for pack_id in ["needs_missing", "needs_new_base", "cycle_a", "cycle_b", "after_cycle", "bad_schema", "needs_bad", "bad_ref", "bad_formula", "bad_patch", "patch_breaks_schema", "broken_json", "bad_ids"]:
		check(db.disabled.has(pack_id), "%s is disabled" % pack_id)
	check(find_problem(db, "needs_missing", "", "depends", "'nothere', which is not installed"), "missing dependency")
	check(find_problem(db, "needs_new_base", "", "depends", "Needs base >=2.0; found 1.2.0"), "dependency version mismatch")
	check(find_problem(db, "cycle_a", "", "depends", "cycle") and find_problem(db, "cycle_b", "", "depends", "cycle"), "dependency cycle")
	check(find_problem(db, "after_cycle", "", "depends", "pack 'cycle_a' did not load"), "dependents of a cycle are disabled, not blamed")
	check(find_problem(db, "bad_schema", "bad_hull", "stats.hull", "Expected a number, got text"), "type error path")
	check(find_problem(db, "bad_schema", "bad_hull", "colour", "Unknown field"), "unknown field path")
	check(find_problem(db, "bad_schema", "bad_hull", "slots[fore].size", "at least 1"), "list entries are named by id")
	check(find_problem(db, "bad_schema", "bad_hull", "tags[0]", "pattern"), "shared schema references apply")
	check(find_problem(db, "needs_bad", "", "depends", "pack 'bad_schema' did not load"), "broken dependency disables dependents")
	check(find_problem(db, "bad_ref", "dangling", "parts[1]", "No gadget named 'blastr'. Did you mean 'blaster'?"), "missing reference with suggestion")
	check(find_problem(db, "bad_ref", "orphan", "parent", "No widget named 'nope'"), "missing parent")
	check(find_problem(db, "bad_formula", "wonky", "weight", "column"), "formula syntax error reports a column")
	check(find_problem(db, "bad_formula", "wonky", "enabled_if", "Expected a condition"), "formula type error")
	check(find_problem(db, "bad_formula", "literal", "weight", "Expected a formula or number value"), "wrong literal for a formula")
	check(find_problem(db, "bad_patch", "oops", "set.slots[missing].size", "No entry [missing]"), "bad patch path")
	check(find_problem(db, "patch_breaks_schema", "soften", "stats.hull", "after patch patch_breaks_schema:soften changed base:brick"), "schema errors from a patch blame the patching pack")
	check(find_problem(db, "conflict_mod", "harder_scout", "set.stats.hull", "Pack 'addon' also sets stats.hull", ContentProblems.WARNING), "patch conflicts warn")
	check(find_problem(db, "optional_patch", "compat", "target", "'elsewhere' is not loaded", ContentProblems.WARNING), "patches for absent packs are skipped")
	check(find_problem(db, "broken_json", "", "", "Invalid JSON at line 4"), "JSON syntax errors report a line")
	check(find_problem(db, "bad_ids", "", "defs[0].id", "Def id must be"), "invalid def IDs")
	check(find_problem(db, "bad_ids", "thing", "def", "Unknown def type 'gizmo'"), "unknown def types")
	check(find_problem(db, "", "", "id", "Pack id 'base' is already used"), "duplicate pack IDs")
	check(find_problem(db, "", "", "", "Folder has no pack.json", ContentProblems.WARNING), "folders without manifests warn")
	var scout := db.get_def("widget", "scout")
	check(scout.stats.hull == 30, "later patches win and disabled patches leave no changes")
	check(db.get_def("widget", "brick").stats.hull == 10, "a patch that broke a def is removed with its pack")
	check(not db.problems.text().is_empty() and ContentProblems.format(db.problems.items[0]).begins_with(db.problems.items[0].severity), "problems format as text")


func check_content_facade() -> void:
	var db := load_roots([GOOD])
	Content.set_database(db)
	check(Content.get_def("gadget", "blaster").power == 3 and Content.all("gadget").size() == 3, "Content reads the set database")
	check(Content.formula("widget", "scout", "weight") != null and Content.has_def("widget", "raider"), "Content exposes formulas and lookups")
	Content.set_database(null)


func check_shipped_packs() -> void:
	var db := PackLoader.new().load_packs(["res://packs"], Content.SCHEMA_DIRS)
	check(db.problems.items.is_empty(), "shipped packs load without problems: %s" % db.problems.text())
	check(db.has_pack("core") and db.has_pack("leviathan"), "core and leviathan packs load")
	for def_type in ["material", "part", "research", "ability", "environment", "goods", "encounter", "campaign_node", "campaign_edge", "chassis", "equipment", "loadout", "travel_tuning", "location", "event"]:
		check(not db.all(def_type).is_empty(), "shipped packs define %s" % def_type)
	var stale := SchemaExporter.stale(SchemaExporter.render())
	check(stale.is_empty(), "schemas/json is current; run tools/export_schemas.gd: %s" % ", ".join(stale))
