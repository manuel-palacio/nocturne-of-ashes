#!/usr/bin/env python3
"""Makes the human model and its palettes from Quaternius's Universal Animation Library (CC0).

    uv run --python 3.12 --with pygltflib==1.16.5 --with numpy==2.5.5 --with pillow==13.0.0 \
        python3 tools/make_character.py <AnimationLibrary_Godot_Standard.glb>
    uv run --python 3.12 --with pygltflib==1.16.5 --with numpy==2.5.5 --with pillow==13.0.0 \
        python3 tools/make_character.py --palettes-only

The versions are pinned because the output is compared byte for byte: another pygltflib can write
the JSON differently and another Pillow or zlib can compress the PNGs differently.

The library's mannequin is a fully animated human with no clothes. This tool dresses it with
colour alone: every triangle is given one body region from the bone that moves it most and its
height, and its texture coordinates point at that region's square in an 8 x 1 palette image. A
character's look is then a palette, `assets/characters/human/palette-<name>.png`.

The model keeps only the clips in CLIPS, renamed; `stagger` is made here from `Hit_Head`. Clips
that loop are written with a `_loop` ending, which Godot's importer reads as looping and removes,
so the game sees exactly the names in CLIPS. The mesh is turned to face -Z, Godot's forward, and
the binary buffer is rebuilt to hold only what the model uses. The output is byte-identical from
one run to the next.
"""
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets/characters/human"
DEFAULT_PALETTE = "alvar"  # the one the model's own material shows

REGION_NAMES = ["skin", "hair", "tunic", "sleeves", "skirt", "hose", "boots", "trim"]
SKIN, HAIR, TUNIC, SLEEVES, SKIRT, HOSE, BOOTS, TRIM = range(len(REGION_NAMES))

# Heights in metres on the 1.83 m mannequin, in its own frame (y up, facing +z before the turn).
CROWN = 1.745          # hair above this on the head
NAPE = 1.60            # and down to here at the back of the head
COLLAR_TOP = 1.52      # the neck below this is a collar band,
COLLAR_FOOT = 1.44     # running down onto the chest and back to here,
COLLAR_HALF = 0.12     # this far either side of the middle
BELT = (0.99, 1.05)    # a band round the waist
WAIST = 1.05           # tunic above, skirt below
KNEE = 0.50            # skirt above, hose below
BOOT_TOP = 0.28        # hose above, boots below

PALETTES = {
    # skin, hair, tunic, sleeves, skirt, hose, boots, trim
    # Brother Alvar: the white habit and mantle of a knight-friar, red trim.
    "alvar": ["#d8aa88", "#4a3324", "#ece8de", "#e2ddd0", "#dcd6c8", "#2a2a30", "#5e3d22", "#b0201e"],
    # Zahra: a deep teal robe, ochre sleeves, dark hair, a pale veil at the collar.
    "zahra": ["#b78462", "#1a1412", "#17625e", "#c8902a", "#145651", "#124a46", "#4a3020", "#e0d2b0"],
    # Gonzalo: grey wool, a brown leather apron, bare forearms, iron-grey hair.
    "gonzalo": ["#cf9e7a", "#8e8e8c", "#7a7c7c", "#cf9e7a", "#7a4a26", "#5c5e5e", "#3a2a1e", "#3c2616"],
    # Crusaders: mail-grey sleeves and hose under a dark red surcoat.
    "crusader": ["#d6a684", "#4e3826", "#7c1616", "#9aa0a4", "#761414", "#8c9296", "#2e2620", "#d8d0bc"],
    # Sergeants: the same, with a bronze surcoat and a darker trim.
    "sergeant": ["#d2a07c", "#3a2a1e", "#9a7230", "#9aa0a4", "#8e6a2c", "#8c9296", "#2e2620", "#2a1e14"],
    # Malakor: black, with a crimson trim, pale skin.
    "malakor": ["#e8ddd2", "#141214", "#242026", "#201c22", "#1e1a20", "#1a171c", "#121012", "#a8102a"],
    # Inigo the smith: brown, a soot-dark apron, bare forearms.
    "smith": ["#c69270", "#2e2018", "#6e4a2a", "#c69270", "#2a2624", "#4e3824", "#2c2018", "#1a1614"],
    # The captive: a torn, dirty undershirt, bare lower legs and feet.
    "captive": ["#c9a084", "#3a2e24", "#b4ae9e", "#aaa494", "#968e7c", "#c29a7e", "#ad866a", "#6e624e"],
}

