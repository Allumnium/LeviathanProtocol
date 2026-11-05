extends Control

const UiKit = preload("res://scripts/ui_kit.gd")
const ShipLoadouts = preload("res://scripts/ship_loadouts.gd")

const MAP_SCENE_PATH := "res://scenes/game_map.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const SceneFadeScript = preload("res://scripts/scene_fade.gd")
const SHOOT_SOUND: AudioStream = preload("res://assets/audio/sfx/shoot-weapon.wav")
const SHIELD_HIT_SOUND: AudioStream = preload("res://assets/audio/sfx/shieldHit.wav")
const ALIEN_EXPLOSION_SOUND: AudioStream = preload("res://assets/audio/sfx/alien_explode.wav")
const SHIP_EXPLOSION_SOUND: AudioStream = preload("res://assets/audio/sfx/ship_explosion.mp3")
const AUTO_CAMERA_RETURN_DELAY := 5.0
const AUTO_CAMERA_MARGIN := Vector2(72.0, 64.0)
const AUTO_CAMERA_SMOOTHING := 4.0
const COMBAT_BLASTER_VOLUME_DB := -30.0
const COMBAT_IMPACT_VOLUME_DB := -10.0
const ALIEN_EXPLOSION_VOLUME_DB := -30.0
const FINISHING_SHOT_TIME_SCALE := 0.1
const FINISHING_SHOT_WINDOW_SECONDS := 0.25
const FINISHING_SHOT_CAMERA_ZOOM := 2.5
const FINISHING_SHOT_CAMERA_TRANSITION_SECONDS := 0.4
const RESULT_DELAY_SECONDS := 1.0
const SIMULATION_TICK_SECONDS := 1.0 / 30.0
const MAX_SIMULATION_STEPS_PER_FRAME := 8
const MIN_CAMERA_ZOOM := 0.05

@onready var visuals: BattleVisuals = $BattleVisuals
@onready var battle_speed_controls: HBoxContainer = $BattleSpeedControls
@onready var pause_button: Button = $BattleSpeedControls/PauseButton
@onready var fast_forward_button: Button = $BattleSpeedControls/FastForwardButton
@onready var five_times_button: Button = $BattleSpeedControls/FiveTimesButton
@onready var destroy_neutral_targets: CheckBox = $DestroyNeutralTargets
@onready var defeat_dialog: Control = $DefeatDialog
@onready var defeat_accept_button: Button = $DefeatDialog/CenterContainer/Panel/Contents/ButtonCenter/AcceptButton
@onready var defeat_close_button: TextureButton = $DefeatDialog/CenterContainer/Panel/CloseX

var simulation := BattleSimulation.new()
var _dragging := false
var _left_pressed := false
var _left_dragged := false
var _left_press_screen := Vector2.ZERO
var _pan_resume_seconds := 0.0
var _zoom_resume_seconds := 0.0
var _finished := false
var _run_lost := false
var _report_open := false
var _battle_credit_reward := 0
var _cinematic_projectile: BattleSimulation.Projectile
var _cinematic_camera_start := Vector2.ZERO
var _cinematic_zoom_start := 1.0
var _cinematic_transition_elapsed := 0.0
var _result_delay_remaining := -1.0
var _pending_result_won := false
var ability_bar: Control
var _paused_before_aim := false
var _simulation_accumulator := 0.0
var repair_label: ResourceText
var objective_label: Label
var _settlement_error := false
var command_header: Container
var battle_readouts: VBoxContainer
var missile_readout: Label
var missile_button: Button
var squadron_readout: Control
var enemy_readout: Control
var selection_scroll: ScrollContainer
var selection_details: VBoxContainer
var selection_status: Label
var battle_frame: VBoxContainer
var battlefield: Control
var footer_panel: PanelContainer
var deploying := true
var begin_button: Button
var deployment_feedback: Label
var _deployment_origins: Dictionary = {}
var _deployment_press := Vector2.ZERO
var _deployment_dragging := false
var _deployment_box := false


