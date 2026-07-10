extends Node3D
## Locker — a hiding spot the runner can duck into.
##
## Press E within 1.8 m to enter. While hiding:
##   • Movement is locked (velocity = 0)
##   • A dark overlay with a 30 s countdown covers the screen
##   • Press E again or wait 30 s to be ejected
##
## The hunter doesn't have a specific "check locker" action — the tension
## comes from hearing footsteps and watching the countdown.

const INTERACT_DIST  := 1.8
const HIDE_TIME      := 30.0

@export var locker_color: Color = Color(0.22, 0.18, 0.16)

var _spawner: Node       # PlayerSpawner for reaching the local player
var _occupied := false   # is someone hiding inside?
var _hide_timer := 0.0   # counts down from HIDE_TIME while occupied

signal player_entered   # so HuntingUI can show the locker overlay
signal player_exited


func _ready() -> void:
	_build_locker_mesh()


func setup(spawner: Node) -> void:
	_spawner = spawner


func _process(delta: float) -> void:
	if GameManager.current_phase != GameManager.Phase.HUNTING:
		return

	var lp := _get_local_player()
	if lp == null:
		return

	var dist := global_position.distance_to(lp.global_position)

	if _occupied:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_eject()
			return
		# Keep player locked in place.
		lp.set("hidden_in_locker", true)
		# Check for voluntary exit (small cooldown so entering doesn't instantly re-eject).
		if Input.is_action_pressed("grab") and _hide_timer < HIDE_TIME - 0.3:
			_eject()
	else:
		# Show hint if close enough (handled by HuntingUI reading this node's data).
		if dist < INTERACT_DIST and lp.get("role") == GameManager.Role.HUNTED:
			if Input.is_action_pressed("grab"):
				_enter(lp)


## The runner enters the locker.
func _enter(lp: Node) -> void:
	_occupied   = true
	_hide_timer = HIDE_TIME
	lp.set("hidden_in_locker", true)
	player_entered.emit()


## Eject the runner from the locker.
func _eject() -> void:
	_occupied = false
	var lp := _get_local_player()
	if lp != null:
		lp.set("hidden_in_locker", false)
	player_exited.emit()


func get_hide_timer() -> float:
	return _hide_timer


func is_occupied() -> bool:
	return _occupied


func get_proximity_to_player() -> float:
	var lp := _get_local_player()
	if lp == null:
		return 9999.0
	return global_position.distance_to(lp.global_position)


func _get_local_player() -> Node3D:
	if _spawner == null:
		return null
	var lp = _spawner.get("local_player")
	return lp if (lp != null and is_instance_valid(lp)) else null


## Build a locker cabinet: tall thin box with a slightly raised door frame.
func _build_locker_mesh() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)

	var shape := CollisionShape3D.new()
	var box   := BoxShape3D.new()
	box.size  = Vector3(0.80, 2.10, 0.60)
	shape.shape = box
	shape.position = Vector3(0, 1.05, 0)
	body.add_child(shape)

	# Cabinet body.
	var mi := MeshInstance3D.new()
	var m  := BoxMesh.new()
	m.size = Vector3(0.80, 2.10, 0.60)
	mi.mesh = m
	mi.position = Vector3(0, 1.05, 0)
	mi.material_override = _mat(locker_color)
	body.add_child(mi)

	# Door frame accent (slightly darker, thinner).
	var door_mi := MeshInstance3D.new()
	var door_m  := BoxMesh.new()
	door_m.size = Vector3(0.72, 1.90, 0.06)
	door_mi.mesh = door_m
	door_mi.position = Vector3(0, 1.05, 0.31)
	door_mi.material_override = _mat(locker_color.darkened(0.35))
	body.add_child(door_mi)

	# Vent slats (cosmetic horizontal lines near the top).
	for i in 4:
		var slat_mi := MeshInstance3D.new()
		var slat_m  := BoxMesh.new()
		slat_m.size = Vector3(0.60, 0.03, 0.07)
		slat_mi.mesh = slat_m
		slat_mi.position = Vector3(0, 1.85 - i * 0.09, 0.31)
		slat_mi.material_override = _mat(locker_color.darkened(0.5))
		body.add_child(slat_mi)

	# Handle (small box).
	var handle_mi := MeshInstance3D.new()
	var handle_m  := BoxMesh.new()
	handle_m.size = Vector3(0.04, 0.20, 0.06)
	handle_mi.mesh = handle_m
	handle_mi.position = Vector3(0.30, 1.05, 0.34)
	handle_mi.material_override = _mat(Color(0.55, 0.55, 0.60))
	body.add_child(handle_mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness    = 0.85
	m.metallic     = 0.25
	return m
