# -*- coding: utf-8 -*-
"""
build_police_car_simple.py — la voiture de police de Route de nuit en version SIMPLE, façon PS1 (~2 500 triangles).

Le joueur ne la conduit pas, il la voit : garée sur l'accotement, de nuit, dans le brouillard. Donc :
  - la caisse basse est UN loft de 16 sections de 14 points, sans subdivision ni épaisseur (formes lisses par
    lissage des normales sous 38°, arêtes vives au-delà) ; les passages de roue sont des poches creusées par booléen
    (un cylindre de 16 faces par roue, matériau sombre transféré) ;
  - le pavillon est un jeu de 13 polygones explicites : pare-brise, toit, lunette, et par côté montant A, vitre
    avant, montant B, vitre arrière, montant C. Les vitres sont des faces OPAQUES sombres et brillantes : pas
    d'intérieur, rien à voir dedans ;
  - la bande bleue est une région de faces de la caisse (pas un objet), « POLICE » est un texte basse résolution ;
  - feux, pare-chocs, rétroviseurs, plaques, rampe : des boîtes et des tours de potier à 8 pas.
Mêmes noms de nœuds que le modèle détaillé pour le jeu : POL_Beacon_L/R (dômes) et POL_BeaconMirror_L/R (pivots).

Exécution :
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python assets/blender/build_police_car_simple.py
Options après « -- » : --pct=60 --quick --no-render --no-export --no-save
Sorties : assets/models/police_car_simple.glb, assets/blender/police_car_simple.blend, renders/police_simple_*.png
Repère : Z vertical, sol en z = 0, AVANT = +Y ; glTF -> Godot (x, z, -y), avant = -Z.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector
_HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
if _HERE not in sys.path: sys.path.insert(0, _HERE)
import civic_lib as L
from build_police_car import text_mesh, env_scene, materials, stats

ROOT_DIR = os.path.normpath(os.path.join(_HERE, "..", ".."))
MODELS = os.path.join(ROOT_DIR, "assets", "models")
RENDERS = os.path.join(_HERE, "renders")
COL = "Police_Car_Simple"; CUTTERS = "Police_Simple_Cutters"; ENV = "Police_Env"

# ---------------------------------------------------------------------------
# Cotes (gabarit Peugeot 405 : 4,40 x 1,69 x 1,385 m)
# ---------------------------------------------------------------------------
HALF_W = 0.845; BELT = 0.97; ROOF = 1.385; ROOF_X = 0.68
NOSE, TAIL = 2.20, -2.20
AXLE_F, AXLE_R = 1.34, -1.33
WHEEL_R, WHEEL_X, TIRE_W = 0.30, 0.73, 0.19
BAND_Z0, BAND_Z1 = 0.60, 0.72
SILL, FLOOR = 0.45, 0.23
COWL_Y, HEADER_Y, RHEADER_Y, RBASE_Y = 0.95, 0.30, -0.82, -1.40
BAR_Y, BEACON_X = 0.05, 0.40

def x_side(z):
    """Flanc vitré : de la ceinture (pleine largeur) au bord du toit (tumblehome)."""
    return HALF_W - (HALF_W - ROOF_X)*max(0.0, min(1.0, (z - BELT)/(ROOF - BELT)))

class Ctx:
    def __init__(self):
        L.clear_collection(COL); L.clear_collection(ENV)
        self.col = L.get_col(COL); self.cut = L.get_col(CUTTERS, self.col); self.env = L.get_col(ENV); self.M = materials()
        self.M['glass_dark'] = L.mat("POL_Glass_Dark", (0.03, 0.035, 0.05), rough=0.18, specular=0.8, coat=0.5)

# ---------------------------------------------------------------------------
# Caisse basse : loft de sections de 14 points (demi-section de 8)
# ---------------------------------------------------------------------------
def half(zt, drop, w, zb, d):
    """(x, z) du centre du dessus au centre du dessous. zt : dessus au centre ; drop : descente de l'épaulement ;
    d : chute de l'arête de l'aile (0 = ceinture à plat jusqu'au bord) ; w : demi-largeur ; zb : dessous.
    Les hauteurs de bande / bas de caisse sont bornées en chaîne pour rester MONOTONES aux sections de fermeture,
    puis le tout est remis à l'échelle entre zb et zt."""
    z1 = zt - drop; z2 = z1 - d
    b1 = min(BAND_Z1, z2 - 0.03); b0 = min(BAND_Z0, b1 - 0.06); sill = min(SILL, b0 - 0.06); floor = min(FLOOR, sill - 0.10)
    pts = [(0.0, zt), (w - 0.06, z1), (w, z2), (w + 0.005, b1), (w + 0.005, b0), (w - 0.03, sill), (w - 0.25, floor), (0.0, floor)]
    k = (zt - zb)/(zt - floor)
    return [(x, zb + (z - floor)*k) for (x, z) in pts]

def ring(y, zt, drop, w, zb, d):
    pts = half(zt, drop, w, zb, d)
    assert all(pts[i][1] >= pts[i+1][1] - 1e-6 for i in range(len(pts) - 1)), ("profil non monotone", y, pts)
    return [(-x, y, z) for (x, z) in pts] + [(x, y, z) for (x, z) in reversed(pts[1:-1])]      # 14 points

STATIONS = [   # (y, zt, drop, w, zb, d)
    (NOSE, 0.52, 0.02, 0.42, 0.36, 0.02), (2.16, 0.72, 0.04, 0.80, 0.26, 0.05), (2.05, 0.78, 0.05, HALF_W, FLOOR, 0.06),
    (1.80, 0.81, 0.05, HALF_W, FLOOR, 0.06), (1.50, 0.85, 0.05, HALF_W, FLOOR, 0.06), (1.20, 0.89, 0.05, HALF_W, FLOOR, 0.06),
    (1.00, 0.92, 0.05, HALF_W, FLOOR, 0.06),
    (COWL_Y, BELT, 0.0, HALF_W, FLOOR, 0.0), (0.0, BELT, 0.0, HALF_W, FLOOR, 0.0), (-0.95, BELT, 0.0, HALF_W, FLOOR, 0.0), (RBASE_Y, BELT, 0.0, HALF_W, FLOOR, 0.0),
    (-1.46, BELT, 0.04, HALF_W, FLOOR, 0.05), (-1.85, 0.955, 0.04, HALF_W, FLOOR, 0.05), (-2.08, 0.93, 0.04, HALF_W, FLOOR, 0.05),
    (-2.16, 0.80, 0.04, 0.80, 0.26, 0.05), (TAIL, 0.52, 0.02, 0.42, 0.36, 0.02),
]

def body(X):
    M = X.M
    def body_mat(c):      # bande bleue : les faces entre les deux points de bande, sur les portières
        return 1 if (BAND_Z0 - 0.01 < c.z < BAND_Z1 + 0.01 and abs(c.x) > HALF_W - 0.02 and -0.95 < c.y < 0.95) else 0
    ob = L.loft("POL_Body", [ring(*st) for st in STATIONS], [M['paint'], M['blue'], M['well']], X.col, subsurf=0, smooth=False, idx_fn=body_mat)
    L.shade(ob, 38)
    # Passages de roue : poches creusées dans la caisse pleine ; le cylindre apporte son matériau sombre.
    for y, tag in ((AXLE_F, "F"), (AXLE_R, "R")):
        for s, nm in ((-1, "L"), (1, "R")):
            cut = L.cyl(f"CUT_Arch_{tag}{nm}", 0.41, 0.60, (s*0.88, y, WHEEL_R + 0.02), M['well'], X.cut, rot=(0, 90, 0), segments=16, smooth=True)
            cut.display_type = 'WIRE'; cut.hide_render = True
    mod = L.add_boolean_collection(ob, X.cut)
    if hasattr(mod, 'material_mode'): mod.material_mode = 'TRANSFER'
    return ob

# ---------------------------------------------------------------------------
# Pavillon : polygones explicites, vitres opaques
# ---------------------------------------------------------------------------
def poly_mesh(name, polys, mats, col, sharp=30):
    """polys : [(points 3D, index de matériau)]. Chaque face est orientée vers l'extérieur (loin de l'axe de la voiture)."""
    bm = bmesh.new(); cache = {}
    def v(p):
        k = tuple(round(c, 5) for c in p)
        if k not in cache: cache[k] = bm.verts.new(p)
        return cache[k]
    for pts, mi in polys:
        f = bm.faces.new([v(p) for p in pts]); f.material_index = mi; f.normal_update()
        c = f.calc_center_median(); out = Vector((c.x, 0.0, c.z - 0.90))
        if f.normal.dot(out) < 0: f.normal_flip()
    ob = L.bm_to_obj(bm, name, mats, col); L.shade(ob, sharp); return ob

def greenhouse(X):
    M = X.M
    side = {   # (y, z) sur le flanc vitré ; 0 = peinture (montants), 1 = vitre
        "PillarA":  ([(COWL_Y, BELT), (HEADER_Y, ROOF), (HEADER_Y - 0.09, ROOF), (COWL_Y - 0.09, BELT)], 0),
        "WinFront": ([(COWL_Y - 0.09, BELT), (HEADER_Y - 0.09, ROOF), (-0.08, ROOF), (-0.08, BELT)], 1),
        "PillarB":  ([(-0.08, BELT), (-0.08, ROOF), (-0.16, ROOF), (-0.16, BELT)], 0),
        "WinRear":  ([(-0.16, BELT), (-0.16, ROOF), (RHEADER_Y + 0.12, ROOF), (RBASE_Y + 0.06, BELT)], 1),
        "PillarC":  ([(RBASE_Y + 0.06, BELT), (RHEADER_Y + 0.12, ROOF), (RHEADER_Y, ROOF), (RBASE_Y, BELT)], 0),
    }
    polys = []
    for s in (-1, 1):
        for pts, mi in side.values():
            p3 = [(s*x_side(z), y, z) for (y, z) in pts]
            polys.append((p3 if s > 0 else list(reversed(p3)), mi))
    polys.append(([(-HALF_W, COWL_Y, BELT), (HALF_W, COWL_Y, BELT), (ROOF_X, HEADER_Y, ROOF), (-ROOF_X, HEADER_Y, ROOF)], 1))          # pare-brise
    polys.append(([(-ROOF_X, HEADER_Y, ROOF), (ROOF_X, HEADER_Y, ROOF), (ROOF_X, RHEADER_Y, ROOF), (-ROOF_X, RHEADER_Y, ROOF)], 0))    # toit
    polys.append(([(-ROOF_X, RHEADER_Y, ROOF), (ROOF_X, RHEADER_Y, ROOF), (HALF_W, RBASE_Y, BELT), (-HALF_W, RBASE_Y, BELT)], 1))      # lunette
    return poly_mesh("POL_Greenhouse", polys, [M['paint'], M['glass_dark']], X.col)

# ---------------------------------------------------------------------------
# Détails : boîtes et tours de potier basse résolution
# ---------------------------------------------------------------------------
def details(X):
    M, C = X.M, X.col
    # avant : la face du nez penche de ~10°, les feux la suivent
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"POL_Headlight_{nm}", (0.40, 0.02, 0.12), (s*0.52, 2.19, 0.64), M['reflector'], C, rot=(10, 0, 0), smooth=False)
        L.box(f"POL_TurnSignal_{nm}", (0.16, 0.02, 0.06), (s*0.62, 2.225, 0.49), M['amber'], C, smooth=False)
        L.box(f"POL_TailLight_{nm}", (0.30, 0.02, 0.13), (s*0.52, -2.185, 0.74), M['red'], C, rot=(-8, 0, 0), smooth=False)
        L.box(f"POL_TailAmber_{nm}", (0.12, 0.02, 0.13), (s*0.74, -2.185, 0.74), M['amber'], C, rot=(-8, 0, 0), smooth=False)
        L.box(f"POL_Mirror_{nm}", (0.09, 0.13, 0.07), (s*0.93, 0.78, 1.07), M['black'], C, bevel=0.012, segs=1)
        L.box(f"POL_MirrorArm_{nm}", (0.11, 0.04, 0.03), (s*0.87, 0.80, 1.04), M['black'], C, smooth=False)
        for y, tag in ((-0.02, "F"), (-0.98, "R")):
            L.box(f"POL_DoorHandle_{tag}{nm}", (0.016, 0.13, 0.03), (s*(HALF_W + 0.004), y, 0.87), M['black'], C, smooth=False)
    L.box("POL_Grille", (0.54, 0.02, 0.10), (0, 2.19, 0.64), M['black'], C, rot=(10, 0, 0), smooth=False)
    L.box("POL_FrontBumper", (1.72, 0.14, 0.14), (0, 2.15, 0.45), M['black'], C, bevel=0.03, segs=1)
    L.box("POL_RearBumper", (1.72, 0.14, 0.14), (0, -2.15, 0.45), M['black'], C, bevel=0.03, segs=1)
    L.box("POL_FrontPlate", (0.50, 0.01, 0.11), (0, 2.225, 0.46), M['plate_w'], C, smooth=False)
    L.box("POL_RearPlate", (0.50, 0.01, 0.11), (0, -2.225, 0.46), M['plate_y'], C, smooth=False)
    L.cyl("POL_AntennaBase", 0.018, 0.02, (0.55, -1.72, 0.975), M['black'], C, segments=8)
    L.cyl_between("POL_Antenna", (0.55, -1.72, 0.98), (0.57, -1.78, 1.90), 0.004, M['chrome'], C, segments=6)
    L.cyl_between("POL_Exhaust", (0.40, -1.95, 0.26), (0.40, -2.22, 0.26), 0.022, M['dark_metal'], C, segments=8)
    # lettrages : blancs dans la bande (lisibles de chaque côté), bleu sur le capot (lisible depuis l'avant)
    for s, nm in ((-1, "L"), (1, "R")):
        text_mesh(f"POL_Text_Door_{nm}", "POLICE", 0.085, (s*(HALF_W + 0.011), 0.40, 0.662), (90, 0, s*90), M['white'], C, extrude=0.0, spacing=1.08, resolution=2)
    text_mesh("POL_Text_Hood", "POLICE", 0.17, (0.0, 1.35, 0.872), (7.6, 0, 180), M['blue'], C, extrude=0.0, spacing=1.1, resolution=2)

