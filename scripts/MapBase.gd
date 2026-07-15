extends Node3D
class_name MapBase
## MapBase
##
## Procedurally builds a 110x110 m arena. Each `style` produces a visually
## distinct, themed set of structures (curved geometry: cylinders, domes,
## pitched roofs), its own palette, ground tint and lighting — while keeping the
## same size, collision footprint and spawn layout for fair play.

# Styles are appended (never reordered) so existing scenes' integer `style`
# values stay valid. CABIN replaced URBAN in-place (same value = 0); CITY is new.
enum Style { CABIN, FOREST, WAREHOUSE, MANSION, NEON, GRAVEYARD, MAZE, DUNGEON, SCHOOL, CAVE, LAB, PARKOUR_VOID, CITY }

const ARENA_SIZE := 200.0
const HALF := ARENA_SIZE * 0.5
## Indoor maps use a much tighter footprint than the open 200 m arena so they
## feel like real buildings and stay densely furnished instead of cavernous.
const INDOOR_HALF := 52.0
const WALL_HEIGHT := 14.0
const OBSTACLE_COUNT := 70
const PERIMETER_SPAWNS := 16
const CENTER_CLEAR := 14.0
const SPACING := 14.0

const RED := Color(0.8, 0.0, 0.0)

## Per-style colour palettes.
const PALETTES := {
	Style.CABIN: [
		Color(0.36, 0.24, 0.14),  # log brown
		Color(0.28, 0.18, 0.11),  # dark timber
		Color(0.25, 0.34, 0.20),  # moss green
		Color(0.42, 0.42, 0.44),  # fieldstone
		Color(0.45, 0.20, 0.12),  # rusty red
	],
	Style.CITY: [
		Color(0.28, 0.29, 0.33),  # wet asphalt gray
		Color(0.45, 0.22, 0.18),  # old brick
		Color(0.55, 0.56, 0.58),  # concrete
		Color(0.20, 0.24, 0.30),  # steel blue
		Color(0.60, 0.50, 0.25),  # sodium-lamp amber
	],
	Style.FOREST: [
		Color(0.27, 0.45, 0.22), Color(0.34, 0.52, 0.26), Color(0.45, 0.36, 0.22),
		Color(0.30, 0.40, 0.24), Color(0.50, 0.42, 0.28),
	],
	Style.WAREHOUSE: [
		Color(0.36, 0.37, 0.42),  # steel gray
		Color(0.20, 0.22, 0.26),  # dark metal
		Color(0.72, 0.40, 0.07),  # safety orange
		Color(0.80, 0.74, 0.08),  # safety yellow
		Color(0.26, 0.48, 0.24),  # industrial green
	],
	Style.MANSION: [
		Color(0.42, 0.10, 0.12),  # deep crimson wallpaper
		Color(0.72, 0.58, 0.30),  # antique gold
		Color(0.86, 0.80, 0.66),  # cream trim
		Color(0.28, 0.18, 0.12),  # dark walnut
		Color(0.34, 0.14, 0.20),  # wine
	],
	Style.MAZE: [
		Color(0.45, 0.12, 0.16), Color(0.78, 0.62, 0.32), Color(0.80, 0.74, 0.60),
		Color(0.34, 0.22, 0.18), Color(0.40, 0.22, 0.34),
	],
	Style.DUNGEON: [
		Color(0.34, 0.32, 0.30), Color(0.26, 0.24, 0.22), Color(0.40, 0.38, 0.34),
		Color(0.22, 0.20, 0.19), Color(0.30, 0.27, 0.24),
	],
	Style.SCHOOL: [
		Color(0.78, 0.76, 0.68),  # pale plaster wall
		Color(0.30, 0.45, 0.70),  # locker blue
		Color(0.70, 0.25, 0.22),  # locker red
		Color(0.55, 0.58, 0.60),  # grey trim
		Color(0.40, 0.30, 0.20),  # wood desk
	],
	Style.CAVE: [
		Color(0.30, 0.30, 0.34), Color(0.24, 0.24, 0.28), Color(0.36, 0.35, 0.38),
		Color(0.20, 0.21, 0.24), Color(0.28, 0.27, 0.30),
	],
	Style.LAB: [
		Color(0.88, 0.88, 0.90), Color(0.75, 0.78, 0.82), Color(0.60, 0.62, 0.65),
		Color(0.92, 0.92, 0.94), Color(0.40, 0.42, 0.48),
	],
	Style.NEON: [
		Color(0.10, 0.95, 0.92), Color(0.95, 0.20, 0.75), Color(0.55, 0.95, 0.20),
		Color(0.30, 0.45, 1.00), Color(1.00, 0.45, 0.10),
	],
	Style.GRAVEYARD: [
		Color(0.42, 0.45, 0.48), Color(0.33, 0.38, 0.36), Color(0.30, 0.26, 0.36),
		Color(0.48, 0.50, 0.46), Color(0.26, 0.30, 0.34),
	],
}

@export var style: Style = Style.CABIN
@export var ground_color: Color = Color(0.35, 0.35, 0.40)
@export var obstacle_color: Color = Color(0.18, 0.18, 0.20)
@export var seed_value: int = 1337

const SBS := "res://assets/textures/SBS - Tiny Texture Pack - 128x128/128x128"
const TEX_PATHS := {
	"wood": "res://assets/textures/mat_wood.png",
	"concrete": "res://assets/textures/mat_concrete.png",
	"metal": "res://assets/textures/mat_metal.png",
	"brick": SBS + "/Bricks/Bricks_01-128x128.png",
	"tile": SBS + "/Tile/Tile_01-128x128.png",
	"sbswood": SBS + "/Wood/Wood_01-128x128.png",
	"sbsgrass": SBS + "/Grass/Grass_01-128x128.png",
	"rock": "res://assets/models/forestpack/RockTexture/rockTexture1.png",
}

## Interior-wall texture for partition-based maps; set per style in _ready.
var _wall_tex := "concrete"
## Exterior-shell (perimeter walls) texture; set per style in _ready ("" = none).
var _shell_tex := ""

## Half-footprint actually used: full arena outdoors, tighter indoors. Set in _ready.
var _half: float = HALF

## Real low-poly foliage meshes (imported as Mesh resources).
const FOLIAGE_TREES := [
	"res://assets/models/foliage2/Low_Poly_Tree_001.obj",
	"res://assets/models/foliage2/Low_Poly_Tree_002.obj",
	"res://assets/models/foliage2/Low_Poly_Tree_003.obj",
	"res://assets/models/foliage2/Low_Poly_Tree_004.obj",
	"res://assets/models/foliage2/Low_Poly_Tree_005.obj",
	"res://assets/models/foliage2/Low_Poly_Tree_006.obj",
]
const FOLIAGE_BUSHES := [
	"res://assets/models/foliage2/Low_Poly_Bush_001.obj",
	"res://assets/models/foliage2/Low_Poly_Bush_002.obj",
]

# ── External asset packs (FBX scenes / OBJ meshes) ───────────────────────────
const FP := "res://assets/models/forestpack"
const FOREST_TREES := [
	FP + "/Trees/OakTree1.fbx", FP + "/Trees/OakTree2.fbx", FP + "/Trees/OakTree3.fbx",
	FP + "/Trees/SpruceTree1.fbx", FP + "/Trees/SpruceTree2.fbx", FP + "/Trees/SpruceTree3.fbx",
]
const FOREST_DEAD := [
	FP + "/Trees/DeadOak1.fbx", FP + "/Trees/DeadOak2.fbx", FP + "/Trees/DeadOak3.fbx",
	FP + "/Trees/DeadSpruce1.fbx", FP + "/Trees/DeadSpruce2.fbx", FP + "/Trees/DeadSpruce3.fbx",
]
const FOREST_ROCKS := [
	FP + "/Rocks/Rock1.fbx", FP + "/Rocks/Rock3.fbx", FP + "/Rocks/Rock5.fbx",
	FP + "/Rocks/Rock7.fbx", FP + "/Rocks/BigRock1.fbx", FP + "/Rocks/BigRock3.fbx",
]
const PSI := "res://assets/models/psionic"
const PSI_PLANTS := [
	PSI + "/flower1.obj", PSI + "/flower2.obj", PSI + "/flower3.obj",
	PSI + "/flower4.obj", PSI + "/grass1.obj", PSI + "/mushroom1.obj",
]
const VAMP := "res://assets/models/vampire/02_Vampire_Set"
const DUN := "res://assets/models/dungeon/obj"

var _rng := RandomNumberGenerator.new()
var _emissive := false   # neon structures glow
var _indoor := false     # true for fully-enclosed building maps (thick walls + ceiling)
var _tex_cache := {}

const FLICKER_SCRIPT := preload("res://scripts/FlickerLight.gd")


## Styles that are fully-enclosed buildings (thick walls + ceiling) instead of
## open-air arenas. Mansion & Neon become room-partitioned interiors; Warehouse
## keeps its shelf-aisle layout but sealed under a roof. The rest stay outdoor.
const INDOOR_STYLES := [Style.MANSION, Style.NEON, Style.WAREHOUSE, Style.MAZE,
	Style.DUNGEON, Style.SCHOOL, Style.CAVE, Style.LAB]

func _ready() -> void:
	_rng.seed = seed_value
	# Parkour void is a self-contained clean white room — skip the normal
	# floor/walls/obstacle pipeline entirely.
	if style == Style.PARKOUR_VOID:
		_half = 58.0
		_build_parkour_void()
		_build_spawns()
		return
	_emissive = style == Style.NEON
	# Indoor maps are fully-enclosed buildings (Murder-Mystery-2 style):
	# thick exterior walls, a ceiling, and interior rooms/corridors.
	_indoor = style in INDOOR_STYLES
	_half = INDOOR_HALF if _indoor else HALF
	# Per-style footprint tweaks: the lab is deliberately tighter than the other
	# indoor maps (cramped RE-style corridors); the city is a mid-size block grid.
	if style == Style.LAB:
		_half = 46.0
	elif style == Style.CITY:
		_half = 72.0
	match style:
		Style.DUNGEON, Style.MAZE: _wall_tex = "brick"
		Style.MANSION:             _wall_tex = "sbswood"
		Style.SCHOOL:              _wall_tex = "concrete"
		Style.CAVE:                _wall_tex = "rock"
		Style.LAB:                 _wall_tex = "tile"
		Style.CABIN:               _wall_tex = "sbswood"
		Style.CITY:                _wall_tex = "brick"
		_:                         _wall_tex = "concrete"
	if style == Style.CAVE:
		_shell_tex = "rock"
	_build_environment()
	_build_floor()
	_build_walls()
	if _indoor:
		_build_ceiling()
	_build_obstacles()
	_spawn_round_doors()
	_spawn_gen_markers()
	_build_spawns()


## True for fully-enclosed building maps (walls + ceiling). Objective/pickup
## placement uses this to keep spawns inside the interior shell.
func is_enclosed() -> bool:
	return _indoor


## Interior half-extent generators/pickups should stay within.
func interior_half() -> float:
	return _half


## --- Lighting (per style) ------------------------------------------------

## Near-pitch-black horror night with thick fog. Hunter relies on the flashlight;
## hunted get the blindness vignette. Accent omnis are faint embers.
func _env_params() -> Dictionary:
	match style:
		Style.FOREST:
			return {"amb": Color(0.07, 0.09, 0.07), "ae": 0.10, "sun": Color(0.24, 0.30, 0.36),
				"se": 0.14, "fog": Color(0.03, 0.04, 0.03), "fd": 0.028, "accent": Color(0.30, 0.45, 0.22)}
		Style.WAREHOUSE:
			return {"amb": Color(0.07, 0.07, 0.08), "ae": 0.10, "sun": Color(0.26, 0.26, 0.32),
				"se": 0.14, "fog": Color(0.03, 0.03, 0.035), "fd": 0.026, "accent": Color(0.55, 0.32, 0.08)}
		Style.MANSION:
			# Warmer + brighter than the rest: a chandelier-lit manor, not pitch black.
			return {"amb": Color(0.16, 0.12, 0.09), "ae": 0.22, "sun": Color(0.40, 0.32, 0.22),
				"se": 0.22, "fog": Color(0.06, 0.045, 0.03), "fd": 0.016, "accent": Color(0.95, 0.70, 0.40)}
		Style.MAZE:
			return {"amb": Color(0.08, 0.07, 0.06), "ae": 0.10, "sun": Color(0.26, 0.22, 0.18),
				"se": 0.13, "fog": Color(0.03, 0.025, 0.02), "fd": 0.030, "accent": Color(0.55, 0.28, 0.10)}
		Style.DUNGEON:
			# Dark stone, lit by flickering torches (built into the layout).
			return {"amb": Color(0.07, 0.06, 0.05), "ae": 0.12, "sun": Color(0.18, 0.15, 0.12),
				"se": 0.10, "fog": Color(0.03, 0.025, 0.02), "fd": 0.028, "accent": Color(1.0, 0.55, 0.20)}
		Style.SCHOOL:
			# Cold fluorescent corridors — brighter, sickly, abandoned-school feel.
			return {"amb": Color(0.16, 0.17, 0.18), "ae": 0.22, "sun": Color(0.30, 0.33, 0.36),
				"se": 0.18, "fog": Color(0.05, 0.06, 0.06), "fd": 0.016, "accent": Color(0.7, 0.85, 0.9)}
		Style.CAVE:
			return {"amb": Color(0.05, 0.06, 0.07), "ae": 0.10, "sun": Color(0.12, 0.14, 0.18),
				"se": 0.08, "fog": Color(0.02, 0.025, 0.03), "fd": 0.035, "accent": Color(0.3, 0.7, 0.9)}
		Style.LAB:
			# Dim, failing facility power — cold pools of flickering fluorescent
			# light in the dark. Resident-Evil basement lab, not a bright clinic.
			return {"amb": Color(0.10, 0.11, 0.13), "ae": 0.16, "sun": Color(0.20, 0.23, 0.28),
				"se": 0.10, "fog": Color(0.035, 0.04, 0.05), "fd": 0.022, "accent": Color(0.55, 0.75, 0.85)}
		Style.CABIN:
			# Moonless woods around a lamplit cabin — the trees swallow the light.
			return {"amb": Color(0.06, 0.07, 0.07), "ae": 0.10, "sun": Color(0.20, 0.26, 0.34),
				"se": 0.12, "fog": Color(0.025, 0.032, 0.028), "fd": 0.030, "accent": Color(1.0, 0.62, 0.28)}
		Style.CITY:
			# Dead city at 3 AM: sodium streetlights, wet asphalt, low haze.
			return {"amb": Color(0.07, 0.08, 0.10), "ae": 0.12, "sun": Color(0.20, 0.22, 0.30),
				"se": 0.12, "fog": Color(0.03, 0.032, 0.04), "fd": 0.022, "accent": Color(0.95, 0.62, 0.25)}
		Style.NEON:
			return {"amb": Color(0.06, 0.06, 0.11), "ae": 0.11, "sun": Color(0.16, 0.18, 0.32),
				"se": 0.11, "fog": Color(0.03, 0.02, 0.07), "fd": 0.030, "accent": Color(0.10, 0.85, 0.85)}
		Style.GRAVEYARD:
			return {"amb": Color(0.08, 0.09, 0.11), "ae": 0.11, "sun": Color(0.22, 0.26, 0.34),
				"se": 0.14, "fog": Color(0.05, 0.06, 0.07), "fd": 0.034, "accent": Color(0.40, 0.26, 0.55)}
		_:
			return {"amb": Color(0.07, 0.07, 0.09), "ae": 0.10, "sun": Color(0.24, 0.25, 0.32),
				"se": 0.14, "fog": Color(0.035, 0.035, 0.04), "fd": 0.028, "accent": RED}


func _build_environment() -> void:
	var p := _env_params()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = (p["fog"] as Color).lightened(0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = p["amb"]
	env.ambient_light_energy = p["ae"]
	env.fog_enabled = not TouchInput.enabled
	env.fog_light_color = p["fog"]
	env.fog_density = p["fd"] * clampf(GameManager.settings_fog, 0.1, 1.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = p["sun"]
	sun.light_energy = p["se"]
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(40), 0)
	sun.shadow_enabled = true
	add_child(sun)

	var accent: Color = p["accent"]
	var hh := _half
	for c in [Vector3(-hh + 5, 5, -hh + 5), Vector3(hh - 5, 5, hh - 5),
			Vector3(-hh + 5, 5, hh - 5), Vector3(hh - 5, 5, -hh + 5)]:
		# FlickerLight = an OmniLight3D that flickers like failing wiring.
		var o: OmniLight3D = FLICKER_SCRIPT.new()
		o.light_color = accent
		o.light_energy = 0.6        # faint embers; the dark is the point
		o.omni_range = 22.0
		o.position = c
		add_child(o)


## --- Geometry ------------------------------------------------------------

func _build_floor() -> void:
	var fs := _half * 2.0
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(fs, 1, fs)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(fs, 1, fs)
	mi.mesh = mesh
	mi.position = Vector3(0, -0.5, 0)
	mi.material_override = _ground_mat()
	body.add_child(mi)


func _build_walls() -> void:
	# Indoor maps use THICK, solid walls (you can't see or clip through them).
	# Open maps keep a thinner translucent boundary you rarely reach. Either way
	# the walls are now several metres thick so fast/dashing players can't tunnel.
	var t := 4.0 if _indoor else 2.0
	var hh := _half
	var span := _half * 2.0
	var specs := [
		[Vector3(0, WALL_HEIGHT * 0.5, -hh), Vector3(span, WALL_HEIGHT, t)],
		[Vector3(0, WALL_HEIGHT * 0.5, hh), Vector3(span, WALL_HEIGHT, t)],
		[Vector3(-hh, WALL_HEIGHT * 0.5, 0), Vector3(t, WALL_HEIGHT, span)],
		[Vector3(hh, WALL_HEIGHT * 0.5, 0), Vector3(t, WALL_HEIGHT, span)],
	]
	# Walls are SOLID on every map now — outdoor arenas are sealed boundaries so
	# players can never wander off into the open terrain.
	var wall_col := obstacle_color.darkened(0.15) if _indoor else obstacle_color.darkened(0.05)
	var mat := _mat(wall_col, _shell_tex)   # _shell_tex textures rocky cave walls
	mat.roughness = 0.9
	for s in specs:
		var center: Vector3 = s[0]
		var size: Vector3 = s[1]
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = center
		add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)


## Solid ceiling for indoor maps — seals the building so there's no "outside".
func _build_ceiling() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = Vector3(0, WALL_HEIGHT, 0)
	add_child(body)
	var cs := _half * 2.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(cs, 1.0, cs)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cs, 1.0, cs)
	mi.mesh = mesh
	mi.material_override = _mat(obstacle_color.darkened(0.35))
	body.add_child(mi)


func _build_obstacles() -> void:
	match style:
		Style.WAREHOUSE:
			_build_factory_layout()                # two-storey enclosed factory
		Style.MANSION:
			_build_mansion_layout()                # grand lived-in manor
		Style.MAZE:
			_build_indoor_layout()                 # tight room/corridor maze
		Style.FOREST:
			_build_forest_layout()                 # dense chaotic woods
		Style.DUNGEON:
			_build_dungeon_layout()                # torch-lit modular dungeon
		Style.SCHOOL:
			_build_school_layout()                 # classrooms, lockers, corridors
		Style.CAVE:
			_build_cave_layout()                   # rocky cavern lit by crystals
		Style.LAB:
			_build_lab_layout()                    # cramped RE-style research lab
		Style.CABIN:
			_build_cabin_layout()                  # cabin in the dark woods
		Style.CITY:
			_build_city_layout()                   # night-time city block
		_:
			if _indoor:
				_build_indoor_layout()
			else:
				_build_random_obstacles()          # open-air arena


## Dense, chaotic forest built from the Lowpoly Forest Pack (FBX), with rocks,
## dead trees and undergrowth packed tight so sightlines are short and twisty.
func _build_forest_layout() -> void:
	var green := Color(0.20, 0.36, 0.16)
	var pine  := Color(0.16, 0.30, 0.20)
	var dead  := Color(0.30, 0.24, 0.17)
	var stone := Color(0.42, 0.43, 0.46)

	var placed := 0
	var attempts := 0
	var used: Array[Vector3] = []
	while placed < 150 and attempts < 2400:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-HALF + 8, HALF - 8), 0,
				_rng.randf_range(-HALF + 8, HALF - 8))
		if pos.length() < CENTER_CLEAR:
			continue
		var too_close := false
		for u in used:
			if u.distance_to(pos) < 3.6:        # tight packing = chaotic thicket
				too_close = true
				break
		if too_close:
			continue
		used.append(pos)
		var r := _rng.randf()
		if r < 0.46:
			var leafy: bool = _rng.randf() < 0.5
			_spawn_model(_pick(FOREST_TREES), pos, _rng.randf_range(7.0, 14.0),
				pine if leafy else green, 0.12)
		elif r < 0.66:
			_spawn_model(_pick(FOREST_DEAD), pos, _rng.randf_range(6.0, 12.0), dead, 0.10)
		elif r < 0.82:
			_spawn_model(_pick(FOREST_ROCKS), pos, _rng.randf_range(1.4, 4.5), stone, 0.42)
		elif r < 0.92:
			_make_foliage(pos, FOLIAGE_BUSHES, 1.6, 3.0, Color(0.18, 0.32, 0.16), 0.45)
		else:
			_spawn_model(_pick(PSI_PLANTS), pos, _rng.randf_range(0.6, 1.4),
				Color(0.30, 0.5, 0.22), 0.0, false)   # undergrowth, no collision
		placed += 1

	# Curated generator spots ringed through the woods. Trees that land on one are
	# skipped at spawn, leaving the generator in a small clearing.
	for a in 8:
		var ang := TAU * a / 8.0 + 0.2
		var rad := 34.0 + (a % 2) * 14.0
		_add_gen_spot(Vector3(cos(ang) * rad, 0, sin(ang) * rad))


## Torch-lit modular dungeon: stone rooms/corridors dressed with the Modular
## Dungeon kit (barrels, chests, columns, crates) and flickering wall torches.
const DUN_PROPS := [
	"/Barrel.obj", "/Barrel2.obj", "/Crate.obj", "/Chest.obj", "/Chest_Gold.obj",
	"/Coin_Pile.obj", "/Bag_Standing.obj", "/Bucket.obj", "/Chair.obj",
]

