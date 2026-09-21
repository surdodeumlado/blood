class_name Wound
extends RefCounted

## An opening that keeps leaking after the blow that made it.
##
## Logical, and owned by the victim's BloodReservoir - NOT by the blood system.
## A quality tier may change how a drip is drawn and may never change how much
## blood the wound gives up or how long it lasts.
##
## Anchoring is local to the victim, so a wounded target that walks leaves a
## trail rather than dripping into the spot where it was hit. When the victim
## dies or disappears, the wound is handed a fixed world position and finishes
## its life there as a remnant, which is how a catastrophic head kill keeps
## bleeding for a moment after the corpse is hidden.

## EXPLICIT LIFECYCLE. Phase 2 had a boolean `detached`, which was not enough:
## a wound on a dead target kept its attached transform and hung in the air at
## torso height with nothing under it, emitting almost nothing. A wound is now
## always in exactly one of three states and each has different rules.
enum State {
	## Following a living body. Inherits its motion, so a wounded target that
	## walks leaves a trail rather than dripping into the spot it was hit.
	ATTACHED_LIVING,
	## The body is gone. Anchored to a fixed world point, falling toward the
	## floor, bleeding out what it has left on a finite clock.
	WORLD_REMNANT,
	## Spent. Retired by its owner on the next tick.
	EXHAUSTED,
}

var state: State = State.ATTACHED_LIVING

var region: BloodTypes.BodyRegion = BloodTypes.BodyRegion.TORSO
var family: BloodTypes.DamageType = BloodTypes.DamageType.BALLISTIC
var severity := 0.0
## Blood still to come out of this wound, in reservoir units.
var remaining := 0.0
var lifetime := 0.0
var age := 0.0
## Seconds between discrete releases. Never per frame.
var drip_interval := 0.25
var since_drip := 0.0

## Where the wound sits on the victim, in the victim's local space.
var local_anchor := Vector3.ZERO
## The direction blood leaves the wound, local to the victim.
var local_direction := Vector3.DOWN

## Set when the victim is gone: the wound finishes its life here instead.
var detached := false
var world_anchor := Vector3.ZERO
## Where a falling remnant comes to rest, and how fast it is currently sinking.
var rest_y := -INF
var fall_speed := 0.0
## How long a remnant is allowed to last once detached.
var remnant_lifetime := 3.5


static func open(
	family_: BloodTypes.DamageType,
	region_: BloodTypes.BodyRegion,
	severity_: float,
	reserve: float,
	life: float,
	interval: float,
	anchor: Vector3,
	direction: Vector3
) -> Wound:
	var w := Wound.new()
	w.family = family_
	w.region = region_
	w.severity = clampf(severity_, 0.0, 1.0)
	w.remaining = reserve * w.severity
	w.lifetime = life * w.severity
	w.drip_interval = maxf(interval, 0.05)
	w.local_anchor = anchor
	w.local_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.DOWN
	# Stagger the first drip so several wounds opened together do not pulse in
	# lockstep, which reads as a machine rather than as a body.
	w.since_drip = randf() * w.drip_interval
	return w


func alive() -> bool:
	if state == State.EXHAUSTED:
		return false
	return age < lifetime and remaining > 0.0


## Nothing left to give. Called by the owner, which then retires it.
func exhaust() -> void:
	state = State.EXHAUSTED
	remaining = 0.0


## Advance the clock. Returns how much blood is due THIS tick, or 0.0 when the
## wound is between drips. The caller turns that into a BloodRelease.
func tick(delta: float) -> float:
	if not alive():
		return 0.0
	age += delta
	since_drip += delta
	if since_drip < drip_interval:
		return 0.0
	since_drip = 0.0
	# Bleed out over the wound's remaining life, so a wound tapers rather than
	# dripping at a constant rate until it abruptly stops.
	var left := maxf(lifetime - age, 0.001)
	var drips_left := maxf(left / drip_interval, 1.0)
	var amount := remaining / drips_left
	# Heavier early: the first seconds after a cut are the visible ones.
	amount *= lerpf(1.6, 0.5, clampf(age / maxf(lifetime, 0.001), 0.0, 1.0))
	amount = minf(amount, remaining)
	remaining -= amount
	if remaining <= 0.0 or age >= lifetime:
		state = State.EXHAUSTED
	return amount


## The victim is gone. Become a WORLD_REMNANT: a fixed source that bleeds out
## what it has left, on a shortened clock, and SINKS toward the floor instead of
## hanging at torso height with nothing supporting it.
##
## `floor_y` is where the remnant settles. The caller does the downward ray, so
## this stays free of scene queries.
func detach(at: Vector3, floor_y := -INF) -> void:
	state = State.WORLD_REMNANT
	detached = true
	world_anchor = at
	rest_y = floor_y
	# A remnant is the last of the bleeding, not a second wound: it releases
	# what it has faster and over a shorter window.
	lifetime = minf(lifetime, remnant_lifetime)
	age = 0.0
	drip_interval = maxf(drip_interval * 0.6, 0.06)


## Remnants fall. Called once per tick by the owner while WORLD_REMNANT, so the
## source collapses toward the impact zone rather than floating.
func fall(delta: float) -> void:
	if state != State.WORLD_REMNANT:
		return
	fall_speed += 9.8 * delta
	world_anchor.y -= fall_speed * delta
	if world_anchor.y <= rest_y:
		world_anchor.y = rest_y
		fall_speed = 0.0


func position_ws(victim_transform: Transform3D) -> Vector3:
	if state != State.ATTACHED_LIVING:
		return world_anchor
	return victim_transform * local_anchor


func direction_ws(victim_transform: Transform3D) -> Vector3:
	if state != State.ATTACHED_LIVING:
		return Vector3.DOWN
	var d := victim_transform.basis * local_direction
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.DOWN
