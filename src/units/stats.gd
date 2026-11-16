class_name Stats
extends Resource
## Health and blood of one unit. Health reaching zero emits `died` once.

signal health_changed(current: int, maximum: int)
signal blood_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100
@export var max_blood: int = 100
## Blood after `reset()`; −1 means full.
@export var starting_blood: int = -1

var health: int
var blood: int


func _init() -> void:
	reset()


## Refills health to its maximum and blood to `starting_blood`, or to its maximum.
## A maximum of 0 or less is raised to 1.
func reset() -> void:
	max_health = maxi(max_health, 1)
	max_blood = maxi(max_blood, 1)
	health = max_health
	blood = max_blood if starting_blood < 0 else clampi(starting_blood, 0, max_blood)
	health_changed.emit(health, max_health)
	blood_changed.emit(blood, max_blood)


func take_damage(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if is_dead():
		died.emit()


func heal(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)


## Brings the dead back with `amount` health, at least 1; does nothing for the living.
func revive(amount: int) -> void:
	if not is_dead():
		return
	health = clampi(amount, 1, max_health)
	health_changed.emit(health, max_health)


## Pays `amount` blood if there is enough; returns false and changes nothing otherwise.
func spend_blood(amount: int) -> bool:
	if amount < 0 or amount > blood:
		return false
	blood -= amount
	blood_changed.emit(blood, max_blood)
	return true


func gain_blood(amount: int) -> void:
	if amount <= 0:
		return
	blood = mini(blood + amount, max_blood)
	blood_changed.emit(blood, max_blood)


func is_dead() -> bool:
	return health <= 0
