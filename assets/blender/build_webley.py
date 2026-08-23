# -*- coding: utf-8 -*-
"""
build_webley.py — revolver Webley Mk VI (.455) à bascule pour Route de nuit.

Exécution :
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python assets/blender/build_webley.py
Sorties : assets/models/webley.glb, assets/blender/webley.blend, assets/blender/renders/webley_*.png

Repère Blender : Y = avant (bouche du canon), Z = haut, X = droite du tireur ; axe du barillet = axe Y (x = z = 0),
cotes en mm dans les constantes. glTF Y-up → Godot (x, z, -y) : le canon pointe vers -Z en Godot.

Hiérarchie exportée (chaque pièce mobile a son origine sur son axe) :
  WBL_Frame (carcasse, racine)
  ├─ WBL_Grip_L / WBL_Grip_R, WBL_TriggerGuard, WBL_Lanyard*, WBL_Screw_*   (fixes)
  ├─ WBL_Hammer   pivot = axe du chien       → armer   : rotation locale X positive (≈ +35°)
  ├─ WBL_Trigger  pivot = axe de la détente  → presser : rotation locale X négative (≈ -12°)
  ├─ WBL_Latch    pivot = axe du verrou      → ouvrir  : rotation locale X positive (≈ +25°)
  └─ WBL_BarrelPivot (empty sur l'axe de charnière)   → basculer : rotation locale X NÉGATIVE (0 → -60°)
     ├─ WBL_Barrel, WBL_Rib, WBL_FrontSight, WBL_TopStrap, WBL_BreechBlock, WBL_Cheek_L/R  (bloc canon)
     └─ WBL_Cylinder (origine sur l'axe, au centre)     → tourner : rotation locale autour de l'axe (Z en Godot)
        └─ WBL_Extractor (origine = face arrière du barillet) → éjecter : translation locale Z en Godot (−Y Blender), 0 → 18 mm
           └─ WBL_Cart_1 … WBL_Cart_6 (cartouches, à masquer une par une pour les chambres vides)
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path: sys.path.insert(0, HERE)
from civic_lib import (get_col, clear_collection, bm_to_obj, shade, mat, node_of, aim, link_obj, camera, render_views,
                       export_glb, save_blend, grid_box, torus, empty, add_boolean_collection, smoothstep)
from webley_lib import (M, extrude_yz, revolve_y, sweep, rounded_rect, cyl_y, attach, tri_count)

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")

# ---------------------------------------------------------------------------
# Cotes (mm) — Webley Mk VI : canon 6", barillet 6 coups, longueur totale ≈ 286 mm
# ---------------------------------------------------------------------------
CYL_R, CYL_Y0, CYL_Y1 = 21.0, -19.0, 19.0      # barillet : rayon, face arrière, face avant
CH_R, CH_PITCH, N_CH = 6.2, 13.5, 6            # chambres : rayon, rayon d'implantation, nombre
CH_ANG = [math.pi / 2 + k * 2 * math.pi / N_CH for k in range(N_CH)]   # chambre 1 en haut (sous le canon)
BORE_Z = CH_PITCH                               # axe du canon = chambre du haut
HINGE = Vector((0.0, 24.0, -29.0))              # axe de charnière (bloc canon)
HAMMER_PIN = Vector((0.0, -40.0, -4.0))
TRIGGER_PIN = Vector((0.0, -10.0, -28.0))
LATCH_PIN = Vector((0.0, -31.0, 19.0))
FW = 13.0                                       # demi-largeur de la carcasse (26 mm)
MUZZLE_Y = 172.0
EXTRACT_MAX = 18.0                              # course d'éjection (mm)

# ---------------------------------------------------------------------------
def materials():
    blued = mat("WBL_Blued", (0.05, 0.055, 0.07), rough=0.45, metallic=0.70)
    steel = mat("WBL_Steel", (0.22, 0.22, 0.23), rough=0.40, metallic=0.80)
    grip = mat("WBL_Grip", (0.18, 0.09, 0.045), rough=0.60)
    brass = mat("WBL_Brass", (0.80, 0.58, 0.25), rough=0.35, metallic=0.90)
    lead = mat("WBL_Lead", (0.55, 0.55, 0.57), rough=0.55, metallic=0.50)
    primer = mat("WBL_Primer", (0.78, 0.72, 0.58), rough=0.35, metallic=0.90)
    return dict(blued=blued, steel=steel, grip=grip, brass=brass, lead=lead, primer=primer)


def cutter_box(name, col, x, y, z, parent=None):
    """Boîte de découpe (x, y, z = (min, max) en mm)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(((x[0] if v.co.x < 0 else x[1]), (y[0] if v.co.y < 0 else y[1]), (z[0] if v.co.z < 0 else z[1]))) * M
    ob = bm_to_obj(bm, name, None, col)
    if parent is not None: attach(ob, parent)
    ob.hide_render = True; ob.display_type = 'WIRE'
    return ob


