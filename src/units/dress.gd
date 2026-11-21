class_name Dress
extends Resource
## What a character wears on the human model: its palette, its head, the gear hung on it and how
## tall it stands.

## The palette's squares, left to right, as `tools/make_character.py` lays them out. The body uses the
## first eight; the faces of the heads use the rest too.
enum Region {
	SKIN, HAIR, TUNIC, SLEEVES, SKIRT, HOSE, BOOTS, TRIM,
	EYE_WHITE, IRIS, BROW, LIPS, BEARD, SOCKET, SHADE, STUBBLE,
}

## A 16 × 1 palette, `assets/characters/human/palette-<name>.png`.
@export var palette: Texture2D
## Its head, made by `tools/blender/heads.py` and hung from `DEF-head`: the model has none of its own.
## Its faces point at the palette's own squares, so it is drawn with the body's material.
@export var head: GearPiece
## Pieces worn on the model, each hung from its bone; cloth among them is coloured from `palette`.
@export var gear: Array[GearPiece] = []
## The figure's height in metres; the model is scaled to it.
@export var height: float = 1.8


## The palette's name: `zahra` for `palette-zahra.png`; empty without a palette. Portraits are named by it.
func palette_name() -> String:
	if palette == null:
		return ""
	return palette.resource_path.get_file().get_basename().trim_prefix("palette-")
