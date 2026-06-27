extends CharacterBody3D
## PlayerController — the player you are actually controlling.
##
## Both the HUNTER and RUNNER (hunted) use first-person view (FPS).
## The GHOST falls back to a top-down iso camera (ghosts float and need overview).
##
## Movement input merges keyboard (WASD) + on-screen joystick (TouchInput.move)
## so the same script works on PC and mobile.

# ─────────────────────────────────────────────────────────────────────────────
# MOVEMENT SPEEDS  (metres / second)
# ─────────────────────────────────────────────────────────────────────────────
const SPEED := {
	0: 5.0,   # HUNTER  — powerful but not always faster than a sprinting runner
	1: 6.0,   # HUNTED  — slightly faster at base so running is a real option
	2: 2.0,   # GHOST   — slow float; you're basically waiting for a revive
}

@export var mouse_sensitivity := 0.0025
@export var gravity := 18.0

# ─────────────────────────────────────────────────────────────────────────────
# HUNTER COMBAT
# ─────────────────────────────────────────────────────────────────────────────
const JUMP_FORCE    := 7.0
const DASH_MULT     := 2.6
const DASH_TIME     := 0.28
const DASH_COOLDOWN := 2.0
const THROW_COOLDOWN := 4.0

## Melee blade swing: how long the swing animation lasts, and how long until the
## hunter can swing again.
const SWING_TIME     := 0.26
const SWING_COOLDOWN := 0.60

const KNIFE_SCENE := preload("res://scenes/KnifeProjectile.tscn")

# ─────────────────────────────────────────────────────────────────────────────
# FLASHLIGHT
# ─────────────────────────────────────────────────────────────────────────────
const FLASH_DRAIN    := 0.16
const FLASH_RECHARGE := 0.016

const SURVIVOR_FLASH_DRAIN    := 0.55
const SURVIVOR_FLASH_RECHARGE := 0.012
const SURVIVOR_FLASH_ENERGY   := 1.4
const SURVIVOR_FLASH_RANGE    := 10.0
const SURVIVOR_FLASH_ANGLE    := 22.0
const SURVIVOR_FLASH_COLOR    := Color(0.92, 0.82, 0.55)
var _flicker_t := 0.0

const SLOW_MULT := 0.7   # revived players are slower

## Max height the player auto-climbs without jumping (stairs/steps/curbs).
const STEP_HEIGHT := 0.7

# ─────────────────────────────────────────────────────────────────────────────
# RUNNER SPRINT + STAMINA  (intentionally weak — sprinting is a last resort)
# ─────────────────────────────────────────────────────────────────────────────
const SPRINT_MULT   := 1.18   # was 1.35 — barely faster than a jog now
const STAMINA_DRAIN := 0.62   # was 0.40 — burns out fast
const STAMINA_REGEN := 0.15   # was 0.22 — slow to recover
const STAMINA_MIN   := 0.05

const BOOST_MULT := 1.30
const BOOST_TIME := 4.0

# ─────────────────────────────────────────────────────────────────────────────
# GHOST  (first-person flight + lightning griefing)
# ─────────────────────────────────────────────────────────────────────────────
const GHOST_FLY_SPEED      := 8.0    # free-fly speed (noclip)
const GHOST_FLY_MIN_Y      := 0.6
const GHOST_FLY_MAX_Y      := 30.0
const GHOST_LIGHTNING_CD   := 45.0   # one strike every 45 s
const GHOST_CHARGE_TIME    := 0.9    # full draw time (bow-like)
const GHOST_CHARGE_MIN     := 0.15   # minimum charge to release a strike
const GHOST_LIGHTNING := preload("res://scripts/GhostLightning.gd")
const FAKE_KILLER     := preload("res://scripts/FakeKiller.gd")
const FAKE_KILLER_CD  := 30.0   # one summoned decoy at a time
const DOUBLE_TAP_SEC  := 0.30   # window for double-Space ground-slam
const GRIEF_TARGET_CD := 12.0   # seconds before ghost can grief the same player again

## Seconds until the ghost can strike again (0 = ready). Read by HuntingUI.
var lightning_cd: float = 0.0
## Current bow-draw charge 0..1 while holding fire. Read by HuntingUI.
var lightning_charge: float = 0.0
## Seconds until the ghost can summon another fake killer. Read by HuntingUI.
var fake_killer_cd: float = 0.0
var _aim_ring: MeshInstance3D   # ground reticle shown while aiming
var _last_jump_press: float = -1.0   # for double-tap detection
var _grief_cooldowns: Dictionary = {}   # peer_id → time remaining