func _build_dungeon_layout() -> void:
	# Stone walls split the footprint into chambers + corridors.
	var lines := [-_half * 0.6, -_half * 0.22, _half * 0.22, _half * 0.6]
	for x in lines:
		_make_partition(true, x, _gap_centers())
	for z in lines:
		_make_partition(false, z, _gap_centers())

	# Scatter dungeon props (kept off the wall lines so doorways stay clear).
	var placed := 0
	var attempts := 0
	var used: Array[Vector3] = []
	while placed < 55 and attempts < 900:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-_half + 6, _half - 6), 0,
				_rng.randf_range(-_half + 6, _half - 6))
		if pos.length() < CENTER_CLEAR:
			continue
		if _near_any(pos.x, lines, 4.0) or _near_any(pos.z, lines, 4.0):
			continue
		var too_close := false
		for u in used:
			if u.distance_to(pos) < 6.0:
				too_close = true
				break
		if too_close:
			continue
		used.append(pos)
		if _rng.randf() < 0.22:
			_spawn_model(DUN + "/Column.obj", pos, _rng.randf_range(3.2, 4.2), Color(1, 1, 1), 0.4)
		else:
			_spawn_model(DUN + _pick(DUN_PROPS), pos, _rng.randf_range(1.0, 1.9), Color(1, 1, 1), 0.4)
		placed += 1

	# Flickering torches across the footprint — reads clearly but stays moody.
	for gx in [-_half * 0.66, -_half * 0.33, 0.0, _half * 0.33, _half * 0.66]:
		for gz in [-_half * 0.66, -_half * 0.33, 0.0, _half * 0.33, _half * 0.66]:
			_make_torch(Vector3(gx, 4.2, gz))

	# Curated generator spots at chamber centres (midway between the partition
	# lines at +-11 and +-31), clear of walls and doorways.
	var chamber := _half * 0.41   # ~21 m — centre of the mid ring of chambers
	_add_gen_spot(Vector3(-chamber, 0, -chamber))
	_add_gen_spot(Vector3(chamber, 0, -chamber))
	_add_gen_spot(Vector3(-chamber, 0, chamber))
	_add_gen_spot(Vector3(chamber, 0, chamber))
	_add_gen_spot(Vector3(0, 0, -chamber))
	_add_gen_spot(Vector3(0, 0, chamber))
	_add_gen_spot(Vector3(-chamber, 0, 0))
	_add_gen_spot(Vector3(chamber, 0, 0))


## A flickering wall torch: ember bulb + warm flickering omni light.
func _make_torch(pos: Vector3) -> void:
	_make_emissive_sphere(pos + Vector3(0, 0.2, 0), 0.16, Color(1.0, 0.5, 0.15))
	var o: OmniLight3D = FLICKER_SCRIPT.new()
	o.light_color = Color(1.0, 0.55, 0.2)
	o.light_energy = 1.7
	o.omni_range = 17.0
	o.position = pos
	add_child(o)


## School: classrooms and locker-lined corridors under cold fluorescent light.
func _build_school_layout() -> void:
	# Oakwood Primary School — two-story layout from floor plan.
	# Ground floor: lobby (east), cafeteria (north), hallway + classrooms (south)
	# Second floor: balcony overlooking cafeteria, upper hallway + classrooms, library, science lab
	var h := _half  # 52 m half-size (indoor)
	var F2 := 5.5   # second floor height
	var wood := Color(0.45, 0.32, 0.18)
	var plaster := Color(0.78, 0.76, 0.68)
	var tile := Color(0.65, 0.65, 0.62)
	var dark := Color(0.3, 0.28, 0.25)

	# ── GROUND FLOOR ──

	# Main hallway runs east-west through center
	var hall_z := 0.0
	var hall_w := 5.0  # hallway width (half)

	# North wall of hallway
	_make_box(Vector3(0, WALL_HEIGHT * 0.25, -hall_w), Vector3(h * 2 - 8, WALL_HEIGHT * 0.5, 0.4), plaster, "concrete")
	# South wall of hallway
	_make_box(Vector3(0, WALL_HEIGHT * 0.25, hall_w), Vector3(h * 2 - 8, WALL_HEIGHT * 0.5, 0.4), plaster, "concrete")

	# Gaps in hallway walls for classroom doors (every ~16m)
	# North side: 4 classrooms + admin office
	var class_x := [-h + 14, -h + 30, -h + 46, h - 24]
	for cx in class_x:
		# Door gap already handled by wall segments — we build classroom interiors
		pass

	# ── CAFETERIA (north half, big open space) ──
	var caf_z := -h * 0.5  # center of cafeteria
	var caf_depth := h - hall_w - 2  # from hallway north wall to perimeter
	# Cafeteria tables (long rows)
	for row in 5:
		var tz := -hall_w - 6 - row * 5.5
		for col in 4:
			var tx := -h + 12 + col * 14.0
			_make_cafeteria_table(Vector3(tx, 0, tz), wood)

	# Kitchen / servery wall (northeast corner)
	_make_box(Vector3(h - 16, WALL_HEIGHT * 0.25, -h + 12), Vector3(0.4, WALL_HEIGHT * 0.5, 22), plaster, "concrete")
	_make_box(Vector3(h - 8, WALL_HEIGHT * 0.25, -h + 2), Vector3(14, WALL_HEIGHT * 0.5, 0.4), plaster, "concrete")
	# Kitchen counters
	_make_box(Vector3(h - 10, 0.9, -h + 6), Vector3(8, 0.9, 1.2), Color(0.55, 0.55, 0.6), "metal")
	_make_box(Vector3(h - 6, 0.9, -h + 10), Vector3(1.2, 0.9, 6), Color(0.55, 0.55, 0.6), "metal")

	# ── CLASSROOMS (south side, behind hallway) ──
	# 6 classrooms along south wall
	for i in 6:
		var cx := -h + 9 + i * 15.5
		var cz := hall_w + 14
		# Classroom divider walls
		if i < 5:
			var wall_x := -h + 16.5 + i * 15.5
			_make_box(Vector3(wall_x, WALL_HEIGHT * 0.25, cz), Vector3(0.3, WALL_HEIGHT * 0.5, 18), plaster, "concrete")
		# Desks inside each classroom
		for dx in [-3.5, 0.0, 3.5]:
			for dz in [-4.0, 0.0, 4.0]:
				_make_desk(Vector3(cx + dx, 0, cz + dz), wood)
		# Chalkboard on back wall
		_make_chalkboard(Vector3(cx, 2.4, hall_w + 2), Vector3(0, 0, 1))

	# Restrooms (between classrooms 3 & 4 on south side)
	var rest_x := -h + 9 + 2.5 * 15.5
	_make_box(Vector3(rest_x, WALL_HEIGHT * 0.25, hall_w + 10), Vector3(8, WALL_HEIGHT * 0.5, 0.3), plaster, "concrete")
	_make_box(Vector3(rest_x, WALL_HEIGHT * 0.25, hall_w + 18), Vector3(8, WALL_HEIGHT * 0.5, 0.3), tile, "tile")
	_make_box(Vector3(rest_x, WALL_HEIGHT * 0.25, hall_w + 14), Vector3(0.3, WALL_HEIGHT * 0.5, 8), plaster, "concrete")

	# Entrance lobby (east end)
	_make_box(Vector3(h - 6, WALL_HEIGHT * 0.25, 0), Vector3(0.4, WALL_HEIGHT * 0.5, hall_w * 2 + 4), plaster, "concrete")

	# Admin office (northeast, behind cafeteria)
	_make_box(Vector3(h - 24, WALL_HEIGHT * 0.25, -hall_w - 2), Vector3(0.4, WALL_HEIGHT * 0.5, 12), plaster, "concrete")
	_make_box(Vector3(h - 18, 0.9, -hall_w - 6), Vector3(4, 0.9, 1.0), wood, "wood")

	# Locker banks along hallway
	for lx in [-h + 10, -h + 26, -h + 42, h - 30, h - 14]:
		_make_locker_bank(Vector3(lx, 0, -hall_w + 0.8), true)
		_make_locker_bank(Vector3(lx, 0, hall_w - 0.8), true)

	# Curated generator spots — open ground-floor spaces (hallway, cafeteria aisle,
	# classroom fronts, lobby). Physics-validated at spawn, so any that a desk or
	# table lands on is simply skipped.
	_add_gen_spot(Vector3(-30, 0, 0))          # west hallway
	_add_gen_spot(Vector3(18, 0, 0))           # east hallway
	_add_gen_spot(Vector3(24, 0, -20))         # cafeteria, east of the tables
	_add_gen_spot(Vector3(-8, 0, -44))         # cafeteria, north wall
	_add_gen_spot(Vector3(-24, 0, hall_w + 24))  # behind south classrooms
	_add_gen_spot(Vector3(20, 0, hall_w + 24))   # behind south classrooms
	_add_gen_spot(Vector3(h - 6, 0, 8))        # entrance lobby
	_add_gen_spot(Vector3(-h + 20, 0, -22))    # cafeteria, west aisle

	# ── SECOND FLOOR (platform slab) ──
	# The upper floor is a U-shape: south classrooms + west library + east science lab
	# with a balcony/mezzanine overlooking the cafeteria

	# Floor slab — south half (above classrooms)
	_make_box(Vector3(0, F2 - 0.1, hall_w + 14), Vector3(h * 2 - 8, 0.2, h - hall_w - 4), tile, "tile")
	# Floor slab — balcony along hallway (narrow strip overlooking cafeteria)
	_make_box(Vector3(0, F2 - 0.1, 0), Vector3(h * 2 - 8, 0.2, hall_w * 2 + 2), tile, "tile")
	# Floor slab — library (west upper)
	_make_box(Vector3(-h + 18, F2 - 0.1, -h * 0.5), Vector3(32, 0.2, h - hall_w - 4), tile, "tile")

	# Staircase 1 (east end) — ramp-like solid box
	_make_box(Vector3(h - 10, F2 * 0.5, hall_w + 6), Vector3(6, F2, 4), dark, "concrete")
	# Staircase 2 (west end)
	_make_box(Vector3(-h + 6, F2 * 0.5, hall_w + 6), Vector3(6, F2, 4), dark, "concrete")

	# ── BALCONY GUARDRAILS (with gaps to fall through!) ──
	var rail_h := 1.1
	var rail_y := F2 + rail_h * 0.5
	# North railing (overlooking cafeteria) with 3 gaps
	for seg in [[-h + 6, -h + 20], [-h + 24, -6], [2, h - 20], [h - 16, h - 6]]:
		var sx: float = seg[0]
		var ex: float = seg[1]
		var cx := (sx + ex) * 0.5
		var w := ex - sx
		_make_railing(Vector3(cx, rail_y, -hall_w - 1), Vector3(w, rail_h, 0.15))
	# South railing of balcony (edge of upper hallway)
	_make_railing(Vector3(0, rail_y, hall_w + 1), Vector3(h * 2 - 12, rail_h, 0.15))

	# ── UPPER FLOOR CLASSROOMS (south side) ──
	for i in 4:
		var cx := -h + 15 + i * 20
		var cz := F2 + 0.0
		# Upper classroom dividers
		if i < 3:
			var wx := -h + 25 + i * 20
			_make_box(Vector3(wx, F2 + WALL_HEIGHT * 0.25, hall_w + 14), Vector3(0.3, WALL_HEIGHT * 0.5 - 1, 18), plaster, "concrete")
		# Desks upstairs
		for dx in [-3.0, 3.0]:
			for dz in [-3.5, 0.0, 3.5]:
				_make_desk(Vector3(cx + dx, F2, hall_w + 14 + dz), wood)

	# Library (west upper wing) — bookshelf maze
	var lib_x := -h + 10
	for row in 4:
		for col in 2:
			_make_bookshelf(Vector3(lib_x + col * 6.0, F2, -h * 0.5 + 4 + row * 6.0))

	# Science lab (east upper, past staircase)
	_make_box(Vector3(h - 16, F2 + 0.9, -h * 0.4), Vector3(8, 0.9, 1.4), Color(0.4, 0.4, 0.45), "metal")
	_make_box(Vector3(h - 10, F2 + 0.9, -h * 0.3), Vector3(1.4, 0.9, 6), Color(0.4, 0.4, 0.45), "metal")

	# ── FLUORESCENT LIGHTS (both floors) ──
	# Ground floor
	for gx in range(-40, 44, 14):
		_make_fluorescent(Vector3(gx, WALL_HEIGHT - 1.0, 0))
		_make_fluorescent(Vector3(gx, WALL_HEIGHT - 1.0, hall_w + 14))
		if gx < 20:
			_make_fluorescent(Vector3(gx, WALL_HEIGHT - 1.0, -h * 0.5))
	# Upper floor
	for gx in range(-40, 44, 16):
		_make_fluorescent(Vector3(gx, F2 + WALL_HEIGHT - 1.5, hall_w + 14))
		_make_fluorescent(Vector3(gx, F2 + WALL_HEIGHT - 1.5, 0))

	# ── LORE CLUTTER ──
	_spawn_school_lore(F2)


func _make_cafeteria_table(pos: Vector3, wood: Color) -> void:
	_make_box(pos + Vector3(0, 0.72, 0), Vector3(5.0, 0.08, 1.0), wood, "wood")
	_make_box(pos + Vector3(-1.8, 0.36, 0), Vector3(0.12, 0.72, 0.8), wood.darkened(0.2))
	_make_box(pos + Vector3(1.8, 0.36, 0), Vector3(0.12, 0.72, 0.8), wood.darkened(0.2))
	# Benches on each side
	_make_box(pos + Vector3(0, 0.42, -1.0), Vector3(4.6, 0.06, 0.4), wood.darkened(0.1))
	_make_box(pos + Vector3(0, 0.42, 1.0), Vector3(4.6, 0.06, 0.4), wood.darkened(0.1))


func _make_bookshelf(pos: Vector3) -> void:
	var shelf_col := Color(0.35, 0.25, 0.15)
	_make_box(pos + Vector3(0, 1.4, 0), Vector3(2.0, 2.8, 0.5), shelf_col, "wood")


func _make_railing(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.5, 0.55)
	m.metallic = 0.6
	m.roughness = 0.4
	mi.material_override = m
	body.add_child(mi)


func _spawn_school_lore(floor2_y: float) -> void:
	var h := _half
	# Wall banners (Label3D on walls)
	_make_wall_text(Vector3(-h + 14, 3.5, -4.8), "OAKWOOD OAKIES\nEST. 1956\n'GROW & ACHIEVE'",
		Color(0.2, 0.45, 0.2), Vector3(0, 0, 0))
	_make_wall_text(Vector3(-h + 35, 3.5, -4.8), "SCHOOL EMERGENCY DRILLS\nINFECTION ALERT:\nREPORT ANY SYMPTOMS\nSTAY CALM & MAINTAIN DISTANCE",
		Color(0.85, 0.1, 0.1), Vector3(0, 0, 0))
	_make_wall_text(Vector3(h - 30, 3.5, -10), "OAKWOOD ATHLETICS\nDISTRICT CHAMPIONS\n1999",
		Color(0.15, 0.2, 0.45), Vector3(0, 0, 0))

	# Discarded notes (flat on the floor, rotated randomly)
	var notes := [
		"It's in the air. Everyone who drank\nfrom the fountain started coughing\nup dark bile. Don't touch the water.",
		"Teacher got sick during third period.\nHer eyes went bloodshot. They locked\nus in. We hear her scratching.",
		"Hide the keys. Don't let the gym\ncoach inside. He isn't himself.",
		"Principal acting strange. Same\nannouncement for three hours.\n'the cycle requires grease'",
		"URGENT SAFETY ANNOUNCEMENT:\nRemain indoors. Do not open doors\nfor anyone displaying hyper-aggression.",
		"...evacuation vectors compromised.\nThe infection turns reasoning into\nweaponized obsession...",
		"...get out of the city. This isn't\na lab outbreak. They dug something\nup during the subway expansions.",
	]
	for i in notes.size():
		var nx := _rng.randf_range(-h + 8, h - 8)
		var nz := _rng.randf_range(-h + 8, h - 8)
		var ny := floor2_y if _rng.randf() < 0.3 else 0.02
		_make_floor_note(Vector3(nx, ny, nz), notes[i])

	# Computer terminal screens (admin office + principal's office area)
	_make_terminal(Vector3(h - 18, 1.5, -8),
		"[FILE_72: CONTAINMENT_LOG]\n\n...Protocol Delta initiated...\n...patient zero symptoms accelerated...\n...cognitive deterioration within 12 hours...\n[ERROR: DATA SEGMENT CORRUPTED]\n...must seal facility...")
	_make_terminal(Vector3(-h + 12, floor2_y + 1.5, -h * 0.5 + 6),
		"[EXPERIMENT_NOTES] NEURAL-9922\n\nAGGRESSION CENTER: 140% baseline\nCOGNITIVE SHOCK: Complete regression\nCORTICAL TEST: Zero pain reaction\nSubject driven by hunting directive.")


func _make_wall_text(pos: Vector3, text: String, color: Color, rot: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 42
	l.pixel_size = 0.004
	l.position = pos
	l.rotation = rot
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	l.no_depth_test = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)


func _make_floor_note(pos: Vector3, text: String) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.set_script(load("res://scripts/Interactable.gd"))
	holder.set("title", "DOCUMENT")
	holder.set("body", text)
	add_child(holder)
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.6, 0.005, 0.8)
	paper.mesh = pm
	paper.rotation.y = _rng.randf_range(0, TAU)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.82, 0.72)
	paper.material_override = m
	holder.add_child(paper)
	var l := Label3D.new()
	l.text = text.substr(0, mini(text.length(), 60))
	l.font_size = 16
	l.pixel_size = 0.0016
	l.position = Vector3(0, 0.01, 0)
	l.rotation = Vector3(-PI * 0.5, _rng.randf_range(0, TAU), 0)
	l.modulate = Color(0.2, 0.15, 0.1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.no_depth_test = false
	holder.add_child(l)


func _make_terminal(pos: Vector3, text: String) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.set_script(load("res://scripts/Interactable.gd"))
	holder.set("title", "TERMINAL")
	holder.set("body", text)
	add_child(holder)
	_make_box(pos + Vector3(0, 0.3, 0), Vector3(0.8, 0.6, 0.1), Color(0.12, 0.12, 0.14), "metal")
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.7, 0.45, 0.02)
	screen.mesh = sm
	screen.position = Vector3(0, 0.3, -0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.05, 0.02)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.3, 0.1)
	mat.emission_energy_multiplier = 0.8
	screen.material_override = mat
	holder.add_child(screen)
	var l := Label3D.new()
	l.text = text.substr(0, mini(text.length(), 80))
	l.font_size = 12
	l.pixel_size = 0.001
	l.position = Vector3(0, 0.3, -0.08)
	l.modulate = Color(0.2, 0.9, 0.25)
	l.outline_size = 0
	l.no_depth_test = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(l)


func _make_desk_cluster(pos: Vector3) -> void:
	var wood := Color(0.45, 0.32, 0.18)
	for ix in [-1.6, 1.6]:
		for iz in [-1.8, 1.8]:
			_make_desk(pos + Vector3(ix, 0, iz), wood)


func _make_desk(pos: Vector3, wood: Color) -> void:
	_make_box(pos + Vector3(0, 0.72, 0), Vector3(1.0, 0.08, 0.6), wood, "wood")            # top
	_make_box(pos + Vector3(0, 0.36, -0.2), Vector3(0.85, 0.72, 0.1), wood.darkened(0.25)) # modesty panel
	_make_box(pos + Vector3(0, 0.42, 0.6), Vector3(0.5, 0.06, 0.45), wood.darkened(0.1))   # chair seat
	_make_box(pos + Vector3(0, 0.8, 0.82), Vector3(0.5, 0.55, 0.06), wood.darkened(0.1))   # chair back


func _make_locker_bank(pos: Vector3, along_x: bool) -> void:
	var n := 4
	var lw := 0.72
	var pal: Array = PALETTES[Style.SCHOOL]
	var col: Color = pal[1] if _rng.randf() < 0.5 else pal[2]   # locker blue / red
	for i in n:
		var off := (float(i) - (n - 1) * 0.5) * lw
		var p: Vector3 = pos + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
		var size: Vector3 = Vector3(lw * 0.95, 2.0, 0.5) if along_x else Vector3(0.5, 2.0, lw * 0.95)
		_make_box(p + Vector3(0, 1.0, 0), size, col, "metal")


func _make_chalkboard(pos: Vector3, facing: Vector3) -> void:
	var flat := absf(facing.x) > 0.5
	var frame: Vector3 = Vector3(0.12, 1.7, 3.3) if flat else Vector3(3.3, 1.7, 0.12)
	var board: Vector3 = Vector3(0.1, 1.4, 2.9) if flat else Vector3(2.9, 1.4, 0.1)
	_cosmetic(_box_mesh(frame), pos, Color(0.35, 0.25, 0.15))
	_cosmetic(_box_mesh(board), pos + facing * 0.06, Color(0.10, 0.22, 0.14))


func _make_fluorescent(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(3.0, 0.12, 0.5)
	mi.mesh = bar
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.95, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.82, 0.9, 1.0)
	m.emission_energy_multiplier = 1.6
	mi.material_override = m
	add_child(mi)
	var o := OmniLight3D.new()
	o.light_color = Color(0.82, 0.9, 1.0)
	o.light_energy = 1.5
	o.omni_range = 20.0
	o.position = pos
	add_child(o)


## Cave: a rocky cavern of boulders, stalagmites/stalactites and glowing crystals.
const CAVE_ROCKS := [
	FP + "/Rocks/Rock1.fbx", FP + "/Rocks/Rock2.fbx", FP + "/Rocks/Rock3.fbx",
	FP + "/Rocks/Rock4.fbx", FP + "/Rocks/Rock5.fbx",
	FP + "/Rocks/BigRock1.fbx", FP + "/Rocks/BigRock2.fbx", FP + "/Rocks/BigRock3.fbx",
	FP + "/Rocks/BigRock4.fbx", FP + "/Rocks/BigRock5.fbx",
]

func _build_cave_layout() -> void:
	var rock := Color(0.32, 0.32, 0.36)
	var placed := 0
	var attempts := 0
	var used: Array[Vector3] = []
	while placed < 65 and attempts < 1200:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-_half + 5, _half - 5), 0,
				_rng.randf_range(-_half + 5, _half - 5))
		if pos.length() < CENTER_CLEAR:
			continue
		var too_close := false
		for u in used:
			if u.distance_to(pos) < 4.5:
				too_close = true
				break
		if too_close:
			continue
		used.append(pos)
		var r := _rng.randf()
		if r < 0.35:
			var m := _spawn_model(_pick(CAVE_ROCKS), pos, _rng.randf_range(2.5, 7.0), rock, 0.45)
			if m == null:
				_make_stalagmite(pos, rock)
		elif r < 0.60:
			_make_stalagmite(pos, rock)
		elif r < 0.80:
			_make_crystal(pos)
		else:
			_make_cave_rubble(pos, rock)
		placed += 1

	for i in 30:
		_make_stalactite(Vector3(_rng.randf_range(-_half + 5, _half - 5), 0,
				_rng.randf_range(-_half + 5, _half - 5)), rock)

	for i in 3:
		var wp := Vector3(_rng.randf_range(-_half + 12, _half - 12), 0,
				_rng.randf_range(-_half + 12, _half - 12))
		if wp.length() > CENTER_CLEAR:
			_make_cave_pool(wp)

	# Curated generator spots ringed around the cavern floor, clear of the
	# central arena and the walls. Rocks that land on one are skipped at spawn.
	var gr := _half * 0.5   # ~26 m ring
	for a in 8:
		var ang := TAU * a / 8.0
		_add_gen_spot(Vector3(cos(ang) * gr, 0, sin(ang) * gr))

	# Cave art mural on one wall — crude charcoal drawings
	_make_wall_text(Vector3(-_half + 2.5, 3.5, _rng.randf_range(-10, 10)),
		"  /\\    /\\\n /  \\  /  \\\n/    \\/    \\\n  |||||||||\n  | O  O |\n   \\||||/\n    \\||/\n  ~~~~~~~\n  /|\\  /|\\ /|\\\n   |    |    |",
		Color(0.45, 0.12, 0.08), Vector3(0, PI * 0.5, 0))
	_make_wall_text(Vector3(_half - 2.5, 2.0, _rng.randf_range(-6, 6)),
		"THEY DIG. THEY FIND.\nIT CHANGES YOUR HEAD.\nTHE CYCLE REQUIRES GREASE.",
		Color(0.4, 0.1, 0.06), Vector3(0, -PI * 0.5, 0))


