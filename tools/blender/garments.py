"""Makes the garments worn on the human model, one `.glb` per piece in `assets/gear/`.

    blender -b --factory-startup -P tools/blender/garments.py

Written for Blender 5.3, and it refuses to run with any other version: another version's glTF
exporter may write different bytes. The output is byte-identical from one run to the next.

The human model has no body of its own under the clothes: `tools/make_character.py` takes off the
chest, the abdomen and the upper arms, so a garment is not a shell over the body but the figure's
surface there. Every garment is rigid pieces, each hung from one bone like any gear (see `gear.py`)
and modelled in the model's frame at rest with its origin at that bone's rest head:

| piece | bone | covers |
|---|---|---|
| `<garment>_chest` | DEF-spine.003 | the chest and shoulders, closed round the neck joint, with its collar |
| `<garment>_abdomen` | DEF-spine.001 | the waist, from inside the chest to the hips, with its belt or sash |
| `<garment>_sleeve_l`, `_r` | DEF-upper_arm.L, .R | the upper arm, from a dome round the shoulder joint to the elbow |
| `<garment>_cuff_l`, `_r` | DEF-forearm.L, .R | a sleeve that hangs over the forearm |

Pieces overlap their neighbours: the abdomen runs up inside the chest and down inside the skirt; a
sleeve starts in a dome round the shoulder joint, which stays where it is however the arm turns, and
its end turns in to the elbow, so no hole shows into it. Where an edge is open to view (a wide cuff,
a standing collar), that part is two-sided in geometry.

Every face's texture coordinates point at the true square of its colour in the wearer's 16 x 1
palette (`tools/make_character.py`), as a head's do, so a garment is drawn with the body's own
material: one piece can be two colours (a habit with its scapular, a surcoat with mail at the
shoulders) and adds no material. `GARMENTS` says what each character wears; each piece stays under
600 triangles. Garments are shaded smooth, like the body and the cloth: shaded flat, their rings
show as bands of plates.

| character | garment |
|---|---|
| Alvar | `habit`: chest with the scapular (hose square) front and back and a cowl on the shoulders, wide sleeves and cuffs, a rope belt |
| Zahra | `robe`: a round neck, fitted sleeves, a sash with its ends hanging at the left hip |
| Malakor | `robe` sleeves and abdomen; `dark_chest` with a high collar; `dark_cuff`s, long and narrow |
| Gonzalo | `tunic` with `rolled_sleeve`s, the forearms bare |
| Inigo | `tunic` with sleeves to the elbow |
| the captive | `shirt`: torn, open at the neck, ragged short sleeves and hem |
| crusader, sergeant | `surcoat`: chest and abdomen in the surcoat's colour, mail at the shoulders and neck, `mail_sleeve`s |
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(1, str(Path(__file__).resolve().parents[1]))
from gear import BONES  # noqa: E402
from make_character import HOSE, REGION_NAMES, SKIN, SLEEVES, TRIM, TUNIC  # noqa: E402
from wearable import Piece, add, export, mul, require_blender, sub, unit  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "assets/gear"
MAX_TRIANGLES = 600
TORSO_SIDES = 16
ARM_SIDES = 10
SQUARE = 2.6  # the torso's sections: 2 is an ellipse, higher is squarer

CHEST, ABDOMEN = "DEF-spine.003", "DEF-spine.001"
UPPER_ARM = {1: "DEF-upper_arm.R", -1: "DEF-upper_arm.L"}
FOREARM = {1: "DEF-forearm.R", -1: "DEF-forearm.L"}
ELBOW = BONES["DEF-forearm.R"][0] - BONES["DEF-upper_arm.R"][0]  # the upper arm's length
WRIST = BONES["DEF-hand.R"][0] - BONES["DEF-forearm.R"][0]  # the forearm's length

# The torso's sections, bottom to top, as (height, half-width, front, back, middle front to back):
# just outside the body the model no longer has, closing over the neck joint at the top (it is about
# 0.066 m wide and 0.062 m deep round z = 0.016, up to the head).
CHEST_RINGS = [(1.17, 0.142, 0.13, 0.108, 0.0), (1.26, 0.158, 0.138, 0.124, 0.005),
               (1.35, 0.18, 0.14, 0.155, 0.012), (1.43, 0.2, 0.128, 0.165, 0.025),
               (1.495, 0.186, 0.108, 0.152, 0.032), (1.54, 0.13, 0.082, 0.112, 0.03)]
NECK = (1.565, 0.082, 0.07, 0.074, 0.016)  # the neck opening, round the neck joint
NECK_IN = (1.53, 0.06, 0.05, 0.055, 0.016)  # turned in, inside the neck joint
ABDOMEN_RINGS = [(1.06, 0.15, 0.125, 0.125, 0.004), (1.16, 0.142, 0.127, 0.112, -0.004),
                 (1.27, 0.152, 0.13, 0.118, 0.004), (1.33, 0.156, 0.125, 0.125, 0.01)]
TUCKED = (0.97, 0.155, 0.128, 0.13, 0.008)  # the abdomen's bottom, tucked into a skirt
HIPS_HEM = [(0.99, 0.162, 0.135, 0.135, 0.01), (0.9, 0.19, 0.15, 0.158, 0.01)]  # a tunic to the hips


# ---- lofting sections into a piece --------------------------------------------------------------

def section_point(centre, u, v, ru, rv, degrees, square=2.0):
    """A point of the superellipse of half-widths `ru` along `u` (at 0 degrees) and `rv` along `v`."""
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    power = 2.0 / square
    return add(centre, add(mul(u, ru * math.copysign(abs(c) ** power, c)),
                           mul(v, rv * math.copysign(abs(s) ** power, s))))


def loft(p: Piece, sections, sides: int, colour_of, square=2.0, start_cap=False, end_cap=False,
         jag=None):
    """Joins `sections`, each `(centre, u, v, ru, rv)`, with quads all round, coloured by
    `colour_of(band, degrees)` (band 0 between the first two sections). `jag(index, degrees)`, if
    given, moves a section's points along the loft. Caps close the ends with a point. Returns the grid."""
    grid = []
    for k, (centre, u, v, ru, rv) in enumerate(sections):
        along = unit(sub(sections[min(k + 1, len(sections) - 1)][0], sections[max(k - 1, 0)][0]))
        ring = []
        for i in range(sides):
            degrees = 360.0 * i / sides
            point = section_point(centre, u, v, ru, rv, degrees, square)
            if jag is not None:
                point = add(point, mul(along, jag(k, degrees)))
            ring.append(p.vertex(point))
        grid.append(ring)
    for band, (lower, upper) in enumerate(zip(grid, grid[1:])):
        c0, c1 = sections[band][0], sections[band + 1][0]
        for i in range(sides):
            j = (i + 1) % sides
            quad = [lower[i], lower[j], upper[j], upper[i]]
            middle = mul(tuple(map(sum, zip(*[p.verts[q] for q in quad]))), 0.25)
            axis_mid = mul(add(c0, c1), 0.5)
            out = sub(middle, axis_mid)
            p.face(quad, out, colour_of(band, 360.0 * (i + 0.5) / sides))
    for cap, ring, k, sign in ((start_cap, grid[0], 0, -1), (end_cap, grid[-1], len(sections) - 1, 1)):
        if not cap:
            continue
        centre = sections[k][0]
        other = sections[k - sign][0]
        way = unit(sub(centre, other))
        tip = p.vertex(add(centre, mul(way, cap if isinstance(cap, float) else 0.0)))
        band = 0 if sign < 0 else len(sections) - 2
        for i in range(sides):
            j = (i + 1) % sides
            p.face([ring[i], ring[j], tip], way, colour_of(band, 360.0 * (i + 0.5) / sides))
    return grid