# Game name: (library clip, loops). `stagger` is made from Hit_Head below.
CLIPS = {
    "idle": ("Idle_Loop", True),
    "walk": ("Walk_Loop", True),
    "run": ("Jog_Fwd_Loop", True),
    "attack": ("Sword_Attack", False),
    "hit": ("Hit_Chest", False),
    "death": ("Death01", False),
    "cast": ("Spell_Simple_Shoot", False),
    "interact": ("Interact", False),
    "stagger": ("Hit_Head", True),
    "talk": ("Idle_Talking_Loop", True),
    "sit": ("Sitting_Idle_Loop", True),
}
# The stagger loop: Hit_Head's keys from STAGGER_KEYS[0] to STAGGER_KEYS[1], played forward then
# back, slowed by STAGGER_SLOW, so the figure reels on the blow and its ends meet.
STAGGER_KEYS = (2, 10)
STAGGER_SLOW = 1.5

WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FLOAT, UBYTE, USHORT = 5126, 5121, 5123
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963
NEAREST, CLAMP_TO_EDGE = 9728, 33071


def region_of(bone: str, x: float, y: float, z: float) -> int | None:
    """The region of a vertex moved most by `bone`, at (`x`, `y`, `z`); `z` < 0 is the back."""
    if "head" in bone:
        return HAIR if y > CROWN or (y > NAPE and z < -0.02) else SKIN
    if any(b in bone for b in ("neck", "spine.003", "shoulder")) and abs(x) < COLLAR_HALF \
            and COLLAR_FOOT < y < COLLAR_TOP:
        return TRIM
    if "neck" in bone:
        return SKIN
    if "hand" in bone or "f_" in bone or "thumb" in bone:
        return SKIN
    if "forearm" in bone:
        return SLEEVES
    if "upper_arm" in bone or "shoulder" in bone:
        return TUNIC
    if "foot" in bone or "toe" in bone:
        return BOOTS
    if "shin" in bone or "thigh" in bone:
        if y < BOOT_TOP:
            return BOOTS
        return HOSE if y < KNEE else SKIRT
    if "hips" in bone or "spine" in bone:
        if BELT[0] <= y <= BELT[1]:
            return TRIM
        return TUNIC if y > WAIST else SKIRT
    return None