func _make_stalagmite(pos: Vector3, col: Color) -> void:
	var h := _rng.randf_range(2.0, 5.0)
	var r := _rng.randf_range(0.4, 0.9)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	add_child(body)
	var shape := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r * 0.6
	cy.height = h
	shape.shape = cy
	shape.position = Vector3(0, h * 0.5, 0)
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = r
	cone.height = h
	mi.mesh = cone
	mi.position = Vector3(0, h * 0.5, 0)
	mi.material_override = _mat(col, "rock")
	body.add_child(mi)


func _make_stalactite(pos: Vector3, col: Color) -> void:
	var h := _rng.randf_range(1.5, 3.5)
	var r := _rng.randf_range(0.3, 0.7)
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = r
	cone.bottom_radius = 0.03
	cone.height = h
	mi.mesh = cone
	mi.position = Vector3(pos.x, WALL_HEIGHT - h * 0.5, pos.z)
	mi.material_override = _mat(col, "rock")
	add_child(mi)


func _make_crystal(pos: Vector3) -> void:
	var col := Color(0.3, 0.7, 0.95) if _rng.randf() < 0.6 else Color(0.7, 0.4, 0.95)
	for i in _rng.randi_range(3, 5):
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var s := _rng.randf_range(0.4, 1.1)
		pm.size = Vector3(s * 0.4, s * 1.7, s * 0.4)
		mi.mesh = pm
		mi.position = pos + Vector3(_rng.randf_range(-0.5, 0.5), s * 0.85, _rng.randf_range(-0.5, 0.5))
		mi.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0, TAU), _rng.randf_range(-0.3, 0.3))
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.6
		mi.material_override = m
		add_child(mi)
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = 1.7
	o.omni_range = 15.0
	o.position = pos + Vector3(0, 1.0, 0)
	add_child(o)


func _make_cave_rubble(pos: Vector3, col: Color) -> void:
	for i in _rng.randi_range(3, 6):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := _rng.randf_range(0.3, 1.2)
		bm.size = Vector3(s, s * 0.6, s * 0.8)
		mi.mesh = bm
		mi.position = pos + Vector3(_rng.randf_range(-1.0, 1.0), s * 0.3,
				_rng.randf_range(-1.0, 1.0))
		mi.rotation = Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0, TAU),
				_rng.randf_range(-0.2, 0.2))
		mi.material_override = _mat(col.darkened(_rng.randf_range(0.0, 0.2)), "rock")
		add_child(mi)


func _make_cave_pool(pos: Vector3) -> void:
	var r := _rng.randf_range(3.0, 6.0)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 0.9
	cm.height = 0.06
	mi.mesh = cm
	mi.position = Vector3(pos.x, 0.02, pos.z)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.14, 0.22, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.7
	m.roughness = 0.1
	m.emission_enabled = true
	m.emission = Color(0.05, 0.10, 0.18)
	m.emission_energy_multiplier = 0.4
	mi.material_override = m
	add_child(mi)


func _build_lab_layout() -> void:
	# ── Resident-Evil-style research lab: tight corridors, small clinical rooms,
	# dim flickering fluorescents. Plan (footprint half = 46):
	#   corridor A (E-W) at z ≈ -15.5 · corridor B (E-W) at z ≈ +15.5
	#   corridor C (N-S spine) at x = 0 — its south end is the entry checkpoint.
	#   NW specimen storage · NE containment cells · W main lab floor
	#   E server room + operating theater · SW offices/break room · SE morgue.
	var h := _half
	var gray := Color(0.60, 0.62, 0.65)
	var steel := Color(0.45, 0.48, 0.52)

	var an := -18.0    # corridor A north wall
	var asw := -13.0   # corridor A south wall
	var bn := 13.0     # corridor B north wall
	var bsw := 18.0    # corridor B south wall
	var cw := -2.5     # corridor C west wall
	var ce := 2.5      # corridor C east wall

	# ── CORRIDOR A walls (every doorway gap becomes a dynamic-door spot) ──
	_plan_wall_z(an, -h + 2, cw, [[-24.0, true]], gray, "tile")                       # specimen storage
	_plan_wall_z(an, ce, h - 2, [[9.5, false], [24.0, true], [38.5, true]], gray, "tile")  # cells
	_plan_wall_z(asw, -h + 2, cw, [[-24.0, true]], gray, "tile")                      # main lab (N)
	_plan_wall_z(asw, ce, h - 2, [[13.0, true], [35.0, true]], gray, "tile")          # server / theater

	# ── CORRIDOR B walls ──
	_plan_wall_z(bn, -h + 2, cw, [[-24.0, false]], gray, "tile")                      # main lab (S)
	_plan_wall_z(bn, ce, h - 2, [[13.0, true], [35.0, false]], gray, "tile")
	_plan_wall_z(bsw, -h + 2, cw, [[-35.0, false], [-13.0, true]], gray, "tile")      # office / break room
	_plan_wall_z(bsw, ce, h - 2, [[24.0, true], [38.5, false]], gray, "tile")         # morgue doors

	# ── CORRIDOR C spine walls (open where corridors A/B cross) ──
	_plan_wall_x(cw, -h + 2, an, [[-32.0, false]], gray, "tile")                      # specimen (E door)
	_plan_wall_x(cw, asw, bn, [[0.0, false]], gray, "tile")                           # main lab (E door)
	_plan_wall_x(cw, bsw, h - 2, [[32.0, false]], gray, "tile")                       # break room (E door)
	_plan_wall_x(ce, asw, bn, [[0.0, false]], gray, "tile")                           # server (W door)
	_plan_wall_x(ce, bsw, h - 2, [[26.0, true]], gray, "tile")                        # morgue (W door)
	# Cell 1's spine wall is BREACHED — something got out. Rubble, not a door.
	_lab_wall_x(ce, -h + 2, -33.0, gray)
	_lab_wall_x(ce, -27.0, an, gray)
	_make_cave_rubble(Vector3(ce + 1.5, 0, -30.0), gray.darkened(0.3))
	_make_blood_streak(Vector3(0.0, 0, -30.0), Vector3(-1, 0, 0.2), 7.0)

	# ── Room dividers ──
	_lab_wall_x(17.0, -h + 2, an, gray)                              # cell 1 | cell 2
	_lab_wall_x(31.5, -h + 2, an, gray)                              # cell 2 | cell 3
	_plan_wall_x(24.0, asw, bn, [[0.0, true]], gray, "tile")         # server ↔ theater
	_plan_wall_x(-24.0, bsw, h - 2, [[32.0, true]], gray, "tile")    # office ↔ break room

	# ═══ NW: SPECIMEN STORAGE ═══
	for row in 3:
		_make_specimen_shelf(Vector3(-38.0 + row * 11.0, 0, -38.0), false)
		_make_specimen_shelf(Vector3(-38.0 + row * 11.0, 0, -27.0), false)
	_make_containment_cylinder(Vector3(-8.0, 0, -40.0), false)
	_make_containment_cylinder(Vector3(-8.0, 0, -25.0), true)
	_make_wall_text(Vector3(-24.0, 3.4, -h + 2.6), "SPECIMEN STORAGE — KEEP SEALED",
		Color(0.55, 0.7, 0.75), Vector3.ZERO)
	_make_floor_note(Vector3(-30.0, 0.02, -33.0),
		"Inventory note: jars 40-61 moved to\ncold storage. Jar 62 was EMPTY when\nI got here. Nobody signed it out.")
	_add_gen_spot(Vector3(-20.0, 0, -40.0))

	# ═══ NE: CONTAINMENT CELLS ═══
	for cell in 3:
		var cell_x := 9.75 + cell * 14.5
		_make_box(Vector3(cell_x + 3.5, 0.35, -41.0), Vector3(2.4, 0.7, 1.1), Color(0.35, 0.36, 0.4), "metal")
		_make_box(Vector3(cell_x - 3.0, 0.5, -40.0), Vector3(1.0, 1.0, 1.0), Color(0.3, 0.31, 0.34), "metal")
	# Cell 1: breached — shattered tank, corpse, gore trail into the spine.
	_make_containment_cylinder(Vector3(9.5, 0, -33.0), true)
	_make_corpse_prop(Vector3(12.0, 0, -38.0))
	_make_blood_splatter(Vector3(16.7, 2.0, -35.0), true)
	_make_wall_text(Vector3(24.0, 3.4, an + 0.8), "CONTAINMENT — AUTHORIZED PERSONNEL ONLY",
		Color(0.85, 0.10, 0.10), Vector3.ZERO)
	var warn: OmniLight3D = FLICKER_SCRIPT.new()
	warn.light_color = Color(0.9, 0.08, 0.05)
	warn.light_energy = 1.5
	warn.omni_range = 18.0
	warn.position = Vector3(24.0, 6.0, -30.0)
	add_child(warn)

	# ═══ W: MAIN LAB FLOOR ═══
	for row in 2:
		var bench_z := -6.0 + row * 12.0
		_make_lab_bench(Vector3(-33.0, 0, bench_z))
		_make_lab_bench(Vector3(-15.0, 0, bench_z))
	_make_operating_table(Vector3(-24.0, 0, 0.0), true)
	_make_surgical_light(Vector3(-24.0, WALL_HEIGHT * 0.5 - 1.2, 0.0))
	_make_terminal(Vector3(-42.0, 1.5, -6.0),
		"LAB FLOOR — SAMPLE LOG\n\nSubject response: aggressive\nCognitive decline: rapid\nViral load: increasing\nRecommendation: SEAL ROOM")
	_make_puddle(Vector3(-20.0, 0.01, 5.0), 1.2, Color(0.5, 0.06, 0.03, 0.7))
	_add_gen_spot(Vector3(-40.0, 0, 8.0))

	# ═══ E: SERVER ROOM ═══
	for row in 3:
		_make_server_rack(Vector3(8.0, 0, -8.0 + row * 8.0), false)
		_make_server_rack(Vector3(15.0, 0, -8.0 + row * 8.0), false)
	_make_terminal(Vector3(20.0, 1.5, -10.0),
		"[FILE_72: CONTAINMENT_LOG]\n\n...Protocol Delta initiated...\n...patient zero accelerated...\n...cognitive deterioration 12 hours...\n[ERROR: DATA SEGMENT CORRUPTED]\n...must seal facility...")
	_add_gen_spot(Vector3(11.5, 0, 9.5))

	# ═══ E: OPERATING THEATER ═══
	_make_operating_table(Vector3(31.0, 0, -4.0), true)
	_make_operating_table(Vector3(38.0, 0, 4.0), false)
	_make_surgical_light(Vector3(31.0, WALL_HEIGHT * 0.5 - 1.2, -4.0))
	_make_box(Vector3(43.0, 0.5, 0.0), Vector3(0.9, 1.0, 3.0), steel, "metal")
	_make_puddle(Vector3(33.0, 0.01, -1.0), 1.6, Color(0.45, 0.03, 0.02, 0.8))
	_make_blood_streak(Vector3(35.0, 0, 8.0), Vector3(0.2, 0, 1), 6.0)
	_make_wall_text(Vector3(h - 2.6, 2.8, 0.0),
		"CYTOPATHIC EFFECTS (CPE)\n\nSyncytia Formation\nCell Lysis via Over-Replication",
		Color(0.45, 0.1, 0.1), Vector3(0, -PI * 0.5, 0))
	_add_gen_spot(Vector3(35.0, 0, 9.0))

	# ═══ SW: OFFICES ═══
	for dx in [-40.0, -34.0]:
		for dz in [26.0, 34.0]:
			_make_desk(Vector3(dx, 0, dz), Color(0.4, 0.3, 0.2))
	_make_box(Vector3(-43.5, 1.0, 42.0), Vector3(1.0, 2.0, 3.0), Color(0.35, 0.37, 0.4), "metal")
	_make_terminal(Vector3(-40.0, 1.5, 42.0),
		"[EXPERIMENT_NOTES] NEURAL-9922\n\nAGGRESSION CENTER: 140% baseline\nCOGNITIVE SHOCK: Full regression\nSubject driven entirely by\nhunting directive.")
	_add_gen_spot(Vector3(-30.0, 0, 42.0))

	# ═══ SW: BREAK ROOM ═══
	_make_cafeteria_table(Vector3(-16.0, 0, 28.0), Color(0.78, 0.78, 0.80))
	_make_cafeteria_table(Vector3(-16.0, 0, 38.0), Color(0.78, 0.78, 0.80))
	_make_vending_machine(Vector3(-6.0, 0, 43.5))
	_make_locker_bank(Vector3(-10.0, 0, bsw + 1.2), true)
	_make_table_body(Vector3(-16.0, 0, 33.0))
	_add_gen_spot(Vector3(-8.0, 0, 30.0))

	# ═══ SE: MORGUE ═══
	_make_morgue_drawers(Vector3(24.0, 0, h - 3.4))
	_make_gurney(Vector3(14.0, 0, 30.0), true)
	_make_gurney(Vector3(30.0, 0, 26.0), false)
	_make_gurney(Vector3(38.0, 0, 34.0), true)
	_make_wall_text(Vector3(24.0, 3.2, bsw + 0.8), "MORGUE — CAPACITY EXCEEDED",
		Color(0.6, 0.62, 0.68), Vector3.ZERO)
	_make_puddle(Vector3(20.0, 0.01, 34.0), 1.1, Color(0.42, 0.03, 0.02, 0.75))
	_add_gen_spot(Vector3(36.0, 0, 24.0))

	# ═══ S: ENTRY SECURITY CHECKPOINT (corridor C, south end) ═══
	_make_security_arch(Vector3(0.0, 0, 30.0))
	_make_box(Vector3(-1.6, 0.55, 38.0), Vector3(1.6, 1.1, 3.0), steel, "metal")
	_make_terminal(Vector3(-1.6, 1.45, 38.0),
		"SECURITY TERMINAL\n\nLOCKDOWN: ACTIVE\nEXITS: SEALED\nBADGE READER: OFFLINE\n\nlast entry 03:14 — DR. PRICE")
	_make_wall_text(Vector3(0.0, 3.6, h - 2.6), "SECURITY CHECKPOINT\nBIOHAZARD LEVEL 4",
		Color(0.85, 0.65, 0.1), Vector3(0, PI, 0))
	_add_gen_spot(Vector3(0.0, 0, 24.0))

	# ── Corridor dressing: bodies where they fell, blood on the walls ──
	_make_corpse_prop(Vector3(-33.0, 0, -15.5))
	_make_corpse_prop(Vector3(20.0, 0, 15.5))
	_make_blood_streak(Vector3(-10.0, 0, -15.5), Vector3(1, 0, 0), 9.0)
	for i in 8:
		_make_blood_splat(Vector3(_rng.randf_range(-h + 6, h - 6),
			_rng.randf_range(0.5, 2.5), _rng.randf_range(-h + 6, h - 6)))

	# ── Flickering fluorescent strips: corridors + one per room. The rest is dark. ──
	for fx in [-32.0, 0.0, 32.0]:
		_make_fluorescent_flicker(Vector3(fx, WALL_HEIGHT * 0.5 - 0.6, -15.5))
		_make_fluorescent_flicker(Vector3(fx, WALL_HEIGHT * 0.5 - 0.6, 15.5))
	for fz in [-32.0, 32.0]:
		_make_fluorescent_flicker(Vector3(0.0, WALL_HEIGHT * 0.5 - 0.6, fz))
	for room_pos in [Vector3(-24, 0, -32), Vector3(24, 0, -32), Vector3(-24, 0, 0),
			Vector3(13, 0, 0), Vector3(35, 0, 0), Vector3(-35, 0, 32),
			Vector3(-13, 0, 32), Vector3(24, 0, 32)]:
		_make_fluorescent_flicker(Vector3(room_pos.x, WALL_HEIGHT * 0.5 - 0.6, room_pos.z))

	_spawn_lab_lore()


## Build a wall segment along Z at a fixed x position, from z0 to z1.
func _lab_wall_z(z: float, x0: float, x1: float, col: Color) -> void:
	if x1 <= x0:
		return
	var cx := (x0 + x1) * 0.5
	var w := x1 - x0
	_make_box(Vector3(cx, WALL_HEIGHT * 0.25, z), Vector3(w, WALL_HEIGHT * 0.5, 0.4), col)


## Build a wall segment along X at a fixed x position, from z0 to z1.
func _lab_wall_x(x: float, z0: float, z1: float, col: Color) -> void:
	if z1 <= z0:
		return
	var cz := (z0 + z1) * 0.5
	var d := z1 - z0
	_make_box(Vector3(x, WALL_HEIGHT * 0.25, cz), Vector3(0.4, WALL_HEIGHT * 0.5, d), col)


## A clean, brightly-lit white box room for parkour. The course (built by
## ParkourCourse) floats inside at y~18; the red floor below is the kill zone.
func _build_parkour_void() -> void:
	var h := _half          # 58
	var room_h := 44.0      # tall enough to enclose the floating course
	var white := Color(0.95, 0.95, 0.97)

	# Bright, flat, even environment — no fog, no horror.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.97, 0.97, 0.99)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.95, 1.0)
	env.ambient_light_energy = 1.0
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Red kill FLOOR (falling onto it = death). Glowing red, unmistakable.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	add_child(floor_body)
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(h * 2, 1, h * 2)
	fshape.shape = fbox
	fshape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fshape)
	var fmi := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(h * 2, 1, h * 2)
	fmi.mesh = fmesh
	fmi.position = Vector3(0, -0.5, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.7, 0.05, 0.05)
	fmat.emission_enabled = true
	fmat.emission = Color(0.6, 0.03, 0.03)
	fmat.emission_energy_multiplier = 0.6
	fmi.material_override = fmat
	floor_body.add_child(fmi)

	# Clean matte-white walls + ceiling (no texture — a true white void).
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = white
	wall_mat.roughness = 0.95
	var specs := [
		[Vector3(0, room_h * 0.5, -h), Vector3(h * 2, room_h, 0.6)],
		[Vector3(0, room_h * 0.5, h), Vector3(h * 2, room_h, 0.6)],
		[Vector3(-h, room_h * 0.5, 0), Vector3(0.6, room_h, h * 2)],
		[Vector3(h, room_h * 0.5, 0), Vector3(0.6, room_h, h * 2)],
	]
	for s in specs:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = s[0]
		add_child(body)
		var shp := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = s[1]
		shp.shape = bx
		body.add_child(shp)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s[1]
		mi.mesh = bm
		mi.material_override = wall_mat
		body.add_child(mi)
	# White ceiling.
	var ceil_mi := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(h * 2, 0.6, h * 2)
	ceil_mi.mesh = cmesh
	ceil_mi.position = Vector3(0, room_h, 0)
	ceil_mi.material_override = wall_mat
	add_child(ceil_mi)

	# Even white lighting from above.
	for gx in [-h * 0.5, h * 0.5]:
		for gz in [-h * 0.5, h * 0.5]:
			var o := OmniLight3D.new()
			o.light_color = Color(1, 1, 1)
			o.light_energy = 2.2
			o.omni_range = h * 1.4
			o.position = Vector3(gx, room_h - 4, gz)
			add_child(o)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 1, 1)
	sun.light_energy = 0.8
	sun.rotation = Vector3(deg_to_rad(-70), deg_to_rad(30), 0)
	add_child(sun)


func _make_test_tube(pos: Vector3, broken: bool) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	cm.height = 0.3
	mi.mesh = cm
	mi.position = pos + Vector3(0, 0.15, 0)
	if broken:
		mi.rotation = Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.6, 0.6))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.9, 0.95, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	add_child(mi)


func _make_puddle(pos: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 0.85
	cm.height = 0.02
	mi.mesh = cm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.3
	m.roughness = 0.2
	mi.material_override = m
	add_child(mi)


func _make_containment_cylinder(pos: Vector3, broken: bool) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.8
	cm.bottom_radius = 0.8
	cm.height = 3.0
	mi.mesh = cm
	mi.position = pos + Vector3(0, 1.5, 0)
	var m := StandardMaterial3D.new()
	if broken:
		m.albedo_color = Color(0.7, 0.75, 0.8, 0.25)
	else:
		m.albedo_color = Color(0.8, 0.85, 0.9, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.2
	m.roughness = 0.1
	mi.material_override = m
	add_child(mi)
	# Base ring
	_make_box(pos + Vector3(0, 0.15, 0), Vector3(2.0, 0.3, 2.0), Color(0.4, 0.42, 0.45), "metal")
	if broken:
		# Broken glass on floor + red liquid spill
		_make_puddle(pos + Vector3(1.2, 0.01, 0.6), 1.8, Color(0.55, 0.04, 0.02, 0.75))
		_make_puddle(pos + Vector3(-0.5, 0.01, 1.0), 1.0, Color(0.5, 0.06, 0.03, 0.6))
		# Glass shards
		for i in 5:
			var shard := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.15, 0.02, 0.08)
			shard.mesh = bm
			shard.position = pos + Vector3(_rng.randf_range(-1.5, 1.5), 0.02,
					_rng.randf_range(-1.0, 1.5))
			shard.rotation.y = _rng.randf_range(0, TAU)
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.8, 0.85, 0.9, 0.5)
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			shard.material_override = sm
			add_child(shard)


func _make_corpse_prop(pos: Vector3) -> void:
	var skin := Color(0.52, 0.42, 0.36).darkened(_rng.randf_range(0.0, 0.25))
	var cloth := Color(0.3, 0.28, 0.25).darkened(_rng.randf_range(0.0, 0.15))
	var rot_y := _rng.randf_range(0, TAU)
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	add_child(root)
	# Torso (capsule lying flat)
	var torso := MeshInstance3D.new()
	var tc := CapsuleMesh.new()
	tc.radius = 0.22
	tc.height = 1.0
	torso.mesh = tc
	torso.position = Vector3(0, 0.22, 0)
	torso.rotation.z = PI * 0.5
	torso.material_override = _mat(cloth)
	root.add_child(torso)
	# Head
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.16
	head.mesh = hm
	head.position = Vector3(-0.6, 0.18, 0)
	head.material_override = _mat(skin)
	root.add_child(head)
	# Legs (two capsules)
	for side in [-0.12, 0.12]:
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.1
		lm.height = 0.8
		leg.mesh = lm
		leg.position = Vector3(0.6, 0.12, side)
		leg.rotation.z = PI * 0.5
		leg.material_override = _mat(cloth.darkened(0.1))
		root.add_child(leg)
	# Arm (one draped out)
	var arm := MeshInstance3D.new()
	var am := CapsuleMesh.new()
	am.radius = 0.07
	am.height = 0.6
	arm.mesh = am
	arm.position = Vector3(-0.1, 0.12, 0.35)
	arm.rotation.z = PI * 0.4
	arm.material_override = _mat(skin)
	root.add_child(arm)
	# Blood pool
	_make_puddle(pos + Vector3(_rng.randf_range(-0.4, 0.4), 0.005,
		_rng.randf_range(-0.3, 0.3)), _rng.randf_range(0.8, 1.6),
		Color(0.4, 0.02, 0.01, 0.8))


