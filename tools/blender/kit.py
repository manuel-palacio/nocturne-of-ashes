"""Makes the stone kit the rooms are built from, one `.glb` per piece in `assets/kit/`.

    blender -b --factory-startup -P tools/blender/kit.py

Written for Blender 5.3, and it refuses to run with any other version: another version's glTF
exporter may write different bytes.

Every piece is modelled in Godot's frame: metres, y up, its origin at floor level in the middle of
its footprint, and the side that faces the room toward +z. Pieces fit a 2 m grid. Wall-like pieces are
one-sided, drawn only from the room (the wall nearest the camera is not drawn at all), with a top face
for the camera to see from above; the vault is drawn only from below, so the camera sees through it.

| piece | footprint (x by z), height | what | blocks |
|---|---|---|---|
| floor_slab | 2 x 2, 0.1 below the floor | worn flagstones | world |
| wall, wall_brick | 2 x 0.5, 4 | coursed stone / Roman brick, one-sided, closed at its ends | walls |
| wall_corner | 0.5 x 0.5, 4 | the post that fills the corner where two walls meet | walls |
| pillar | 0.8 x 0.8, 4 | brick pier, stone plinth, capital at the impost (2 m), stone cap | world |
| arch_horseshoe | 2 x 0.8, 4 | a bay: horseshoe arch, alternating stone and brick voussoirs, alfiz | world (jambs) |
| arch_round | 4 x 0.8, 4 | a bay: Roman round arch in radial brick | world (jambs) |
| arch_segmental | 6 x 0.8, 4 | a wide bay: Roman segmental arch in radial brick, for an arcade on piers 6 m apart | world (jambs) |
| vault_barrel | 4 x 2, from 4 to 6 | a barrel vault segment in brick, seen from below only | nothing |
| door_frame | 2 x 0.5, 4 | a wall bay with a 1.4 x 2.4 doorway in dressed stone | walls |
| door_leaf | 1.4 x 0.1, 2.4 | planked door with iron straps, studs and a ring | nothing (the door scene's body does) |
| stair_down | 2 x 4, 2.4 below the floor | a flight going down toward -z under a lintel | walls (a low barrier round its mouth and sides) |
| forge | 2.6 x 1.4, 4 | hearth with a fire pan, a plastered hood and flue | world (hearth) |
| anvil, rack, barrel, bench | props | | world |
| bars | 2 x 0.06, 2.4 | an iron grille | walls (blocks units, not clicks) |
| sconce | 0.16 x 0.4, from 1.9 to 2.6 | an iron torch bracket; its back is flat at z = -0.2 | nothing |
| lock_seal | 1.4 x 0.3, 2.4 | a stone slab barred by iron, a great padlock | nothing (the door scene's body does) |

The arch bays carry their own jambs (half a pier each side, with the pillar's plinth and impost), so a
row of bays is an arcade whose neighbouring jambs make the piers; the impost is at 2 m, as on the
pillar. A segmental arch is a third of a circle, so it rises 1.5 m over its 5.2 m opening and stays
under the bay's top. A horseshoe arch's curve continues a third of its radius below its centre line, so the opening
is narrower at the impost (1.2 m) than at its widest (1.27 m).

Materials: each face uses one of five shared materials, by name: stone, brick, plaster, wood, iron.
The pieces carry no textures; `tools/kit_import.gd` (the pieces' import script) swaps each named
material for `resources/materials/<name>.tres`, whose textures are in `assets/textures/`. Texture
coordinates are set here, at world scale: flat faces are box-mapped (`SCALE` gives the metres per
repeat), so a texture runs on across neighbouring pieces on the 2 m grid, turned by any multiple of
90 degrees. Brick is stretched to 2 m by 1 m per repeat, which makes its bricks long and thin, as
Roman bricks are. Arch rings and vaults are mapped round their curve instead, so their bricks and
voussoirs radiate from the centre.

Collision: where a piece blocks movement it has boxes (or a prism) named `...-convcolonly`, which
Godot's importer turns into `StaticBody3D`s with convex shapes and no mesh. Each collider's name says
its layer: `<piece>_block<n>-walls-convcolonly` for layer 3 "walls", which units bump into but the
click ray passes through, and `<piece>_block<n>-convcolonly` for layer 1 "world", which stops both.
The import script reads the marker; the layer is written down only here, in the piece.

The output is byte-identical from one run to the next: the meshes are built in a fixed order, and the
exporter's generator string (which names the Blender version) is replaced by this tool's name. Every
piece stays under 2,000 triangles.
"""
import json
import math
import struct
import sys
from pathlib import Path

import bmesh
import bpy

BLENDER = (5, 3)  # the version the output is pinned to
OUT = Path(__file__).resolve().parents[2] / "assets/kit"
MAX_TRIANGLES = 2000

# The shared materials, and the metres per texture repeat along u and v.
SCALE = {"stone": (2.0, 2.0), "brick": (2.0, 1.0), "plaster": (2.0, 2.0), "wood": (1.0, 1.0), "iron": (1.0, 1.0)}
MATERIALS = list(SCALE)

IMPOST = 2.0  # height of the capitals that arches spring from
HEIGHT = 4.0  # walls, piers and arch bays
WALL_HALF = 0.25  # half a wall's thickness
BAY_HALF = 0.37  # half an arch bay's thickness, without what stands proud of it
PROUD = 0.03  # how far arch rings stand out from a bay's faces


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
    return mul(a, 1.0 / math.sqrt(dot(a, a)))


