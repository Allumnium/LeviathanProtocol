class_name BuildViewportStarfield
extends Node2D

const STAR_SPRITE: Texture2D = preload("res://assets/star1.png")
const STAR_FRAME_COUNT := 6
const STAR_FRAME_SIZE := Vector2(32.0, 29.0)
const STAR_FRAMES_PER_SECOND := 3.0
const STAR_AREA_PER_STAR := 5000.0
const MIN_STAR_COUNT := 60
const MAX_STAR_COUNT := 800
const STAR_COLORS: Array[Color] = [
	Color(0.76, 0.86, 1.0),
	Color(0.94, 0.96, 1.0),
	Color(1.0, 0.9, 0.76),
]

class DistantStar:
	extends RefCounted

	var world_position := Vector2.ZERO
	var radius := 0.7
	var color := Color.WHITE
	var phase := 0.0
	var twinkle_speed := 1.0
	var animation_frame_offset := 0.0
	var animation_speed := 1.0


@onready var _viewport_control: Control = get_parent() as Control
@onready var _pan_root: Node2D = _viewport_control.get_node("PanRoot") as Node2D

var _stars: Array[DistantStar] = []
var _random := RandomNumberGenerator.new()
var _elapsed_time := 0.0
var _world_bounds := Rect2()


func _ready() -> void:
	_random.randomize()


func configure(
	map_world_size: Vector2,
	viewport_size: Vector2,
	minimum_zoom: float
) -> void:
	if (
		map_world_size.x <= 0.0
		or map_world_size.y <= 0.0
		or viewport_size.x <= 0.0
		or viewport_size.y <= 0.0
		or minimum_zoom <= 0.0
	):
		push_error("Cannot configure build stars with invalid dimensions or zoom.")
		return

	var viewport_half_world_size := viewport_size / (minimum_zoom * 2.0)
	var world_margin := viewport_half_world_size
	_world_bounds = Rect2(
		-world_margin,
		map_world_size + world_margin * 2.0
	)
	var star_count := clampi(
		roundi(_world_bounds.size.x * _world_bounds.size.y / STAR_AREA_PER_STAR),
		MIN_STAR_COUNT,
		MAX_STAR_COUNT
	)

	_stars.clear()
	for _index in range(star_count):
		_stars.append(_create_star())
	queue_redraw()


func _process(delta: float) -> void:
	if _stars.is_empty() or not is_visible_in_tree():
		return

	_elapsed_time += delta
	queue_redraw()


func _draw() -> void:
	if _stars.is_empty() or not is_instance_valid(_pan_root):
		return

	var visible_rect := Rect2(Vector2.ZERO, _viewport_control.size).grow(3.0)
	var pan_transform := _pan_root.transform
	for star in _stars:
		var star_position := pan_transform * star.world_position
		if not visible_rect.has_point(star_position):
			continue

		var twinkle := 0.5 + 0.5 * sin(
			_elapsed_time * star.twinkle_speed + star.phase
		)
		var brightness := lerpf(0.2, 0.8, twinkle)
		var frame_index := (
			floori(
				_elapsed_time * STAR_FRAMES_PER_SECOND * star.animation_speed
				+ star.animation_frame_offset
			)
			% STAR_FRAME_COUNT
		)
		var sprite_size := Vector2(
			star.radius * 2.0,
			star.radius * 2.0 * STAR_FRAME_SIZE.y / STAR_FRAME_SIZE.x
		)
		var sprite_rect := Rect2(
			star_position - sprite_size * 0.5,
			sprite_size
		)
		var source_rect := Rect2(
			Vector2(frame_index * STAR_FRAME_SIZE.x, 0.0),
			STAR_FRAME_SIZE
		)
		draw_texture_rect_region(
			STAR_SPRITE,
			sprite_rect,
			source_rect,
			Color(star.color.r, star.color.g, star.color.b, brightness)
		)


func _create_star() -> DistantStar:
	var star := DistantStar.new()
	star.world_position = Vector2(
		_random.randf_range(_world_bounds.position.x, _world_bounds.end.x),
		_random.randf_range(_world_bounds.position.y, _world_bounds.end.y)
	)
	star.radius = _random.randf_range(0.35, 0.9)
	star.color = STAR_COLORS[_random.randi_range(0, STAR_COLORS.size() - 1)]
	star.phase = _random.randf_range(0.0, TAU)
	star.twinkle_speed = _random.randf_range(0.7, 1.8)
	star.animation_frame_offset = _random.randf_range(0.0, STAR_FRAME_COUNT)
	star.animation_speed = _random.randf_range(0.45, 0.9)
	return star