def torso_section(y, w, front, back, cz):
    """A torso section about the vertical: 0 degrees is the front (-z), 90 the right (+x)."""
    return ((0.0, y, cz + (back - front) / 2), (0.0, 0.0, -1.0), (1.0, 0.0, 0.0), (front + back) / 2, w)


def from_front(degrees: float) -> float:
    """How far round from the front a torso angle is, 0 to 180."""
    d = degrees % 360
    return d if d <= 180 else 360 - d


def two_sided_part(p: Piece, part: Piece) -> None:
    part.two_sided()
    p.take(part)


# ---- the torso ----------------------------------------------------------------------------------

def chest(name: str, colour_of, collar=None) -> Piece:
    """The chest from inside the abdomen to the neck, turned in round the neck joint. `colour_of(y,
    degrees)` colours it; `collar(piece)` adds what stands round the neck."""
    p = Piece(name, CHEST, False)
    rings = CHEST_RINGS + [NECK, NECK_IN]
    sections = [torso_section(*r) for r in rings]
    loft(p, sections, TORSO_SIDES, lambda band, d: colour_of((rings[band][0] + rings[band + 1][0]) / 2, d),
         SQUARE)
    if collar:
        collar(p)
    return p


def abdomen(name: str, colour_of, hem=None, belt=None, jag=None) -> Piece:
    """The waist, from inside the chest down into the skirt (or, with `hem`, flaring to the hips).
    `belt` is `(colour, top, bottom, standing out)`."""
    p = Piece(name, ABDOMEN, False)
    rings = list(reversed(ABDOMEN_RINGS))  # top down
    rings += list(reversed(hem)) if hem else [TUCKED]
    sections = [torso_section(*r) for r in rings]
    loft(p, sections, TORSO_SIDES, lambda band, d: colour_of((rings[band][0] + rings[band + 1][0]) / 2, d),
         SQUARE, jag=jag)
    if belt:
        colour, top, bottom, out = belt

        def width(y):  # the abdomen's section at `y`, between its rings
            for upper, lower in zip(rings, rings[1:]):
                if lower[0] <= y <= upper[0]:
                    t = (y - lower[0]) / (upper[0] - lower[0])
                    return tuple(a + (b - a) * t for a, b in zip(lower, upper))
            return rings[-1]

        band = []
        for y in (top, bottom):
            _, w, f, b, cz = width(y)
            band.append(torso_section(y, w + out, f + out, b + out, cz))
        loft(p, band, TORSO_SIDES, lambda _b, _d: colour, SQUARE)
    return p


