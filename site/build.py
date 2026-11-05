# Makes the one-file page from template.html, inty.js, app.js, the cartridge
# and the screens in img/. Output: site/artifact.html (body only, no repo links) and
# ../index.html (the whole page, served by GitHub Pages from the repo root).
import base64
import io
import os
import re

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def read(*p):
    return open(os.path.join(HERE, *p), encoding='utf8', newline='').read().replace('\r\n', '\n')


def data_uri(name):
    im = Image.open(os.path.join(HERE, 'img', name + '.png'))
    if im.mode != 'RGBA':
        im = im.convert('RGB').convert('P', palette=Image.ADAPTIVE, colors=16)
    b = io.BytesIO()
    im.save(b, 'PNG', optimize=True)
    return 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()


t = read('template.html')
t = re.sub(r'\{\{img:([a-z0-9_]+)\}\}', lambda m: data_uri(m.group(1)), t)
rom = base64.b64encode(open(os.path.join(HERE, '..', 'cockpit', 'cockpit.rom'), 'rb').read()).decode()
inty = read('inty.js').replace("if (typeof module !== 'undefined') module.exports = { Inty, PAD, INTY_PALETTE, SCREEN_W, SCREEN_H };\n", '')
t = t.replace('{{rom}}', rom).replace('{{inty}}', inty).replace('{{app}}', read('app.js'))
t = t.replace('{{pad_tall}}', read('pad_tall.svg')).replace('{{pad_wide}}', read('pad_wide.svg'))
assert '{{' not in t, t[t.index('{{'):][:60]
MARK = '<!--PAGES_LINKS-->\n'
LINKS = ('        <li><a href="https://github.com/Plicerin/apollo">Source code</a></li>\n'
         '        <li><a href="cockpit/cockpit.rom" download="apollo.rom">Download the cartridge (apollo.rom)</a></li>\n')
open(os.path.join(HERE, 'artifact.html'), 'w', encoding='utf8', newline='\n').write(t.replace(MARK, ''))
t = t.replace(MARK, LINKS)

m = re.match(r'(\s*<title>.*?</title>\s*(?:<meta[^>]*>\s*)*(?:<link[^>]*>\s*)*<style>.*?</style>)', t, re.S)
head, body = m.group(1), t[m.end():]
page = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        + head + '\n</head>\n<body>\n' + body + '\n</body>\n</html>\n')
open(os.path.join(HERE, '..', 'index.html'), 'w', encoding='utf8', newline='\n').write(page)
print('index.html', len(page), 'bytes')
