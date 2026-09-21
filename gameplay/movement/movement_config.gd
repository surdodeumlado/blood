class_name MovementConfig
extends Resource

## Single source of truth for every movement / camera number in the prototype.
##
## Nothing in the movement code is allowed to hardcode a tuning value: if you
## want to change how the game feels, you change it here (or in the .tres that
## the player scene points at) and nowhere else.

@export_group("Ground")
## Speed the player accelerates to on flat ground with no extra momentum.
@export var move_speed := 9.0
## m/s^2 added toward the input direction while grounded. MUST stay comfortably
## above ground_deceleration, because ground friction now runs every grounded
## tick: if acceleration cannot out-pace it, the player can never reach
## move_speed at all.
@export var ground_acceleration := 150.0
## m/s^2 of ground traction, applied every grounded tick while at or below
## move_speed - with or without input. This is what removes the "walking on
## soap" feel: any velocity that is not along the input direction is scrubbed
## off hard, so turning and stopping are crisp.
##
## It is deliberately scoped to normal walking speed. Above move_speed the much
## gentler momentum_friction takes over instead, and on the tick a jump fires
## friction is skipped entirely, so bhop and slide momentum are untouched.
@export var ground_deceleration := 95.0
## Seconds after LANDING during which traction is suspended while the player is
## still holding a direction.
##
## Walking never triggers it, because walking never lands - so normal ground
## movement keeps its full traction. A hop in progress does, which is the whole
## point: building speed from a standstill happens at 0-9 m/s, exactly the band
## traction governs, and letting 95 m/s^2 chew on every imperfectly timed
## landing is what broke bunnyhop after the traction pass.
##
## Set to 0.0 to get the un-graced behaviour back for comparison.
@export var landing_traction_grace := 0.2
## m/s^2 bled off when moving FASTER than move_speed while still holding input.
## This is the bunnyhop timing pressure knob: every physics tick spent standing
## on the ground instead of jumping costs this much speed. Raise it to punish
## sloppy hop timing harder, lower it to be more forgiving.
@export var momentum_friction := 14.0
## move_speed multiplier while crouch-walking.
@export var crouch_speed_multiplier := 0.45

@export_group("Air control (steering only - never grants speed)")
## Baseline air control, used only while horizontal speed is BELOW move_speed:
## step off a ledge from a standstill and you can still fly the jump normally.
@export var air_acceleration := 16.0
## Degrees per second the velocity may be rotated toward the input direction
## while airborne. Speed-PRESERVING: this is "how much can I turn", and it is
## deliberately unable to change "how fast can I go" - that is the job of the
## strafe block below. Raising it makes the air feel more agile without making
## anyone faster.
@export var air_control_turn_rate := 120.0
## Extra steering granted when the player is NOT holding forward. Lateral-only
## input buys tighter, more aggressive curves at the cost of longitudinal
## efficiency (see air_strafe_lateral_efficiency).
@export var air_control_lateral_bonus := 1.0

@export_group("Air strafe / bunnyhop (speed gain only)")
## m/s^2 added ALONG THE CURRENT VELOCITY at perfect strafe/turn sync.
##
## The model: air-strafe gain is paid for by SYNCHRONISATION between the lateral
## key and the camera turn, not by the geometry of the velocity vector.
##
##     A (left)  + turning left   = valid strafe
##     D (right) + turning right  = valid strafe
##     either key with a still camera = nothing
##     camera turn with no lateral key = nothing
##
## Both sides are the same rule, so alternating A and D is exactly as valid as
## holding one long curve, and neither is a privileged special case.
@export var air_strafe_acceleration := 3.6
## Yaw rate, in degrees per second, that counts as fully synchronised. Turning
## slower than this scales the gain down proportionally; turning faster does not
## pay more, so mouse-spinning is not a technique.
@export var air_strafe_sync_yaw_rate := 150.0
## Gain multiplier when the player holds NO forward input. Below 1.0 on purpose:
## lateral-only strafing stays viable and keeps momentum, but W + A/D remains
## the better way to build straight-line speed.
@export_range(0.0, 1.0) var air_strafe_lateral_efficiency := 0.5
## Below this speed the strafe term has full strength.
@export var air_falloff_start := 14.0
## Strafe gain reaches exactly zero here. Not a clamp: it is where the curve
## lands, so a skilled player asymptotes toward it instead of hitting a wall.
@export var air_soft_ceiling := 25.0
## Shape of the diminishing returns between falloff_start and soft_ceiling.
## 1.0 = linear, >1 = keeps gain longer then drops hard, <1 = drops early.
@export var air_falloff_exponent := 1.0
## m/s^2 pulling airborne speed back down to the soft ceiling when above it
## (e.g. after a dash). Gentle on purpose.
@export var overspeed_drag := 6.0
## Max airborne velocity change in m/s^2 while airborne is not limited here; the
## absolute number below is a safety net against physics blowups, NOT a
## gameplay cap. It sits far above the soft ceiling and should never be hit.
@export var safety_speed_limit := 40.0
## Terminal fall speed.
@export var max_fall_speed := 45.0