def hide_all_cutters():
    for c in bpy.data.collections:
        if c.name.startswith("CUT_"):
            for o in c.objects: o.hide_set(True); o.hide_render = True


# ---------------------------------------------------------------------------
# Carcasse et pièces fixes
# ---------------------------------------------------------------------------
def build_frame(mt, col):
    T = True
    prof = [(-20.5, 18, T), (-20.5, -21, T), (-14, -23), (14, -23, T), (14, -36, T), (-20, -36), (-30, -37),
            (-33, -38), (-37, -50), (-44, -72), (-50, -90), (-52, -97), (-54, -100), (-62, -101), (-84, -101),
            (-89, -99), (-90, -95), (-88, -84), (-80, -58), (-70, -34), (-62, -16), (-58, -6), (-54, 2), (-48, 8),
            (-42, 12), (-36, 16),
            (-35, 20), (-30, 22), (-27, 20), (-27, 18, T), (-24, 18)]
    frame = extrude_yz("WBL_Frame", prof, -FW, FW, mt["blued"], col, bevel=2.0)
    # nez de carcasse (articulation) plus étroit, entre les joues du bloc canon
    knuckle = [(10, -23, T), (20, -22), (24, -21), (30, -24), (32, -29), (30, -34), (24, -37), (17, -37), (10, -36, T)]
    extrude_yz("WBL_Knuckle", knuckle, -6.5, 6.5, mt["blued"], col, bevel=1.2, parent=frame)
    # découpes : logement du chien, canal du percuteur, fente de la détente
    cuts = get_col("CUT_Frame")
    cutter_box("CUT_HammerSlot", cuts, (-4.5, 4.5), (-52, -31), (0, 40))
    cutter_box("CUT_NoseChannel", cuts, (-2.5, 2.5), (-36, -19), (8, 17.5))
    cutter_box("CUT_TriggerSlot", cuts, (-3.3, 3.3), (-18, -2), (-40, -20))
    add_boolean_collection(frame, cuts, "Cuts")
    # pontet : bande 8 × 3.5 mm balayée sous la carcasse
    path = [(0, 10, -35), (0, 8, -43), (0, 3, -50), (0, -6, -55), (0, -16, -57), (0, -26, -55), (0, -32, -49),
            (0, -35, -42), (0, -35, -37)]
    sweep("WBL_TriggerGuard", path, rounded_rect(8.0, 3.5, 1.2), mt["blued"], col, subsurf=1, parent=frame)
    # plaquettes de crosse (bombées)
    corners = dict(tf=(-36, -42), tb=(-58, -10), bb=(-86, -95), bf=(-53, -95))   # haut-avant, haut-arrière, bas-arrière, bas-avant
    def yz(u, v):
        f = Vector(corners["tf"]).lerp(Vector(corners["bf"]), u)
        b = Vector(corners["tb"]).lerp(Vector(corners["bb"]), u)
        p = f.lerp(b, v)
        p.y -= 3.0 * math.sin(math.pi * u) * (1 - v)        # sangle avant légèrement creuse
        return p
    def dome(u, v):
        return FW + 0.5 + 6.0 * (math.sin(math.pi * v) ** 0.5) * (min(1.0, 4 * u * (1 - u)) ** 0.3)
    us = [i / 10 for i in range(11)]; vs = [j / 8 for j in range(9)]
    for side, name in ((1, "WBL_Grip_R"), (-1, "WBL_Grip_L")):
        g = grid_box(name, us, vs, dome, FW - 1.5, mt["grip"], col, subsurf=1,
                     to_world=lambda u, v, w, s=side: (s * w * M, yz(u, v).x * M, yz(u, v).y * M))
        attach(g, frame)
        # vis de plaquette
        s = cyl_y("WBL_Screw_Grip" + ("R" if side > 0 else "L"), 3.0, -0.8, 0.8, (0, 0, 0), mt["steel"], col, steps=16)
        c = yz(0.5, 0.5); s.location = Vector((side * (FW + 6.2), c.x, c.y)) * M
        s.rotation_euler = (0, 0, math.radians(90)); attach(s, frame)
    # anneau de dragonne
    stud = cyl_y("WBL_LanyardStud", 2.5, -1, 6, (0, -71, -106), mt["steel"], col, steps=12)
    stud.rotation_euler = (math.radians(90), 0, 0); attach(stud, frame)
    ring = torus("WBL_LanyardRing", 6.5 * M, 1.3 * M, Vector((0, -71, -110)) * M, mt["steel"], col, rot=(0, 90, 0), maj=32, minr=10)
    attach(ring, frame)
    # têtes d'axes (chien, détente, charnière côté gauche)
    for nm, p, side, r in (("WBL_Screw_Hammer", HAMMER_PIN, 1, 3.0), ("WBL_Screw_HammerL", HAMMER_PIN, -1, 3.0),
                           ("WBL_Screw_Trigger", TRIGGER_PIN, 1, 2.5), ("WBL_Screw_TriggerL", TRIGGER_PIN, -1, 2.5)):
        s = cyl_y(nm, r, -0.6, 0.6, (0, 0, 0), mt["steel"], col, steps=16)
        s.location = Vector((side * FW, p.y, p.z)) * M; s.rotation_euler = (0, 0, math.radians(90)); attach(s, frame)
    return frame