def light_bar(X):
    M, C = X.M, X.col
    L.box("POL_BarBase", (1.10, 0.20, 0.06), (0, BAR_Y, ROOF + 0.03), M['black'], C, bevel=0.012, segs=1)
    L.box("POL_BarCentre", (0.26, 0.16, 0.09), (0, BAR_Y, ROOF + 0.105), M['blue'], C, bevel=0.01, segs=1)
    for s, nm in ((-1, "L"), (1, "R")):
        base = (s*BEACON_X, BAR_Y, ROOF + 0.06)
        L.lathe(f"POL_BeaconBase_{nm}", [(0.0, 0.0), (0.095, 0.0), (0.095, 0.022), (0.0, 0.022)], M['black'], C, loc=base, steps=8)
        piv = L.empty(f"POL_BeaconMirror_{nm}", (base[0], base[1], base[2] + 0.022), C)
        L.box(f"POL_BeaconMirrorPlate_{nm}", (0.07, 0.012, 0.06), (0, -0.02, 0.055), M['reflector'], C, parent=piv, smooth=False)
        L.cyl(f"POL_BeaconBulb_{nm}", 0.011, 0.05, (0, 0, 0.05), M['bulb'], C, segments=6, parent=piv)
        L.lathe(f"POL_Beacon_{nm}", [(0.0, 0.13), (0.045, 0.125), (0.075, 0.09), (0.08, 0.02), (0.08, 0.0), (0.0, 0.0)], M['beacon'], C,
                loc=(base[0], base[1], base[2] + 0.022), steps=8)