def newell(points) -> tuple:
    normal = (0.0, 0.0, 0.0)
    for a, b in zip(points, points[1:] + points[:1]):
        normal = add(normal, ((a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]),
                              (a[0] - b[0]) * (a[1] + b[1])))
    return normal


def box_mapping(normal, scale, turn=False):
    """World-scale texture coordinates for a flat face: projected along the axis the face looks down,
    upright on walls, and the same on every face that looks the same way. `turn` turns it 90 degrees."""
    su, sv = scale
    axis = max(range(3), key=lambda i: abs(normal[i]))
    sign = 1.0 if normal[axis] > 0 else -1.0
    if axis == 1:
        flat = lambda p: (p[0], -sign * p[2])
    elif axis == 2:
        flat = lambda p: (sign * p[0], p[1])
    else:
        flat = lambda p: (-sign * p[2], p[1])
    if turn:
        return lambda p: (flat(p)[1] / su, -flat(p)[0] / sv)
    return lambda p: (flat(p)[0] / su, flat(p)[1] / sv)


class Piece:
    """A piece's faces, each with its own corners, a material and texture coordinates, and the boxes
    (or prisms) that block movement."""

    def __init__(self, name: str):
        self.name = name
        self.faces: list[tuple[list, str, list]] = []
        self.colliders: list[tuple[str, list[tuple]]] = []  # (layer, convex point cloud)

    def face(self, points, out, material, uvs=None, scale=None, turn=False) -> None:
        """Adds a face wound to look along `out`. Without `uvs` it is box-mapped at the material's
        scale (or `scale`)."""
        points = [tuple(float(c) for c in p) for p in points]
        if uvs is not None:
            uvs = [tuple(float(c) for c in uv) for uv in uvs]
        if dot(newell(points), out) < 0:
            points.reverse()
            if uvs is not None:
                uvs.reverse()
        if uvs is None:
            mapping = box_mapping(newell(points), scale or SCALE[material], turn)
            uvs = [mapping(p) for p in points]
        self.faces.append((points, material, uvs))

    def triangles(self) -> int:
        return sum(len(points) - 2 for points, _, _ in self.faces)

    def box(self, lo, hi, material, skip=(), scale=None, turn=False) -> None:
        """An axis-aligned box from corner `lo` to corner `hi`, without the faces named in `skip`
        (`-x`, `+x`, `-y`, `+y`, `-z`, `+z`)."""
        for axis, name in enumerate("xyz"):
            for sign, side in ((-1, "-"), (1, "+")):
                if side + name in skip:
                    continue
                level = hi[axis] if sign > 0 else lo[axis]
                u, v = [a for a in range(3) if a != axis]
                corners = []
                for cu, cv in ((0, 0), (1, 0), (1, 1), (0, 1)):
                    p = [0.0, 0.0, 0.0]
                    p[axis] = level
                    p[u] = hi[u] if cu else lo[u]
                    p[v] = hi[v] if cv else lo[v]
                    corners.append(tuple(p))
                out = [0, 0, 0]
                out[axis] = sign
                self.face(corners, out, material, scale=scale, turn=turn)

    def beam(self, start, end, width, depth, material, up=(0, 1, 0), caps=True) -> None:
        """A box of `width` by `depth` from `start` to `end`, its width across `up`."""
        along = unit(sub(end, start))
        across = unit(cross(along, up)) if abs(dot(along, unit(up))) < 0.99 else (1.0, 0.0, 0.0)
        other = cross(across, along)
        ring = []
        for cw, cd in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            ring.append(add(mul(across, cw * width / 2), mul(other, cd * depth / 2)))
        for i in range(4):
            j = (i + 1) % 4
            mid = mul(add(ring[i], ring[j]), 0.5)
            self.face([add(start, ring[i]), add(start, ring[j]), add(end, ring[j]), add(end, ring[i])], mid, material)
        if caps:
            self.face([add(start, c) for c in ring], mul(along, -1), material)
            self.face([add(end, c) for c in ring], along, material)

    def lathe(self, rings, sides, material, centre=(0.0, 0.0), turn=0.0, inward=False, top=False,
              repeats=None) -> None:
        """A surface of revolution about the vertical through `centre` (x, z): `rings` of `(y, r)` from
        the bottom up, `sides` around, the first corner `turn` degrees from +x. Faces look out (or in,
        with `inward`); `top` closes the last ring. Mapped round the curve, a whole number of
        `repeats` round the circumference, so the seam does not show."""
        su, sv = SCALE[material]
        if repeats is None:
            repeats = max(1, round(2 * math.pi * max(r for _, r in rings) / su))
        grid = []
        for y, r in rings:
            ring = []
            for i in range(sides + 1):
                a = math.radians(turn) + 2 * math.pi * i / sides
                ring.append(((centre[0] + r * math.cos(a), y, centre[1] + r * math.sin(a)), (repeats * i / sides, y / sv)))
            grid.append(ring)
        for lower, upper in zip(grid, grid[1:]):
            for i in range(sides):
                a = math.radians(turn) + 2 * math.pi * (i + 0.5) / sides
                out = (math.cos(a), 0.0, math.sin(a))
                if inward:
                    out = mul(out, -1)
                quad = [lower[i], lower[i + 1], upper[i + 1], upper[i]]
                self.face([p for p, _ in quad], out, material, uvs=[uv for _, uv in quad])
        if top:
            self.face([p for p, _ in grid[-1][:-1]], (0, 1, 0), material)

    def collider(self, lo, hi, layer: str = "world") -> None:
        """A box that blocks movement, on the "world" layer or the "walls" layer."""
        self.colliders.append((layer, [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]))