# ─────────────────────────────────────────────────────────────────────────────
# HP (runner only — hunter is invincible)
# ─────────────────────────────────────────────────────────────────────────────
const MAX_HP := 5

## Current hit-points. Read by HuntingUI for the HP bar.
var hp: int = MAX_HP
var _hit_by_melee := false
var _hit_by_throw := false

# ─────────────────────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────────────────────
var _anim_phase := 0.0
var _dash_timer := 0.0
var _dash_cd    := 0.0

## Seconds until hunter can throw again. Read by HuntingUI.
var throw_cd: float = 0.0

## Melee swing state. swing_cd is read by HuntingUI for the swing gauge.
var swing_cd: float = 0.0
var _swing_t: float = 0.0
var _knife_base_pos := Vector3.ZERO
var _knife_base_rot := Vector3.ZERO

var _knife: Node3D
var flash_battery := 1.0   # read by HuntingUI
var slowed := false

var stamina := 1.0          # read by HuntingUI
var _sprinting := false
var _boost_timer := 0.0

## Fear (0..1) written by HuntingUI based on hunter proximity.
## Drives heartbeat shake and stamina drain under panic.
var fear := 0.0
var _heartbeat := 0.0
var _cam_base := Vector3.ZERO   # resting FPS-cam position for heartbeat shake
var _heart_player: AudioStreamPlayer   # looping heartbeat that swells with fear
var _step_timer := 0.0                  # local footstep SFX cadence (hunter)

## Slow debuff from a bad pickup. Counts down to 0.
var _slow_debuff_timer: float = 0.0

## Stun (ghost lightning) — frozen in place while > 0.
var _stun_timer: float = 0.0

## Set by Locker.gd to freeze movement while the runner is hiding.
var hidden_in_locker: bool = false

@export var role: int = 1
var peer_id: int = -1
var is_local := true

@onready var _mesh:       Node3D      = $Mesh
@onready var _fps_cam:    Camera3D    = $Head/FPSCamera
@onready var _iso_cam:    Camera3D    = $IsoPivot/IsoCamera
@onready var _flashlight: SpotLight3D = $Head/Flashlight

var _yaw   := 0.0
var _pitch := 0.0


# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	if is_local:
		peer_id = NetworkManager.local_peer_id
	Avatar.build(_mesh)
	_cam_base = _fps_cam.position   # remember resting spot for heartbeat shake
	if is_local:
		_build_heart_player()
	configure_for_role(role)


## A looping heartbeat that fades in as the hunter gets close (runner only).
func _build_heart_player() -> void:
	_heart_player = AudioStreamPlayer.new()
	_heart_player.bus = "SFX"
	var hb := AudioManager.get_sfx_stream("heartbeat")
	if hb is AudioStreamMP3:
		(hb as AudioStreamMP3).loop = true
		_heart_player.stream = hb
	_heart_player.volume_db = -80.0
	add_child(_heart_player)


## Called whenever the role changes (spawn, capture, revive).
func configure_for_role(new_role: int) -> void:
	role = new_role
	_flashlight.visible = false
	if role != GameManager.Role.GHOST:
		_clear_aim_ring()   # drop any leftover lightning reticle

	match role:
		GameManager.Role.HUNTER:
			_mesh.visible = false   # first-person: you don't see your own body
			collision_mask = 1
			gravity = 18.0
			_flashlight.light_color = Color(1, 0.96, 0.88)
			_flashlight.light_energy = 7.0
			_flashlight.spot_range = 34.0
			_flashlight.spot_angle = 36.0
			if is_local:
				_fps_cam.current = true
				if not TouchInput.enabled:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_ensure_knife()

		GameManager.Role.HUNTED:
			_mesh.visible = false
			hp = MAX_HP
			_hit_by_melee = false
			_hit_by_throw = false
			collision_mask = 1
			gravity = 18.0
			flash_battery = 0.6
			_flashlight.light_color = SURVIVOR_FLASH_COLOR
			_flashlight.light_energy = SURVIVOR_FLASH_ENERGY
			_flashlight.spot_range = SURVIVOR_FLASH_RANGE
			_flashlight.spot_angle = SURVIVOR_FLASH_ANGLE
			Avatar.set_color(_mesh, GameManager.local_color)
			if is_local:
				_fps_cam.current = true
				if not TouchInput.enabled:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		GameManager.Role.GHOST:
			# Ghosts now share the runner's first-person view, but can fly through
			# walls (noclip) and grief the living with lightning.
			_mesh.visible = false
			collision_mask = 0      # walk through walls
			gravity = 0.0
			lightning_cd = 0.0      # strike ready when you first turn ghost
			lightning_charge = 0.0
			if _heart_player and _heart_player.playing:
				_heart_player.stop()
			if is_local:
				_fps_cam.current = true
				if not TouchInput.enabled:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_clear_aim_ring()