def build_hammer(mt, col, frame):
    # corps (8 mm, dans le logement) ; le nez + percuteur (4 mm) passe dans le canal de la culasse
    prof = [(-38, -11), (-35, -4), (-34, 6), (-34, 16), (-38, 17), (-44, 22), (-50, 26),
            (-54, 26), (-55, 23), (-51, 20), (-46, 15), (-45, 8), (-45, -4), (-44, -10), (-40, -12)]
    h = extrude_yz("WBL_Hammer", prof, -4.0, 4.0, mt["steel"], col, origin=HAMMER_PIN, bevel=0.8, segs=2)
    attach(h, frame)
    nose = [(-36, 9, True), (-28, 10), (-24, 12.3), (-19.5, 12.8), (-19.5, 14.2), (-24, 15), (-28, 17), (-36, 17.2, True)]
    attach(extrude_yz("WBL_Hammer_Nose", nose, -2.0, 2.0, mt["steel"], col, origin=HAMMER_PIN, bevel=0.4, segs=1, iters=1), h)
    return h


def build_trigger(mt, col, frame):
    prof = [(-5, -24, True), (-5, -33), (-8, -41), (-12, -49), (-15.5, -53), (-18, -52), (-17.5, -48), (-14.5, -42),
            (-13, -36), (-14, -30), (-15, -24, True)]
    t = extrude_yz("WBL_Trigger", prof, -3.0, 3.0, mt["steel"], col, origin=TRIGGER_PIN, bevel=0.8, segs=2)
    attach(t, frame)
    return t


def build_latch(mt, col, frame):
    """Verrou en étrier : deux bras de part et d'autre de l'arceau, traverse au-dessus, levier de pouce à gauche."""
    T = True
    arm = [(-37, 14), (-36, 22), (-31, 27), (-23, 31), (-19, 30), (-19.5, 27), (-24, 25), (-27, 20), (-27, 12, T), (-35, 11, T)]
    parts = []
    for side, nm in ((1, "WBL_Latch"), (-1, "WBL_Latch_ArmL")):
        parts.append(extrude_yz(nm, arm, side * 6.8, side * 10.8, mt["steel"], col, origin=LATCH_PIN, bevel=0.8, segs=2))
    latch = parts[0]
    attach(latch, frame); attach(parts[1], latch)
    bar = extrude_yz("WBL_Latch_Bar", [(-26, 27), (-23, 31), (-19, 30), (-19.5, 27)], -10.8, 10.8, mt["steel"], col,
                     origin=LATCH_PIN, bevel=0.8, segs=2, iters=1)
    attach(bar, latch)
    lever = [(-37, 14), (-42, 13), (-50, 12.5), (-55, 14), (-56, 17), (-53, 18.5), (-46, 18), (-40, 19.5), (-36, 22)]
    lv = extrude_yz("WBL_Latch_Lever", lever, -10.8, -7.0, mt["steel"], col, origin=LATCH_PIN, bevel=0.6, segs=2)
    attach(lv, latch)
    return latch


