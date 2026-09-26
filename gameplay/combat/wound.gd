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
## dies, future releases follow its visible body via validated instance IDs.
## Hiding/freeing that body terminates the source. Released drops never follow it.

## EXPLICIT LIFECYCLE. Phase 2 had a boolean `detached`, which was not enough:
## a wound on a dead target kept its attached transform and hung in the air at
## torso height with nothing under it, emitting almost nothing. A wound is now
## always in exactly one of three states and each has different rules.
enum State {
	## Following a living body. Inherits its motion, so a wounded target that
	## walks leaves a trail rather than dripping into the spot it was hit.
	ATTACHED_LIVING,
	## Finite post-mortem reserve; BloodSystem resolves the visible body each tick.
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
## How long a remnant is allowed to last once detached, and how much material
## it may spend doing it. BOTH come from ReservoirConfig now - they used to be a
## hardcoded 3.5 here while the config values sat unread, which is why tuning
## them did nothing.
var remnant_lifetime := 3.5
## Absolute ceiling on a remnant's age, independent of every other rule. This is
## the last line of defence against a wound that bleeds forever because some
## other number was mis-set.
var hard_deadline := 0.0
var owner_generation := 0
var death_id := 0
var transferred_mass := 0.0
var last_valid_surface: Dictionary = {}
var last_valid_position := Vector3.ZERO
## IDs do not retain Nodes. Only FUTURE releases resolve this source.
var source_id := 0
var reservoir_id := 0

func bind_source(source: Node3D, reservoir: BloodReservoir, at: Vector3) -> void:
	source_id = source.get_instance_id()
	reservoir_id = reservoir.get_instance_id()
	local_anchor = source.to_local(at)
	owner_generation = reservoir.generation

func current_source() -> Node3D:
	var source := instance_from_id(source_id) as Node3D if is_instance_id_valid(source_id) else null
	var reservoir := instance_from_id(reservoir_id) as BloodReservoir if is_instance_id_valid(reservoir_id) else null
	if source == null or reservoir == null: return null
	if source.is_queued_for_deletion() or reservoir.is_queued_for_deletion(): return null
	if not source.is_inside_tree() or not source.is_visible_in_tree(): return null
	if reservoir.generation != owner_generation: return null
	return source


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
	# A remnant dies at its deadline whatever else is true. Belt and braces: if
	# any other rule were ever mis-tuned, this still terminates it.
	if state == State.WORLD_REMNANT and hard_deadline > 0.0 and age >= hard_deadline:
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
	if not alive():
		exhaust()
		return 0.0
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
	var past_deadline := hard_deadline > 0.0 and age >= hard_deadline
	if remaining <= 0.0 or age >= lifetime or past_deadline:
		state = State.EXHAUSTED
	return amount


## The victim is gone. Become a WORLD_REMNANT: a fixed source that bleeds out
## what it has left, on a shortened clock, and SINKS toward the floor instead of
## hanging at torso height with nothing supporting it.
##
## `floor_y` is where the remnant settles. The caller does the downward ray, so
## this stays free of scene queries.
func detach(at: Vector3, floor_y := -INF, budget := -1.0, life := -1.0) -> void:
	if state != State.ATTACHED_LIVING:
		return
	state = State.WORLD_REMNANT
	detached = true
	world_anchor = at
	last_valid_position = at
	rest_y = floor_y
	if life > 0.0:
		remnant_lifetime = life

	# THE FIX FOR POST-MORTEM GUSHING.
	#
	# This used to shorten the CLOCK and leave `remaining` untouched, so a
	# remnant pushed the wound's whole reserve out through a shorter window with
	# a faster drip - it bled HARDER after death than the living wound did.
	# The mass is now capped as well as the time, so a remnant is a small, finite
	# last release and cannot outlive its budget.
	if budget >= 0.0:
		remaining = minf(remaining, budget)
	transferred_mass = remaining
	lifetime = minf(lifetime, remnant_lifetime)
	age = 0.0
	hard_deadline = remnant_lifetime
	# Slightly faster than the living wound, but it now has far less to give, so
	# this reads as the last of it running out rather than as a second wound.
	drip_interval = maxf(drip_interval * 0.75, 0.08)


## Legacy standalone model helper. Production body wounds NEVER use this:
## they resolve the current visible source or terminate safely.
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
