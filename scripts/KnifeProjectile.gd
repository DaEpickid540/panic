extends Area3D
## KnifeProjectile — the weapon the hunter throws.
##
## With the HP system, hitting a HUNTED player reduces their HP by 1.
## After three hits they become a ghost (instead of dying instantly).
## Wall collision despawns the projectile immediately.

const SPEED    := 30.0
const DROP     := 10.0
const MAX_LIFE := 2.5

var _vel     := Vector3.ZERO
var _thrower := -1
var _life    := 0.0


func _ready() -> void:
	collision_mask = 1 << 1
	monitoring = true
	body_entered.connect(_on_body)

	var scene := load(GameManager.weapon_path()) as PackedScene
	if scene:
		var box := get_node_or_null("Mesh")
		if box:
			box.queue_free()
		var model := scene.instantiate()
		add_child(model)
		model.scale = Vector3.ONE * 0.72
		model.rotation_degrees = Vector3(-90, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.74, 0.8)
		mat.metallic  = 0.8
		mat.roughness = 0.3
		Avatar.set_material(model, mat)


func launch(dir: Vector3, thrower_id: int) -> void:
	_thrower = thrower_id
	_vel = dir.normalized() * SPEED
	look_at(global_position + dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	var prev := global_position
	_vel.y -= DROP * delta
	global_position += _vel * delta

	var space  := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(prev, global_position, 1)
	if space.intersect_ray(params):
		queue_free()
		return

	# End-over-end tumble: rotate around the axis perpendicular to velocity
	# in world space so the spin looks correct regardless of model orientation.
	var side := _vel.cross(Vector3.UP)
	if side.length_squared() > 0.001:
		rotate(side.normalized(), delta * 16.0)
	else:
		rotate_object_local(Vector3.RIGHT, delta * 16.0)

	_life += delta
	if _life > MAX_LIFE or global_position.y < -1.0:
		queue_free()


func _on_body(body: Node) -> void:
	var owner_node := body.get_parent()
	if owner_node and ("peer_id" in owner_node) and ("role" in owner_node):
		if owner_node.peer_id == _thrower:
			return
		if owner_node.role == GameManager.Role.HUNTED:
			if owner_node.has_method("take_damage"):
				owner_node.take_damage(1, _thrower, "throw")
			else:
				GameManager.capture_player(owner_node.peer_id, _thrower)
	queue_free()
