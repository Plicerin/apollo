# Draws the hand controller for the page, as two SVGs with the same working parts:
# pad_tall.svg, the real handset's shape, stands beside the screen on a computer;
# pad_wide.svg puts the disc beside the keypad, so a phone's thumbs can reach it.
# Our own drawing. The parts carry the data-key, data-side and data-disc tags that
# app.js wires up.
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'clear', '0', 'enter']


def defs(p):
    return f'''<defs>
<linearGradient id="{p}body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3d3530"/><stop offset=".5" stop-color="#352e29"/><stop offset="1" stop-color="#2c2622"/></linearGradient>
<linearGradient id="{p}wall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#191512"/><stop offset=".55" stop-color="#2b2521"/><stop offset="1" stop-color="#4a423b"/></linearGradient>
<linearGradient id="{p}field" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#957f59"/><stop offset=".07" stop-color="#ae9971"/><stop offset="1" stop-color="#a48f68"/></linearGradient>
<radialGradient id="{p}cap" cx=".5" cy=".46" r=".62"><stop offset="0" stop-color="#d4c8aa"/><stop offset=".5" stop-color="#bfb193"/><stop offset=".82" stop-color="#9c8e72"/><stop offset="1" stop-color="#7a6e56"/></radialGradient>
<linearGradient id="{p}btn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4c443d"/><stop offset="1" stop-color="#231e1a"/></linearGradient>
<linearGradient id="{p}well" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#181411"/><stop offset="1" stop-color="#4b433c"/></linearGradient>
<radialGradient id="{p}rim" cx=".5" cy=".5" r=".5"><stop offset=".88" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#241805" stop-opacity=".6"/></radialGradient>
</defs>'''


def body(p, x, y, w, h, r=6):
    return (f'<rect x="{x}" y="{y + 3}" width="{w}" height="{h}" rx="{r + 1}" fill="#000" opacity=".45"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#{p}body)" stroke="#191512"/>'
            f'<rect x="{x + 1}" y="{y + 1}" width="{w - 2}" height="{h - 2}" rx="{r - 1}" fill="none" stroke="#fff" stroke-opacity=".08"/>')


def bay(p, x, y, w, h, fx, fy, fw, fh, r):
    """The keypad's deep bay: a thick lip, the sloped walls with their rails, the tan floor."""
    ix, iy, iw, ih = x + 7, y + 7, w - 14, h - 14
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="#171310"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="none" stroke="#fff" stroke-opacity=".1"/>'
            f'<rect x="{ix}" y="{iy}" width="{iw}" height="{ih}" rx="{r - 6}" fill="url(#{p}wall)"/>'
            f'<rect x="{(ix + fx) / 2:.1f}" y="{(iy + fy) / 2:.1f}" width="{(iw + fw) / 2:.1f}" height="{(ih + fh) / 2:.1f}" rx="{r - 9}" fill="none" stroke="#8a7f70" stroke-opacity=".32" stroke-width="1.4" stroke-dasharray="15 7"/>'
            f'<rect x="{fx}" y="{fy}" width="{fw}" height="{fh}" rx="2.5" fill="url(#{p}field)" stroke="#120e0b"/>')


def key(p, name, cx, cy, sock, cap, cell, fs):
    wordy = name in ('clear', 'enter')
    c = cap / 2
    if wordy:
        text = f'<text class="word" x="{cx}" y="{cy + fs * .19:.1f}" font-size="{fs * .6:.1f}">{name}</text>'
    else:
        # A wide, leaning numeral, as the real keys have
        text = (f'<text class="num" transform="translate({cx} {cy + fs * .36:.1f}) skewX(-8) scale(1.28 1)" '
                f'font-size="{fs:.1f}">{name}</text>')
    return (f'<g class="k" data-key="{name}" role="button" aria-label="{name}">'
            f'<rect class="hit" x="{cx - cell / 2}" y="{cy - cell / 2}" width="{cell}" height="{cell}"/>'
            f'<rect x="{cx - sock / 2}" y="{cy - sock / 2}" width="{sock}" height="{sock}" rx="3.5" fill="#37302a" stroke="#1d1815" stroke-width=".8"/>'
            f'<g class="press"><rect x="{cx - c}" y="{cy - c + 1}" width="{cap}" height="{cap}" rx="{cap * .4:.1f}" fill="#000" opacity=".4"/>'
            f'<rect class="cap" x="{cx - c}" y="{cy - c}" width="{cap}" height="{cap}" rx="{cap * .4:.1f}" fill="url(#{p}cap)"/>'
            f'{text}</g></g>')


def side(p, which, label, left, x, y, w, h, hx, hw, tx, pad=8):
    rot = -90 if left else 90
    return (f'<g class="s" data-side="{which}" role="button" aria-label="{label} side button">'
            f'<rect class="hit" x="{hx}" y="{y - pad}" width="{hw}" height="{h + pad * 2}"/>'
            f'<rect class="btn" x="{x}" y="{y}" width="{w}" height="{h}" rx="1.5" fill="url(#{p}btn)" stroke="#120e0b" stroke-width=".8"/>'
            f'<text class="sl" transform="translate({tx} {y + h / 2}) rotate({rot})" y="2.4" font-size="7">{label}</text></g>')


