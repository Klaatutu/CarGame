# -*- coding: utf-8 -*-
"""
make_can_labels.py — atlas de texture 512×256 (look PS1) pour chaque canette, à partir des étiquettes
fournies dans assets/blender/textures/src/ (nosleep.jpg, cariboon.jpg, kombo.jpg).

Exécution : python assets/blender/make_can_labels.py   (Python système avec Pillow, pas Blender)
Sortie    : assets/blender/textures/can_label_<boisson>.png

Organisation de l'atlas (dépliage cylindrique fait par build_can.py) :
  u = tour de la canette (0..1, couture en +X), v = hauteur (0 = fond, 1 = couvercle) → HAUT de l'image = couvercle.
  L'étiquette est étirée sur la bande v0..v1 ; le reste (fond, col, couvercle, languette) est alu uni.
- nosleep / kombo : visuels d'étiquette complète sur fond blanc → recadrage automatique du contenu
  (leurs propres bandes alu/or incluses), logos déjà en face avant (u ≈ 0.75) et arrière (u ≈ 0.25).
- cariboon : image publicitaire pleine → on enlève le cadre jaune ; le logo (65 % du tour !) reste centré
  en u ≈ 0.5 et build_can.py décale les UV de cette boisson (u_off) pour l'amener en face avant.
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "textures", "src")
OUT = os.path.join(HERE, "textures")
W, H = 512, 256
ALU, ALU_DARK = (170, 172, 178), (108, 110, 116)

def row(v): return int(round((1.0 - v) * H))

def autocrop(im, thresh=225, inset=0.02):
    """Boîte englobante des pixels non blancs (fond blanc des visuels d'étiquette), rognée de `inset` × largeur
    de chaque côté pour que le reflet clair des bords du mock-up ne fasse pas une ligne à la couture."""
    g = im.convert("L").point(lambda v: 255 if v < thresh else 0)
    x0, y0, x1, y1 = g.getbbox(); dx = int((x1 - x0) * inset)
    return im.crop((x0 + dx, y0, x1 - dx, y1))

def strip_frame(im, margin=6):
    """Enlève le cadre jaune (lignes/colonnes de bord majoritairement jaunes) d'une image publicitaire."""
    px = im.load(); w, h = im.size
    def yellow(p): r, g, b = p; return r > 160 and g > 140 and b < 130 and r > b + 60
    def row_frac(y): return sum(yellow(px[x, y]) for x in range(0, w, 4)) / (w / 4)
    def col_frac(x): return sum(yellow(px[x, y]) for y in range(0, h, 4)) / (h / 4)
    # le cadre peut être une ligne à l'intérieur de l'image (bande de décor au-delà) : on coupe à la dernière
    # ligne/colonne jaune trouvée dans les 10 % extérieurs (pas plus loin : le logo est jaune lui aussi)
    top = [y for y in range(0, h // 10) if row_frac(y) > 0.25]
    bot = [y for y in range(9 * h // 10, h) if row_frac(y) > 0.25]
    lef = [x for x in range(0, w // 10) if col_frac(x) > 0.25]
    rig = [x for x in range(9 * w // 10, w) if col_frac(x) > 0.25]
    y0 = (max(top) + 1 if top else 0) + margin; y1 = (min(bot) if bot else h) - margin
    x0 = (max(lef) + 1 if lef else 0) + margin; x1 = (min(rig) if rig else w) - margin
    return im.crop((x0, y0, x1, y1))

def atlas(label, v0, v1, colors=32):
    """Étiquette étirée sur la bande v0..v1 de l'atlas, alu ailleurs, palette réduite."""
    img = Image.new("RGB", (W, H), ALU)
    r_top, r_bot = row(v1), row(v0)
    img.paste(label.resize((W, r_bot - r_top), Image.LANCZOS), (0, r_top))
    d = ImageDraw.Draw(img)
    d.line([(0, r_top - 1), (W, r_top - 1)], fill=ALU_DARK); d.line([(0, r_bot), (W, r_bot)], fill=ALU_DARK)
    return img.quantize(colors=colors, dither=Image.Dither.NONE).convert("RGB")

def load(name): return Image.open(os.path.join(SRC, name)).convert("RGB")

JOBS = {
    "nosleep":  (lambda: autocrop(load("nosleep.jpg")), 0.055, 0.865),
    "kombo":    (lambda: autocrop(load("kombo.jpg")), 0.055, 0.865),
    "cariboon": (lambda: strip_frame(load("cariboon.jpg")), 0.07, 0.85),
}

if __name__ == "__main__":
    for name, (fn, v0, v1) in JOBS.items():
        img = atlas(fn(), v0, v1)
        path = os.path.join(OUT, f"can_label_{name}.png"); img.save(path)
        print("écrit", path, img.size)