func _make_table_body(pos: Vector3) -> void:
	# A cafeteria table with a partially consumed body on it
	_make_cafeteria_table(pos, Color(0.82, 0.82, 0.84))
	var skin := Color(0.48, 0.38, 0.33)
	var cloth := Color(0.35, 0.32, 0.28)
	var ty := 0.78  # table surface height
	# Torso on table
	var torso := MeshInstance3D.new()
	var tc := CapsuleMesh.new()
	tc.radius = 0.25
	tc.height = 1.1
	torso.mesh = tc
	torso.position = pos + Vector3(0, ty + 0.25, 0)
	torso.rotation.z = PI * 0.5
	torso.material_override = _mat(cloth)
	add_child(torso)
	# Head
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.17
	head.mesh = hm
	head.position = pos + Vector3(-0.65, ty + 0.22, 0)
	head.material_override = _mat(skin)
	add_child(head)
	# Arm hanging off table
	var arm := MeshInstance3D.new()
	var am := CapsuleMesh.new()
	am.radius = 0.08
	am.height = 0.65
	arm.mesh = am
	arm.position = pos + Vector3(0.2, ty - 0.1, 0.55)
	arm.rotation = Vector3(0.3, 0, 0.8)
	arm.material_override = _mat(skin)
	add_child(arm)
	# Blood on table + dripping to floor
	_make_puddle(pos + Vector3(0.1, ty + 0.02, 0), 0.9, Color(0.45, 0.02, 0.01, 0.85))
	_make_puddle(pos + Vector3(0.3, ty + 0.02, -0.3), 0.5, Color(0.4, 0.03, 0.01, 0.75))
	_make_puddle(pos + Vector3(0.5, 0.01, 0.6), 0.7, Color(0.35, 0.02, 0.01, 0.7))


func _make_blood_splat(pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = "█▓▒░"
	l.font_size = _rng.randi_range(24, 48)
	l.pixel_size = 0.006
	l.position = pos
	l.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0, TAU), _rng.randf_range(-0.3, 0.3))
	l.modulate = Color(0.45, 0.04, 0.02, _rng.randf_range(0.4, 0.8))
	l.no_depth_test = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(l)


func _make_fluorescent_lab(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(3.2, 0.08, 0.5)
	mi.mesh = bar
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.98, 0.98, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.95, 0.97, 1.0)
	m.emission_energy_multiplier = 2.5
	mi.material_override = m
	add_child(mi)
	var o := OmniLight3D.new()
	o.light_color = Color(0.95, 0.97, 1.0)
	o.light_energy = 2.8
	o.omni_range = 18.0
	o.position = pos
	add_child(o)


func _spawn_lab_lore() -> void:
	var h := _half
	var memos := [
		"MEMO 1: INITIAL OUTBREAK\nDr. Mitchell -> Dr. Crawford\nMarch 14, 2024\n\nThree patients. Aggressive outbursts.\nHigh fever, rapid onset. They attacked\nstaff unprovoked. Sedation didn't help.",
		"MEMO 2: LAB NOTE\nDr. Price -> Self\nMarch 16, 2024\n\nUnknown viral agent in bloodwork.\nAttacking the frontal lobe.\nBehavioral inhibition shutting down.",
		"MEMO 6: VIRUS CLASSIFICATION\nDr. Price -> CDC\nMarch 20, 2024\n\nNeurovirus Type-7. Rewires aggression\ncenters. Pure instinct. No cure.\nAirborne possible but unconfirmed.",
		"MEMO 10: TRANSMISSION THEORY\nDr. Price -> Research Team\nMarch 23, 2024\n\nViral particles in saliva and blood.\nInfected attack uninfected.\nEvolution doesn't explain this.\nSomeone designed this.",
		"MEMO 13: RESEARCH FAILURE\nDr. Price -> Project File\nMarch 25, 2024\n\nEvery test subject dies or turns.\nNo middle ground. The virus doesn't\nkill--it transforms. No going back.",
		"MEMO 15: HUNTER'S MANIFESTO\nSubject 23 (Infected)\nMarch 26, 2024\n\nTHEY RUN THEY HIDE THEY SCREAM\nWE FIND WE TAKE WE BURN\nBURNING BURNING BURNING\nWHAT IS THIS THING IN MY HEAD",
		"MEMO 19: FINAL ENTRY\nDr. Price -> History\nMarch 29, 2024\n\nThis wasn't nature. The viral\nstructure is too perfect, too\ndesigned. Someone made this.\nSomeone wanted this to happen.",
	]
	# Floor notes
	for i in memos.size():
		var nx := _rng.randf_range(-h + 8, h - 8)
		var nz := _rng.randf_range(-h + 8, h - 8)
		_make_floor_note(Vector3(nx, 0.02, nz), memos[i])
	# Extra short notes (survival, personal)
	var short_notes := [
		"I'm hiding in the library.\nIf you get this, know that\nI tried to stay safe.\n- David",
		"EVACUATION CANCELLED.\nNo one leaves. Stay put.\nHelp is coming.\n(it's not coming)",
		"They hunt at night.\nStay quiet. Stay hidden.\nIf you see blood, run.",
		"47 confirmed infected.\nWe lost the east wing.\nThey're not mindless.\nThey're just angry.",
		"Don't try to save anyone.\nYou'll get yourself killed.\nI'm sorry.",
	]
	for note in short_notes:
		var nx := _rng.randf_range(-h + 6, h - 6)
		var nz := _rng.randf_range(-h + 6, h - 6)
		_make_floor_note(Vector3(nx, 0.02, nz), note)

	# Computer terminals
	_make_terminal(Vector3(8, 1.5, h * 0.5),
		"[FILE_72: CONTAINMENT_LOG]\n\n...Protocol Delta initiated...\n...Site 4-B status unknown...\n...patient zero symptoms accelerated...\n...cognitive deterioration 12 hours...\n[ERROR: DATA SEGMENT CORRUPTED]\n...must seal facility immediately...")
	_make_terminal(Vector3(20, 1.5, h * 0.5),
		"[EXPERIMENT_NOTES] NEURAL-9922\n\nAGGRESSION CENTER: 140% baseline\nCOGNITIVE SHOCK: Complete regression\nCOGNITIVE BLOCK: Frontal lobe suppressed\nReplaced by foreign autonomic pulses\nSubject driven by hunting directive.\n\nDIAGNOSTIC: Zero pain reaction.")
	# Graffiti on wall
	_make_wall_text(Vector3(h - 2.5, 2.0, 8),
		"They're not people anymore.\nThe virus took that.\nWhat's left is hunger and rage.\nIf you're reading this,\nyou're next.",
		Color(0.5, 0.06, 0.02), Vector3(0, -PI * 0.5, 0))


func _build_random_obstacles() -> void:
	var placed := 0
	var attempts := 0
	var used: Array[Vector3] = []
	while placed < OBSTACLE_COUNT and attempts < 900:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-HALF + 9, HALF - 9), 0,
				_rng.randf_range(-HALF + 9, HALF - 9))
		if pos.length() < CENTER_CLEAR:
			continue
		var too_close := false
		for u in used:
			if u.distance_to(pos) < SPACING:
				too_close = true
				break
		if too_close:
			continue
		used.append(pos)
		_make_structure(pos)
		placed += 1


## Factory: a fully-enclosed TWO-STOREY industrial building.
##
## A mezzanine floor rings a central open atrium (so you can see — and fall —
## between levels), reached by four ramps. The ground floor holds machines,
## shelf rows and conveyors; both levels are threaded with walk-through vent
## ducts and doored rooms. Exterior walls + ceiling (built earlier) seal it off.
const FACTORY_FLOOR_H := 6.5      # mezzanine walkable height
const FACTORY_ATRIUM  := 30.0     # half-size of the central open void
const FACTORY_STEEL   := Color(0.34, 0.35, 0.40)
const FACTORY_DARK    := Color(0.17, 0.18, 0.21)

func _build_factory_layout() -> void:
	var fh := FACTORY_FLOOR_H
	var inner := _half - 4.0
	var mez_depth := 14.0
	var mez_z := _half - 4.0 - mez_depth * 0.5    # north mezzanine centre
	var mez_front := mez_z - mez_depth * 0.5      # its south edge

	# ── Mezzanine office gantry along the north wall, reached by one ramp ──
	_make_slab(Vector3(0, fh, mez_z), Vector2(inner * 2.0, mez_depth))
	_make_railing_gapped(Vector3(0, fh, mez_front), true, inner * 2.0, 11.0)
	var run := 13.0
	_make_ramp(Vector3(0, 0, mez_front - run), Vector3(0, 0, 1), fh, run, 9.0)
	for ox in [-inner * 0.55, 0.0, inner * 0.55]:
		_make_large_machine(Vector3(ox, fh, mez_z))   # control consoles up top
	_add_ceiling_light(Vector3(0, WALL_HEIGHT - 1.5, mez_z))

	# ── Ground floor: parallel shelving rows with walkable aisles ──
	var rack_depth := 4.0
	var aisle := 7.0
	var z_step := rack_depth + aisle
	var rowlen := inner * 1.7
	var z := -inner + 14.0
	while z < mez_front - 18.0:
		var x := -rowlen * 0.5
		while x < rowlen * 0.5 - 3.0:
			var seg := _rng.randf_range(4.0, 6.0)
			_make_shelf_rack(Vector3(x + seg * 0.5, 0, z))
			x += seg + _rng.randf_range(1.5, 3.0)
		# A crate stack or barrels parked in the aisle behind the row.
		var ax := _rng.randf_range(-rowlen * 0.4, rowlen * 0.4)
		if _rng.randf() < 0.6:
			_make_crate_stack(Vector3(ax, 0, z + aisle * 0.5))
		else:
			_spawn_model(DUN + "/Barrel.obj", Vector3(ax, 0, z + aisle * 0.5), 1.7, Color(1, 1, 1), 0.4)
		z += z_step

	# ── Machine line + conveyor along the south wall ──
	for i in 4:
		var mx := lerpf(-inner + 6.0, inner - 6.0, float(i) / 3.0)
		_make_large_machine(Vector3(mx, 0, -inner + 5.0))
	_make_conveyor_belt(Vector3(0, 0, -inner + 9.0))

	# ── Corner silos + scattered crates/barrels for density ──
	for cx in [-inner + 7.0, inner - 7.0]:
		for cz in [-inner + 7.0, inner - 7.0]:
			if _rng.randf() < 0.7:
				_make_silo(Vector3(cx, 0, cz))
	for i in 6:
		var p := Vector3(_rng.randf_range(-inner + 6, inner - 6), 0,
				_rng.randf_range(-inner + 6, mez_front - 6))
		if _rng.randf() < 0.5:
			_make_crate_stack(p)
		else:
			_spawn_model(DUN + "/Crate.obj", p, 1.6, Color(1, 1, 1), 0.4)

	# ── Ceiling lights ──
	for gx in [-inner * 0.6, -inner * 0.2, inner * 0.2, inner * 0.6]:
		for gz in [-inner * 0.6, -inner * 0.2, inner * 0.2, inner * 0.6]:
			_add_ceiling_light(Vector3(gx, WALL_HEIGHT - 1.5, gz))

	# Curated generator spots in the walkable aisles between shelf rows and on the
	# open ground-floor edges. Racks/crates that overlap one are skipped at spawn.
	for az in [-28.5, -6.5, 4.5]:
		_add_gen_spot(Vector3(-inner + 10.0, 0, az))
		_add_gen_spot(Vector3(inner - 10.0, 0, az))
	_add_gen_spot(Vector3(0, 0, mez_front - 6.0))    # open floor south of the mezzanine
	_add_gen_spot(Vector3(0, 0, -inner + 14.0))      # open strip by the machine line


## A waist-high railing along one axis with a central gap (for ramp access).
func _make_railing_gapped(center: Vector3, along_x: bool, span: float, gap: float) -> void:
	var seg := (span - gap) * 0.5
	if seg <= 0.2:
		return
	var off := (gap + seg) * 0.5
	for s in [-1.0, 1.0]:
		var c := center + Vector3(0, 0.55, 0)
		if along_x:
			c.x += s * off
		else:
			c.z += s * off
		var size: Vector3 = Vector3(seg, 1.1, 0.16) if along_x else Vector3(0.16, 1.1, seg)
		_make_box(c, size, FACTORY_DARK, "metal")


## A flat walkable mezzanine slab. `center.y` is the desired TOP surface height.
func _make_slab(center: Vector3, size_xz: Vector2) -> void:
	var thick := 0.5
	var c := center - Vector3(0, thick * 0.5, 0)   # drop so the top sits at center.y
	_make_box(c, Vector3(size_xz.x, thick, size_xz.y), FACTORY_STEEL, "metal")


## A tilted ramp box. `low` = ground start, `dir` = horizontal ascent direction,
## rising `rise` over horizontal `run`, `width` wide. Climbable (~30°).
func _make_ramp(low: Vector3, dir: Vector3, rise: float, run: float, width: float) -> void:
	var d := dir.normalized()
	var top := low + d * run + Vector3(0, rise, 0)
	var mid := (low + top) * 0.5
	var length := low.distance_to(top)
	var angle := atan2(rise, run)
	var yaw := atan2(d.x, d.z)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -angle)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = mid
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.4, length)
	shape.shape = box
	shape.transform.basis = basis
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	mi.mesh = mesh
	mi.transform.basis = basis
	mi.material_override = _mat(FACTORY_STEEL, "metal")
	body.add_child(mi)


## A ground-floor wall (height 5) with a central doorway gap + an open door panel.
func _make_door_wall(center: Vector3, along_x: bool, span: float,
		wall_col := Color(-1, -1, -1), wall_tex := "metal") -> void:
	var h := 5.0
	var t := 0.4
	var gap := 3.6
	var col: Color = FACTORY_STEEL.darkened(0.1) if wall_col.r < 0.0 else wall_col
	var wall_center := center + Vector3(0, h * 0.5, 0)
	var wall_size: Vector3 = Vector3(span, h, t) if along_x else Vector3(t, h, span)
	_make_doorway_wall(wall_center, wall_size, along_x, gap, col)

	# Open door panel hinged at one side of the gap.
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(gap * 0.9, h * 0.82, 0.12)
	panel.mesh = pm
	panel.material_override = _mat(Color(0.45, 0.32, 0.16), "metal")   # rusty door
	var hinge := gap * 0.5
	if along_x:
		panel.position = center + Vector3(hinge, h * 0.41, 0.0)
		panel.rotation.y = deg_to_rad(78.0)
	else:
		panel.position = center + Vector3(0.0, h * 0.41, hinge)
		panel.rotation.y = deg_to_rad(12.0)
	add_child(panel)


## A walk-through vent duct: a 3-sided metal tunnel (open floor + ends) you can
## run through as a shortcut / cover. `along_x` runs it along the X axis.
func _make_vent_duct(center: Vector3, along_x: bool, length: float) -> void:
	var w := 2.8       # inner width
	var h := 2.6       # inner height
	var th := 0.18
	var col := FACTORY_DARK
	if along_x:
		_make_box(center + Vector3(0, h + th * 0.5, 0), Vector3(length, th, w + th * 2), col, "metal")        # roof
		_make_box(center + Vector3(0, h * 0.5, w * 0.5), Vector3(length, h, th), col, "metal")                # +Z wall
		_make_box(center + Vector3(0, h * 0.5, -w * 0.5), Vector3(length, h, th), col, "metal")               # -Z wall
		# Grate slats across the entrances (cosmetic).
		for s in [-1.0, 1.0]:
			for i in 4:
				_cosmetic(_grate_bar(w), center + Vector3(s * length * 0.5, 0.4 + i * 0.6, 0),
					col.lightened(0.12))
	else:
		_make_box(center + Vector3(0, h + th * 0.5, 0), Vector3(w + th * 2, th, length), col, "metal")
		_make_box(center + Vector3(w * 0.5, h * 0.5, 0), Vector3(th, h, length), col, "metal")
		_make_box(center + Vector3(-w * 0.5, h * 0.5, 0), Vector3(th, h, length), col, "metal")
		for s in [-1.0, 1.0]:
			for i in 4:
				var bar := BoxMesh.new()
				bar.size = Vector3(0.06, 0.12, w)
				_cosmetic(bar, center + Vector3(0, 0.4 + i * 0.6, s * length * 0.5), col.lightened(0.12))


## A horizontal grate bar mesh (used at vent entrances).
func _grate_bar(w: float) -> BoxMesh:
	var bar := BoxMesh.new()
	bar.size = Vector3(w, 0.12, 0.06)
	return bar


## Random ground spot in the outer ring (between atrium and outer wall).
func _factory_ground_spot(atr: float, b: float) -> Vector3:
	for attempt in 12:
		var p := Vector3(_rng.randf_range(-b, b), 0, _rng.randf_range(-b, b))
		if absf(p.x) > atr + 2.0 or absf(p.z) > atr + 2.0:
			return p
	return Vector3(atr + 6.0, 0, atr + 6.0)


## Random spot on one of the mezzanine bands.
func _factory_band_spot(atr: float, b: float) -> Vector3:
	return _factory_ground_spot(atr, b - 3.0)


## Murder-Mystery-2-style manor with a floor plan you can actually learn:
##   West wing:  kitchen (NW) · dining room (W) · servant quarters (SW)
##   East wing:  study (NE) · library (E) · trophy room (SE)
##   Centre:     ballroom (N) · grand staircase + mezzanine · entrance hall (S)
## Every doorway is registered as a dynamic-door spot (randomised per round).
func _build_mansion_layout() -> void:
	var crimson := Color(0.42, 0.10, 0.12)
	var gold    := Color(0.72, 0.58, 0.30)
	var cream   := Color(0.86, 0.80, 0.66)
	var walnut  := Color(0.26, 0.17, 0.11)
	var m := _half
	var fh := 6.0                       # mezzanine height

	# ── Structural walls ──
	# Wing walls (x = ±14) with doors into the centre rooms.
	_plan_wall_x(-14.0, -m + 2, m - 2, [[-30.0, false], [0.0, false], [34.0, false]], walnut, "sbswood")
	_plan_wall_x(14.0, -m + 2, m - 2, [[-30.0, false], [0.0, false], [34.0, false]], walnut, "sbswood")
	# West wing dividers.
	_plan_wall_z(-18.0, -m + 2, -14.0, [[-33.0, true]], walnut, "sbswood")   # kitchen | dining
	_plan_wall_z(16.0, -m + 2, -14.0, [[-33.0, true]], walnut, "sbswood")    # dining | servants
	# East wing dividers.
	_plan_wall_z(-18.0, 14.0, m - 2, [[33.0, true]], walnut, "sbswood")      # study | library
	_plan_wall_z(16.0, 14.0, m - 2, [[33.0, true]], walnut, "sbswood")       # library | trophy
	# Centre dividers around the stair passage.
	_plan_wall_z(-10.0, -14.0, 14.0, [[0.0, false]], walnut, "sbswood")      # ballroom door
	_plan_wall_z(8.0, -14.0, 14.0, [[0.0, false]], walnut, "sbswood")        # hall door

	# ── Grand staircase + mezzanine landing (over the stair passage) ──
	_make_ramp(Vector3(0, 0, 7.0), Vector3(0, 0, -1), fh, 13.0, 8.0)
	_make_slab(Vector3(0, fh, -8.0), Vector2(26.0, 4.0))
	_make_railing_gapped(Vector3(0, fh, -5.8), true, 26.0, 8.5)
	for tx in [-9.0, 9.0]:
		_make_trophy_pedestal(Vector3(tx, fh, -8.0))

	# ═══ KITCHEN (NW) ═══
	_make_kitchen_counter(Vector3(-48.6, 0, -35.0), false, 12.0)
	_make_kitchen_counter(Vector3(-30.0, 0, -48.6), true, 14.0)
	_make_box(Vector3(-33.0, 0.7, -35.0), Vector3(3.6, 1.4, 2.0), walnut.lightened(0.1), "wood")   # island
	_make_box(Vector3(-18.0, 1.1, -47.5), Vector3(2.2, 2.2, 1.6), Color(0.75, 0.77, 0.8), "metal") # icebox
	_make_puddle(Vector3(-26.0, 0.01, -30.0), 1.0, Color(0.45, 0.03, 0.02, 0.75))
	_make_sconce(Vector3(-48.5, 4.5, -26.0))
	_make_floor_note(Vector3(-30.0, 0.02, -40.0),
		"Dinner was served at eight.\nOnly six of us sat down.\nThe knife rack is missing one.")
	_add_gen_spot(Vector3(-24.0, 0, -42.0))

	# ═══ DINING ROOM (W) ═══
	_make_long_table(Vector3(-33.0, 0, -1.0), 16.0, walnut)
	_make_chandelier(Vector3(-33.0, 0, -1.0))
	_make_fireplace(Vector3(-m + 2.4, 0, -1.0), walnut)
	_make_carpet(Vector3(-33.0, 0.03, -1.0), Vector2(11.0, 22.0), crimson.darkened(0.15))
	_make_portrait(Vector3(-15.1, 4.0, -8.0), Vector3(-1, 0, 0), gold)
	_make_portrait(Vector3(-15.1, 4.0, 8.0), Vector3(-1, 0, 0), gold)
	_add_gen_spot(Vector3(-46.0, 0, 10.0))

	# ═══ SERVANT QUARTERS (SW) ═══
	for i in 3:
		_make_bed(Vector3(-46.5, 0, 24.0 + i * 9.0), false, Color(0.5, 0.5, 0.55))
	_make_box(Vector3(-20.0, 1.0, 46.0), Vector3(2.0, 2.0, 1.0), walnut, "wood")   # wardrobe
	_make_desk(Vector3(-30.0, 0, 46.0), walnut)
	_make_carpet(Vector3(-33.0, 0.03, 33.0), Vector2(8.0, 8.0), Color(0.3, 0.3, 0.28))
	_make_sconce(Vector3(-48.5, 4.5, 34.0))
	_make_floor_note(Vector3(-38.0, 0.02, 28.0),
		"The master rang the bell at\nmidnight. Nobody rang it back.\nI'm not going up there again.")
	_add_gen_spot(Vector3(-38.0, 0, 42.0))

	# ═══ STUDY (NE) ═══
	_make_box(Vector3(33.0, 0.95, -40.0), Vector3(3.6, 0.2, 1.8), walnut, "wood")   # grand desk top
	_make_box(Vector3(33.0, 0.45, -40.0), Vector3(3.2, 0.9, 1.4), walnut.darkened(0.15), "wood")
	_make_box(Vector3(33.0, 0.6, -37.0), Vector3(0.9, 1.2, 0.9), crimson.darkened(0.2), "wood")  # chair
	_make_bookshelves(Vector3(46.0, 0, -30.0), walnut)
	_make_cylinder(Vector3(24.0, 0.5, -46.0), 0.12, 1.0, walnut)                    # globe stand
	_make_sphere(Vector3(24.0, 1.3, -46.0), 0.45, Color(0.35, 0.45, 0.55), false, false)
	_make_portrait(Vector3(33.0, 4.0, -m + 2.5), Vector3(0, 0, 1), gold)
	_make_sconce(Vector3(48.5, 4.5, -34.0))
	_make_floor_note(Vector3(30.0, 0.02, -36.0),
		"I found the will in the study.\nEverything goes to the gardener?\nHe's been dead for ten years.")
	_add_gen_spot(Vector3(42.0, 0, -46.0))

	# ═══ LIBRARY (E) ═══
	for row in 3:
		_make_bookshelf_row(Vector3(24.0 + row * 9.0, 0, -1.0), 18.0)
	_make_fireplace(Vector3(33.0, 0, -16.6), walnut)
	_make_sofa(Vector3(33.0, 0, 12.0), crimson)
	_make_carpet(Vector3(33.0, 0.03, -1.0), Vector2(24.0, 20.0), Color(0.30, 0.24, 0.18))
	_make_sconce(Vector3(48.5, 4.5, -1.0))
	_add_gen_spot(Vector3(46.0, 0, 10.0))

	# ═══ TROPHY ROOM (SE) ═══
	for i in 3:
		for j in 2:
			_make_trophy_pedestal(Vector3(24.0 + i * 9.0, 0, 26.0 + j * 14.0))
	_make_display_case(Vector3(46.0, 0, 34.0))
	for hx in [24.0, 33.0, 42.0]:
		_make_mounted_head(Vector3(hx, 3.2, m - 2.6))
	_make_sconce(Vector3(48.5, 4.5, 34.0))
	_add_gen_spot(Vector3(40.0, 0, 46.0))

	# ═══ BALLROOM (N) ═══
	_make_carpet(Vector3(0.0, 0.02, -31.0), Vector2(20.0, 30.0), Color(0.55, 0.48, 0.38))
	for col_x in [-10.0, 10.0]:
		for col_z in [-46.0, -16.0]:
			_make_manor_column(Vector3(col_x, 0, col_z), cream, gold)
	_make_chandelier(Vector3(0.0, 0, -31.0))
	_make_piano(Vector3(-8.0, 0, -46.0))
	# The murder scene: the victim, mid-ballroom, dragged toward the doors.
	_make_corpse_prop(Vector3(2.0, 0, -28.0))
	_make_blood_pool(Vector3(2.0, 0, -28.0), 2.0)
	_make_blood_streak(Vector3(5.0, 0, -24.0), Vector3(0.6, 0, 1.0), 6.0)
	_add_gen_spot(Vector3(0.0, 0, -44.0))

	# ═══ GRAND ENTRANCE HALL (S) ═══
	_make_carpet(Vector3(0.0, 0.03, 30.0), Vector2(7.0, 40.0), crimson.darkened(0.1))
	for col_x in [-9.0, 9.0]:
		for col_z in [18.0, 42.0]:
			_make_manor_column(Vector3(col_x, 0, col_z), cream, gold)
	_make_chandelier(Vector3(0.0, 0, 28.0))
	# Front door alcove on the south wall (cosmetic — the manor is sealed).
	_make_box(Vector3(0.0, 2.6, m - 1.6), Vector3(5.2, 5.2, 0.6), walnut.darkened(0.2), "wood")
	for px in [-6.0, 6.0]:
		_make_portrait(Vector3(px, 4.0, m - 2.4), Vector3(0, 0, -1), gold)
	_make_floor_note(Vector3(0.0, 0.02, 36.0),
		"The doors won't open. The windows\nare boarded from OUTSIDE.\nOne of us did this.")
	_add_gen_spot(Vector3(0.0, 0, 46.0))

	# ── Sconces along the wing walls + blood through the halls ──
	for sz in [-30.0, 0.0, 34.0]:
		_make_sconce(Vector3(-13.2, 4.5, sz + 3.5))
		_make_sconce(Vector3(13.2, 4.5, sz + 3.5))
	for i in 10:
		var bp := Vector3(_rng.randf_range(-m + 8, m - 8), 0, _rng.randf_range(-m + 8, m - 8))
		if _rng.randf() < 0.6:
			_make_blood_pool(bp, _rng.randf_range(0.5, 1.2))
		else:
			_make_blood_streak(bp, Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)),
				_rng.randf_range(2.0, 5.0))


