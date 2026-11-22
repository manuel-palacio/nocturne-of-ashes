"""What the tools that make pieces worn on the human model share: `gear.py` and `heads.py`.

A `Piece` is a mesh in the model's own frame (`assets/characters/human/human.glb`): metres, y up,
the figure facing -z, in its rest pose. `export` writes it as a `.glb` whose origin is a point of
that frame (the rest-pose head of the bone it hangs from), with one texture coordinate per face
chosen from the face's colour, and replaces the exporter's generator string (which names the
Blender version) with the tool's name, so the bytes depend on the tool alone.

Imported by the tools, which Blender runs with `-P`; it is not run itself.
"""
import json
import math
import struct
import sys
from pathlib import Path

import bmesh
import bpy

BLENDER = (5, 3)  # the version the output is pinned to

FLAT_DEPTH, FLAT_WIDTH = 0.6, 0.15
KEY_DIRECTIONS = {"fore": (0, 0, -1), "aft": (0, 0, 1), "left": (-1, 0, 0), "right": (1, 0, 0)}


def require_blender(tool: str) -> None:
    """Stops `tool` unless it runs in the Blender its output is pinned to."""
    if tuple(bpy.app.version[:2]) != BLENDER:
        sys.exit("%s: written for Blender %d.%d, not %s; its exporter may write other bytes"
                 % ((tool,) + BLENDER + (bpy.app.version_string,)))


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


def newell(points) -> tuple:
    """The (unnormalised) normal of a polygon by Newell's method."""
    normal = (0.0, 0.0, 0.0)
    for a, b in zip(points, points[1:] + points[:1]):
        normal = add(normal, ((a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]),
                              (a[0] - b[0]) * (a[1] + b[1])))
    return normal


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
        if dot(newell([self.verts[i] for i in indices]), out) < 0:
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

    def take(self, other: "Piece") -> None:
        """Adds `other`'s faces, on vertices of their own. Neither has shape keys."""
        assert not self.keys and not other.keys, "cannot join pieces with shape keys"
        base = len(self.verts)
        self.verts.extend(other.verts)
        self.faces.extend(tuple(i + base for i in face) for face in other.faces)
        self.colours.extend(other.colours)

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

    def lathe(self, rings, sides, colour=None, closed=True, cap=False, keys=None, flat=None, seat=None) -> None:
        """Rings, top to bottom, of `(y, rx, rz, cz, half_arc)`: an ellipse of half-widths `rx`, `rz`
        about `(0, y, cz)`. Angle 0 is the back (+z), 90 degrees the right (+x). A closed lathe goes
        all round; an open one spans `half_arc` degrees either side of the back. `cap` closes the
        top with a point.

        `keys` maps a shape key's name to `(spread, lift, top, knee)`. At full weight the side
        facing the key's way stands out like cloth over a striding knee: from where it hangs at
        height `top` it runs out, steeply at first, to reach, at height `knee`, `1 + spread` times
        the hem's own reach that way, and hangs straight down from there to the hem. So no key takes
        the cloth further than `1 + spread` times the hem's reach, the bulge is where the knee and
        shin are, and the far side stays where it is. With a `lift`, a second key, `<name>_up`,
        raises the side facing the way below `knee`, by up to `lift` at the hem where it faces the
        way squarely: the hem rides up over a leg the cloth cannot hold, so a foot shows below it
        rather than through it.

        `flat`, as `(top, hem)`, adds a `flat` key that, as deep, brings the front in to
        `FLAT_DEPTH` of its reach and widens the hem by `FLAT_WIDTH`, leaving the back where it is:
        the hem laid flat round a figure lying on its back, the front fallen onto the legs and the
        back on the floor under them. `seat`, as `(top, thighs, drop)`, adds a `seat` key that lays the front over a
        seated figure's lap: the cloth runs forward from `top` for the length `thighs`, falling
        `drop`, then hangs from the knees; the front's sides go all the way, and the sides part of it."""
        ups = [f"{name}_up" for name, (_, lift, _, _) in (keys or {}).items() if lift]
        for name in list(keys or {}) + ups + (["flat"] if flat else []) + (["seat"] if seat else []):
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
                local = (rx * math.sin(a), 0.0, rz * math.cos(a))
                for name, (spread, lift, top, knee) in (keys or {}).items():
                    toward = KEY_DIRECTIONS[name]
                    reach, hem_reach = (rx, rings[-1][1]) if toward[0] else (rz, rings[-1][2])
                    # Out from the top to the knee, steepest at the top as over a thigh raised high,
                    # then straight down.
                    share = min(max((top - y) / (top - knee), 0.0), 1.0)
                    stood = reach + ((1 + spread) * hem_reach - reach) * share ** 0.5
                    out = mul(toward, max(dot(local, toward), 0.0) * max(stood / reach - 1.0, 0.0))
                    facing = max(dot(radial, toward), 0.0)
                    rises = min(max((knee - y) / (knee - rings[-1][0]), 0.0), 1.0) if lift else 0.0
                    self.keys[name][index] = out
                    if lift:
                        self.keys[f"{name}_up"][index] = (0.0, lift * rises * facing * facing, 0.0)
                if flat:
                    depth = min(max((flat[0] - y) / (flat[0] - flat[1]), 0.0), 1.0)
                    self.keys["flat"][index] = (rx * math.sin(a) * FLAT_WIDTH * depth, 0.0,
                                                -rz * min(math.cos(a), 0.0) * (1 - FLAT_DEPTH) * depth)
                if seat:
                    top, thighs, drop = seat
                    down = max(top - y, 0.0)
                    forward = min(down, thighs)
                    # Up from where it hangs to the lap, then down from the knees.
                    rise = down - (drop * forward / thighs) - max(down - thighs, 0.0)
                    front = min(1.6 * max(-math.cos(a), 0.0), 1.0) if closed else 0.0
                    self.keys["seat"][index] = (0.0, rise * front, -forward * front)
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


