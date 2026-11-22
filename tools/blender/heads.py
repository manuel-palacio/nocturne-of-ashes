"""Makes a head for each character, one `.glb` each in `assets/gear/head_<name>.glb`.

    blender -b --factory-startup -P tools/blender/heads.py

Written for Blender 5.3, and it refuses to run with any other version: another version's glTF
exporter may write different bytes. The output is byte-identical from one run to the next.

The human model has no head of its own (`tools/make_character.py` takes it off above the neck
joint), so every dress wears one of these, hung from `DEF-head` like any gear (see `gear.py`): each
is modelled in the model's frame at rest, with its origin at the head bone's rest head.

A head is one rigid piece, faceted and painted flat, closer to a carved saint than a photograph:

- a skull of rings round the head, bottom to top (`rings`): the bottom ring sits inside the neck
  joint, so the neck closes into the head however the head turns; then under the jaw, the jaw, the
  mouth, the nose's base, the eyes, the brow, the forehead and the crown. A ring is two
  half-superellipses (deeper at the back than at the front), with bumps for the brow ridge, the
  cheekbones, the eye sockets and hollow cheeks;
- a nose, a wedge from between the brows to its tip; ears, flat blocks on the sides;
- hair as geometry: the skull's faces above the hairline are raised and coloured as hair (a cut, a
  tonsure, a bald crown with a fringe, matted hair, or a cut cropped close for headwear), and long
  hair hangs as sheets made two-sided in geometry; a beard is raised the same way;
- eyes, brows, mouth and lines painted: flat faces laid a few millimetres over the skull whose
  texture coordinates point at their own squares of the character's palette (eye white, iris, brow,
  lips, the shadowed socket).

Every face's texture coordinates point at the true square of its colour in the wearer's 16 x 1
palette (`tools/make_character.py` lays it out), so a head is drawn with the body's own material,
no offset, and takes the wearer's skin and hair. `HEADS` holds each character's proportions and
choices. Every head stays under 900 triangles.
"""
import math
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(1, str(Path(__file__).resolve().parents[1]))
from gear import BONES  # noqa: E402
from make_character import (BEARD, BROW, EYE_WHITE, HAIR, IRIS, LIPS, NECK_TOP, REGION_NAMES,  # noqa: E402
                            SHADE, SKIN, SOCKET, STUBBLE)
from wearable import Piece, add, dot, export, mul, newell, require_blender, sub, unit  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "assets/gear"
MAX_TRIANGLES = 900
BONE = "DEF-head"
ORIGIN = BONES[BONE]
CZ = ORIGIN[2]  # the head's middle, front to back

# The skull's columns, in degrees round from the front (-z) towards +x; mirrored for -x. Denser in
# front, where the face is.
HALF = [0, 14, 28, 42, 58, 76, 96, 118, 142, 162, 180]
ANGLES = HALF + [-a for a in reversed(HALF[1:-1])]
# The bottom ring: inside the neck joint (about 0.066 m wide and 0.048 m deep round the bone's
# middle, up to `NECK_TOP`), so no gap opens between neck and head as the head bows or turns.
NECK_RING = (1.535, 0.052, 0.034, 0.04)  # height, half-width, front, back
# How far painted features stand off the skull, in metres.
LIFT_SOCKET, LIFT_EYE, LIFT_IRIS, LIFT_PAINT = 0.0015, 0.003, 0.0045, 0.002
LIFT_BROW, LIFT_MOUSTACHE = 0.003, 0.005  # these stand as slabs
BEARD_THICK = 0.009  # how far a full beard stands off the skin


