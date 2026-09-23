class_name BloodPhysicsSettings
extends Resource

## SI properties and explicitly artistic bounds. See BLOOD_PHYSICS_RESEARCH.md.
@export_group("Fluid / SI")
@export var density := 1055.0
@export var viscosity := 0.0048
@export var surface_tension := 0.060
@export var air_density := 1.204
@export var air_viscosity := 0.0000181
@export var fixed_substep := 0.0083333333
## A gameplay calibration, NOT a claim about a human reservoir's volume.
@export var kilograms_per_unit := 0.1
@export_group("Readability / artistic")
@export var diameter_exaggeration := 8.0
## Arcade multipliers apply AFTER the readability floor, never to physical d.
@export_range(0.0, 4.0) var render_mist_scale := 0.65
@export_range(0.1, 4.0) var render_fine_scale := 1.3
@export_range(0.1, 4.0) var render_small_scale := 3.0
@export_range(0.1, 4.0) var render_medium_scale := 2.5
@export_range(0.1, 4.0) var render_large_scale := 1.8
@export_range(0.1, 4.0) var render_glob_scale := 1.3
@export_range(0.1, 4.0) var render_ligament_scale := 1.0
@export var min_render_diameter := 0.004
@export var max_drop_diameter := 0.065
@export var max_glob_diameter := 0.085
@export var max_elongation := 1.4
@export var mist_max_diameter := 0.006
@export var ligament_max_length := 0.12
@export var ligament_max_width := 0.012
@export var ligament_lifetime := 0.10
@export var ligament_fraction := 0.045
@export var fat_max_size := 0.035
@export var grain_max_size := 0.038
@export var tissue_max_size := 0.11
@export var chunk_max_size := 0.18
@export var solid_max_flight_time := 8.0
## Final stain footprint only: no changes to spread, satellites, wet mass or flow.
@export_range(1.0, 1.5) var stain_medium_render_scale := 1.12
@export_range(1.0, 1.5) var stain_large_render_scale := 1.18
@export_range(1.0, 1.5) var stain_glob_render_scale := 1.22
@export_group("Breakup / bounded approximation")
@export var breakup_weber := 12.0
@export var breakup_max_generation := 2
@export var breakup_exposure := 0.025
@export_group("Impact / phenomenological")
@export var splash_weber := 160.0
@export var splash_min_reynolds := 100.0
@export var max_stain_aspect := 3.6
@export var glancing_sine := 0.5
@export var wet_patch_size := 0.4
@export var max_wet_patches := 1024
@export var max_causal_records := 4096
@export var rivulet_width_gain := 0.42
@export var rivulet_min_width := 0.024
@export var rivulet_max_width := 0.09
@export_group("Cast-off / presentation only")
@export var castoff_min_acceleration := 12.0
@export var castoff_load_mass := 0.025
@export var contact_retained_fraction := 0.08
@export var castoff_min_tip_speed := 1.0