## A lived-in furniture cluster: a seating/dining set + a vampire table + plants.
func _furnish_manor_room(pos: Vector3, wood: Color, fabric: Color) -> void:
	var r := _rng.randf()
	if r < 0.34:
		_make_dining_set(pos, wood)
	elif r < 0.6:
		_make_bookshelves(pos, wood)
	elif r < 0.8:
		_make_sofa(pos, fabric)
	else:
		_spawn_model(VAMP + "/Vampire_Chair_Throne.fbx", pos, 2.6, Color(0.4, 0.1, 0.12))
	_spawn_model(VAMP + "/Vampire_Table_Large.fbx",
		pos + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-7, 7)), 1.4,
		Color(0.30, 0.20, 0.14))
	for i in 3:
		_spawn_model(_pick(PSI_PLANTS),
			pos + Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-9, 9)),
			_rng.randf_range(0.8, 1.6), Color(0.30, 0.5, 0.22), 0.0, false)


## A warm wall sconce: a small glowing bulb + a soft omni light.
func _make_sconce(pos: Vector3) -> void:
	_make_emissive_sphere(pos, 0.18, Color(1.0, 0.72, 0.42))
	var o := OmniLight3D.new()
	o.light_color = Color(1.0, 0.72, 0.42)
	o.light_energy = 1.3
	o.omni_range = 11.0
	o.position = pos
	add_child(o)


## Flat carpet/rug quad lying on the floor.
func _make_carpet(center: Vector3, size_xz: Vector2, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size_xz
	mi.mesh = pm
	mi.position = center
	mi.material_override = _mat(color)
	add_child(mi)


## Fluted column with a gold base + capital.
func _make_manor_column(pos: Vector3, shaft: Color, trim: Color) -> void:
	var h := 11.0
	_make_box(pos + Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 2.0), trim.darkened(0.15), "concrete")
	_make_cylinder(pos + Vector3(0, h * 0.5 + 0.6, 0), 0.65, h, shaft, "concrete")
	_make_box(pos + Vector3(0, h + 0.9, 0), Vector3(1.9, 0.6, 1.9), trim.darkened(0.15), "concrete")


## A hanging chandelier: gold ring + candle flames + a warm steady light.
func _make_chandelier(pos: Vector3) -> void:
	var y := WALL_HEIGHT - 2.2
	_cosmetic(_make_cylinder_mesh(0.05, 2.0, Color.BLACK),
		Vector3(pos.x, WALL_HEIGHT - 1.2, pos.z), Color(0.08, 0.08, 0.08))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 1.0
	_cosmetic(ring, Vector3(pos.x, y, pos.z), Color(0.72, 0.58, 0.30))
	for i in 8:
		var a := TAU * float(i) / 8.0
		_make_emissive_sphere(Vector3(pos.x + cos(a) * 0.85, y + 0.25, pos.z + sin(a) * 0.85),
			0.09, Color(1.0, 0.8, 0.4))
	var o := OmniLight3D.new()
	o.light_color = Color(1.0, 0.85, 0.58)
	o.light_energy = 2.6
	o.omni_range = 30.0
	o.position = Vector3(pos.x, y - 0.3, pos.z)
	add_child(o)


func _make_emissive_sphere(pos: Vector3, r: float, color: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	add_child(mi)


## Grand staircase up to a railed balcony on the north wall.
func _build_grand_stair(carpet: Color) -> void:
	var fh := 6.5
	var bx := 40.0            # balcony half-width
	var bz := HALF - 6.0
	var depth := 12.0
	_make_slab(Vector3(0, fh, bz - depth * 0.5), Vector2(bx * 2.0, depth))
	_make_railing_gapped(Vector3(0, fh, bz - depth), true, bx * 2.0, 13.0)
	var run := 14.0
	_make_ramp(Vector3(0, 0, bz - depth - run), Vector3(0, 0, 1), fh, run, 10.0)
	_make_carpet(Vector3(0, fh + 0.06, bz - depth * 0.5), Vector2(8.0, depth), carpet.darkened(0.1))


## A small furniture cluster in a room around `pos`.
func _furnish_room(pos: Vector3, wood: Color, fabric: Color) -> void:
	var r := _rng.randf()
	if r < 0.4:
		_make_dining_set(pos, wood)
	elif r < 0.7:
		_make_bookshelves(pos, wood)
	else:
		_make_sofa(pos, fabric)
	_make_box(pos + Vector3(_rng.randf_range(-8, 8), 0.5, _rng.randf_range(-8, 8)),
		Vector3(1.4, 1.0, 1.4), wood, "wood")


func _make_dining_set(pos: Vector3, wood: Color) -> void:
	_make_box(pos + Vector3(0, 1.0, 0), Vector3(8.0, 0.3, 2.4), wood, "wood")
	for sx in [-3.5, 3.5]:
		_make_box(pos + Vector3(sx, 0.5, 0), Vector3(0.3, 1.0, 2.0), wood.darkened(0.2))
	var i := -3.0
	while i <= 3.0:
		_make_box(pos + Vector3(i, 0.6, 1.7), Vector3(0.9, 1.2, 0.2), wood.darkened(0.1))
		_make_box(pos + Vector3(i, 0.6, -1.7), Vector3(0.9, 1.2, 0.2), wood.darkened(0.1))
		i += 2.0


func _make_bookshelves(pos: Vector3, wood: Color) -> void:
	for sx in [-2.0, 0.0, 2.0]:
		var base := pos + Vector3(sx, 0, 0)
		_make_box(base + Vector3(0, 3.0, 0), Vector3(1.8, 6.0, 0.8), wood, "wood")
		for sh in range(1, 6):
			_make_box(base + Vector3(0, float(sh), 0.0), Vector3(1.7, 0.08, 0.7), wood.lightened(0.1))


func _make_sofa(pos: Vector3, fabric: Color) -> void:
	_make_box(pos + Vector3(0, 0.5, 0), Vector3(4.0, 0.8, 1.6), fabric, "wood")
	_make_box(pos + Vector3(0, 1.2, -0.7), Vector3(4.0, 1.0, 0.3), fabric)
	for sx in [-1.9, 1.9]:
		_make_box(pos + Vector3(sx, 1.0, 0), Vector3(0.3, 0.9, 1.6), fabric.darkened(0.1))


## A fireplace recessed into a wall with a warm glow.
func _make_fireplace(pos: Vector3, stone: Color) -> void:
	_make_box(pos + Vector3(0, 2.0, 0), Vector3(5.0, 4.0, 1.2), stone.darkened(0.2), "concrete")
	_make_box(pos + Vector3(0, 1.2, 0.3), Vector3(2.6, 2.0, 0.8), Color(0.04, 0.03, 0.03))
	_make_emissive_sphere(pos + Vector3(0, 0.9, 0.4), 0.5, Color(1.0, 0.5, 0.15))
	var o := OmniLight3D.new()
	o.light_color = Color(1.0, 0.55, 0.2)
	o.light_energy = 2.2
	o.omni_range = 16.0
	o.position = pos + Vector3(0, 1.2, 1.0)
	add_child(o)


## A framed portrait hung flat on a wall (gold frame + dark canvas).
func _make_portrait(pos: Vector3, facing: Vector3, frame: Color) -> void:
	var flat := absf(facing.x) > 0.5
	var fsize: Vector3 = Vector3(0.2, 2.4, 1.8) if flat else Vector3(1.8, 2.4, 0.2)
	var csize: Vector3 = Vector3(0.1, 2.0, 1.4) if flat else Vector3(1.4, 2.0, 0.1)
	_cosmetic(_box_mesh(fsize), pos, frame)
	_cosmetic(_box_mesh(csize), pos + facing * 0.06, Color(0.10, 0.08, 0.07))


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


# ── Blood (murder-scene dressing) ────────────────────────────────────────────

func _blood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.02, 0.02, 0.95)
	m.metallic = 0.3
	m.roughness = 0.25          # wet sheen
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## An irregular floor pool built from overlapping flat discs.
func _make_blood_pool(pos: Vector3, radius: float) -> void:
	var mat := _blood_mat()
	for i in _rng.randi_range(4, 7):
		var off := Vector3(_rng.randf_range(-radius, radius), 0, _rng.randf_range(-radius, radius)) * 0.7
		var rr := radius * _rng.randf_range(0.4, 1.0)
		var disc := CylinderMesh.new()
		disc.top_radius = rr
		disc.bottom_radius = rr
		disc.height = 0.02
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.position = pos + off + Vector3(0, 0.025, 0)
		mi.material_override = mat
		add_child(mi)


## A drag streak across the floor.
func _make_blood_streak(pos: Vector3, dir: Vector3, length: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.5, length)
	mi.mesh = pm
	mi.position = pos + Vector3(0, 0.03, 0)
	mi.rotation.y = atan2(dir.x, dir.z)
	mi.material_override = _blood_mat()
	add_child(mi)


## A splatter on a wall (thin flat quad standing vertical).
func _make_blood_splatter(pos: Vector3, along_x: bool) -> void:
	var mi := MeshInstance3D.new()
	var s := _rng.randf_range(1.0, 2.2)
	mi.mesh = _box_mesh(Vector3(0.06, s, s) if along_x else Vector3(s, s, 0.06))
	mi.position = pos
	mi.material_override = _blood_mat()
	add_child(mi)


func _spill_blood() -> void:
	# Centrepiece pool + drag in the grand hall.
	_make_blood_pool(Vector3(2.0, 0, -4.0), 2.4)
	_make_blood_streak(Vector3(5.0, 0, -2.0), Vector3(1, 0, 0.6), 8.0)
	# Pools + streaks scattered through every room.
	for i in 28:
		var p := Vector3(_rng.randf_range(-HALF + 8, HALF - 8), 0, _rng.randf_range(-HALF + 8, HALF - 8))
		if _rng.randf() < 0.7:
			_make_blood_pool(p, _rng.randf_range(0.6, 1.8))
		else:
			_make_blood_streak(p, Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)),
				_rng.randf_range(2.0, 6.0))
	# Wall splatter along the partition lines + exterior walls.
	for i in 16:
		var along_x := _rng.randf() < 0.5
		var coord: float = [-48.0, 48.0, -HALF + 2.0, HALF - 2.0][_rng.randi() % 4]
		var other := _rng.randf_range(-HALF + 8, HALF - 8)
		var y := _rng.randf_range(1.5, 6.0)
		if along_x:
			_make_blood_splatter(Vector3(coord, y, other), true)
		else:
			_make_blood_splatter(Vector3(other, y, coord), false)


## Indoor building: thick interior walls split the arena into rooms joined by
## doorways, forming corridors (Murder-Mystery-2 style). The exterior walls +
## ceiling (built earlier) seal it off so there's no outside plot to wander to.
func _build_indoor_layout() -> void:
	# Grid lines (relative to the indoor footprint). Avoid x=0/z=0 so the central
	# room (where the hunter spawns) stays open.
	var lines := [-_half * 0.6, -_half * 0.22, _half * 0.22, _half * 0.6]

	for x in lines:
		_make_partition(true, x, _gap_centers())
	for z in lines:
		_make_partition(false, z, _gap_centers())

	# Furniture scattered through the rooms (avoiding the centre + doorways).
	var placed := 0
	var attempts := 0
	while placed < 40 and attempts < 600:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-_half + 6, _half - 6), 0,
				_rng.randf_range(-_half + 6, _half - 6))
		if pos.length() < CENTER_CLEAR:
			continue
		if _near_any(pos.x, lines, 4.0) or _near_any(pos.z, lines, 4.0):
			continue
		_make_indoor_prop(pos)
		placed += 1

	# Ceiling lights spread across the footprint — they flicker (FlickerLight).
	for gx in [-_half * 0.66, -_half * 0.33, 0.0, _half * 0.33, _half * 0.66]:
		for gz in [-_half * 0.66, -_half * 0.33, 0.0, _half * 0.33, _half * 0.66]:
			_add_ceiling_light(Vector3(gx, WALL_HEIGHT - 1.5, gz))

	# Curated generator spots at room centres (midway between the partition lines),
	# clear of the walls and doorways. Furniture overlaps are skipped at spawn.
	var room := _half * 0.41
	_add_gen_spot(Vector3(-room, 0, -room))
	_add_gen_spot(Vector3(room, 0, -room))
	_add_gen_spot(Vector3(-room, 0, room))
	_add_gen_spot(Vector3(room, 0, room))
	_add_gen_spot(Vector3(0, 0, -room))
	_add_gen_spot(Vector3(0, 0, room))
	_add_gen_spot(Vector3(-room, 0, 0))
	_add_gen_spot(Vector3(room, 0, 0))


## Random furniture for an indoor room (reuses existing structure builders).
func _make_indoor_prop(pos: Vector3) -> void:
	var r := _rng.randf()
	if r < 0.34:
		_make_crate_stack(pos)
	elif r < 0.60:
		_make_column(pos)
	elif r < 0.80:
		_make_block(pos)
	else:
		_make_fountain(pos)


## Pick 2–3 doorway positions along a wall's span (used to leave gaps).
func _gap_centers() -> Array:
	var s := _half * 0.72
	var spots := [-s, -s * 0.5, 0.0, s * 0.5, s]
	spots.shuffle()
	var n := _rng.randi_range(2, 3)
	return spots.slice(0, n)


## Build one interior wall with doorway gaps.
##   vertical = true  → wall runs along Z at x = coord.
##   vertical = false → wall runs along X at z = coord.
func _make_partition(vertical: bool, coord: float, gap_centers: Array) -> void:
	var span_min := -_half + 4.0
	var span_max := _half - 4.0
	var thickness := 2.4
	var door := 6.0

	# Turn doorway centres into [start, end] cuts, sorted along the span.
	var cuts: Array = []
	for g in gap_centers:
		cuts.append([g - door * 0.5, g + door * 0.5])
	cuts.sort_custom(func(a, b): return a[0] < b[0])

	# Emit wall segments between the cuts.
	var cursor := span_min
	for c in cuts:
		var seg_end: float = clampf(c[0], span_min, span_max)
		if seg_end - cursor > 0.5:
			_add_partition_segment(vertical, coord, cursor, seg_end, thickness)
		cursor = maxf(cursor, c[1])
		# Register the doorway so the dynamic-door pass can hang a door in it.
		# Partition rooms have no guaranteed second exit, so these never lock.
		var gc: float = clampf((c[0] + c[1]) * 0.5, span_min + door, span_max - door)
		var dpos := Vector3(coord, 0, gc) if vertical else Vector3(gc, 0, coord)
		_add_door_spot(dpos, not vertical, door * 0.9, false)
	if span_max - cursor > 0.5:
		_add_partition_segment(vertical, coord, cursor, span_max, thickness)


func _add_partition_segment(vertical: bool, coord: float, a: float, b: float, thickness: float) -> void:
	var length := b - a
	var mid := (a + b) * 0.5
	var pos: Vector3
	var size: Vector3
	if vertical:   # along Z at x = coord
		pos = Vector3(coord, WALL_HEIGHT * 0.5, mid)
		size = Vector3(thickness, WALL_HEIGHT, length)
	else:          # along X at z = coord
		pos = Vector3(mid, WALL_HEIGHT * 0.5, coord)
		size = Vector3(length, WALL_HEIGHT, thickness)
	_make_box(pos, size, _pick_color().darkened(0.25), _wall_tex)


## A flickering ceiling light for indoor rooms.
func _add_ceiling_light(pos: Vector3) -> void:
	var o: OmniLight3D = FLICKER_SCRIPT.new()
	o.light_color = Color(0.9, 0.82, 0.66)   # warm dim bulb
	o.light_energy = 0.8
	o.omni_range = 26.0
	o.position = pos
	add_child(o)


## True if `value` is within `margin` of any number in `lines`.
func _near_any(value: float, lines: Array, margin: float) -> bool:
	for l in lines:
		if absf(value - l) < margin:
			return true
	return false


## --- Style-specific structures -------------------------------------------

func _make_structure(pos: Vector3) -> void:
	var r := _rng.randf()
	match style:
		Style.FOREST:
			if r < 0.50: _make_foliage(pos, FOLIAGE_TREES, 6.0, 11.0, Color(0.16, 0.26, 0.14))
			elif r < 0.70: _make_rock(pos)
			elif r < 0.85: _make_foliage(pos, FOLIAGE_BUSHES, 1.6, 2.8, Color(0.18, 0.30, 0.16), 0.45)
			else: _make_house(pos)
		Style.WAREHOUSE:
			if r < 0.28: _make_shelf_rack(pos)
			elif r < 0.52: _make_large_machine(pos)
			elif r < 0.68: _make_conveyor_belt(pos)
			elif r < 0.82: _make_catwalk(pos)
			elif r < 0.93: _make_crate_stack(pos)
			else: _make_silo(pos)
		Style.MANSION:
			if r < 0.42: _make_house(pos)
			elif r < 0.72: _make_column(pos)
			elif r < 0.86: _make_fountain(pos)
			else: _make_block(pos)
		Style.NEON:
			if r < 0.38: _make_neon_pillar(pos)
			elif r < 0.68: _make_tower(pos)
			elif r < 0.85: _make_block(pos)
			else: _make_crate_stack(pos)
		Style.GRAVEYARD:
			if r < 0.40: _make_tombstone(pos)
			elif r < 0.64: _make_foliage(pos, FOLIAGE_TREES, 5.0, 9.0, Color(0.14, 0.15, 0.13))
			elif r < 0.84: _make_house(pos)
			else: _make_rock(pos)
		_: # URBAN
			if r < 0.40: _make_house(pos)
			elif r < 0.70: _make_tower(pos)
			else: _make_block(pos)


func _make_block(pos: Vector3) -> void:
	var w := _rng.randf_range(4, 7)
	var ht := _rng.randf_range(4, 10)
	var d := _rng.randf_range(4, 7)
	_make_box(pos + Vector3(0, ht * 0.5, 0), Vector3(w, ht, d), _pick_color(), "concrete")


## Cylinder tower with a domed cap (curved).
func _make_tower(pos: Vector3) -> void:
	var rad := _rng.randf_range(2.0, 3.4)
	var h := _rng.randf_range(6, 12)
	var col := _pick_color()
	_make_cylinder(pos + Vector3(0, h * 0.5, 0), rad, h, col, "concrete")
	_make_sphere(pos + Vector3(0, h, 0), rad, col.darkened(0.2), true, false)


func _make_crate_stack(pos: Vector3) -> void:
	var n := _rng.randi_range(2, 4)
	var col := _pick_color()
	for i in n:
		var s := _rng.randf_range(1.6, 2.4)
		var off := Vector3(_rng.randf_range(-0.6, 0.6), s * 0.5 + i * 2.0, _rng.randf_range(-0.6, 0.6))
		_make_box(pos + off, Vector3(s, s, s), col.lerp(Color.WHITE, 0.08 * i), "wood")


## Walkable hollow house: walls + doorway + pitched roof + rounded corner posts.
func _make_house(pos: Vector3) -> void:
	var w := _rng.randf_range(9, 13)
	var d := _rng.randf_range(9, 13)
	var h := _rng.randf_range(4.0, 5.5)
	var t := 0.4
	var col := _pick_color()
	var roof_col := col.darkened(0.4)
	var door := 3.0
	var door_side := _rng.randi_range(0, 3)

	for side in 4:
		var along_x := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var wall_pos: Vector3
		var wall_size: Vector3
		if along_x:
			wall_pos = pos + Vector3(0, h * 0.5, sgn * d * 0.5)
			wall_size = Vector3(w, h, t)
		else:
			wall_pos = pos + Vector3(sgn * w * 0.5, h * 0.5, 0)
			wall_size = Vector3(t, h, d)
		if side == door_side:
			_make_doorway_wall(wall_pos, wall_size, along_x, door, col)
		else:
			_make_box(wall_pos, wall_size, col, "wood")

	# Rounded corner posts.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_make_cylinder(pos + Vector3(cx * w * 0.5, h * 0.5, cz * d * 0.5), 0.5, h, roof_col, "wood")

	# Pitched roof (curved silhouette via a prism).
	var rh := 2.6
	_cosmetic(_prism(Vector3(w + 0.8, rh, d + 0.8)), pos + Vector3(0, h + rh * 0.5, 0), roof_col)


