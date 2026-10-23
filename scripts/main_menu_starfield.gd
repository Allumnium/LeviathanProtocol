extends Control

const STAR_AREA_PER_STAR := 1500.0
const MIN_STAR_COUNT := 72
const MAX_STAR_COUNT := 220
const STAR_CLICK_RADIUS := 10.0
const CLICK_FLASH_DURATION := 0.8
const MAX_FLIGHT_ANGLE_DEGREES := 35.0
const FLIGHT_TURN_SPEED_DEGREES_PER_SECOND := 45.0
const MIN_STAR_DEPTH := 0.00000001
const STAR_CULL_MARGIN_SCALE := 17.0
const MIN_INITIAL_STAR_DEPTH := 0.24
const MAX_STAR_RADIUS_SCALE := 5.0
const MIN_TRAVEL_SPEED := 0.025
const MAX_TRAVEL_SPEED := 0.065
const MIN_RESPAWN_RADIUS := 0.025
const MAX_RESPAWN_RADIUS := 0.24
const STAR_STREAK_DEPTH := 0.22
const STAR_SPRITE: Texture2D = preload("res://assets/star1.png")
const STAR_SPRITE_FRAME_COUNT := 6
const STAR_SPRITE_FRAME_SIZE := Vector2(32.0, 29.0)
const STAR_SPRITE_FRAMES_PER_SECOND := 6.0
const STAR_COLORS: Array[Color] = [
	Color(0.76, 0.86, 1.0),
	Color(0.94, 0.96, 1.0),
	Color(1.0, 0.9, 0.76),
]

class TwinkleStar:
	extends RefCounted

	var world_offset := Vector2.ZERO
	var depth := 1.0
	var radius := 1.0
	var color := Color.WHITE
	var phase := 0.0
	var speed := 1.0
	var animation_frame_offset := 0.0
	var animation_speed := 1.0
	var travel_speed := 0.05
	var minimum_brightness := 0.25
	var maximum_brightness := 0.9
	var is_sparkle := false
	var click_flash_remaining := 0.0


var _stars: Array[TwinkleStar] = []
var _random := RandomNumberGenerator.new()
var _elapsed_time := 0.0
var _warp_progress := 0.0
var _flight_pitch_degrees := 0.0
var _flight_yaw_degrees := 0.0
var _steering_direction := Vector2.ZERO


func _ready() -> void:
	_random.randomize()
	resized.connect(_on_resized)
	call_deferred("_generate_stars")


func _process(delta: float) -> void:
	_elapsed_time += delta
	var pitch_input := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		pitch_input += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		pitch_input -= 1.0
	var yaw_input := 0.0
	if Input.is_physical_key_pressed(KEY_D):
		yaw_input += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		yaw_input -= 1.0

	var is_shift_pressed := Input.is_key_pressed(KEY_SHIFT)
	var speed_multiplier := 2.0 if is_shift_pressed else 1.0
	var turn_speed := FLIGHT_TURN_SPEED_DEGREES_PER_SECOND * speed_multiplier
	_flight_pitch_degrees = clampf(
		_flight_pitch_degrees + pitch_input * turn_speed * delta,
		-MAX_FLIGHT_ANGLE_DEGREES,
		MAX_FLIGHT_ANGLE_DEGREES
	)
	_flight_yaw_degrees = clampf(
		_flight_yaw_degrees + yaw_input * turn_speed * delta,
		-MAX_FLIGHT_ANGLE_DEGREES,
		MAX_FLIGHT_ANGLE_DEGREES
	)
	_steering_direction = Vector2(
		-tan(deg_to_rad(_flight_yaw_degrees)),
		tan(deg_to_rad(_flight_pitch_degrees))
	)
	var max_steering_strength := tan(deg_to_rad(MAX_FLIGHT_ANGLE_DEGREES))
	if _steering_direction.length() > max_steering_strength:
		_steering_direction = (
			_steering_direction.normalized() * max_steering_strength
		)

	var eased_warp_progress := _warp_progress * _warp_progress
	var travel_multiplier := lerpf(1.0, 80.0, eased_warp_progress) * speed_multiplier
	for star in _stars:
		star.click_flash_remaining = maxf(star.click_flash_remaining - delta, 0.0)
		var depth_travel := star.travel_speed * travel_multiplier * delta
		var next_depth := maxf(star.depth - depth_travel, MIN_STAR_DEPTH)

		var current_position_offset := star.world_offset / star.depth
		var next_position_offset := star.world_offset / next_depth
		var radial_displacement := next_position_offset - current_position_offset
		next_position_offset += _steering_direction * radial_displacement.length()
		star.world_offset = next_position_offset * next_depth
		star.depth = next_depth
		if next_depth <= MIN_STAR_DEPTH or _is_star_offscreen(star):
			_reset_star_position(star, false)
	queue_redraw()