# ---------------------------------------------------------------------------
# Bloc canon (bascule autour de HINGE)
# ---------------------------------------------------------------------------
def build_barrel_group(mt, col, frame):
    pivot = empty("WBL_BarrelPivot", HINGE * M, col, size=0.02)
    attach(pivot, frame)
    T = True
    # canon : révolution autour de Y, alésage visible à la bouche
    prof = [(0, 165), (5.8, 165), (5.8, 172), (7.6, 172), (8.6, 171.0), (8.6, 120), (9.2, 80), (9.8, 40), (10.6, 32),
            (11.5, 29), (11.5, 28), (0, 28)]
    barrel = revolve_y("WBL_Barrel", prof, mt["blued"], col, steps=32, loc=(0, 0, BORE_Z), angle=45)
    attach(barrel, pivot)
    # bande supérieure du canon (rib) et guidon
    rib = grid_box("WBL_Rib", [170 - 4 * i for i in range(37)], [-3.5 + 7 * j / 4 for j in range(5)],
                   lambda u, v: 25.0 - 0.3 * (v / 3.5) ** 2, 18.0, mt["blued"], col, subsurf=1,
                   to_world=lambda u, v, w: (v * M, u * M, w * M))
    attach(rib, pivot)
    sight = extrude_yz("WBL_FrontSight", [(158, 24), (160, 31), (163, 32), (166, 31.5), (167, 24)], -1.1, 1.1,
                       mt["blued"], col, bevel=0.3, segs=1, iters=1)
    attach(sight, pivot)
    # bloc de culasse avant (devant le barillet) et joues de charnière
    block = [(19.8, 27, T), (19.8, -20, T), (27, -20), (30, -14), (31, 0), (31, 10), (30, 18), (28, 24), (25, 27)]
    attach(extrude_yz("WBL_BreechBlock", block, -FW, FW, mt["blued"], col, bevel=3.0, iters=3), pivot)
    cheek = [(14.5, -14, T), (14.5, -20), (16, -24), (14, -30), (16, -35), (21, -38), (27, -38), (32, -34),
             (33.5, -28), (31, -22), (28, -18), (26, -14)]
    for side, nm in ((1, "WBL_Cheek_R"), (-1, "WBL_Cheek_L")):
        attach(extrude_yz(nm, cheek, side * 7.0, side * FW, mt["blued"], col, bevel=2.0), pivot)
    hs = cyl_y("WBL_Screw_Hinge", 4.0, -0.8, 0.8, (0, 0, 0), mt["steel"], col, steps=16)
    hs.location = Vector((-FW, HINGE.y, HINGE.z)) * M; hs.rotation_euler = (0, 0, math.radians(90)); attach(hs, pivot)
    # bande supérieure au-dessus du barillet + arceau arrière (cran de mire) saisi par le verrou
    def top(u, v):
        bow = smoothstep(-19, -23, u)
        notch = 2.5 * max(0.0, 1 - (v / 1.8) ** 2) * smoothstep(-23, -25, u)
        return 26.5 - 0.4 * (v / 6.5) ** 2 + 1.8 * bow - notch
    def bot(u, v):
        return 21.8 - 3.8 * smoothstep(-19, -22, u)
    strap = grid_box("WBL_TopStrap", [26 - 2 * i for i in range(28)], [-6.5 + 13 * j / 6 for j in range(7)],
                     top, bot, mt["blued"], col, subsurf=1, to_world=lambda u, v, w: (v * M, u * M, w * M))
    attach(strap, pivot)
    return pivot


# ---------------------------------------------------------------------------
# Barillet, étoile d'extraction, cartouches
# ---------------------------------------------------------------------------
def flute_fn(th, r, t):
    """Six cannelures entre les chambres, profondeur 2.2 mm, fondues aux deux bouts."""
    if r < CYL_R - 1e-6: return r
    depth = 2.2 * smoothstep(-10, -6, t) * smoothstep(17, 13, t)
    best = 0.0
    for k in range(N_CH):
        a = CH_ANG[k] + math.pi / N_CH
        d = (th - a + math.pi) % (2 * math.pi) - math.pi
        w = math.radians(17)
        if abs(d) < w: best = max(best, math.cos(math.pi * d / (2 * w)) ** 2)
    return r - depth * best