@dataclass(frozen=True)
class Head:
    """One character's head. Lengths in metres, heights in the model's frame."""
    width: float = 0.079        # the skull's half-width at the temples
    jaw: float = 0.066          # half-width at the jaw
    cheek: float = 0.004        # how far the cheekbones stand out
    hollow: float = 0.0         # how far the cheeks fall in below them
    chin: float = 0.104         # how far forward the chin comes
    chin_y: float = 1.578       # the chin's underside, in front
    face: float = 0.114         # the face's depth in front of the middle
    back: float = 0.108         # the skull's depth behind the middle
    brow: float = 0.006         # how far the brow ridge stands out
    square: float = 2.4         # 2 is round; higher is squarer
    crown_y: float = 1.832
    eye_y: float = 1.697
    eye_x: float = 0.033
    eye: tuple = (0.016, 0.0075)        # an eye's half-width and half-height
    iris: float = 0.0062                # the iris's half-size
    socket: float = 0.006               # how deep the sockets go
    brows: tuple = (0.0065, 0.0)        # thickness, and how far the outer end rises
    nose: tuple = (0.024, 0.015, 1.655)  # how far it stands out, half-width of its base, its base's height
    mouth: tuple = (0.021, 0.0045, 1.624)  # half-width, half-height, height
    hair: str = "short"                 # short, cropped, tonsure, bald, matted
    hairline: tuple = (1.778, 1.705, 1.6)  # its height in front, at the sides and behind
    hair_thick: float = 0.006
    long_hair: bool = False             # sheets to the shoulders
    hair_end: float = 1.48              # the height long hair hangs down to
    beard: str = "none"                 # none, stubble, full
    stubble: tuple = (0.012, 98)        # how far below the nose's base stubble starts, and how far round it goes
    moustache: bool = False
    lines: bool = False                 # an older face's lines from nose to mouth


HEADS = {
    # Álvar: lean and young, clean-shaven, a ring of brown hair round a shaven crown.
    "alvar": Head(width=0.077, jaw=0.062, cheek=0.005, chin=0.102, hair="tonsure", hair_thick=0.008,
                  hairline=(1.772, 1.705, 1.6)),
    # Zahra: fine-boned, small nose and chin, dark brows; her hair close under the veil.
    "zahra": Head(width=0.074, jaw=0.055, cheek=0.006, chin=0.096, chin_y=1.584, face=0.11, back=0.104,
                  brow=0.004, nose=(0.019, 0.012, 1.657), mouth=(0.018, 0.0045, 1.626), eye=(0.016, 0.008),
                  brows=(0.0075, 0.003), hair="cropped", hair_thick=0.003, hairline=(1.768, 1.70, 1.6)),
    # Gonzalo: broad, a heavy jaw, a bald crown with a grey fringe, a full grey beard.
    "gonzalo": Head(width=0.086, jaw=0.08, cheek=0.004, chin=0.11, face=0.116, back=0.11, square=2.9,
                    brow=0.008, nose=(0.026, 0.018, 1.653), brows=(0.009, -0.002), hair="bald",
                    hairline=(1.70, 1.655, 1.585), hair_thick=0.007, beard="full", lines=True),
    # Malakor: long and gaunt, hollow cheeks, pale, black hair to the shoulders.
    "malakor": Head(width=0.074, jaw=0.056, cheek=0.008, hollow=0.009, chin=0.1, chin_y=1.556,
                    crown_y=1.842, face=0.112, back=0.106, brow=0.007, nose=(0.027, 0.013, 1.652),
                    mouth=(0.019, 0.0035, 1.616), brows=(0.006, 0.006), hairline=(1.785, 1.71, 1.6),
                    hair_thick=0.007, long_hair=True),
    # Inigo the smith: square, short dark hair, stubble low on the jaw and chin.
    "smith": Head(width=0.084, jaw=0.077, cheek=0.003, chin=0.106, square=3.2, brow=0.007,
                  nose=(0.024, 0.017, 1.655), brows=(0.008, -0.001), hairline=(1.776, 1.705, 1.6),
                  hair_thick=0.007, beard="stubble", stubble=(0.024, 76)),
    # The captive: narrow and gaunt, hollow cheeks, matted hair to the nape, a ragged full beard.
    "captive": Head(width=0.069, jaw=0.054, cheek=0.009, hollow=0.009, chin=0.1, face=0.11, back=0.104,
                    nose=(0.023, 0.013, 1.655), hair="matted", hair_thick=0.014,
                    hairline=(1.765, 1.69, 1.585), long_hair=True, hair_end=1.53, beard="full"),
    # The crusader: a plain soldier's face, his hair cropped for the helmet.
    "crusader": Head(width=0.08, jaw=0.068, hair="cropped", hair_thick=0.003, hairline=(1.776, 1.705, 1.6)),
    # The sergeant: an older soldier, heavy brows, a moustache, lines; cropped for helmet and coif.
    "sergeant": Head(width=0.081, jaw=0.07, cheek=0.005, chin=0.106, square=2.7, brow=0.009,
                     nose=(0.026, 0.016, 1.654), brows=(0.009, -0.002), hair="cropped", hair_thick=0.003,
                     hairline=(1.77, 1.705, 1.6), moustache=True, lines=True),
}