# ─────────────────────────────────────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return

	# FPS look — hunter, runner AND ghost all share the same camera-yaw system.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := _look_scale()
		_apply_look(-event.relative.x * s, -event.relative.y * s)
		return
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not get_tree().paused \
			and GameManager.current_phase == GameManager.Phase.HUNTING \
			and not TouchInput.enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Flashlight — hunter and survivor both get one (survivor's is garbage).
	if role != GameManager.Role.GHOST and event.is_action_pressed("flashlight"):
		if _flashlight.visible:
			_flashlight.visible = false
		elif flash_battery > 0.08:
			_flashlight.visible = true
		return

	# Interact with lore objects (all non-ghost roles).
	if event.is_action_pressed("grab") and role != GameManager.Role.GHOST:
		if _current_interactable != null:
			_try_interact()
			get_viewport().set_input_as_handled()
			return
		var has_nearby := false
		for n in get_tree().get_nodes_in_group("interactable"):
			if is_instance_valid(n) and global_position.distance_to(n.global_position) < 3.5:
				has_nearby = true
				break
		if has_nearby:
			_try_interact()
			get_viewport().set_input_as_handled()
			return

	# Hunter-only actions.
	if role != GameManager.Role.HUNTER:
		return

	if event.is_action_pressed("throw"):
		_throw_knife()


# ─────────────────────────────────────────────────────────────────────────────
# PHYSICS
# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	# FPS look from mobile touch drag (all roles are first-person now).
	if TouchInput.enabled:
		var l := TouchInput.consume_look()
		var s := _look_scale()
		_apply_look(-l.x * s, -l.y * s)

	# Cooldown ticks (shared).
	_dash_cd    = maxf(0.0, _dash_cd    - delta)
	_dash_timer = maxf(0.0, _dash_timer - delta)
	throw_cd    = maxf(0.0, throw_cd    - delta)
	_boost_timer        = maxf(0.0, _boost_timer        - delta)
	_slow_debuff_timer  = maxf(0.0, _slow_debuff_timer  - delta)
	_stun_timer         = maxf(0.0, _stun_timer         - delta)
	swing_cd            = maxf(0.0, swing_cd            - delta)
	_update_swing(delta)

	# ── GHOST: free-fly + lightning grief, then bail out. ──
	if role == GameManager.Role.GHOST:
		_ghost_step(delta)
		return

	# Flashlight drain / recharge (survivor drains way faster).
	var drain: float = SURVIVOR_FLASH_DRAIN if role == GameManager.Role.HUNTED else FLASH_DRAIN
	var regen: float = SURVIVOR_FLASH_RECHARGE if role == GameManager.Role.HUNTED else FLASH_RECHARGE
	if _flicker_t > 0.0:
		_flicker_t -= delta
		if _flicker_t <= 0.0 and flash_battery > 0.0:
			_flashlight.visible = true
			_flashlight.light_energy = SURVIVOR_FLASH_ENERGY
	if _flashlight.visible:
		flash_battery = maxf(0.0, flash_battery - drain * delta)
		if flash_battery <= 0.0:
			_flashlight.visible = false
		elif role == GameManager.Role.HUNTED:
			var roll := randf()
			if roll < 0.003:
				_flashlight.visible = false
				_flicker_t = randf_range(0.04, 0.15)
			elif roll < 0.012:
				_flashlight.light_energy = randf_range(0.2, 0.6)
			elif _flashlight.light_energy != SURVIVOR_FLASH_ENERGY:
				_flashlight.light_energy = lerpf(_flashlight.light_energy, SURVIVOR_FLASH_ENERGY, delta * 8.0)
	else:
		flash_battery = minf(1.0, flash_battery + regen * delta)

	# Gravity + jump.
	if gravity > 0.0:
		if is_on_floor():
			velocity.y = 0.0
			if Input.is_action_just_pressed("jump"):
				velocity.y = JUMP_FORCE
		else:
			velocity.y -= gravity * delta

	if role == GameManager.Role.HUNTER and _dash_cd <= 0.0 \
			and Input.is_action_just_pressed("dash"):
		_dash_timer = DASH_TIME
		_dash_cd    = DASH_COOLDOWN

	# Locker: hold still while hiding.
	if hidden_in_locker:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Stunned by ghost lightning: frozen (gravity still applies).
	if _stun_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_update_heartbeat_shake(delta)
		return

	# Runner sprint + fear-scaled stamina. Injured runners burn stamina faster.
	var input := _get_move_input()
	_sprinting = false
	if role == GameManager.Role.HUNTED:
		var hp_stam: float = _cripple_mult()
		var wants_sprint := Input.is_action_pressed("sprint") and input.length() > 0.1
		if wants_sprint and stamina > STAMINA_MIN:
			_sprinting = true
			stamina = maxf(0.0, stamina - STAMINA_DRAIN * (1.0 + fear * 0.5) / hp_stam * delta)
		else:
			stamina = minf(1.0, stamina + STAMINA_REGEN * hp_stam * (1.0 - fear * 0.6) * delta)

	# Horizontal movement speed.
	var speed: float = SPEED.get(role, 5.0)
	if slowed or _slow_debuff_timer > 0.0:
		speed *= SLOW_MULT
	if role == GameManager.Role.HUNTED:
		speed *= _cripple_mult()              # hurt runners limp
	if _dash_timer > 0.0:
		speed *= DASH_MULT
	if _sprinting:
		speed *= SPRINT_MULT
	if _boost_timer > 0.0:
		speed *= BOOST_MULT
	if role == GameManager.Role.HUNTER:
		speed *= GameManager.hunter_speed_mult()   # endgame escalation
	var dir := _input_to_world_dir(input)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_auto_step(Vector3(velocity.x, 0.0, velocity.z) * delta)
	move_and_slide()

	# Hunter footsteps (the runner is "audio-blind" so gets no movement SFX).
	if role == GameManager.Role.HUNTER and is_on_floor():
		var hsp := Vector2(velocity.x, velocity.z).length()
		if hsp > 1.2:
			_step_timer -= delta
			if _step_timer <= 0.0:
				_step_timer = 0.34 if _dash_timer > 0.0 else 0.46
				AudioManager.play_sfx("footstep_concrete", -9.0)
		else:
			_step_timer = 0.0

	_update_heartbeat_shake(delta)


## Heartbeat camera shake + audio for runners. Both swell as the hunter closes in.
func _update_heartbeat_shake(delta: float) -> void:
	if role != GameManager.Role.HUNTED:
		if _heart_player and _heart_player.playing:
			_heart_player.stop()
		_fps_cam.position = _cam_base
		return

	# Audio: fade the looping heartbeat in/out with fear.
	if _heart_player:
		if fear > 0.06:
			if not _heart_player.playing:
				_heart_player.play()
			_heart_player.volume_db   = lerpf(-26.0, -4.0, fear)
			_heart_player.pitch_scale = lerpf(0.85, 1.45, fear)
		elif _heart_player.playing:
			_heart_player.stop()

	if fear <= 0.01:
		_fps_cam.position = _cam_base
		return
	_heartbeat += delta * lerpf(1.5, 4.0, fear)
	var thump: float = maxf(0.0, sin(_heartbeat * TAU))
	var amount: float = fear * 0.14 * thump
	_fps_cam.position = _cam_base + Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * amount


# ─────────────────────────────────────────────────────────────────────────────
# GHOST FLIGHT + LIGHTNING GRIEF
# ─────────────────────────────────────────────────────────────────────────────

## Per-frame ghost behaviour: 3-D noclip flight + bow-style lightning aiming.
func _ghost_step(delta: float) -> void:
	lightning_cd   = maxf(0.0, lightning_cd - delta)
	fake_killer_cd = maxf(0.0, fake_killer_cd - delta)
	for pid in _grief_cooldowns.keys():
		_grief_cooldowns[pid] -= delta
		if _grief_cooldowns[pid] <= 0.0:
			_grief_cooldowns.erase(pid)

	# Free-fly: WASD moves where you look, Space rises, Shift falls.
	var input := _get_move_input()
	var cam_basis := _fps_cam.global_transform.basis
	var move := Vector3.ZERO
	if input != Vector2.ZERO:
		move += cam_basis * Vector3(input.x, 0.0, input.y)
	if Input.is_action_pressed("jump"):
		move.y += 1.0
	if Input.is_action_pressed("sprint"):
		move.y -= 1.0      # Shift = fall
	if move.length() > 0.01:
		move = move.normalized()
	velocity = move * GHOST_FLY_SPEED
	move_and_slide()
	global_position.y = clampf(global_position.y, GHOST_FLY_MIN_Y, GHOST_FLY_MAX_Y)

	# Double-tap Space = drop straight to the floor below.
	if Input.is_action_just_pressed("jump"):
		var now := Time.get_ticks_msec() / 1000.0
		if _last_jump_press > 0.0 and now - _last_jump_press < DOUBLE_TAP_SEC:
			_ghost_drop_to_ground()
			_last_jump_press = -1.0
		else:
			_last_jump_press = now

	# F = summon a fake killer (decoy) at where you're aiming.
	if Input.is_action_just_pressed("flashlight"):
		if fake_killer_cd <= 0.0:
			_summon_fake_killer()
		else:
			var ui := get_tree().get_first_node_in_group("hunting_ui")
			if ui and ui.has_method("show_pickup_effect"):
				ui.show_pickup_effect("FAKE KILLER — %ds" % ceili(fake_killer_cd), false)

	_ghost_lightning(delta)


## Snap the ghost down onto the floor directly beneath it (double-tap Space).
func _ghost_drop_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var params := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0, 1)
	var hit := space.intersect_ray(params)
	if hit.has("position"):
		global_position.y = maxf(GHOST_FLY_MIN_Y, (hit["position"] as Vector3).y + 0.6)
	else:
		global_position.y = GHOST_FLY_MIN_Y


