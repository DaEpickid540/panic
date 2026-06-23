extends Control
## MiniMap — 150x150 top-down radar. Now shown for GHOSTS only (so they can
## stalk the living). Colours are role-based:
##   red dot    = hunter
##   white dot  = hunted (runner)
##   faint ring = another ghost / self
## Dots refresh every 500 ms from synced positions (the GameController spawner).

const REFRESH := 0.5
const WORLD_HALF := MapBase.HALF   # stays in sync with the arena size

var _spawner: Node
var _accum := 0.0


func _ready() -> void:
	var gc := get_tree().get_first_node_in_group("game_controller")
	if gc:
		_spawner = gc.get_node_or_null("PlayerSpawner")


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH:
		_accum = 0.0
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.04, 0.05, 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.08, 0.08, 0.8), false, 2.0)
	if _spawner == null or _spawner.local_player == null:
		return
	# Self (the ghost) — faint ring.
	_dot(_spawner.local_player.global_position, Color(0.6, 0.6, 0.7), 4.0, false)
	for peer_id in _spawner.remotes:
		var rp = _spawner.remotes[peer_id]
		match rp.role:
			GameManager.Role.HUNTER:
				_dot(rp.global_position, Color(0.85, 0.1, 0.1), 4.5, true)
			GameManager.Role.HUNTED:
				_dot(rp.global_position, Color(1, 1, 1), 3.0, true)
			_:
				_dot(rp.global_position, Color(0.6, 0.6, 0.7), 3.5, false)


func _dot(world: Vector3, color: Color, r: float, filled: bool) -> void:
	var u := (world.x / WORLD_HALF * 0.5 + 0.5) * size.x
	var v := (world.z / WORLD_HALF * 0.5 + 0.5) * size.y
	var p := Vector2(u, v)
	if filled:
		draw_circle(p, r, color)
	else:
		draw_arc(p, r, 0, TAU, 16, color, 1.5)
