"""Makes the gear and cloth pieces worn on the human model, one `.glb` per piece in `assets/gear/`.

    blender -b --factory-startup -P tools/blender/gear.py

Written for Blender 5.3, and it refuses to run with any other version: another version's glTF
exporter may write different bytes.

Each piece is modelled in the model's own frame (`assets/characters/human/human.glb`): metres, y up,
the figure facing -z, in its rest pose (a T-pose, palms down). A piece's origin is the rest-pose
head of the bone it hangs from (`BONES`), so a piece needs no per-character offset: `UnitVisual`
hangs it from that bone with a `BoneAttachment3D` and undoes the bone's rest rotation, so at rest
it sits where it is modelled here, and it moves with the bone from there. Taller or shorter
characters scale the whole model, gear and all.

| piece | bone | colour |
|---|---|---|
| sword, hammer, staff | DEF-hand.R | own (steel, wood, leather) |
| shield, shield_large | DEF-hand.L | own |
| helmet, mail_coif | DEF-head | own |
| veil | DEF-head | the wearer's palette (`trim`) |
| skirt_long | DEF-hips | the wearer's palette, its own squares (`skirt`; `hose` front and back) |
| skirt_short, apron | DEF-hips | the wearer's palette (`skirt`) |
| mantle | DEF-spine.003 | the wearer's palette (`tunic`) |

`resources/gear/<piece>.tres` holds that table for the game.

Pieces with their own colours (steel, wood, leather) take them from one shared 8 x 1 palette,
`assets/gear/palette-gear.png`, which this tool also writes: each face's texture coordinates point
at its colour's square. Cloth pieces carry no colour: every texture coordinate points at the first
square of a character's 16 x 1 palette (`tools/make_character.py`), and the wearer's material
shifts it to the square of a region, so the same file is white on one figure and teal on another. Either way a piece is drawn
with the same kind of material as the body, so it adds no shader to compile. For the same reason
cloth, and the mail coif, are made two-sided in their geometry (a second, inward-facing copy of
each face) rather than by their material.

Cloth pieces are rigid, but have shape keys (`fore`, `aft`, `left`, `right`) that stand the cloth
out that way as over a knee, to at most 1.4 times the hem's reach, and lift the hem over a leg it
cannot hold: the game sets them from the legs each frame, so a striding leg stays inside the skirt
and a running figure's mantle swings back. Skirts and the apron also have a `flat` key that lays
the hem flat round the legs for a figure lying on the floor, and skirts a `seat` key that lays the
front over a seated figure's lap.

The output is byte-identical from one run to the next: the mesh is built in a fixed order, and the
exporter's generator string (which names the Blender version) is replaced by this tool's name.
Every piece stays under 600 triangles.

The mesh machinery (`Piece`, the export) is shared with `heads.py` in `wearable.py`.

For each cloth piece with shape keys it also writes `assets/gear/<piece>_cloth.tres`, a `ClothShape`:
per key and per ring of the mesh, how far the piece reaches that way at rest and how much further the
key takes it. The game fits the cloth from these tables and never reads the mesh back.
"""
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(1, str(Path(__file__).resolve().parents[1]))
from make_character import HOSE, REGION_NAMES, SKIRT  # noqa: E402
from wearable import KEY_DIRECTIONS, Piece, add, cross, dot, export, mul, require_blender, sub, unit  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "assets/gear"
MAX_TRIANGLES = 600

