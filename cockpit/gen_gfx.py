# Generates gfx.bas: command-module cockpit GRAM cards, attitude-ball and
# g-dial animation frames, and the trip map (cards, screen layout, ship
# positions). Run: python -I gen_gfx.py
import math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gfx.bas')


def card(rows):
    """8 strings of 8 'X'/'.' -> 8 row bytes."""
    assert len(rows) == 8 and all(len(r) == 8 for r in rows), rows
    return [sum(1 << (7 - i) for i, c in enumerate(r) if c == 'X') for r in rows]


def mirror(c):
    return [int('{:08b}'.format(b)[::-1], 2) for b in c]


def words(c):
    """Row bytes -> 4 DECLEs, first row in the low byte (IntyBASIC BITMAP order)."""
    return [c[2 * i] | (c[2 * i + 1] << 8) for i in range(4)]


def grid(w, h, f):
    """Cut a w x h pixel function into cards, row-major."""
    return [[sum(1 << (7 - i) for i in range(8) if f(cx * 8 + i, cy * 8 + r)) for r in range(8)]
            for cy in range(h // 8) for cx in range(w // 8)]


def emit(lines, label, cards, note=None):
    lines.append(label + ':')
    for n, c in enumerate(cards):
        w = ','.join('${:04X}'.format(v) for v in words(c))
        lines.append('\tDATA {}\t\' {}'.format(w, note(n) if note else n))


# ---------------------------------------------------------------- cockpit
def horizon(k):          # k sky rows on top, earth below
    return card(['........'] * k + ['XXXXXXXX'] * (8 - k))


def edge(r, right, inv=False):
    """Window side post for window row r (0-4): a wedge 6 px wide at the top,
    1 px at the bottom, plus the 2 px lips on the top and bottom rows.
    inv: for black space, where a black post would vanish. The window side
    is set (black) and the wedge is clear, showing the grey panel colour."""
    rows = []
    for yl in range(8):
        gy = r * 8 + yl
        b = 1 + round(5 * (39 - gy) / 39)
        s = ''.join('X' if (xl < b) != inv else '.' for xl in range(8))
        if (r == 0 and yl < 2) or (r == 4 and yl >= 6):
            s = 'X' * 8
        rows.append(s[::-1] if right else s)
    return card(rows)


def ball(s):
    """Attitude ball, 24x24: white sky above the horizon, black ground with
    a white rim below. s = 0..22, horizon s-11 px below the centre."""
    off = s - 11

    def f(x, y):
        dx, dy = x - 11.5, y - 11.5
        d = math.hypot(dx, dy)
        yy = y - 12
        if d > 11.2:
            return False
        if yy < off:
            return not (abs(dx) < 4 and yy == off - 6)
        if d > 10.2:
            return True
        return abs(dx) < 4 and yy == off + 5
    return grid(24, 24, f)


def gdial(n):
    """G-force dial, 24x24: ticks at 0-5 g over 270 degrees, needle n/15."""
    def ray(dx, dy, a, lo, hi):
        along = dx * math.cos(a) + dy * math.sin(a)
        perp = abs(-dx * math.sin(a) + dy * math.cos(a))
        return lo <= along <= hi and perp < 0.75

    na = math.radians(135 + 270 * n / 15)

    def f(x, y):
        dx, dy = x - 11.5, y - 11.5
        if any(ray(dx, dy, math.radians(135 + 54 * k), 8.5, 11) for k in range(6)):
            return True
        return ray(dx, dy, na, -1, 8) or math.hypot(dx, dy) < 1.6
    return grid(24, 24, f)


BLANK = card(['........'] * 8)
cm = []
cm += [horizon(k) for k in range(8)]                         # 0-7   C_HZ
cm += [card(['XXXXXXXX'] * 2 + ['........'] * 6),            # 8     C_LIPT
       card(['........'] * 6 + ['XXXXXXXX'] * 2)]            # 9     C_LIPB
cm += [edge(r, False) for r in range(5)]                     # 10-14 C_EDL
cm += [edge(r, True) for r in range(5)]                      # 15-19 C_EDR
cm += [edge(r, False, True) for r in range(5)]               # 20-24 C_EDLI
cm += [edge(r, True, True) for r in range(5)]                # 25-29 C_EDRI
cm += ball(22)                                               # 30-38 C_BALL
cm += gdial(0)                                               # 39-47 C_GDL
cm += [BLANK, BLANK]                                         # 48-49 C_TWR
cm += [card(['...X....', '...X....', '........', 'XX...XX.',  # 50    C_RET
             '........', '...X....', '...X....', '........']),
       card(['...X....', '..X.X...', '.X...X..', 'X.....X.',  # 51    C_DIA
             '.X...X..', '..X.X...', '...X....', '........']),
       card(['...XX...', '..XXXX..', '..XXXX..', '...XX...',  # 52    C_FLM
             '...XX...', '...X....', '....X...', '...X....']),
       BLANK,                                                # 53    C_CLD
       card(['XXX..XXX', '...XX...'] + ['........'] * 6),    # 54    C_WING
       card(['XX......'] * 8)]                               # 55    C_NDL
cm += [card(['.XXXXXX.'] + ['.X....X.'] * 4 + ['.XXXXXX.', '........', '........'])]  # 56 C_LAMP
cm += [card(['........', '.X....X.', '.X....X.', 'XXX..XXX',  # 57    C_SW
             'XXX..XXX', '........', '........', '........'])]
disc = ['..XXXX..', '.XXXXXX.', 'XXXXXXXX', 'XXXXXXXX',
        'XXXXXXXX', 'XXXXXXXX', '.XXXXXX.', '..XXXX..']
cm += [card(disc),                                           # 58    C_EARTH
       card(['..XXXX..', '.XXXXXX.', 'XX.XXXXX', 'XXXXX.XX',  # 59    C_MOON
             'XXXXXXXX', 'X.XXXXXX', '.XXXX.X.', '..XXXX..']),
       card(['........'] * 3 + ['X..X..X.'] + ['........'] * 4),  # 60 C_DOT
       card(['........'] * 3 + ['XXXXXXXX'] * 2 + ['........'] * 3)]  # 61 C_LINE
ship = card(['........', '.XX.....', '.XXXX...', 'XXXXXXX.',
             'XXXXXXX.', '.XXXX...', '.XX.....', '........'])
cm += [ship, mirror(ship)]                                   # 62-63 C_SHR/L
assert len(cm) == 64, len(cm)

# ---------------------------------------------------------------- the globe
# Every Earth with room for it: rough coastlines in latitude and longitude,
# turned to face the viewer, with the Americas a little larger than life so
# that they still read at these sizes.
EARTH_LAND = [
    [(71, -160), (70, -130), (74, -95), (68, -82), (62, -92), (58, -94), (52, -80), (62, -78), (58, -62), (52, -56),
     (46, -62), (41, -71), (35, -76), (31, -81), (25, -80), (30, -84), (29, -94), (21, -97), (18, -90), (21, -87),
     (15, -84), (9, -78), (8, -82), (15, -94), (23, -106), (31, -114), (33, -118), (48, -125), (58, -136), (60, -150), (55, -165)],
    [(11, -73), (9, -61), (2, -50), (-6, -35), (-13, -38), (-23, -42), (-36, -57), (-53, -68), (-53, -74), (-38, -73),
     (-18, -71), (-5, -81), (5, -77)],
    [(83, -35), (76, -19), (70, -22), (60, -43), (70, -54), (78, -70)],
    [(36, -6), (37, 10), (32, 32), (12, 44), (-34, 20), (4, 9), (5, -8), (15, -17), (28, -13)],
    [(44, -9), (51, -3), (60, 5), (71, 25), (44, 30)],
]
EARTH_C = (22, -85)      # latitude, longitude in the middle of the disc
EARTH_Z = 1.2            # how much larger than life


def on_land(lat, lon):
    for poly in EARTH_LAND:
        inside = False
        for k, (a, b) in enumerate(poly):
            c, d = poly[k - 1]
            if (b > lon) != (d > lon) and lat < a + (c - a) * (lon - b) / (d - b):
                inside = not inside
        if inside:
            return True
    return False


def globe(u, v):
    """Is this point of the disc land? u right, v up, both -1 to 1."""
    u, v = u / EARTH_Z, v / EARTH_Z
    w = u * u + v * v
    if w >= 1:
        return False
    z = math.sqrt(1 - w)
    c0, s0 = math.cos(math.radians(EARTH_C[0])), math.sin(math.radians(EARTH_C[0]))
    lat = math.degrees(math.asin(v * c0 + z * s0))
    lon = EARTH_C[1] + math.degrees(math.atan2(u, z * c0 - v * s0))
    return on_land(lat, lon)


def land_grid(cols, rows, x0, y0, cx, cy, r):
    """One screen pixel per cell, left top at x0,y0, over a disc at cx,cy: 1 = mostly land."""
    out = []
    for ry in range(rows):
        line = []
        for col in range(cols):
            n = 0
            if math.hypot(x0 + col + .5 - cx, y0 + ry + .5 - cy) <= r:
                for i in range(4):
                    for j in range(4):
                        n += globe((x0 + col + (i + .5) / 4 - cx) / r, (cy - y0 - ry - (j + .5) / 4) / r)
            line.append(1 if n >= 7 else 0)
        out.append(line)
    return out


def grid_cards(gr, col0, row0, nrows=2):
    """Cards of an 8-wide sprite cut from a land_grid, nrows cards tall."""
    return [[sum(gr[row0 + cy * 8 + rw][col0 + i] << (7 - i) for i in range(8)) for rw in range(8)]
            for cy in range(nrows)]


# ---------------------------------------------------------------- trip map
# Map area: screen rows 1-7 (y 8-63). Earth on cards cols 1-3 rows 3-5,
# Moon on cols 16-17 rows 3-4; the path never enters those cards, so each
# card holds a single object (one foreground colour).
EC, ER = (19.5, 35.5), 11
MC, MR = (135.5, 31.5), 7
pix = {}           # (x, y) -> ('E'|'M'|'P', path index)


def put(x, y, kind, idx=0):
    x, y = int(round(x)), int(round(y))
    if (x, y) not in pix:
        pix[(x, y)] = (kind, idx)


for y in range(8, 64):
    for x in range(160):
        if math.hypot(x + .5 - EC[0] - .5, y + .5 - EC[1] - .5) <= ER:
            put(x, y, 'E')
        if math.hypot(x + .5 - MC[0] - .5, y + .5 - MC[1] - .5) <= MR:
            put(x, y, 'M')
for (x, y) in [(132, 29), (137, 34), (139, 28)]:
    del pix[(x, y)]                  # craters


def bez(p0, p1, p2, t):
    return tuple((1 - t) ** 2 * p0[i] + 2 * t * (1 - t) * p1[i] + t * t * p2[i] for i in range(2))


LR = 14
a0 = math.radians(-145)
lp0 = (MC[0] + LR * math.cos(a0), MC[1] + LR * math.sin(a0))
lp1 = (MC[0] + LR * math.cos(-a0), MC[1] + LR * math.sin(-a0))
def rasterise(segs):
    """Curves t=0..1 -> pixel points in travel order, and each curve's start."""
    pts, starts = [], []
    for sf in segs:
        starts.append(len(pts))
        for i in range(801):
            p = tuple(int(round(v)) for v in sf(i / 800))
            if not pts or pts[-1] != p:
                pts.append(p)
    return pts, starts


segs = [lambda t: bez((33, 30), (78, -4), lp0, t),
        lambda t: (MC[0] + LR * math.cos(a0 - 2 * a0 * t), MC[1] + LR * math.sin(a0 - 2 * a0 * t)),
        lambda t: bez(lp1, (78, 70), (33, 42), t)]
path, seg_start = rasterise(segs)
for i, (x, y) in enumerate(path):
    assert (x, y) not in pix or pix[(x, y)][0] == 'P', ('path hits object', x, y)
    put(x, y, 'P', i + 1)

COL = {'E': 'FG_BLUE', 'M': 'FG_WHITE'}
map_cards, map_bt = [], []
for cy in range(1, 8):
    for cx in range(20):
        cell = [(x, y) for y in range(cy * 8, cy * 8 + 8) for x in range(cx * 8, cx * 8 + 8) if (x, y) in pix]
        if not cell:
            continue
        kinds = {pix[p][0] for p in cell}
        assert len(kinds) == 1, ('mixed card', cx, cy, kinds)
        kind = kinds.pop()
        c = [sum(1 << (7 - i) for i in range(8) if (cx * 8 + i, cy * 8 + r) in pix) for r in range(8)]
        if c not in map_cards:
            map_cards.append(c)
        idx = min(pix[p][1] for p in cell) if kind == 'P' else 0
        map_bt.append((cy * 20 + cx, map_cards.index(c), kind, idx))
for pos in list(range(120, 125)) + list(range(135, 139)):  # EARTH / MOON labels
    assert pos not in [e[0] for e in map_bt], ('label overlaps map', pos)

n_map = len(map_cards)
map_cards.append(card(['..XXX...', '.XXXXX..', 'XX...XX.', 'XX.X.XX.',          # you-are-here
                       'XX...XX.', '.XXXXX..', '..XXX...', '........']))         # ring, centre (3,3)
# Land: sprites 1, 5, 6 (16 rows, one pixel each) across the disc, sprite 7 below
MAP_LY = 25
map_land = land_grid(24, 24, 8, MAP_LY, 20, 36, 11)
if len(map_cards) % 2:
    map_cards.append(BLANK)
MAP_L = len(map_cards)
for s in range(3):
    map_cards += grid_cards(map_land, s * 8, 0)
below = [sum(map_land[y][x0 + i] for i in range(8) for y in range(16, 24)) for x0 in range(17)]
MAP_LX = below.index(max(below))
map_cards += grid_cards(map_land, MAP_LX, 16, 1)
print('map land pixels', sum(map(sum, map_land)), 'below the tall sprites', sum(map(sum, map_land[16:])),
      'lost', sum(map(sum, map_land[16:])) - max(below))
assert len(map_cards) <= 64, len(map_cards)
while len(map_cards) < 64:
    map_cards.append(BLANK)

# Ship position after each stage (0 = on the pad .. 8 = home): x, y, progress
L0, L1, L2 = seg_start[0], seg_start[1], seg_start[2]
n_out, n_loop, n_back = L1 - L0, L2 - L1, len(path) - L2
stops = [None, L0, L0 + n_out * 15 // 100, L0 + n_out * 40 // 100, L1,
         L1 + n_loop // 2, L1 + n_loop * 85 // 100, L2 + n_back // 2, None]
pts = []
for s, i in enumerate(stops):
    if i is None:
        x, y = (28, 29) if s == 0 else (28, 42)
        prog = 0 if s == 0 else len(path) + 1
    else:
        (x, y), prog = path[i], i + 1
    if s == 5:
        x, y = 138, 33        # landed: on the Moon itself, not in orbit
    pts += [x, y, prog]

# ---------------------------------------------------------------- map overlay
# A smaller trip map over the cockpit windows while a keypad key pauses the
# game: map on rows 2-5 (y 16-47), where-you-are line on row 1. It borrows
# the window art's GRAM cards (0-29, 48-53, 56-57) and leaves the panel's
# (ball, dial, wing, needle, trip strip) alone. Same rule as the big map:
# one object per card. Out along the top, round the Moon's far side, back
# along the bottom.
OV_SLOTS = list(range(30)) + list(range(48, 54)) + [56, 57]
OEC, OER = (12, 32), 7.6           # Earth: cards cols 0-2 rows 3-4
OMC, OMR = (144, 32), 5.3          # Moon: cards cols 17-18 rows 3-4
OLR = 12                           # loop radius, clear of the Moon's cards
opix = {}


def oput(x, y, kind, idx=0):
    if (x, y) not in opix:
        opix[(x, y)] = (kind, idx)


for y in range(16, 48):
    for x in range(160):
        if math.hypot(x + .5 - OEC[0], y + .5 - OEC[1]) <= OER:
            oput(x, y, 'E')
        if math.hypot(x + .5 - OMC[0], y + .5 - OMC[1]) <= OMR:
            oput(x, y, 'M')
for (x, y) in [(142, 30), (146, 33)]:
    del opix[(x, y)]                 # craters

osegs = [lambda t: bez((26, 27), (29, 20), (40, 20), t),
         lambda t: (40 + 104 * t, 20),
         lambda t: (OMC[0] + OLR * math.sin(math.pi * t), OMC[1] - OLR * math.cos(math.pi * t)),
         lambda t: (144 - 104 * t, 44),
         lambda t: bez((40, 44), (29, 44), (26, 37), t)]
opath, ostart = rasterise(osegs)
for i, (x, y) in enumerate(opath):
    assert 16 <= y < 48, ('overlay path leaves rows 2-5', x, y)
    assert (x, y) not in opix or opix[(x, y)][0] == 'P', ('overlay path hits object', x, y)
    oput(x, y, 'P', i + 1)

ov_cards, ov_bt = [], []
for cy in range(2, 6):
    for cx in range(20):
        cell = [(x, y) for y in range(cy * 8, cy * 8 + 8) for x in range(cx * 8, cx * 8 + 8) if (x, y) in opix]
        if not cell:
            continue
        kinds = {opix[p][0] for p in cell}
        assert len(kinds) == 1, ('mixed overlay card', cx, cy, kinds)
        kind = kinds.pop()
        c = [sum(1 << (7 - i) for i in range(8) if (cx * 8 + i, cy * 8 + r) in opix) for r in range(8)]
        if c not in ov_cards:
            ov_cards.append(c)
        idx = min(opix[p][1] for p in cell) if kind == 'P' else 0
        ov_bt.append((cy * 20 + cx, OV_SLOTS[ov_cards.index(c)], kind, idx))
assert len(ov_cards) <= len(OV_SLOTS) - 2, ('overlay needs too many cards', len(ov_cards))
n_ov = len(ov_cards)
while len(ov_cards) < len(OV_SLOTS) - 2:
    ov_cards.append(BLANK)
ov_cards.append(map_cards[n_map])                            # ring, slot 56
ov_cards.append(BLANK)                                       # slot 57
# Land: two tall sprites in spare slots 24-27, one pixel each
assert n_ov <= 24, n_ov
ov_land = land_grid(16, 16, 4, 24, OEC[0], OEC[1], OER)
ov_cards[24:28] = grid_cards(ov_land, 0, 0) + grid_cards(ov_land, 8, 0)

# The small Earth (Earthrise, Moon base): 8 x 8 at double size, too coarse for
# the globe to work out, so drawn by hand: Canada and the US, Mexico, South America
oland = ['........', '.XXXX...', 'XXXXX...', '.XXX....',
         '..X.....', '...XXX..', '....XX..', '....X...']
for j, row in enumerate(oland):
    for i, ch in enumerate(row):
        assert ch == '.' or disc[j][i] == 'X', ('land off Earth', i, j)

# Ship on the overlay: 0 = on the pad (countdown), s = during stage s
oloop, oback = ostart[3] - ostart[2], len(opath) - ostart[3]
oidx = [None, 0, ostart[2] * 15 // 100, ostart[2] * 40 // 100, ostart[2],
        ostart[2] + oloop // 2, ostart[2] + oloop * 85 // 100, ostart[3] + oback // 2, len(opath) - 1]
after = [(18, 26, 0)] + [opath[i] + (i + 1,) for i in oidx[1:]]
after[5] = (140, 31, after[5][2])                            # landed on the Moon
after[8] = (18, 38, len(opath) + 1)                          # home
during = [after[0]]
for s in range(1, 9):
    if s in (1, 5, 6):          # off the path: halfway between the two stops
        (x0, y0, p0), (x1, y1, _) = after[s - 1], after[s]
        during.append(((x0 + x1) // 2, (y0 + y1) // 2, p0))
    else:
        m = (oidx[s - 1] + oidx[s]) // 2
        during.append(opath[m] + (m + 1,))

# ---------------------------------------------------------------- docking
# Stage 3 target, seen nose-on: the rocket's top (a disc D px across) with
# the lander in front of it, solid so the bright crosshair and <> stand out
# against it. 16 x 16 per sprite pair, centre (8, 8); Intellivision
# pixels are 1.25x taller than wide, so rows are squashed to look round.
# Frame cards: lander L top/bottom, R top/bottom, then the same for the disc
# (loaded into GRAM 0-7 for DOUBLEY sprites). Sizes 4-16; the game shows
# 10-16 at 2x for the last few feet.
LM_SIZES = [4, 6, 8, 10, 12, 14, 16]


def lm_frame(D):
    r = D / 2

    def at(x, y):
        dx, dy = x + .5 - 8, (y + .5 - 8) * 1.25
        disc = dx * dx + dy * dy <= r * r + .3
        a = .34 * D
        lm = abs(dx) <= a and abs(dy) <= a and abs(dx) + abs(dy) <= 1.42 * a
        return lm, disc

    def cards(k):
        return [[sum(1 << (7 - i) for i in range(8) if at(cx * 8 + i, cy * 8 + r)[k]) for r in range(8)]
                for cx in range(2) for cy in range(2)]
    return cards(0) + cards(1)


lm_f = [c for D in LM_SIZES for c in lm_frame(D)]


# Stage 6 target: the Command Module nose-on, a grey disc with four thruster
# blocks and a dark docking hub so the crosshair and <> stand out against it.
def cm_frame(D):
    r = D / 2 * .86

    def at(x, y):
        dx, dy = x + .5 - 8, (y + .5 - 8) * 1.25
        d2 = dx * dx + dy * dy
        body = d2 <= r * r + .3
        if D >= 10 and abs(abs(dx) - abs(dy)) <= 1 and r * r < d2 <= (r + 2) ** 2:
            body = True
        hub = d2 <= (.42 * r) ** 2 + .3
        return hub, body

    def cards(k):
        return [[sum(1 << (7 - i) for i in range(8) if at(cx * 8 + i, cy * 8 + r)[k]) for r in range(8)]
                for cx in range(2) for cy in range(2)]
    return cards(0) + cards(1)


cm_f = [c for D in LM_SIZES for c in cm_frame(D)]
flag_f = [card(['....XXXX', '........', '....XXXX', '........', '.XXXXXXX', '........', '........', '........']),
          card(['XXXX....', 'XXXX....', 'XXXX....', 'X.......', 'X.......', 'X.......', 'X.......', 'X.......'])]

# ---------------------------------------------------------------- Earth ahead
# Stage 7: the Earth seen from space, the Americas facing you. A real globe:
# rough coastlines in latitude and longitude, turned to face the viewer.
# Cards: disc (left top, bottom; right top, bottom), then land the same way.
def earth_frame(D):
    r = D / 2

    def at(x, y):
        dx, dy = x + .5 - 8, (y + .5 - 8) * 1.25
        if dx * dx + dy * dy > r * r + .3:
            return False, False
        n = sum(globe((x + (i + .5) / 4 - 8) / r, -(y + (j + .5) / 4 - 8) * 1.25 / r) for i in range(4) for j in range(4))
        return True, n >= 7

    def cards(k):
        return [[sum(1 << (7 - i) for i in range(8) if at(cx * 8 + i, cy * 8 + rw)[k]) for rw in range(8)]
                for cx in range(2) for cy in range(2)]
    return cards(0) + cards(1)


EARTH_SIZES = [9, 12, 15]
earth_g = [c for D in EARTH_SIZES for c in earth_frame(D)]

# ---------------------------------------------------------------- Moon
# Stage 4: the Moon ahead, same sizes as the docking target, with dark seas
# cut out once it's big enough. Cards: left top/bottom, right top/bottom.
# moon_x: craters (black sprites), small then large. moon_hz: GRAM 0-9 over the grey ground (the
# card's background colour): k rows of black sky on top with a bumpy edge, and
# black speckles; then the top lip as usual and a speckled bottom lip. Speckles
# on the lip card vanish against black sky, so it serves both.
# earth_f: the Earth's disc and land with the bottom n rows cut off, n = 0-8.
def moon_frame(D):
    r = D / 2
    seas = [(-.18, -.12, .15), (.17, .04, .1), (-.06, .24, .09)]

    def at(x, y):
        dx, dy = x + .5 - 8, (y + .5 - 8) * 1.25
        if dx * dx + dy * dy > r * r + .3:
            return False
        return not (D >= 10 and any(math.hypot(dx - a * D, dy - b * D) < c * D for a, b, c in seas))
    return [[sum(1 << (7 - i) for i in range(8) if at(cx * 8 + i, cy * 8 + rw)) for rw in range(8)]
            for cx in range(2) for cy in range(2)]


moon_f = [c for D in LM_SIZES for c in moon_frame(D)]
moon_x = [card(['.XX.....', 'X..X....', 'X..X....', '.XX.....'] + ['........'] * 4),
          card(['..XXXX..', '.XXXXXX.', 'XXX..XXX', 'XX....XX',
                'X......X', 'X......X', '.X....X.', '..XXXX..'])]
BUMP = [0, 1, 1, 0, -1, 0, 1, 0]             # sky reaches this far below row k
SPECK = [(1, 7), (3, 5), (6, 6)]              # (x, y) dots on the ground


def moon_edge(k, lip=False):
    rows = []
    for y in range(8):
        s = ''
        for x in range(8):
            sky = k > 0 and y < k + BUMP[x]
            s += 'X' if sky or (x, y) in SPECK or (lip and y >= 6) else '.'
        rows.append(s)
    return card(rows)


moon_hz = [moon_edge(k) for k in range(8)] + [cm[8], moon_edge(0, True)]
# moon_g: the plain ground card with its dots scrolled down 0-7 rows
gr_rows = [''.join('X' if (x, y) in SPECK else '.' for x in range(8)) for y in range(8)]
moon_g = [card(gr_rows[8 - n:] + gr_rows[:8 - n]) for n in range(8)]
earth_f = []
for n in range(9):
    for art in (disc, oland):
        earth_f.append(card(art[:8 - n] + ['........'] * n))

# ---------------------------------------------------------------- lander
# Stage 5 cockpit, loaded over the command module's window posts and ball.
# Left window: interior up and left of a 45-degree edge. Over sky the interior
# is black up to the edge; over ground (same grey as the frame) only a black
# line shows the edge. The right window is the mirror image.
def slant(sky):
    rows = []
    for y in range(8):
        e = 8 - y
        rows.append(''.join('X' if (x < e if sky else e - 2 <= x < e) else '.' for x in range(8)))
    return card(rows)


def tape(r):
    """8 px wide tape: ticks on the left, a 2 px bar at row r (None = no bar)."""
    rows = []
    for y in range(8):
        s = 'X' if y % 4 == 0 else '.'
        s += '.' + ('XXXXXX' if r is not None and r <= y <= r + 1 else '......')
        rows.append(s)
    return card(rows)


lm_cards = [slant(True), mirror(slant(True)), slant(False), mirror(slant(False)),
            card(['......XX'] * 8), card(['XX......'] * 8)]
lm_cards += [tape(r) for r in range(8)] + [tape(None)]
lm_cards += [card(['XX....XX', 'XXX..XXX', '.XXXXXX.', '..XXXX..',
                   '..XXXX..', '.XXXXXX.', 'XXX..XXX', 'XX....XX']),     # landing X
             card(['XXX.....'] * 3 + ['........'] * 5),                  # drift dot
             card(['..XX....', '.XXXX.XX', '.XXXX.XX', '..XX....',       # boulders
                   '.....XX.', '.XX.XXXX', 'XXXX.XX.', '.XX.....'])]
assert len(lm_cards) == 18, len(lm_cards)


def drift_dial(x, y):
    """24 x 24: a cross through the middle and ticks around the edge."""
    if x == 11 or y == 11:
        return True
    return (x % 4 == 3 and y in (0, 23)) or (y % 4 == 3 and x in (0, 23))


lm_drift = grid(24, 24, drift_dial)

# ---------------------------------------------------------------- output
# Constants go in their own file: IntyBASIC needs a CONST before its first use
# ---------------------------------------------------------------- moon base
# The landing reward. Astronauts and flag are 8 x 16 sprites shown 2x wide and
# 2x tall. A helmet's visor is just a hole: the black sky shows through it.
def tall(rows):
    assert len(rows) == 16 and all(len(r) == 8 for r in rows), rows
    return [card(rows[:8]), card(rows[8:])]


ast_f = (tall(['...XXXX.', '..XXXXXX', '..X....X', '..X....X', '..XXXXXX', '...XXXX.', '.XXXXXXX', '.XXXXXXX',
               '.X.XXX.X', '.X.XXX.X', '.X.XXX.X', '...XXXX.', '..XXXXXX', '..XX..XX', '..XX..XX', '.XXX.XXX']) +
         tall(['...XXXX.', '..XXXXXX', 'XXX....X', 'X.X....X', 'X.XXXXXX', 'XX.XXXX.', '.XXXXXXX', '..XXXXXX',
               '..XXXX.X', '..XXXX.X', '..XXXX.X', '...XXXX.', '..XXXXXX', '..XX..XX', '..XX..XX', '.XXX.XXX']))

# Flag: three ripple frames, each white, red, blue (two cards each). The pole
# is the white layer's first column. The blue corner has holes for its stars.
RIPPLE = [[0, 0, 0, 0, 1, 1, 1], [0, 0, 0, 1, 1, 1, 0], [0, 0, 1, 1, 1, 0, 0]]


def flag_frame(dy):
    w = [['.'] * 8 for _ in range(16)]
    r = [['.'] * 8 for _ in range(16)]
    b = [['.'] * 8 for _ in range(16)]
    for y in range(16):
        w[y][0] = 'X'
    for c in range(1, 8):
        for s in range(8):          # four bands, two rows each
            y = 1 + s + dy[c - 1]
            w[y][c] = 'X'
            if c <= 3 and s <= 3:
                if (c, s) not in ((2, 1), (1, 3), (3, 3)):
                    b[y][c] = 'X'
            elif s // 2 % 2 == 0:
                r[y][c] = 'X'
    return tall([''.join(x) for x in w]) + tall([''.join(x) for x in r]) + tall([''.join(x) for x in b])


flag_a = [c for dy in RIPPLE for c in flag_frame(dy)]

# The lander on the Moon, drawn on the screen itself: 7 cards wide, 5 tall, at
# column 12, row 3. W = white upper stage, Y = gold lower stage and legs on
# black sky; K = black on the grey ground (card row 4). One colour per card.
BW, BH = 56, 40
bp = {}


def bfill(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            bp[(x, y)] = ch


def bclear(x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            bp.pop((x, y), None)


def bline(x0, y0, x1, y1, ch):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(n + 1):
        bp[(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n))] = ch


# Upper stage: cabin, side tanks, docking tunnel, dish, windows, hatch
bfill(24, 0, 31, 3, 'W')
bfill(18, 3, 37, 15, 'W')
bfill(16, 5, 39, 13, 'W')
bfill(11, 7, 15, 12, 'W')
bfill(40, 7, 44, 12, 'W')
bline(37, 3, 43, 0, 'W')
bfill(42, 0, 47, 1, 'W')
for i in range(5):
    bclear(20 + i, 6 + i, 25, 6 + i)
    bclear(30, 6 + i, 35 - i, 6 + i)
bclear(25, 11, 30, 15)
bclear(26, 0, 29, 1)
# Lower stage: gold box, foil bands, engine bell
bfill(16, 16, 39, 27, 'Y')
bfill(13, 18, 42, 25, 'Y')
for x in range(16, 40, 6):
    bline(x, 16, x + 3, 27, '.')
bfill(23, 28, 32, 31, 'Y')
bclear(25, 30, 30, 31)
# Legs and pads
for d in (0, 1):
    bline(13 + d, 22, 4 + d, 31, 'Y')
    bline(42 - d, 22, 51 - d, 31, 'Y')
bline(17, 27, 8, 31, 'Y')
bline(38, 27, 47, 31, 'Y')
bfill(4, 32, 5, 35, 'K')
bfill(50, 32, 51, 35, 'K')
bfill(1, 36, 8, 37, 'K')
bfill(47, 36, 54, 37, 'K')
bfill(27, 28, 28, 31, 'Y')
bfill(27, 32, 28, 35, 'K')
bfill(24, 36, 31, 37, 'K')
bfill(9, 38, 46, 39, 'K')   # shadow

bp = {k: v for k, v in bp.items() if v != '.'}
COLOURS = {'W': 'FG_WHITE', 'Y': 'FG_YELLOW', 'K': 'FG_BLACK'}
base_c, base_bt = [], []
for cy in range(BH // 8):
    for cx in range(BW // 8):
        cell = {(x % 8, y % 8): bp[(x, y)] for x in range(cx * 8, cx * 8 + 8)
                for y in range(cy * 8, cy * 8 + 8) if (x, y) in bp}
        if not cell:
            continue
        kinds = set(cell.values())
        assert len(kinds) == 1, ('two colours in one card', cx, cy, kinds)
        if cy == 4:
            assert kinds == {'K'}, ('ground row must be black', cx, kinds)
        c = [sum(1 << (7 - i) for i in range(8) if (i, r) in cell) for r in range(8)]
        if c not in base_c:
            base_c.append(c)
        bg = ' + BG_GREY' if cy == 4 else ''
        base_bt.append(((cy + 3) * 20 + cx + 12, '$0800 + {} * 8 + {}{}'.format(22 + base_c.index(c), COLOURS[kinds.pop()], bg)))
assert 16 < len(base_c) <= 28, ('lander card count', len(base_c))

# ---------------------------------------------------------------- re-entry
# Fire streaking up the window: one card, four steps of a scrolling pattern
FLAME = ['X......X', 'X..X...X', '...X....', '...X.X..', '.....X..', '.X...X..', '.X......', '.X....X.']
flame_f = [card([FLAME[(r + s * 2) % 8] for r in range(8)]) for s in range(4)]

# Chutes. One canopy card, used three times, and one card of lines for the right
# half of the fan (flipped for the left half), so every line comes down to one
# point. Cards are 8 x 8 pixels drawn double size; canopies sit 16 wide, side by
# side, with the fan's lines reaching the middle canopy's edge and the side
# canopies' centres.
chute_c = [card(['........', '........', '..XXXX..', '.XXXXXX.', 'XXXXXXXX', 'XX.XX.XX', 'XX.XX.XX', 'X..XX..X']),
           card(['...X...X', '...X..X.', '..X..X..', '..X.X...', '.X.X....', '.XX.....', 'XX......', 'X.......'])]
# The two small chutes first: a smaller canopy, one line a side
drogue_c = [card(['........', '........', '..XXXX..', '.XXXXXX.', 'XXXXXXXX', '.X.XX.X.', '...XX...', '...XX...']),
            card(['...X....', '...X....', '..X.....', '..X.....', '.X......', '.X......', 'X.......', 'X.......'])]

# Splashdown: all at GRAM 10 up, in this order
wave_f = [card(['........', '..XX....', '.X..X...', '........', '......XX', '.....X..', '........', '........']),
          card(['........', '......X.', '.....X.X', '........', '.XX.....', 'X..X....', '........', '........']),
          card(['........', '...XX...', '..X..X..', '........', 'XX......', '..X.....', '........', '........']),
          card(['........', '.......X', '......X.', '........', '..XX....', '.X..X...', '........', '........']),
          card(['........', '....XX..', '...X..X.', '........', 'X......X', '.X......', '........', '........']),
          card(['........', 'X.......', '.X.....X', '........', '...XX...', '..X..X..', '........', '........']),
          card(['........', '.....XX.', '....X..X', '........', '.......X', 'X.X.....', '........', '........']),
          card(['........', '.X......', 'X.X.....', '........', '....XX..', '...X..X.', '........', '........'])]
heli_f = [card(['XXXXXXXX', '...XX...', '..XXXX..', '.XXXXXXX', 'XXXXX..X', '.XXXX...', '..X..X..', '.XXXXXX.']),
          card(['...XX...', '...XX...', '..XXXX..', '.XXXXXXX', 'XXXXX..X', '.XXXX...', '..X..X..', '.XXXXXX.'])]
capsule = card(['...XX...', '...XX...', '..XXXX..', '..XXXX..', '.XXXXXX.', '.XXXXXX.', 'XXXXXXXX', 'XXXXXXXX'])
spray = card(['X..X..X.', '.X.X.X..', '..XXX..X', 'X.XXX.X.', '.XXXXX..', 'XXXXXXXX', '.XXXXXX.', '........'])
ship_c = [card(['........', '........', '........', '........', '........', 'XXXXXXXX', '.XXXXXXX', '..XXXXXX']),
          card(['........', '...X....', '...XX...', '..XXXX..', '..XXXX..', 'XXXXXXXX', 'XXXXXXXX', 'XXXXXXXX']),
          card(['........', '........', '........', '........', '........', 'XXXXXXXX', 'XXXXXXXX', 'XXXXXXX.'])]
cloud_c = [card(['........', '...XX...', '..XXXX.X', '.XXXXXXX', 'XXXXXXXX', 'XXXXXXXX', '.XXXXXX.', '........']),
           card(['........', '........', 'XX......', 'XXXX....', 'XXXXXX..', 'XXXXXXX.', 'XXXXX...', '........'])]
# 10-11 waves, 12 helicopter, 13 capsule, 14 spray, 15 unused, 16 canopy, 17 fan of
# lines, 18-20 ship, 21-22 cloud
sea_c = wave_f[:2] + [heli_f[0], capsule, spray, card(['........'] * 8)] + chute_c + ship_c + cloud_c
SEA_ROW = 7
sea_bt = [(SEA_ROW * 20 + 4 + i, '$0800 + {} * 8 + FG_BLACK + BG_CYAN'.format(18 + i)) for i in range(3)]
for pos, cn in ((5 * 20 + 2, 21), (5 * 20 + 3, 22), (4 * 20 + 14, 21), (4 * 20 + 15, 22), (6 * 20 + 16, 21), (6 * 20 + 17, 22)):
    sea_bt.append((pos, '$0800 + {} * 8 + FG_WHITE + BG_CYAN'.format(cn)))

with open(os.path.join(os.path.dirname(OUT), 'gfx_const.bas'), 'w', newline='\r\n') as f:
    f.write("' Generated by gen_gfx.py - do not edit\n"
            "\tCONST MAP_N = {}\t\t' map cards; ship card = MAP_N\n"
            "\tCONST MAP_E = {}\t\t' map_bt entries\n"
            "\tCONST OV_E = {}\t\t' ov_bt entries (overlay map)\n".format(n_map, len(map_bt), len(ov_bt)))
    f.write("\tCONST MAP_L = {}\t\t' map land sprites: 3 tall, then 1 below\n"
            "\tCONST MAP_LX = {}\t\t' where the lower one sits\n"
            "\tCONST MAP_LY = {}\t\t' top of the land, screen row\n".format(MAP_L, MAP_LX, MAP_LY))
    f.write("\tCONST BASE_N = {}\t\t' moon base lander cards\n"
            "\tCONST BASE_E = {}\t\t' base_bt entries\n".format(len(base_c), len(base_bt)))
    f.write("\tCONST SEA_N = {}\t\t' splashdown cards\n"
            "\tCONST SEA_E = {}\t\t' sea_bt entries\n".format(len(sea_c), len(sea_bt)))

L = ["' Generated by gen_gfx.py - do not edit"]
L.append("' Command-module cockpit cards 0-63")
emit(L, 'cm_gram', cm)
L.append('')
L.append("' Attitude ball: 23 frames of 9 cards (3x3), horizon s-11 px below centre")
emit(L, 'ball_f', [c for s in range(23) for c in ball(s)], lambda n: 'frame {} card {}'.format(n // 9, n % 9))
L.append('')
L.append("' G-force dial: 16 needle positions of 9 cards (3x3), 0-5 g")
emit(L, 'gdial_f', [c for n in range(16) for c in gdial(n)], lambda n: 'frame {} card {}'.format(n // 9, n % 9))
L.append('')
L.append("' Trip map cards (padded to 64)")
emit(L, 'map_gram', map_cards)
L.append('')
L.append("' Trip map layout: BACKTAB pos, card word, path index (0 = Earth/Moon)")
L.append('map_bt:')
for pos, cn, kind, idx in map_bt:
    word = '$0800 + {} * 8{}'.format(cn, (' + ' + COL[kind]) if kind in COL else '')
    L.append('\tDATA {}, {}, {}'.format(pos, word, idx))
L.append('')
L.append("' Ship on the map after stage 0-8: x, y (pixels), path progress")
L.append('map_pts:')
for s in range(9):
    L.append('\tDATA {}, {}, {}\t\' after stage {}'.format(pts[3 * s], pts[3 * s + 1], pts[3 * s + 2], s))
L.append('')
L.append("' Overlay map cards for GRAM 0-29, 48-53, 56 (ring), 57 (continents)")
emit(L, 'ov_gram', ov_cards, lambda n: 'card {}'.format(OV_SLOTS[n]))
L.append('')
L.append("' Overlay map layout: BACKTAB pos, card word, path index (0 = Earth/Moon)")
L.append('ov_bt:')
for pos, cn, kind, idx in ov_bt:
    word = '$0800 + {} * 8{}'.format(cn, (' + ' + COL[kind]) if kind in COL else '')
    L.append('\tDATA {}, {}, {}'.format(pos, word, idx))
L.append('')
L.append("' Ship on the overlay: on the pad, then during stage 1-8: x, y, path progress")
L.append('ov_pts:')
for s, (x, y, pr) in enumerate(during):
    L.append('\tDATA {}, {}, {}\t\' {}'.format(x, y, pr, 'on the pad' if s == 0 else 'during stage {}'.format(s)))

L.append('')
L.append("' Docking target: 7 sizes x 8 cards (lander L/R, rocket top L/R; top, bottom)")
emit(L, 'lm_f', lm_f, lambda n: 'size {} card {}'.format(LM_SIZES[n // 8], n % 8))

L.append('')
L.append("' Command Module target: 7 sizes x 8 cards (hub L/R, body L/R; top, bottom)")
emit(L, 'cm_f', cm_f, lambda n: 'size {} card {}'.format(LM_SIZES[n // 8], n % 8))
L.append('')
L.append("' Flag: stripes, then the blue corner and pole")
emit(L, 'flag_f', flag_f)
L.append('')
L.append("' Moon base: astronaut poses (down, salute), flag ripple frames, lander cards")
emit(L, 'ast_f', ast_f)
emit(L, 'flag_a', flag_a)
emit(L, 'base_c', base_c)
L.append('base_bt:')
for pos, word in base_bt:
    L.append('	DATA {}, {}'.format(pos, word))
L.append('')
L.append("' The Moon ahead: 7 sizes x 4 cards (left top, bottom; right top, bottom)")
emit(L, 'moon_f', moon_f, lambda n: 'size {} card {}'.format(LM_SIZES[n // 4], n % 4))
L.append('')
L.append("' Crater")
emit(L, 'moon_x', moon_x)
L.append('')
L.append("' Horizon cards over the grey Moon: k rows of black sky on top")
emit(L, 'moon_hz', moon_hz)
L.append('')
L.append("' Lander cockpit: window edges, tape, X, dot, boulders")
emit(L, 'lm_cards', lm_cards)
L.append('')
L.append("' Lander drift dial")
emit(L, 'lm_drift', lm_drift)
L.append('')
L.append("' Ground dots scrolling down")
emit(L, 'moon_g', moon_g)
L.append('')
L.append("' The Earth (disc, land) with its bottom 0-8 rows cut off at the horizon")
emit(L, 'earth_f', earth_f, lambda n: 'cut {} {}'.format(n // 2, 'land' if n % 2 else 'disc'))
L.append('')
L.append("' The Earth ahead: 3 sizes x 8 cards (disc, land; left top, bottom, right top, bottom)")
emit(L, 'earth_g', earth_g, lambda n: 'size {} card {}'.format(EARTH_SIZES[n // 8], n % 8))

L.append('')
L.append("' Re-entry: flames, chute; splashdown cards, waves, rotor")
emit(L, 'flame_f', flame_f)
emit(L, 'chute_c', chute_c)
emit(L, 'drogue_c', drogue_c)
emit(L, 'sea_c', sea_c)
emit(L, 'wave_f', wave_f)
emit(L, 'heli_f', heli_f)
L.append('sea_bt:')
for pos, word in sea_bt:
    L.append('\tDATA {}, {}'.format(pos, word))

with open(OUT, 'w', newline='\r\n') as f:
    f.write('\n'.join(L) + '\n')
print('cockpit cards', len(cm), '| map cards', n_map, '+2 | map entries', len(map_bt), '| path', len(path))
print('overlay cards', n_ov, 'of', len(OV_SLOTS) - 2, '| entries', len(ov_bt), '| path', len(opath))