def main(source: str) -> None:
    import numpy as np
    from pygltflib import (GLTF2, Accessor, BufferView, Image as GltfImage, Material,
                           PbrMetallicRoughness, Primitive, Sampler, Texture, TextureInfo)

    dtypes = {FLOAT: np.float32, USHORT: np.uint16, UBYTE: np.uint8, 5125: np.uint32}
    gltf = GLTF2().load(source)
    old_blob = gltf.binary_blob()
    old_accessors = gltf.accessors
    old_views = gltf.bufferViews

    def read(index: int) -> np.ndarray:
        accessor = old_accessors[index]
        view = old_views[accessor.bufferView]
        dtype = np.dtype(dtypes[accessor.componentType])
        width = WIDTH[accessor.type]
        assert not view.byteStride or view.byteStride == dtype.itemsize * width, f"accessor {index} is interleaved"
        assert accessor.sparse is None, f"accessor {index} is sparse"
        offset = (view.byteOffset or 0) + (accessor.byteOffset or 0)
        return np.frombuffer(old_blob, dtype=dtype, count=accessor.count * width, offset=offset).reshape(
            accessor.count, width)

    # A fresh buffer holding only what the model uses, in a fixed order, every view 4-byte aligned.
    blob = bytearray()
    accessors: list = []
    views: list = []

    def add(data: np.ndarray, kind: str, component: int, target=None, bounds: bool = False) -> int:
        raw = np.ascontiguousarray(data.astype(dtypes[component])).tobytes()
        views.append(BufferView(buffer=0, byteOffset=len(blob), byteLength=len(raw), target=target))
        blob.extend(raw)
        while len(blob) % 4:
            blob.append(0)
        accessor = Accessor(bufferView=len(views) - 1, componentType=component, count=len(data), type=kind)
        if bounds:
            accessor.min = data.min(axis=0).astype(float).tolist()
            accessor.max = data.max(axis=0).astype(float).tolist()
        accessors.append(accessor)
        return len(accessors) - 1

    copied: dict[int, int] = {}

    def copy(index: int, bounds: bool = False) -> int:
        if index not in copied:
            old = old_accessors[index]
            copied[index] = add(read(index), old.type, old.componentType, bounds=bounds)
        return copied[index]

    # The mesh: both of the library's primitives joined into one, one region per triangle.
    assert len(gltf.meshes) == 1 and len(gltf.skins) == 1, "expected the library's one mesh and one skin"
    bones = [gltf.nodes[j].name for j in gltf.skins[0].joints]
    parts = {"position": [], "normal": [], "joints": [], "weights": [], "triangles": []}
    base = 0
    for primitive in gltf.meshes[0].primitives:
        position = read(primitive.attributes.POSITION)
        parts["position"].append(position)
        parts["normal"].append(read(primitive.attributes.NORMAL))
        assert old_accessors[primitive.attributes.WEIGHTS_0].componentType == FLOAT, "weights are not floats"
        joint_index = read(primitive.attributes.JOINTS_0)
        assert joint_index.max() < 256, "a joint index does not fit in a byte"
        parts["joints"].append(joint_index)
        parts["weights"].append(read(primitive.attributes.WEIGHTS_0))
        parts["triangles"].append(read(primitive.indices).reshape(-1, 3).astype(np.int64) + base)
        base += len(position)
    position, normal, joints, weights, triangles = (np.concatenate(parts[k]) for k in
                                                    ("position", "normal", "joints", "weights", "triangles"))
    lead = joints[np.arange(len(joints)), weights.argmax(axis=1)]
    unmapped = sorted({bones[b] for b in lead if region_of(bones[b], 0.0, 1.0, 0.0) is None})
    if unmapped:
        sys.exit(f"make_character: no region for the bones {', '.join(unmapped)}")
    of_vertex = np.array([region_of(bones[lead[i]], *position[i]) for i in range(len(position))])
    # A triangle takes the commonest region among its corners (the lowest on a tie), and a vertex
    # is copied once for each region that uses it, so no triangle spans two palette squares.
    remap: dict[tuple[int, int], int] = {}
    order: list[tuple[int, int]] = []
    faces = []
    for tri in triangles:
        region = int(np.bincount(of_vertex[tri]).argmax())
        for v in tri:
            key = (int(v), region)
            if key not in remap:
                remap[key] = len(order)
                order.append(key)
            faces.append(remap[key])
    source_index = np.array([k[0] for k in order])
    regions = np.array([k[1] for k in order])
    uv = np.stack([(regions + 0.5) / len(REGION_NAMES), np.full(len(order), 0.5)], axis=1)
    assert len(order) < 65536, "too many vertices for 16-bit indices"
    mesh_primitive = Primitive(material=0, mode=4)
    mesh_primitive.attributes.POSITION = add(position[source_index], "VEC3", FLOAT, ARRAY_BUFFER, bounds=True)
    mesh_primitive.attributes.NORMAL = add(normal[source_index], "VEC3", FLOAT, ARRAY_BUFFER)
    mesh_primitive.attributes.TEXCOORD_0 = add(uv, "VEC2", FLOAT, ARRAY_BUFFER)
    mesh_primitive.attributes.JOINTS_0 = add(joints[source_index], "VEC4", UBYTE, ARRAY_BUFFER)
    mesh_primitive.attributes.WEIGHTS_0 = add(weights[source_index], "VEC4", FLOAT, ARRAY_BUFFER)
    mesh_primitive.indices = add(np.array(faces), "SCALAR", USHORT, ELEMENT_ARRAY_BUFFER)
    gltf.meshes[0].primitives = [mesh_primitive]
    gltf.skins[0].inverseBindMatrices = copy(gltf.skins[0].inverseBindMatrices)

    # One material, showing the default palette through nearest sampling.
    gltf.images = [GltfImage(uri=f"palette-{DEFAULT_PALETTE}.png")]
    gltf.samplers = [Sampler(magFilter=NEAREST, minFilter=NEAREST, wrapS=CLAMP_TO_EDGE, wrapT=CLAMP_TO_EDGE)]
    gltf.textures = [Texture(sampler=0, source=0)]
    gltf.materials = [Material(name="palette", doubleSided=False, pbrMetallicRoughness=PbrMetallicRoughness(
        baseColorFactor=[1.0, 1.0, 1.0, 1.0], baseColorTexture=TextureInfo(index=0),
        metallicFactor=0.0, roughnessFactor=1.0))]

    # Turn the rig to face -Z: the library's figure faces +Z.
    rig = [n for n in gltf.nodes if n.name == "Rig"]
    assert len(rig) == 1 and rig[0].rotation is None and rig[0].matrix is None, "no plain Rig node"
    rig[0].rotation = [0.0, 1.0, 0.0, 0.0]

    # The clips.
    by_name = {a.name: a for a in gltf.animations}
    missing = sorted(source for source, _ in CLIPS.values() if source not in by_name)
    if missing:
        sys.exit(f"make_character: the library has no clip {', '.join(missing)}")
    animations = []
    for name, (source_name, loops) in CLIPS.items():
        animation = by_name[source_name]
        if name == "stagger":
            make_stagger(animation, read, add, copy)
        else:
            for sampler in animation.samplers:
                sampler.input = copy(sampler.input, bounds=True)
                sampler.output = copy(sampler.output)
        animation.name = f"{name}_loop" if loops else name
        animations.append(animation)
    gltf.animations = animations

    gltf.accessors = accessors
    gltf.bufferViews = views
    gltf.buffers[0].byteLength = len(blob)
    gltf.set_binary_blob(bytes(blob))
    gltf.asset.generator = "tools/make_character.py"
    OUT.mkdir(parents=True, exist_ok=True)
    gltf.save_binary(str(OUT / "human.glb"))
    print("wrote human.glb:", len(faces) // 3, "triangles,", len(order), "vertices,",
          round(len(blob) / 1e6, 2), "MB of data")
    write_palettes()