func _make_doorway_wall(center: Vector3, size: Vector3, along_x: bool, gap: float, col: Color) -> void:
	var span := size.x if along_x else size.z
	var seg := (span - gap) * 0.5
	if seg <= 0.2:
		_make_box(center, size, col, "wood")
		return
	var offset := (gap + seg) * 0.5
	for s in [-1.0, 1.0]:
		var p := center
		var sz := size
		if along_x:
			p.x += s * offset
			sz.x = seg
		else:
			p.z += s * offset
			sz.z = seg
		_make_box(p, sz, col, "wood")


## Forest -----------------------------------------------------------------

func _make_tree(pos: Vector3) -> void:
	var th := _rng.randf_range(3.0, 5.0)
	_make_cylinder(pos + Vector3(0, th * 0.5, 0), 0.5, th, Color(0.34, 0.24, 0.16))
	var green: Color = PALETTES[Style.FOREST][_rng.randi() % 3]
	_make_sphere(pos + Vector3(0, th + 1.0, 0), _rng.randf_range(2.0, 2.8), green, false, false)
	_make_sphere(pos + Vector3(_rng.randf_range(-0.8, 0.8), th + 2.0, 0), _rng.randf_range(1.4, 2.0), green.lightened(0.1), false, false)


## Place a real foliage mesh (OBJ), scaled to a target height, resting on the
## floor, with a thin trunk collider. Falls back to the primitive tree.
func _make_foliage(pos: Vector3, paths: Array, hmin: float, hmax: float, tint: Color, collide_frac := 0.18) -> void:
	var path: String = paths[_rng.randi() % paths.size()]
	var mesh := load(path) as Mesh
	if mesh == null:
		_make_tree(pos)
		return
	var aabb := mesh.get_aabb()
	if aabb.size.y < 0.001:
		_make_tree(pos)
		return
	var th := _rng.randf_range(hmin, hmax)
	var sc := th / aabb.size.y
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = Vector3(pos.x, 0.0, pos.z)
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * sc
	mi.position = Vector3(0, -aabb.position.y * sc, 0)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.material_override = _mat(tint)
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(maxf(aabb.size.x, aabb.size.z) * sc * collide_frac, 0.3)
	cyl.height = th
	shape.shape = cyl
	shape.position = Vector3(0, th * 0.5, 0)
	body.add_child(shape)


func _make_rock(pos: Vector3) -> void:
	var r := _rng.randf_range(1.6, 2.8)
	_make_sphere(pos + Vector3(0, r * 0.45, 0), r, Color(0.4, 0.42, 0.45), false, true)


func _make_bush(pos: Vector3) -> void:
	var r := _rng.randf_range(1.1, 1.6)
	_make_sphere(pos + Vector3(0, r * 0.6, 0), r, Color(0.26, 0.42, 0.22), false, true)


## Warehouse --------------------------------------------------------------

func _make_silo(pos: Vector3) -> void:
	var rad := _rng.randf_range(2.0, 3.0)
	var h := _rng.randf_range(7, 10)
	var col := _pick_color()
	_make_cylinder(pos + Vector3(0, h * 0.5, 0), rad, h, col, "metal")
	_make_sphere(pos + Vector3(0, h, 0), rad, col.lightened(0.1), true, false)


func _make_tank(pos: Vector3) -> void:
	var rad := _rng.randf_range(3.0, 4.0)
	_make_cylinder(pos + Vector3(0, 1.6, 0), rad, 3.2, _pick_color(), "metal")


## Tall metal shelving unit with horizontal shelves — warehouse aisle feel.
func _make_shelf_rack(pos: Vector3) -> void:
	var h := _rng.randf_range(7.0, 11.0)
	var depth := _rng.randf_range(3.5, 5.5)
	var col := Color(0.32, 0.33, 0.38)
	var shelf_col := Color(0.20, 0.22, 0.25)
	var along_x := _rng.randf() < 0.5

	# Two upright posts (front + back of the rack depth).
	for sign_d in [-1.0, 1.0]:
		var pp: Vector3
		if along_x:
			pp = pos + Vector3(sign_d * depth * 0.5, h * 0.5, 0)
		else:
			pp = pos + Vector3(0, h * 0.5, sign_d * depth * 0.5)
		_make_box(pp, Vector3(0.16, h, 0.16), col, "metal")

	# Horizontal shelves (3–5 levels).
	var levels := _rng.randi_range(3, 5)
	for i in levels + 1:
		var sy := h * float(i) / float(levels)
		var shelf_size: Vector3
		if along_x:
			shelf_size = Vector3(depth, 0.10, 1.1)
		else:
			shelf_size = Vector3(1.1, 0.10, depth)
		_make_box(pos + Vector3(0, sy, 0), shelf_size, shelf_col, "metal")

	# Top crossbeam.
	var beam: Vector3 = Vector3(depth + 0.2, 0.18, 0.18) if along_x else Vector3(0.18, 0.18, depth + 0.2)
	_make_box(pos + Vector3(0, h, 0), beam, col, "metal")


## Low flat conveyor belt running along one axis — players run around or vault it.
func _make_conveyor_belt(pos: Vector3) -> void:
	var length := _rng.randf_range(8.0, 15.0)
	var belt_h := 1.1
	var col_frame := Color(0.28, 0.28, 0.32)
	var col_belt := Color(0.12, 0.12, 0.14)
	var along_x := _rng.randf() < 0.5

	# Main frame body.
	var frame_size: Vector3
	if along_x:
		frame_size = Vector3(length, belt_h, 1.5)
	else:
		frame_size = Vector3(1.5, belt_h, length)
	_make_box(pos + Vector3(0, belt_h * 0.5, 0), frame_size, col_frame, "metal")

	# Belt surface (cosmetic dark strip on top).
	var top_mesh := BoxMesh.new()
	if along_x:
		top_mesh.size = Vector3(length - 0.3, 0.06, 1.0)
	else:
		top_mesh.size = Vector3(1.0, 0.06, length - 0.3)
	_cosmetic(top_mesh, pos + Vector3(0, belt_h + 0.03, 0), col_belt)

	# Support legs along the length.
	var leg_count := maxi(2, int(length / 4.0))
	for i in leg_count:
		var t := (float(i) + 0.5) / float(leg_count)
		for side in [-1.0, 1.0]:
			var lp: Vector3
			if along_x:
				lp = pos + Vector3((t - 0.5) * length, belt_h * 0.25, side * 0.55)
			else:
				lp = pos + Vector3(side * 0.55, belt_h * 0.25, (t - 0.5) * length)
			_make_box(lp, Vector3(0.12, belt_h * 0.5, 0.12), col_frame, "metal")


## Elevated catwalk on pillars — players can walk below or (with effort) on top.
func _make_catwalk(pos: Vector3) -> void:
	var cat_h := _rng.randf_range(4.0, 6.0)
	var length := _rng.randf_range(10.0, 16.0)
	var along_x := _rng.randf() < 0.5
	var col := Color(0.26, 0.28, 0.32)
	var rail_col := Color(0.20, 0.22, 0.26)

	# Platform (walkable top surface).
	var plat_size: Vector3
	if along_x:
		plat_size = Vector3(length, 0.28, 2.2)
	else:
		plat_size = Vector3(2.2, 0.28, length)
	_make_box(pos + Vector3(0, cat_h, 0), plat_size, col, "metal")

	# Railings (cosmetic, above platform surface).
	for side in [-1.0, 1.0]:
		var rail_mesh := BoxMesh.new()
		if along_x:
			rail_mesh.size = Vector3(length, 0.08, 0.08)
			_cosmetic(rail_mesh, pos + Vector3(0, cat_h + 0.8, side * 1.05), rail_col)
		else:
			rail_mesh.size = Vector3(0.08, 0.08, length)
			_cosmetic(rail_mesh, pos + Vector3(side * 1.05, cat_h + 0.8, 0), rail_col)

	# Support pillars every 4–5 m.
	var pillar_n := maxi(2, int(length / 4.5))
	for i in pillar_n:
		var t := (float(i) + 0.5) / float(pillar_n)
		var px := (t - 0.5) * length if along_x else 0.0
		var pz := 0.0 if along_x else (t - 0.5) * length
		_make_box(pos + Vector3(px, cat_h * 0.5, pz),
				Vector3(0.30, cat_h, 0.30), col, "metal")


## Blocky industrial machine body with vertical exhaust pipes.
func _make_large_machine(pos: Vector3) -> void:
	var w := _rng.randf_range(4.0, 6.5)
	var d := _rng.randf_range(3.0, 5.0)
	var h := _rng.randf_range(3.5, 6.0)
	var col_main := Color(0.24, 0.26, 0.30)
	var col_accent := _pick_color()  # safety orange / yellow / green

	# Main machine body.
	_make_box(pos + Vector3(0, h * 0.5, 0), Vector3(w, h, d), col_main, "metal")

	# Exhaust pipes on top.
	var pipe_n := _rng.randi_range(1, 3)
	for i in pipe_n:
		var pipe_h := _rng.randf_range(2.0, 4.5)
		var ox := _rng.randf_range(-w * 0.35, w * 0.35)
		var oz := _rng.randf_range(-d * 0.3, d * 0.3)
		_make_cylinder(pos + Vector3(ox, h + pipe_h * 0.5, oz),
				_rng.randf_range(0.20, 0.44), pipe_h, col_accent, "metal")

	# Side control panel accent.
	_make_box(pos + Vector3(w * 0.5 + 0.12, h * 0.42, 0),
			Vector3(0.22, h * 0.44, minf(d * 0.5, 1.6)), col_accent)


## Mansion ----------------------------------------------------------------

func _make_column(pos: Vector3) -> void:
	var h := _rng.randf_range(6, 9)
	var col: Color = PALETTES[Style.MANSION][2]   # cream
	_make_box(pos + Vector3(0, 0.3, 0), Vector3(2.2, 0.6, 2.2), col.darkened(0.2), "concrete")      # base
	_make_cylinder(pos + Vector3(0, h * 0.5 + 0.6, 0), 0.7, h, col, "concrete")                     # shaft
	_make_box(pos + Vector3(0, h + 0.9, 0), Vector3(2.0, 0.6, 2.0), col.darkened(0.2), "concrete")  # capital


func _make_fountain(pos: Vector3) -> void:
	var col := _pick_color()
	_make_cylinder(pos + Vector3(0, 0.5, 0), 3.0, 1.0, col)             # basin
	_make_cylinder(pos + Vector3(0, 1.6, 0), 0.5, 2.0, col.lightened(0.15))
	_make_sphere(pos + Vector3(0, 2.8, 0), 0.8, col.lightened(0.3), false, false)


## Neon -------------------------------------------------------------------

func _make_neon_pillar(pos: Vector3) -> void:
	var h := _rng.randf_range(6, 11)
	_make_box(pos + Vector3(0, h * 0.5, 0), Vector3(1.2, h, 1.2), _pick_color())


## Graveyard --------------------------------------------------------------

func _make_tombstone(pos: Vector3) -> void:
	var col := _pick_color()
	var w := _rng.randf_range(1.3, 1.8)
	var h := _rng.randf_range(1.4, 2.2)
	_make_box(pos + Vector3(0, h * 0.5, 0), Vector3(w, h, 0.35), col, "concrete")
	_make_sphere(pos + Vector3(0, h, 0), w * 0.5, col, true, false)   # rounded top


func _make_dead_tree(pos: Vector3) -> void:
	var th := _rng.randf_range(3.5, 5.5)
	var brown := Color(0.26, 0.20, 0.16)
	_make_cylinder(pos + Vector3(0, th * 0.5, 0), 0.45, th, brown)
	for i in _rng.randi_range(2, 4):
		var ang := _rng.randf_range(0, TAU)
		var bl := _rng.randf_range(1.5, 2.5)
		var branch := _make_cylinder_mesh(0.18, bl, brown)
		var mi := MeshInstance3D.new()
		mi.mesh = branch
		mi.material_override = _mat(brown)
		mi.position = pos + Vector3(0, _rng.randf_range(th * 0.5, th), 0)
		mi.rotation = Vector3(deg_to_rad(_rng.randf_range(35, 60)), ang, 0)
		add_child(mi)


func _pick_color() -> Color:
	var pal: Array = PALETTES.get(style, PALETTES[Style.CABIN])
	return pal[_rng.randi() % pal.size()]


# ── Imported-model placement (FBX scenes / OBJ meshes) ───────────────────────

## Place an imported model (FBX→PackedScene or OBJ→Mesh) at `pos`, auto-scaled to
## `target_h` via its AABB (so unknown source units don't matter), resting on the
## floor with a random yaw. Optional cylinder collider. Returns the holder, or
## null if the asset is missing/empty.
func _spawn_model(path: String, pos: Vector3, target_h: float, tint := Color(1, 1, 1),
		collide_frac := 0.3, do_collide := true) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	var inst: Node3D
	if res is PackedScene:
		inst = (res as PackedScene).instantiate()
	elif res is Mesh:
		inst = MeshInstance3D.new()
		(inst as MeshInstance3D).mesh = res
	else:
		return null

	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(inst)
	var aabb := _subtree_aabb(inst)
	if aabb.size.y < 0.0001:
		holder.queue_free()
		return null
	var sc := target_h / aabb.size.y
	holder.scale = Vector3.ONE * sc
	holder.rotation.y = _rng.randf_range(0.0, TAU)
	holder.position = Vector3(pos.x, -aabb.position.y * sc, pos.z)
	if tint != Color(1, 1, 1):
		_tint_model(inst, tint)

	if do_collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = Vector3(pos.x, 0, pos.z)
		add_child(body)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(maxf(aabb.size.x, aabb.size.z) * sc * collide_frac, 0.3)
		cyl.height = target_h
		shape.shape = cyl
		shape.position = Vector3(0, target_h * 0.5, 0)
		body.add_child(shape)
	return holder


## Combined AABB of a node subtree, in the space of the node's parent.
func _subtree_aabb(root: Node3D) -> AABB:
	var have := false
	var out := AABB()
	var stack: Array = [[root, root.transform]]
	while not stack.is_empty():
		var e = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
			if have:
				out = out.merge(a)
			else:
				out = a
				have = true
		for c in n.get_children():
			var cxf: Transform3D = xf * (c as Node3D).transform if c is Node3D else xf
			stack.append([c, cxf])
	return out


## Override every mesh's albedo with `color` (imported FBX often lose textures).
func _tint_model(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = _mat(color)
	for c in node.get_children():
		_tint_model(c, color)


## Convenience: pick a random path from an array.
func _pick(arr: Array) -> String:
	return arr[_rng.randi() % arr.size()]


## --- Spawns --------------------------------------------------------------

func _build_spawns() -> void:
	var root := Node3D.new()
	root.name = "SpawnPoints"
	add_child(root)
	var h := Marker3D.new()
	h.name = "HunterSpawn"
	# Most maps keep the centre clear; the LAB routes walls through the origin,
	# so the hunter wakes up at the entry security checkpoint instead.
	if style == Style.LAB:
		h.position = Vector3(0, 1, _half - 13.0)
	else:
		h.position = Vector3(0, 1, 0)
	root.add_child(h)
	var rad := _half - 4.0
	for i in PERIMETER_SPAWNS:
		var ang := TAU * float(i) / float(PERIMETER_SPAWNS)
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(cos(ang) * rad, 1, sin(ang) * rad)
		root.add_child(m)


## --- primitive helpers ---------------------------------------------------

func _make_box(center: Vector3, size: Vector3, color: Color, tex := "") -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, tex)
	body.add_child(mi)


func _make_cylinder(center: Vector3, radius: float, height: float, color: Color, tex := "") -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = _make_cylinder_mesh(radius, height, color)
	mi.material_override = _mat(color, tex)
	body.add_child(mi)


func _make_cylinder_mesh(radius: float, height: float, _color: Color) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


## Sphere (or dome via hemi). Cosmetic when collide=false (canopies, caps).
func _make_sphere(center: Vector3, radius: float, color: Color, hemi := false, collide := true) -> void:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius if hemi else radius * 2.0
	sm.is_hemisphere = hemi
	if not collide:
		_cosmetic(sm, center, color)
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	add_child(body)
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	shape.shape = s
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = _mat(color)
	body.add_child(mi)


func _prism(size: Vector3) -> PrismMesh:
	var pm := PrismMesh.new()
	pm.size = size
	return pm


## A mesh with no collision (roofs, canopies, decoration).
func _cosmetic(mesh: Mesh, center: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = center
	mi.rotation = rot
	mi.material_override = _mat(color)
	add_child(mi)


func _tex(key: String) -> Texture2D:
	if key == "":
		return null
	if not _tex_cache.has(key):
		var p: String = TEX_PATHS.get(key, "")
		_tex_cache[key] = load(p) if (p != "" and ResourceLoader.exists(p)) else null
	return _tex_cache[key]


func _mat(color: Color, tex_key := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	var t := _tex(tex_key)
	if t:
		m.albedo_texture = t
		m.uv1_scale = Vector3(2.0, 2.0, 1.0)
		if tex_key == "metal":
			m.metallic = 0.55
			m.roughness = 0.45
	if _emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.7
	return m


## Tiled ground tinted by the per-map ground_color.
func _ground_mat() -> StandardMaterial3D:
	# Per-style floor texture, using the SBS pack where it fits.
	var tex_path := "res://assets/textures/ground_concrete.png"
	var tiling := ARENA_SIZE / 6.0
	match style:
		Style.FOREST:
			tex_path = TEX_PATHS["sbsgrass"]
			tiling = ARENA_SIZE / 4.0
		Style.MANSION:
			tex_path = TEX_PATHS["tile"]
			tiling = ARENA_SIZE / 3.0
		Style.DUNGEON, Style.MAZE:
			tex_path = TEX_PATHS["brick"]
			tiling = ARENA_SIZE / 3.0
		Style.SCHOOL:
			tex_path = TEX_PATHS["tile"]
			tiling = ARENA_SIZE / 3.0
		Style.CAVE:
			tex_path = TEX_PATHS["rock"]
			tiling = ARENA_SIZE / 5.0
		Style.LAB:
			tex_path = TEX_PATHS["metal"]
			tiling = ARENA_SIZE / 3.0
		Style.CABIN:
			tex_path = TEX_PATHS["sbsgrass"]
			tiling = ARENA_SIZE / 4.0
		Style.CITY:
			tex_path = "res://assets/textures/ground_concrete.png"
			tiling = ARENA_SIZE / 5.0
	var m := StandardMaterial3D.new()
	m.albedo_color = ground_color
	m.roughness = 0.95
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
		m.uv1_scale = Vector3(tiling, tiling, 1.0)
	return m



# ═════════════════════════════════════════════════════════════════════════════
# DYNAMIC DOORS + GENERATOR SPAWN POINTS  (randomised every round)
# ═════════════════════════════════════════════════════════════════════════════

const DOOR_SCRIPT := preload("res://scripts/Door.gd")

## Doorway gaps recorded while building the layout. Each entry:
## {"pos": Vector3, "along_x": bool, "width": float, "can_lock": bool}
var _door_spots: Array = []
## Curated generator spawn positions for this layout (published as markers).
var _gen_spots: Array = []


func _add_door_spot(pos: Vector3, along_x: bool, width := 3.6, can_lock := true) -> void:
	_door_spots.append({"pos": pos, "along_x": along_x, "width": width, "can_lock": can_lock})


func _add_gen_spot(pos: Vector3) -> void:
	_gen_spots.append(pos)


## Spawn swinging doors at a random subset of the recorded doorways and LOCK a
## few of them. Uses a randomised RNG (not the seeded layout RNG) so the door
## arrangement changes every round even though the architecture stays fixed.
## Only spots flagged `can_lock` may lock — those are doorways whose rooms keep
## an alternate route, so a locked door never seals off part of the map.
func _spawn_round_doors() -> void:
	if _door_spots.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spots := _door_spots.duplicate()
	# Fisher-Yates with our own RNG (Array.shuffle uses the global one).
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var place_n := maxi(1, int(ceil(spots.size() * 0.75)))
	var lock_budget := int(floor(place_n * 0.25))
	for i in mini(place_n, spots.size()):
		var s: Dictionary = spots[i]
		var locked: bool = s["can_lock"] and lock_budget > 0 and rng.randf() < 0.55
		if locked:
			lock_budget -= 1
		var d: Node3D = DOOR_SCRIPT.new()
		add_child(d)
		d.position = s["pos"]
		d.setup(s["along_x"], s["width"], locked)


## Publish curated generator spots as Marker3D nodes in the "generator_spawn"
## group; ObjectiveController prefers these (shuffled per round) over scatter.
func _spawn_gen_markers() -> void:
	if _gen_spots.is_empty():
		return
	var root := Node3D.new()
	root.name = "GeneratorSpawns"
	add_child(root)
	for pos in _gen_spots:
		var mk := Marker3D.new()
		root.add_child(mk)
		mk.position = pos
		mk.add_to_group("generator_spawn")


## Wall along X at fixed z, spanning x0→x1, with doorway gaps at `doors`
## (each entry = [centre, can_lock]). Every gap registers a dynamic-door spot.
func _plan_wall_z(z: float, x0: float, x1: float, doors: Array, col: Color, tex := "", height := -1.0) -> void:
	var wall_h := (WALL_HEIGHT * 0.5) if height <= 0.0 else height
	var dwh := 1.8
	var ds := doors.duplicate()
	ds.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := x0
	for d in ds:
		var c: float = d[0]
		if c - dwh - cursor > 0.3:
			_make_box(Vector3((cursor + c - dwh) * 0.5, wall_h * 0.5, z),
				Vector3(c - dwh - cursor, wall_h, 0.4), col, tex)
		_add_door_spot(Vector3(c, 0, z), true, dwh * 2.0, bool(d[1]))
		cursor = c + dwh
	if x1 - cursor > 0.3:
		_make_box(Vector3((cursor + x1) * 0.5, wall_h * 0.5, z),
			Vector3(x1 - cursor, wall_h, 0.4), col, tex)


## Wall along Z at fixed x, spanning z0→z1, with doorway gaps at `doors`.
func _plan_wall_x(x: float, z0: float, z1: float, doors: Array, col: Color, tex := "", height := -1.0) -> void:
	var wall_h := (WALL_HEIGHT * 0.5) if height <= 0.0 else height
	var dwh := 1.8
	var ds := doors.duplicate()
	ds.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := z0
	for d in ds:
		var c: float = d[0]
		if c - dwh - cursor > 0.3:
			_make_box(Vector3(x, wall_h * 0.5, (cursor + c - dwh) * 0.5),
				Vector3(0.4, wall_h, c - dwh - cursor), col, tex)
		_add_door_spot(Vector3(x, 0, c), false, dwh * 2.0, bool(d[1]))
		cursor = c + dwh
	if z1 - cursor > 0.3:
		_make_box(Vector3(x, wall_h * 0.5, (cursor + z1) * 0.5),
			Vector3(0.4, wall_h, z1 - cursor), col, tex)


# ═════════════════════════════════════════════════════════════════════════════
# SHARED INTERIOR PROP BUILDERS  (lab / mansion / cabin / city)
# ═════════════════════════════════════════════════════════════════════════════

## A dim cold fluorescent strip that flickers like failing facility power.
func _make_fluorescent_flicker(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(2.6, 0.08, 0.4)
	mi.mesh = bar
	mi.position = pos
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.85, 0.9, 0.95)
	mmat.emission_enabled = true
	mmat.emission = Color(0.75, 0.85, 0.95)
	mmat.emission_energy_multiplier = 1.1
	mi.material_override = mmat
	add_child(mi)
	var o: OmniLight3D = FLICKER_SCRIPT.new()
	o.light_color = Color(0.72, 0.82, 0.92)
	o.light_energy = 1.5
	o.omni_range = 14.0
	o.position = pos - Vector3(0, 0.4, 0)
	add_child(o)


## A steel lab workbench: cabinets, glassware, a microscope.
func _make_lab_bench(pos: Vector3) -> void:
	var steel := Color(0.48, 0.51, 0.55)
	_make_box(pos + Vector3(0, 0.9, 0), Vector3(5.0, 0.16, 1.4), steel, "metal")
	_make_box(pos + Vector3(-2.0, 0.45, 0), Vector3(0.8, 0.9, 1.2), steel.darkened(0.2), "metal")
	_make_box(pos + Vector3(2.0, 0.45, 0), Vector3(0.8, 0.9, 1.2), steel.darkened(0.2), "metal")
	for j in 3:
		_make_test_tube(pos + Vector3(_rng.randf_range(-2.0, 2.0), 0.98,
			_rng.randf_range(-0.4, 0.4)), _rng.randf() < 0.3)
	_make_box(pos + Vector3(0.8, 1.14, 0.2), Vector3(0.22, 0.32, 0.22), Color(0.2, 0.2, 0.24), "metal")


## A sealed glass jar with something suspended in fluid.
func _make_specimen_jar(pos: Vector3) -> void:
	var glass := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.14
	cm.bottom_radius = 0.14
	cm.height = 0.36
	glass.mesh = cm
	glass.position = pos + Vector3(0, 0.18, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.7, 0.85, 0.8, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = gm
	add_child(glass)
	var blob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	blob.mesh = sm
	blob.position = pos + Vector3(0, 0.15, 0)
	var bm := StandardMaterial3D.new()
	var c := Color(0.25, 0.6, 0.2) if _rng.randf() < 0.7 else Color(0.55, 0.15, 0.1)
	bm.albedo_color = c
	bm.emission_enabled = true
	bm.emission = c
	bm.emission_energy_multiplier = 0.8
	blob.material_override = bm
	add_child(blob)


## A metal rack whose shelves are lined with glowing specimen jars.
func _make_specimen_shelf(pos: Vector3, along_x: bool) -> void:
	var span := 6.0
	var frame := Color(0.35, 0.37, 0.4)
	for s in [-1.0, 1.0]:
		var off := Vector3(s * (span * 0.5 - 0.1), 1.1, 0) if along_x \
			else Vector3(0, 1.1, s * (span * 0.5 - 0.1))
		_make_box(pos + off, Vector3(0.12, 2.2, 0.12), frame, "metal")
	for lvl in [0.5, 1.2, 1.9]:
		var size := Vector3(span, 0.1, 0.9) if along_x else Vector3(0.9, 0.1, span)
		_make_box(pos + Vector3(0, lvl, 0), size, Color(0.4, 0.42, 0.45), "metal")
		for i in 4:
			var t := (float(i) + 0.5) / 4.0 - 0.5
			var jp := pos + (Vector3(t * span, lvl + 0.05, 0) if along_x \
				else Vector3(0, lvl + 0.05, t * span))
			_make_specimen_jar(jp)


## A humming server cabinet with blinking status LEDs.
func _make_server_rack(pos: Vector3, along_x: bool) -> void:
	var size := Vector3(3.6, 2.6, 0.9) if along_x else Vector3(0.9, 2.6, 3.6)
	_make_box(pos + Vector3(0, 1.3, 0), size, Color(0.10, 0.11, 0.13), "metal")
	for i in 6:
		var t := (float(i) + 0.5) / 6.0 - 0.5
		var lp := pos + (Vector3(t * 3.2, _rng.randf_range(0.4, 2.2), 0.48) if along_x \
			else Vector3(0.48, _rng.randf_range(0.4, 2.2), t * 3.2))
		var led := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.07, 0.07, 0.07)
		led.mesh = lb
		led.position = lp
		var lm := StandardMaterial3D.new()
		var c := Color(0.2, 0.9, 0.3) if _rng.randf() < 0.7 else Color(0.9, 0.6, 0.1)
		lm.albedo_color = c
		lm.emission_enabled = true
		lm.emission = c
		lm.emission_energy_multiplier = 1.8
		led.material_override = lm
		add_child(led)


## A steel operating table, optionally with a sheeted body on it.
func _make_operating_table(pos: Vector3, with_body: bool) -> void:
	var steel := Color(0.68, 0.71, 0.75)
	_make_box(pos + Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.4), steel.darkened(0.3), "metal")
	_make_box(pos + Vector3(0, 0.95, 0), Vector3(2.3, 0.1, 0.95), steel, "metal")
	_make_box(pos + Vector3(1.6, 0.85, 0.4), Vector3(0.6, 0.05, 0.4), steel.lightened(0.1), "metal")
	if not with_body:
		return
	var ty := 1.0
	var torso := MeshInstance3D.new()
	var tc := CapsuleMesh.new()
	tc.radius = 0.24
	tc.height = 1.05
	torso.mesh = tc
	torso.position = pos + Vector3(0, ty + 0.22, 0)
	torso.rotation.z = PI * 0.5
	torso.material_override = _mat(Color(0.72, 0.74, 0.78))
	add_child(torso)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.16
	head.mesh = hm
	head.position = pos + Vector3(-0.72, ty + 0.18, 0)
	head.material_override = _mat(Color(0.5, 0.4, 0.34))
	add_child(head)
	_make_puddle(pos + Vector3(0.3, ty + 0.06, 0), 0.5, Color(0.45, 0.02, 0.01, 0.85))
	_make_puddle(pos + Vector3(0.6, 0.01, 0.7), 0.8, Color(0.4, 0.02, 0.01, 0.7))


## An overhead surgical lamp: bright disc + a pool of light below.
func _make_surgical_light(pos: Vector3) -> void:
	_cosmetic(_make_cylinder_mesh(0.05, 1.2, Color.BLACK), pos + Vector3(0, 0.6, 0), Color(0.1, 0.1, 0.1))
	var head := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 0.14
	head.mesh = cm
	head.position = pos
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.9, 0.92, 0.95)
	hmat.emission_enabled = true
	hmat.emission = Color(0.95, 0.97, 1.0)
	hmat.emission_energy_multiplier = 1.6
	head.material_override = hmat
	add_child(head)
	var o := OmniLight3D.new()
	o.light_color = Color(0.95, 0.97, 1.0)
	o.light_energy = 1.6
	o.omni_range = 10.0
	o.position = pos - Vector3(0, 1.0, 0)
	add_child(o)


