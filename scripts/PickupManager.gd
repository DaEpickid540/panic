extends Node3D
## PickupManager — scatters mystery syringes around the arena each round.
## All 8 pickups look identical (blood-red syringe). Their random good/bad
## effect is only revealed when grabbed — that's the tension.

const SYRINGE_COUNT := 8
const CENTER_CLEAR  := 14.0
const HOVER_Y       := 1.2

const PICKUP_SCRIPT := preload("res://scripts/Pickup.gd")

var _spawner: Node
var _bound: float = 40.0
var _rng := RandomNumberGenerator.new()


func setup(spawner: Node, bound: float) -> void:
	_spawner = spawner
	_bound   = maxf(bound - 6.0, 10.0)
	_rng.randomize()
	for i in SYRINGE_COUNT:
		var pos := _random_spot()
		var p: Node3D = PICKUP_SCRIPT.new()
		add_child(p)
		p.global_position = pos
		p.setup(_spawner)


func _random_spot() -> Vector3:
	for attempt in 20:
		var pos := Vector3(
			_rng.randf_range(-_bound, _bound), HOVER_Y,
			_rng.randf_range(-_bound, _bound))
		if Vector2(pos.x, pos.z).length() > CENTER_CLEAR:
			return pos
	return Vector3(_bound * 0.5, HOVER_Y, _bound * 0.5)