@export_group("Jump")
@export var jump_velocity := 8.5
@export var gravity := 24.0
## Grace period after walking off a ledge during which jump still works.
@export var coyote_time := 0.10
## How early a jump press is remembered before touching the ground. Keep this
## small: it exists for input/framerate fairness, not to automate bunnyhop.
## Jump is is_action_just_pressed, so holding the key never re-triggers.
@export var jump_buffer_time := 0.10
## A jump taken within this long of landing counts as a clean hop for the HUD
## chain readout. Display only; it grants nothing.
@export var bhop_grace_time := 0.12

@export_group("Dash")
@export var dash_speed := 20.0
@export var dash_duration := 0.14
## Horizontal velocity is multiplied by this the instant the dash ends. Below
## 1.0 means dashing while already fast is a net loss, so dash stays a
## correction / burst tool instead of something to mash on cooldown.
@export var dash_exit_speed_multiplier := 0.85
## Dashes allowed per airtime. Refilled on landing. The charge pool below is the
## real limiter; this is only a safety valve against hovering on air dashes.
@export var air_dash_limit := 2

@export_group("Dash charges")
## Dash is a resource. One dash costs one charge, and no charge means no dash.
@export var dash_max_charges := 2
## Seconds to refill ONE charge. Charges refill strictly one at a time: a single
## timer runs, completes a charge, then starts on the next.
@export var dash_charge_time := 1.35
## Minimum gap between two dashes, so spending both charges still reads as two
## separate actions rather than one long blur. Starts when a dash ENDS.
@export var dash_cooldown := 0.15
## A normal kill pushes the in-progress charge this many seconds closer to done.
## It can complete the current charge but never spills into the next one.
@export var dash_kill_recharge_bonus := 0.7

@export_group("Slide")
## Minimum horizontal speed required for crouch to become a slide.
@export var slide_min_speed := 7.0
## Slide ends by itself once horizontal speed drops below this.
@export var slide_end_speed := 4.0
## Entry speed is raised to move_speed * this. It is a max(), never an add,
## so repeatedly entering slides cannot stack speed.
@export var slide_entry_speed_multiplier := 1.25
## m/s^2 bled off while sliding. Much lower than ground friction.
@export var slide_friction := 3.0
## Degrees per second the slide heading may be rotated by A / D. This is the
## whole steering authority, and it is a RATE, not a blend: whatever the input,
## the trajectory can never swing faster than this, so the direction the slide
## was entered with keeps dominating. Raise it for looser carving, lower it for
## a more committed slide. It has no effect on how much speed is kept.
@export var slide_turn_rate := 55.0
## Degrees per second the slide is pulled toward where the camera is looking.
## Much smaller on purpose: it bends the line, it never snaps velocity to the
## view. Set to 0.0 to take the camera out of the slide entirely.
@export var slide_camera_turn_rate := 22.0
## Extra m/s^2 of deceleration while S is held. S is a brake and a cancel; it is
## deliberately not wired into steering, so it can never spin the slide around
## and carry the momentum backwards.
@export var slide_brake_strength := 26.0
## m/s^2 gained sliding down a slope.
@export var slide_slope_acceleration := 18.0

@export_group("Body")
@export var stand_height := 1.8
@export var crouch_height := 0.9
@export var capsule_radius := 0.4
## Eye sits this far below the top of the capsule.
@export var eye_offset := 0.2
## Metres per second the capsule grows / shrinks.
@export var height_change_speed := 6.0

@export_group("Camera")
@export var mouse_sensitivity := 0.0022
@export var pitch_limit_degrees := 89.0

@export_group("FOV")
## The camera composes its final FOV as
##     speed component + dash accent + hit pulse
## clamped to fov_absolute_max, so no two effects can fight or stack away.
@export var fov_base := 90.0
@export var fov_max := 104.0
## Horizontal speed at which the FOV starts widening.
@export var fov_speed_start := 9.0
## Horizontal speed at which the FOV reaches fov_max.
@export var fov_speed_full := 25.0
## Higher = the speed component tracks faster. Frame-rate independent.
@export var fov_lerp_speed := 6.0
## Degrees added while dashing, on top of the speed component.
@export var fov_dash_accent := 5.0
## Higher = the dash accent fades faster.
@export var fov_dash_recovery := 4.5
## Higher = hit pulses fade faster. These need to be quick and clean.
@export var fov_pulse_recovery := 9.0
## Hard ceiling on the composed FOV. Nothing gets past this, ever, so stacked
## accents can never turn into a fisheye.
@export var fov_absolute_max := 114.0