# ---- the arms -----------------------------------------------------------------------------------

def arm_section(side: int, bone: str, t: float, ry: float, rz: float, dy=0.0, dz=0.0):
    """A section across the arm `t` metres out along it from `bone`'s head: 0 degrees is up, 90 the front."""
    origin = BONES[bone]
    return ((origin[0] + side * t, origin[1] + dy, origin[2] + dz), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0), ry, rz)


def sleeve(name: str, side: int, colour, rings, dome=0.074, turn_in=0.045, jag=None, colour_of=None) -> Piece:
    """An upper sleeve: a dome round the shoulder joint, then `rings` of `(t, ry, rz)` out along the
    upper arm, its end turned in to `turn_in` round the elbow."""
    p = Piece(name, UPPER_ARM[side], False)
    sections = [arm_section(side, UPPER_ARM[side], -dome * f, dome * r, dome * r)
                for f, r in ((0.72, 0.69), (0.36, 0.93))]
    sections += [arm_section(side, UPPER_ARM[side], t, ry, rz) for t, ry, rz in rings]
    last = rings[-1][0]
    sections.append(arm_section(side, UPPER_ARM[side], last - 0.012, turn_in, turn_in))
    paint = colour_of or (lambda _band, _d: colour)
    loft(p, sections, ARM_SIDES, paint, 2.0, start_cap=dome * 0.28, jag=jag)
    return p


def cuff(name: str, side: int, colour, rings, inner=0.05) -> Piece:
    """A sleeve over the forearm: `rings` of `(t, ry, rz, dy)` from the elbow, open at the wrist and
    two-sided there, so its inside shows."""
    p = Piece(name, FOREARM[side], False)
    sections = [arm_section(side, FOREARM[side], -0.03, inner, inner)]
    sections += [arm_section(side, FOREARM[side], t, ry, rz, dy) for t, ry, rz, dy in rings]
    part = Piece(name, FOREARM[side], False)
    loft(part, sections, ARM_SIDES, lambda _b, _d: colour, 2.0)
    two_sided_part(p, part)
    return p


# ---- what each wears ----------------------------------------------------------------------------

def plain(colour):
    return lambda *_: colour


