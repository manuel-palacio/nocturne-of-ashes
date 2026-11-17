"""Makes the gear and cloth pieces worn on the human model, one `.glb` per piece in `assets/gear/`.

    blender -b --factory-startup -P tools/blender/gear.py

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
| hood, veil | DEF-head | the wearer's palette (`tunic`, `trim`) |
| skirt_long, skirt_short, apron | DEF-hips | the wearer's palette (`skirt`) |
| mantle | DEF-spine.003 | the wearer's palette (`tunic`) |

`resources/gear/<piece>.tres` holds that table for the game.

Pieces with their own colours (steel, wood, leather) take them from one shared 8 x 1 palette,
`assets/gear/palette-gear.png`, which this tool also writes: each face's texture coordinates point
at its colour's square. Cloth pieces carry no colour: every texture coordinate points at the first
square of a character's 8 x 1 palette, and the wearer's material shifts it to the square of a
region, so the same file is white on one figure and teal on another. Either way a piece is drawn
with the same kind of material as the body, so it adds no shader to compile. For the same reason
cloth, and the mail coif, are made two-sided in their geometry (a second, inward-facing copy of
each face) rather than by their material.

Cloth pieces are rigid, but have shape keys (`fore`, `aft`, `left`, `right`) that stretch the hem
that way, more the further below the top: the game sets them from the legs each frame, so a
striding leg stays inside the skirt and a running figure's mantle swings back. Skirts also have a
`flat` key that lays the hem flat round the legs, front and back, for a figure lying on the floor.

The output is byte-identical from one run to the next: the mesh is built in a fixed order, and the
exporter's generator string (which names the Blender version) is replaced by this tool's name.
Every piece stays under 600 triangles.
"""
import json
import math
import struct
import sys
import zlib
from pathlib import Path

import bmesh
import bpy

OUT = Path(__file__).resolve().parents[2] / "assets/gear"
MAX_TRIANGLES = 600