@dataclass(frozen=True)
class Ring:
    y_front: float
    y_side: float
    y_back: float
    width: float
    front: float
    back: float
    bumps: tuple = ()  # (degrees from the front, half-width in degrees, outward)


def rings(h: Head) -> list[Ring]:
    """The skull's rings, bottom to top."""
    mouth_y, nose_y = h.mouth[2], h.nose[2]
    y, w, f, b = NECK_RING
    full = h.beard == "full"
    under = h.chin_y - (0.045 if full else 0.012)
    return [
        Ring(y, y, y, w, f, b),
        # Under the jaw, and the nape; a full beard hangs lower in front.
        Ring(under, h.chin_y + 0.012, 1.585, h.jaw * 0.88, h.chin * (0.98 if full else 0.72), 0.072),
        Ring(h.chin_y, h.chin_y + 0.032, 1.607, h.jaw, h.chin + (0.01 if full else 0.0), h.back * 0.8),
        Ring(mouth_y, mouth_y, mouth_y, (h.jaw + h.width) / 2, h.face * 0.97, h.back * 0.88,
             ((55, 22, -h.hollow),)),
        Ring(nose_y, nose_y, nose_y, h.width * 0.97, h.face, h.back * 0.96, ((52, 18, h.cheek),)),
        Ring(h.eye_y, h.eye_y, h.eye_y, h.width, h.face - 0.002, h.back, ((24, 14, -h.socket),)),
        Ring(h.eye_y + 0.024, h.eye_y + 0.024, h.eye_y + 0.024, h.width, h.face, h.back,
             ((0, 46, h.brow),)),
        Ring(h.eye_y + 0.058, h.eye_y + 0.058, h.eye_y + 0.058, h.width * 0.98, h.face * 0.93, h.back),
        Ring(1.79, 1.79, 1.79, h.width * 0.88, h.face * 0.8, h.back * 0.93),
        Ring(h.crown_y - 0.018, h.crown_y - 0.018, h.crown_y - 0.018, h.width * 0.62, h.face * 0.55,
             h.back * 0.66),
        Ring(h.crown_y - 0.004, h.crown_y - 0.004, h.crown_y - 0.004, h.width * 0.42, h.face * 0.38,
             h.back * 0.45),
    ]


def ring_point(ring: Ring, degrees: float, square: float) -> tuple:
    """A point of `ring` at `degrees` round from the front, with its bumps."""
    a = math.radians(degrees)
    s, c = math.sin(a), math.cos(a)
    power = 2.0 / square
    x = ring.width * math.copysign(abs(s) ** power, s)
    depth = ring.front if c >= 0 else ring.back
    z = -depth * math.copysign(abs(c) ** power, c)
    y = ring.y_side + (ring.y_front - ring.y_side) * max(c, 0.0) + (ring.y_back - ring.y_side) * max(-c, 0.0)
    out = 0.0
    for centre, half, amount in ring.bumps:
        near = 1.0 - abs(abs(degrees) - centre) / half
        if near > 0:
            out += amount * (0.5 - 0.5 * math.cos(math.pi * near))
    radial = unit((x, 0.0, z)) if abs(x) + abs(z) > 0 else (0.0, 0.0, -1.0)
    return add((x, y, z + CZ), mul(radial, out))


