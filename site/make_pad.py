# Draws the hand controller for the page, as two SVGs with the same working parts:
# pad_tall.svg, the real handset's shape, stands beside the screen on a computer;
# pad_wide.svg puts the disc beside the keypad, so a phone's thumbs can reach it.
# Our own drawing, from the handset's layout. The parts carry the data-key,
# data-side and data-disc tags that app.js wires up.
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

STAGES = {'1': 'LIFTOFF', '2': 'ORBIT', '3': 'DOCK', '4': 'BRAKE', '5': 'LAND',
          '6': 'MEET UP', '7': 'HOME', '8': 'RE-ENTRY', '9': ''}
KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'clear', '0', 'enter']


def defs(p):
    return f'''<defs>
<linearGradient id="{p}body" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#46372b"/><stop offset=".55" stop-color="#31261e"/><stop offset="1" stop-color="#211912"/></linearGradient>
<linearGradient id="{p}well" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0d0906"/><stop offset="1" stop-color="#2a2019"/></linearGradient>
<linearGradient id="{p}cap" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4e6c2"/><stop offset=".5" stop-color="#dcc391"/><stop offset="1" stop-color="#b3935a"/></linearGradient>
<linearGradient id="{p}btn" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#6a5644"/><stop offset="1" stop-color="#2a2019"/></linearGradient>
<radialGradient id="{p}rim" cx=".5" cy=".5" r=".5"><stop offset=".86" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#2a1d0c" stop-opacity=".55"/></radialGradient>
</defs>'''


def body(p, x, y, w, h):
    return (f'<rect x="{x}" y="{y + 3}" width="{w}" height="{h}" rx="13" fill="#000" opacity=".45"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="url(#{p}body)" stroke="#120c08"/>'
            f'<rect x="{x + 1.5}" y="{y + 1.5}" width="{w - 3}" height="{h - 3}" rx="10.5" fill="none" stroke="#fff" stroke-opacity=".07"/>')


def key(p, name, cx, cy, cw, ch, hw, hh, fs):
    label = {'clear': 'clear', 'enter': 'enter'}.get(name, name)
    small = name in ('clear', 'enter')
    size = fs * 0.62 if small else fs
    return (f'<g class="k" data-key="{name}" role="button" aria-label="{label}">'
            f'<rect class="hit" x="{cx - hw / 2}" y="{cy - hh / 2}" width="{hw}" height="{hh}"/>'
            f'<rect x="{cx - cw / 2 - 3}" y="{cy - ch / 2 - 3}" width="{cw + 6}" height="{ch + 6}" rx="8" fill="#0b0705"/>'
            f'<g class="press"><rect class="cap" x="{cx - cw / 2}" y="{cy - ch / 2}" width="{cw}" height="{ch}" rx="{min(cw, ch) * .36:.1f}" fill="url(#{p}cap)"/>'
            f'<rect x="{cx - cw / 2 + 4}" y="{cy - ch / 2 + 2}" width="{cw - 8}" height="{ch * .28:.1f}" rx="{ch * .14:.1f}" fill="#fff" opacity=".28"/>'
            f'<text class="num" x="{cx}" y="{cy + size * .36:.1f}" font-size="{size:.1f}">{label}</text></g></g>')


def side(p, which, label, left, x, y, w, h, hx, hw, tx):
    grad = f'url(#{p}btn)'
    flip = '' if left else f' transform="translate({2 * x + w} 0) scale(-1 1)"'
    rot = -90 if left else 90
    return (f'<g class="s" data-side="{which}" role="button" aria-label="{label} side button">'
            f'<rect class="hit" x="{hx}" y="{y - 3}" width="{hw}" height="{h + 6}"/>'
            f'<g{flip}><rect class="btn" x="{x}" y="{y}" width="{w}" height="{h}" rx="2.5" fill="{grad}" stroke="#0b0705"/></g>'
            f'<text class="sl" transform="translate({tx} {y + h / 2}) rotate({rot})" y="2.6" font-size="7.5">{label}</text></g>')


def disc(p, cx, cy, r):
    """Spun metal: wedges of light and dark, as round-brushed metal catches a lamp."""
    out = [f'<g class="d" data-disc role="application" aria-label="Disc: press and drag to steer">'
           f'<circle class="hit" cx="{cx}" cy="{cy}" r="{r + 16}"/>'
           f'<circle cx="{cx}" cy="{cy}" r="{r + 9}" fill="url(#{p}well)"/>'
           f'<circle cx="{cx}" cy="{cy}" r="{r + 9}" fill="none" stroke="#fff" stroke-opacity=".1"/>'
           f'<g class="plate"><circle cx="{cx}" cy="{cy}" r="{r}" fill="#c8ae7e"/>']
    n = 72
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        m = (a0 + a1) / 2
        t = 0.5 + 0.5 * math.cos(2 * (m - math.radians(62)))
        t = t ** 2.4
        u = 0.5 + 0.5 * math.cos(6 * m + 1)
        v = 0.70 + 0.30 * t + 0.03 * u
        col = '#%02x%02x%02x' % (min(255, int(238 * v)), min(255, int(208 * v)), min(255, int(152 * v)))
        x0, y0 = cx + r * math.cos(a0), cy + r * math.sin(a0)
        x1, y1 = cx + r * math.cos(a1), cy + r * math.sin(a1)
        out.append(f'<path d="M{cx} {cy}L{x0:.1f} {y0:.1f}A{r} {r} 0 0 1 {x1:.1f} {y1:.1f}Z" fill="{col}" stroke="{col}" stroke-width=".9"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{p}rim)"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#6e5529"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="2" fill="#8a6c38"/></g>')
    out.append(f'<circle class="knob" cx="{cx}" cy="{cy}" r="{r * .19:.1f}"/></g>')
    return ''.join(out)


