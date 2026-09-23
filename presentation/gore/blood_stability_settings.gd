class_name BloodStabilitySettings
extends Resource

@export_group("Presentation frame limits")
@export var queries_per_frame := 640
@export var new_drops_per_frame := 192
@export var new_solids_per_frame := 72
@export var new_micro_per_frame := 128
@export var stain_writes_per_frame := 48
@export var runoff_starts_per_frame := 4
@export var wall_drops_per_frame := 4
@export var max_pending_releases := 64
@export var max_pending_contacts := 512
@export var max_coarse_jobs := 128
@export var surface_query_reserve := 128
@export var solid_queries_per_frame := 64
@export var aggregation_cell_m := 0.3
@export var event_neighborhood_m := 5.0
@export var adaptive_pressure := 0.32
@export var minimum_sampling := 0.28
@export var distant_sampling := 0.55
@export var importance_distance_m := 14.0

@export_group("Surface support")
@export var detail_surface_offset_m := 0.0025
@export var pool_surface_offset_m := 0.001
@export var runoff_surface_offset_m := 0.002
@export var support_probe_m := 0.065
@export var support_plane_tolerance_m := 0.012
@export var support_normal_dot := 0.985
@export var max_support_shrinks := 4
@export var minimum_surface_texels_per_m := 160.0
@export var immediate_fine_width_m := 0.16
@export var immediate_medium_width_m := 0.42
@export var immediate_glob_width_m := 0.9
@export var catastrophic_min_mass := 0.035
@export var catastrophic_width_m := 1.25
@export var residual_width_m := 0.22

@export_group("Wet patches and pools")
@export var wet_patch_cell_m := 0.5
@export var wet_lifetime_s := 8.0
@export var runoff_delay_min_s := 0.06
@export var runoff_delay_max_s := 0.35
@export var runoff_retention_scale := 0.4
@export var pool_start_mass := 0.018
@export var pool_area_per_mass := 4.5
@export var pool_max_area_m2 := 1.5
@export var pool_growth_window_s := 0.3
@export var pool_growth_m2_s := 2.5
@export var pool_initial_area_m2 := 0.012
## Approximate occupied diameter of the procedural mask inside its unit quad.
@export var pool_mask_occupancy := 0.75

@export_group("Bounded polish")
@export var max_fading_stains := 128
@export var fade_reserve_slots := 96
@export var fade_scan_per_step := 64
@export var fade_min_age_s := 5.0
@export var fade_micro_s := 0.25
@export var fade_medium_s := 0.65
@export var fade_pool_s := 1.2
## Trail occupies the rear vertices of existing rounded droplets, no extra instances.
@export var max_trails := 96
@export var trail_min_speed := 5.0
@export var trail_max_length_m := 0.18
@export var trail_time_s := 0.012
@export var slash_trail_gain := 1.65
@export var slash_stain_aspect := 1.65
@export var directional_tail_strength := 0.35
## Additional area funded by each incoming deposit; one tiny parcel cannot unlock a full pool.
@export var pool_area_credit_per_deposit := 0.08

@export_group("Blood impact audio / placeholders")
@export var audio_enabled := true
@export var audio_voices := 6
@export var audio_events_per_frame := 2
@export var audio_clusters := 32
@export var audio_window_s := 0.08
@export var audio_cell_m := 1.2
@export var audio_min_mass := 0.00015
@export var audio_max_distance_m := 18.0
@export var audio_base_db := -21.0
@export var audio_max_db := -16.0
@export var audio_unit_size_m := 5.0
@export var audio_cluster_max_age_s := 0.35

## Wet patches visited per physics frame by the time-sliced scan.
##
## The scan used to visit every patch every frame, and the expensive part - an
## instance_from_id() plus a Transform3D comparison - ran before any early-out.
## At the 1024-patch cap that is roughly 61k lookups per second whether or not
## anything is happening, which is what made a fought-in arena hitch.
##
## Each patch advances by the time since it was last visited, so the physics is
## unchanged; only the revisit interval is. 128 gives a ~0.13 s interval at the
## cap, well inside the second-scale behaviour these patches model.
@export var wet_updates_per_frame := 128

## Impact bloom, matching the uniforms in blood_stain.gdshader.
##
## A deposit starts at bloom_initial of its footprint and spreads to full over
## bloom_duration_s. The window is the wrap period of the packed birth time and
## only needs to be much longer than the duration.
@export var bloom_window_s := 8.0
@export var bloom_duration_s := 0.11
@export_range(0.05, 1.0) var bloom_initial := 0.22