# ---- walls and floors ----------------------------------------------------------------------------

def floor_slab() -> Piece:
    p = Piece("floor_slab")
    p.box((-1, -0.1, -1), (1, 0, 1), "stone", skip=("-y",))
    p.collider((-1, -0.1, -1), (1, 0, 1))
    return p


def wall(name: str, material: str) -> Piece:
    p = Piece(name)
    p.face([(-1, 0, WALL_HALF), (1, 0, WALL_HALF), (1, HEIGHT, WALL_HALF), (-1, HEIGHT, WALL_HALF)], (0, 0, 1), material)
    p.face([(-1, HEIGHT, -WALL_HALF), (1, HEIGHT, -WALL_HALF), (1, HEIGHT, WALL_HALF), (-1, HEIGHT, WALL_HALF)],
           (0, 1, 0), material)
    for sign in (-1, 1):  # its ends, for a run of wall that stops short of anything
        x = sign * 1.0
        p.face([(x, 0, -WALL_HALF), (x, 0, WALL_HALF), (x, HEIGHT, WALL_HALF), (x, HEIGHT, -WALL_HALF)], (sign, 0, 0), material)
    p.collider((-1, 0, -WALL_HALF), (1, HEIGHT, WALL_HALF), "walls")
    return p


def wall_corner() -> Piece:
    """The square where two walls meet at a room's corner, which neither wall covers: seen from above
    it would be a hole. Stone, as the walls are; brick rooms' corners read the same from above."""
    p = Piece("wall_corner")
    p.box((-WALL_HALF, 0, -WALL_HALF), (WALL_HALF, HEIGHT, WALL_HALF), "stone", skip=("-y",))
    p.collider((-WALL_HALF, 0, -WALL_HALF), (WALL_HALF, HEIGHT, WALL_HALF), "walls")
    return p


def pillar() -> Piece:
    p = Piece("pillar")
    stone = 0.4
    shaft = 0.35
    p.box((-stone, 0, -stone), (stone, 0.3, stone), "stone", skip=("-y",))  # plinth
    p.box((-shaft, 0.3, -shaft), (shaft, IMPOST - 0.2, shaft), "brick", skip=("-y", "+y"))
    p.box((-stone, IMPOST - 0.2, -stone), (stone, IMPOST, stone), "stone", skip=("-y",))  # capital
    p.box((-shaft, IMPOST, -shaft), (shaft, HEIGHT - 0.2, shaft), "brick", skip=("-y", "+y"))
    p.box((-stone, HEIGHT - 0.2, -stone), (stone, HEIGHT, stone), "stone", skip=("-y",))  # cap
    p.collider((-stone, 0, -stone), (stone, HEIGHT, stone))
    return p


# ---- arches --------------------------------------------------------------------------------------