func _ready() -> void:
	AudioManager.play_battle_music(GameState.pending_encounter.get("template_id", "") == "bastion_warden")
	SceneFadeScript.reveal(self)
	if not GameState.battle_pending or not simulation.setup_owned(
		GameState.get_deployed_fleet(), GameState.battle_aliens,
		GameState.allied_salvage_chance(), GameState.laser_upgrade_level, GameState.battle_simulation_seed(), GameState.battle_support_context()
	):
		push_error("Cannot open battle without a valid deployment.")
		GameState.cancel_battle()
		set_physics_process(false)
		call_deferred("_return_to_map")
		return
	simulation.victory_materials = GameState.battle_material_rewards()
	simulation.battle_id = GameState.battle_identity()
	if not simulation.credits_only:
		simulation.ability_commit = _commit_battle_ability
	simulation.asteroid_field.pickup_commit = _commit_asteroid_pickup
	if simulation.visibility_enabled:
		var radar: Control = load("res://scripts/battle_radar.gd").new()
		radar.name = "Radar"
		radar.simulation = simulation
		add_child(radar)
		radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		radar.offset_left = -120
		radar.offset_top = -96
		radar.offset_right = -8
		radar.offset_bottom = -8
	if not simulation.abilities.available.is_empty():
		ability_bar = load("res://scripts/battle_ability_bar.gd").new()
		ability_bar.name = "AbilityBar"
		ability_bar.simulation = simulation
		ability_bar.visuals = visuals
		ability_bar.targeting_changed.connect(_ability_targeting_changed)
	if not simulation.set_objective_targets(GameState.battle_objective_ids()):
		push_error("Battle objective refers to an unknown target.")
		GameState.cancel_battle()
		set_physics_process(false)
		call_deferred("_return_to_map")
		return
	simulation.set_destroy_all_neutral_targets(GameState.destroy_all_neutral_targets)
	repair_label = ResourceText.new()
	objective_label = Label.new()
	objective_label.text = simulation.encounter.label(simulation)
	_build_header()
	_build_battle_panels()
	destroy_neutral_targets.set_pressed_no_signal(GameState.destroy_all_neutral_targets)
	destroy_neutral_targets.hide()
	destroy_neutral_targets.toggled.connect(_on_destroy_neutral_targets_toggled)
	AudioManager.connect_ui_button(pause_button, &"detail")
	AudioManager.connect_ui_button(fast_forward_button, &"detail")
	AudioManager.connect_ui_button(five_times_button, &"detail")
	simulation.weapon_fired.connect(
		AudioManager.play_sfx.bind(SHOOT_SOUND, 1.0, COMBAT_BLASTER_VOLUME_DB, 35)
	)
	simulation.shield_hit.connect(
		AudioManager.play_sfx.bind(SHIELD_HIT_SOUND, 1.0, COMBAT_IMPACT_VOLUME_DB)
	)
	simulation.ship_destroyed.connect(_on_ship_destroyed)
	simulation.projectile_impacted.connect(visuals.add_projectile_impact)
	visuals.simulation = simulation
	visuals.deployment_area = BattleSimulation.deployment_area(GameState.pending_encounter)
	for member: BattleSimulation.Combatant in simulation.players:
		member.position = (BattleSimulation.PLAYER_FORMATION_CENTER \
			+ member.owned_ship.formation * BattleSimulation.DEPLOYMENT_SCALE).clamp(
				visuals.deployment_area.position + Vector2.ONE * member.radius,
				visuals.deployment_area.end - Vector2.ONE * member.radius)
		member.previous_position = member.position
	simulation.refresh_visibility()
	battle_speed_controls.hide()
	if ability_bar != null:
		ability_bar.input_enabled = false
		ability_bar.refresh()
	visuals.camera_zoom = clampf(minf(visuals.size.x / 850.0, visuals.size.y / 600.0), 0.25, 2.5)
	fast_forward_button.set_pressed_no_signal(GameState.battle_speed == 2)
	five_times_button.set_pressed_no_signal(GameState.battle_speed == 5)
	pause_button.toggled.connect(_on_pause_toggled)
	fast_forward_button.toggled.connect(_on_speed_toggled.bind(2))
	five_times_button.toggled.connect(_on_speed_toggled.bind(5))
	AudioManager.connect_ui_button(defeat_accept_button)
	AudioManager.connect_ui_button(defeat_close_button)
	defeat_accept_button.pressed.connect(_return_to_main_menu)
	defeat_close_button.pressed.connect(_return_to_main_menu)

func _build_header() -> void:
	var column := VBoxContainer.new()
	column.name = "BattleFrame"
	battle_frame = column
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	move_child(column, visuals.get_index() + 1)
	command_header = preload("res://scripts/command_header.gd").new()
	preload("res://scripts/panel_slide.gd").wrap(column, command_header, Vector2.UP)
	battle_speed_controls.reparent(command_header.middle)
	battle_speed_controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	battle_speed_controls.mouse_filter = Control.MOUSE_FILTER_PASS
	battle_speed_controls.add_theme_constant_override("separation", 2)
	var glyphs := preload("res://scripts/time_control.gd")
	glyphs.decorate(pause_button, "pause")
	glyphs.decorate(fast_forward_button, "play")
	glyphs.decorate(five_times_button, "fast")
	for speed: int in [2, 5]:
		var label := Label.new()
		label.name = "Speed%dLabel" % speed
		label.text = "%dx" % speed
		label.theme_type_variation = &"HeaderResearch"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		battle_speed_controls.add_child(label)
		battle_speed_controls.move_child(label, 2 if speed == 2 else 4)
	battle_readouts = VBoxContainer.new()
	battle_readouts.name = "BattleReadouts"
	battle_readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	column.add_child(margin)
	margin.add_child(battle_readouts)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.theme_type_variation = &"HeaderResearch"
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	command_header.course.add_child(objective_label)
	begin_button = preload("res://scripts/ui_kit.gd").button("BEGIN COMBAT", _begin_combat)
	begin_button.name = "BeginCombat"
	begin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_header.course.add_child(begin_button)
	objective_label.reparent(battle_readouts)
	deployment_feedback = Label.new()
	deployment_feedback.name = "DeploymentFeedback"
	deployment_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deployment_feedback.add_theme_color_override("font_color", Color("ffd28a"))
	deployment_feedback.hide()
	battle_readouts.add_child(deployment_feedback)
	battle_readouts.add_child(repair_label)
	var transport := preload("res://scripts/battle_transport_readout.gd").new()
	transport.simulation = simulation
	command_header.left.add_child(transport)
	missile_readout = Label.new()
	missile_readout.name = "BattleMissiles"
	missile_readout.theme_type_variation = &"HeaderResearch"
	missile_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	missile_readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	missile_readout.text = "MISSILES %d" % simulation.missile_supply
	var settings_margin := MarginContainer.new()
	settings_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_margin.add_theme_constant_override("margin_right", 36)
	settings_margin.add_child(missile_readout)
	command_header.right.add_child(settings_margin)