def cord(x, top, y):
    """The coiled cord, leaving the handset's top corner."""
    loops = ''.join(f'<ellipse cx="{x + (i % 2) * 2}" cy="{y - 4 - i * 6.2:.1f}" rx="9" ry="4.2" transform="rotate(-14 {x} {y - 4 - i * 6.2:.1f})"/>'
                    for i in range(int((y - top) / 6.2)))
    return f'<g fill="none" stroke="#0a0705" stroke-width="3">{loops}</g>'


def tall():
    p, W, H = 'pt', 240, 590
    x, y, w, h = 12, 36, 216, 546
    o = [f'<svg class="handset tall" viewBox="0 0 {W} {H}" role="group" aria-label="Hand controller" xmlns="http://www.w3.org/2000/svg">', defs(p)]
    o.append(cord(198, 2, y + 3))
    # Side buttons go first, so the body's edge sits over their inner end
    for which, label, by in (('top', 'TOP', 306), ('lower', 'LOWER', 364)):
        o.append(side(p, which, label, True, 5, by, 12, 48, 0, 33, 23))
        o.append(side(p, which, label, False, 223, by, 12, 48, 207, 33, 217))
    body_svg = body(p, x, y, w, h)
    # Keep the side buttons clickable and visible: draw the body underneath them
    o.insert(3, body_svg)
    # The ledge the overlay slides in under
    o.append(f'<rect x="{x + 1}" y="{y + 1}" width="{w - 2}" height="17" rx="10" fill="#fff" opacity=".05"/>')
    o.append(f'<path d="M{x + 2} {y + 18}H{x + w - 2}" stroke="#120c08"/>')
    # The keypad bay, and the Apollo overlay in it
    bx, by, bw, bh = 34, 62, 172, 288
    o.append(f'<rect x="{bx - 3}" y="{by - 3}" width="{bw + 6}" height="{bh + 6}" rx="15" fill="url(#{p}well)"/>')
    o.append(f'<rect class="ov" x="{bx + 2}" y="{by + 2}" width="{bw - 4}" height="{bh - 4}" rx="10"/>')
    o.append(f'<text class="ovt" x="120" y="{by + 18}" font-size="9">APOLLO</text>')
    for i, name in enumerate(KEYS):
        cx, cy = 68 + 52 * (i % 3), 100 + 58 * (i // 3)
        o.append(key(p, name, cx, cy, 42, 28, 52, 58, 16))
        if STAGES.get(name):
            o.append(f'<text class="ovl" x="{cx}" y="{cy + 25}" font-size="7.6">{STAGES[name]}</text>')
    o.append(f'<text class="ovf" x="120" y="{by + bh - 7}" font-size="7.2">IN FLIGHT, ANY KEY: TRIP MAP</text>')
    o.append(disc(p, 120, 468, 70))
    o.append('</svg>')
    return ''.join(o)


def wide():
    p, W, H = 'pw', 360, 196
    o = [f'<svg class="handset wide" viewBox="0 0 {W} {H}" role="group" aria-label="Hand controller" xmlns="http://www.w3.org/2000/svg">', defs(p)]
    o.append(body(p, 8, 5, 344, 186))
    for which, label, by in (('top', 'TOP', 22), ('lower', 'LOWER', 102)):
        o.append(side(p, which, label, True, 1, by, 12, 72, 0, 30, 19))
        o.append(side(p, which, label, False, 347, by, 12, 72, 330, 30, 341))
    o.append(disc(p, 112, 98, 62))
    bx, by, bw, bh = 194, 13, 134, 170
    o.append(f'<rect x="{bx - 3}" y="{by - 3}" width="{bw + 6}" height="{bh + 6}" rx="13" fill="url(#{p}well)"/>')
    o.append(f'<rect class="ov" x="{bx + 2}" y="{by + 2}" width="{bw - 4}" height="{bh - 4}" rx="8"/>')
    for i, name in enumerate(KEYS):
        cx, cy = 219 + 42 * (i % 3), 37 + 41 * (i // 3)
        o.append(key(p, name, cx, cy, 34, 30, 42, 41, 15))
    o.append('</svg>')
    return ''.join(o)


for name, svg in (('pad_tall.svg', tall()), ('pad_wide.svg', wide())):
    with open(os.path.join(HERE, name), 'w', encoding='utf8', newline='\n') as f:
        f.write(svg + '\n')
    print(name, len(svg), 'bytes')
