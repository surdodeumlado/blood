class_name BloodSurfaceResponse
extends Resource

## Assign collider metadata `blood_response` to one of data/blood/surfaces/*.tres.
## Presets describe the coating/substrate, not a universal metal/wood law.
@export var label := "SMOOTH_NONABSORBENT"
@export_range(0.0, 1.0) var roughness := 0.05
@export var spread := 1.05
@export var absorption_rate := 0.0
@export var retention := 0.35
@export var runoff_mobility := 1.0
@export var splash_multiplier := 1.0
@export var stain_darkening := 0.0