def wheels(X):
    M, C = X.M, X.col
    for y, tag in ((AXLE_F, "F"), (AXLE_R, "R")):
        for s, nm in ((-1, "L"), (1, "R")):
            L.cyl(f"POL_Tire_{tag}{nm}", WHEEL_R, TIRE_W, (s*WHEEL_X, y, WHEEL_R), M['tire'], C, rot=(0, 90, 0), segments=12)
            L.cyl(f"POL_Hubcap_{tag}{nm}", 0.13, 0.02, (s*(WHEEL_X + TIRE_W/2), y, WHEEL_R), M['chrome'], C, rot=(0, 90, 0), segments=10)

VIEWS = [("CAM_Front34", "police_simple_front34.png", []), ("CAM_Rear34", "police_simple_rear34.png", []), ("CAM_Side", "police_simple_side.png", []),
         ("CAM_Bar", "police_simple_bar.png", [])]

def build():
    X = Ctx()
    body(X); greenhouse(X); details(X); light_bar(X); wheels(X); env_scene(X)
    L.hide_cutters(CUTTERS)
    tris, out = stats(X.col)
    print("Police car (simple) built:", len(X.col.all_objects), "objects,", tris, "tris")
    if out: print("HORS GABARIT :", out)
    return X

def main(export=True, render=True, save=True, views=None, pct=100):
    for ob in list(bpy.data.objects):
        if ob.name in ("Cube", "Light", "Camera"): bpy.data.objects.remove(ob, do_unlink=True)
    build()
    if export:
        os.makedirs(MODELS, exist_ok=True)
        n, mb = L.export_glb(COL, os.path.join(MODELS, "police_car_simple.glb")); print(f"export police_car_simple.glb : {n} objets, {mb} Mo")
        L.hide_cutters(CUTTERS)
    if render:
        print("rendus :", L.render_views(views or VIEWS, RENDERS, pct=pct))
    if save: L.save_blend(os.path.join(_HERE, "police_car_simple.blend"))

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    quick = [v for v in VIEWS if v[0] in ("CAM_Front34", "CAM_Rear34")] if "--quick" in args else None
    main(export="--no-export" not in args, render="--no-render" not in args, save="--no-save" not in args,
         views=quick, pct=int(next((a.split("=")[1] for a in args if a.startswith("--pct=")), 100)))
