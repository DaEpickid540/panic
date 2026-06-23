extends Node3D
class_name Pickup
## Pickup — a mysterious blood-red syringe floating in the arena.
##
## You don't know what's inside until you grab it. Could be medicine.
## Could be something much worse. Effects are 50/50 good/bad.
##
## Effects (any role can pick up any syringe):
##   GOOD → "heal"  (runner +1 HP),  "stamina" (refill + boost), "speed" (6s sprint)
##   BAD  → "slow"  (8s half-speed), "drain"   (stamina empty),  "damage" (-1 HP)

const RESPAWN_TIME := 25.0
const PICKUP_RANGE := 1.8
const BOB_HEIGHT   := 0.32
const BOB_SPEED    := 1.8
const SPIN_SPEED   := 1.2

# Equal split: 3 good, 3 bad.
const EFFECTS := ["heal", "stamina", "speed", "slow", "drain", "damage"]

var _spawner: Node
var _base_y: float = 1.2
var _t: float = 0.0
var _respawn: float = 0.0
var _visual: Node3D
var _glow: OmniLight3D


func setup(p_spawner: Node) -> void:
	_spawner = p_spawner
	_base_y  = global_position.y
	_build_visual()


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	# Syringe body: dark red cylinder.
	var body_mi := MeshInstance3D.new()
	var body_m  := CylinderMesh.new()
	body_m.top_radius    = 0.08
	body_m.bottom_radius = 0.08
	body_m.height        = 0.70
	body_mi.mesh = body_m
	body_mi.material_override = _emissive_mat(Color(0.75, 0.02, 0.04))
	_visual.add_child(body_mi)

	# Plunger top (darker cap).
	var cap_mi := MeshInstance3D.new()
	var cap_m  := CylinderMesh.new()
	cap_m.top_radius    = 0.11
	cap_m.bottom_radius = 0.11
	cap_m.height        = 0.08
	cap_mi.mesh = cap_m
	cap_mi.position = Vector3(0, 0.39, 0)
	cap_mi.material_override = _emissive_mat(Color(0.40, 0.01, 0.02))
	_visual.add_child(cap_mi)

	# Needle (thin cylinder pointing down).
	var needle_mi := MeshInstance3D.new()
	var needle_m  := CylinderMesh.new()
	needle_m.top_radius    = 0.014
	needle_m.bottom_radius = 0.006
	needle_m.height        = 0.22
	needle_mi.mesh = needle_m
	needle_mi.position = Vector3(0, -0.46, 0)
	needle_mi.material_override = _emissive_mat(Color(0.70, 0.68, 0.72))
	_visual.add_child(needle_mi)

	# Glow (blood red, faint).
	_glow = OmniLight3D.new()
	_glow.light_color  = Color(0.9, 0.05, 0.05)
	_glow.light_energy = 1.0
	_glow.omni_range   = 5.0
	add_child(_glow)


func _process(delta: float) -> void:
	if _respawn > 0.0:
		_respawn -= delta
		if _respawn <= 0.0:
			_set_shown(true)
		return

	_t += delta
	global_position.y = _base_y + sin(_t * BOB_SPEED) * BOB_HEIGHT
	if _visual:
		_visual.rotation.y += SPIN_SPEED * delta
		# Tip the syringe at an angle (looks more sinister than straight up).
		_visual.rotation.z = 0.4 + sin(_t * 0.9) * 0.08

	if _spawner == null:
		return
	var lp = _spawner.local_player
	if lp == null or not is_instance_valid(lp):
		return
	if global_position.distance_to(lp.global_position) <= PICKUP_RANGE:
		_try_collect(lp)


func _try_collect(lp) -> void:
	if not lp.has_method("apply_pickup"):
		return
	var eff: String = EFFECTS[randi() % EFFECTS.size()]
	lp.apply_pickup(eff)
	_collected(eff)


func _collected(effect: String) -> void:
	AudioManager.play_sfx("countdown_beep", -1.0)
	_respawn = RESPAWN_TIME
	_set_shown(false)
	# Broadcast effect name to HuntingUI for the toast label.
	var ui := _find_hunting_ui()
	if ui and ui.has_method("show_pickup_effect"):
		var good := effect in ["heal", "stamina", "speed", "flash"]
		ui.show_pickup_effect(effect.to_upper(), good)


func _find_hunting_ui() -> Node:
	return get_tree().get_first_node_in_group("hunting_ui")


func _set_shown(shown: bool) -> void:
	if _visual: _visual.visible = shown
	if _glow:   _glow.visible   = shown


func _emissive_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color               = color
	m.emission_enabled           = true
	m.emission                   = color
	m.emission_energy_multiplier = 1.6
	return m