def hairline(h: Head, degrees: float) -> float:
    front, side, back = h.hairline
    a = abs(degrees)
    if a <= 90:
        return front + (side - front) * (a / 90) ** 1.5
    return side + (back - side) * (a - 90) / 90


def skull_colour(h: Head, degrees: float, y: float, band: int) -> int:
    """The colour of the skull's face whose middle is at `degrees` and height `y`, in `band` (0 is the
    lowest, between the neck ring and the one under the jaw)."""
    a = abs(degrees)
    line = hairline(h, degrees)
    if h.hair == "matted":  # straggling over the forehead and the neck
        line -= 0.03 * noise(int(round(degrees * 10)) + 1000)
    hair = y > line
    if h.hair == "tonsure":
        hair = hair and y < 1.797
    elif h.hair == "bald":
        hair = hair and y < 1.735 and a > 62
    if hair:
        return HAIR
    if h.beard == "full" and y < h.nose[2] - 0.004 and a <= 104:
        return BEARD
    if h.beard == "stubble" and band >= 1 and y < h.nose[2] - h.stubble[0] and a <= h.stubble[1]:
        return STUBBLE
    if band <= 1:
        return SHADE  # under the jaw
    if h.hollow > 0 and band == 3 and 38 <= a <= 74:
        return SHADE  # hollow cheeks
    return SKIN


def noise(i: int) -> float:
    """A fixed pseudo-random number in [0, 1) for vertex `i`."""
    return ((i * 2654435761) % 4294967296) / 4294967296