## Spawn a fake-killer decoy at the aimed point; it chases & knocks runners down.
func _summon_fake_killer() -> void:
	var spawner := _get_spawner()
	if spawner == null:
		return
	fake_killer_cd = FAKE_KILLER_CD
	var pos := _ghost_aim_point()
	var fk: Node3D = FAKE_KILLER.new()
	get_tree().current_scene.add_child(fk)
	fk.global_position = Vector3(pos.x, maxf(pos.y, 0.0), pos.z)
	var bound: float = spawner._arena_bound() if spawner.has_method("_arena_bound") else 90.0
	fk.setup(spawner, bound)
	var ui := get_tree().get_first_node_in_group("hunting_ui")
	if ui and ui.has_method("show_pickup_effect"):
		ui.show_pickup_effect("FAKE KILLER SUMMONED", true)


func _get_spawner() -> Node:
	var gc := get_tree().get_first_node_in_group("game_controller")
	if gc:
		return gc.get_node_or_null("PlayerSpawner")
	return null


## Charge while holding fire (RMB / "throw"); release to call down a strike.
func _ghost_lightning(delta: float) -> void:
	var ready := lightning_cd <= 0.0
	var holding := Input.is_action_pressed("throw")

	if holding and ready:
		lightning_charge = minf(1.0, lightning_charge + delta / GHOST_CHARGE_TIME)
		_update_aim_ring(true)
	elif Input.is_action_just_released("throw"):
		if ready and lightning_charge >= GHOST_CHARGE_MIN:
			_fire_lightning()
		lightning_charge = 0.0
		_update_aim_ring(false)
	else:
		if lightning_charge > 0.0:
			lightning_charge = 0.0
		_update_aim_ring(false)


