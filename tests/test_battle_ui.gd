extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in range(5):
		await process_frame

func member(ship: HangarShip, id: String) -> BattleSimulation.Combatant:
	var actor := BattleSimulation.Combatant.new()
	actor.owned_ship = ship
	actor.entity_id = id
	actor.faction = BattleSimulation.Faction.PLAYER
	actor.stats = ship.get_stats()
	actor.integrity = ship.hull_hp
	return actor

func run() -> void:
	root.size = Vector2i(1280, 720)
	await _transport()
	await _targeting()
	print("BATTLE UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _transport() -> void:
	var sim := BattleSimulation.new()
	var ship := HangarShip.new()
	check(ship.initialize_chassis("flagship_civic", 1, true), "Transport display fixture initializes")
	ship.mounts.cargo = {"uid": "1", "equipment_id": "cargo_hold", "rank": 1,
		"load": {"kind": "cargo", "quantity": 7, "unit_value": 6, "origin": 0}}
	ship.mounts.upper_port = {"uid": "2", "equipment_id": "passenger_cabin", "rank": 1,
		"load": {"kind": "passengers", "quantity": 3, "unit_value": 8, "origin": 0}}
	ship.mounts.upper_starboard = {"uid": "3", "equipment_id": "passenger_cabin", "rank": 1}
	ship.rebuild_units()
	var actor := member(ship, "transport")
	check(sim.register_entity(actor), "Loaded transport registers")
	sim.other_entities.erase(actor)
	sim.players.append(actor)
	sim._rebuild_member_cache()
	var header: Control = load("res://scripts/command_header.gd").new()
	root.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var readout: Control = load("res://scripts/battle_transport_readout.gd").new()
	readout.simulation = sim
	header.left.add_child(readout)
	await settle()
	check(readout.values.cargo.text == "x7" and readout.values.passengers.text == "x3",
		"Transport counters show goods and people, not occupied bays or capacity")
	for resolution in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		check(header.left.get_global_rect().encloses(readout.get_global_rect())
			and root.get_visible_rect().encloses(readout.get_global_rect()),
			"Box/person counters fit the header at %d" % resolution.x)
		for kind: String in ["cargo", "passengers"]:
			var label: Label = readout.values[kind]
			check(label.get_line_count() == 1 and label.get_minimum_size().x <= label.size.x,
				"Transport multiplier has real single-line width at %d" % resolution.x)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/battle-transport-%d.png" % resolution.x)
	ship.hull_hp = 0
	await settle()
	check(readout.values.cargo.text == "x7" and readout.values.passengers.text == "x3",
		"Zero hull remains alive and keeps its carried quantities")
	ship.hull_hp = -1
	await settle()
	check(readout.visible and readout.values.cargo.text == "x0" and readout.values.passengers.text == "x0",
		"Destroyed host immediately loses its displayed loads, retaining meaningful zero counters")
	ship.hull_hp = ship.hull_max
	ship.mounts.cargo.erase("load")
	ship.mounts.upper_port.erase("load")
	await settle()
	check(readout.values.cargo.text == "x0" and readout.values.passengers.text == "x0",
		"Empty loads never display equipment capacity as carried goods")
	sim.players.clear()
	await settle()
	check(readout.values.cargo.text == "x0", "Nondeployed ships do not contribute")
	header.queue_free()
	await settle()
	var empty: Control = load("res://scripts/battle_transport_readout.gd").new()
	empty.simulation = sim
	root.add_child(empty)
	await settle()
	check(not empty.visible, "Battles without transport equipment omit the empty instrument")
	empty.queue_free()
	await settle()

func _targeting() -> void:
	root.size = Vector2i(1280, 720)
	var sim := BattleSimulation.new()
	sim.battle_id = "ui/targeting"
	sim.visibility_enabled = true
	# Exercise retained ability UI without enabling equipment purchases or abilities in physical runs.
	var ship := HangarShip.new()
	check(ship.initialize_chassis("flagship_basic", 1, true), "Targeting fixture initializes")
	var ids: Array[String] = ["scan", "seismic_cut", "ion_pulse", "gravity_well"]
	for id: String in ids:
		var part := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
		part.definition_id = GameDefinitions.find("abilities", id).source_equipment_id
		ship._append_mount(id, Vector2(256, 256), part)
	var source := member(ship, "source")
	check(sim.register_entity(source), "Targeting source registers")
	sim.other_entities.erase(source)
	sim.players.append(source)
	sim._rebuild_member_cache()
	check(sim.abilities.configure({"ability_ids": ids}), "Existing implemented ability definitions configure")
	var rock := BattleSimulation.Combatant.new()
	rock.entity_id = "rock"
	rock.faction = BattleSimulation.Faction.NEUTRAL
	rock.tags = {"asteroid": true}
	rock.integrity = 1000
	rock.stats = ShipStats.new()
	rock.radius = 20
	rock.position = Vector2(100, 0)
	rock.previous_position = rock.position
	check(sim.register_entity(rock), "Visible rock registers")
	var enemy := BattleSimulation.Combatant.new()
	enemy.entity_id = "enemy"
	enemy.integrity = 1000
	enemy.stats = ShipStats.new()
	enemy.radius = 20
	enemy.position = rock.position
	enemy.previous_position = enemy.position
	check(sim.register_entity(enemy), "Visible enemy registers")
	sim.refresh_visibility()
	var visuals: Control = load("res://scripts/battle_visuals.gd").new()
	visuals.simulation = sim
	root.add_child(visuals)
	visuals.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar: Control = load("res://scripts/battle_ability_bar.gd").new()
	bar.simulation = sim
	bar.visuals = visuals
	root.add_child(bar)
	await settle()
	bar.position = Vector2(8, root.get_visible_rect().size.y - bar.get_combined_minimum_size().y - 8)
	var fingerprints: Array[PackedByteArray] = []
	for id: String in ids:
		bar.begin_targeting(id)
		bar.set_preview(Vector2(100, 0))
		await settle()
		check(bar.targeting and bar.status.text.is_empty() and bar.action_buttons[id].button_pressed,
			"Selected %s uses a pressed named button without click-instruction prose" % id)
		check(visuals.ability_preview.valid and visuals.ability_preview.sources == [source],
			"%s preview preserves cast validation and source range" % id)
		var valid_shape: Array = visuals.ability_reticle(id, true)
		check(not valid_shape.is_empty()
			and visuals.ability_reticle(id, false).size() == valid_shape.size() + 2,
			"%s has its own reticle and shape-based invalid X" % id)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png("res://.local/battle-target-%s.png" % id)
			var scale := Vector2(image.get_size()) / root.get_visible_rect().size
			var center: Vector2 = (visuals.world_transform() * Vector2(100, 0)) * scale
			var region := Rect2i(Vector2i(center - Vector2(13, 13) * scale), Vector2i(Vector2(26, 26) * scale))
			var pixels := image.get_region(region).get_data()
			check(not fingerprints.has(pixels), "%s renders a visibly distinct target reticle" % id)
			fingerprints.append(pixels)
			source.position = Vector2(1000, 0)
			sim.refresh_visibility()
			bar.set_preview(Vector2(100, 0))
			await settle()
			await RenderingServer.frame_post_draw
			var invalid_image := root.get_texture().get_image()
			check(not visuals.ability_preview.valid and invalid_image.get_region(region).get_data() != pixels,
				"%s renders invalid-target feedback at the same pointer position" % id)
			invalid_image.save_png("res://.local/battle-target-%s-invalid.png" % id)
			source.position = Vector2.ZERO
			sim.refresh_visibility()
		bar.set_preview(Vector2(1000, 0))
		await settle()
		check(not visuals.ability_preview.valid and not bar.cast_at(Vector2(1000, 0))
			and bar.status.text == "Unavailable" and bar.targeting,
			"Invalid %s stays in targeting with an explicit failure" % id)
		bar.cancel_targeting()
		await settle()
		check(not bar.targeting and visuals.ability_preview.is_empty()
			and not bar.action_buttons[id].button_pressed, "Cancellation clears %s reticle and selected state" % id)
	var far_ship := HangarShip.new()
	check(far_ship.initialize_chassis("flagship_basic", 2), "Alternative source fixture initializes")
	var scanner := ShipPart.new(0, 0, Vector2i.ZERO, [], ShipPartStats.new())
	scanner.definition_id = "command_center"
	far_ship._append_mount("scan", Vector2(256, 256), scanner)
	var far_source := member(far_ship, "far-source")
	far_source.position = Vector2(1000, 0)
	check(sim.register_entity(far_source), "Alternative source registers")
	sim.other_entities.erase(far_source)
	sim.players.append(far_source)
	sim._rebuild_member_cache()
	sim.refresh_visibility()
	bar.begin_targeting("scan")
	bar.set_preview(Vector2(100, 0))
	await settle()
	var far_index: int = bar._source_ids.find(far_source.entity_id) + 1
	bar.source_picker.select(far_index)
	bar.source_picker.item_selected.emit(far_index)
	await settle()
	check(visuals.ability_preview.sources == [far_source] and not visuals.ability_preview.valid,
		"Explicit source selection shows only that source's range and rejects unreachable casts")
	bar.source_picker.select(0)
	bar.source_picker.item_selected.emit(0)
	await settle()
	check(visuals.ability_preview.sources.size() == 2 and visuals.ability_preview.valid,
		"Auto source restores all eligible ranges and valid targeting")
	sim.ability_commit = func(_proposal: Dictionary) -> bool: return false
	var before := sim.abilities.snapshot()
	check(not bar.cast_at(Vector2(100, 0)) and bar.status.text == "Save failed"
		and bar.targeting and sim.abilities.snapshot() == before,
		"Failed ability save is explicit and preserves cooldowns, targeting and resources")
	bar.auto_button.button_pressed = false
	check(bar.status.text == "Save failed" and bar.auto_button.button_pressed
		and sim.abilities.snapshot() == before, "Failed Auto change restores saved toggle and keeps the error explicit")
	sim.ability_commit = func(_proposal: Dictionary) -> bool: return true
	bar.auto_button.button_pressed = false
	check(bar.status.text.is_empty() and not sim.abilities.state.auto.scan,
		"Successful retry clears stale save-failure prose")
	check(bar.cast_at(Vector2(100, 0)) and not bar.targeting and visuals.ability_preview.is_empty(),
		"Successful cast clears the reticle")
	await settle()
	check(bar.action_buttons.scan.text == "SCAN 25" and bar.action_buttons.scan.disabled,
		"Exact cooldown seconds remain visible")
	sim.abilities.state.cooldowns.scan = 0
	bar.begin_targeting("scan")
	sim.abilities.state.cooldowns.scan = 1
	await settle()
	check(not bar.targeting, "Automatic cast cooldown cancels stale manual targeting")
	sim.abilities.state.cooldowns.scan = 0
	bar.begin_targeting("scan")
	ship.hull_hp = -1
	far_ship.hull_hp = -1
	await settle()
	check(not bar.targeting and visuals.ability_preview.is_empty(), "Source loss cancels targeting")
	bar.queue_free()
	visuals.queue_free()
	await settle()
