class_name Stats
extends Resource
## Health and blood of one unit. Health reaching zero emits `died` once.

signal health_changed(current: int, maximum: int)
signal blood_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100
@export var max_blood: int = 100

var health: int
var blood: int


func _init() -> void:
	reset()


## Refills health and blood to their maximums.
func reset() -> void:
	health = max_health
	blood = max_blood
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
