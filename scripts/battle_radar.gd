extends Control

var simulation: BattleSimulation

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _process(_delta: float) -> void:
	queue_redraw()

func _point(world: Vector2) -> Vector2:
	return size * 0.5 + world / (BattleSimulation.ARENA_RADIUS * 2.4) * size

func _draw() -> void:
	if simulation == null or not simulation.visibility_enabled:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("081018"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("536979"), false, 1)
	for member in simulation.players:
		if member.is_alive():
			draw_circle(_point(member.position), 2, Color("8cd4e8"))
	for member in simulation.aliens:
		if member.is_alive() and simulation.team_can_see(BattleSimulation.Faction.PLAYER, member):
			draw_rect(Rect2(_point(member.position) - Vector2.ONE * 2, Vector2.ONE * 4), Color("ed8975"))
	for member in simulation.other_entities:
		if member.is_alive() and simulation.team_can_see(BattleSimulation.Faction.PLAYER, member):
			draw_circle(_point(member.position), 2, Color("929b9d"))
	for contact: Dictionary in simulation.visibility.contacts(BattleSimulation.Faction.PLAYER):
		var point := _point(contact.position)
		if contact.kind == "radar":
			draw_arc(point, 2.5, 0, TAU, 12, Color("e9bb70"), 1)
		else:
			draw_line(point - Vector2(2, 2), point + Vector2(2, 2), Color("708595"), 1)
			draw_line(point - Vector2(2, -2), point + Vector2(2, -2), Color("708595"), 1)
