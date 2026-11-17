class_name Dress
extends Resource
## What a character wears on the human model: its palette, the gear hung on it and how tall it stands.

## The palette's squares, left to right, as `tools/make_character.py` lays them out.
enum Region { SKIN, HAIR, TUNIC, SLEEVES, SKIRT, HOSE, BOOTS, TRIM }

## An 8 × 1 palette, `assets/characters/human/palette-<name>.png`.
@export var palette: Texture2D
## Pieces worn on the model.
@export var gear: Array[PackedScene] = []
## The figure's height in metres; the model is scaled to it.
@export var height: float = 1.8


## The colour of `region` in the palette; grey without one.
func colour(region: Region) -> Color:
	if palette == null:
		return Color.GRAY
	return palette.get_image().get_pixel(region, 0)
