class_name BloodRainStreakLayer
extends RefCounted
## One camera-facing quad batch. No physics, mass, slot references or trail history.
var layer: BloodMultiMeshLayer
var slots := PackedInt32Array()
var drop_ids := PackedInt64Array()
var count := 0
var previous_count := 0
var peak := 0
var last_transform := Transform3D.IDENTITY
const HIDDEN := Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)

func setup(parent: Node3D, capacity: int) -> void:
	if layer != null: return
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://presentation/gore/blood_rain_streak.gdshader")
	layer = BloodMultiMeshLayer.new()
	layer.name = "RainStreakBatch"
	parent.add_child(layer)
	layer.setup(mesh,material,clampi(capacity,1,192))
	slots.resize(layer.capacity); drop_ids.resize(layer.capacity)
	for i in slots.size(): slots[i]=layer.acquire(false)
	drop_ids.fill(-1)

func begin() -> void:
	previous_count=count; count=0

static func transform_for(pos: Vector3, velocity: Vector3, camera: Vector3, camera_right: Vector3, size: Vector2) -> Transform3D:
	var axis := velocity.normalized()
	var right := axis.cross(camera-pos)
	if right.length_squared()<0.00001: right=camera_right.slide(axis)
	if right.length_squared()<0.00001: right=axis.cross(Vector3.UP if absf(axis.y)<0.95 else Vector3.RIGHT)
	right=right.normalized()
	return Transform3D(Basis(right*size.x,axis*size.y,right.cross(axis).normalized()),pos-axis*size.y*0.5)

func write(pos: Vector3, velocity: Vector3, camera: Vector3, camera_right: Vector3, size: Vector2, color: Color, drop: int) -> bool:
	if count>=slots.size() or size.y<=0: return false
	last_transform=transform_for(pos,velocity,camera,camera_right,size)
	drop_ids[count]=drop
	layer.write(slots[count],last_transform,color,Color(0,0,1,0))
	count+=1; peak=maxi(peak,count)
	return true

func finish() -> void:
	for i in range(count,previous_count):
		layer.write(slots[i],HIDDEN,Color(0,0,0,0),Color(0,0,0,0))
		drop_ids[i]=-1

func clear() -> void:
	begin(); finish()