def disc(p, cx, cy, r):
    """Spun metal in a stepped, round well: two lobes of light across the brushing."""
    out = [f'<g class="d" data-disc role="application" aria-label="Disc: press and drag to steer">'
           f'<circle class="hit" cx="{cx}" cy="{cy}" r="{r + 18}"/>'
           f'<circle cx="{cx}" cy="{cy}" r="{r + 12}" fill="url(#{p}well)"/>'
           f'<circle cx="{cx}" cy="{cy}" r="{r + 12}" fill="none" stroke="#000" stroke-opacity=".5"/>'
           f'<circle cx="{cx}" cy="{cy}" r="{r + 7.5}" fill="#1a1613"/>'
           f'<circle cx="{cx}" cy="{cy}" r="{r + 7.5}" fill="none" stroke="#fff" stroke-opacity=".14"/>'
           f'<circle cx="{cx}" cy="{cy}" r="{r + 2}" fill="#0d0a08"/>'
           f'<g class="plate"><circle cx="{cx}" cy="{cy}" r="{r}" fill="#a98f5e"/>']
    n = 90
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        m = (a0 + a1) / 2
        t = (0.5 + 0.5 * math.cos(2 * (m + math.radians(62)))) ** 3.4
        v = 0.52 + 0.48 * t
        col = '#%02x%02x%02x' % (int(240 * v), int(218 * v), int(160 * v))
        x0, y0 = cx + r * math.cos(a0), cy + r * math.sin(a0)
        x1, y1 = cx + r * math.cos(a1), cy + r * math.sin(a1)
        out.append(f'<path d="M{cx} {cy}L{x0:.1f} {y0:.1f}A{r} {r} 0 0 1 {x1:.1f} {y1:.1f}Z" fill="{col}" stroke="{col}" stroke-width=".8"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{p}rim)"/></g>')
    out.append(f'<circle class="knob" cx="{cx}" cy="{cy}" r="{r * .2:.1f}"/></g>')
    return ''.join(out)


def tall():
    p, W, H = 'pt', 240, 480
    x, y, w, h = 22, 44, 196, 427
    o = [f'<svg class="handset tall" viewBox="0 0 {W} {H}" role="group" aria-label="Hand controller" xmlns="http://www.w3.org/2000/svg">', defs(p)]
    # The cord's stub, then the body and the ledge the overlays slide in under
    o.append(f'<rect x="177" y="4" width="9" height="42" rx="4.5" fill="#0d0b09"/><rect x="179" y="7" width="2" height="36" rx="1" fill="#fff" opacity=".14"/>')
    o.append(body(p, x, y, w, h))
    o.append(f'<path d="M{x + 3} {y + 5.5}H{x + w - 3}" stroke="#171310" stroke-width="1.2"/>')
    o.append(f'<path d="M{x + 3} {y + 3}H{x + w - 3}" stroke="#fff" stroke-opacity=".13" stroke-width="2.4"/>')
    o.append(bay(p, 29, 103, 182, 218, 48, 120, 145, 182, 18))
    for i, name in enumerate(KEYS):
        o.append(key(p, name, 76 + 44.5 * (i % 3), 146 + 44 * (i // 3), 37, 30, 44, 12.5))
    o.append(disc(p, 120, 396, 52))
    # Last, so their wide tap zones sit over the bay's lip
    for which, label, by in (('top', 'TOP', 173), ('lower', 'LOWER', 222)):
        o.append(side(p, which, label, True, 15, by, 7.5, 29, 0, 46, 8))
        o.append(side(p, which, label, False, 217.5, by, 7.5, 29, 194, 46, 232))
    o.append('</svg>')
    return ''.join(o)


def wide():
    p, W, H = 'pw', 360, 196
    o = [f'<svg class="handset wide" viewBox="0 0 {W} {H}" role="group" aria-label="Hand controller" xmlns="http://www.w3.org/2000/svg">', defs(p)]
    o.append(body(p, 9, 5, 342, 186))
    o.append(disc(p, 108, 98, 56))
    o.append(bay(p, 186, 8, 150, 180, 199, 18, 124, 160, 14))
    for i, name in enumerate(KEYS):
        o.append(key(p, name, 220 + 41 * (i % 3), 37 + 41 * (i // 3), 36, 30, 41, 13))
    # Bigger than the real thing here, for thumbs
    for which, label, by in (('top', 'TOP', 24), ('lower', 'LOWER', 102)):
        o.append(side(p, which, label, True, 1, by, 9, 70, 0, 32, 21, 4))
        o.append(side(p, which, label, False, 350, by, 9, 70, 338, 22, 343, 4))
    o.append('</svg>')
    return ''.join(o)


for name, svg in (('pad_tall.svg', tall()), ('pad_wide.svg', wide())):
    with open(os.path.join(HERE, name), 'w', encoding='utf8', newline='\n') as f:
        f.write(svg + '\n')
    print(name, len(svg), 'bytes')