func _commit_asteroid_pickup(id: String, materials: Array, field: Dictionary) -> bool:
	return GameState.commit_asteroid_pickup(simulation, id, materials, field)


func _physics_process(delta: float) -> void:
	if deploying:
		return
	if UiNavigation.settings_open():
		return
	if _finished:
		return
	if _result_delay_remaining >= 0.0:
		# Keep the wreckage moving while the battlefield remains visible during
		# the short beat before the result panel appears.
		_advance_fixed_simulation(delta, 1.0)
		_result_delay_remaining -= delta
		visuals.queue_redraw()
		if _result_delay_remaining <= 0.0:
			_finish_battle(_pending_result_won)
		return
	if pause_button.button_pressed:
		return
	# Simulation speed must not depend on the render callback clearing a spent shot.
	if _cinematic_projectile != null and (not simulation.projectiles.has(_cinematic_projectile) or _cinematic_projectile.guidance_lost):
		_cinematic_projectile = null
		_update_camera_recovery(delta)
	if _cinematic_projectile == null:
		_try_begin_finishing_shot()
	var speed_multiplier := float(GameState.battle_speed)
	if _cinematic_projectile != null:
		speed_multiplier *= FINISHING_SHOT_TIME_SCALE
	_advance_fixed_simulation(delta, speed_multiplier)
	if _cinematic_projectile == null:
		_try_begin_finishing_shot()
	match simulation.phase:
		BattleSimulation.Phase.COMBAT:
			pass
		BattleSimulation.Phase.VICTORY:
			_begin_result_delay(true)
		BattleSimulation.Phase.DEFEAT:
			_begin_result_delay(false)
		BattleSimulation.Phase.WITHDRAWN:
			_finish_battle(false)
	visuals.queue_redraw()
	if missile_readout != null:
		missile_readout.text = "MISSILES %d" % simulation.missile_supply
	_refresh_missile_control()
	if objective_label != null:
		objective_label.text = "Saving battle result failed. Retrying..." if _settlement_error else simulation.encounter.label(simulation)
	if repair_label != null:
		repair_label.visible = not simulation.repair_reserves.is_empty() or simulation.doctrines.pool.get("repair_capacity", 0) > 0 or simulation.doctrines.pool.get("rebuild_capacity", 0) > 0
		var remaining := 0.0
		for member in simulation.players:
			if not member.is_alive() or member.owned_ship == null:
				continue
			for index in range(member.owned_ship.units.size()):
				if member.owned_ship.units[index].hp > 0:
					remaining += float(simulation.repair_reserves.get(SharedSupport.reserve_key(member.owned_ship, index), 0.0))
		var drone_remaining := maxf(0, simulation.doctrines.pool.get("repair_capacity", 0) - simulation.doctrines.pool.get("repair_spent", 0))
		var rebuilds: int = simulation.doctrines.pool.get("rebuild_capacity", 0) - simulation.doctrines.pool.get("rebuilt", []).size()
		var support_text := "REPAIR: %.1f HP" % (minf(remaining, maxf(0, simulation.repair_capacity - simulation.repair_spent)) + drone_remaining)
		if simulation.doctrines.pool.get("rebuild_capacity", 0) > 0:
			support_text += " | REBUILD: %d" % rebuilds
		if not simulation.doctrines.carriers.reserves.is_empty():
			var available := simulation.doctrines.carriers.available(simulation)
			var craft_text := "CRAFT: %d ready / %d active" % [available.x, available.y]
			support_text = support_text + " | " + craft_text if repair_label.visible else craft_text
			repair_label.show()
		repair_label.set_content(support_text)


func _advance_fixed_simulation(delta: float, speed_multiplier: float) -> void:
	if deploying:
		return
	_simulation_accumulator += delta * speed_multiplier
	var steps := 0
	while (
		_simulation_accumulator >= SIMULATION_TICK_SECONDS
		and steps < MAX_SIMULATION_STEPS_PER_FRAME
	):
		simulation.advance(SIMULATION_TICK_SECONDS)
		GameState.update_battle_support(simulation)
		_simulation_accumulator -= SIMULATION_TICK_SECONDS
		steps += 1
	if steps == MAX_SIMULATION_STEPS_PER_FRAME:
		# Keep bounded catch-up time through a costly frame instead of losing
		# requested fast-forward time every time the per-frame budget is reached.
		_simulation_accumulator = minf(_simulation_accumulator, 1.0)
	visuals.interpolation_alpha = clampf(
		_simulation_accumulator / SIMULATION_TICK_SECONDS,
		0.0,
		1.0
	)