func set_warp_progress(progress: float) -> void:
	_warp_progress = clampf(progress, 0.0, 1.0)


func _draw() -> void:
	var eased_warp_progress := _warp_progress * _warp_progress
	var warp_size_scale := lerpf(1.0, 3.0, eased_warp_progress)
	for star in _stars:
		var star_position := _get_star_position(star)
		var twinkle := 0.5 + 0.5 * sin(_elapsed_time * star.speed + star.phase)
		var approach_brightness := (1.0 - star.depth) * 0.28
		var brightness := (
			lerpf(star.minimum_brightness, star.maximum_brightness, twinkle)
			+ approach_brightness
		)
		var size_pulse := 0.9 + twinkle * 0.2
		var click_progress := star.click_flash_remaining / CLICK_FLASH_DURATION
		var click_flash := click_progress * click_progress
		brightness = clampf(brightness + click_flash * 0.55, 0.0, 1.0)
		var radius_scale := minf(1.0 / star.depth, MAX_STAR_RADIUS_SCALE)
		radius_scale *= size_pulse * (1.0 + click_flash * 0.75)
		var sprite_scale := radius_scale * warp_size_scale
		var tint := star.color

		draw_circle(
			star_position,
			star.radius * 4.0 * radius_scale,
			Color(tint.r, tint.g, tint.b, 0.004 * brightness),
			true,
			-1.0,
			true
		)
		draw_circle(
			star_position,
			star.radius * 2.0 * radius_scale,
			Color(tint.r, tint.g, tint.b, 0.018 * brightness),
			true,
			-1.0,
			true
		)
		var frame_index := (
			floori(
				_elapsed_time * STAR_SPRITE_FRAMES_PER_SECOND * star.animation_speed
				+ star.animation_frame_offset
			)
			% STAR_SPRITE_FRAME_COUNT
		)
		var source_rect := Rect2(
			Vector2(frame_index * STAR_SPRITE_FRAME_SIZE.x, 0.0),
			STAR_SPRITE_FRAME_SIZE
		)
		var sprite_size := Vector2(
			star.radius * 2.0 * sprite_scale,
			star.radius * 2.0 * sprite_scale
				* STAR_SPRITE_FRAME_SIZE.y
				/ STAR_SPRITE_FRAME_SIZE.x
		)
		var sprite_rect := Rect2(star_position - sprite_size * 0.5, sprite_size)
		draw_texture_rect_region(
			STAR_SPRITE,
			sprite_rect,
			source_rect,
			Color(1.0, 1.0, 1.0, 0.5 + 0.5 * brightness)
		)

		if star.depth < STAR_STREAK_DEPTH and not star.world_offset.is_zero_approx():
			var streak_progress := clampf(
				(STAR_STREAK_DEPTH - star.depth)
				/ (STAR_STREAK_DEPTH - MIN_STAR_DEPTH),
				0.0,
				1.0
			)
			var streak_length := 			star.radius * sprite_scale * streak_progress * 2.5
			var travel_direction := _get_star_travel_direction(star)
			draw_line(
				star_position - travel_direction * streak_length,
				star_position,
				Color(tint.r, tint.g, tint.b, 0.18 * brightness * streak_progress),
				maxf(star.radius * 0.45, 0.6),
				true
			)

		if star.is_sparkle or click_flash > 0.35:
			var ray_length := star.radius * 3.0 * radius_scale
			var ray_color := Color(tint.r, tint.g, tint.b, 0.14 * brightness)
			draw_line(
				star_position - Vector2(0.0, ray_length),
				star_position + Vector2(0.0, ray_length),
				ray_color,
				0.5,
				true
			)
			draw_line(
				star_position - Vector2(ray_length, 0.0),
				star_position + Vector2(ray_length, 0.0),
				ray_color,
				0.5,
				true
			)


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event == null
		or not mouse_event.pressed
		or mouse_event.button_index != MOUSE_BUTTON_LEFT
	):
		return

	var closest_star_index := -1
	var closest_distance_squared := STAR_CLICK_RADIUS * STAR_CLICK_RADIUS
	for index in range(_stars.size()):
		var star_position := _get_star_position(_stars[index])
		var distance_squared := mouse_event.position.distance_squared_to(star_position)
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_star_index = index

	if closest_star_index >= 0:
		_stars[closest_star_index].click_flash_remaining = CLICK_FLASH_DURATION
		queue_redraw()