def build_cylinder(mt, col, pivot):
    prof = [(0, CYL_Y0), (19.5, CYL_Y0), (CYL_R, CYL_Y0 + 1.5)] + [(CYL_R, t) for t in range(-16, 18, 1)] + \
           [(CYL_R, CYL_Y1 - 1.5), (19.5, CYL_Y1), (0, CYL_Y1)]
    cyl = revolve_y("WBL_Cylinder", prof, mt["blued"], col, steps=72, rfn=flute_fn, angle=50)
    attach(cyl, pivot)
    cuts = get_col("CUT_Cylinder")
    for k, a in enumerate(CH_ANG):
        c = cyl_y(f"CUT_Chamber_{k+1}", CH_R, CYL_Y0 - 3, CYL_Y1 + 3, (CH_PITCH * math.cos(a), 0, CH_PITCH * math.sin(a)), None, cuts, steps=24)
        attach(c, cyl)
        # cran d'arrêt du barillet (rectangle peu profond à l'arrière, entre les cannelures)
        n = cutter_box(f"CUT_Stop_{k+1}", cuts, (-1.8, 1.8), (-14, -7), (CYL_R - 1.5, CYL_R + 2))
        n.rotation_euler = (0, a - math.pi / 2, 0); attach(n, cyl)
    attach(cyl_y("CUT_Bore", 4.0, CYL_Y0 - 3, CYL_Y1 + 3, (0, 0, 0), None, cuts, steps=20), cyl)
    attach(cyl_y("CUT_StarRecess", 14.8, CYL_Y0 - 3, CYL_Y0 + 2.6, (0, 0, 0), None, cuts, steps=48), cyl)
    add_boolean_collection(cyl, cuts, "Cuts")
    return cyl


def build_extractor(mt, col, cyl):
    """Étoile : disque évidé par les six chambres, tige dans l'alésage central, rochet à l'arrière. Origine = face arrière."""
    star = revolve_y("WBL_Extractor", [(0, 0), (14.5, 0), (14.5, 2.5), (3.8, 2.5), (3.8, CYL_L - 2), (0, CYL_L - 2)],
                     mt["steel"], col, steps=48, loc=(0, CYL_Y0, 0), angle=60)
    attach(star, cyl)
    cuts = get_col("CUT_Star")
    for k, a in enumerate(CH_ANG):
        attach(cyl_y(f"CUT_StarChamber_{k+1}", CH_R, -3, 6, (CH_PITCH * math.cos(a), CYL_Y0, CH_PITCH * math.sin(a)), None, cuts, steps=24), star)
    add_boolean_collection(star, cuts, "Cuts")
    ratchet = revolve_y("WBL_Ratchet", [(0, -1.2), (4.5, -1.2), (5.5, -0.5), (5.5, 0), (0, 0)], mt["steel"], col, steps=6,
                        loc=(0, CYL_Y0, 0), angle=30)
    attach(ratchet, star)
    return star


CYL_L = CYL_Y1 - CYL_Y0


def build_cartridges(mt, col, star):
    """Cartouche .455 Webley : culot à bourrelet, étui laiton 19.3 mm, balle plomb à nez rond. Origine = face du culot."""
    prof = [(0, 0.25), (2.8, 0.25), (2.8, 0), (6.75, 0), (6.75, 1.0), (6.1, 1.5), (6.1, 19.3), (5.85, 19.3), (5.75, 19.6),
            (5.75, 26.0), (5.5, 28.0), (4.6, 30.5), (3.0, 32.2), (0, 33.0)]
    def mat_fn(r, t):
        if t <= 0.3 and r < 2.9: return 2
        return 1 if t > 19.4 else 0
    carts = []
    for k, a in enumerate(CH_ANG):
        c = revolve_y(f"WBL_Cart_{k+1}", prof, [mt["brass"], mt["lead"], mt["primer"]], col, steps=24,
                      loc=(CH_PITCH * math.cos(a), CYL_Y0 - 1.0, CH_PITCH * math.sin(a)), mat_fn=mat_fn, angle=60)
        attach(c, star); carts.append(c)
    return carts