def arch_bay(name: str, half: float, opening: float, below: float, ring: float, voussoirs: int,
             ring_materials: list, wall_material: str, alfiz: bool, chamfer: float) -> Piece:
    """A bay `2 * half` wide, `HEIGHT` tall and `2 * BAY_HALF` thick, open below an arch whose curve
    meets the jambs `opening` either side of the middle at the impost. The curve continues `below`
    (a fraction of its radius) under its centre line: 0 for a round arch, a third for a horseshoe; a
    negative fraction starts it above, for a segmental arch.
    The ring of `voussoirs`, `ring` deep, stands `PROUD` of both faces, cycling through
    `ring_materials`; with `alfiz`, a brick frame round it encloses a plastered field."""
    p = Piece(name)
    start = math.asin(below)  # how far below the centre line the curve begins
    r = opening / math.cos(start)
    cy = IMPOST + r * below
    outer = r + ring
    sub_steps = 2 if voussoirs < 16 else 1
    steps = voussoirs * sub_steps
    angles = [-start + (math.pi + 2 * start) * k / steps for k in range(steps + 1)]

    def at(radius, a):
        return (radius * math.cos(a), cy + radius * math.sin(a))

    depth = BAY_HALF + PROUD
    arc = [at(outer, a) for a in reversed(angles)]  # the extrados, left to right
    # The alfiz: a rectangular frame round the arch from the impost to over the crown, its field
    # plastered, so both kinds of voussoir stand out from it.
    gap, band, raised = 0.03, 0.06, 0.025
    x_in, top = outer + gap, cy + outer + gap
    x_out, top_out = x_in + band, top + band
    for side in (1, -1):  # the room side (+z), then the other
        z = side * BAY_HALF
        if alfiz:
            outline = [(-half, 0), (-opening, 0), (-opening, IMPOST), (-x_out, IMPOST), (-x_out, top_out), (x_out, top_out),
                       (x_out, IMPOST), (opening, IMPOST), (opening, 0), (half, 0), (half, HEIGHT), (-half, HEIGHT)]
            field = [(-x_in, IMPOST)] + arc + [(x_in, IMPOST), (x_in, top), (-x_in, top)]
            p.face([(x, y, z) for x, y in field], (0, 0, side), "plaster")
        else:
            outline = [(-half, 0), (-opening, 0), (-opening, IMPOST)] + arc
            outline += [(opening, IMPOST), (opening, 0), (half, 0), (half, HEIGHT), (-half, HEIGHT)]
        p.face([(x, y, z) for x, y in outline], (0, 0, side), wall_material)
    # The jambs' inner faces, the bay's ends and its top.
    for sign in (-1, 1):
        x = sign * opening
        p.face([(x, 0, -BAY_HALF), (x, 0, BAY_HALF), (x, IMPOST, BAY_HALF), (x, IMPOST, -BAY_HALF)], (-sign, 0, 0), wall_material)
        x = sign * half
        p.face([(x, 0, -BAY_HALF), (x, 0, BAY_HALF), (x, HEIGHT, BAY_HALF), (x, HEIGHT, -BAY_HALF)], (sign, 0, 0), wall_material)
    p.face([(-half, HEIGHT, -BAY_HALF), (half, HEIGHT, -BAY_HALF), (half, HEIGHT, BAY_HALF), (-half, HEIGHT, BAY_HALF)],
           (0, 1, 0), wall_material)
    # The ring: each voussoir's faces mapped round the curve (u across the ring, v along it), so the
    # joints of its stones and bricks radiate from the centre. With a `chamfer`, each voussoir's face
    # is bevelled all round, so every joint and the ring's edges catch the light.
    middle = (r + outer) / 2
    edge = depth - chamfer  # where a voussoir's face meets its bevel, or the face itself
    last = voussoirs - 1
    for v in range(voussoirs):
        angs = angles[v * sub_steps:(v + 1) * sub_steps + 1]
        material = ring_materials[v % len(ring_materials)]
        su, sv = SCALE[material]

        def polar(rho, phi, z):
            x, y = at(rho, phi)
            return (x, y, z), ((rho - r) / su, middle * phi / sv)

        def faces(points, out):
            p.face([pt for pt, _ in points], out, material, uvs=[uv for _, uv in points])

        rim = [(r, a) for a in angs] + [(outer, a) for a in reversed(angs)]
        inset = []
        for rho, phi in rim:
            rho_in = rho + chamfer if rho == r else rho - chamfer
            phi_in = phi + chamfer / rho_in if phi == angs[0] else phi - chamfer / rho_in if phi == angs[-1] else phi
            inset.append((rho_in, phi_in))
        centre = at(middle, (angs[0] + angs[-1]) / 2)
        for side in (1, -1):
            outline = [polar(rho, phi, side * edge) for rho, phi in rim]
            if chamfer:
                face = [polar(rho, phi, side * depth) for rho, phi in inset]
                faces(face, (0, 0, side))
                for i in range(len(rim)):
                    j = (i + 1) % len(rim)
                    mid_xy = mul(add(outline[i][0][:2], outline[j][0][:2]), 0.5)
                    away = unit(sub(mid_xy, centre))
                    faces([outline[i], outline[j], face[j], face[i]], (away[0], away[1], side))
            else:
                faces(outline, (0, 0, side))
            # Where the ring stands proud of the bay's face: its outer edge, and its ends at the imposts.
            zin = side * BAY_HALF
            for a, b in zip(angs, angs[1:]):
                mid = (a + b) / 2
                faces([polar(outer, a, zin), polar(outer, a, side * edge), polar(outer, b, side * edge), polar(outer, b, zin)],
                      (math.cos(mid), math.sin(mid), 0))
            for end, a, toward in ((0, angs[0], -1), (last, angs[-1], 1)):
                if v == end:
                    faces([polar(r, a, zin), polar(outer, a, zin), polar(outer, a, side * edge), polar(r, a, side * edge)],
                          (-toward * math.sin(a), toward * math.cos(a), 0))
        for a, b in zip(angs, angs[1:]):  # the soffit, through the bay
            mid = (a + b) / 2
            (xa, ya), (xb, yb) = at(r, a), at(r, b)
            p.face([(xa, ya, -edge), (xa, ya, edge), (xb, yb, edge), (xb, yb, -edge)], (-math.cos(mid), -math.sin(mid), 0),
                   material, uvs=[(-edge / su, r * a / sv), (edge / su, r * a / sv), (edge / su, r * b / sv), (-edge / su, r * b / sv)])
    # Plinths and imposts: the pillar's, halved, on each jamb, a little into the opening.
    for sign in (-1, 1):
        inner, outer_x = sign * (opening - 0.04), sign * half
        lo_x, hi_x = min(inner, outer_x), max(inner, outer_x)
        skip = ("-y", "+x" if sign > 0 else "-x")
        p.box((lo_x, 0, -BAY_HALF - 0.02), (hi_x, 0.3, BAY_HALF + 0.02), "stone", skip=skip)
        p.box((lo_x, IMPOST - 0.2, -BAY_HALF - 0.02), (hi_x, IMPOST, BAY_HALF + 0.02), "stone", skip=skip)
        p.collider((lo_x, 0, -BAY_HALF), (hi_x, IMPOST, BAY_HALF))
    if alfiz:  # the frame itself, in brick, standing out of the face
        for side in (1, -1):
            z0, z1 = sorted((side * BAY_HALF, side * (BAY_HALF + raised)))
            for sign in (-1, 1):
                lo_x, hi_x = sorted((sign * x_in, sign * x_out))
                p.box((lo_x, IMPOST, z0), (hi_x, top, z1), "brick", skip=("-y", "+y", "-z" if side > 0 else "+z"))
            p.box((-x_out, top, z0), (x_out, top_out, z1), "brick", skip=("-z" if side > 0 else "+z",))
    return p


def arch_horseshoe() -> Piece:
    return arch_bay("arch_horseshoe", half=1.0, opening=0.6, below=1 / 3, ring=0.25, voussoirs=15,
                    ring_materials=["stone", "brick"], wall_material="stone", alfiz=True, chamfer=0.015)