func _on_resized() -> void:
	_sync_star_count()


func _generate_stars() -> void:
	_sync_star_count()


func _sync_star_count() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var area := size.x * size.y
	var star_count := clampi(roundi(area / STAR_AREA_PER_STAR), MIN_STAR_COUNT, MAX_STAR_COUNT)
	var initialize_across_screen := _stars.is_empty()
	while _stars.size() < star_count:
		_stars.append(_create_star(initialize_across_screen))
	while _stars.size() > star_count:
		_stars.pop_back()

	queue_redraw()


func _create_star(initialize_across_screen: bool) -> TwinkleStar:
	var star := TwinkleStar.new()
	star.radius = _random.randf_range(0.35, 0.95)
	star.color = STAR_COLORS[_random.randi_range(0, STAR_COLORS.size() - 1)]
	star.phase = _random.randf_range(0.0, TAU)
	star.speed = _random.randf_range(0.7, 2.1)
	star.animation_speed = _random.randf_range(0.7, 1.3)
	star.travel_speed = _random.randf_range(MIN_TRAVEL_SPEED, MAX_TRAVEL_SPEED)
	star.minimum_brightness = _random.randf_range(0.18, 0.42)
	star.maximum_brightness = _random.randf_range(0.62, 0.95)
	star.is_sparkle = _random.randf() < 0.025
	_reset_star_position(star, initialize_across_screen)
	return star


func _reset_star_position(star: TwinkleStar, initialize_across_screen: bool) -> void:
	star.phase = _random.randf_range(0.0, TAU)
	star.animation_frame_offset = _random.randf_range(0.0, STAR_SPRITE_FRAME_COUNT)
	star.click_flash_remaining = 0.0
	if initialize_across_screen:
		star.depth = _random.randf_range(MIN_INITIAL_STAR_DEPTH, 1.0)
		var initial_position := Vector2(_random.randf(), _random.randf()) * size
		star.world_offset = (
			(initial_position - size * 0.5)
			/ maxf(size.x, size.y)
			* star.depth
		)
		return

	star.depth = 1.0
	var angle := _random.randf_range(0.0, TAU)
	var spawn_radius := _random.randf_range(MIN_RESPAWN_RADIUS, MAX_RESPAWN_RADIUS)
	star.world_offset = Vector2(cos(angle), sin(angle)) * spawn_radius


func _get_star_position(star: TwinkleStar) -> Vector2:
	return size * 0.5 + star.world_offset * maxf(size.x, size.y) / star.depth


func _get_star_travel_direction(star: TwinkleStar) -> Vector2:
	return (star.world_offset.normalized() + _steering_direction).normalized()


func _is_star_offscreen(star: TwinkleStar) -> bool:
	var star_position := _get_star_position(star)
	var radius_scale := minf(1.0 / star.depth, MAX_STAR_RADIUS_SCALE)
	var margin := star.radius * radius_scale * STAR_CULL_MARGIN_SCALE
	return (
		star_position.x < -margin
		or star_position.x > size.x + margin
		or star_position.y < -margin
		or star_position.y > size.y + margin
	)