## Where the ghost is aiming: first world hit, or the y=0 ground plane.
func _ghost_aim_point() -> Vector3:
	var from := _fps_cam.global_position
	var aim_dir := -_fps_cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, from + aim_dir * 140.0, 1)
	var hit := space.intersect_ray(params)
	if hit.has("position"):
		return hit["position"]
	if absf(aim_dir.y) > 0.001:
		var t := -from.y / aim_dir.y
		if t > 0.0:
			return from + aim_dir * t
	return from + aim_dir * 40.0


func _fire_lightning() -> void:
	lightning_cd = GHOST_LIGHTNING_CD
	var pos := _ghost_aim_point()
	var bolt: Node3D = GHOST_LIGHTNING.new()
	get_tree().current_scene.add_child(bolt)
	bolt.strike(pos, peer_id)


## Glowing ground reticle that grows as the strike charges.
func _update_aim_ring(active: bool) -> void:
	if not active:
		_clear_aim_ring()
		return
	if _aim_ring == null or not is_instance_valid(_aim_ring):
		_aim_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.5
		tm.outer_radius = 2.1
		_aim_ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.8, 1.0, 0.7)
		m.emission_enabled = true
		m.emission = Color(0.5, 0.75, 1.0)
		m.emission_energy_multiplier = 2.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aim_ring.material_override = m
		get_tree().current_scene.add_child(_aim_ring)
	var p := _ghost_aim_point()
	_aim_ring.global_position = p + Vector3(0.0, 0.12, 0.0)
	var s := lerpf(0.55, 1.35, lightning_charge)
	_aim_ring.scale = Vector3(s, s, s)
	_aim_ring.visible = true


