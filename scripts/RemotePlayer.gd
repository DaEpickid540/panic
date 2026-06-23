extends Node3D
class_name RemotePlayer
## RemotePlayer — avatar for any player who ISN'T you.
##
## In an online match, this smoothly interpolates between networked position
## updates. In offline/solo mode these same nodes run as TEST BOTS — they
## wander (or chase) independently so you have opponents without a second player.

const LERP_SPEED := 12.0

# ─────────────────────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────────────────────
var peer_id:         int   = -1
var role:            int   = GameManager.Role.HUNTED
var target_position: Vector3 = Vector3.ZERO
var target_yaw:      float   = 0.0
var last_seen_ms:    int   = 0

# Bot settings
const BASE_SPEED  := 3.2
const FLEE_SPEED  := 5.8    # runner bots flee at this speed
const CHASE_SPEED := 5.5    # hunter bot chases at this speed
const FLEE_RADIUS := 16.0

var is_bot:    bool  = false
var slowed:    bool  = false
var bot_speed: float = BASE_SPEED
var _bound:    float = 40.0
var _wander:   Vector3 = Vector3.ZERO
var _anim_phase: float = 0.0

## Seconds between melee strikes (hunter bot can't spam hits).
var _hit_cd: float = 0.0

const MAX_HP := 5
var hp: int = MAX_HP
var _hit_by_melee := false
var _hit_by_throw := false

## Stun (ghost lightning) — frozen while > 0.
var _stun_timer: float = 0.0

## Stuck detection for bots.
var _stuck_pos := Vector3.ZERO
var _stuck_time := 0.0
var _strafe_side := 1.0

@onready var _mesh: Node3D = $Mesh


func _ready() -> void:
	Avatar.build(_mesh)


static func id_color(pid: int, alpha := 1.0) -> Color:
	var hue := float(absi(pid) % 1000) / 1000.0
	var c := Color.from_hsv(hue, 0.6, 0.95)
	c.a = alpha
	return c


func setup(p_peer_id: int, p_role: int) -> void:
	peer_id = p_peer_id
	apply_role(p_role)


func apply_role(p_role: int) -> void:
	role = p_role
	if role == GameManager.Role.HUNTED:
		hp = MAX_HP
		_hit_by_melee = false
		_hit_by_throw = false
	if role == GameManager.Role.GHOST:
		_mesh.visible = false
	elif role == GameManager.Role.HUNTER:
		_mesh.visible = true
		# The killer wears a terrifying monster skin (variant varies per hunter).
		Avatar.set_monster(_mesh, absi(peer_id))
	else:
		_mesh.visible = true
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.7
		mat.albedo_color = Color(0.82, 0.82, 0.88)
		Avatar.set_material(_mesh, mat)

	if is_bot:
		var base: float
		if role == GameManager.Role.HUNTER:
			base = CHASE_SPEED
		else:
			base = BASE_SPEED
		bot_speed = base * (0.7 if slowed else 1.0)


func enable_bot(bound: float) -> void:
	is_bot    = true
	_bound    = maxf(bound - 2.0, 5.0)
	bot_speed = CHASE_SPEED if role == GameManager.Role.HUNTER else BASE_SPEED
	_pick_wander()


func _pick_wander() -> void:
	_wander = Vector3(randf_range(-_bound, _bound), global_position.y,
					  randf_range(-_bound, _bound))


func receive(pos: Vector3, yaw: float) -> void:
	target_position = pos
	target_yaw      = yaw
	last_seen_ms    = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var prev := global_position

	_hit_cd = maxf(0.0, _hit_cd - delta)
	_stun_timer = maxf(0.0, _stun_timer - delta)

	if _stun_timer > 0.0:
		# Frozen by ghost lightning — hold still but keep getting interpolated yaw.
		Avatar.animate_walk(_mesh, _anim_phase, 0.0)
		return

	if is_bot:
		_bot_step(delta)
	else:
		var t := clampf(LERP_SPEED * delta, 0.0, 1.0)
		global_position = global_position.lerp(target_position, t)
		rotation.y      = lerp_angle(rotation.y, target_yaw, t)

	var moved := Vector2(global_position.x - prev.x, global_position.z - prev.z).length()
	if moved > 0.004:
		_anim_phase += delta * 10.0
		Avatar.animate_walk(_mesh, _anim_phase, 0.55)
	else:
		Avatar.animate_walk(_mesh, _anim_phase, 0.0)