def blender_point(p, origin) -> tuple:
    """A point of the model's frame (y up, -z forward), relative to `origin`, in Blender's frame
    (z up), which the exporter turns back: Blender (x, y, z) is glTF (x, z, -y)."""
    x, y, z = sub(p, origin)
    return (x, -z, y)


def export(piece: Piece, origin, path: Path, uv_of, smooth: bool, generator: str) -> None:
    """Writes `piece` to `path` with its origin at `origin`: every corner of a face at `uv_of(colour)`
    of the face's colour, shaded smooth or flat, and the exporter's generator string replaced by
    `generator`."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
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
        uv = uv_of(colour)
        for loop in polygon.loop_indices:
            layer.data[loop].uv = uv
        polygon.use_smooth = smooth
    obj = bpy.data.objects.new(piece.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if piece.keys:
        obj.shape_key_add(name="Basis", from_mix=False)
        for name, offsets in piece.keys.items():
            key = obj.shape_key_add(name=name, from_mix=False)
            key.value = 0.0
            for point, v, offset in zip(key.data, piece.verts, offsets):
                point.co = blender_point(add(v, offset), origin)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", export_yup=True, export_apply=False,
        export_materials="NONE", export_vertex_color="NONE", export_texcoords=True, export_normals=True, export_tangents=False, export_extras=False,
        export_morph=True, export_morph_normal=True, export_animations=False, export_skins=False,
        export_cameras=False, export_lights=False)
    fix_generator(path, generator)


def fix_generator(path: Path, generator: str) -> None:
    """Replaces the exporter's generator string, which names its version, with `generator`."""
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, f"{path.name} is not a glTF 2 binary"
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A, f"{path.name} does not start with its JSON"
    document = json.loads(data[20:20 + length])
    document["asset"] = {"generator": generator, "version": "2.0"}
    text = json.dumps(document, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    rest = data[20 + length:]
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(text) + len(rest)) + struct.pack(
        "<II", len(text), 0x4E4F534A) + text + rest
    path.write_bytes(out)
