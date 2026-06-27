extends Node3D
## Interactable — press E near this to read lore text full-screen.

const RANGE := 3.5

@export var title: String = ""
@export var body: String = ""
var showing := false


func _ready() -> void:
	add_to_group("interactable")


func open() -> void:
	showing = true


func close() -> void:
	showing = false
