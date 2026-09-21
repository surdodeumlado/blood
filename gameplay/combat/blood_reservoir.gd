class_name BloodReservoir
extends Node

## How much material this body still has, and what leaves it per hit.
##
## Lives in gameplay/ on purpose. This is COMBAT TRUTH: it is the thing that
## decides a maul kill is catastrophic and a graze is not. Presentation reads
## the resulting BloodRelease and decides how to draw it, and a quality tier can
## never reach in here and change a number. Turning INSANE down to LOW must
## change how many representatives are drawn and nothing else.
##
## Attach one as a child of anything that can bleed. Weapons find it through
## Hurtbox.blood_reservoir(), the same duck-typed route they already use for
## take_damage() and overkill_ratio().

@export var config: ReservoirConfig

var remaining_blood := 1.0
var remaining_tissue := 1.0
## How much a corpse may still give up, spent by post-mortem hits and remnants.
var death_release_allowance := 0.0

var wounds: Array[Wound] = []

## Telemetry: everything this body has ever released.
var total_released := 0.0

var _victim: Node3D
var _emitter: Node


func _ready() -> void:
	if config == null:
		config = load("res://data/blood/reservoir_defaults.tres")
	_victim = get_parent() as Node3D
	refill()


## Back to full. The Blood Lab reset and the dummy's respawn both call this.
func refill() -> void:
	remaining_blood = config.max_blood
	remaining_tissue = config.max_tissue
	death_release_allowance = config.max_blood * config.death_release_allowance
	wounds.clear()


# --------------------------------------------------------------------------
# Withdrawals
# --------------------------------------------------------------------------

## THE mass decision. Given what combat says happened, how much material
## actually leaves this body right now?
##
## Returns a BloodRelease snapshot. Deducts from the reservoir, so the second
## hit on the same body is genuinely smaller than the first - which is the
## whole reason this component exists rather than a lookup table on the weapon.
func withdraw(ctx: BloodContext) -> BloodRelease:
	var family := ctx.damage_type
	var scale := config.family_scale(family)

	# Region.
	match ctx.body_region:
		BloodTypes.BodyRegion.HEAD:
			scale *= config.head_multiplier
		BloodTypes.BodyRegion.LIMB:
			scale *= config.limb_multiplier
		_:
			pass

	# Energy and overkill push the release up.
	scale *= 1.0 + (ctx.energy - 1.0) * config.energy_influence
	scale *= 1.0 + ctx.overkill * config.overkill_influence

	var blood := 0.0
	var tissue := 0.0
	var severity := 0.0

	if ctx.is_kill:
		var fraction := config.kill_blood_fraction
		if ctx.body_region == BloodTypes.BodyRegion.HEAD:
			fraction = minf(fraction * config.kill_head_multiplier, 1.0)
		blood = remaining_blood * fraction * scale
		tissue = blood * config.kill_tissue_ratio
		severity = config.remnant_severity
	else:
		blood = remaining_blood * config.hit_blood_fraction * scale
		tissue = blood * config.hit_tissue_ratio
		severity = config.wound_severity_for(family) * clampf(scale, 0.3, 2.0)

	# A body cannot give what it does not have. A corpse keeps a small allowance
	# so post-mortem hits still bleed instead of going dry and silent.
	blood = _draw_blood(blood, ctx.is_kill)
	tissue = minf(tissue, remaining_tissue)
	remaining_tissue = maxf(remaining_tissue - tissue, 0.0)

	var release := BloodRelease.make(ctx, blood, tissue)
	release.tissue_mix = config.tissue_mix_for(family)
	release.wound_severity = severity
	total_released += blood
	return release


func _draw_blood(wanted: float, is_kill: bool) -> float:
	var available := remaining_blood
	if available <= 0.0:
		# Dead and drained - the allowance is what is left to give.
		var from_allowance := minf(wanted, death_release_allowance)
		death_release_allowance -= from_allowance
		return from_allowance
	var drawn := minf(wanted, available)
	remaining_blood -= drawn
	if is_kill:
		# A kill empties what it took AND unlocks the corpse allowance, so the
		# body still has something left for a remnant to leak.
		death_release_allowance = maxf(
			death_release_allowance, config.max_blood * config.death_release_allowance * 0.5
		)
	return drawn


# --------------------------------------------------------------------------
# Wounds
# --------------------------------------------------------------------------

## Open a lasting wound from a release. Returns the wound, or null when the
## family opens none.
func open_wound(release: BloodRelease) -> Wound:
	if config.wound_reserve <= 0.0 or release.wound_severity <= 0.01:
		return null
	if _victim == null:
		return null
	var ctx := release.context
	var local := _victim.global_transform.affine_inverse() * ctx.position_ws
	# Blood runs off the wound roughly the way the blow drove through it, with a
	# downward bias: it is leaking, not spraying.
	var dir := ctx.primary_axis()
	dir = (dir * 0.45 + Vector3.DOWN).normalized()
	var local_dir := _victim.global_transform.basis.inverse() * dir

	var w := Wound.open(
		ctx.damage_type,
		ctx.body_region,
		release.wound_severity,
		config.wound_reserve,
		config.wound_lifetime,
		config.wound_drip_interval,
		local,
		local_dir
	)
	wounds.append(w)
	while wounds.size() > config.max_wounds:
		wounds.pop_front()
	return w


## Advance every wound. Returns the amount due per wound this tick as an array
## of {wound, amount}, which the blood system turns into discrete releases.
func tick_wounds(delta: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	var i := wounds.size() - 1
	while i >= 0:
		var w := wounds[i]
		var amount := w.tick(delta)
		if amount > 0.0:
			var drawn := _draw_blood(amount, false)
			if drawn > 0.0:
				due.append({"wound": w, "amount": drawn})
		if not w.alive():
			wounds.remove_at(i)
		i -= 1
	return due


## The victim is dying or being hidden. Detach every wound so they finish out in
## world space - a corpse that vanishes must not take its bleeding with it.
func detach_wounds(at: Vector3) -> void:
	for w in wounds:
		w.detach(at)


func victim() -> Node3D:
	return _victim


func has_material() -> bool:
	return remaining_blood > 0.0 or death_release_allowance > 0.0
