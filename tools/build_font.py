"""Gera uma fonte OTF a partir de fotos de um alfabeto grafite.

uso: python build_font.py letras.jpg numeros.jpg saida.otf

letras.jpg  : A-Z em linhas, em ordem (tinta escura, fundo claro)
numeros.jpg : linhas "12345", "67890", "*", ".,:+-=<>", '?!(){}[]/"', "@#€$%&"
"""
import sys
import math
import numpy as np
from PIL import Image
from skimage import measure
from scipy import ndimage
import potrace
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.areaPen import AreaPen

SRC_LETTERS, SRC_EXTRAS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
UP = 4             # superamostragem antes de vetorizar (bordas mais lisas)
UPM = 1000
CAP = 720          # altura de maiúscula em unidades
SIDE = 30          # espaçamento lateral em unidades
MATH = 330         # altura do centro de + - = < >
PULL = {'A': 170}  # avanço do traço esquerdo por baixo da letra anterior


def load(path):
    gray = np.array(Image.open(path).convert('L'))
    lab = measure.label(gray < 128, connectivity=2)
    return gray, lab, [p for p in measure.regionprops(lab) if p.area >= 20]


def group_bbox(comps):
    return (min(c.bbox[0] for c in comps), min(c.bbox[1] for c in comps),
            max(c.bbox[2] for c in comps), max(c.bbox[3] for c in comps))


def trace(gray, lab, labels, upx, ybase, name):
    """vetoriza os componentes `labels`; `ybase` é a linha (px da foto) que vira y=0;
    upx = unidades da fonte por pixel da foto"""
    comps_mask = np.isin(lab, labels)
    rows, cols = np.nonzero(comps_mask)
    pad = 4
    r0, c0 = max(rows.min() - pad, 0), max(cols.min() - pad, 0)
    r1, c1 = min(rows.max() + 1 + pad, gray.shape[0]), min(cols.max() + 1 + pad, gray.shape[1])
    own = ndimage.binary_dilation(comps_mask[r0:r1, c0:c1], iterations=2)  # sem vizinhas
    g = gray[r0:r1, c0:c1].astype(float)
    g[~own] = 255
    big_g = np.array(Image.fromarray(g.astype(np.uint8)).resize(
        (g.shape[1] * UP, g.shape[0] * UP), Image.BICUBIC))
    mask = big_g < 128
    # potracer considera "tinta" o valor falso, por isso o ~
    path = potrace.Bitmap(~mask).trace(turdsize=20, alphamax=1.0, opticurve=True, opttolerance=0.2)

    xs = np.nonzero(mask.any(axis=0))[0]
    shift = SIDE - PULL.get(name, 0)
    def tx(p):
        return ((p.x - xs.min()) / UP * upx + shift, (ybase - (r0 + p.y / UP)) * upx)

    adv = int(round((xs.max() - xs.min()) / UP * upx + 2 * SIDE - PULL.get(name, 0)))
    rec = RecordingPen()
    for curve in path:
        rec.moveTo(tx(curve.start_point))
        for seg in curve.segments:
            if seg.is_corner:
                rec.lineTo(tx(seg.c)); rec.lineTo(tx(seg.end_point))
            else:
                rec.curveTo(tx(seg.c1), tx(seg.c2), tx(seg.end_point))
        rec.closePath()
    return rec, (adv, shift)


outlines, metrics = {}, {}

# --- letras -------------------------------------------------------------------
gray, lab, props = load(SRC_LETTERS)
# junta componentes pequenos (pingo do i etc.) ao maior mais próximo
big = [p for p in props if p.area >= 1500]
small = [p for p in props if p.area < 1500]
groups = {p.label: [p] for p in big}
center = lambda b: ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
for s in small:
    sr, sc = center(s.bbox)
    best = min(big, key=lambda b: abs(center(b.bbox)[1] - sc) + abs(center(b.bbox)[0] - sr))
    groups[best.label].append(s)
letters = [dict(labels=[c.label for c in cs], bbox=group_bbox(cs)) for cs in groups.values()]

# linhas pelo centro vertical, depois ordena por x
letters.sort(key=lambda l: center(l['bbox'])[0])
rows, cur = [], [letters[0]]
for l in letters[1:]:
    if center(l['bbox'])[0] - np.mean([center(x['bbox'])[0] for x in cur]) > 60:
        rows.append(cur); cur = [l]
    else:
        cur.append(l)
rows.append(cur)
flat = []
for row in rows:
    row.sort(key=lambda l: l['bbox'][1])
    base = float(np.median([l['bbox'][2] for l in row]))   # linha de base = mediana dos fundos
    for l in row:
        l['base'] = base
    flat += row
assert len(flat) == 26, f'esperava 26 letras, achei {len(flat)}: {[len(r) for r in rows]}'
upx = CAP / float(np.median([l['base'] - l['bbox'][0] for l in flat]))
for idx, l in enumerate(flat):
    name = chr(65 + idx)
    outlines[name], metrics[name] = trace(gray, lab, l['labels'], upx, l['base'], name)