def make_stagger(animation, read, add, copy) -> None:
    """Turns Hit_Head into a loop: a stretch of its keys forward, then back to where it began."""
    import numpy as np

    inputs = {s.input for s in animation.samplers}
    assert len(inputs) == 1, "Hit_Head's channels have different key times"
    times = read(next(iter(inputs)))[:, 0]
    first, last = STAGGER_KEYS
    assert last < len(times), "Hit_Head has fewer keys than STAGGER_KEYS needs"
    forward = list(range(first, last + 1))
    keys = forward + forward[-2::-1]  # first .. last .. first
    step = np.diff(times[first:last + 1])
    gaps = np.concatenate([step, step[::-1]]) * STAGGER_SLOW
    new_times = np.concatenate([[0.0], np.cumsum(gaps)]).reshape(-1, 1)
    new_input = add(new_times, "SCALAR", FLOAT, bounds=True)
    for sampler in animation.samplers:
        assert sampler.interpolation in (None, "LINEAR"), f"Hit_Head has {sampler.interpolation} keys"
        values = read(sampler.output)
        kind = {width: name for name, width in WIDTH.items()}[values.shape[1]]
        sampler.input = new_input
        sampler.output = add(values[keys], kind, FLOAT)


def write_palettes() -> None:
    """Every character's palette, 8 x 1 pixels in REGION_NAMES order. Needs no model."""
    OUT.mkdir(parents=True, exist_ok=True)
    for name, colours in PALETTES.items():
        assert len(colours) == len(REGION_NAMES), f"palette {name} needs {len(REGION_NAMES)} colours"
        image = Image.new("RGB", (len(REGION_NAMES), 1))
        for x, colour in enumerate(colours):
            image.putpixel((x, 0), tuple(int(colour[i:i + 2], 16) for i in (1, 3, 5)))
        image.save(OUT / f"palette-{name}.png", optimize=False)
        print("wrote", f"palette-{name}.png")


if __name__ == "__main__":
    if sys.argv[1:] == ["--palettes-only"]:
        write_palettes()
    elif len(sys.argv) == 2:
        main(sys.argv[1])
    else:
        sys.exit(__doc__)
