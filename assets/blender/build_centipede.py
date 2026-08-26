# -*- coding: utf-8 -*-
"""
build_centipede.py — la scolopendre de Route de nuit, en géométrie organique.

Exécution :
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python assets/blender/build_centipede.py
Sorties : assets/models/centipede.glb, assets/blender/centipede.blend, assets/blender/renders/centipede_*.png

Repère Blender par anneau : X = droite, Y = avant, Z = haut. glTF Y-up → Godot (x, z, -y) :
l'avant = -Z en Godot, exactement le repère local que centipede.gd donne à chaque Seg
(Basis(right, up, -fwd)). Cotes en mm, reprises des constantes de scripts/centipede.gd.

Hiérarchie exportée (mêmes pivots que ce que _build_body() construisait en BoxMesh) :
  CPD_Seg00 (tête) … CPD_Seg14 — empties, posés par le jeu à chaque image
  ├─ CPD_Shell00 …             — la plaque (tergite) de l'anneau
  ├─ CPD_LegL00 / CPD_LegR00   — empties à (±w·0,45, 0, 0) ; le jeu pose rotation = (0, houle, ±droop)
  │  └─ CPD_LimbL00 …          — la patte entière (fémur arqué, tarse coudé, pointe), figée
  └─ (tête) CPD_AntL / CPD_AntR — empties, rotation posée par le jeu ; CPD_FeelerL/R dedans
     + CPD_Eye_L/R, CPD_Fang_L/R (forcipules)

Les rotations de pose (ondulation, antennes écartées) ne servent qu'aux rendus : le jeu
écrase transform des Seg et rotation des pivots à chaque image.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path: sys.path.insert(0, HERE)
from civic_lib import (get_col, clear_collection, bm_to_obj, mat, node_of, aim, link_obj,
                       camera, render_views, export_glb, save_blend, grid_box, ellipsoid,
                       empty, tube_along, bump)
from webley_lib import tri_count

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")
M = 0.001

# ---------------------------------------------------------------------------
# Cotes (mm) — mêmes valeurs que centipede.gd. BODY_T est MESURÉ (lames des
# aérateurs à 6,3 mm) : la bête doit rester plus plate que ça.
# ---------------------------------------------------------------------------
SEGMENTS = 15
SPACING = 19.0
BODY_W = 22.0
HEAD_W = 27.0
HEAD_L = 21.0
# La cage depasse l'anneau du jeu (0,84 x l'espacement) : la subdivision la
# retire d'environ 2 mm par bord, et c'est l'anneau APRES subdivision qui doit
# laisser 3 mm de jour a son voisin.
SEG_L = SPACING * 0.98
LEG_LEN = 28.0
LEG_THIGH = 0.62
KNEE = 0.42
DROOP = 0.10
ANT_LEN = 40.0
RIDE = 5.0
# Plaque : 3,3 mm de dôme au-dessus du plan des hanches, 2,3 dessous (le
# sternite est plus plat) — 5,6 mm en cage, moins après subdivision : passe les
# lames à 6,3.
T_TOP, T_BOT = 3.3, 2.3


def taper(i):
    return 1.0 - 0.55 * max(0.0, min(1.0, (i - (SEGMENTS - 4)) / 3.0))


def seg_width(i):
    return HEAD_W if i == 0 else BODY_W * taper(i)


def materials():
    shell = mat("CPD_Shell", (0.26, 0.115, 0.048), rough=0.32, metallic=0.22)
    limb = mat("CPD_Limb", (0.46, 0.26, 0.075), rough=0.48, metallic=0.05)
    eye = mat("CPD_Eye", (0.02, 0.02, 0.025), rough=0.12, metallic=0.30)
    fang = mat("CPD_Fang", (0.30, 0.14, 0.05), rough=0.35, metallic=0.15)
    return dict(shell=shell, limb=limb, eye=eye, fang=fang)


# ---------------------------------------------------------------------------
# Pièces
# ---------------------------------------------------------------------------
def tergite(name, w, l, mats, col, parent):
    """Plaque dorsale bombée : cage tout-quads + subdivision, pas une boîte.
    Dôme transversal marqué (la chitine est cintrée), arc longitudinal léger,
    ventre presque plat."""
    us = [-w / 2, -w * 0.30, 0.0, w * 0.30, w / 2]
    vs = [-l / 2, -l * 0.28, 0.0, l * 0.28, l / 2]
    dome = lambda u: 1.0 - (2.0 * u / w) ** 2 * 0.55
    arc = lambda v: 1.0 - (2.0 * v / l) ** 2 * 0.20
    keel = lambda u: 0.40 * bump(u, 0.0, w * 0.30)
    flat = lambda u: 1.0 - (2.0 * u / w) ** 2 * 0.35
    # Legerement trapezoidale : le bord AVANT (v = +l/2, +Y) est plus etroit,
    # comme s'il glissait sous la plaque precedente.
    narrow = lambda v: 1.0 - 0.09 * (v / l + 0.5)
    return grid_box(name, us, vs,
                    lambda u, v: T_TOP * dome(u) * arc(v) + keel(u),
                    lambda u, v: -T_BOT * flat(u),
                    mats["shell"], col, subsurf=2,
                    to_world=lambda u, v, z: (u * narrow(v) * M, v * M, z * M),
                    parent=parent)


def limb(name, s, scale, mats, col, parent, ultimate=False):
    """Une patte entière, un seul tube effilé : fémur arqué vers le haut, genou,
    tarse plongeant à KNEE, pointe en griffe. Les dernières (ultimate=True)
    traînent vers l'arrière, plus longues et plus fines — c'est la signature de
    la scolopendre vue de dos."""
    ck, sk = math.cos(KNEE), math.sin(KNEE)
    if ultimate:
        L = LEG_LEN * scale * 1.7
        a = 0.95                                # rabattues vers l'arrière
        dx, dy = math.cos(a), -math.sin(a)
        th = L * LEG_THIGH
        ta = L * (1.0 - LEG_THIGH)
        pts = [(0.0, 0.0, 0.0),
               (s * dx * th * 0.5, dy * th * 0.5, 1.2 * scale),
               (s * dx * th, dy * th, 0.3),
               (s * dx * (th + ta * 0.5 * ck), dy * (th + ta * 0.5 * ck), 0.3 - ta * 0.5 * sk * 0.6),
               (s * dx * (th + ta * ck), dy * (th + ta * ck), 0.3 - ta * sk * 0.6)]
        radii = [0.90, 0.80, 0.72, 0.48, 0.18]
    else:
        th = LEG_LEN * scale * LEG_THIGH
        ta = LEG_LEN * scale * (1.0 - LEG_THIGH)
        pts = [(0.0, 0.0, 0.0),
               (s * th * 0.38, 0.0, 0.95 * scale),
               (s * th * 0.78, 0.0, 1.00 * scale),
               (s * th, 0.0, 0.25),
               (s * (th + ta * 0.5 * ck), 0.0, 0.25 - ta * 0.5 * sk),
               (s * (th + ta * ck), 0.0, 0.30 - ta * sk)]
        radii = [1.05, 0.98, 0.85, 0.90, 0.55, 0.22]
    pts = [(x * M, y * M, z * M) for (x, y, z) in pts]
    radii = [r * scale * M for r in radii]
    return tube_along(name, pts, radii, mats["limb"], col, n=8, subsurf=1,
                      parent=parent, cap_scale=0.7)


def feeler(name, side, mats, col, parent):
    """Antenne : fouet effilé PORTÉ AU-DESSUS du plan de la tête et courbé vers
    l'extérieur — à plat il se confondait avec les pattes, ce qui s'est vu au
    premier rendu."""
    pts = [(0, 0, 0), (side * 0.3, 8, 1.6), (side * 1.0, 16, 2.8),
           (side * 2.0, 24, 3.2), (side * 3.2, 32, 2.6), (side * 4.6, ANT_LEN, 1.6)]
    radii = [0.85, 0.75, 0.62, 0.50, 0.35, 0.15]
    pts = [(x * M, y * M, z * M) for (x, y, z) in pts]
    radii = [r * M for r in radii]
    return tube_along(name, pts, radii, mats["limb"], col, n=8, subsurf=1,
                      parent=parent, cap_scale=0.7)


def head_extras(mats, col, seg):
    """Yeux et forcipules — les deux détails qui font lire « tête » et pas
    « premier anneau »."""
    for s, tag in ((-1.0, "L"), (1.0, "R")):
        eye = ellipsoid("CPD_Eye_%s" % tag, (1.4 * M, 1.7 * M, 1.2 * M),
                        (s * 7.4 * M, 6.2 * M, 2.1 * M), mats["eye"], col,
                        parent=seg, u=12, v=8)
        eye.name = "CPD_Eye_%s" % tag
        pts = [(s * 6.0, 4.5, -2.0), (s * 6.8, 8.6, -2.6),
               (s * 4.6, 11.4, -2.6), (s * 2.2, 12.4, -2.0)]
        radii = [1.1, 0.95, 0.55, 0.20]
        tube_along("CPD_Fang_%s" % tag, [(x * M, y * M, z * M) for (x, y, z) in pts],
                   [r * M for r in radii], mats["fang"], col, n=8, subsurf=1,
                   parent=seg, cap_scale=0.7)


# ---------------------------------------------------------------------------
# Assemblage
# ---------------------------------------------------------------------------
def build():
    mats = materials()
    col = get_col("Centipede")
    segs, leg_pivots, ant_pivots = [], [], []

    for i in range(SEGMENTS):
        seg = empty("CPD_Seg%02d" % i, (0, 0, 0), col, size=0.02)
        segs.append(seg)
        w = seg_width(i)
        if i == 0:
            head = ellipsoid("CPD_Shell00", (11.2 * M, 10.4 * M, 3.8 * M),
                             (0, 0.8 * M, 0.8 * M), mats["shell"], col, parent=seg, u=20, v=12)
            head.name = "CPD_Shell00"
            head_extras(mats, col, seg)
            for s, tag in ((-1.0, "L"), (1.0, "R")):
                ant = empty("CPD_Ant%s" % tag, (s * HEAD_W * 0.3 * M, HEAD_L * 0.5 * M, 2.0 * M),
                            col, parent=seg, size=0.01)
                feeler("CPD_Feeler%s" % tag, s, mats, col, ant)
                ant_pivots.append(ant)
        else:
            tergite("CPD_Shell%02d" % i, w, SEG_L, mats, col, seg)

        # Échelle des pattes : discrètes sous la tête (maxillipèdes), pleines au
        # milieu, suivant l'effilement en queue ; la dernière paire traîne.
        ult = i == SEGMENTS - 1
        scale = 0.8 if i == 0 else (taper(i) ** 0.6 if not ult else 0.75)
        pair = []
        for s, tag in ((-1.0, "L"), (1.0, "R")):
            piv = empty("CPD_Leg%s%02d" % (tag, i), (s * w * 0.45 * M, 0, 0), col,
                        parent=seg, size=0.008)
            limb("CPD_Limb%s%02d" % (tag, i), s, scale, mats, col, piv, ultimate=ult)
            pair.append(piv)
        leg_pivots.append(pair)

    return dict(segs=segs, legs=leg_pivots, ants=ant_pivots)


# ---------------------------------------------------------------------------
# Pose de rendu — purement cosmétique, le jeu écrase tout
# ---------------------------------------------------------------------------
def pose(objs):
    p = Vector((0.0, 0.0, 0.0))
    for i, seg in enumerate(objs["segs"]):
        th = 0.28 * math.sin(i * 0.55 + 0.7)
        if i > 0:
            p = p - Vector((-math.sin(th), math.cos(th), 0.0)) * (SPACING * M)
        seg.location = p
        seg.rotation_euler = (0, 0, th)
        ph = -i * 0.85
        legL, legR = objs["legs"][i]
        legL.rotation_euler = (0, -DROOP, math.sin(ph) * 0.55)
        legR.rotation_euler = (0, DROOP, math.sin(ph + math.pi) * 0.55)
    objs["ants"][0].rotation_euler = (0.10, 0, 0.45)
    objs["ants"][1].rotation_euler = (-0.05, 0, -0.45)
    bpy.context.view_layer.update()


def unpose(objs):
    for i, seg in enumerate(objs["segs"]):
        seg.location = (0, -i * SPACING * M, 0)
        seg.rotation_euler = (0, 0, 0)
        for piv in objs["legs"][i]:
            piv.rotation_euler = (0, 0, 0)
    for ant in objs["ants"]:
        ant.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()


# ---------------------------------------------------------------------------
def setup_scene():
    scene = bpy.context.scene
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(bpy.data.collections): clear_collection(c.name)
    env = get_col("ENV_Centipede")
    w = scene.world or bpy.data.worlds.new("World"); scene.world = w; w.use_nodes = True
    bg = node_of(w.node_tree, 'ShaderNodeBackground')
    bg.inputs['Color'].default_value = (0.20, 0.21, 0.24, 1.0); bg.inputs['Strength'].default_value = 0.12
    scene.view_settings.view_transform = 'Standard'
    # Sol au ras du ventre : les hanches sont à RIDE au-dessus de la surface.
    bm = bmesh.new(); s = 0.6
    bm.faces.new([bm.verts.new(p) for p in ((-s, -s, -RIDE * M), (s, -s, -RIDE * M),
                                            (s, s, -RIDE * M), (-s, s, -RIDE * M))])
    bm_to_obj(bm, "ENV_Floor", mat("ENV_Floor", (0.07, 0.07, 0.08), rough=0.90), env)
    tgt = (0.0, -0.12, 0.0)
    for name, energy, size, color, loc in (("ENV_Key", 2.4, 0.45, (1.0, 0.93, 0.84), (-0.30, -0.02, 0.40)),
                                           ("ENV_Fill", 0.9, 0.8, (0.80, 0.88, 1.0), (0.40, -0.30, 0.22)),
                                           ("ENV_Rim", 1.4, 0.4, (1.0, 1.0, 1.0), (0.10, 0.35, 0.28))):
        l = bpy.data.lights.new(name, 'AREA'); l.energy = energy; l.size = size; l.color = color
        ob = bpy.data.objects.new(name, l); link_obj(ob, env); ob.location = loc; aim(ob, tgt)
    camera("CAM_34", (-0.26, 0.14, 0.18), (0.0, -0.10, 0.0), 55, env, clip_start=0.005)
    camera("CAM_Side", (0.30, -0.12, 0.035), (0.0, -0.12, 0.0), 65, env, clip_start=0.005)
    camera("CAM_Top", (0.02, -0.125, 0.40), (0.0, -0.13, 0.0), 55, env, clip_start=0.005)
    camera("CAM_Head", (-0.085, 0.085, 0.055), (0.0, -0.005, 0.0), 80, env, clip_start=0.005)
    scene.render.resolution_x, scene.render.resolution_y = 1400, 800
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    return env


def main(export=True, render=True, save=True):
    setup_scene()
    objs = build()
    dg = bpy.context.evaluated_depsgraph_get()
    total = sum(tri_count(o.evaluated_get(dg))
                for o in bpy.data.collections["Centipede"].all_objects if o.type == 'MESH')
    print("Centipede : %d objets, %d tris (modificateurs appliques)"
          % (len(bpy.data.collections["Centipede"].all_objects), total))
    out = os.path.join(HERE, "renders")
    if render:
        pose(objs)
        render_views([("CAM_34", "centipede_34.png", []),
                      ("CAM_Side", "centipede_side.png", []),
                      ("CAM_Top", "centipede_top.png", []),
                      ("CAM_Head", "centipede_head.png", [])], out)
    unpose(objs)
    if export:
        os.makedirs(MODELS, exist_ok=True)
        n, mb = export_glb("Centipede", os.path.join(MODELS, "centipede.glb"))
        print("export centipede.glb : %d objet(s), %s Mo" % (n, mb))
    if save: save_blend(os.path.join(HERE, "centipede.blend"))


if __name__ == "__main__":
    main()