class Skull:
    """The skull's grid, and where on it a point at a height and an angle lies."""

    def __init__(self, piece: Piece, h: Head):
        self.piece, self.h = piece, h
        self.rings = rings(h)
        self.grid = [[piece.vertex(ring_point(r, a, h.square)) for a in ANGLES] for r in self.rings]
        self.top = piece.vertex((0.0, h.crown_y + 0.002, CZ + 0.004))
        self.bottom = piece.vertex((0.0, NECK_RING[0] - 0.004, CZ))

    def faces(self) -> None:
        p, h, count = self.piece, self.h, len(ANGLES)
        raised: dict[int, float] = {}
        for band, (lower, upper) in enumerate(zip(self.grid, self.grid[1:])):
            for i in range(count):
                j = (i + 1) % count
                quad = [lower[i], lower[j], upper[j], upper[i]]
                middle = mul(add(add(p.verts[quad[0]], p.verts[quad[1]]), add(p.verts[quad[2]], p.verts[quad[3]])), 0.25)
                degrees = self.middle_angle(i)
                colour = skull_colour(h, degrees, middle[1], band)
                p.face(quad, self.outward(middle), colour)
                if colour == HAIR:
                    for v in quad:
                        raised[v] = max(raised.get(v, 0.0), h.hair_thick)
                elif colour == BEARD:
                    for v in quad:
                        raised[v] = max(raised.get(v, 0.0), BEARD_THICK)
        top = self.grid[-1]
        crown = skull_colour(h, 0.0, h.crown_y, len(self.grid))
        for i in range(count):
            j = (i + 1) % count
            p.face([top[i], top[j], self.top], (0, 1, 0), crown)
            p.face([self.grid[0][i], self.grid[0][j], self.bottom], (0, -1, 0), SHADE)
        if crown == HAIR:
            raised[self.top] = h.hair_thick * 0.5
        for v, thick in sorted(raised.items()):
            if h.hair == "matted" and thick == h.hair_thick:
                thick *= 0.3 + 1.2 * noise(v)
            x, y, z = p.verts[v]
            p.verts[v] = add(p.verts[v], mul(unit((x, 0.0, z - CZ)) if v != self.top else (0, 1, 0), thick))

    @staticmethod
    def middle_angle(i: int) -> float:
        """The angle halfway between column `i` and the next."""
        a, b = ANGLES[i], ANGLES[(i + 1) % len(ANGLES)]
        return -(180 + abs(b)) / 2 if a == 180 else (a + b) / 2

    def outward(self, point) -> tuple:
        x, y, z = point
        middle_y = (NECK_RING[0] + self.h.crown_y) / 2
        return (x, (y - middle_y) * 0.5, z - CZ)

    # ---- where a point lies on the front of the skull --------------------------------------------

    def cell(self, degrees: float, y: float):
        """The four corners of the skull's face round the point at `degrees` and height `y`, and the
        point's place between them (across, then up)."""
        a = abs(degrees)
        for m in range(len(HALF) - 1):
            if HALF[m] <= a <= HALF[m + 1]:
                break
        columns = [ANGLES.index(HALF[m] if degrees >= 0 else -HALF[m]),
                   ANGLES.index(HALF[m + 1] if degrees >= 0 else -HALF[m + 1])]
        t = (a - HALF[m]) / (HALF[m + 1] - HALF[m])

        def height(k: int) -> float:
            return (self.piece.verts[self.grid[k][columns[0]]][1] * (1 - t)
                    + self.piece.verts[self.grid[k][columns[1]]][1] * t)

        for k in range(len(self.rings) - 1):
            low, high = height(k), height(k + 1)
            if low <= y <= high:
                break
        else:
            raise ValueError(f"no ring round height {y} at {degrees} degrees")
        s = (y - low) / (high - low)
        corners = [self.piece.verts[self.grid[k][columns[0]]], self.piece.verts[self.grid[k][columns[1]]],
                   self.piece.verts[self.grid[k + 1][columns[1]]], self.piece.verts[self.grid[k + 1][columns[0]]]]
        return corners, s, t

    def at(self, degrees: float, y: float) -> tuple:
        (a, b, c, d), s, t = self.cell(degrees, y)
        lower = add(mul(a, 1 - t), mul(b, t))
        upper = add(mul(d, 1 - t), mul(c, t))
        return add(mul(lower, 1 - s), mul(upper, s))

    def normal(self, degrees: float, y: float) -> tuple:
        corners, _, _ = self.cell(degrees, y)
        n = unit(newell(corners))
        return n if dot(n, self.outward(self.at(degrees, y))) > 0 else mul(n, -1)

    def angle_at(self, x: float, y: float) -> float:
        """The angle at which the skull's surface at height `y` is `x` across, on the front."""
        lo, hi = 0.0, 96.0
        for _ in range(40):
            mid = (lo + hi) / 2
            if self.at(mid, y)[0] < abs(x):
                lo = mid
            else:
                hi = mid
        return math.copysign((lo + hi) / 2, x) if x != 0 else 0.0

    def on_face(self, x: float, y: float, lift: float, normal=None) -> tuple:
        degrees = self.angle_at(x, y)
        n = normal or self.normal(degrees, y)
        return add(self.at(degrees, y), mul(n, lift))


def paint(skull: Skull, outline, lift: float, colour: int, walls: bool = False) -> None:
    """A flat face over the skull, its corners at `outline`'s (x, y) on the front, `lift` off it. With
    `walls`, it stands as a slab, closed down to the skull round its edge."""
    p = skull.piece
    middle = (sum(x for x, _ in outline) / len(outline), sum(y for _, y in outline) / len(outline))
    n = skull.normal(skull.angle_at(*middle), middle[1])
    top = [p.vertex(skull.on_face(x, y, lift, n)) for x, y in outline]
    p.face(top, n, colour)
    if walls:
        base = [p.vertex(skull.on_face(x, y, -0.001, n)) for x, y in outline]
        mean = mul(tuple(map(sum, zip(*[p.verts[v] for v in top]))), 1.0 / len(top))
        for i in range(len(outline)):
            j = (i + 1) % len(outline)
            edge_middle = mul(add(p.verts[top[i]], p.verts[top[j]]), 0.5)
            p.face([top[i], top[j], base[j], base[i]], sub(edge_middle, mean), colour)