func _clear_aim_ring() -> void:
	if _aim_ring and is_instance_valid(_aim_ring):
		_aim_ring.queue_free()
	_aim_ring = null


func _exit_tree() -> void:
	_clear_aim_ring()


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _get_move_input() -> Vector2:
	var kb := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var t  := TouchInput.move if TouchInput.enabled else Vector2.ZERO
	return (kb + t).limit_length(1.0)


## Auto-climb stairs/steps: if walking into something no taller than STEP_HEIGHT
## with clearance above it, nudge up so the player walks up without jumping.
func _auto_step(motion: Vector3) -> void:
	if not is_on_floor() or motion.length() < 0.001:
		return
	# Blocked at foot level?
	if not test_move(global_transform, motion):
		return
	# Clear if we start a step higher? Then it's a climbable step, not a wall.
	var raised := global_transform.translated(Vector3(0, STEP_HEIGHT, 0))
	if test_move(raised, motion):
		return
	global_position.y += STEP_HEIGHT


func _input_to_world_dir(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	# Both hunter and runner are first-person — move relative to body yaw.
	return (transform.basis * Vector3(input.x, 0, input.y)).normalized()


func _look_scale() -> float:
	return mouse_sensitivity * GameManager.settings_sensitivity


func _apply_look(dyaw: float, dpitch: float) -> void:
	_yaw += dyaw
	_pitch = clampf(_pitch + dpitch, -1.4, 1.4)
	rotation.y = _yaw
	$Head.rotation.x = _pitch


func _ensure_knife() -> void:
	if _knife and is_instance_valid(_knife):
		_knife.visible = true
		return
	_knife = Node3D.new()
	_fps_cam.add_child(_knife)
	_knife.position = Vector3(0.33, -0.30, -0.5)
	_knife.rotation_degrees = Vector3(-72, 8, 14)
	_knife.scale = Vector3.ONE * 0.38
	_knife_base_pos = _knife.position
	_knife_base_rot = _knife.rotation
	var scene := load(GameManager.weapon_path()) as PackedScene
	if scene:
		var model := scene.instantiate()
		_knife.add_child(model)
		Avatar.set_material(model, _simple_mat(Color(0.7, 0.72, 0.78), true))
	else:
		var blade := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.03, 0.013, 0.28)
		blade.mesh = bb
		blade.material_override = _simple_mat(Color(0.82, 0.83, 0.88), true)
		_knife.add_child(blade)


func _throw_knife() -> void:
	if throw_cd > 0.0:
		return
	throw_cd = THROW_COOLDOWN
	var fwd := -_fps_cam.global_transform.basis.z
	var k := KNIFE_SCENE.instantiate()
	get_tree().current_scene.add_child(k)
	k.global_position = _fps_cam.global_position + fwd * 0.8
	k.launch(fwd, peer_id)


## Begin a melee blade swing if off cooldown. Returns true if the swing fired
## (so the caller may resolve the hit), false if still on cooldown.
func swing_blade() -> bool:
	if swing_cd > 0.0 or role != GameManager.Role.HUNTER:
		return false
	swing_cd = SWING_COOLDOWN
	_swing_t = SWING_TIME
	AudioManager.play_sfx("footstep_concrete", -4.0)   # a short blade whoosh
	return true