func _on_pause_toggled(is_paused: bool) -> void:
	if is_paused:
		fast_forward_button.set_pressed_no_signal(false)
		five_times_button.set_pressed_no_signal(false)
		GameState.battle_speed = 1
		AudioManager.save_settings()


func _on_destroy_neutral_targets_toggled(enabled: bool) -> void:
	if _finished or _report_open or _result_delay_remaining >= 0.0 or simulation.phase != BattleSimulation.Phase.COMBAT:
		destroy_neutral_targets.set_pressed_no_signal(simulation.destroy_all_neutral_targets)
		return
	if not GameState.set_destroy_all_neutral_targets(enabled):
		destroy_neutral_targets.set_pressed_no_signal(simulation.destroy_all_neutral_targets)
		return
	simulation.issue_command("neutral_cleanup", {"enabled": enabled})


func _on_speed_toggled(enabled: bool, speed: int) -> void:
	if deploying:
		return
	GameState.battle_speed = speed if enabled else 1
	fast_forward_button.set_pressed_no_signal(GameState.battle_speed == 2)
	five_times_button.set_pressed_no_signal(GameState.battle_speed == 5)
	AudioManager.save_settings()
	if enabled:
		pause_button.set_pressed_no_signal(false)


func _process(delta: float) -> void:
	if UiNavigation.settings_open():
		return
	if _report_open or _result_delay_remaining >= 0.0:
		return
	if ability_bar != null and ability_bar.targeting:
		visuals.queue_redraw()
		return
	if _cinematic_projectile != null and not _cinematic_projectile.guidance_lost and simulation.projectiles.has(_cinematic_projectile):
		_cinematic_transition_elapsed += delta
		var transition_weight := smoothstep(
			0.0,
			1.0,
			clampf(
				_cinematic_transition_elapsed / FINISHING_SHOT_CAMERA_TRANSITION_SECONDS,
				0.0,
				1.0
			)
		)
		visuals.camera_position = _cinematic_camera_start.lerp(
			_cinematic_projectile.previous_position.lerp(
				_cinematic_projectile.position,
				visuals.interpolation_alpha
			),
			transition_weight
		)
		visuals.camera_zoom = lerpf(
			_cinematic_zoom_start,
			FINISHING_SHOT_CAMERA_ZOOM,
			transition_weight
		)
		visuals.queue_redraw()
		return
	_cinematic_projectile = null
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if not direction.is_zero_approx():
		_mark_manual_pan_input()
		visuals.camera_position += direction.normalized() * 400.0 * delta / visuals.camera_zoom
	if _dragging and _pan_resume_seconds > 0:
		_mark_manual_pan_input()
	if not deploying:
		_update_auto_camera(delta)
	visuals.queue_redraw()


func _input(event: InputEvent) -> void:
	if UiNavigation.settings_open():
		return
	var settings := get_node_or_null("SettingsButton") as Control
	if event is InputEventMouseButton and settings != null and settings.get_global_rect().has_point(event.position):
		_dragging = false
		_left_pressed = false
		return
	if ability_bar != null and ability_bar.targeting:
		if ability_bar.menu_open():
			return
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			ability_bar.cancel_targeting()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion:
			ability_bar.set_preview(visuals.world_transform().affine_inverse() * event.position)
			return
		if event is InputEventMouseButton:
			if not _battlefield_input(event.position):
				return
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				ability_bar.cast_at(visuals.world_transform().affine_inverse() * event.position)
				get_viewport().set_input_as_handled()
				return
			if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				ability_bar.cancel_targeting()
				get_viewport().set_input_as_handled()
				return
	var focus := get_viewport().gui_get_focus_owner()
	if event is InputEventKey and (focus is BaseButton or focus is Range):
		return
	if _report_open or _result_delay_remaining >= 0.0 or _cinematic_projectile != null:
		return
	if deploying and _deployment_input(event):
		return
	if event is InputEventMouseButton:
		if not _battlefield_input(event.position):
			if not event.pressed:
				_dragging = false
				_left_pressed = false
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_pressed = true
				_left_dragged = false
				_left_press_screen = event.position
			else:
				if _left_pressed and not _left_dragged and _left_press_screen.distance_to(event.position) <= 5:
					if not _select_flag(event.position):
						var point: Vector2 = visuals.world_transform().affine_inverse() * event.position
						if not _select_deployment(point):
							_issue_target_at(point)
					visuals.queue_redraw()
				_left_pressed = false
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var world_under_cursor: Vector2 = visuals.world_transform().affine_inverse() * event.position
			var zoom_factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			visuals.camera_zoom = clampf(visuals.camera_zoom * zoom_factor, MIN_CAMERA_ZOOM, 3.0)
			visuals.camera_position = world_under_cursor - (event.position - visuals.world_center()) / visuals.camera_zoom
			_mark_manual_zoom_input()
	elif event is InputEventMouseMotion and _dragging:
		if _left_pressed and _left_press_screen.distance_to(event.position) > 5:
			_left_dragged = true
		visuals.camera_position -= event.relative / visuals.camera_zoom
		if not event.relative.is_zero_approx():
			_mark_manual_pan_input()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_pan_resume_seconds = 0.0
		_zoom_resume_seconds = 0.0