def mirrored(outline, side: int) -> list:
    """`outline`, drawn for the face's +x side, on the side `side` (+1 or -1)."""
    return [(x * side, y) for x, y in outline]


def face_features(skull: Skull) -> None:
    """The painted eyes, brows, mouth and lines, and the nose and ears."""
    h = skull.h
    ew, eh = h.eye
    x, y, r = h.eye_x, h.eye_y, h.iris
    # Outward from the nose is +x: an eye's inner corner is at -ew, its outer at +ew.
    socket = [(x + dx, y + dy) for dx, dy in ((-1.25 * ew, 0.0015), (-0.5 * ew, eh * 1.9), (0.6 * ew, eh * 2.0),
                                              (1.3 * ew, 0.002), (0.6 * ew, -eh * 1.5), (-0.5 * ew, -eh * 1.4))]
    eye = [(x + dx, y + dy) for dx, dy in ((-ew, 0.0), (-0.4 * ew, eh), (0.5 * ew, eh), (ew, 0.0008),
                                           (0.5 * ew, -eh * 0.85), (-0.4 * ew, -eh * 0.85))]
    iris = [(x - r, y - r), (x + r, y - r), (x + r, y + r), (x - r, y + r)]
    thick, rise = h.brows
    low = y + eh + 0.006
    inner, outer = x - ew * 1.05, x + ew * 1.2
    brow = [(inner, low), (outer, low + rise), (outer, low + rise + thick * 0.65), (inner, low + thick)]
    line = [(0.021, h.nose[2] + 0.001), (0.0245, h.nose[2] + 0.001), (0.031, h.mouth[2] - 0.006),
            (0.0275, h.mouth[2] - 0.007)]  # from the nose's wing to the mouth's corner
    for side in (1, -1):
        paint(skull, mirrored(socket, side), LIFT_SOCKET, SOCKET)
        paint(skull, mirrored(eye, side), LIFT_EYE, EYE_WHITE)
        paint(skull, mirrored(iris, side), LIFT_IRIS, IRIS)
        paint(skull, mirrored(brow, side), LIFT_BROW, BROW, walls=True)
        if h.lines:
            paint(skull, mirrored(line, side), LIFT_PAINT, SHADE)
    mw, mh, my = h.mouth
    lips = [(-mw, my), (-mw * 0.5, my - mh), (mw * 0.5, my - mh), (mw, my), (mw * 0.5, my + mh * 0.8),
            (-mw * 0.5, my + mh * 0.8)]
    paint(skull, lips, LIFT_PAINT, LIPS)
    paint(skull, [(-mw * 0.8, my - 0.0011), (mw * 0.8, my - 0.0011), (mw * 0.8, my + 0.0011),
                  (-mw * 0.8, my + 0.0011)], LIFT_PAINT + 0.001, SHADE)
    if h.moustache:
        base = h.nose[2] - 0.006
        stache = [(-0.03, base - 0.016), (-0.022, base - 0.004), (0.0, base + 0.001), (0.022, base - 0.004),
                  (0.03, base - 0.016), (0.019, base - 0.009), (0.0, base - 0.006), (-0.019, base - 0.009)]
        paint(skull, stache, LIFT_MOUSTACHE, BEARD, walls=True)
    nose(skull)
    if not h.long_hair:  # long hair hangs over the ears
        for side in (1, -1):
            ear(skull, side)


