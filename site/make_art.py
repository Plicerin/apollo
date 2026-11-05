# Pixel art for the page: the APOLLO wordmark, whose two O's are the Earth and
# the Moon joined by the flight path. Uses the game's own coastlines (gen_gfx.py)
# and the page's own character set (inty.js).
import math
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'cockpit', 'gen_gfx.py'), encoding='latin1').read()
a = src.index('EARTH_LAND = [')
b = src.index('def land_grid(')
exec(src[a:b])          # EARTH_LAND, on_land, globe

js = open(os.path.join(HERE, 'inty.js'), encoding='utf8').read()
hexes = ''.join(re.findall(r"'([0-9A-F ]+)'", js[js.index('const FONT_HEX'):js.index('function makeGrom')]))
hexes = hexes.replace(' ', '')


def glyph(ch):
    i = ord(ch) - 32
    return [int(hexes[(i * 8 + r) * 2:(i * 8 + r) * 2 + 2], 16) for r in range(8)]


WHITE = (255, 255, 255, 255)
GREY = (200, 200, 200, 255)
DIM = (120, 124, 140, 255)
BLUE = (20, 56, 247, 255)
GREEN = (7, 194, 0, 255)
YELLOW = (255, 255, 1, 255)
RED = (227, 91, 14, 255)
ICE = (235, 240, 255, 255)

S = 3            # cells per font pixel
CELL = 24
W = CELL * 6 + 6
H = 46
TOP = 3
im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
px = im.load()


def letter(ch, col):
    g = glyph(ch)
    for y in range(7):
        for x in range(8):
            if (g[y] >> (7 - x)) & 1:
                for j in range(S):
                    for i in range(S):
                        px[col * CELL + 3 + x * S + i, TOP + y * S + j] = WHITE


for col, ch in enumerate('APOLLO'):
    if col not in (2, 5):
        letter(ch, col)

# Earth, facing the Americas, in the place of the first O
ecx, ecy, er = 2 * CELL + 3 + 10.5, TOP + 10.5, 11.5
for y in range(H):
    for x in range(W):
        dx, dy = x + .5 - ecx - .5, y + .5 - ecy - .5
        if dx * dx + dy * dy <= er * er:
            n = 0
            for i in range(3):
                for j in range(3):
                    n += globe((dx + (i - 1) / 3) / er, -(dy + (j - 1) / 3) / er)
            c = GREEN if n >= 4 else BLUE
            px[x, y] = c

# Moon, in the place of the second O
mcx, mcy, mr = 5 * CELL + 3 + 10.5, TOP + 10.5, 10.5
craters = [(-3.5, -4, 2.2), (4, -1.5, 1.6), (-1, 4.5, 2.6), (5, 5, 1.2), (-6.5, 2, 1.1), (1.5, -6.5, 1.2)]
for y in range(H):
    for x in range(W):
        dx, dy = x + .5 - mcx - .5, y + .5 - mcy - .5
        if dx * dx + dy * dy <= mr * mr:
            c = WHITE
            if dx * .55 + dy * .75 > mr * .62:
                c = GREY
            for cx, cy, r in craters:
                if (dx - cx) ** 2 + (dy - cy) ** 2 <= r * r:
                    c = GREY if (dx - cx) ** 2 + (dy - cy) ** 2 > (r - 1) ** 2 else DIM
            px[x, y] = c


# The flight path: out of the Earth, under the L's, round the Moon's far side
def bez(p0, p1, p2, p3, t):
    u = 1 - t
    return (u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1])


def stroke(pts, color):
    last = None
    for x, y in pts:
        q = (round(x), round(y))
        if q != last and 0 <= q[0] < W and 0 <= q[1] < H:
            if px[q[0], q[1]][3] == 0:
                px[q[0], q[1]] = color
        last = q


path = [bez((ecx + 9, ecy + 9), (ecx + 24, ecy + 28), (mcx - 32, mcy + 29), (mcx, mcy + 13.5), t / 400) for t in range(401)]
# round the far side of the Moon
path += [(mcx + 13.5 * math.cos(a), mcy + 13.5 * math.sin(a)) for a in [math.pi / 2 - k * (math.pi * 1.32) / 200 for k in range(201)]]
stroke(path, YELLOW)

# The ship on its way
sx, sy = bez((ecx + 9, ecy + 9), (ecx + 24, ecy + 28), (mcx - 32, mcy + 29), (mcx, mcy + 13.5), .56)
for j in range(-1, 2):
    for i in range(-1, 2):
        if abs(i) + abs(j) < 2:
            px[round(sx) + i, round(sy) + j] = RED

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'img', 'wordmark.png')
os.makedirs(os.path.dirname(out), exist_ok=True)
im = im.crop(im.getbbox())
im.save(out, optimize=True)
print(out, im.size)

# A larger view for the page icon and previews
big = im.resize((im.width * 6, im.height * 6), Image.NEAREST)
bg = Image.new('RGB', big.size, (5, 7, 20))
bg.paste(big, (0, 0), big)
bg.save(out.replace('.png', '_preview.png'))