# --- números e símbolos -----------------------------------------------------------
EXTRA_ROWS = [  # (faixa vertical do topo dos componentes em px, caracteres, ampliação)
    ((40, 155), '12345', 1.0),
    ((155, 275), '67890', 1.0),
    ((275, 345), '*', 1.0),
    ((345, 387), ".,:+-=<>", 1.7),       # na foto são bem menores que os números
    ((387, 475), '?!(){}[]/"', 1.3),
    ((475, 565), '@#€$%&', 1.25),
]
GNAME = {',': 'comma', "'": 'quotesingle', ':': 'colon', '+': 'plus', '-': 'hyphen', '=': 'equal',
         '<': 'less', '>': 'greater', '?': 'question', '!': 'exclam', '(': 'parenleft',
         ')': 'parenright', '{': 'braceleft', '}': 'braceright', '[': 'bracketleft',
         ']': 'bracketright', '/': 'slash', '"': 'quotedbl', '@': 'at', '#': 'numbersign',
         '€': 'Euro', '$': 'dollar', '%': 'percent', '&': 'ampersand', '*': 'asterisk', '.': 'period',
         '0': 'zero', '1': 'one', '2': 'two', '3': 'three', '4': 'four', '5': 'five', '6': 'six',
         '7': 'seven', '8': 'eight', '9': 'nine'}

gray, lab, props = load(SRC_EXTRAS)
extras = {}
for (ylo, yhi), chars, zoom in EXTRA_ROWS:
    comps = sorted([p for p in props if ylo <= p.bbox[0] < yhi], key=lambda p: p.bbox[1])
    glyphs = []
    for c in comps:
        for gl in glyphs:
            b = group_bbox(gl)
            ov = min(b[3], c.bbox[3]) - max(b[1], c.bbox[1])
            w = min(b[3] - b[1], c.bbox[3] - c.bbox[1])
            gap = c.bbox[1] - b[3]
            # mesma coluna (pingos, ':' '=' '%') ou dois traços pequenos colados ('"')
            if ov > 0.5 * w or ('"' in chars and c.area < 300 and all(x.area < 300 for x in gl) and gap <= 3):
                gl.append(c); break
        else:
            glyphs.append([c])
    assert len(glyphs) == len(chars), f'linha {chars!r}: achei {len(glyphs)} glifos'
    base = float(np.median([group_bbox(g)[2] for g in glyphs]))
    for ch, g in zip(chars, glyphs):
        extras[ch] = dict(comps=g, bbox=group_bbox(g), base=base, zoom=zoom)

digit_h = np.median([extras[d]['bbox'][2] - extras[d]['bbox'][0] for d in '0123456789'])
upx2 = CAP / float(digit_h)

def place(ch, info):
    """linha da foto que vira y=0, conforme o tipo de símbolo"""
    top, bot = info['bbox'][0], info['bbox'][2]
    u = upx2 * info['zoom']
    if ch in "*'\"":
        return top + CAP / u                 # pendura na altura de maiúscula
    if ch in '+-=<>':
        return (top + bot) / 2 + MATH / u    # centrado na altura matemática
    if ch == ',':
        return top + 110 / u                 # desce abaixo da linha de base
    if ch in ':.':
        return bot
    return info['base']

for ch, info in extras.items():
    gname = GNAME[ch]
    outlines[gname], metrics[gname] = trace(gray, lab, [c.label for c in info['comps']],
                                            upx2 * info['zoom'], place(ch, info), gname)
# apóstrofo: a vírgula pendurada na altura de maiúscula
com = extras[',']
u = upx2 * com['zoom']
outlines['quotesingle'], metrics['quotesingle'] = trace(
    gray, lab, [c.label for c in com['comps']], u, com['bbox'][0] + CAP / u, 'quotesingle')

# --- acentos em estilo pincel -------------------------------------------------
ap = AreaPen(); outlines['O'].replay(ap)
outer_sign = 1 if ap.value > 0 else -1   # sentido dos contornos externos do potrace

def poly(pen, pts):
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    if (-a > 0) != (outer_sign > 0):      # AreaPen usa o sinal oposto ao do laço
        pts = pts[::-1]
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()

def stroke(pen, pts, w0, w1):
    """traço com espessura variando de w0 a w1 ao longo de pts"""
    left, right = [], []
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        a = pts[min(i + 1, n - 1)]; b = pts[max(i - 1, 0)]
        dx, dy = a[0] - b[0], a[1] - b[1]
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        w = (w0 + (w1 - w0) * i / (n - 1)) / 2
        left.append((x + nx * w, y + ny * w)); right.append((x - nx * w, y - ny * w))
    poly(pen, left + right[::-1])