func _battlefield_input(point: Vector2) -> bool:
	if battlefield != null and not battlefield.get_global_rect().has_point(point):
		return false
	if squadron_readout != null and squadron_readout.visible and squadron_readout.get_global_rect().has_point(point):
		return false
	if command_header != null and command_header.get_global_rect().has_point(point):
		return false
	if ability_bar != null and ability_bar.visible and ability_bar.get_global_rect().has_point(point):
		return false
	var radar := get_node_or_null("Radar") as Control
	if radar != null and radar.get_global_rect().has_point(point):
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered == null or hovered == self or hovered == visuals


func _issue_target_at(point: Vector2) -> void:
	if deploying:
		return
	var selected: BattleSimulation.Combatant
	var nearest := INF
	for actor in simulation._members:
		if actor.faction == BattleSimulation.Faction.PLAYER or not actor.is_alive() or not actor.targetable \
			or (simulation.visibility_enabled and not simulation.team_can_see(0, actor)):
			continue
		var distance: float = point.distance_to(actor.position)
		if BattleSimulation.Collision.contains(BattleSimulation.Collision.actor_polygons(actor), point) and distance < nearest:
			selected = actor
			nearest = distance
	for member in simulation.players:
		if not member.is_alive() or member.stats.weapons.is_empty():
			continue
		if selected != null:
			simulation.issue_command("attack", {"source": member.entity_id, "target": selected.entity_id})
		elif member.commanded_target != null:
			simulation.issue_command("clear_attack", {"source": member.entity_id})


func _mark_manual_pan_input() -> void:
	_pan_resume_seconds = AUTO_CAMERA_RETURN_DELAY

func _mark_manual_zoom_input() -> void:
	_zoom_resume_seconds = AUTO_CAMERA_RETURN_DELAY

func _update_camera_recovery(delta: float) -> void:
	_pan_resume_seconds = maxf(0, _pan_resume_seconds - delta)
	_zoom_resume_seconds = maxf(0, _zoom_resume_seconds - delta)


func _commit_battle_ability(proposal: Dictionary) -> bool:
	return GameState.commit_battle_ability(simulation, proposal)


func _build_battle_panels() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.mouse_filter = MOUSE_FILTER_IGNORE
	battle_frame.add_child(body)
	squadron_readout = _fleet_panel(body, false)
	battlefield = Control.new()
	battlefield.name = "Battlefield"
	battlefield.mouse_filter = MOUSE_FILTER_IGNORE
	battlefield.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(battlefield)
	battlefield.item_rect_changed.connect(_update_battlefield_rect)
	enemy_readout = _fleet_panel(body, true)
	selection_scroll = ScrollContainer.new()
	selection_scroll.name = "SelectionDetails"
	selection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	selection_scroll.hide()
	enemy_readout.get_parent().add_child(selection_scroll)
	selection_details = VBoxContainer.new()
	selection_details.size_flags_horizontal = SIZE_EXPAND_FILL
	selection_scroll.add_child(selection_details)
	footer_panel = preload("res://scripts/ui_art_frame.gd").new()
	footer_panel.name = "CommandFooter"
	footer_panel.horizontal = true
	footer_panel.theme_type_variation = &"CommandFooter"
	battle_frame.add_child(footer_panel)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	footer_panel.add_child(controls)
	missile_button = preload("res://scripts/ui_kit.gd").button("MISSILES ON", _toggle_missiles)
	missile_button.name = "MissileFire"
	missile_button.toggle_mode = true
	missile_button.size_flags_vertical = SIZE_SHRINK_CENTER
	controls.add_child(missile_button)
	_refresh_missile_control()
	if ability_bar != null:
		ability_bar.embedded = true
		controls.add_child(ability_bar)
	else:
		var empty := Label.new()
		empty.text = "ACTIVE ABILITIES"
		empty.theme_type_variation = &"ResearchDescriptionText"
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		controls.add_child(empty)
	body.resized.connect(_resize_battle_panels)
	resized.connect(_resize_battle_panels)
	_resize_battle_panels.call_deferred()
	var selection_timer := Timer.new()
	selection_timer.wait_time = 0.1
	selection_timer.autostart = true
	selection_timer.timeout.connect(_refresh_selection_status)
	add_child(selection_timer)

func _toggle_missiles() -> void:
	simulation.issue_command("missile_fire", {"enabled": missile_button.button_pressed})
	_refresh_missile_control()


func _refresh_missile_control() -> void:
	if missile_button == null:
		return
	missile_button.set_pressed_no_signal(simulation.missile_fire_enabled)
	missile_button.text = "MISSILES ON" if simulation.missile_fire_enabled else "MISSILES OFF"
	missile_button.disabled = simulation.phase != BattleSimulation.Phase.COMBAT