## A wheeled gurney, optionally with a sheet-covered occupant.
func _make_gurney(pos: Vector3, with_body: bool) -> void:
	var steel := Color(0.6, 0.63, 0.67)
	_make_box(pos + Vector3(0, 0.85, 0), Vector3(2.0, 0.08, 0.8), steel, "metal")
	for sx in [-0.8, 0.8]:
		_make_box(pos + Vector3(sx, 0.42, 0), Vector3(0.08, 0.85, 0.6), steel.darkened(0.25), "metal")
	if with_body:
		_make_box(pos + Vector3(0, 1.03, 0), Vector3(1.7, 0.3, 0.6), Color(0.8, 0.8, 0.83))
		_make_puddle(pos + Vector3(0.4, 1.2, 0.1), 0.3, Color(0.45, 0.02, 0.01, 0.8))


## A wall of morgue drawers; one is left open with the slab pulled out.
func _make_morgue_drawers(pos: Vector3) -> void:
	var steel := Color(0.55, 0.58, 0.62)
	_make_box(pos + Vector3(0, 1.6, 0), Vector3(12.0, 3.2, 1.4), steel.darkened(0.25), "metal")
	for cxi in 5:
		for ryi in 3:
			var face := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(2.0, 0.85, 0.06)
			face.mesh = fb
			face.position = Vector3(pos.x - 4.8 + cxi * 2.4, 0.65 + ryi * 1.05, pos.z - 0.75)
			face.material_override = _mat(steel)
			add_child(face)
	_make_box(pos + Vector3(-2.4, 0.55, -2.2), Vector3(1.9, 0.12, 2.2), steel.lightened(0.1), "metal")
	_make_puddle(pos + Vector3(-2.4, 0.62, -2.4), 0.5, Color(0.45, 0.02, 0.01, 0.85))


## A vending machine with a glowing front (still running on backup power).
func _make_vending_machine(pos: Vector3) -> void:
	_make_box(pos + Vector3(0, 1.05, 0), Vector3(1.2, 2.1, 0.9), Color(0.15, 0.16, 0.2), "metal")
	var front := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.9, 1.5, 0.05)
	front.mesh = fb
	front.position = pos + Vector3(0, 1.25, -0.48)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.5, 0.8)
	fm.emission_enabled = true
	fm.emission = Color(0.25, 0.45, 0.8)
	fm.emission_energy_multiplier = 1.2
	front.material_override = fm
	add_child(front)


## A security scanner arch with a blinking status lamp.
func _make_security_arch(pos: Vector3) -> void:
	var dark := Color(0.2, 0.21, 0.25)
	for s in [-1.5, 1.5]:
		_make_box(pos + Vector3(s, 1.25, 0), Vector3(0.35, 2.5, 0.5), dark, "metal")
	_cosmetic(_box_mesh(Vector3(3.4, 0.35, 0.5)), pos + Vector3(0, 2.65, 0), dark)
	_make_emissive_sphere(pos + Vector3(0, 2.55, 0.3), 0.07, Color(0.9, 0.15, 0.1))


## A banquet-length dining table with chairs down both sides and candelabra.
func _make_long_table(pos: Vector3, length: float, wood: Color) -> void:
	_make_box(pos + Vector3(0, 1.0, 0), Vector3(2.6, 0.14, length), wood, "wood")
	for s in [-1.0, 1.0]:
		_make_box(pos + Vector3(0, 0.5, s * (length * 0.5 - 0.6)), Vector3(2.2, 1.0, 0.3), wood.darkened(0.2))
	var zc := -length * 0.5 + 1.5
	while zc <= length * 0.5 - 1.5:
		for s in [-1.0, 1.0]:
			_make_box(pos + Vector3(s * 1.8, 0.55, zc), Vector3(0.55, 1.1, 0.55), wood.darkened(0.1), "wood")
		zc += 2.2
	for czz in [-length * 0.25, 0.0, length * 0.25]:
		_make_emissive_sphere(pos + Vector3(0, 1.45, czz), 0.09, Color(1.0, 0.78, 0.4))


## A run of kitchen counters with a worktop and pots.
func _make_kitchen_counter(pos: Vector3, along_x: bool, length: float) -> void:
	var top := Color(0.62, 0.60, 0.55)
	var body := Color(0.32, 0.22, 0.14)
	var size := Vector3(length, 0.95, 1.1) if along_x else Vector3(1.1, 0.95, length)
	_make_box(pos + Vector3(0, 0.475, 0), size, body, "wood")
	var tsize := Vector3(length + 0.1, 0.08, 1.2) if along_x else Vector3(1.2, 0.08, length + 0.1)
	_make_box(pos + Vector3(0, 0.99, 0), tsize, top)
	for i in 3:
		var t := (float(i) + 0.5) / 3.0 - 0.5
		var off := Vector3(t * length, 1.12, 0) if along_x else Vector3(0, 1.12, t * length)
		_cosmetic(_make_cylinder_mesh(0.16, 0.18, Color.BLACK), pos + off, Color(0.25, 0.26, 0.28))


## A simple bed: frame, mattress, pillow, headboard.
func _make_bed(pos: Vector3, along_x: bool, blanket: Color) -> void:
	var wood := Color(0.3, 0.2, 0.12)
	var size := Vector3(2.2, 0.45, 1.2) if along_x else Vector3(1.2, 0.45, 2.2)
	_make_box(pos + Vector3(0, 0.225, 0), size, wood, "wood")
	var msize := Vector3(2.0, 0.22, 1.05) if along_x else Vector3(1.05, 0.22, 2.0)
	_make_box(pos + Vector3(0, 0.56, 0), msize, blanket)
	var poff := Vector3(-0.75, 0.72, 0) if along_x else Vector3(0, 0.72, -0.75)
	_cosmetic(_box_mesh(Vector3(0.5, 0.14, 0.6) if along_x else Vector3(0.6, 0.14, 0.5)),
		pos + poff, Color(0.88, 0.86, 0.8))
	var hoff := Vector3(-1.15, 0.55, 0) if along_x else Vector3(0, 0.55, -1.15)
	_make_box(pos + hoff, Vector3(0.12, 1.1, 1.2) if along_x else Vector3(1.2, 1.1, 0.12), wood, "wood")


## A grand piano (lid open) with its bench.
func _make_piano(pos: Vector3) -> void:
	var black := Color(0.08, 0.08, 0.09)
	_make_box(pos + Vector3(0, 0.95, 0), Vector3(2.6, 1.0, 1.5), black)
	_make_box(pos + Vector3(0, 0.78, 1.0), Vector3(2.2, 0.10, 0.5), Color(0.9, 0.88, 0.82))
	_make_box(pos + Vector3(0, 0.3, 1.7), Vector3(1.2, 0.6, 0.5), black.lightened(0.08))
	_cosmetic(_box_mesh(Vector3(2.4, 0.06, 1.3)), pos + Vector3(0, 1.5, -0.2), black.lightened(0.05))


## A tall double-sided library stack with coloured book spines.
func _make_bookshelf_row(pos: Vector3, length: float) -> void:
	var wood := Color(0.3, 0.2, 0.12)
	_make_box(pos + Vector3(0, 2.0, 0), Vector3(1.0, 4.0, length), wood, "wood")
	var pal: Array = PALETTES[Style.MANSION]
	for side in [-0.53, 0.53]:
		var zc := -length * 0.5 + 0.8
		while zc < length * 0.5 - 0.4:
			var bcol: Color = pal[_rng.randi() % pal.size()]
			_cosmetic(_box_mesh(Vector3(0.06, _rng.randf_range(0.5, 0.9), _rng.randf_range(0.5, 1.1))),
				pos + Vector3(side, _rng.randf_range(0.6, 3.4), zc), bcol.lightened(0.1))
			zc += _rng.randf_range(0.9, 1.6)


## A marble pedestal topped with a faintly glowing gold cup.
func _make_trophy_pedestal(pos: Vector3) -> void:
	var marble := Color(0.8, 0.78, 0.72)
	_make_box(pos + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 0.9), marble, "concrete")
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.12
	cm.height = 0.5
	cup.mesh = cm
	cup.position = pos + Vector3(0, 1.5, 0)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.85, 0.7, 0.25)
	gmat.metallic = 0.9
	gmat.roughness = 0.2
	gmat.emission_enabled = true
	gmat.emission = Color(0.5, 0.4, 0.1)
	gmat.emission_energy_multiplier = 0.4
	cup.material_override = gmat
	add_child(cup)


## A glass display case whose weapon mount is conspicuously EMPTY.
func _make_display_case(pos: Vector3) -> void:
	_make_box(pos + Vector3(0, 0.55, 0), Vector3(1.6, 1.1, 1.0), Color(0.26, 0.17, 0.11), "wood")
	var glass := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(1.4, 0.8, 0.85)
	glass.mesh = gb
	glass.position = pos + Vector3(0, 1.5, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.75, 0.85, 0.9, 0.22)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = gm
	add_child(glass)
	_cosmetic(_box_mesh(Vector3(0.8, 0.06, 0.3)), pos + Vector3(0, 1.18, 0), Color(0.45, 0.08, 0.08))


## A mounted hunting trophy on a wall plaque.
func _make_mounted_head(pos: Vector3) -> void:
	_cosmetic(_box_mesh(Vector3(0.9, 1.1, 0.1)), pos, Color(0.26, 0.17, 0.11))
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	_cosmetic(head, pos + Vector3(0, 0.05, -0.28), Color(0.32, 0.24, 0.16))


## A stacked firewood pile (cosmetic logs + one invisible collider).
func _make_log_pile(pos: Vector3) -> void:
	var bark := Color(0.33, 0.23, 0.14)
	for row in 3:
		for i in 4 - row:
			var mi := MeshInstance3D.new()
			mi.mesh = _make_cylinder_mesh(0.22, 1.8, bark)
			mi.position = pos + Vector3(-0.66 + i * 0.44 + row * 0.22, 0.22 + row * 0.4, 0)
			mi.rotation.x = PI * 0.5
			mi.material_override = _mat(bark.darkened(_rng.randf_range(0.0, 0.15)), "wood")
			add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos + Vector3(0, 0.6, 0)
	add_child(body)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.0, 1.2, 1.9)
	shape.shape = bx
	body.add_child(shape)


## A wooden lantern post with a warm flickering flame.
func _make_lantern_post(pos: Vector3) -> void:
	_make_cylinder(pos + Vector3(0, 1.6, 0), 0.09, 3.2, Color(0.2, 0.16, 0.12), "wood")
	_make_emissive_sphere(pos + Vector3(0, 3.1, 0), 0.14, Color(1.0, 0.7, 0.35))
	var o: OmniLight3D = FLICKER_SCRIPT.new()
	o.light_color = Color(1.0, 0.66, 0.3)
	o.light_energy = 1.4
	o.omni_range = 13.0
	o.position = pos + Vector3(0, 3.0, 0)
	add_child(o)


## A sodium streetlight; a few in every city are on their way out.
func _make_streetlight(pos: Vector3, arm_dir := Vector3(1, 0, 0)) -> void:
	var pole := Color(0.16, 0.17, 0.19)
	_make_cylinder(pos + Vector3(0, 3.0, 0), 0.12, 6.0, pole, "metal")
	var head_pos := pos + arm_dir * 1.6 + Vector3(0, 5.9, 0)
	_cosmetic(_box_mesh(Vector3(absf(arm_dir.x) * 1.6 + 0.12, 0.12, absf(arm_dir.z) * 1.6 + 0.12)),
		pos + arm_dir * 0.8 + Vector3(0, 5.9, 0), pole)
	var lamp := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.5, 0.14, 0.3)
	lamp.mesh = lb
	lamp.position = head_pos
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1.0, 0.75, 0.4)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.68, 0.3)
	lmat.emission_energy_multiplier = 1.8
	lamp.material_override = lmat
	add_child(lamp)
	var o: OmniLight3D
	if _rng.randf() < 0.3:
		o = FLICKER_SCRIPT.new()
	else:
		o = OmniLight3D.new()
	o.light_color = Color(1.0, 0.62, 0.25)
	o.light_energy = 1.6
	o.omni_range = 18.0
	o.position = head_pos - Vector3(0, 0.4, 0)
	add_child(o)


## An abandoned parked car (body + cabin + wheels).
func _make_city_car(pos: Vector3, along_x: bool, col: Color) -> void:
	var body_size := Vector3(4.2, 0.9, 1.9) if along_x else Vector3(1.9, 0.9, 4.2)
	_make_box(pos + Vector3(0, 0.75, 0), body_size, col, "metal")
	var cab_size := Vector3(2.1, 0.7, 1.7) if along_x else Vector3(1.7, 0.7, 2.1)
	_make_box(pos + Vector3(0, 1.55, 0), cab_size, col.darkened(0.35), "metal")
	for sa in [-1.4, 1.4]:
		for sb in [-0.95, 0.95]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = _make_cylinder_mesh(0.38, 0.3, Color.BLACK)
			wheel.position = pos + (Vector3(sa, 0.38, sb) if along_x else Vector3(sb, 0.38, sa))
			wheel.rotation = Vector3(PI * 0.5, 0, 0) if along_x else Vector3(0, 0, PI * 0.5)
			wheel.material_override = _mat(Color(0.06, 0.06, 0.07))
			add_child(wheel)


## An alley dumpster with a skewed lid.
func _make_dumpster(pos: Vector3) -> void:
	var green := Color(0.16, 0.3, 0.18)
	_make_box(pos + Vector3(0, 0.75, 0), Vector3(2.4, 1.5, 1.4), green, "metal")
	_cosmetic(_box_mesh(Vector3(2.5, 0.1, 1.5)), pos + Vector3(0.2, 1.62, 0), green.darkened(0.2),
		Vector3(0, 0, 0.12))


## A store gondola shelf stocked with colourful product boxes.
func _make_store_shelf(pos: Vector3, along_x: bool, length: float) -> void:
	var frame := Color(0.75, 0.75, 0.78)
	var size := Vector3(length, 1.8, 0.9) if along_x else Vector3(0.9, 1.8, length)
	_make_box(pos + Vector3(0, 0.9, 0), size, frame, "metal")
	var pal: Array = PALETTES[Style.CITY]
	for i in int(length):
		var t := (float(i) + 0.5) / length - 0.5
		for lvl in [0.5, 1.0, 1.5]:
			if _rng.randf() < 0.6:
				var off := Vector3(t * length, lvl + 0.14, 0.52) if along_x \
					else Vector3(0.52, lvl + 0.14, t * length)
				_cosmetic(_box_mesh(Vector3(0.5, 0.26, 0.12) if along_x else Vector3(0.12, 0.26, 0.5)),
					pos + off, (pal[_rng.randi() % pal.size()] as Color).lightened(0.25))