# Rest-pose bone heads of the human model, in its frame (read from human.glb's skeleton).
BONES = {
    "DEF-hips": (0.0, 0.917, 0.05),
    "DEF-spine.001": (0.0, 1.0505, 0.0156),
    "DEF-spine.003": (0.0, 1.315, 0.005),
    "DEF-head": (0.0, 1.569, -0.005),
    "DEF-hand.R": (0.739, 1.441, 0.065),
    "DEF-hand.L": (-0.739, 1.441, 0.065),
    "DEF-upper_arm.R": (0.1919, 1.4408, 0.0654),
    "DEF-upper_arm.L": (-0.1919, 1.4408, 0.0654),
    "DEF-forearm.R": (0.4663, 1.4408, 0.0701),
    "DEF-forearm.L": (-0.4663, 1.4408, 0.0701),
}
# The middle of the right fist, from the wrist (the hand's bone head) at rest: the fingers curl
# down, under the hand, and the grip runs front to back (along z), the index finger in front.
FIST_R = (0.09, -0.03, 0.0)
# The shield sits on the back of the left hand and forearm: the hand points along -x at rest, and
# the back of the hand faces +y.
SHIELD_AT = (0.08, 0.075, 0.0)
# Where each thing held in the right fist points at rest. Straight along the grip (-z), a sword
# would point up across the chest in the idle pose, so each is turned in the hand towards how it
# should hang in `idle` (worked out from the right hand's turn between the rest pose and `idle`):
# the sword about level and forward (and still along its swing in `attack`), the hammer head down
# and forward, the staff upright.
SWORD_AXIS = (0.59, 0.14, -0.8)
HAMMER_AXIS = (0.86, 0.01, -0.51)
STAFF_AXIS = (-0.8, 0.16, -0.57)


# The squares of the gear palette, left to right.
GEAR_PALETTE = ["#b8c0c6", "#6e757c", "#8e959b", "#8a5e36", "#a8804e", "#5a3c26", "#000000", "#000000"]
STEEL, DARK_STEEL, MAIL, WOOD, PALE_WOOD, LEATHER = range(6)
CLOTH_UV = (0.5 / len(REGION_NAMES), 0.5)  # the middle of a character palette's first square
# Cloth whose faces point at the true squares of the wearer's palette, as the garments' do
# (`garments.py`), so it can be two colours and is drawn with the body's own material.
OWN_SQUARES = {"skirt_long"}
# How far a stretching key takes cloth at most: this share of its hem's reach further out that way.
# The mantle hangs from the shoulders, so a crouch already swings it back: it gives less.
SPREAD, MANTLE_SPREAD = 0.4, 0.25
# How far a skirt's hem rides up, at most, where a leg pushes it out squarely: over a knee it cannot hold.
LONG_LIFT, SHORT_LIFT = 0.45, 0.1

# How far the apron's hem comes back to lie on the legs when its wearer lies down.
APRON_FLAT = 0.11

# ---- the pieces --------------------------------------------------------------------------------

def fist(offset) -> tuple:
    return add(add(BONES["DEF-hand.R"], FIST_R), offset)


def held(axis) -> tuple:
    """For a thing held along `axis`: that axis, the axis across it nearest the hand's length (+x),
    and the third."""
    along = unit(axis)
    across = unit(sub((1, 0, 0), mul(along, dot((1, 0, 0), along))))
    return along, across, cross(along, across)


def sword() -> Piece:
    p = Piece("sword", "DEF-hand.R", False)
    along, across, flat = held(SWORD_AXIS)
    axes = (across, flat, along)
    p.tube(fist(mul(along, -0.07)), fist(mul(along, 0.055)), 0.017, 6, LEATHER)  # grip
    p.box(fist(mul(along, -0.09)), (0.04, 0.04, 0.035), DARK_STEEL, axes)  # pommel
    p.box(fist(mul(along, 0.07)), (0.2, 0.03, 0.03), DARK_STEEL, axes)  # crossguard, across the grip
    p.box(fist(mul(along, 0.43)), (0.05, 0.012, 0.69), STEEL, axes)  # blade, its edges across
    base, tip = fist(mul(along, 0.775)), fist(mul(along, 0.86))
    corners = [p.vertex(add(base, add(mul(across, w), mul(flat, t))))
               for w, t in ((-0.025, -0.006), (0.025, -0.006), (0.025, 0.006), (-0.025, 0.006))]
    point = p.vertex(tip)
    for a, b in zip(corners, corners[1:] + corners[:1]):
        mid = mul(add(p.verts[a], p.verts[b]), 0.5)
        p.face([a, b, point], add(sub(mid, base), mul(along, 0.03)), STEEL)
    return p