def arch_round() -> Piece:
    return arch_bay("arch_round", half=2.0, opening=1.6, below=0.0, ring=0.35, voussoirs=16,
                    ring_materials=["brick"], wall_material="brick", alfiz=False, chamfer=0.0)


def arch_segmental() -> Piece:
    return arch_bay("arch_segmental", half=3.0, opening=2.6, below=-0.5, ring=0.3, voussoirs=18,
                    ring_materials=["brick"], wall_material="brick", alfiz=False, chamfer=0.0)


def vault_barrel() -> Piece:
    """Half a cylinder of radius 2 springing from the wall tops, its axis along z, drawn from below."""
    p = Piece("vault_barrel")
    radius, steps = 2.0, 16
    su, sv = SCALE["brick"]
    for k in range(steps):
        a, b = math.pi * k / steps, math.pi * (k + 1) / steps
        mid = (a + b) / 2
        corners = [(radius * math.cos(a), HEIGHT + radius * math.sin(a), -1), (radius * math.cos(a), HEIGHT + radius * math.sin(a), 1),
                   (radius * math.cos(b), HEIGHT + radius * math.sin(b), 1), (radius * math.cos(b), HEIGHT + radius * math.sin(b), -1)]
        # Brick courses run along the vault's axis, the bricks' length along it too.
        uvs = [(-1 / su, radius * a / sv), (1 / su, radius * a / sv), (1 / su, radius * b / sv), (-1 / su, radius * b / sv)]
        p.face(corners, (-math.cos(mid), -math.sin(mid), 0), "brick", uvs=uvs)
    return p


# ---- doors ---------------------------------------------------------------------------------------

def door_frame() -> Piece:
    p = Piece("door_frame")
    hw, h = 0.7, 2.4
    z = WALL_HALF
    p.face([(-1, 0, z), (-hw, 0, z), (-hw, h, z), (hw, h, z), (hw, 0, z), (1, 0, z), (1, HEIGHT, z), (-1, HEIGHT, z)], (0, 0, 1), "stone")
    p.face([(-1, HEIGHT, -z), (1, HEIGHT, -z), (1, HEIGHT, z), (-1, HEIGHT, z)], (0, 1, 0), "stone")
    proud = 0.05
    for sign in (-1, 1):  # the reveals, through the wall and the frame
        x = sign * hw
        p.face([(x, 0, -z), (x, 0, z + proud), (x, h, z + proud), (x, h, -z)], (-sign, 0, 0), "stone")
    p.face([(-hw, h, -z), (hw, h, -z), (hw, h, z + proud), (-hw, h, z + proud)], (0, -1, 0), "stone")
    # Dressed jamb stones, long and short in turn, and a lintel, standing out of the wall.
    joint = 0.012
    for sign in (-1, 1):
        y = 0.0
        for height, width in ((0.8, 0.3), (0.78, 0.22), (0.82 - joint, 0.3)):
            lo_x, hi_x = sorted((sign * hw, sign * (hw + width)))
            p.box((lo_x, y, z), (hi_x, y + height - joint, z + proud), "stone", skip=("-y", "-z"))
            y += height
    p.box((-0.98, h, z), (0.98, h + 0.45, z + proud), "stone", skip=("-y", "-z"))
    p.collider((-1, 0, -z), (-hw, HEIGHT, z), "walls")
    p.collider((hw, 0, -z), (1, HEIGHT, z), "walls")
    p.collider((-hw, h, -z), (hw, HEIGHT, z), "walls")
    return p


def stud(p: Piece, x: float, y: float, z: float, size: float = 0.022, height: float = 0.02) -> None:
    """A square-headed nail: a low pyramid on the face at depth `z`."""
    base = [(x - size, y - size, z), (x + size, y - size, z), (x + size, y + size, z), (x - size, y + size, z)]
    tip = (x, y, z + height)
    for a, b in zip(base, base[1:] + base[:1]):
        p.face([a, b, tip], sub(mul(add(a, b), 0.5), (x, y, z - 0.01)), "iron")


def door_leaf() -> Piece:
    p = Piece("door_leaf")
    hw, h, t = 0.7, 2.4, 0.05
    p.box((-hw, 0, -t), (hw, h, t), "wood", skip=("-y",), scale=(2.0, 2.0))
    strap = 0.015
    for y in (0.3, 1.2, 2.1):
        p.box((-hw + 0.04, y - 0.035, t), (hw - 0.04, y + 0.035, t + strap), "iron", skip=("-z",))
        for x in (-0.55, -0.275, 0.0, 0.275, 0.55):
            stud(p, x, y, t + strap)
    # A ring to pull it by, on a plate.
    p.box((0.4, 1.06, t), (0.5, 1.16, t + 0.01), "iron", skip=("-z",))
    centre, radius, tube = (0.45, 1.0), 0.075, 0.012
    sides = 8
    for i in range(sides):
        a, b = 2 * math.pi * i / sides, 2 * math.pi * (i + 1) / sides
        pa = (centre[0] + radius * math.sin(a), centre[1] + radius * math.cos(a), t + 0.025)
        pb = (centre[0] + radius * math.sin(b), centre[1] + radius * math.cos(b), t + 0.025)
        p.beam(pa, pb, tube, tube, "iron", up=(0, 0, 1), caps=False)
    return p