def habit() -> list[Piece]:
    """Alvar: a white habit; the scapular, a panel in the hose square from the shoulders down, front
    and back (the long skirt carries it on); a cowl lying on the shoulders; wide sleeves; a rope belt."""
    def scapular(_y, degrees):
        return HOSE if from_front(degrees) < 30 or from_front(degrees) > 150 else TUNIC

    def cowl(p: Piece):
        # A thick roll of cloth round the shoulders and the neck, its hood folded down the back.
        roll = [(1.47, 0.205, 0.132, 0.178, 0.034), (1.535, 0.19, 0.122, 0.168, 0.034),
                (1.585, 0.135, 0.094, 0.13, 0.028), (1.6, 0.095, 0.082, 0.096, 0.02),
                (1.565, 0.08, 0.07, 0.076, 0.016)]
        loft(p, [torso_section(*r) for r in roll], TORSO_SIDES, lambda _b, _d: TUNIC, SQUARE)
        hood = [((0.0, 1.5, 0.19), 0.115, 0.03), ((0.0, 1.42, 0.2), 0.105, 0.03), ((0.0, 1.33, 0.186), 0.07, 0.024),
                ((0.0, 1.27, 0.166), 0.02, 0.012)]
        loft(p, [(c, (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), w, d) for c, w, d in hood], 8, lambda _b, _d: TUNIC,
             start_cap=True, end_cap=True)

    pieces = [chest("habit_chest", scapular, cowl),
              abdomen("habit_abdomen", lambda _y, d: scapular(_y, d), belt=(TRIM, 1.05, 1.02, 0.03))]
    for side, suffix in ((-1, "l"), (1, "r")):
        pieces.append(sleeve(f"habit_sleeve_{suffix}", side, TUNIC,
                             [(0.0, 0.08, 0.08), (0.14, 0.085, 0.085), (0.27, 0.09, 0.09)], turn_in=0.05))
        pieces.append(cuff(f"habit_cuff_{suffix}", side, TUNIC,
                           [(0.0, 0.09, 0.09, 0.0), (0.12, 0.105, 0.105, -0.01), (0.22, 0.125, 0.12, -0.03)]))
    return pieces


def robe() -> list[Piece]:
    """Zahra's robe, and Malakor's below the chest: fitted sleeves, a sash with ends at the left hip."""
    pieces = [chest("robe_chest", plain(TUNIC)), robe_abdomen()]
    for side, suffix in ((-1, "l"), (1, "r")):
        pieces.append(sleeve(f"robe_sleeve_{suffix}", side, SLEEVES,
                             [(0.0, 0.07, 0.07), (0.15, 0.066, 0.064), (0.29, 0.062, 0.06)]))
    return pieces


def robe_abdomen() -> Piece:
    p = abdomen("robe_abdomen", plain(TUNIC), belt=(TRIM, 1.07, 1.0, 0.03))
    # The sash's knotted ends, hanging at the left hip.
    ends = [((-0.12, 1.02, -0.11), 0.03, 0.012), ((-0.135, 0.9, -0.12), 0.028, 0.01),
            ((-0.145, 0.78, -0.12), 0.022, 0.008)]
    loft(p, [(c, (1.0, 0.0, 0.3), (0.0, 0.0, -1.0), w, d) for c, w, d in ends], 6, lambda _b, _d: TRIM,
         start_cap=True, end_cap=True)
    return p


def dark() -> list[Piece]:
    """Malakor: a high collar standing round the neck, and long narrow sleeves flaring at the wrist."""
    def collar(p: Piece):
        stand = Piece("collar", CHEST, False)
        rings = [(1.545, 0.092, 0.08, 0.085, 0.018), (1.6, 0.098, 0.085, 0.092, 0.02),
                 (1.655, 0.112, 0.094, 0.106, 0.026)]
        loft(stand, [torso_section(*r) for r in rings], TORSO_SIDES, lambda _b, _d: TUNIC, SQUARE)
        two_sided_part(p, stand)

    pieces = [chest("dark_chest", plain(TUNIC), collar)]
    for side, suffix in ((-1, "l"), (1, "r")):
        pieces.append(cuff(f"dark_cuff_{suffix}", side, SLEEVES,
                           [(0.0, 0.066, 0.064, 0.0), (0.2, 0.064, 0.062, 0.0), (0.3, 0.085, 0.08, -0.01)]))
    return pieces


