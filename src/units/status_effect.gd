class_name StatusEffect
extends Resource
## A timed change to one `Unit`: how fast it walks, how hard it hits and is hit, whether it is stunned,
## and how far its taunt reaches. The unit keeps its own copy and counts `duration` down on it.

@export var id: StringName
@export var duration: float = 1.0
@export var speed_multiplier: float = 1.0
@export var damage_dealt_multiplier: float = 1.0
@export var damage_taken_multiplier: float = 1.0
@export var stuns: bool = false
@export var taunt_radius: float = 0.0