def hammer() -> Piece:
    p = Piece("hammer", "DEF-hand.R", False)
    along, across, flat = held(HAMMER_AXIS)
    p.tube(fist(mul(along, -0.09)), fist(mul(along, 0.34)), 0.016, 6, PALE_WOOD)  # handle
    p.box(fist(mul(along, 0.33)), (0.07, 0.17, 0.07), DARK_STEEL, (across, flat, along))  # head, across the handle
    return p


def staff() -> Piece:
    p = Piece("staff", "DEF-hand.R", False)
    axis = unit(STAFF_AXIS)
    p.tube(fist(mul(axis, -1.1)), fist(mul(axis, 0.62)), 0.022, 6, WOOD)
    p.tube(fist(mul(axis, 0.62)), fist(mul(axis, 0.7)), 0.03, 6, PALE_WOOD, end_radius=0.012)  # the head
    return p


def kite(length: float, width: float) -> list[tuple]:
    """A kite shield's outline as (along, across) points, `along` running from the top (-) to the
    point (+), anticlockwise."""
    top = -0.33 * length
    shape = [(top, 0.0), (top + 0.01 * length, 0.3 * width), (top + 0.05 * length, 0.47 * width),
             (top + 0.2 * length, 0.5 * width), (top + 0.42 * length, 0.42 * width),
             (top + 0.7 * length, 0.22 * width), (top + length, 0.0)]
    return shape + [(a, -w) for a, w in reversed(shape[1:-1])]


def shield(name: str, length: float, width: float) -> Piece:
    p = Piece(name, "DEF-hand.L", False)
    centre = add(BONES["DEF-hand.L"], SHIELD_AT)
    along, across, face = (-1, 0, 0), (0, 0, 1), (0, 1, 0)
    thickness = 0.03
    outline = kite(length, width)

    def at(a: float, w: float, lift: float):
        # The face bows outward: its middle stands a little proud of its edges.
        bow = 0.06 * (1 - (2 * w / width) ** 2)
        return add(centre, add(add(mul(along, a), mul(across, w)), mul(face, lift + bow)))

    front = [p.vertex(at(a, w, 0.0)) for a, w in outline]
    back = [p.vertex(at(a, w, -thickness)) for a, w in outline]
    middle = (sum(a for a, _ in outline) / len(outline), 0.0)
    front_middle = p.vertex(at(*middle, 0.0))
    back_middle = p.vertex(at(*middle, -thickness))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        p.face([front[i], front[j], front_middle], face, WOOD)
        p.face([back[i], back[j], back_middle], mul(face, -1), LEATHER)
        a, w = outline[i]
        b, v = outline[j]
        p.face([front[i], front[j], back[j], back[i]], add(mul(along, a + b), mul(across, w + v)), DARK_STEEL)
    p.box(at(middle[0] - 0.02, 0.0, 0.015), (0.09, 0.03, 0.09), STEEL, axes=(along, face, across))  # boss
    return p


def helmet() -> Piece:
    p = Piece("helmet", "DEF-head", False)
    p.lathe([(1.93, 0.012, 0.014, -0.005, 0), (1.895, 0.068, 0.083, -0.005, 0), (1.845, 0.103, 0.127, -0.005, 0),
             (1.775, 0.118, 0.146, -0.005, 0), (1.735, 0.121, 0.15, -0.005, 0)], 12, STEEL, cap=True)
    p.lathe([(1.735, 0.123, 0.152, -0.005, 0), (1.705, 0.123, 0.152, -0.005, 0)], 12, DARK_STEEL)  # the brow band
    p.box((0.0, 1.66, -0.163), (0.022, 0.12, 0.014), DARK_STEEL)  # the nasal
    return p


def mail_coif() -> Piece:
    p = Piece("mail_coif", "DEF-head", False)
    p.lathe([(1.865, 0.05, 0.06, -0.005, 178), (1.805, 0.1, 0.128, -0.005, 165), (1.72, 0.108, 0.138, -0.005, 150),
             (1.63, 0.113, 0.138, 0.0, 150), (1.55, 0.13, 0.135, 0.01, 150), (1.49, 0.21, 0.175, 0.02, 160),
             (1.43, 0.27, 0.21, 0.02, 170)], 14, MAIL, closed=False, cap=True)
    p.two_sided()
    return p