def lock_seal() -> Piece:
    p = Piece("lock_seal")
    hw, h = 0.7, 2.4
    p.box((-hw, 0, -0.15), (hw, h, -0.03), "stone", skip=("-y", "-z"))
    for y in (0.7, 1.75):  # iron bands across the slab
        p.box((-hw, y - 0.05, -0.03), (hw, y + 0.05, -0.01), "iron", skip=("-z",))
        for x in (-0.6, -0.3, 0.3, 0.6):
            stud(p, x, y, -0.01, size=0.025, height=0.02)
    p.box((-0.24, 0.95, -0.03), (0.24, 1.5, 0.0), "iron", skip=("-z",))  # the lock plate
    p.box((-0.05, 1.36, 0.0), (0.05, 1.48, 0.06), "iron", skip=("-z",))  # the staple
    p.box((-0.16, 0.92, 0.02), (0.16, 1.26, 0.15), "iron", skip=())  # the padlock's body
    for sign in (-1, 1):  # its shackle, through the staple
        p.box((sign * 0.1 - 0.018, 1.26, 0.065), (sign * 0.1 + 0.018, 1.46, 0.1), "iron", skip=("-y",))
    p.box((-0.118, 1.46, 0.065), (0.118, 1.5, 0.1), "iron")
    stud(p, 0.0, 1.06, 0.15, size=0.03, height=0.0)  # the keyhole's escutcheon, flat
    return p


# ---- set pieces ----------------------------------------------------------------------------------

def stair_down() -> Piece:
    """Twelve steps going down toward -z, 2.4 m in 4 m, between walls, the last third under a lintel."""
    p = Piece("stair_down")
    steps, drop, run = 12, 0.2, 4.0 / 12
    for i in range(steps):
        z0, z1 = 2 - i * run, 2 - (i + 1) * run
        y0, y1 = -i * drop, -(i + 1) * drop
        p.face([(-1, y0, z0), (1, y0, z0), (1, y1, z0), (-1, y1, z0)], (0, 0, 1), "stone")  # riser
        p.face([(-1, y1, z0), (1, y1, z0), (1, y1, z1), (-1, y1, z1)], (0, 1, 0), "stone")  # tread
    bottom = -steps * drop
    for sign in (-1, 1):
        x = sign * 1.0
        p.face([(x, 0, -2), (x, 0, 2), (x, bottom, 2), (x, bottom, -2)], (-sign, 0, 0), "stone")
    p.face([(-1, 0, -2), (1, 0, -2), (1, bottom, -2), (-1, bottom, -2)], (0, 0, 1), "stone")
    cover, lintel = -1.0, 0.35
    p.face([(-1, 0, -2), (1, 0, -2), (1, 0, cover), (-1, 0, cover)], (0, 1, 0), "stone")
    p.face([(-1, 0, cover), (1, 0, cover), (1, -lintel, cover), (-1, -lintel, cover)], (0, 0, 1), "stone")
    p.face([(-1, -lintel, -2), (1, -lintel, -2), (1, -lintel, cover), (-1, -lintel, cover)], (0, -1, 0), "stone")
    # A low barrier on the walls layer round its mouth and sides: units cannot step in, and a click
    # on the drawn steps passes through to the floor plane. Nothing stands on the world layer.
    p.collider((-1, 0, 1.9), (1, 1.0, 2), "walls")
    for sign in (-1, 1):
        lo_x, hi_x = sorted((sign * 1.0, sign * 0.9))
        p.collider((lo_x, 0, -2), (hi_x, 1.0, 1.9), "walls")
    return p


def forge() -> Piece:
    p = Piece("forge")
    # The hearth, a fire pan sunk in its top.
    hx, hz, hy = 1.1, 0.6, 0.8
    px, pz, pan = 0.75, 0.35, 0.1
    p.box((-hx, 0, -hz), (hx, hy, hz), "stone", skip=("-y", "+y"))
    for lo, hi in (((-hx, -hz), (hx, -pz)), ((-hx, pz), (hx, hz)), ((-hx, -pz), (-px, pz)), ((px, -pz), (hx, pz))):
        p.face([(lo[0], hy, lo[1]), (hi[0], hy, lo[1]), (hi[0], hy, hi[1]), (lo[0], hy, hi[1])], (0, 1, 0), "stone")
    for corners, out in (([(-px, hy, -pz), (px, hy, -pz), (px, hy - pan, -pz), (-px, hy - pan, -pz)], (0, 0, 1)),
                         ([(-px, hy, pz), (px, hy, pz), (px, hy - pan, pz), (-px, hy - pan, pz)], (0, 0, -1)),
                         ([(-px, hy, -pz), (-px, hy, pz), (-px, hy - pan, pz), (-px, hy - pan, -pz)], (1, 0, 0)),
                         ([(px, hy, -pz), (px, hy, pz), (px, hy - pan, pz), (px, hy - pan, -pz)], (-1, 0, 0)),
                         ([(-px, hy - pan, -pz), (px, hy - pan, -pz), (px, hy - pan, pz), (-px, hy - pan, pz)], (0, 1, 0))):
        p.face(corners, out, "iron")
    # The hood: a wooden frame just over head height, plaster sloping up to a flue against the wall behind.
    fx, fz, fy, beam = 1.3, 0.7, 2.05, 0.18
    p.box((-fx, fy, fz - 0.1), (fx, fy + beam, fz), "wood", skip=("-z",), scale=(2.0, 2.0), turn=True)
    for sign in (-1, 1):
        lo_x, hi_x = sorted((sign * fx, sign * (fx - 0.1)))
        p.box((lo_x, fy, -fz), (hi_x, fy + beam, fz - 0.1), "wood", skip=("-z",), scale=(2.0, 2.0), turn=True)
    top, tx, tz = 3.1, 0.45, -0.2
    hood_base = fy + beam
    slopes = [([(-fx, hood_base, fz), (fx, hood_base, fz), (tx, top, tz), (-tx, top, tz)], (0, 0.7, 1)),
              ([(-fx, hood_base, -fz), (-fx, hood_base, fz), (-tx, top, tz), (-tx, top, -fz)], (-1, 0.7, 0)),
              ([(fx, hood_base, -fz), (fx, hood_base, fz), (tx, top, tz), (tx, top, -fz)], (1, 0.7, 0))]
    for corners, out in slopes:
        p.face(corners, out, "plaster")
        p.face(corners, mul(out, -1), "plaster")  # the inside, seen from under the hood
    p.box((-tx, top, -fz), (tx, HEIGHT, tz), "plaster", skip=("-y", "-z"))  # the flue
    p.collider((-hx, 0, -hz), (hx, hy, hz))
    return p