# Rest-pose bone heads of the human model, in its frame (read from human.glb's skeleton).
BONES = {
    "DEF-hips": (0.0, 0.917, 0.05),
    "DEF-spine.003": (0.0, 1.315, 0.005),
    "DEF-head": (0.0, 1.569, -0.005),
    "DEF-hand.R": (0.739, 1.441, 0.065),
    "DEF-hand.L": (-0.739, 1.441, 0.065),
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
CLOTH_UV = (0.5 / 8, 0.5)  # the middle of the palette's first square

FLAT_DEPTH, FLAT_WIDTH = 0.35, 0.15
KEY_DIRECTIONS = {"fore": (0, 0, -1), "aft": (0, 0, 1), "left": (-1, 0, 0), "right": (1, 0, 0)}


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x * k for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    length = math.sqrt(dot(a, a))
    return mul(a, 1.0 / length)


class Piece:
    """A mesh in the model's frame: vertices, faces wound to face `out`, a colour per face, and
    shape-key offsets per vertex."""

    def __init__(self, name: str, bone: str, cloth: bool):
        self.name, self.bone, self.cloth = name, bone, cloth
        self.verts: list[tuple] = []
        self.faces: list[tuple] = []
        self.colours: list[tuple] = []
        self.keys: dict[str, list[tuple]] = {}

    def vertex(self, p) -> int:
        self.verts.append(tuple(float(c) for c in p))
        for offsets in self.keys.values():
            offsets.append((0.0, 0.0, 0.0))
        return len(self.verts) - 1

    def face(self, indices, out, colour=None) -> None:
        """Adds a face, reversed if its normal does not point along `out`."""
        points = [self.verts[i] for i in indices]
        normal = (0.0, 0.0, 0.0)
        for a, b in zip(points, points[1:] + points[:1]):  # Newell's method
            normal = add(normal, ((a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]),
                                  (a[0] - b[0]) * (a[1] + b[1])))
        if dot(normal, out) < 0:
            indices = list(reversed(indices))
        self.faces.append(tuple(indices))
        self.colours.append(colour)

    def two_sided(self) -> None:
        """Adds an inward-facing copy of every face, on vertices of its own, so both sides are drawn
        with back faces culled and each side is lit by its own normals."""
        count = len(self.verts)
        for v in list(self.verts):
            self.verts.append(v)
        for name, offsets in self.keys.items():
            self.keys[name] = offsets + offsets[:count]
        for face, colour in list(zip(self.faces, self.colours)):
            self.faces.append(tuple(i + count for i in reversed(face)))
            self.colours.append(colour)

    def triangles(self) -> int:
        return sum(len(f) - 2 for f in self.faces)

    def box(self, centre, size, colour, axes=((1, 0, 0), (0, 1, 0), (0, 0, 1))) -> None:
        """A box of `size` along the unit `axes`."""
        corners = []
        for i in range(8):
            p = centre
            for axis, half, sign in zip(axes, mul(size, 0.5), ((i >> 0) & 1, (i >> 1) & 1, (i >> 2) & 1)):
                p = add(p, mul(axis, half if sign else -half))
            corners.append(self.vertex(p))
        for axis in range(3):
            for sign in (0, 1):
                quad = [i for i in range(8) if (i >> axis) & 1 == sign]
                quad = [quad[0], quad[1], quad[3], quad[2]]
                out = mul(axes[axis], 1 if sign else -1)
                self.face([corners[i] for i in quad], out, colour)

    def tube(self, start, end, radius, sides, colour, end_radius=None, caps=True) -> None:
        """A closed prism (or a cone, with `end_radius`) from `start` to `end`."""
        axis = unit(sub(end, start))
        side = unit(cross(axis, (0, 1, 0) if abs(axis[1]) < 0.9 else (1, 0, 0)))
        other = cross(axis, side)
        rings = []
        for centre, r in ((start, radius), (end, radius if end_radius is None else end_radius)):
            ring = []
            for i in range(sides):
                a = 2 * math.pi * i / sides
                ring.append(self.vertex(add(centre, add(mul(side, r * math.cos(a)), mul(other, r * math.sin(a))))))
            rings.append(ring)
        for i in range(sides):
            j = (i + 1) % sides
            a = 2 * math.pi * (i + 0.5) / sides
            self.face([rings[0][i], rings[0][j], rings[1][j], rings[1][i]],
                      add(mul(side, math.cos(a)), mul(other, math.sin(a))), colour)
        if caps:
            self.face(rings[0], mul(axis, -1), colour)
            self.face(rings[1], axis, colour)

    def lathe(self, rings, sides, colour=None, closed=True, cap=False, keys=None, flat=None) -> None:
        """Rings, top to bottom, of `(y, rx, rz, cz, half_arc)`: an ellipse of half-widths `rx`, `rz`
        about `(0, y, cz)`. Angle 0 is the back (+z), 90 degrees the right (+x). A closed lathe goes
        all round; an open one spans `half_arc` degrees either side of the back. `cap` closes the
        top with a point. `keys` maps a shape key's name to `(reach, top, hem)`: at full weight the
        vertices facing the key's way move that way by up to `reach`, from nothing at height `top`
        to all of it at `hem` and below, rising fastest near the top. `flat`, as `(top, hem)`, adds a `flat` key that, as deep,
        squeezes the hem front to back to `FLAT_DEPTH` of its depth and widens it by `FLAT_WIDTH`."""
        for name in list(keys or {}) + (["flat"] if flat else []):
            self.keys.setdefault(name, [(0.0, 0.0, 0.0)] * len(self.verts))
        count = sides if closed else sides + 1
        grid = []
        for y, rx, rz, cz, half_arc in rings:
            ring = []
            for i in range(count):
                if closed:
                    a = 2 * math.pi * i / sides
                else:
                    a = math.radians(-half_arc + 2 * half_arc * i / sides)
                index = self.vertex((rx * math.sin(a), y, cz + rz * math.cos(a)))
                radial = (math.sin(a), 0.0, math.cos(a))
                for name, (reach, top, hem) in (keys or {}).items():
                    toward = KEY_DIRECTIONS[name]
                    # Rising fast below the top, as cloth gives most round a knee lifted high.
                    depth = min(max((top - y) / (top - hem), 0.0), 1.0) ** 0.6
                    self.keys[name][index] = mul(toward, reach * depth * max(dot(radial, toward), 0.0))
                if flat:
                    depth = min(max((flat[0] - y) / (flat[0] - flat[1]), 0.0), 1.0)
                    self.keys["flat"][index] = (rx * math.sin(a) * FLAT_WIDTH * depth, 0.0,
                                                -rz * math.cos(a) * (1 - FLAT_DEPTH) * depth)
                ring.append(index)
            grid.append(ring)
        for upper, lower, (y, rx, rz, cz, _) in zip(grid, grid[1:], rings):
            for i in range(count if closed else count - 1):
                j = (i + 1) % count
                a = (2 * math.pi * (i + 0.5) / sides) if closed else math.radians(
                    -rings[0][4] + 2 * rings[0][4] * (i + 0.5) / sides)
                self.face([upper[i], upper[j], lower[j], lower[i]], (math.sin(a), 0.0, math.cos(a)), colour)
        if cap:
            y, rx, rz, cz, _ = rings[0]
            tip = self.vertex((0.0, y + 0.02, cz))
            for i in range(count if closed else count - 1):
                j = (i + 1) % count
                self.face([grid[0][i], grid[0][j], tip], (0, 1, 0), colour)


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


