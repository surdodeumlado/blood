class_name MeleeWeapon
extends Weapon

## Placeholder melee: a volumetric sweep resolved with one overlap query.
## Twin Daggers and the Maul are the same code with different numbers, different
## rigs and a different damage family - the blood tells them apart, not the
## attack logic.
##
## Three things this file is careful about:
##   1. ONE motion per attack. Wind-up, swing, follow-through, recovery. The
##      recovery must never retrace the swing, or it reads as a second strike.
##   2. One damage event per victim per swing, tracked in a per-swing set, with
##      the first victim taking the full hit and the rest taking a fraction.
##   3. Cast-off: a weapon that has touched blood throws some of it off along
##      the next swing arc. Presentation only.

@export var reach := 1.9
@export var radius := 0.85
@export var swing_time := 0.42
@export var damage_body := 55.0
@export var damage_head := 110.0
## Damage dealt to every target after the first in the SAME swing, as a
## fraction of that target's max health.
@export_range(0.0, 1.0) var secondary_health_fraction := 0.5
## Fallback when a target cannot report its max health.
@export var secondary_damage_fallback := 50.0
@export var knockback_scale := 1.0
@export var swing_arc := 110.0
## Alternate side (and rig) each attack.
@export var alternating := false
## Metres the rig travels across the screen during the swing.
@export var swing_travel := 0.35
@export var windup_travel := 0.12
## How far through the attack the damage lands. The sweep should resolve at the
## moment the weapon is crossing in front of the player, not on the wind-up.
@export_range(0.05, 0.95) var contact_at := 0.32
## How much of the player's FACING mixes into the swing tangent to form the
## momentum axis. 0 = purely lateral swing, 1 = purely a thrust forward. A
## blade cuts mostly across; a heavy head drives more through.
@export_range(0.0, 1.5) var momentum_forward_bias := 0.45

@export_group("Cast-off")
## Blood picked up per connecting hit, capped at 1.0. Spent over later swings.
@export var blood_load_per_hit := 0.6
## Droplets thrown per swing at full load.
@export var castoff_droplets := 7
## Fraction of the load spent by one swing.
@export_range(0.0, 1.0) var castoff_spend := 0.5

var blood_load := 0.0
## Actual world-space motion of the weapon tip, sampled between render frames.
## Cast-off leaves the blade along the direction it is REALLY travelling rather
## than along a camera-left/right approximation.
var tip_velocity := Vector3.ZERO
var _last_tip := Vector3.ZERO
var _have_tip := false
## Debug readouts for the smoke test.
var last_sweep_overlaps := -1
var last_sweep_targets := -1
var contact_count := 0

var _cooldown := 0.0
var _swing := 0.0
var _side := 1.0
var _contact_done := false
var _swing_hits: Dictionary = {}
var _posed_rest := true
var _rig_rest: Transform3D
var _alt_rest: Transform3D

@onready var _rig: Node3D = $Rig
@onready var _rig_alt: Node3D = get_node_or_null("RigAlt")


func _on_setup() -> void:
	_rig_rest = _rig.transform
	if _rig_alt != null:
		_alt_rest = _rig_alt.transform
	_rng.seed = hash(display_name)


## Gameplay clock and hit resolution. This lives in _physics_process because the
## sweep is a shape query: space state is only reliable during physics, and
## running it on the render frame silently returned no overlaps at all.
func _physics_process(delta: float) -> void:
	# Cooldown runs whether or not this weapon is in hand.
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _swing <= 0.0:
		return
	_swing = maxf(_swing - delta, 0.0)
	# Damage lands mid-swing, not on the button press: the sweep should connect
	# when the weapon is actually crossing in front of the player.
	if not _contact_done and _phase() >= contact_at:
		_contact_done = true
		contact_count += 1
		_resolve_sweep()
		_throw_castoff()


## Presentation only, at render rate so the swing stays smooth above 60 Hz.
func _process(delta: float) -> void:
	if _swing > 0.0 or not _posed_rest:
		_pose(_phase())
	_track_tip(delta)


## The weapon tip's real velocity, for cast-off. Sampled after the pose so it
## reflects where the rig actually went this frame.
func _track_tip(delta: float) -> void:
	var tip := _tip_position()
	if _have_tip and delta > 0.0:
		tip_velocity = (tip - _last_tip) / delta
	_last_tip = tip
	_have_tip = true


