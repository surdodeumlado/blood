class_name BloodStabilitySettings
extends Resource

@export_group("Descending blood assist / arcade")
@export var fall_assist_enabled := true
@export var fall_assist_acceleration := 35.0
## Telemetry descent marker only; no longer switches a physical force on/off.
@export var fall_assist_threshold_m_s := 0.15
## Roll-off landmarks for the smooth force, not velocity assignments.
@export var fall_assist_small_target := 7.0
@export var fall_assist_medium_target := 9.5
@export var fall_assist_large_target := 11.0
@export var fall_assist_glob_target := 12.0
@export var fall_assist_small_cap := 9.0
@export var fall_assist_medium_cap := 11.0
@export var fall_assist_large_cap := 13.0
@export var fall_assist_glob_cap := 14.0

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
@export var trail_min_speed := 2.5
@export var trail_max_length_m := 0.18
@export var trail_time_s := 0.018
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
@export var audio_base_db := -18.0
@export var audio_max_db := -13.0
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

## Visual-only continuity. GPU formation is bounded by max_surface slots;
## admission remains stain_writes_per_frame. No growth nodes/materials/CPU writes.
@export_group("Flight and wet formation")
@export var bloom_duration_s := 0.14
@export var bloom_max_duration_s := 0.23
@export var small_min_pixels := 2.8
@export var medium_min_pixels := 4.0
@export var large_min_pixels := 5.0
@export var small_render_cap_m := 0.045
@export var medium_render_cap_m := 0.065
@export var large_render_cap_m := 0.095
@export var glob_render_cap_m := 0.12
@export var near_readability_ramp_m := 1.25
## Sampling only; all parcel mass is divided across the surviving representatives.
@export_range(0.1, 1.0) var small_sampling := 0.55
@export_range(0.1, 1.0) var medium_sampling := 0.75
@export_range(0.1, 1.0) var micro_sampling := 0.65
@export_group("Fresh wet bridges")
@export var bridge_jobs := 64
@export var bridge_pairs := 128
@export var bridge_ops_per_step := 2
@export var bridge_max_age_s := 1.2
@export var bridge_min_mass := 0.012
@export var bridge_max_distance_m := 0.32
@export var bridge_offset_m := 0.0015

@export_group("Heavy blood rain / presentation")
@export var rain_enabled := true
## Developer-only live THE_BOX A/B. F8 toggles; never enabled by default.
@export var blood_rain_debug_extreme := false
## Production values selected AFTER the actual THE_BOX NORMAL / EXTREME capture.
@export var rain_launch_speed_scale := 0.18
@export var rain_medium_upward_scale := 0.18
@export var rain_medium_min_physical_m := 0.00198
## Initial rain-carrier distribution, NOT gravity or a per-frame velocity clamp.
@export var rain_medium_downward_m_s := 9.2
@export var rain_large_downward_m_s := 11.2
@export var rain_glob_downward_m_s := 12.5
@export var rain_launch_vertical_spread_m_s := 0.7
## Presentation floor for descending important drops; bounded by tail cap.
@export var falling_trail_min_pixels := 14.0
@export_group("Shared rectangular rain streaks")
## One fixed allocation. Active selection may be profiled at96/128/160/192.
@export var rain_streak_capacity := 192
@export var rain_streak_budget := 192
@export_enum("Bodies only", "Production", "Streaks only") var rain_streak_mode := 1
@export var rain_streak_exposure_s := 0.11
@export var rain_streak_min_speed := 2.0
@export var rain_streak_min_pixels := 18.0
@export var rain_streak_width_pixels := 1.7
@export var rain_streak_width_min_m := 0.014
@export var rain_streak_width_max_m := 0.04
@export var rain_streak_medium_cap_m := 0.9
@export var rain_streak_large_cap_m := 1.1
@export var rain_high_arc_fraction := 0.35
@export var rain_high_arc_speed_cap := 34.0
@export var rain_high_arc_medium_speed_cap := 16.0
@export var rain_carrier_horizontal_cap_m_s := 12.0
## Developer A/B only. Normal gameplay never enables the rejected baseline.
@export var rain_rejected_baseline_debug := false
@export var blood_impact_audio_debug := false
@export var rain_splash_scale := 2.2
@export var rain_splash_duration_scale := 1.45
@export var rain_splash_irregularity := 0.85
## Optional authored replacement: isolated / sparse / patter / rain / heavy rain.
## Only first five entries are read, once per playback; no resources created.
@export var rain_audio_samples: Array[AudioStream] = []
@export var rain_audio_wet_sample: AudioStream
## Restored verbatim from pre-reduction live snapshot (222 initial reps).
@export var explosion_small_sampling := 0.65
@export var explosion_medium_sampling := 0.9
@export var explosion_medium_fraction := 0.52
@export var explosion_large_fraction := 0.25
@export var heavy_upward_scale := 0.22
@export var glob_upward_scale := 0.12
@export var rain_exposure_s := 0.07
@export var rain_tail_cap_m := 0.65
@export var rain_medium_min_pixels := 4.0
@export var rain_large_min_pixels := 5.5
@export var splash_capacity := 64
@export var splashes_per_frame := 8
@export var splash_max_width_m := 0.16
@export var audio_recent_capacity := 128
@export var audio_recent_window_s := 0.55
@export var audio_recent_radius_m := 5.0