def nose(skull: Skull) -> None:
    """A wedge from between the brows to its tip, its underside in shadow."""
    h, p = skull.h, skull.piece
    out, half, base = h.nose
    front = (0.0, 0.0, -1.0)
    root = p.vertex(skull.on_face(0.0, h.eye_y + 0.01, -0.001, front))
    tip_at = skull.on_face(0.0, base + 0.007, 0.0, front)
    tip = p.vertex(add(tip_at, mul(front, out)))
    left = p.vertex(skull.on_face(-half, base + 0.004, -0.003))
    right = p.vertex(skull.on_face(half, base + 0.004, -0.003))
    under = p.vertex(add(skull.on_face(0.0, base - 0.004, -0.001, front), mul(front, out * 0.25)))
    p.face([root, left, tip], (-1.0, 0.25, -0.6), SKIN)
    p.face([root, tip, right], (1.0, 0.25, -0.6), SKIN)
    p.face([left, under, tip], (-0.4, -1.0, -0.3), SHADE)
    p.face([under, right, tip], (0.4, -1.0, -0.3), SHADE)


def ear(skull: Skull, side: int) -> None:
    """A flat block on the side of the head, between the eyes' and the nose's heights."""
    h, p = skull.h, skull.piece
    top, bottom = h.eye_y + 0.008, h.nose[2] - 0.008
    outline = [(top, 0.002), (top - 0.004, 0.026), (bottom + 0.012, 0.032), (bottom, 0.014),
               (bottom + 0.012, -0.004)]  # (height, behind the middle)
    outer, inner = [], []
    for y, behind in outline:
        x = side * max(skull.at(96, y)[0], skull.at(76, y)[0]) * 0.985
        inner.append(p.vertex((x, y, CZ + behind)))
        outer.append(p.vertex((x + side * 0.013, y, CZ + behind + 0.006)))
    p.face(outer, (side, 0.0, 0.25), SKIN)
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        mid = mul(add(p.verts[outer[i]], p.verts[outer[j]]), 0.5)
        centre = (0.0, sum(y for y, _ in outline) / len(outline), CZ + sum(b for _, b in outline) / len(outline))
        way = sub(mid, centre)
        p.face([outer[i], outer[j], inner[j], inner[i]], (0.0, way[1], way[2]), SKIN)


def long_hair(h: Head) -> Piece:
    """Hair hanging from under the crown to the shoulders, round the back and sides."""
    sheet = Piece("hair", BONE, False)
    t = h.hair_thick
    arc = 116
    sheet.lathe([(h.hairline[1] + 0.03, h.width + t + 0.004, h.back + t + 0.004, CZ + 0.002, arc),
                 (1.66, h.width + 0.014, h.back + 0.012, CZ + 0.004, arc),
                 (1.57, h.width + 0.024, h.back + 0.006, CZ + 0.014, arc - 4),
                 (h.hair_end, h.width + 0.036, h.back + 0.0, CZ + 0.026, arc - 8)], 14, HAIR, closed=False)
    sheet.two_sided()
    return sheet


def head(name: str, h: Head) -> Piece:
    p = Piece(f"head_{name}", BONE, False)
    skull = Skull(p, h)
    skull.faces()
    face_features(skull)
    if h.long_hair:
        p.take(long_hair(h))
    return p


def main() -> None:
    require_blender("heads")
    assert len(REGION_NAMES) == 16, "the heads paint squares 8 to 15 of a 16-square palette"
    assert NECK_RING[0] < NECK_TOP, "the head's lowest ring must lie inside the neck joint"
    OUT.mkdir(parents=True, exist_ok=True)
    for name, h in HEADS.items():
        piece = head(name, h)
        triangles = piece.triangles()
        if triangles >= MAX_TRIANGLES:
            sys.exit(f"heads: {name} has {triangles} triangles, at most {MAX_TRIANGLES - 1} allowed")
        export(piece, ORIGIN, OUT / f"{piece.name}.glb",
               lambda colour: ((colour + 0.5) / len(REGION_NAMES), 0.5), False, "tools/blender/heads.py")
        print(f"wrote {piece.name}.glb: {triangles} triangles")


if __name__ == "__main__":
    main()