def anvil() -> Piece:
    p = Piece("anvil")
    p.lathe([(0.0, 0.24), (0.5, 0.24)], 8, "wood", turn=22.5, top=True)  # the stump
    p.box((-0.2, 0.5, -0.13), (0.2, 0.58, 0.13), "iron", skip=("-y",))  # foot
    p.box((-0.12, 0.58, -0.07), (0.12, 0.68, 0.07), "iron", skip=("-y", "+y"))  # waist
    p.box((-0.24, 0.68, -0.09), (0.3, 0.82, 0.09), "iron", skip=("-x",))  # body and face, the heel at +x
    base = [(-0.24, 0.68, -0.06), (-0.24, 0.68, 0.06), (-0.24, 0.82, 0.06), (-0.24, 0.82, -0.06)]
    tip = (-0.42, 0.8, 0.0)
    for a, b in zip(base, base[1:] + base[:1]):
        p.face([a, b, tip], sub(mul(add(a, b), 0.5), (-0.2, 0.75, 0.0)), "iron")  # the horn
    p.face([(-0.24, 0.68, -0.09), (-0.24, 0.68, 0.09), (-0.24, 0.82, 0.09), (-0.24, 0.82, -0.09)], (-1, 0, 0), "iron")
    p.collider((-0.42, 0, -0.24), (0.3, 0.82, 0.24))
    return p


def rack() -> Piece:
    p = Piece("rack")
    for sign in (-1, 1):
        x = sign * 0.9
        p.box((x - 0.04, 0, -0.04), (x + 0.04, 1.85, 0.04), "wood", skip=("-y",))  # upright
        p.box((x - 0.045, 0, -0.25), (x + 0.045, 0.08, 0.25), "wood", skip=("-y",))  # foot
    for y in (0.95, 1.62):  # rails
        p.box((-0.98, y, -0.035), (0.98, y + 0.07, 0.035), "wood", turn=True)
    # Swords, points on the floor in front, hilts against the lower rail.
    for x in (-0.6, -0.35, -0.1):
        foot, rest = (x, 0.02, 0.2), (x, 0.92, 0.045)
        p.beam(foot, rest, 0.045, 0.01, "iron", up=(0, 0, 1))  # blade
        along = unit(sub(rest, foot))
        guard = add(rest, mul(along, 0.01))
        p.beam(add(guard, (-0.09, 0, 0)), add(guard, (0.09, 0, 0)), 0.025, 0.025, "iron")
        p.beam(add(rest, mul(along, 0.02)), add(rest, mul(along, 0.17)), 0.03, 0.03, "wood")  # grip
    # Spears, butts on the floor, heads above the top rail.
    for x in (0.25, 0.5, 0.72):
        foot, top = (x, 0.0, 0.16), (x, 1.72, 0.045)
        p.beam(foot, top, 0.035, 0.035, "wood")
        along = unit(sub(top, foot))
        head = add(top, mul(along, 0.17))
        base = [add(top, (dx, 0, dz)) for dx, dz in ((-0.03, 0), (0, 0.012), (0.03, 0), (0, -0.012))]
        for a, b in zip(base, base[1:] + base[:1]):
            p.face([a, b, head], sub(mul(add(a, b), 0.5), top), "iron")
    p.collider((-1.0, 0, -0.25), (1.0, 1.85, 0.25))
    return p


def barrel() -> Piece:
    p = Piece("barrel")
    profile = [(0.0, 0.27), (0.15, 0.3), (0.45, 0.32), (0.75, 0.3), (0.9, 0.27)]
    p.lathe(profile, 12, "wood")
    p.lathe([(0.87, 0.255), (0.9, 0.255)], 12, "wood", inward=True)  # the chime, inside the rim
    p.lathe([(0.9, 0.27), (0.9, 0.255)], 12, "wood")
    p.lathe([(0.87, 0.255)], 12, "wood", top=True)  # the head, sunk in
    for y0, y1 in ((0.07, 0.13), (0.28, 0.34), (0.56, 0.62), (0.77, 0.83)):  # hoops
        def radius(y):
            for (ya, ra), (yb, rb) in zip(profile, profile[1:]):
                if ya <= y <= yb:
                    return ra + (rb - ra) * (y - ya) / (yb - ya) + 0.008
        p.lathe([(y0, radius(y0)), (y1, radius(y1))], 12, "iron")
    p.colliders.append(("world", [(0.32 * math.cos(math.pi * i / 4), y, 0.32 * math.sin(math.pi * i / 4))
                        for i in range(8) for y in (0.0, 0.9)]))
    return p


