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
## m/s^2 added toward the input direction while grounded.
@export var ground_acceleration := 55.0
## m/s^2 bled off when there is no movement input at all.
@export var ground_deceleration := 45.0
## m/s^2 bled off when moving FASTER than move_speed while still holding input.
## This is the bunnyhop timing pressure knob: every physics tick spent standing
## on the ground instead of jumping costs this much speed. Raise it to punish
## sloppy hop timing harder, lower it to be more forgiving.
@export var momentum_friction := 14.0
## move_speed multiplier while crouch-walking.
@export var crouch_speed_multiplier := 0.45

@export_group("Air control")
## Baseline air control, used only while horizontal speed is BELOW move_speed:
## step off a ledge from a standstill and you can still fly the jump normally.
@export var air_acceleration := 16.0
## Above move_speed the baseline term stops adding and becomes pure redirection:
## this many degrees per second of speed-PRESERVING turn. It is what keeps fast
## air movement responsive, and it is incapable of granting speed, so holding a
## strafe key can never be a substitute for the technique below.
@export var air_turn_rate := 110.0

@export_group("Air strafe / bunnyhop")
## The skill term. Only applies while the velocity is nearly perpendicular to
## the input direction (see air_speed_cap), so it rewards real air-strafe
## technique instead of holding a key.
@export var air_strafe_acceleration := 60.0
## Quake/CS "max wish speed" for the strafe term: speed is only added while the
## projection of velocity onto the input direction is BELOW this. Small value =
## you must keep rotating the view to stay in the gain window. This single
## number is what makes strafing a technique rather than a held key.
@export var air_speed_cap := 1.1
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
## Starts counting when the dash ENDS.
@export var dash_cooldown := 0.50
## Horizontal velocity is multiplied by this the instant the dash ends. Below
## 1.0 means dashing while already fast is a net loss, so dash stays a
## correction / burst tool instead of something to mash on cooldown.
@export var dash_exit_speed_multiplier := 0.85
## Dashes allowed per airtime. Refilled on landing. 0 = ground dash only.
@export var air_dash_limit := 1

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
## How hard the slide can be steered. Speed-preserving: it rotates the velocity,
## it never lengthens it.
@export var slide_steer_acceleration := 9.0
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
@export var fov_base := 90.0
@export var fov_max := 108.0
## Horizontal speed at which the FOV starts widening.
@export var fov_speed_start := 9.0
## Horizontal speed at which the FOV reaches fov_max.
@export var fov_speed_full := 25.0
## Higher = FOV snaps faster. Frame-rate independent.
@export var fov_lerp_speed := 6.0