# ---------------------------------------------------------------------------
# Poses (rendu de contrôle) — les mêmes manipulations que fera le jeu
# ---------------------------------------------------------------------------
def pose(objs, open_deg=0.0, extract=0.0, hammer_deg=0.0, latch_deg=0.0, cyl_deg=0.0):
    objs["pivot"].rotation_euler = (math.radians(-open_deg), 0, 0)
    objs["star"].location = Vector((0, CYL_Y0 - extract, 0)) * M
    objs["hammer"].rotation_euler = (math.radians(hammer_deg), 0, 0)
    objs["latch"].rotation_euler = (math.radians(latch_deg), 0, 0)
    objs["cyl"].rotation_euler = (0, math.radians(cyl_deg), 0)
    bpy.context.view_layer.update()


def setup_scene():
    scene = bpy.context.scene
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(bpy.data.collections): clear_collection(c.name)
    env = get_col("ENV_Webley")
    w = scene.world or bpy.data.worlds.new("World"); scene.world = w; w.use_nodes = True
    bg = node_of(w.node_tree, 'ShaderNodeBackground')
    bg.inputs['Color'].default_value = (0.30, 0.31, 0.35, 1.0); bg.inputs['Strength'].default_value = 0.30
    scene.view_settings.view_transform = 'Standard'
    bm = bmesh.new(); s = 1.0
    bm.faces.new([bm.verts.new(p) for p in ((-s, -s, -0.12), (s, -s, -0.12), (s, s, -0.12), (-s, s, -0.12))])
    bm_to_obj(bm, "ENV_Floor", mat("ENV_Floor", (0.12, 0.12, 0.13), rough=0.85), env)
    tgt = (0.0, 0.03, -0.02)
    for name, energy, size, color, loc in (("ENV_Key", 28.0, 0.6, (1.0, 0.94, 0.86), (-0.55, -0.35, 0.70)),
                                           ("ENV_Fill", 10.0, 1.0, (0.80, 0.88, 1.0), (0.70, -0.30, 0.35)),
                                           ("ENV_Rim", 18.0, 0.5, (1.0, 1.0, 1.0), (0.20, 0.80, 0.50))):
        l = bpy.data.lights.new(name, 'AREA'); l.energy = energy; l.size = size; l.color = color
        ob = bpy.data.objects.new(name, l); link_obj(ob, env); ob.location = loc; aim(ob, tgt)
    camera("CAM_Closed", (-0.34, -0.24, 0.20), (0.0, 0.04, -0.03), 50, env)
    camera("CAM_Side", (0.62, 0.04, 0.02), (0.0, 0.04, -0.03), 60, env)
    camera("CAM_Open", (-0.22, -0.26, 0.24), (0.0, 0.00, -0.03), 48, env)
    camera("CAM_Rear", (-0.10, -0.36, 0.16), (0.0, -0.01, -0.01), 55, env)
    scene.render.resolution_x, scene.render.resolution_y = 1400, 800
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    return env


def build():
    mt = materials()
    col = get_col("Webley")
    frame = build_frame(mt, col)
    hammer = build_hammer(mt, col, frame)
    trigger = build_trigger(mt, col, frame)
    latch = build_latch(mt, col, frame)
    pivot = build_barrel_group(mt, col, frame)
    cyl = build_cylinder(mt, col, pivot)
    star = build_extractor(mt, col, cyl)
    carts = build_cartridges(mt, col, star)
    hide_all_cutters()
    return dict(frame=frame, hammer=hammer, trigger=trigger, latch=latch, pivot=pivot, cyl=cyl, star=star, carts=carts)


def main(export=True, render=True, save=True):
    setup_scene()
    objs = build()
    dg = bpy.context.evaluated_depsgraph_get()
    total = sum(tri_count(o.evaluated_get(dg)) for o in bpy.data.collections["Webley"].all_objects if o.type == 'MESH')
    print(f"Webley : {len(bpy.data.collections['Webley'].all_objects)} objets, {total} tris (modificateurs appliqués)")
    out = os.path.join(HERE, "renders")
    if render:
        pose(objs)
        render_views([("CAM_Closed", "webley_closed.png", []), ("CAM_Side", "webley_side.png", [])], out)
        pose(objs, open_deg=60, extract=14, hammer_deg=0, latch_deg=25)
        render_views([("CAM_Open", "webley_open.png", []), ("CAM_Rear", "webley_open_rear.png", [])], out)
        pose(objs)
    if export:
        os.makedirs(MODELS, exist_ok=True)
        n, mb = export_glb("Webley", os.path.join(MODELS, "webley.glb"))
        print(f"export webley.glb : {n} objet(s), {mb} Mo")
    if save: save_blend(os.path.join(HERE, "webley.blend"))


if __name__ == "__main__":
    main()