## Animate the held blade through its swing arc and back to rest.
func _update_swing(_delta: float) -> void:
	if _knife == null or not is_instance_valid(_knife):
		return
	if _swing_t > 0.0:
		_swing_t = maxf(0.0, _swing_t - _delta)
		var p := 1.0 - _swing_t / SWING_TIME       # 0 → 1 over the swing
		var arc := sin(p * PI)                      # 0 → 1 → 0 (out and back)
		_knife.rotation = _knife_base_rot + Vector3(deg_to_rad(-85.0) * arc, 0.0, deg_to_rad(45.0) * arc)
		_knife.position = _knife_base_pos + Vector3(-0.12, 0.06, -0.18) * arc
	elif _knife.position != _knife_base_pos:
		_knife.rotation = _knife_base_rot
		_knife.position = _knife_base_pos


func _simple_mat(color: Color, metal: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if metal:
		m.metallic = 0.8
		m.roughness = 0.25
	return m


# ─────────────────────────────────────────────────────────────────────────────
# PICKUP EFFECTS
# ─────────────────────────────────────────────────────────────────────────────

## Recharge the flashlight battery.
func refill_flash() -> void:
	flash_battery = 1.0

## Legacy stamina refill (kept for compatibility).
func give_adrenaline() -> void:
	stamina = 1.0
	_boost_timer = BOOST_TIME

## Random pickup — can be good or bad. Called by Pickup.gd.
func apply_pickup(effect: String) -> void:
	match effect:
		"heal":
			hp = mini(MAX_HP, hp + 1)
		"stamina":
			stamina = 1.0
			_boost_timer = BOOST_TIME
		"speed":
			_boost_timer = BOOST_TIME * 1.5
		"flash":
			flash_battery = 1.0   # good for hunter, no-op feel for runner
		"slow":
			_slow_debuff_timer = 8.0
		"drain":
			stamina = 0.0
			flash_battery = maxf(0.0, flash_battery - 0.5)
		"damage":
			take_damage(1, -1)


## Reduce the runner's HP. Must be hit by BOTH melee and throw to die.
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
			if is_local:
				var ui := get_tree().get_first_node_in_group("hunting_ui")
				if ui and ui.has_method("show_pickup_effect"):
					var need := "THROW" if _hit_by_melee else "MELEE"
					ui.show_pickup_effect("NEED %s HIT TO FINISH" % need, false)
	if hp > 0 and is_local:
		_slow_debuff_timer = maxf(_slow_debuff_timer, 0.5)
		var ui := get_tree().get_first_node_in_group("hunting_ui")
		if ui and ui.has_method("flash_damage"):
			ui.flash_damage(hp)


## Movement penalty from injury — progressive cripple across 5 HP.
func _cripple_mult() -> float:
	match hp:
		4: return 0.92
		3: return 0.82
		2: return 0.68
		1: return 0.52
		_: return 1.0


## Generator repair speed penalty from injury.
func repair_mult() -> float:
	match hp:
		4: return 0.90
		3: return 0.75
		2: return 0.50
		1: return 0.30
		_: return 1.0


## Freeze the runner in place (ghost lightning grief).
func apply_stun(duration: float) -> void:
	if role != GameManager.Role.HUNTED:
		return
	_stun_timer = maxf(_stun_timer, duration)


var _current_interactable: Node = null

func _try_interact() -> void:
	var ui := get_tree().get_first_node_in_group("hunting_ui")
	if _current_interactable != null:
		_current_interactable.close()
		_current_interactable = null
		if ui and ui.has_method("hide_interact_doc"):
			ui.hide_interact_doc()
		return
	var best: Node = null
	var best_dist := 999.0
	for n in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n):
			continue
		var d := global_position.distance_to(n.global_position)
		if d < 3.5 and d < best_dist:
			best_dist = d
			best = n
	if best != null:
		best.open()
		_current_interactable = best
		if ui and ui.has_method("show_interact_doc"):
			ui.show_interact_doc(best.title, best.body)


func _set_ghost_transparency() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = RemotePlayer.id_color(peer_id, 0.4)
	mat.emission_enabled = true
	mat.emission = RemotePlayer.id_color(peer_id) * 0.5
	Avatar.set_material(_mesh, mat)
