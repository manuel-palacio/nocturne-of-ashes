class_name GearPiece
extends Resource
## One piece worn on the human model: a scene made by `tools/blender/gear.py` (or `garments.py` or
## `heads.py`), the bone it hangs from, and, for cloth, the square of the wearer's palette that colours
## it. The tool's table says which bone each piece is modelled for.

## The piece, modelled in the model's rest pose with its origin at the head of `bone`.
@export var scene: PackedScene
## The model's bone it hangs from, such as `&"DEF-hand.R"`.
@export var bone: StringName
## Whether it is cloth, coloured by the wearer's palette at `region`; anything else keeps its own colours.
@export var cloth: bool = false
@export var region: Dress.Region = Dress.Region.TUNIC
## Whether its faces point at the palette's own squares, as a head's do (a garment of several colours):
## it is drawn with the body's own material, and `region` does not apply.
@export var own_squares: bool = false
## For cloth that stretches round the legs: how far it keeps from them, beyond their thickness, in metres.
@export var clearance: float = 0.03
## For cloth that stretches: its tables, written by the tool beside the piece as `<piece>_cloth.tres`.
@export var shape: ClothShape