def hood() -> Piece:
    p = Piece("hood", "DEF-head", True)
    p.lathe([(1.895, 0.04, 0.05, 0.03, 175), (1.86, 0.095, 0.115, 0.015, 165), (1.80, 0.118, 0.145, 0.0, 150),
             (1.70, 0.123, 0.148, 0.0, 140), (1.60, 0.128, 0.143, 0.005, 140), (1.52, 0.155, 0.15, 0.015, 145),
             (1.45, 0.245, 0.195, 0.02, 160)], 14, closed=False, cap=True)
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
    rings = SKIRT_TOP + [(0.75, 0.25, 0.21, 0.0, 0), (0.5, 0.3, 0.26, 0.0, 0), (0.3, 0.33, 0.29, 0.0, 0),
                         (0.1, 0.36, 0.32, 0.0, 0)]
    p.lathe(rings, 16, keys={name: (0.5, 0.95, 0.1) for name in KEY_DIRECTIONS}, flat=(0.95, 0.1))
    p.two_sided()
    return p


def skirt_short() -> Piece:
    p = Piece("skirt_short", "DEF-hips", True)
    rings = SKIRT_TOP + [(0.75, 0.245, 0.205, 0.0, 0), (0.5, 0.285, 0.245, 0.0, 0)]
    p.lathe(rings, 16, keys={name: (0.35, 0.95, 0.5) for name in KEY_DIRECTIONS}, flat=(0.95, 0.5))
    p.two_sided()
    return p


def apron() -> Piece:
    p = Piece("apron", "DEF-hips", True)
    p.keys["fore"] = []
    rows = [(1.32, 0.3, -0.15), (1.1, 0.32, -0.15), (0.95, 0.34, -0.15), (0.75, 0.37, -0.16), (0.5, 0.4, -0.17)]
    columns = 6
    grid = []
    for y, width, z in rows:
        row = []
        for i in range(columns + 1):
            x = width * (i / columns - 0.5)
            index = p.vertex((x, y, z + 0.06 * (2 * x / width) ** 2))
            depth = min(max((0.95 - y) / (0.95 - 0.5), 0.0), 1.0)
            p.keys["fore"][index] = (0.0, 0.0, -0.4 * depth)
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
    p.lathe(rings, 14, closed=False, keys={"aft": (0.45, 1.25, 0.38)})
    p.two_sided()
    return p


PIECES = [sword, hammer, staff, lambda: shield("shield", 0.85, 0.5), lambda: shield("shield_large", 1.05, 0.58),
          helmet, mail_coif, hood, veil, skirt_long, skirt_short, apron, mantle]


# ---- writing them ------------------------------------------------------------------------------

def blender_point(p, origin) -> tuple:
    """A point of the model's frame (y up, -z forward), relative to `origin`, in Blender's frame
    (z up), which the exporter turns back: Blender (x, y, z) is glTF (x, z, -y)."""
    x, y, z = sub(p, origin)
    return (x, -z, y)


def build(piece: Piece) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    origin = BONES[piece.bone]
    mesh = bpy.data.meshes.new(piece.name)
    bm = bmesh.new()
    verts = [bm.verts.new(blender_point(v, origin)) for v in piece.verts]
    bm.verts.index_update()
    for indices in piece.faces:
        bm.faces.new([verts[i] for i in indices])
    bm.faces.index_update()
    bm.to_mesh(mesh)
    bm.free()
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon, colour in zip(mesh.polygons, piece.colours):
        uv = CLOTH_UV if piece.cloth else ((colour + 0.5) / len(GEAR_PALETTE), 0.5)
        for loop in polygon.loop_indices:
            layer.data[loop].uv = uv
        polygon.use_smooth = piece.cloth
    obj = bpy.data.objects.new(piece.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if piece.keys:
        obj.shape_key_add(name="Basis", from_mix=False)
        for name, offsets in piece.keys.items():
            key = obj.shape_key_add(name=name, from_mix=False)
            key.value = 0.0
            for point, v, offset in zip(key.data, piece.verts, offsets):
                point.co = blender_point(add(v, offset), origin)
    path = OUT / f"{piece.name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", export_yup=True, export_apply=False,
        export_materials="NONE", export_vertex_color="NONE", export_texcoords=True, export_normals=True, export_tangents=False, export_extras=False,
        export_morph=True, export_morph_normal=True, export_animations=False, export_skins=False,
        export_cameras=False, export_lights=False)
    fix_generator(path)


def fix_generator(path: Path) -> None:
    """Replaces the exporter's generator string, which names its version, with this tool's name."""
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, f"{path.name} is not a glTF 2 binary"
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A, f"{path.name} does not start with its JSON"
    document = json.loads(data[20:20 + length])
    document["asset"] = {"generator": "tools/blender/gear.py", "version": "2.0"}
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    rest = data[20 + length:]
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + len(rest)) + struct.pack(
        "<II", len(text), 0x4E4F534A) + text + rest
    path.write_bytes(out)


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
    OUT.mkdir(parents=True, exist_ok=True)
    write_palette()
    for make in PIECES:
        piece = make()
        triangles = piece.triangles()
        if triangles >= MAX_TRIANGLES:
            sys.exit(f"gear: {piece.name} has {triangles} triangles, at most {MAX_TRIANGLES - 1} allowed")
        build(piece)
        print(f"wrote {piece.name}.glb: {triangles} triangles")


main()