def tunic() -> list[Piece]:
    """The smiths' tunic to the hips, belted; Inigo's sleeves to the elbow, Gonzalo's rolled above it."""
    pieces = [chest("tunic_chest", plain(TUNIC)),
              abdomen("tunic_abdomen", plain(TUNIC), hem=HIPS_HEM, belt=(TRIM, 1.06, 1.025, 0.02))]
    for side, suffix in ((-1, "l"), (1, "r")):
        pieces.append(sleeve(f"tunic_sleeve_{suffix}", side, TUNIC,
                             [(0.0, 0.072, 0.072), (0.15, 0.07, 0.068), (0.29, 0.07, 0.066)]))
        # Rolled up: a thick roll of cloth just above the elbow.
        pieces.append(sleeve(f"rolled_sleeve_{suffix}", side, TUNIC,
                             [(0.0, 0.072, 0.072), (0.18, 0.068, 0.066), (0.19, 0.082, 0.08),
                              (0.25, 0.08, 0.078), (0.26, 0.064, 0.062)], turn_in=0.05))
    return pieces


def ragged(k: int, degrees: float, last: int, depth: float) -> float:
    """A torn edge: the last section's points pushed on along the loft by up to `depth`, unevenly."""
    if k != last:
        return 0.0
    i = int(round(degrees / 22.5))
    return depth * ((i * 7 + 3) % 5) / 4.0


def shirt() -> list[Piece]:
    """The captive's torn shirt: open at the neck (the skin shows in a V), a ragged hem and short sleeves."""
    def open_neck(y, degrees):
        return SKIN if y > 1.5 and from_front(degrees) < 18 else TUNIC

    hem = HIPS_HEM
    pieces = [chest("shirt_chest", open_neck),
              abdomen("shirt_abdomen", plain(TUNIC), hem=hem,
                      jag=lambda k, d: ragged(k, d, len(ABDOMEN_RINGS) + len(hem) - 1, 0.05))]
    for side, suffix in ((-1, "l"), (1, "r")):
        rings = [(0.0, 0.074, 0.074), (0.16, 0.074, 0.072), (0.25, 0.076, 0.074)]
        pieces.append(sleeve(f"shirt_sleeve_{suffix}", side, TUNIC, rings, turn_in=0.05,
                             jag=lambda k, d: ragged(k, d, 4, 0.04)))
    return pieces


def surcoat() -> list[Piece]:
    """The soldiers' surcoat over mail: the surcoat's colour front and back, mail (the sleeves'
    square) at the shoulders and round the neck; a belt; mail sleeves."""
    def over_mail(y, degrees):
        a = from_front(degrees)
        return SLEEVES if y > 1.52 or (y > 1.3 and 55 < a < 125) else TUNIC

    pieces = [chest("surcoat_chest", over_mail),
              abdomen("surcoat_abdomen", plain(TUNIC), belt=(TRIM, 1.05, 1.015, 0.03))]
    for side, suffix in ((-1, "l"), (1, "r")):
        pieces.append(sleeve(f"mail_sleeve_{suffix}", side, SLEEVES,
                             [(0.0, 0.071, 0.07), (0.15, 0.066, 0.064), (0.29, 0.063, 0.06)]))
    return pieces


GARMENTS = [habit, robe, dark, tunic, shirt, surcoat]


def main() -> None:
    require_blender("garments")
    OUT.mkdir(parents=True, exist_ok=True)
    for make in GARMENTS:
        for piece in make():
            triangles = piece.triangles()
            if triangles >= MAX_TRIANGLES:
                sys.exit(f"garments: {piece.name} has {triangles} triangles, at most {MAX_TRIANGLES - 1} allowed")
            export(piece, BONES[piece.bone], OUT / f"{piece.name}.glb",
                   lambda colour: ((colour + 0.5) / len(REGION_NAMES), 0.5), True, "tools/blender/garments.py")
            print(f"wrote {piece.name}.glb: {triangles} triangles")


if __name__ == "__main__":
    main()
