extends MultiMeshInstance3D

## Reference lines on the floor. Without them a big grey box gives the eye
## nothing to measure speed against, which makes bunnyhop impossible to judge.
##
## One MultiMesh, one draw call, no collision, unshaded. Effectively free.

@export var extent := 36.0
@export var spacing := 8.0
@export var line_width := 0.16
@export var color := Color(0.5, 0.53, 0.6)
## Sits just above the floor surface so nothing z-fights - but BELOW every blood
## layer, which is the whole point of how low this is.
##
## It used to be a 10 mm tall box at 15 mm, occupying y 0.010 to 0.020. Blood
## detail sits at BloodSettings.surface_offset (12 mm) and soaked bases at 4 mm,
## so these opaque strips ran straight through the blood layer and hid it. The
## grid is diagnostic decoration; it must never occlude the thing being
## diagnosed. Collision is untouched - this geometry has none.
@export var height := 0.002
## Deliberately almost flat, so there is no side face to stand proud of a stain.
@export var thickness := 0.0006


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(line_width, thickness, extent * 2.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat

	var per_axis := int(extent * 2.0 / spacing) + 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = per_axis * 2

	var i := 0
	for n in per_axis:
		var p := -extent + n * spacing
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p, height, 0.0)))
		i += 1
	for n in per_axis:
		var p := -extent + n * spacing
		mm.set_instance_transform(
			i, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, height, p))
		)
		i += 1

	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
