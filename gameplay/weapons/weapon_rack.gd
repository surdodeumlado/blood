class_name WeaponRack
extends Node3D

## Provisional fixed weapon slots for THE_BOX. NOT the game's weapon system.
##
## Four test instruments, always available, one active at a time, selected with
## 1-4. There is no inventory, no pickup, no ammo, no unlock and no progression
## here on purpose - this exists so four BloodProfiles can be compared in
## seconds without editing a .tres between them.
##
## Switching is deliberately inert with respect to movement: it touches nothing
## but which weapon is visible and receiving input.

signal weapon_changed(weapon: Weapon)
signal hit_confirmed(zone: StringName)
signal enemy_killed(zone: StringName)

const SLOT_ACTIONS: Array[StringName] = [
	&"weapon_slot_1", &"weapon_slot_2", &"weapon_slot_3", &"weapon_slot_4"
]

@export var config: CombatConfig

var weapons: Array[Weapon] = []
var current_index := 0


func setup(camera: FirstPersonCamera, shooter: CollisionObject3D) -> void:
	for child in get_children():
		var weapon := child as Weapon
		if weapon == null:
			continue
		weapons.append(weapon)
		weapon.setup(camera, shooter, config)
		weapon.hit_confirmed.connect(func(z: StringName) -> void: hit_confirmed.emit(z))
		weapon.enemy_killed.connect(func(z: StringName) -> void: enemy_killed.emit(z))
	select(0)


func current() -> Weapon:
	if weapons.is_empty():
		return null
	return weapons[current_index]


## Exactly one weapon is active at any time.
func select(index: int) -> void:
	if weapons.is_empty():
		return
	current_index = clampi(index, 0, weapons.size() - 1)
	for i in weapons.size():
		weapons[i].set_active(i == current_index)
	weapon_changed.emit(current())


func cycle(step: int) -> void:
	if weapons.is_empty():
		return
	select(posmod(current_index + step, weapons.size()))


## Returns true if the event was a slot change, so the caller can stop there.
func handle_input(event: InputEvent) -> bool:
	for i in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			select(i)
			return true
	if event.is_action_pressed(&"weapon_next"):
		cycle(1)
		return true
	if event.is_action_pressed(&"weapon_previous"):
		cycle(-1)
		return true
	return false


func try_attack() -> void:
	var weapon := current()
	if weapon != null:
		weapon.try_attack()


func ready_to_attack() -> bool:
	var weapon := current()
	return weapon != null and weapon.ready_to_attack()
