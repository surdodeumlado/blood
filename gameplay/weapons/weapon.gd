class_name Weapon
extends Node3D

## Minimal shared contract for the THE_BOX weapon lab.
##
## This is NOT the game's weapon system. It exists so that four test
## instruments can sit in fixed slots and prove four BloodProfiles, and it is
## deliberately thin: a name, a damage family, an impact energy, and one place
## where a resolved hit turns into damage plus a BloodContext.
##
## The whole point of the base class is that no weapon ever spawns a particle.
## A weapon describes WHAT it did; BloodSystem decides how that looks. Changing
## how slashing looks means editing a .tres, never editing the cleaver.

signal hit_confirmed(zone: StringName)
signal enemy_killed(zone: StringName)

const ZONE_BODY := &"body"
const ZONE_HEAD := &"head"

@export var display_name := "WEAPON"
## The blood family this instrument produces. Drives which BloodProfile is used.
@export var damage_type: BloodTypes.DamageType = BloodTypes.DamageType.BALLISTIC
## Normalised impact energy handed to the blood context.
@export var impact_energy := 1.0

var config: CombatConfig
var active := false

var _camera: FirstPersonCamera
var _shooter: CollisionObject3D
var _blood: BloodSystem
var _rng := RandomNumberGenerator.new()


func setup(camera: FirstPersonCamera, shooter: CollisionObject3D, combat: CombatConfig) -> void:
	_camera = camera
	_shooter = shooter
	config = combat
	_on_setup()


## Shown or hidden. Cooldowns deliberately keep running while holstered, so
## switching away and back can never be used to skip one, and switching can
## never hand a fresh weapon someone else's timer.
func set_active(value: bool) -> void:
	active = value
	visible = value
	_on_active_changed(value)


func ready_to_attack() -> bool:
	return true


func try_attack() -> void:
	pass


## Hook points for subclasses.
func _on_setup() -> void:
	pass


func _on_active_changed(_value: bool) -> void:
	pass


# --------------------------------------------------------------------------
# Shared hit resolution. Every weapon funnels through this.
# --------------------------------------------------------------------------

## Returns true if the target died. Applies damage, then describes the impact
## to the blood system. No subclass touches particles.
func apply_hit(
	collider: Object,
	point: Vector3,
	direction: Vector3,
	normal: Vector3,
	zone: StringName,
	damage: float,
	energy_scale := 1.0,
	shape_context := Callable()
) -> bool:
	if collider == null or not collider.has_method("take_damage"):
		return false
	# A corpse still has take_damage(). Anything that cannot be hurt is not a hit.
	if collider.has_method("is_damageable") and not collider.is_damageable():
		return false

	var killed: bool = collider.take_damage(damage, point, direction, zone)
	var blood := _blood_system()
	if blood != null:
		var ctx := BloodContext.make(
			damage_type, point, direction, _region_for(zone), impact_energy * energy_scale
		)
		ctx.surface_normal_ws = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.ZERO
		ctx.is_kill = killed
		if collider.has_method("overkill_ratio"):
			ctx.overkill = collider.overkill_ratio()
		# The only place a weapon may add to the description of its own impact:
		# a swing plane, a blast direction. It still describes WHAT happened and
		# never HOW it looks.
		if shape_context.is_valid():
			shape_context.call(ctx)

		# THE MASS DECISION BELONGS TO THE BODY, not to the weapon. The victim's
		# reservoir says how much material actually left it - which is why the
		# second hit on the same target is genuinely smaller than the first, and
		# why a maul kill is catastrophic without the maul knowing anything
		# about particles. A target with no reservoir falls back to an estimate.
		var reservoir: BloodReservoir = null
		if collider.has_method("blood_reservoir"):
			reservoir = collider.blood_reservoir()
		var release: BloodRelease
		if reservoir != null:
			release = reservoir.withdraw(ctx)
			if killed:
				# The corpse is about to be hidden, so the wound this blow opens
				# finishes its life in world space as a remnant.
				var w := reservoir.open_wound(release)
				if w != null:
					blood.add_remnant(w, point)
			else:
				reservoir.open_wound(release)
		else:
			release = blood.estimate_release(ctx)
		blood.release(release)

	hit_confirmed.emit(zone)
	if killed:
		enemy_killed.emit(zone)
	return killed


## Overlap query against hurtboxes. Used by the melee instruments so that
## connecting while moving fast is easy, instead of depending on one thin ray.
func overlap_hurtboxes(shape: Shape3D, transform: Transform3D) -> Array[Dictionary]:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = transform
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = config.hurtbox_layer
	params.exclude = [_shooter.get_rid()]
	var raw := _camera.get_world_3d().direct_space_state.intersect_shape(params, 16)
	var out: Array[Dictionary] = []
	out.assign(raw)
	return out


## One damageable target per victim: a sweep that overlaps both the body and the
## head hurtbox must not deal damage twice.
func unique_targets(hits: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for hit in hits:
		var area = hit.get("collider")
		if area == null or not area.has_method("take_damage"):
			continue
		if area.has_method("is_damageable") and not area.is_damageable():
			continue
		var zone: StringName = area.hit_zone(0) if area.has_method("hit_zone") else ZONE_BODY
		var owner_id := _victim_id(area)
		# Prefer the head when a sweep catches both.
		if not best.has(owner_id) or zone == ZONE_HEAD:
			best[owner_id] = {"area": area, "zone": zone}
	return best


## The VICTIM, not the hurtbox that was struck.
##
## A hurtbox answers is_damageable() on its owner's behalf, so walking up until
## something answers that question stopped at the hurtbox itself - and a sweep
## catching a body AND a head counted them as two separate victims. The second
## one then took secondary damage, which killed targets in a single swing.
func _victim_id(area: Object) -> int:
	if area.has_method("damage_owner"):
		var owner_node = area.damage_owner()
		if owner_node != null:
			return (owner_node as Object).get_instance_id()
	var node := (area as Node).get_parent()
	while node != null:
		if node.has_method("take_damage"):
			return node.get_instance_id()
		node = node.get_parent()
	return area.get_instance_id()



## The real contact point on a hurtbox, at the height of the region that was
## actually hit. A hurtbox NODE reports its owner's origin - the feet - so
## anything that resolves hits by overlap rather than by ray must ask for this
## instead, or head blood is born on the floor.
func wound_point_of(area: Object, from_ws: Vector3, direction_ws: Vector3) -> Vector3:
	if area != null and area.has_method("wound_point"):
		return area.wound_point(from_ws, direction_ws)
	return (area as Node3D).global_position if area is Node3D else from_ws

func _region_for(zone: StringName) -> BloodTypes.BodyRegion:
	match zone:
		ZONE_HEAD:
			return BloodTypes.BodyRegion.HEAD
		&"limb":
			return BloodTypes.BodyRegion.LIMB
		_:
			return BloodTypes.BodyRegion.TORSO


func camera() -> FirstPersonCamera:
	return _camera


## Resolved lazily: the blood system belongs to the world, not to the weapon,
## and a scene without one simply produces no blood rather than crashing.
func _blood_system() -> BloodSystem:
	if _blood == null or not is_instance_valid(_blood):
		_blood = BloodSystem.find(get_tree())
	return _blood
