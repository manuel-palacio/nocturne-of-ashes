class_name ClothShape
extends Resource
## How a cloth piece stretches, measured by `tools/blender/gear.py` when it makes the piece, so the game
## never reads a mesh back from the graphics card to find out. Heights and reaches are in metres in the
## piece's frame (the model's frame at rest, origin at the piece's bone).

## The piece's stretching shape keys, by name (`fore`, `aft`, `left`, `right`).
@export var keys: PackedStringArray = PackedStringArray()
## For each of `keys`, per ring of the piece from the lowest up: (height, how far the piece reaches
## that key's way at rest, how much further the key takes it at full weight).
@export var rings: Array[PackedVector3Array] = []
## Whether the piece has a `flat` key, which lays its hem flat.
@export var flattens: bool = false