def acute(pen, cx, top):  stroke(pen, [(cx - 55, top), (cx + 65, top + 120)], 70, 30)
def grave(pen, cx, top):  stroke(pen, [(cx + 55, top), (cx - 65, top + 120)], 70, 30)
def circ(pen, cx, top):
    stroke(pen, [(cx - 110, top), (cx, top + 110)], 60, 50)
    stroke(pen, [(cx, top + 110), (cx + 110, top)], 50, 25)
def tilde(pen, cx, top):
    pts = [(cx - 140 + 280 * t / 20, top + 55 + 38 * math.sin(math.pi * 2 * t / 20)) for t in range(21)]
    stroke(pen, pts, 62, 52)
def diaer(pen, cx, top):
    for dx in (-65, 65):
        x, y = cx + dx, top + 45
        poly(pen, [(x - 38, y), (x, y - 38), (x + 38, y), (x, y + 38)])
def cedil(pen, cx, top):
    stroke(pen, [(cx, 20), (cx + 10, -50), (cx + 70, -95), (cx + 40, -165), (cx - 60, -175)], 60, 25)

MARKS = {'acute': acute, 'grave': grave, 'circ': circ, 'tilde': tilde, 'diaer': diaer, 'cedil': cedil}
ACCENTED = {
    'Á': ('A', 'acute'), 'À': ('A', 'grave'), 'Â': ('A', 'circ'), 'Ã': ('A', 'tilde'), 'Ä': ('A', 'diaer'),
    'É': ('E', 'acute'), 'È': ('E', 'grave'), 'Ê': ('E', 'circ'), 'Ë': ('E', 'diaer'),
    'Í': ('I', 'acute'), 'Ì': ('I', 'grave'), 'Î': ('I', 'circ'), 'Ï': ('I', 'diaer'),
    'Ó': ('O', 'acute'), 'Ò': ('O', 'grave'), 'Ô': ('O', 'circ'), 'Õ': ('O', 'tilde'), 'Ö': ('O', 'diaer'),
    'Ú': ('U', 'acute'), 'Ù': ('U', 'grave'), 'Û': ('U', 'circ'), 'Ü': ('U', 'diaer'),
    'Ç': ('C', 'cedil'), 'Ñ': ('N', 'tilde'),
}
glyph_of = {}
for ch, (base, mark) in ACCENTED.items():
    gname = 'uni%04X' % ord(ch)
    bp = BoundsPen(None); outlines[base].replay(bp)
    ymax = bp.bounds[3]
    # centro horizontal da parte de cima da letra (ignora traços laterais longos)
    tops = [pt for op, args in outlines[base].value for pt in args if pt[1] > ymax - 160]
    cx = sum(x for x, _ in tops) / len(tops)
    rec = RecordingPen(); outlines[base].replay(rec)
    MARKS[mark](rec, cx, max(CAP, ymax) + 55)
    outlines[gname] = rec
    metrics[gname] = metrics[base]
    glyph_of[ch] = gname

# --- monta a fonte ----------------------------------------------------------------
cmap = {32: 'space', 0xA0: 'space'}
for i in range(26):
    cmap[65 + i] = chr(65 + i)
    cmap[97 + i] = chr(65 + i)   # minúsculas usam o mesmo desenho
for ch, gname in glyph_of.items():
    cmap[ord(ch)] = gname
    cmap[ord(ch.lower())] = gname
for ch, gname in GNAME.items():
    cmap[ord(ch)] = gname
ALIASES = {'’': "'", '‘': "'", '´': "'", '“': '"', '”': '"', '–': '-', '—': '-', '‐': '-',
           '·': '.', '•': '.', '…': '.'}
for ch, target in ALIASES.items():
    cmap[ord(ch)] = GNAME[target]

charstrings = {}
for gname, rec in outlines.items():
    pen = T2CharStringPen(metrics[gname][0], None)
    rec.replay(pen)
    charstrings[gname] = pen.getCharString()
for gname, w in (('.notdef', 500), ('space', 320)):
    charstrings[gname] = T2CharStringPen(w, None).getCharString()
    metrics[gname] = (w, 0)

fb = FontBuilder(UPM, isTTF=False)
fb.setupGlyphOrder(['.notdef', 'space'] + sorted(n for n in outlines))
fb.setupCharacterMap(cmap)
fam = 'Spotify Disc Tag'
fb.setupCFF(fam.replace(' ', ''), {'FullName': fam}, charstrings, {})
fb.setupHorizontalMetrics(metrics)
fb.setupHorizontalHeader(ascent=1000, descent=-250)
fb.setupNameTable({'familyName': fam, 'styleName': 'Regular'})
fb.setupOS2(sTypoAscender=1000, sTypoDescender=-250, usWinAscent=1000, usWinDescent=300,
            sCapHeight=CAP, sxHeight=CAP)
fb.setupPost()
fb.save(OUT)
print('salvo', OUT, '-', len(charstrings), 'glifos')