## A buzzing neon sign: glowing text + a coloured pool of light.
func _make_neon_sign(pos: Vector3, text: String, color: Color, rot: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.01
	l.position = pos
	l.rotation = rot
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = color.darkened(0.7)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = true
	add_child(l)
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = 1.5
	o.omni_range = 12.0
	o.position = pos
	add_child(o)


# ═════════════════════════════════════════════════════════════════════════════
# CABIN LAYOUT  (style 0 — replaced the old Urban arena)
# ═════════════════════════════════════════════════════════════════════════════

## Cabin in the woods: a lamplit log cabin in a clearing, ringed by dense dark
## forest, with a woodshed, an outhouse, a well and a root cellar. The hunter
## wakes up in the main room by the fireplace.
func _build_cabin_layout() -> void:
	var log_col := Color(0.36, 0.24, 0.14)
	var timber := Color(0.28, 0.18, 0.11)
	var stone := Color(0.42, 0.42, 0.44)
	var wall_h := 4.6

	# ── THE CABIN (centred on the origin) ──
	# Footprint x[-13,13], z[-9,9]: bedroom west, main room centre, kitchen east.
	var cx0 := -13.0
	var cx1 := 13.0
	var cz0 := -9.0
	var cz1 := 9.0
	_plan_wall_z(cz1, cx0, cx1, [[0.0, false]], log_col, "sbswood", wall_h)     # front door (S)
	_plan_wall_z(cz0, cx0, cx1, [[8.0, false]], log_col, "sbswood", wall_h)     # back door → cellar
	_plan_wall_x(cx0, cz0, cz1, [], log_col, "sbswood", wall_h)
	_plan_wall_x(cx1, cz0, cz1, [], log_col, "sbswood", wall_h)
	_plan_wall_x(-5.0, cz0, cz1, [[3.0, true]], timber, "sbswood", wall_h)      # bedroom door
	_plan_wall_x(5.0, cz0, cz1, [[-3.0, true]], timber, "sbswood", wall_h)      # kitchen door
	_make_box(Vector3(0, wall_h + 0.2, 0), Vector3(cx1 - cx0, 0.4, cz1 - cz0), timber.darkened(0.1), "sbswood")
	_cosmetic(_prism(Vector3(cx1 - cx0 + 1.6, 3.2, cz1 - cz0 + 1.6)),
		Vector3(0, wall_h + 2.0, 0), timber.darkened(0.2))

	# Main room: fireplace, rug, seats — the heart of the cabin.
	_make_fireplace(Vector3(0.0, 0, cz0 + 0.9), stone)
	_make_carpet(Vector3(0, 0.03, 1.5), Vector2(6.0, 5.0), Color(0.4, 0.22, 0.14))
	_make_sofa(Vector3(-2.6, 0, 4.0), Color(0.35, 0.25, 0.18))
	_make_box(Vector3(2.8, 0.4, 2.5), Vector3(1.4, 0.8, 1.4), timber, "wood")
	_cosmetic(_box_mesh(Vector3(1.6, 0.12, 0.12)), Vector3(0, 3.4, cz0 + 1.6), Color(0.8, 0.75, 0.62))
	_make_sconce(Vector3(0.0, 3.4, 6.0))

	# Bedroom (west end).
	_make_bed(Vector3(-10.5, 0, -4.5), true, Color(0.5, 0.3, 0.25))
	_make_bed(Vector3(-10.5, 0, 4.5), true, Color(0.3, 0.4, 0.45))
	_make_box(Vector3(-6.5, 1.0, -7.6), Vector3(1.6, 2.0, 1.0), timber, "wood")
	_make_sconce(Vector3(-9.0, 3.4, 0.0))
	_make_floor_note(Vector3(-9.0, 0.02, 0.5),
		"Day 6. The thing in the woods\ncircles closer each night.\nI nailed the cellar shut. It knows.")

	# Kitchen (east end).
	_make_kitchen_counter(Vector3(11.9, 0, 0.0), false, 8.0)
	_make_box(Vector3(7.5, 0.75, 6.5), Vector3(2.4, 1.5, 1.4), timber, "wood")
	_make_box(Vector3(6.5, 1.0, -7.6), Vector3(1.4, 2.0, 1.2), Color(0.2, 0.2, 0.22), "metal")
	_make_cylinder(Vector3(6.5, 2.6, -7.6), 0.12, 1.2, Color(0.15, 0.15, 0.17), "metal")
	_make_sconce(Vector3(9.0, 3.4, 0.0))

	# ── ROOT CELLAR (windowless — the cabin's "basement") ──
	_plan_wall_z(-19.0, 3.0, 13.0, [[8.0, true]], stone, "concrete", 3.4)   # outer cellar door
	_plan_wall_x(3.0, -19.0, cz0, [], stone, "concrete", 3.4)
	_plan_wall_x(13.0, -19.0, cz0, [], stone, "concrete", 3.4)
	_make_box(Vector3(8.0, 3.5, -14.0), Vector3(10.0, 0.3, 10.0), stone.darkened(0.2), "concrete")
	_spawn_model(DUN + "/Barrel.obj", Vector3(5.5, 0, -16.5), 1.6, Color(1, 1, 1), 0.4)
	_spawn_model(DUN + "/Crate.obj", Vector3(11.0, 0, -16.0), 1.5, Color(1, 1, 1), 0.4)
	_make_box(Vector3(12.2, 1.0, -12.0), Vector3(0.8, 2.0, 3.0), timber, "wood")
	var cellar_light: OmniLight3D = FLICKER_SCRIPT.new()
	cellar_light.light_color = Color(0.8, 0.75, 0.6)
	cellar_light.light_energy = 0.9
	cellar_light.omni_range = 9.0
	cellar_light.position = Vector3(8.0, 2.8, -14.0)
	add_child(cellar_light)
	_add_gen_spot(Vector3(8.0, 0, -13.5))

	# ── WOODSHED (east of the cabin) ──
	_make_box(Vector3(26.0, 1.6, 10.0), Vector3(7.0, 3.2, 0.4), timber, "sbswood")
	_make_box(Vector3(22.7, 1.6, 13.0), Vector3(0.4, 3.2, 6.0), timber, "sbswood")
	_make_box(Vector3(29.3, 1.6, 13.0), Vector3(0.4, 3.2, 6.0), timber, "sbswood")
	_cosmetic(_prism(Vector3(8.0, 1.8, 7.4)), Vector3(26.0, 4.0, 13.0), timber.darkened(0.25))
	_make_log_pile(Vector3(26.0, 0, 12.0))
	_make_cylinder(Vector3(25.0, 0.35, 15.3), 0.4, 0.7, timber, "wood")   # chopping block
	_add_gen_spot(Vector3(27.6, 0, 14.6))

	# ── OUTHOUSE (northwest path) ──
	_make_box(Vector3(-24.0, 1.4, 16.9), Vector3(2.4, 2.8, 0.3), timber, "sbswood")
	_make_box(Vector3(-25.2, 1.4, 18.0), Vector3(0.3, 2.8, 2.4), timber, "sbswood")
	_make_box(Vector3(-22.8, 1.4, 18.0), Vector3(0.3, 2.8, 2.4), timber, "sbswood")
	_make_box(Vector3(-24.0, 0.4, 17.5), Vector3(1.8, 0.8, 0.9), timber, "wood")
	_cosmetic(_prism(Vector3(3.0, 1.2, 3.0)), Vector3(-24.0, 3.3, 18.0), timber.darkened(0.3))
	_add_door_spot(Vector3(-24.0, 0, 19.1), true, 1.8, false)
	_add_gen_spot(Vector3(-24.0, 0, 23.0))

	# ── WELL (front yard) ──
	_make_cylinder(Vector3(14.0, 0.6, 20.0), 1.2, 1.2, stone, "concrete")
	for s in [-1.0, 1.0]:
		_make_box(Vector3(14.0 + s * 1.1, 1.5, 20.0), Vector3(0.14, 1.8, 0.14), timber, "wood")
	_cosmetic(_prism(Vector3(3.0, 1.0, 3.0)), Vector3(14.0, 2.7, 20.0), timber.darkened(0.3))
	_add_gen_spot(Vector3(14.0, 0, 24.0))

	# ── Yard lanterns + treeline generator spots ──
	_make_lantern_post(Vector3(0.0, 0, 12.5))
	_make_lantern_post(Vector3(18.0, 0, -4.0))
	_make_lantern_post(Vector3(-16.0, 0, 8.0))
	_add_gen_spot(Vector3(-20.0, 0, -16.0))
	_add_gen_spot(Vector3(30.0, 0, -18.0))
	_add_gen_spot(Vector3(0.0, 0, 34.0))
	_add_gen_spot(Vector3(-32.0, 0, 2.0))

	# ── THE DARK FOREST (dense ring outside the clearing) ──
	var green := Color(0.20, 0.36, 0.16)
	var pine := Color(0.16, 0.30, 0.20)
	var dead := Color(0.30, 0.24, 0.17)
	var rock := Color(0.42, 0.43, 0.46)
	var placed := 0
	var attempts := 0
	var used: Array[Vector3] = []
	while placed < 130 and attempts < 2400:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-HALF + 8, HALF - 8), 0,
				_rng.randf_range(-HALF + 8, HALF - 8))
		if pos.length() < 38.0:
			continue
		var too_close := false
		for u in used:
			if u.distance_to(pos) < 4.0:
				too_close = true
				break
		if too_close:
			continue
		used.append(pos)
		var r := _rng.randf()
		if r < 0.46:
			var leafy: bool = _rng.randf() < 0.5
			_spawn_model(_pick(FOREST_TREES), pos, _rng.randf_range(7.0, 14.0),
				pine if leafy else green, 0.12)
		elif r < 0.66:
			_spawn_model(_pick(FOREST_DEAD), pos, _rng.randf_range(6.0, 12.0), dead, 0.10)
		elif r < 0.82:
			_spawn_model(_pick(FOREST_ROCKS), pos, _rng.randf_range(1.4, 4.5), rock, 0.42)
		else:
			_make_foliage(pos, FOLIAGE_BUSHES, 1.6, 3.0, Color(0.18, 0.32, 0.16), 0.45)
		placed += 1
	# Ragged treeline just inside the clearing edge.
	for i in 14:
		var ang := _rng.randf_range(0.0, TAU)
		var rr := _rng.randf_range(28.0, 38.0)
		var p2 := Vector3(cos(ang) * rr, 0, sin(ang) * rr)
		if p2.distance_to(Vector3(26, 0, 13)) < 8.0 or p2.distance_to(Vector3(-24, 0, 18)) < 6.0 \
				or p2.distance_to(Vector3(14, 0, 20)) < 5.0 or p2.distance_to(Vector3(8, 0, -14)) < 8.0:
			continue
		_spawn_model(_pick(FOREST_TREES), p2, _rng.randf_range(7.0, 12.0), Color(0.16, 0.28, 0.16), 0.12)


# ═════════════════════════════════════════════════════════════════════════════
# CITY LAYOUT  (style 12 — new map)
# ═════════════════════════════════════════════════════════════════════════════

## A dead city block at 3 AM: two streets cross at the centre, and each quarter
## holds an enterable building — apartment house (NW), police station (NE),
## convenience store (SW) and a two-level parking garage (SE).
func _build_city_layout() -> void:
	var h := _half
	var brick := Color(0.45, 0.22, 0.18)
	var conc := Color(0.5, 0.51, 0.53)
	var plaster := Color(0.62, 0.60, 0.56)
	var dark := Color(0.22, 0.23, 0.26)
	var pal: Array = PALETTES[Style.CITY]

	# ── STREETS: markings, crosswalks, streetlights, abandoned cars ──
	var lane_x := -h + 8.0
	while lane_x < h - 6.0:
		if absf(lane_x) > 12.0:
			_cosmetic(_box_mesh(Vector3(3.0, 0.02, 0.25)), Vector3(lane_x, 0.03, 0.0), Color(0.75, 0.65, 0.3))
		lane_x += 8.0
	var lane_z := -h + 8.0
	while lane_z < h - 6.0:
		if absf(lane_z) > 12.0:
			_cosmetic(_box_mesh(Vector3(0.25, 0.02, 3.0)), Vector3(0.0, 0.03, lane_z), Color(0.75, 0.65, 0.3))
		lane_z += 8.0
	for i in 5:
		_cosmetic(_box_mesh(Vector3(1.2, 0.02, 2.6)), Vector3(-6.0 + i * 3.0, 0.03, -10.4), Color(0.8, 0.8, 0.8))
		_cosmetic(_box_mesh(Vector3(1.2, 0.02, 2.6)), Vector3(-6.0 + i * 3.0, 0.03, 10.4), Color(0.8, 0.8, 0.8))
	for sx in [-56.0, -28.0, 28.0, 56.0]:
		_make_streetlight(Vector3(sx, 0, -10.5), Vector3(0, 0, 1))
		_make_streetlight(Vector3(sx, 0, 10.5), Vector3(0, 0, -1))
	for sz in [-56.0, -28.0, 28.0, 56.0]:
		_make_streetlight(Vector3(-10.5, 0, sz), Vector3(1, 0, 0))
		_make_streetlight(Vector3(10.5, 0, sz), Vector3(-1, 0, 0))
	_make_city_car(Vector3(-30.0, 0, 4.5), true, pal[3])
	_make_city_car(Vector3(22.0, 0, -4.5), true, pal[1])
	_make_city_car(Vector3(-4.5, 0, -34.0), false, pal[0].lightened(0.1))
	_make_city_car(Vector3(4.5, 0, 30.0), false, pal[4])
	_make_cylinder(Vector3(-11.0, 0.4, 11.0), 0.22, 0.8, Color(0.7, 0.12, 0.1), "metal")   # hydrant
	_make_floor_note(Vector3(2.0, 0.02, 12.5),
		"CITYWIDE ALERT: shelter in place.\nDo NOT approach the infected.\nThey remember how to open doors.")

	# ═══ NW: APARTMENT BUILDING — "THE MARLOWE" ═══
	var aw := -52.0
	var ae := -16.0
	var an := -56.0
	var asx := -20.0
	_plan_wall_z(asx, aw, ae, [[-34.0, false]], brick, "brick", 6.0)          # entrance (street side)
	_plan_wall_z(an, aw, ae, [[-22.0, true]], brick, "brick", 6.0)            # back door
	_plan_wall_x(aw, an, asx, [], brick, "brick", 6.0)
	_plan_wall_x(ae, an, asx, [], brick, "brick", 6.0)
	_make_box(Vector3(-34.0, 6.2, -38.0), Vector3(36.0, 0.4, 36.0), dark, "concrete")   # roof
	# Lobby (front) | two apartments (back), split by a doored wall.
	_plan_wall_z(-38.0, aw, ae, [[-44.0, true], [-24.0, true]], plaster, "concrete", 6.0)
	_plan_wall_x(-34.0, an, -38.0, [], plaster, "concrete", 6.0)
	# Lobby: mailboxes, bench, dying light.
	_make_box(Vector3(-51.2, 1.3, -30.0), Vector3(0.6, 1.6, 6.0), Color(0.55, 0.5, 0.4), "metal")
	_make_sofa(Vector3(-24.0, 0, -35.0), Color(0.3, 0.28, 0.25))
	_make_fluorescent_flicker(Vector3(-34.0, 5.2, -29.0))
	_make_wall_text(Vector3(-34.0, 4.6, asx - 0.6), "THE MARLOWE\nAPARTMENTS", Color(0.75, 0.7, 0.55), Vector3.ZERO)
	_add_gen_spot(Vector3(-42.0, 0, -26.0))
	# Apartment W: bed, wardrobe — and a tenant who never made it out.
	_make_bed(Vector3(-49.0, 0, -52.0), false, Color(0.4, 0.35, 0.3))
	_make_box(Vector3(-36.5, 1.0, -52.5), Vector3(1.6, 2.0, 1.0), Color(0.3, 0.22, 0.15), "wood")
	_make_corpse_prop(Vector3(-44.0, 0, -46.0))
	_make_fluorescent_flicker(Vector3(-43.0, 5.2, -47.0))
	# Apartment E: sofa, TV still hissing static, bed.
	_make_sofa(Vector3(-26.0, 0, -50.0), Color(0.26, 0.3, 0.34))
	_make_box(Vector3(-26.0, 0.9, -44.5), Vector3(1.8, 1.2, 0.4), Color(0.1, 0.1, 0.12), "metal")
	var tv := MeshInstance3D.new()
	var tvb := BoxMesh.new()
	tvb.size = Vector3(1.5, 0.9, 0.05)
	tv.mesh = tvb
	tv.position = Vector3(-26.0, 0.95, -44.7)
	var tvm := StandardMaterial3D.new()
	tvm.albedo_color = Color(0.6, 0.65, 0.7)
	tvm.emission_enabled = true
	tvm.emission = Color(0.5, 0.55, 0.65)
	tvm.emission_energy_multiplier = 0.9
	tv.material_override = tvm
	add_child(tv)
	_make_bed(Vector3(-19.5, 0, -52.0), false, Color(0.45, 0.3, 0.3))
	_make_fluorescent_flicker(Vector3(-25.0, 5.2, -48.0))

	# ═══ NE: POLICE STATION — 13TH PRECINCT ═══
	var pw := 16.0
	var pe := 52.0
	var pn := -52.0
	var ps := -20.0
	_plan_wall_z(ps, pw, pe, [[34.0, false]], conc, "concrete", 6.0)          # front doors
	_plan_wall_z(pn, pw, pe, [], conc, "concrete", 6.0)
	_plan_wall_x(pw, pn, ps, [], conc, "concrete", 6.0)
	_plan_wall_x(pe, pn, ps, [[-36.0, true]], conc, "concrete", 6.0)          # side door
	_make_box(Vector3(34.0, 6.2, -36.0), Vector3(36.0, 0.4, 32.0), dark, "concrete")
	_make_wall_text(Vector3(34.0, 4.8, ps - 0.6), "POLICE — 13TH PRECINCT", Color(0.5, 0.65, 0.9), Vector3.ZERO)
	# Reception desk facing the doors.
	_make_box(Vector3(34.0, 0.6, -26.0), Vector3(5.0, 1.2, 1.2), Color(0.35, 0.28, 0.2), "wood")
	# Office bullpen.
	for dx in [28.0, 34.0, 40.0]:
		for dz in [-34.0, -40.0]:
			_make_desk(Vector3(dx, 0, dz), Color(0.38, 0.3, 0.22))
	_make_terminal(Vector3(34.0, 1.5, -34.5),
		"DISPATCH LOG — 03:12\n\nUnits 4, 7, 9: NO RESPONSE\nRiot at St. Mary's Hospital\nQuarantine line BROKEN\n\n[TRANSMIT FAILED]")
	# Holding cell (SE corner of the station).
	_plan_wall_x(42.0, pn + 1, -42.0, [[-46.5, true]], conc, "concrete", 4.0)
	_make_box(Vector3(47.0, 2.0, -42.0), Vector3(10.0, 4.0, 0.4), conc, "concrete")
	_make_box(Vector3(49.5, 0.35, -48.5), Vector3(2.4, 0.7, 1.1), Color(0.35, 0.36, 0.4), "metal")   # cot
	_make_blood_splatter(Vector3(46.0, 1.6, -50.5), false)
	# Evidence room (SW corner) — the door here never locks (generator inside).
	_plan_wall_x(26.0, pn + 1, -40.0, [[-46.0, false]], conc, "concrete", 6.0)
	_make_box(Vector3(21.0, 2.0, -40.0), Vector3(10.0, 4.0, 0.4), conc, "concrete")
	_spawn_model(DUN + "/Crate.obj", Vector3(18.5, 0, -49.0), 1.5, Color(1, 1, 1), 0.4)
	_make_box(Vector3(24.5, 1.0, -50.5), Vector3(2.6, 2.0, 0.8), Color(0.35, 0.37, 0.4), "metal")
	_add_gen_spot(Vector3(21.0, 0, -45.0))
	_make_fluorescent_flicker(Vector3(34.0, 5.2, -30.0))
	_make_fluorescent_flicker(Vector3(30.0, 5.2, -44.0))
	_add_gen_spot(Vector3(44.0, 0, -30.0))

	# ═══ SW: CONVENIENCE STORE — "24/7 MART" ═══
	var sw := -46.0
	var se := -18.0
	var sn := 20.0
	var ss := 44.0
	_plan_wall_z(sn, sw, se, [[-32.0, false]], brick, "brick", 5.0)           # front door
	_plan_wall_z(ss, sw, se, [], brick, "brick", 5.0)
	_plan_wall_x(sw, sn, ss, [], brick, "brick", 5.0)
	_plan_wall_x(se, sn, ss, [], brick, "brick", 5.0)
	_make_box(Vector3(-32.0, 5.3, 32.0), Vector3(28.0, 0.3, 24.0), dark, "concrete")
	_make_neon_sign(Vector3(-32.0, 4.2, 19.2), "24/7 MART", Color(0.2, 0.95, 0.5), Vector3.ZERO)
	# Counter + register by the door.
	_make_box(Vector3(-42.0, 0.55, 24.0), Vector3(3.0, 1.1, 1.2), Color(0.5, 0.45, 0.4), "wood")
	_cosmetic(_box_mesh(Vector3(0.6, 0.5, 0.5)), Vector3(-42.5, 1.35, 24.0), Color(0.2, 0.2, 0.24))
	# Aisles.
	for i in 3:
		_make_store_shelf(Vector3(-36.0 + i * 6.0, 0, 33.0), false, 12.0)
	# Freezers along the back wall, still glowing.
	for fx in [-40.0, -35.0]:
		_make_vending_machine(Vector3(fx, 0, 42.8))
	# Looted mess.
	for i in 6:
		_cosmetic(_box_mesh(Vector3(0.4, 0.2, 0.3)),
			Vector3(_rng.randf_range(-44.0, -20.0), 0.12, _rng.randf_range(22.0, 42.0)),
			(pal[_rng.randi() % pal.size()] as Color).lightened(0.3))
	_make_fluorescent_flicker(Vector3(-32.0, 4.4, 28.0))
	_make_fluorescent_flicker(Vector3(-32.0, 4.4, 38.0))
	_add_gen_spot(Vector3(-42.0, 0, 39.0))
	# Back alley: dumpsters + graffiti.
	_make_dumpster(Vector3(-42.0, 0, 48.5))
	_make_dumpster(Vector3(-37.0, 0, 49.5))
	_make_wall_text(Vector3(-30.0, 2.2, 44.8), "THEY COME OUT AT NIGHT", Color(0.7, 0.12, 0.1), Vector3.ZERO)
	_add_gen_spot(Vector3(-50.0, 0, 50.0))

	# ═══ SE: PARKING GARAGE (two walkable levels) ═══
	var gx0 := 16.0
	var gx1 := 60.0
	var gz0 := 16.0
	var gz1 := 56.0
	_make_slab(Vector3((gx0 + gx1) * 0.5, 5.4, (gz0 + gz1) * 0.5), Vector2(gx1 - gx0, gz1 - gz0))
	for gx in [20.0, 30.0, 40.0, 50.0, 58.0]:
		for gz in [20.0, 30.0, 40.0, 52.0]:
			_make_box(Vector3(gx, 2.7, gz), Vector3(0.7, 5.4, 0.7), conc, "concrete")
	# Roof parapet (gap on the west edge where the ramp bridge lands).
	_make_box(Vector3((gx0 + gx1) * 0.5, 5.95, gz1), Vector3(gx1 - gx0, 1.1, 0.3), conc, "concrete")
	_make_box(Vector3((gx0 + gx1) * 0.5, 5.95, gz0), Vector3(gx1 - gx0, 1.1, 0.3), conc, "concrete")
	_make_box(Vector3(gx1, 5.95, (gz0 + gz1) * 0.5), Vector3(0.3, 1.1, gz1 - gz0), conc, "concrete")
	_make_box(Vector3(gx0, 5.95, 25.0), Vector3(0.3, 1.1, 18.0), conc, "concrete")
	_make_box(Vector3(gx0, 5.95, 49.0), Vector3(0.3, 1.1, 14.0), conc, "concrete")
	# External ramp up the west face + bridge onto the deck.
	_make_ramp(Vector3(13.0, 0, 52.0), Vector3(0, 0, -1), 5.4, 14.0, 5.0)
	_make_slab(Vector3(14.5, 5.4, 38.0), Vector2(5.0, 6.0))
	# Parked cars, both levels.
	_make_city_car(Vector3(25.0, 0, 24.0), true, pal[2].darkened(0.2))
	_make_city_car(Vector3(35.0, 0, 44.0), false, pal[1])
	_make_city_car(Vector3(48.0, 0, 30.0), true, pal[3])
	_make_city_car(Vector3(30.0, 5.4, 24.0), true, pal[0].lightened(0.15))
	_make_city_car(Vector3(44.0, 5.4, 36.0), false, pal[4].darkened(0.1))
	_make_fluorescent_flicker(Vector3(30.0, 4.6, 30.0))
	_make_fluorescent_flicker(Vector3(45.0, 4.6, 44.0))
	_make_wall_text(Vector3(38.0, 3.0, gz0 + 0.6), "PARKING — LEVEL 1", Color(0.8, 0.6, 0.15), Vector3.ZERO)
	_add_gen_spot(Vector3(25.0, 0, 36.0))
	_add_gen_spot(Vector3(52.0, 0, 22.0))

	# One more generator spot out on the open street corner.
	_add_gen_spot(Vector3(12.0, 0, -12.0))