func _tip_position() -> Vector3:
	var rig := _active_rig()
	# The business end, not the grip: a blade sheds blood off its far edge.
	return rig.global_transform * (Vector3.FORWARD * reach * 0.5)


func _phase() -> float:
	return clampf(1.0 - _swing / maxf(swing_time, 0.001), 0.0, 1.0)


func ready_to_attack() -> bool:
	return _cooldown <= 0.0


func try_attack() -> void:
	if not ready_to_attack() or camera() == null:
		return
	_cooldown = swing_time
	_swing = swing_time
	_contact_done = false
	_posed_rest = false
	_swing_hits.clear()
	if alternating:
		_side = -_side
	camera().add_recoil(config.melee_recoil_pitch, _rng.randf_range(-1.0, 1.0) * 0.3)
	Sfx.play_2d(&"dash", _rng.randf_range(0.78, 0.95), -10.0)


## Which rig is swinging this attack, and which is idle.
func _active_rig() -> Node3D:
	if _rig_alt != null and _side < 0.0:
		return _rig_alt
	return _rig


func _active_rest() -> Transform3D:
	if _rig_alt != null and _side < 0.0:
		return _alt_rest
	return _rig_rest


## ONE motion. Wind-up pulls back, the swing throws the mass all the way across,
## the follow-through keeps going the SAME way and drops out of frame, and the
## recovery eases up from below. Nothing ever travels back along the swing path,
## which is what made the old version read as two strikes.
func _pose(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var rig := _active_rig()
	var rest := _active_rest()
	var side := _side
	if _rig_alt != null:
		# With two rigs each one always swings inward from its own side.
		side = 1.0 if rig == _rig else -1.0

	var travel := 0.0
	var lift := 0.0
	var spin := 0.0

	if t < 0.22:
		# Wind-up: back and out, rotating away from the target.
		var u := t / 0.22
		travel = side * windup_travel * u
		lift = -windup_travel * 0.35 * u
		spin = -0.25 * u
	elif t < 0.58:
		# The swing itself. Fast, all the way across.
		var u := (t - 0.22) / 0.36
		var eased := 1.0 - pow(1.0 - u, 2.6)
		travel = lerpf(side * windup_travel, -side * swing_travel * 2.0, eased)
		lift = lerpf(-windup_travel * 0.35, swing_travel * 0.22, eased)
		spin = lerpf(-0.25, 1.0, eased)
	elif t < 0.78:
		# Follow-through: keeps going the same direction and drops out of frame.
		var u := (t - 0.58) / 0.2
		travel = lerpf(-side * swing_travel * 2.0, -side * swing_travel * 2.4, u)
		lift = lerpf(swing_travel * 0.22, -swing_travel * 1.1, u)
		spin = lerpf(1.0, 1.35, u)
	else:
		# Recovery: rises back to rest from below, still rotating forward.
		var u := (t - 0.78) / 0.22
		var eased := u * u
		travel = lerpf(-side * swing_travel * 2.4, 0.0, eased)
		lift = lerpf(-swing_travel * 1.1, 0.0, eased)
		spin = lerpf(1.35, 2.0, eased)

	rig.transform = rest
	rig.position = rest.origin + Vector3(travel, lift, -absf(travel) * 0.25)
	rig.rotate_object_local(Vector3.FORWARD, deg_to_rad(swing_arc) * side * spin)
	if t >= 1.0:
		rig.transform = rest
		_posed_rest = true


# --------------------------------------------------------------------------
# Damage
# --------------------------------------------------------------------------

## One overlap query for the whole swing. The first unique victim takes the full
## hit; every other victim caught by the SAME swing takes a fraction of their
## max health. A victim already in the per-swing set is skipped entirely, so no
## one can be damaged twice by one motion.
func _resolve_sweep() -> void:
	var cam := camera()
	var forward := -cam.global_basis.z
	var centre := cam.global_position + forward * reach
	# The swing travels ACROSS the view, toward the side the rig is moving to,
	# and the plane it sweeps contains that tangent and the forward axis. The
	# blood pattern is derived from this, never from "camera side + random".
	# THE SWING MOMENTUM AXIS. This is the vector the whole blunt signature is
	# built on, so it is derived from the rig's REAL world motion when that is
	# available and only falls back to the camera-side approximation when the
	# rig has not moved enough to give a reliable direction.
	#
	# Phase 2 computed this, stored it in ctx.weapon_velocity_ws, and then
	# nothing ever read it - while BLUNT silently used camera forward as its
	# axis. That is why reversing a maul swing produced identical blood.
	var tangent: Vector3
	var tip_speed: float
	if tip_velocity.length() > 1.0:
		tangent = tip_velocity.normalized()
		tip_speed = tip_velocity.length()
	else:
		tangent = (cam.global_basis.x * -_side).normalized()
		tip_speed = (swing_travel * 2.0 + windup_travel) / maxf(swing_time, 0.001)
	var plane_normal := tangent.cross(forward).normalized()
	if plane_normal.length_squared() < 0.0001:
		plane_normal = cam.global_basis.y
	# What the blow actually drives INTO the victim: the swing carries across,
	# the player's facing carries through. A heavy head transfers both.
	var momentum_axis := (tangent + forward * momentum_forward_bias).normalized()

	var shape := SphereShape3D.new()
	shape.radius = radius
	var overlaps := overlap_hurtboxes(shape, Transform3D(Basis(), centre))
	var targets := unique_targets(overlaps)
	last_sweep_overlaps = overlaps.size()
	last_sweep_targets = targets.size()
	if targets.is_empty():
		return

	for id in targets:
		if _swing_hits.has(id):
			continue
		var entry: Dictionary = targets[id]
		var area = entry["area"]
		var zone: StringName = entry["zone"]
		var point: Vector3 = wound_point_of(area, cam.global_position, forward)
		var first := _swing_hits.is_empty()
		_swing_hits[id] = true

		var damage := 0.0
		var energy := 1.0
		if first:
			damage = damage_head if zone == ZONE_HEAD else damage_body
		else:
			damage = _secondary_damage(area)
			# Secondary victims still bleed hard, just not lethally.
			energy = 0.7

		apply_hit(
			area, point, forward, -forward, zone, damage, knockback_scale * energy,
			func(ctx: BloodContext) -> void:
				ctx.swing_plane_normal_ws = plane_normal
				ctx.weapon_velocity_ws = tangent * tip_speed
				# EVERY melee family now carries its own real travel into the
				# pattern. A blade carries energy along its edge; a heavy head
				# drives a broad mass along the momentum axis. Neither may fall
				# back to camera forward while genuine swing data exists.
				ctx.penetration_direction_ws = momentum_axis
		)
		blood_load = minf(blood_load + blood_load_per_hit, 1.0)
		if first:
			camera().pulse_fov(
				config.fov_pulse_head if zone == ZONE_HEAD else config.fov_pulse_body
			)


func _secondary_damage(area: Object) -> float:
	var node := area as Node
	while node != null:
		if node.has_method("max_health"):
			return node.max_health() * secondary_health_fraction
		node = node.get_parent()
	return secondary_damage_fallback


# --------------------------------------------------------------------------
# Cast-off
# --------------------------------------------------------------------------

## A bloodied weapon throws some of its load off along the swing arc. This is
## why a melee fight paints the floor in streaks rather than in neat pools.
## Presentation only - it deals no damage and gates nothing.
func _throw_castoff() -> void:
	if blood_load <= 0.05:
		return
	var blood := _blood_system()
	if blood == null:
		return
	var cam := camera()
	# Prefer the blade's ACTUAL motion. Only when the rig has not moved enough to
	# give a reliable direction does this fall back to the swing side, which is
	# the approximation the whole of Phase 1 used.
	var tangent: Vector3
	if tip_velocity.length() > 0.75:
		tangent = tip_velocity.normalized()
	else:
		tangent = (cam.global_basis.x * -_side).normalized()
	var origin := _tip_position()
	blood.cast_off(
		origin,
		tangent,
		BloodTypes.DamageType.SLASHING if damage_type == BloodTypes.DamageType.SLASHING
			else damage_type,
		int(round(castoff_droplets * blood_load)),
		impact_energy
	)
	blood_load = maxf(blood_load - castoff_spend, 0.0)