def veil() -> Piece:
    p = Piece("veil", "DEF-head", True)
    p.lathe([(1.875, 0.03, 0.035, -0.005, 178), (1.85, 0.072, 0.088, -0.005, 172), (1.80, 0.1, 0.128, -0.005, 150),
             (1.72, 0.107, 0.137, -0.005, 140), (1.63, 0.112, 0.137, 0.0, 135), (1.55, 0.125, 0.133, 0.01, 135),
             (1.48, 0.185, 0.165, 0.02, 140)], 14, closed=False, cap=True)
    p.two_sided()
    return p


SKIRT_TOP = [(1.03, 0.175, 0.135, 0.0, 0), (0.92, 0.205, 0.165, 0.0, 0)]


def skirt_long() -> Piece:
    p = Piece("skirt_long", "DEF-hips", True)
    rings = SKIRT_TOP + [(0.75, 0.245, 0.205, 0.0, 0), (0.5, 0.28, 0.24, 0.0, 0), (0.3, 0.305, 0.265, 0.0, 0),
                         (0.1, 0.33, 0.29, 0.0, 0)]
    p.lathe(rings, 16, SKIRT, keys={name: (SPREAD, LONG_LIFT, 0.95, 0.65) for name in KEY_DIRECTIONS}, flat=(0.95, 0.1),
            seat=(0.95, 0.42, -0.05))
    # Alvar's scapular hangs on down the front and back: those faces take the hose square, which
    # the other long skirts' palettes colour as the skirt.
    for i, face in enumerate(p.faces):
        x, _, z = (sum(p.verts[v][k] for v in face) / len(face) for k in range(3))
        if abs(x) < 0.4 * abs(z):
            p.colours[i] = HOSE
    p.two_sided()
    return p


def skirt_short() -> Piece:
    p = Piece("skirt_short", "DEF-hips", True)
    rings = SKIRT_TOP + [(0.75, 0.245, 0.205, 0.0, 0), (0.5, 0.285, 0.245, 0.0, 0)]
    p.lathe(rings, 16, keys={name: (SPREAD, SHORT_LIFT, 0.95, 0.65) for name in KEY_DIRECTIONS}, flat=(0.95, 0.5),
            seat=(0.95, 0.42, -0.05))
    p.two_sided()
    return p


def apron() -> Piece:
    p = Piece("apron", "DEF-hips", True)
    p.keys["fore"] = []
    p.keys["flat"] = []
    rows = [(1.32, 0.3, -0.15), (1.1, 0.32, -0.15), (0.95, 0.34, -0.15), (0.75, 0.37, -0.16), (0.5, 0.4, -0.17)]
    columns = 6
    grid = []
    for y, width, z in rows:
        row = []
        for i in range(columns + 1):
            x = width * (i / columns - 0.5)
            index = p.vertex((x, y, z + 0.03 * (2 * x / width) ** 2))
            depth = min(max((0.95 - y) / (0.95 - 0.5), 0.0), 1.0)
            p.keys["fore"][index] = (0.0, 0.0, -0.4 * depth)
            # Laid flat: the hanging part back against the legs of a figure lying on its back.
            p.keys["flat"][index] = (0.0, 0.0, APRON_FLAT * depth)
            row.append(index)
        grid.append(row)
    for upper, lower in zip(grid, grid[1:]):
        for i in range(columns):
            p.face([upper[i], upper[i + 1], lower[i + 1], lower[i]], (0, 0, -1))
    # Its ties round the waist, so it shows from behind too.
    p.lathe([(1.06, 0.172, 0.135, 0.0, 0), (1.0, 0.172, 0.135, 0.0, 0)], 12)
    p.two_sided()
    return p


