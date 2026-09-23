extends Node3D

## DEVELOPER RENDER FIXTURE for the stain pipeline.
##
##     godot --path . res://tests/blood_render_fixture.tscn
##
## Two rows on a flat white floor, viewed from above:
##
##   ROW 1  every atlas variant at the SAME quad size. They must look like
##          DIFFERENT SHAPES. Before Phase 2.3 they all rendered as TINY_DROP,
##          because nothing consumed the per-instance atlas index, and this row
##          would have been seven identical dots.
##
##   ROW 2  one variant at requested visible footprints of 5, 10, 20, 40 and
##          80 cm, with a white ruler bar of exactly that length beside each.
##          The INK should match the bar, not the quad.
##
## This is meant to be LOOKED AT. It runs windowed, not headless, because the
## thing being checked is pixels. The headless suite checks the maths that feeds
## it; this checks that the maths reaches the screen.

const SETTINGS := "res://data/blood/blood_settings.tres"
const RESERVOIR := "res://data/blood/reservoir_defaults.tres"

const VARIANT_NAMES := [
	"TINY_DROP", "MEDIUM_ROUND", "LARGE_IRREGULAR", "ELONGATED",
	"STREAK", "CLUSTER", "POOLED",
]
## Requested VISIBLE diameters for the calibration row, in metres.
const SIZES := [0.05, 0.10, 0.20, 0.40, 0.80]

var _blood: BloodSystem


func _ready() -> void:
	_build_room()
	_blood = BloodSystem.new()
	_blood.settings = (load(SETTINGS) as BloodSettings).duplicate()
	_blood.fallback_reservoir = load(RESERVOIR)
	_blood.profiles.assign([
		load("res://data/blood/blood_ballistic.tres"),
		load("res://data/blood/blood_slashing.tres"),
		load("res://data/blood/blood_piercing.tres"),
		load("res://data/blood/blood_blunt.tres"),
		load("res://data/blood/blood_high_energy.tres"),
	])
	add_child(_blood)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_lay_variants()
	_lay_sizes()
	_report()


func _build_room() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40, 1, 40)
	mesh.mesh = plane
	mesh.position = Vector3(0, -0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.93, 0.95)
	mat.roughness = 1.0
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, -30, 0)
	sun.light_energy = 1.0
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.2, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	# Straight down, so the marks are seen at their true proportions.
	var cam := Camera3D.new()
	cam.position = Vector3(0, 9.0, 0.5)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.fov = 70.0
	cam.current = true
	add_child(cam)


## ROW 1: every variant, identical quad size. Must read as different shapes.
func _lay_variants() -> void:
	var profile: BloodProfile = load("res://data/blood/blood_ballistic.tres")
	var x := -4.2
	for shape in BloodTypes.STAIN_COUNT:
		_blood.place_variant_for_test(profile, Vector3(x, 0.0, -1.6), shape, 0.55)
		_label(VARIANT_NAMES[shape], Vector3(x, 0.02, -2.6), 0.22)
		x += 1.4


## ROW 2: requested visible footprints, each next to a ruler of that exact
## length. The INK is what should match the ruler.
func _lay_sizes() -> void:
	var profile: BloodProfile = load("res://data/blood/blood_blunt.tres")
	var x := -3.6
	for size in SIZES:
		var d: float = size
		_blood.place_variant_for_test(
			profile, Vector3(x, 0.0, 1.8), int(BloodTypes.Stain.LARGE_IRREGULAR), d
		)
		_ruler(Vector3(x, 0.006, 2.6), d)
		_label("%d cm" % int(d * 100.0), Vector3(x, 0.02, 3.1), 0.2)
		x += 1.8


## A plain white bar of exactly `length` metres, to measure the ink against.
func _ruler(at: Vector3, length: float) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.004, 0.05)
	mi.mesh = box
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)


func _label(text: String, at: Vector3, size: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size * 0.01
	l.position = at
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.modulate = Color(0.1, 0.1, 0.12)
	add_child(l)


func _report() -> void:
	print("")
	print("=== BLOOD RENDER FIXTURE ===")
	print("Top row: all %d atlas variants at the SAME quad size." % BloodTypes.STAIN_COUNT)
	print("They must look like DIFFERENT SHAPES. Identical dots = atlas bug.")
	print("")
	print("MEASURED ATLAS OCCUPANCY (visible ink as a fraction of its cell)")
	for shape in BloodTypes.STAIN_COUNT:
		var occ: Vector2 = _blood.atlas_occupancy(shape)
		var quad: Vector2 = _blood.quad_for_visible_diameter(0.20, shape)
		print("  %-16s ink %.2f x %.2f of cell | fill %.3f | quad for 20 cm ink: %.3f m"
			% [VARIANT_NAMES[shape], occ.x, occ.y, _blood.atlas_fill(shape), quad.x])
	print("")
	print("Bottom row: requested visible footprints with a ruler of that length.")
	print("The INK should match the white bar, not the quad.")
