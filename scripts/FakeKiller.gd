extends Node3D
## FakeKiller — a ghost-summoned decoy that mimics the real hunter: red avatar,
## killer chase AI, and the same growls/screams. But it can't actually capture —
## when it reaches a runner it only KNOCKS THEM TO THE GROUND (a hard stun) and
## then dies on the spot. It also self-destructs after LIFETIME seconds if it
## never lands a hit.

const SPEED        := 6.2
const MELEE        := 2.3
const LIFETIME     := 30.0
const KNOCKDOWN    := 2.6     # seconds the struck runner is floored
const SFX_INTERVAL := 3.5
const GROWLS := ["demonic_growl", "ghost_scratch", "demonic_scream"]

var _spawner: Node
var _bound: float = 90.0
var _mesh: Node3D
var _anim := 0.0
var _life := 0.0
var _sfx_cd := 0.8
var _struck := false


func setup(spawner: Node, bound: float) -> void:
	_spawner = spawner
	_bound = maxf(bound - 2.0, 10.0)


func _ready() -> void:
	_mesh = Node3D.new()
	_mesh.name = "Mesh"
	add_child(_mesh)
	Avatar.build(_mesh)
	Avatar.set_monster(_mesh, randi())
	if GameManager.get_local_role() != GameManager.Role.HUNTER:
		AudioManager.play_sfx("demonic_growl", 3.0)


func _process(delta: float) -> void:
	if _struck:
		return
	_life += delta
	if _life >= LIFETIME:
		_die()
		return

	_sfx_cd -= delta
	if _sfx_cd <= 0.0:
		_sfx_cd = SFX_INTERVAL
		if GameManager.get_local_role() != GameManager.Role.HUNTER:
			AudioManager.play_sfx(GROWLS[randi() % GROWLS.size()], 0.0)

	var target := _nearest_runner()
	if target == null:
		return

	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < MELEE:
		_strike(target)
		return

	# Chase with simple wall avoidance.
	var dir := to.normalized()
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.9, 0)
	var step := SPEED * delta
	if not _blocked(space, origin, dir, step + 0.7):
		global_position += dir * step
	else:
		var perp := Vector3(-dir.z, 0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
		if not _blocked(space, origin, perp, step + 0.7):
			global_position += perp * step
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.15)
	global_position.x = clampf(global_position.x, -_bound, _bound)
	global_position.y = maxf(global_position.y, 0.0)
	global_position.z = clampf(global_position.z, -_bound, _bound)

	_anim += delta * 11.0
	Avatar.animate_walk(_mesh, _anim, 0.6)


## Knock the runner to the ground, then perish.
func _strike(target: Node) -> void:
	if _struck:
		return
	_struck = true
	GameManager.grief_runner(target, -1, 0, KNOCKDOWN)
	var local_role := GameManager.get_local_role()
	if local_role != GameManager.Role.HUNTER:
		AudioManager.play_sfx("ghost_scream", 6.0)
	if _spawner and target == _spawner.get("local_player") \
			and local_role == GameManager.Role.HUNTED:
		var ui := get_tree().get_first_node_in_group("hunting_ui")
		if ui and ui.has_method("force_jumpscare"):
			ui.force_jumpscare()
	_die()


func _die() -> void:
	set_process(false)
	var t := create_tween()
	t.tween_property(self, "scale", Vector3(0.02, 0.02, 0.02), 0.3)
	t.parallel().tween_property(self, "position:y", position.y - 1.0, 0.3)
	t.tween_callback(queue_free)


func _nearest_runner() -> Node3D:
	if _spawner == null:
		return null
	var best: Node3D = null
	var best_d := 9999.0
	var lp = _spawner.get("local_player")
	if lp != null and is_instance_valid(lp) and lp.role == GameManager.Role.HUNTED:
		best = lp
		best_d = global_position.distance_to(lp.global_position)
	if "remotes" in _spawner:
		for id in _spawner.remotes:
			var rp = _spawner.remotes[id]
			if is_instance_valid(rp) and rp.role == GameManager.Role.HUNTED:
				var d := global_position.distance_to(rp.global_position)
				if d < best_d:
					best_d = d
					best = rp
	return best


func _blocked(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, dist: float) -> bool:
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * dist, 1)
	return not space.intersect_ray(params).is_empty()