def mantle() -> Piece:
    p = Piece("mantle", "DEF-spine.003", True)
    arc = 100
    rings = [(1.5, 0.19, 0.14, 0.02, arc), (1.44, 0.27, 0.19, 0.02, arc), (1.25, 0.34, 0.24, 0.03, arc),
             (0.95, 0.4, 0.29, 0.03, arc), (0.65, 0.42, 0.33, 0.03, arc), (0.38, 0.44, 0.36, 0.03, arc)]
    p.lathe(rings, 14, closed=False, keys={"aft": (MANTLE_SPREAD, 0.0, 1.25, 0.38)})
    p.two_sided()
    return p


PIECES = [sword, hammer, staff, lambda: shield("shield", 0.85, 0.5), lambda: shield("shield_large", 1.05, 0.58),
          helmet, mail_coif, veil, skirt_long, skirt_short, apron, mantle]


# ---- writing them ------------------------------------------------------------------------------

def build(piece: Piece) -> None:
    def uv_of(colour):
        if piece.name in OWN_SQUARES:
            return ((colour + 0.5) / len(REGION_NAMES), 0.5)
        return CLOTH_UV if piece.cloth else ((colour + 0.5) / len(GEAR_PALETTE), 0.5)

    export(piece, BONES[piece.bone], OUT / f"{piece.name}.glb", uv_of, piece.cloth, "tools/blender/gear.py")


def write_shape(piece: Piece) -> None:
    """The piece's `ClothShape`: for each stretching key and each ring height (to the millimetre),
    the reach of the ring's furthest vertex that way at rest and that vertex's extra reach under the
    key, in the piece's frame."""
    origin = BONES[piece.bone]
    names = [name for name in KEY_DIRECTIONS if name in piece.keys]
    tables = []
    for name in names:
        way = KEY_DIRECTIONS[name]
        by_height: dict[int, tuple[float, float]] = {}
        for v, offset in zip(piece.verts, piece.keys[name]):
            local = sub(v, origin)
            height = round(local[1] * 1000)
            reach, extra = dot(local, way), dot(offset, way)
            if height not in by_height or reach > by_height[height][0]:
                by_height[height] = (reach, extra)
        rows = ", ".join("%.5f, %.5f, %.5f" % (h / 1000, r, e) for h, (r, e) in sorted(by_height.items()))
        tables.append(f"PackedVector3Array({rows})")
    text = "\n".join([
        '[gd_resource type="Resource" script_class="ClothShape" load_steps=2 format=3]', "",
        '[ext_resource type="Script" path="res://src/units/cloth_shape.gd" id="1_shape"]', "",
        "[resource]", 'script = ExtResource("1_shape")',
        "keys = PackedStringArray(%s)" % ", ".join(f'"{n}"' for n in names),
        "rings = Array[PackedVector3Array]([%s])" % ", ".join(tables),
        "flattens = %s" % ("true" if "flat" in piece.keys else "false"),
        "seats = %s" % ("true" if "seat" in piece.keys else "false"), ""])
    (OUT / f"{piece.name}_cloth.tres").write_text(text)
    print(f"wrote {piece.name}_cloth.tres")


def write_palette() -> None:
    """The gear palette as an 8 x 1 RGB PNG, written byte by byte so it never changes."""
    row = b"\x00" + b"".join(bytes(int(c[i:i + 2], 16) for i in (1, 3, 5)) for c in GEAR_PALETTE)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    header = struct.pack(">IIBBBBB", len(GEAR_PALETTE), 1, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(row, 9)) + chunk(b"IEND", b"")
    (OUT / "palette-gear.png").write_bytes(png)
    print("wrote palette-gear.png")


def main() -> None:
    require_blender("gear")
    OUT.mkdir(parents=True, exist_ok=True)
    write_palette()
    for make in PIECES:
        piece = make()
        triangles = piece.triangles()
        if triangles >= MAX_TRIANGLES:
            sys.exit(f"gear: {piece.name} has {triangles} triangles, at most {MAX_TRIANGLES - 1} allowed")
        build(piece)
        if piece.cloth and piece.keys:
            write_shape(piece)
        print(f"wrote {piece.name}.glb: {triangles} triangles")


if __name__ == "__main__":
    main()