func _fleet_panel(parent: Container, enemies: bool) -> Control:
	var panel := preload("res://scripts/ui_art_frame.gd").new()
	panel.name = "EnemyPanel" if enemies else "AlliedPanel"
	panel.theme_type_variation = &"CommandRightPanel" if enemies else &"CommandLeftPanel"
	parent.add_child(panel)
	var readout := preload("res://scripts/battle_squadron_readout.gd").new()
	readout.simulation = simulation
	readout.enemies = enemies
	panel.add_child(readout)
	return readout

func _resize_battle_panels() -> void:
	if battlefield == null:
		return
	for readout: Control in [squadron_readout, enemy_readout]:
		var panel = readout.get_parent()
		if panel.art != null:
			panel.custom_minimum_size.x = battlefield.get_parent().size.y * panel.art.get_width() / panel.art.get_height()
	_update_battlefield_rect()

func _update_battlefield_rect() -> void:
	visuals.battlefield_rect = battlefield.get_global_rect()
	var radar := get_node_or_null("Radar") as Control
	if radar != null:
		var corner := visuals.battlefield_rect.end
		radar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		radar.position = corner - radar.size - Vector2(8, 8)
	visuals.queue_redraw()
	if deploying and _pan_resume_seconds == 0 and _zoom_resume_seconds == 0:
		var bounds := visuals.deployment_area
		for member: BattleSimulation.Combatant in simulation.aliens:
			if not simulation.visibility_enabled or simulation.team_can_see(0, member):
				bounds = bounds.expand(member.position + Vector2.ONE * member.radius)
		visuals.camera_position = bounds.get_center()
		visuals.camera_zoom = clampf(minf(battlefield.size.x / (bounds.size.x + 60),
			battlefield.size.y / (bounds.size.y + 60)), MIN_CAMERA_ZOOM, 3)

func _begin_combat() -> void:
	if not deploying:
		return
	var positions := {}
	for member: BattleSimulation.Combatant in simulation.players:
		positions[member.owned_ship.id] = member.position
	if not GameState.save_battle_deployment(positions):
		deployment_feedback.text = "Save failed: " + GameState.last_save_error
		deployment_feedback.show()
		return
	for member: BattleSimulation.Combatant in simulation.players:
		member.owned_ship = GameState.owned_ship(member.owned_ship.id)
		member.previous_position = member.position
	simulation._rebuild_member_cache()
	simulation.refresh_visibility()
	deploying = false
	_deployment_dragging = false
	_deployment_box = false
	_deployment_origins.clear()
	visuals.deployment_area = Rect2()
	_clear_selection()
	visuals.deployment_box = Rect2()
	begin_button.hide()
	deployment_feedback.hide()
	objective_label.reparent(command_header.course)
	battle_speed_controls.show()
	if ability_bar != null:
		ability_bar.input_enabled = true
		ability_bar.refresh()
	_simulation_accumulator = 0
	visuals.queue_redraw()

func _select_deployment(point: Vector2, additive := false) -> bool:
	if not additive:
		visuals.deployment_selection.clear()
	visuals.selected_squadron = ""
	for member: BattleSimulation.Combatant in simulation.players:
		if member.is_alive() and BattleSimulation.Collision.contains(BattleSimulation.Collision.actor_polygons(member), point):
			if member.entity_id not in visuals.deployment_selection:
				visuals.deployment_selection.append(member.entity_id)
			_show_selection_details()
			return true
	_show_selection_details()
	return false

func _select_flag(screen_point: Vector2, additive := false) -> bool:
	for flag: Dictionary in visuals.squadron_flags():
		if flag.enemy or not flag.rect.has_point(screen_point):
			continue
		if not additive:
			visuals.deployment_selection.clear()
		visuals.selected_squadron = flag.id
		for member: BattleSimulation.Combatant in simulation.players:
			if member.is_alive() and member.squadron_id == flag.id and member.entity_id not in visuals.deployment_selection:
				visuals.deployment_selection.append(member.entity_id)
		for id: String in visuals.deployment_selection:
			if simulation.entities[id].squadron_id != flag.id:
				visuals.selected_squadron = ""
		_show_selection_details()
		return true
	return false

func _clear_selection() -> void:
	visuals.deployment_selection.clear()
	visuals.selected_squadron = ""
	_show_selection_details()
	visuals.queue_redraw()