func _bot_step(delta: float) -> void:
	if role == GameManager.Role.HUNTER:
		var target := _find_nearest_hunted()
		if target != null:
			var tdist := global_position.distance_to(target.global_position)
			if tdist < 2.5:
				if _hit_cd <= 0.0:
					_hit_cd = 1.8
					var hit_type := "throw" if randf() < 0.4 else "melee"
					if target.has_method("take_damage"):
						target.take_damage(1, peer_id, hit_type)
					elif "peer_id" in target:
						GameManager.capture_player(target.peer_id, peer_id)
			elif tdist < 32.0:
				_wander = target.global_position
				bot_speed = CHASE_SPEED
		else:
			bot_speed = CHASE_SPEED
	else:
		# ── Hunted bot: flee the hunter; otherwise go power a generator. ──
		var hunter := _find_hunter()
		var threatened := false
		if hunter != null:
			var away := global_position - hunter.global_position
			away.y = 0.0
			if away.length() < FLEE_RADIUS and away.length() > 0.01:
				_wander   = global_position + away.normalized() * 18.0
				_wander.x = clampf(_wander.x, -_bound, _bound)
				_wander.z = clampf(_wander.z, -_bound, _bound)
				bot_speed = FLEE_SPEED
				threatened = true
		if not threatened:
			var gen := _nearest_unpowered_generator()
			if gen != null:
				var to_gen := gen.global_position - global_position
				to_gen.y = 0.0
				if to_gen.length() <= 3.5:
					# Stand on the generator to power it (don't wander off).
					Avatar.animate_walk(_mesh, _anim_phase, 0.0)
					return
				_wander = gen.global_position
				bot_speed = BASE_SPEED * 1.15   # hustle to objectives

	# ── Shared: walk toward _wander, raycast for walls ──
	var to := _wander - global_position
	to.y = 0.0
	if to.length() < 1.0:
		_pick_wander()
	else:
		var dir    := to.normalized()
		var space  := get_world_3d().direct_space_state
		var origin := global_position + Vector3(0, 0.8, 0)

		if _ray_blocked(space, origin, dir, 2.8):
			var perp := Vector3(-dir.z, 0, dir.x) * _strafe_side
			if _ray_blocked(space, origin, perp, 2.8):
				_strafe_side *= -1.0
				perp = Vector3(-dir.z, 0, dir.x) * _strafe_side
			if _ray_blocked(space, origin, perp, 2.8):
				dir = -dir
			else:
				_wander   = global_position + perp * 14.0
				_wander.x = clampf(_wander.x, -_bound, _bound)
				_wander.z = clampf(_wander.z, -_bound, _bound)
				dir = perp

		var step := bot_speed * delta
		if not _ray_blocked(space, origin, dir, step + 0.6):
			global_position += dir * step
		else:
			global_position -= dir * step * 0.5
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.12)

	global_position.x = clampf(global_position.x, -_bound, _bound)
	global_position.z = clampf(global_position.z, -_bound, _bound)

	# Stuck detection: if barely moved in 3 seconds, pick a random new target.
	var moved := global_position.distance_to(_stuck_pos)
	if moved < 0.5:
		_stuck_time += delta
		if _stuck_time > 3.0:
			_stuck_time = 0.0
			_strafe_side *= -1.0
			_wander = Vector3(randf_range(-_bound, _bound), global_position.y,
					randf_range(-_bound, _bound))
	else:
		_stuck_time = 0.0
		_stuck_pos = global_position


func take_damage(amount: int = 1, by_peer_id: int = -1, hit_type: String = "melee") -> void:
	if role != GameManager.Role.HUNTED:
		return
	if hit_type == "melee":
		_hit_by_melee = true
	elif hit_type == "throw":
		_hit_by_throw = true
	hp = maxi(0, hp - amount)
	if hp <= 0:
		if _hit_by_melee and _hit_by_throw:
			GameManager.capture_player(peer_id, by_peer_id)
		else:
			hp = 1


## Freeze a runner bot in place (ghost lightning grief).
func apply_stun(duration: float) -> void:
	if role != GameManager.Role.HUNTED:
		return
	_stun_timer = maxf(_stun_timer, duration)


func _ray_blocked(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, dist: float) -> bool:
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * dist, 1)
	return not space.intersect_ray(params).is_empty()


## Nearest generator that still needs powering (runner bots head for these).
func _nearest_unpowered_generator() -> Node3D:
	var best: Node3D = null
	var best_dist := 9999.0
	for g in get_tree().get_nodes_in_group("generator"):
		if not is_instance_valid(g) or ("done" in g and g.done):
			continue
		var d := global_position.distance_to(g.global_position)
		if d < best_dist:
			best_dist = d
			best = g
	return best


## Find the nearest HUNTED player (local or remote bot). Used by hunter bot.
func _find_nearest_hunted() -> Node3D:
	var sp := get_parent()
	if sp == null:
		return null
	var best: Node3D = null
	var best_dist := 9999.0
	if "local_player" in sp and sp.local_player != null and is_instance_valid(sp.local_player):
		if sp.local_player.role == GameManager.Role.HUNTED:
			best = sp.local_player
			best_dist = global_position.distance_to(sp.local_player.global_position)
	if "remotes" in sp:
		for id in sp.remotes:
			var rp = sp.remotes[id]
			if is_instance_valid(rp) and rp != self and rp.role == GameManager.Role.HUNTED:
				var d := global_position.distance_to(rp.global_position)
				if d < best_dist:
					best_dist = d
					best = rp
	return best


## Find the hunter (any). Used by hunted bots to flee.
func _find_hunter() -> Node3D:
	var sp := get_parent()
	if sp == null:
		return null
	if "local_player" in sp and sp.local_player != null \
			and is_instance_valid(sp.local_player) \
			and sp.local_player.role == GameManager.Role.HUNTER:
		return sp.local_player
	if "remotes" in sp:
		for id in sp.remotes:
			var rp = sp.remotes[id]
			if rp != self and rp.role == GameManager.Role.HUNTER:
				return rp
	return null