def bench() -> Piece:
    p = Piece("bench")
    p.box((-0.8, 0.44, -0.2), (0.8, 0.5, 0.2), "wood", turn=True)  # the seat, its planks along it
    for sign in (-1, 1):
        x = sign * 0.55
        p.box((x - 0.03, 0, -0.17), (x + 0.03, 0.44, 0.17), "wood", skip=("-y", "+y"))
    p.box((-0.52, 0.15, -0.03), (0.52, 0.21, 0.03), "wood", skip=("-x", "+x"), turn=True)  # stretcher
    p.collider((-0.8, 0, -0.2), (0.8, 0.5, 0.2))
    return p


def bars() -> Piece:
    p = Piece("bars")
    half = 0.0175
    for i in range(10):
        x = -0.9 + 0.2 * i
        p.box((x - half, 0, -half), (x + half, 2.4, half), "iron", skip=("-y",))
    for y in (0.12, 1.2, 2.25):
        p.box((-1.0, y - 0.03, -0.03), (1.0, y + 0.03, 0.03), "iron")
    p.collider((-1.0, 0, -0.05), (1.0, 2.4, 0.05), "walls")
    return p


def sconce() -> Piece:
    p = Piece("sconce")
    p.box((-0.05, 1.9, -0.2), (0.05, 2.2, -0.185), "iron", skip=("-z",))  # the plate on the wall
    cup_z = 0.12
    p.beam((0, 2.0, -0.185), (0, 2.19, cup_z), 0.03, 0.02, "iron", up=(1, 0, 0))  # the arm
    rings = [(2.18, 0.03), (2.34, 0.075)]
    p.lathe(rings, 6, "iron", centre=(0.0, cup_z), turn=90)  # the cup, open at the top
    p.lathe(rings, 6, "iron", centre=(0.0, cup_z), turn=90, inward=True)
    p.lathe([(2.12, 0.025), (2.45, 0.025)], 6, "wood", centre=(0.0, cup_z))  # the torch
    p.lathe([(2.45, 0.035), (2.6, 0.03)], 6, "wood", centre=(0.0, cup_z), top=True)  # its pitch-soaked head
    return p


PIECES = [floor_slab, lambda: wall("wall", "stone"), lambda: wall("wall_brick", "brick"), wall_corner, pillar, arch_horseshoe,
          arch_round, arch_segmental, vault_barrel, door_frame, door_leaf, stair_down, forge, anvil, rack, barrel, bench, bars,
          sconce, lock_seal]


# ---- writing them --------------------------------------------------------------------------------

def blender_point(p) -> tuple:
    """A point of Godot's frame (y up) in Blender's (z up), which the exporter turns back: Blender
    (x, y, z) is glTF (x, z, -y)."""
    x, y, z = p
    return (x, -z, y)


def new_object(name: str, faces):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for points in faces:
        verts = [bm.verts.new(blender_point(p)) for p in points]
        bm.faces.new(verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build(piece: Piece) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    used = [m for m in MATERIALS if any(material == m for _, material, _ in piece.faces)]
    obj = new_object(piece.name, [points for points, _, _ in piece.faces])
    mesh = obj.data
    for name in used:
        mesh.materials.append(bpy.data.materials.new(name))
    layer = mesh.uv_layers.new(name="UVMap")
    for polygon, (_, material, uvs) in zip(mesh.polygons, piece.faces):
        polygon.material_index = used.index(material)
        polygon.use_smooth = False
        for loop, uv in zip(polygon.loop_indices, uvs):
            layer.data[loop].uv = uv
    for i, (layer, points) in enumerate(piece.colliders):
        marker = "-walls" if layer == "walls" else ""
        new_object(f"{piece.name}_block{i + 1}{marker}-convcolonly", convex_faces(points))
    path = OUT / f"{piece.name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", export_yup=True, export_apply=False,
        export_materials="EXPORT", export_vertex_color="NONE", export_texcoords=True, export_normals=True,
        export_tangents=False, export_extras=False, export_morph=False, export_animations=False,
        export_skins=False, export_cameras=False, export_lights=False)
    fix_generator(path)


def convex_faces(points) -> list:
    """The faces of the convex hull of `points` (a box's corners, or a prism's), wound outward."""
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in points]
    bmesh.ops.convex_hull(bm, input=verts)
    for v in [v for v in bm.verts if not v.link_faces]:
        bm.verts.remove(v)
    faces = [[tuple(v.co) for v in f.verts] for f in bm.faces]
    bm.free()
    return faces


def fix_generator(path: Path) -> None:
    """Replaces the exporter's generator string, which names its version, with this tool's name."""
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, f"{path.name} is not a glTF 2 binary"
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A, f"{path.name} does not start with its JSON"
    document = json.loads(data[20:20 + length])
    document["asset"] = {"generator": "tools/blender/kit.py", "version": "2.0"}
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    rest = data[20 + length:]
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + len(rest)) + struct.pack(
        "<II", len(text), 0x4E4F534A) + text + rest
    path.write_bytes(out)


def main() -> None:
    if tuple(bpy.app.version[:2]) != BLENDER:
        sys.exit("kit: written for Blender %d.%d, not %s; its exporter may write other bytes"
                 % (BLENDER + (bpy.app.version_string,)))
    OUT.mkdir(parents=True, exist_ok=True)
    for make in PIECES:
        piece = make()
        triangles = piece.triangles()
        if triangles >= MAX_TRIANGLES:
            sys.exit(f"kit: {piece.name} has {triangles} triangles, at most {MAX_TRIANGLES - 1} allowed")
        build(piece)
        print(f"wrote {piece.name}.glb: {triangles} triangles")


main()