func _show_selection_details() -> void:
	if selection_details == null:
		return
	for child in selection_details.get_children():
		selection_details.remove_child(child)
		child.queue_free()
	selection_status = null
	var selected := visuals.deployment_selection
	selection_scroll.visible = not selected.is_empty()
	enemy_readout.visible = selected.is_empty()
	if selected.is_empty():
		return
	var close_row := Control.new()
	close_row.custom_minimum_size.y = 24
	selection_details.add_child(close_row)
	close_row.add_child(UiKit.close_button(_clear_selection))
	var actor: BattleSimulation.Combatant = simulation.entities[selected[0]]
	var group := not visuals.selected_squadron.is_empty()
	var multiple := selected.size() > 1 and not group
	var title: String = actor.owned_ship.display_name if not group else "Squadron #%d" % actor.owned_ship.squadron_id
	if multiple:
		title = "Selected ships"
	selection_details.add_child(UiKit.label(title, &"HeaderResearch"))
	selection_status = UiKit.label("")
	selection_details.add_child(selection_status)
	if not multiple:
		selection_details.add_child(UiKit.label("Stance: " + HangarSquadrons.LABELS.get(actor.owned_ship.stance, actor.owned_ship.stance)))
	if deploying:
		selection_details.add_child(UiKit.label("Drag flag to move squadron" if group else "Drag ship to move"))
	if group or multiple:
		for id: String in selected:
			var member: BattleSimulation.Combatant = simulation.entities[id]
			var option := UiKit.button(member.owned_ship.display_name + " #%d" % member.owned_ship.id, func() -> void:
				visuals.deployment_selection.assign([id])
				visuals.selected_squadron = ""
				_show_selection_details()
				visuals.queue_redraw())
			selection_details.add_child(option)
	else:
		var ship: HangarShip = actor.owned_ship
		var preset := ShipLoadouts.find(ship.chassis_id, GameState.ship_loadout_id(ship.id))
		selection_details.add_child(UiKit.label(str(preset.get("name", "Loadout"))))
		for mount: Dictionary in ship.mounts.values():
			var item := SlotCatalog.find_equipment(mount.equipment_id, int(mount.rank))
			selection_details.add_child(UiKit.label(str(item.name)))
	_refresh_selection_status()

func _refresh_selection_status() -> void:
	if not is_instance_valid(selection_status):
		return
	var hull := 0.0
	var maximum := 0.0
	var shields := 0.0
	var shield_max := 0.0
	var living := 0
	for id: String in visuals.deployment_selection:
		var actor: BattleSimulation.Combatant = simulation.entities[id]
		maximum += actor.owned_ship.hull_max
		shield_max += actor.stats.shields
		if actor.is_alive():
			living += 1
			hull += maxf(0, actor.owned_ship.hull_hp)
			shields += actor.shields
	selection_status.text = "%d / %d alive\nHull %.0f / %.0f\nShields %.0f / %.0f" % [living, visuals.deployment_selection.size(), hull, maximum, shields, shield_max]

func _move_deployment(delta: Vector2) -> void:
	var area := visuals.deployment_area
	var lower := Vector2(-INF, -INF)
	var upper := Vector2(INF, INF)
	for id: String in _deployment_origins:
		var member: BattleSimulation.Combatant = simulation.entities[id]
		var origin: Vector2 = _deployment_origins[id]
		lower = lower.max(area.position + Vector2.ONE * member.radius - origin)
		upper = upper.min(area.end - Vector2.ONE * member.radius - origin)
	var shift := delta.clamp(lower, upper)
	for id: String in _deployment_origins:
		var member: BattleSimulation.Combatant = simulation.entities[id]
		member.position = _deployment_origins[id] + shift
		member.previous_position = member.position
	simulation.refresh_visibility()
	visuals.queue_redraw()

func _deployment_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _battlefield_input(event.position):
				return false
			_deployment_press = visuals.world_transform().affine_inverse() * event.position
			_deployment_dragging = _select_flag(event.position, event.shift_pressed)
			if not _deployment_dragging:
				_deployment_dragging = _select_deployment(_deployment_press, event.shift_pressed)
			_deployment_box = not _deployment_dragging
			visuals.deployment_box = Rect2()
			_deployment_origins.clear()
			for id: String in visuals.deployment_selection:
				_deployment_origins[id] = simulation.entities[id].position
		else:
			if not _deployment_dragging and not _deployment_box:
				return false
			if _deployment_box:
				var point: Vector2 = visuals.world_transform().affine_inverse() * event.position
				var box := Rect2(_deployment_press, point - _deployment_press).abs()
				for member: BattleSimulation.Combatant in simulation.players:
					if box.has_point(member.position):
						_select_deployment(member.position, true)
			_deployment_dragging = false
			_deployment_box = false
			visuals.deployment_box = Rect2()
			_deployment_origins.clear()
		visuals.queue_redraw()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion and (_deployment_dragging or _deployment_box):
		var point: Vector2 = visuals.world_transform().affine_inverse() * event.position
		if _deployment_dragging:
			_move_deployment(point - _deployment_press)
		else:
			visuals.deployment_box = Rect2(_deployment_press, point - _deployment_press).abs()
			visuals.queue_redraw()
		get_viewport().set_input_as_handled()
		return true
	return false


func _ability_targeting_changed(enabled: bool) -> void:
	_dragging = false
	if enabled:
		_mark_manual_pan_input()
		_mark_manual_zoom_input()
		_paused_before_aim = pause_button.button_pressed
		if simulation.abilities.state.pause_aim:
			pause_button.set_pressed_no_signal(true)
	else:
		pause_button.set_pressed_no_signal(_paused_before_aim)


func _update_auto_camera(delta: float) -> void:
	var auto_pan: bool = GameState.battle_auto_pan and is_zero_approx(_pan_resume_seconds)
	var auto_zoom: bool = GameState.battle_auto_zoom and is_zero_approx(_zoom_resume_seconds)
	if not auto_pan and not auto_zoom:
		return
	var ship_count := 0
	var center := Vector2.ZERO
	for member in simulation.players:
		if member.is_alive():
			center += member.position
			ship_count += 1
	for member in simulation.aliens:
		if member.is_alive() and (not simulation.visibility_enabled or simulation.team_can_see(BattleSimulation.Faction.PLAYER, member)):
			center += member.position
			ship_count += 1
	if ship_count == 0 or visuals.size.x <= 0.0 or visuals.size.y <= 0.0:
		return
	center /= float(ship_count)
	var extent := Vector2.ONE
	for member in simulation.players:
		if not member.is_alive():
			continue
		var distance := (member.position - center).abs() + Vector2.ONE * member.radius
		extent.x = maxf(extent.x, distance.x)
		extent.y = maxf(extent.y, distance.y)
	for member in simulation.aliens:
		if not member.is_alive() or (simulation.visibility_enabled and not simulation.team_can_see(BattleSimulation.Faction.PLAYER, member)):
			continue
		var alien_distance := (member.position - center).abs() + Vector2.ONE * member.radius
		extent.x = maxf(extent.x, alien_distance.x)
		extent.y = maxf(extent.y, alien_distance.y)
	var raw_available_half := battlefield.size * 0.5 - AUTO_CAMERA_MARGIN
	var available_half := Vector2(
		maxf(raw_available_half.x, 1.0),
		maxf(raw_available_half.y, 1.0)
	)
	var target_zoom := clampf(
		minf(available_half.x / extent.x, available_half.y / extent.y),
		MIN_CAMERA_ZOOM,
		3.0
	)
	var interpolation := minf(delta * AUTO_CAMERA_SMOOTHING, 1.0)
	if auto_pan:
		visuals.camera_position = visuals.camera_position.lerp(center, interpolation)
	if auto_zoom:
		visuals.camera_zoom = lerpf(visuals.camera_zoom, target_zoom, interpolation)


func _on_ship_destroyed(is_player: bool) -> void:
	if is_player:
		AudioManager.play_sfx(SHIP_EXPLOSION_SOUND)
	else:
		AudioManager.play_sfx(ALIEN_EXPLOSION_SOUND, 1.0, ALIEN_EXPLOSION_VOLUME_DB)


func _try_begin_finishing_shot() -> void:
	if ability_bar != null and ability_bar.targeting:
		return
	var projectile := simulation.get_finishing_projectile(FINISHING_SHOT_WINDOW_SECONDS)
	if projectile == null:
		return
	_cinematic_projectile = projectile
	_cinematic_camera_start = visuals.camera_position
	_cinematic_zoom_start = visuals.camera_zoom
	_cinematic_transition_elapsed = 0.0


func _begin_result_delay(won: bool) -> void:
	if squadron_readout != null:
		squadron_readout.hide()
		enemy_readout.hide()
		selection_scroll.hide()
		footer_panel.hide()
	if ability_bar != null:
		ability_bar.cancel_targeting()
		ability_bar.hide()
	_pending_result_won = won
	_result_delay_remaining = RESULT_DELAY_SECONDS
	_cinematic_projectile = null
	_dragging = false
	battle_speed_controls.hide()
	destroy_neutral_targets.disabled = true


func _finish_battle(won: bool) -> void:
	if squadron_readout != null:
		squadron_readout.hide()
		enemy_readout.hide()
		selection_scroll.hide()
		footer_panel.hide()
	if ability_bar != null:
		ability_bar.cancel_targeting()
		ability_bar.hide()
	battle_speed_controls.hide()
	var credits_before := GameState.credits
	if not GameState.settle_battle(simulation):
		_settlement_error = true
		objective_label.add_theme_color_override("font_color", Color("ffd28a"))
		push_error("Could not save battle outcome.")
		_result_delay_remaining = RESULT_DELAY_SECONDS
		return
	_finished = true
	battle_frame.hide()
	destroy_neutral_targets.hide()
	objective_label.hide()
	repair_label.hide()
	_battle_credit_reward = maxi(GameState.credits - credits_before, 0)
	_run_lost = GameState.is_run_lost()
	if _run_lost:
		_report_open = true
		defeat_dialog.show_game_over()
	else:
		_show_report(won)


func _return_to_map() -> void:
	if not is_inside_tree():
		return
	SceneFadeScript.cover_and_change(self, MAP_SCENE_PATH, "", false)


func _return_to_main_menu() -> void:
	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if error != OK:
		push_error("Could not return to the main menu. Error code: %s" % error)


func _on_report_closed() -> void:
	_report_open = false
	if _run_lost:
		defeat_dialog.show_game_over()
	else:
		_return_to_map()


func _show_report(won: bool) -> void:
	_report_open = true
	var backdrop := ColorRect.new()
	backdrop.name = "ReportBackdrop"
	backdrop.color = Color(0.003, 0.012, 0.018, 1)
	backdrop.z_index = 39
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var report := preload("res://scripts/battle_report.gd").new()
	add_child(report)
	report.show_report(
		GameState.last_battle_report,
		"Victory" if won else (
			"Withdrawn" if simulation.phase == BattleSimulation.Phase.WITHDRAWN else "Defeat"
		),
		simulation.collected_categories,
		_battle_credit_reward,
		GameState.last_equipment_loot
	)
	report.closed.connect(_on_report_closed)
