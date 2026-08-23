# -*- coding: utf-8 -*-
"""
build_police_car.py — berline de police (Police Nationale, 1990) pour Route de nuit.

Une trois-volumes d'époque (gabarit Peugeot 405 : 4,42 m, 1,69 m, 1,40 m, empattement 2,67 m) construite avec la
même technique que la carrosserie de la Civic : UNE coque fermée loftée (sections de 40 points : capot, pare-brise,
pavillon, lunette, malle, flancs, dessous), subdivisée, épaissie (Solidify 12 mm), puis découpée par booléen
(passages de roue + six baies vitrées). Les montants sont la tôle qui reste entre les découpes.

Livrée : caisse blanche, bande bleue sur les flancs avec « POLICE » en blanc, « POLICE » bleu sur le capot et la
malle, rampe de toit noire avec deux gyrophares bleus (POL_Beacon_L/R : le jeu les fait clignoter et y accroche
des lumières), antenne fouet sur la malle, plaque avant blanche / arrière jaune (avant 1993).

Exécution :
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python assets/blender/build_police_car.py
  ou, Blender ouvert : sys.path.insert(0, ".../assets/blender"); import build_police_car; build_police_car.main()

Sorties : assets/models/police_car.glb, assets/blender/police_car.blend, assets/blender/renders/police_*.png
Repère : Z vertical, sol en z = 0, milieu de la voiture en y = 0, AVANT = +Y. glTF Y-up -> Godot (x, z, -y),
avant = -Z, comme la Civic. Les roues POL_Wheel_FL/FR/RL/RR ont leur +Z local vers l'extérieur.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector
_HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
if _HERE not in sys.path: sys.path.insert(0, _HERE)
import civic_lib as L
from civic_dims import round_outline

ROOT_DIR = os.path.normpath(os.path.join(_HERE, "..", ".."))
MODELS = os.path.join(ROOT_DIR, "assets", "models")
RENDERS = os.path.join(_HERE, "renders")
COL = "Police_Car"; CUTTERS = "Police_Cutters"; ENV = "Police_Env"

# ---------------------------------------------------------------------------
# Cotes
# ---------------------------------------------------------------------------
HALF_W = 0.845               # demi-largeur hors tout (1690 mm)
ROOF_OUT = 1.40              # pavillon
ROOF_EDGE = 1.33             # bord du pavillon (gouttière)
BELT = 0.97                  # ceinture de caisse aux portes
NOSE, TAIL = 2.22, -2.21
AXLE_F, AXLE_R = 1.34, -1.33
WHEEL_R, WHEEL_X = 0.30, 0.73
COWL_Y, COWL_Z = 0.98, 0.95                 # bas du pare-brise
HEADER_Y, HEADER_Z = 0.30, 1.385            # haut du pare-brise
RWIN_Y0, RWIN_Z0 = -1.40, 1.01              # bas de la lunette
RWIN_Y1, RWIN_Z1 = -0.82, 1.385             # haut de la lunette
DOOR_F_FRONT, DOOR_F_REAR = 0.92, -0.10     # portière avant (à la ceinture)
DOOR_R_REAR = -1.06                         # arrière de la portière arrière
WIN_TOP = 1.30
PILLAR_B = -0.12                            # axe du montant B

def z_ws(y):      return COWL_Z + (COWL_Y - y)/(COWL_Y - HEADER_Y)*(HEADER_Z - COWL_Z)
def z_rear(y):    return RWIN_Z0 + (y - RWIN_Y0)/(RWIN_Y1 - RWIN_Y0)*(RWIN_Z1 - RWIN_Z0)
def pillar_y(z):  return COWL_Y - (z - COWL_Z)/(HEADER_Z - COWL_Z)*(COWL_Y - HEADER_Y)       # montant A dans le plan YZ
def cpillar_y(z): return RWIN_Y0 + (z - RWIN_Z0)/(RWIN_Z1 - RWIN_Z0)*(RWIN_Y1 - RWIN_Y0)     # bord de lunette
def x_side(z):    return 0.825 - 0.125*max(0.0, min(1.0, (z - BELT)/(ROOF_EDGE - BELT)))    # flanc vitré (tumblehome)

WS_N = Vector((0, HEADER_Z - COWL_Z, COWL_Y - HEADER_Y)).normalized()
WS_S = Vector((0, -(COWL_Y - HEADER_Y), HEADER_Z - COWL_Z)).normalized()
RW_N = Vector((0, -(RWIN_Z1 - RWIN_Z0), RWIN_Y1 - RWIN_Y0)).normalized()
RW_S = Vector((0, RWIN_Y1 - RWIN_Y0, RWIN_Z1 - RWIN_Z0)).normalized()
WS_BASE = Vector((0, 0.955, z_ws(0.955))); WS_VTOP = (0.955 - 0.345)/abs(WS_S.y)
RW_BASE = Vector((0, -1.375, z_rear(-1.375))); RW_VTOP = (1.375 - 0.865)/abs(RW_S.y)
def ws_pt(x, v): p = WS_BASE + WS_S*v; return (x, p.y, p.z)
def rw_pt(x, v): p = RW_BASE + RW_S*v; return (x, p.y, p.z)

# Contours des vitres. Latérales : (y, z) ; pare-brise / lunette : 3D sur le plan de la vitre.
FRONT_WIN = round_outline([(pillar_y(0.985) - 0.05, 0.985), (pillar_y(WIN_TOP) - 0.075, WIN_TOP), (PILLAR_B + 0.04, WIN_TOP), (PILLAR_B + 0.04, 0.985)],
                          (0.03, 0.08, 0.05, 0.03))
REAR_WIN = round_outline([(PILLAR_B - 0.04, 0.985), (PILLAR_B - 0.04, WIN_TOP), (-0.93, WIN_TOP), (-1.15, 0.985)], (0.03, 0.05, 0.08, 0.04))
WS_WIN = [ws_pt(x, v) for (x, v) in round_outline([(-0.72, 0.0), (0.72, 0.0), (0.64, WS_VTOP), (-0.64, WS_VTOP)], (0.10, 0.10, 0.09, 0.09), n=6)]
RW_WIN = [rw_pt(x, v) for (x, v) in round_outline([(-0.66, 0.0), (0.66, 0.0), (0.59, RW_VTOP), (-0.59, RW_VTOP)], (0.09, 0.09, 0.08, 0.08), n=6)]

# ---------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------
def materials():
    m = L.mat
    return dict(
        paint   = m("POL_Paint_White", (0.86, 0.87, 0.87), rough=0.35, coat=0.6),
        blue    = m("POL_Blue", (0.012, 0.055, 0.38), rough=0.4, coat=0.3),
        white   = m("POL_Letter_White", (0.92, 0.92, 0.92), rough=0.5),
        inner   = m("POL_Sheet_Inner", (0.05, 0.05, 0.055), rough=0.9),
        black   = m("POL_Trim_Black", (0.015, 0.015, 0.016), rough=0.7),
        chrome  = m("POL_Chrome", (0.85, 0.86, 0.88), rough=0.15, metallic=1.0),
        glass   = m("POL_Glass", (0.75, 0.82, 0.88), rough=0.02, alpha=0.10, specular=0.6),
        hl_glass = m("POL_Headlight_Glass", (0.85, 0.88, 0.92), rough=0.08, alpha=0.35, coat=1.0),
        reflector = m("POL_Reflector", (0.9, 0.9, 0.92), rough=0.2, metallic=1.0),
        amber   = m("POL_Lens_Amber", (0.95, 0.45, 0.05), rough=0.15, coat=1.0, emission=(1.0, 0.5, 0.1), emit=0.15),
        red     = m("POL_Lens_Red", (0.75, 0.03, 0.02), rough=0.15, coat=1.0, emission=(1.0, 0.05, 0.02), emit=0.15),
        white_lens = m("POL_Lens_White", (0.9, 0.9, 0.88), rough=0.15, coat=1.0),
        beacon  = m("POL_Beacon_Blue", (0.05, 0.22, 0.95), rough=0.1, alpha=0.55, coat=1.0, emission=(0.15, 0.4, 1.0), emit=0.5),
        bulb    = m("POL_Beacon_Bulb", (0.9, 0.95, 1.0), rough=0.3, emission=(0.8, 0.9, 1.0), emit=2.0),
        tire    = m("POL_Tire", (0.018, 0.018, 0.018), rough=0.9),
        steel   = m("POL_Rim_Steel", (0.22, 0.22, 0.24), rough=0.5, metallic=0.6),
        plate_w = m("POL_Plate_White", (0.9, 0.9, 0.86), rough=0.5),
        plate_y = m("POL_Plate_Yellow", (0.95, 0.78, 0.12), rough=0.5),
        plate_txt = m("POL_Plate_Text", (0.02, 0.02, 0.02), rough=0.6),
        interior = m("POL_Interior", (0.045, 0.045, 0.05), rough=0.92),
        seat    = m("POL_Seat", (0.06, 0.065, 0.075), rough=0.95),
        dark_metal = m("POL_Dark_Metal", (0.12, 0.12, 0.12), rough=0.6, metallic=0.6),
        well    = m("POL_WheelWell", (0.02, 0.02, 0.02), rough=1.0),
        asphalt = m("ENV_Asphalt", (0.09, 0.09, 0.09), rough=0.95),
    )

class Ctx:
    def __init__(self):
        L.clear_collection(COL); L.clear_collection(ENV)
        self.col = L.get_col(COL); self.cut = L.get_col(CUTTERS, self.col); self.env = L.get_col(ENV); self.M = materials()

# ---------------------------------------------------------------------------
# Coque : demi-section de 21 points (dessus -> bord -> flanc -> dessous, le dernier au centre)
# ---------------------------------------------------------------------------
LOWER = [(0.825, BELT), (0.838, 0.91), (0.845, 0.84), (0.847, 0.76), (0.845, 0.68), (0.838, 0.60), (0.825, 0.53), (0.805, 0.47),
         (0.79, 0.43), (0.76, 0.36), (0.69, 0.28), (0.50, 0.22), (0.0, 0.21)]                      # 13 points, ceinture -> centre du dessous
CROWN = {'ws': (0.003, 0.009, 0.016, 0.028), 'roof': (0.008, 0.026, 0.05, 0.07), 'rear': (0.004, 0.012, 0.022, 0.035)}

def side_x_low(z):
    """Demi-largeur du flanc bas (sous la ceinture) à la hauteur z."""
    for i in range(len(LOWER) - 1):
        (x0, z0), (x1, z1) = LOWER[i], LOWER[i+1]
        if z1 <= z <= z0: return x0 + (x1 - x0)*(z0 - z)/(z0 - z1)
    return LOWER[-1][0] if z < LOWER[-1][1] else LOWER[0][0]

def lower_pts(belt_eff):
    """Le flanc bas, la ceinture ramenée à belt_eff : les points au-dessus du pivot sont compressés linéairement
    dans [pivot, belt_eff]. Le pivot descend avec la ceinture pour que le profil reste MONOTONE en z — un simple
    décalage faisait un pli aux stations de fermeture (nez, queue), d'où des épines après subdivision + épaisseur."""
    zp = min(0.72, belt_eff - 0.04)
    return [(x, zp + (z - zp)*(belt_eff - zp)/(BELT - zp) if z > zp else z) for (x, z) in LOWER]

def half_profile(y, kind, zt, w, zb):
    if kind in ('hood', 'tail'):
        # capot / malle : bombé léger, dessus d'aile au niveau du bord, arête d'aile vive (pli à l'index 4) qui roule sur 6 cm
        top = [(0.0, zt), (0.26, zt - 0.004), (0.50, zt - 0.016), (0.68, zt - 0.03), (0.78, zt - 0.035), (0.815, zt - 0.042), (0.832, zt - 0.05), (0.840, zt - 0.06)]
        pts = top + lower_pts(zt - 0.07)
        pts = [(x*(w/HALF_W), zb + (z - 0.21)*(zt - zb)/(zt - 0.21)) for (x, z) in pts]
    else:
        c = CROWN[kind]; ze = zt - c[3]; xe = x_side(ze)
        top = [(0.0, zt), (0.28, zt - c[0]), (0.50, zt - c[1]), (0.64*xe/0.70, zt - c[2]), (xe, ze)]
        drop = 0.06*L.smoothstep(0.60, 0.99, y) if kind == 'ws' else 0.0      # la ceinture redescend vers l'aile avant
        belt_eff = min(BELT - drop, ze - 0.03)
        side = [(x_side(z), z) for z in (ze - (ze - belt_eff)*f for f in (0.25, 0.55, 0.85))]
        pts = top + side + lower_pts(belt_eff)
    assert len(pts) == 21, len(pts)
    assert all(pts[i][1] >= pts[i+1][1] - 1e-6 for i in range(20)), ("profil non monotone en z", y, kind, pts)
    return pts

def ring(y, kind, zt, w=HALF_W, zb=0.21):
    pts = half_profile(y, kind, zt, w, zb)
    return [(-x, y, z) for (x, z) in pts] + [(x, y, z) for (x, z) in reversed(pts[1:-1])]

STATIONS = [
    (NOSE, 'hood', 0.50, 0.30, 0.40), (2.21, 'hood', 0.62, 0.62, 0.34), (2.19, 'hood', 0.72, 0.76, 0.29), (2.15, 'hood', 0.77, 0.81, 0.25),
    (2.08, 'hood', 0.795, 0.835, 0.22), (2.00, 'hood', 0.81), (1.80, 'hood', 0.835), (1.55, 'hood', 0.865), (1.30, 'hood', 0.89),
    (1.10, 'hood', 0.915), (0.99, 'hood', 0.93),
    (0.94, 'ws', z_ws(0.94)), (0.85, 'ws', z_ws(0.85)), (0.72, 'ws', z_ws(0.72)), (0.58, 'ws', z_ws(0.58)), (0.45, 'ws', z_ws(0.45)), (0.36, 'ws', z_ws(0.36)),
    (HEADER_Y, 'ws', HEADER_Z),
    (0.22, 'roof', 1.395), (0.0, 'roof', ROOF_OUT), (-0.30, 'roof', ROOF_OUT), (-0.55, 'roof', ROOF_OUT), (-0.75, 'roof', 1.395), (RWIN_Y1, 'roof', RWIN_Z1),
    (-0.90, 'rear', z_rear(-0.90)), (-1.05, 'rear', z_rear(-1.05)), (-1.20, 'rear', z_rear(-1.20)), (-1.33, 'rear', z_rear(-1.33)), (RWIN_Y0, 'rear', RWIN_Z0),
    (-1.46, 'tail', 1.00), (-1.65, 'tail', 0.99), (-1.85, 'tail', 0.975), (-2.02, 'tail', 0.955, 0.84, 0.22), (-2.12, 'tail', 0.93, 0.83, 0.23),
    (-2.17, 'tail', 0.86, 0.80, 0.26), (-2.19, 'tail', 0.74, 0.74, 0.30), (-2.20, 'tail', 0.60, 0.58, 0.35), (TAIL, 'tail', 0.48, 0.30, 0.42),
]

def body_shell(X):
    rings = [ring(*st) for st in STATIONS]
    body = L.loft("POL_Body", rings, [X.M['paint'], X.M['inner']], X.col,
                  creases=[(4, 0.5), (36, 0.5), (8, 0.7), (32, 0.7), (15, 0.6), (25, 0.6), (16, 0.3), (24, 0.3)])
    sheet = L.add_solidify(body, 0.012)
    # Sans ça, l'épaisseur « even » envoie quatre sommets à plusieurs mètres (normales mal conditionnées aux
    # sommets du nez, de la malle et du haut de lunette) : des traits fins qui sortent de la caisse au rendu.
    sheet.use_quality_normals = True
    L.add_boolean_collection(body, X.cut)
    return body

def prism(X, name, outline, d, ext=0.12):
    d = Vector(d).normalized()
    ob = L.loft(name, [[tuple(Vector(p) - d*ext) for p in outline], [tuple(Vector(p) + d*ext) for p in outline]], None, X.cut, closed=True, caps=True, subsurf=0, smooth=False)
    ob.display_type = 'WIRE'; ob.hide_render = True; return ob

def wheel_arches(X):
    M = X.M
    for y, tag in ((AXLE_F, "F"), (AXLE_R, "R")):
        for s, nm in ((-1, "L"), (1, "R")):
            cut = L.cyl(f"CUT_Arch_{tag}{nm}", 0.41, 0.70, (s*0.88, y, WHEEL_R + 0.02), None, X.cut, rot=(0, 90, 0), segments=48, smooth=False)
            cut.display_type = 'WIRE'; cut.hide_render = True
            angs = [-10 + 200*k/15 for k in range(16)]
            zc = lambda a: WHEEL_R + 0.02 + 0.415*math.sin(math.radians(a))
            outer = [(s*(side_x_low(zc(a)) - 0.006), y + 0.415*math.cos(math.radians(a)), zc(a)) for a in angs]
            mid = [(s*0.53, y + 0.415*math.cos(math.radians(a)), zc(a)) for a in angs]
            inner = [(s*0.53, y + 0.10*math.cos(math.radians(a)), WHEEL_R + 0.02 + 0.10*math.sin(math.radians(a))) for a in angs]
            L.loft(f"POL_WheelWell_{tag}{nm}", [outer, mid, inner], M['well'], X.col, closed=False, caps=False, subsurf=1)
            lip = [(s*(side_x_low(WHEEL_R + 0.02 + 0.41*math.sin(math.radians(a))) + 0.006), y + 0.41*math.cos(math.radians(a)), WHEEL_R + 0.02 + 0.41*math.sin(math.radians(a)))
                   for a in [-8 + 196*k/22 for k in range(23)]]
            L.tube_along(f"POL_ArchLip_{tag}{nm}", lip, 0.009, M['paint'], X.col, n=8, subsurf=1)

def side_glass_pts(s, outline, inset):
    pts = [(s*(x_side(z) - inset), y, z) for (y, z) in outline]
    return pts if s > 0 else list(reversed(pts))

def plane_glass_pts(outline3d, n, inset):
    return [tuple(Vector(p) - Vector(n)*inset) for p in outline3d]

def glazing(X):
    """Découpes des baies + vitres + joints plats + montant B noir + gouttières."""
    M = X.M
    for s, nm in ((-1, "L"), (1, "R")):
        prism(X, f"CUT_FrontWin_{nm}", [(s*0.80, y, z) for (y, z) in FRONT_WIN], (s, 0, 0), 0.14)
        prism(X, f"CUT_RearWin_{nm}", [(s*0.80, y, z) for (y, z) in REAR_WIN], (s, 0, 0), 0.14)
    prism(X, "CUT_Windshield", WS_WIN, WS_N, 0.10); prism(X, "CUT_RearGlass", RW_WIN, RW_N, 0.10)
    def band_side(name, s, outline, width=0.022, lip=0.012):
        o = [(s*(x_side(z) + 0.004), y, z) for (y, z) in L.offset_outline(outline, lip)]
        i = [(s*(x_side(z) + 0.004), y, z) for (y, z) in L.offset_outline(outline, lip - width)]
        return L.band(name, o, i, M['black'], X.col)
    def band_plane(name, outline3d, n, width=0.024, lip=0.012):
        return L.band(name, L.offset_outline3d(outline3d, lip, n, 0.004), L.offset_outline3d(outline3d, lip - width, n, 0.004), M['black'], X.col)
    for s, nm in ((-1, "L"), (1, "R")):
        L.polygon(f"POL_FrontGlass_{nm}", side_glass_pts(s, FRONT_WIN, 0.003), M['glass'], X.col)
        L.polygon(f"POL_RearDoorGlass_{nm}", side_glass_pts(s, REAR_WIN, 0.003), M['glass'], X.col)
        band_side(f"POL_FrontWinSeal_{nm}", s, FRONT_WIN); band_side(f"POL_RearWinSeal_{nm}", s, REAR_WIN)
        pts = [(s*(x_side(z) + 0.005), y, z) for (y, z) in ((PILLAR_B + 0.045, 0.98), (PILLAR_B + 0.045, 1.31), (PILLAR_B - 0.045, 1.31), (PILLAR_B - 0.045, 0.98))]
        L.polygon(f"POL_PillarB_Black_{nm}", pts if s > 0 else list(reversed(pts)), M['black'], X.col)
        L.tube_along(f"POL_Gutter_{nm}", [(s*0.705, 0.33, ROOF_EDGE + 0.004), (s*0.705, -0.30, ROOF_EDGE + 0.007), (s*0.705, -0.84, ROOF_EDGE + 0.004)], 0.006, M['black'], X.col)
    L.polygon("POL_WindshieldGlass", plane_glass_pts(WS_WIN, WS_N, 0.003), M['glass'], X.col)
    L.polygon("POL_RearGlass", plane_glass_pts(RW_WIN, RW_N, 0.003), M['glass'], X.col)
    band_plane("POL_WindshieldSeal", WS_WIN, WS_N); band_plane("POL_RearGlassSeal", RW_WIN, RW_N)

# ---------------------------------------------------------------------------
# Texte -> maillage (Arial gras si disponible)
# ---------------------------------------------------------------------------
_FONT = None
def font():
    global _FONT
    if _FONT is None:
        for p in (r"C:\Windows\Fonts\arialbd.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
            if os.path.exists(p):
                _FONT = bpy.data.fonts.load(p, check_existing=True); break
        else: _FONT = False
    return _FONT or None

def text_mesh(name, body, size, loc, rot, mat, col, extrude=0.002, spacing=1.0, resolution=12):
    """resolution : segments par courbe de Bézier des glyphes (12 = lisse ; 2-3 = basse-poly)."""
    cu = bpy.data.curves.new(name + "_cu", 'FONT'); cu.body = body; cu.size = size; cu.extrude = extrude
    cu.align_x = 'CENTER'; cu.align_y = 'CENTER'; cu.space_character = spacing; cu.resolution_u = resolution
    f = font()
    if f: cu.font = f
    tmp = bpy.data.objects.new(name + "_tmp", cu); col.objects.link(tmp)
    bpy.context.view_layer.update(); dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg)); me.name = name
    ob = bpy.data.objects.new(name, me); col.objects.link(ob); me.materials.append(mat)
    bpy.data.objects.remove(tmp, do_unlink=True); bpy.data.curves.remove(cu)
    L.place(ob, loc, rot); L.shade(ob, 50); return ob

# ---------------------------------------------------------------------------
# Livrée : bande bleue, lettrages
# ---------------------------------------------------------------------------
BAND_Z0, BAND_Z1 = 0.60, 0.725

def livery(X):
    M, C = X.M, X.col
    for s, nm in ((-1, "L"), (1, "R")):
        ys = [0.95 - 0.05*k for k in range(int((0.95 + 0.95)/0.05) + 1)]            # de l'aile avant à l'aile arrière
        rows = [[(s*(side_x_low(z) + 0.004), y, z) for y in ys] for z in (BAND_Z0, BAND_Z1)]
        L.loft(f"POL_Band_{nm}", rows, M['blue'], C, closed=False, caps=False, subsurf=0, smooth=False)
        # « POLICE » en blanc dans la bande, sur la portière avant
        x = s*(side_x_low(0.66) + 0.006)
        text_mesh(f"POL_Text_Door_{nm}", "POLICE", 0.085, (x, 0.40, 0.663), (90, 0, s*90), M['white'], C, extrude=0.003, spacing=1.08)
    # capot : lisible depuis l'avant (haut des lettres vers le pare-brise = -Y), suit la pente du capot (~7°)
    text_mesh("POL_Text_Hood", "POLICE", 0.17, (0.0, 1.40, 0.885), (6, 0, 180), M['blue'], C, extrude=0.002, spacing=1.1)
    # malle : lisible depuis l'arrière, suit la pente du couvercle
    text_mesh("POL_Text_Trunk", "POLICE", 0.11, (0.0, -1.80, 0.985), (4.5, 0, 0), M['blue'], C, extrude=0.002, spacing=1.1)

# ---------------------------------------------------------------------------
# Faces avant / arrière
# ---------------------------------------------------------------------------
def front(X):
    M, C = X.M, X.col; FR = (12, 0, 0)          # la face avant penche de 12° (haut en arrière)
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"POL_Headlight_{nm}_Housing", (0.40, 0.04, 0.12), (s*0.55, 2.185, 0.635), M['black'], C, rot=FR, bevel=0.005)
        L.box(f"POL_Headlight_{nm}_Reflector", (0.38, 0.02, 0.105), (s*0.55, 2.193, 0.637), M['reflector'], C, rot=FR)
        L.box(f"POL_Headlight_{nm}_Lens", (0.39, 0.008, 0.11), (s*0.55, 2.208, 0.64), M['hl_glass'], C, rot=FR, bevel=0.002)
        L.box(f"POL_TurnSignal_{nm}", (0.16, 0.03, 0.06), (s*0.62, 2.225, 0.49), M['amber'], C, bevel=0.004)
    L.box("POL_Grille", (0.60, 0.03, 0.11), (0, 2.195, 0.635), M['black'], C, rot=FR, bevel=0.005)
    for i in range(4): L.box(f"POL_GrilleBar{i}", (0.56, 0.012, 0.008), (0, 2.21, 0.595 + 0.026*i), M['black'], C, rot=FR)
    L.box("POL_Badge", (0.03, 0.006, 0.04), (0, 2.218, 0.655), M['chrome'], C, rot=FR, bevel=0.003)
    # pare-chocs : plastique noir enveloppant, retours sur les ailes
    L.box("POL_FrontBumper", (1.74, 0.16, 0.15), (0, 2.15, 0.455), M['black'], C, bevel=0.035, segs=5)
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"POL_FrontBumperWrap_{nm}", (0.05, 0.34, 0.15), (s*0.826, 1.99, 0.455), M['black'], C, bevel=0.02, segs=5)
    L.box("POL_FrontBumperStrip", (1.70, 0.012, 0.03), (0, 2.235, 0.45), M['paint'], C, bevel=0.004)
    L.box("POL_FrontAirDam", (1.20, 0.06, 0.06), (0, 2.17, 0.33), M['black'], C, bevel=0.008)
    plate(X, "POL_FrontPlate", (0, 2.245, 0.47), (0, 0, 0), M['plate_w'], "8345 PQ 75")
    ws_on = lambda x, v, h=0.012: tuple(Vector(ws_pt(x, v)) + WS_N*h)
    for nm, px, b0, b1 in (("L", -0.38, (-0.70, 0.03), (-0.22, 0.115)), ("R", 0.18, (-0.16, 0.045), (0.34, 0.12))):
        L.cyl(f"POL_WiperPivot_{nm}", 0.012, 0.03, (px, 0.975, 0.955), M['black'], C, rot=(-32, 0, 0), segments=16)
        mid = ((b0[0] + b1[0])*0.5, (b0[1] + b1[1])*0.5)
        L.cyl_between(f"POL_WiperArm_{nm}", (px, 0.975, 0.965), ws_on(mid[0], mid[1], 0.02), 0.005, M['black'], C, segments=10)
        L.cyl_between(f"POL_WiperBlade_{nm}", ws_on(*b0), ws_on(*b1), 0.0065, M['black'], C, segments=10)

def plate(X, name, loc, rot, mat, number):
    M, C = X.M, X.col
    L.box(name, (0.52, 0.006, 0.11), loc, mat, C, rot=rot, bevel=0.002)
    t = text_mesh(name + "_Text", number, 0.062, (loc[0], loc[1] + (0.004 if loc[1] > 0 else -0.004), loc[2]), (90, 0, 180 if loc[1] > 0 else 0), M['plate_txt'], C, extrude=0.0005, spacing=1.0)
    t.rotation_euler.x += math.radians(rot[0])

def rear(X):
    M, C = X.M, X.col; RR = (-12, 0, 0)         # panneau arrière : haut légèrement en avant
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"POL_TailLight_{nm}_Housing", (0.46, 0.03, 0.15), (s*0.56, -2.165, 0.76), M['black'], C, rot=RR, bevel=0.004)
        L.box(f"POL_TailLight_{nm}_Red", (0.24, 0.012, 0.13), (s*0.50, -2.183, 0.76), M['red'], C, rot=RR, bevel=0.002)
        L.box(f"POL_TailLight_{nm}_Amber", (0.11, 0.012, 0.13), (s*0.69, -2.183, 0.76), M['amber'], C, rot=RR, bevel=0.002)
        L.box(f"POL_TailLight_{nm}_Reverse", (0.07, 0.012, 0.13), (s*0.345, -2.183, 0.76), M['white_lens'], C, rot=RR, bevel=0.002)
    L.box("POL_RearPlateRecess", (0.56, 0.02, 0.14), (0, -2.17, 0.76), M['black'], C, rot=RR, bevel=0.004)
    plate(X, "POL_RearPlate", (0, -2.195, 0.76), (-12, 0, 0), M['plate_y'], "8345 PQ 75")
    L.box("POL_RearBumper", (1.74, 0.16, 0.15), (0, -2.14, 0.455), M['black'], C, bevel=0.035, segs=5)
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"POL_RearBumperWrap_{nm}", (0.05, 0.34, 0.15), (s*0.826, -1.98, 0.455), M['black'], C, bevel=0.02, segs=5)
    L.box("POL_RearBumperStrip", (1.70, 0.012, 0.03), (0, -2.225, 0.45), M['paint'], C, bevel=0.004)
    L.box("POL_TrunkHandle", (0.12, 0.02, 0.03), (0, -2.125, 0.90), M['black'], C, rot=RR, bevel=0.005)
    L.cyl("POL_TrunkLock", 0.011, 0.01, (0.11, -2.13, 0.90), M['chrome'], C, rot=(78, 0, 0), segments=20)
    L.cyl_between("POL_Exhaust", (0.40, -1.90, 0.27), (0.40, -2.22, 0.27), 0.022, M['dark_metal'], C, segments=20)
    L.cyl_between("POL_ExhaustPipe", (0.40, -1.40, 0.25), (0.40, -1.90, 0.27), 0.018, M['dark_metal'], C, segments=12)
    # antenne fouet de la radio de bord, sur la malle
    L.cyl("POL_AntennaBase", 0.018, 0.025, (0.55, -1.72, 0.992), M['black'], C, segments=16)
    L.cyl_between("POL_Antenna", (0.55, -1.72, 1.00), (0.57, -1.78, 1.95), 0.004, M['chrome'], C, segments=8)

# ---------------------------------------------------------------------------
# Côtés : poignées, rétroviseurs, baguettes, lignes de panneaux, trappe
# ---------------------------------------------------------------------------
def sides(X):
    M, C = X.M, X.col
    for s, nm in ((-1, "L"), (1, "R")):
        for y, tag in ((-0.02, "F"), (-0.98, "R")):
            L.box(f"POL_DoorHandle_{tag}{nm}", (0.02, 0.14, 0.036), (s*(side_x_low(0.88) + 0.004), y, 0.88), M['black'], C, bevel=0.006)
        L.cyl(f"POL_DoorLock_{nm}", 0.009, 0.006, (s*(side_x_low(0.88) + 0.004), 0.10, 0.88), M['chrome'], C, rot=(0, 90, 0), segments=20)
        mirror(X, s, nm)
        L.box(f"POL_SillMolding_{nm}", (0.012, 2.05, 0.05), (s*(side_x_low(0.49) + 0.004), -0.07, 0.49), M['black'], C, bevel=0.004)
        for y, tag in ((DOOR_F_FRONT, "FrontA"), (DOOR_F_REAR, "FrontB"), (PILLAR_B - 0.02, "RearB"), (DOOR_R_REAR, "RearC")):
            L.tube_along(f"POL_Seam_{tag}_{nm}", [(s*(side_x_low(z) + 0.003), y - (0.02 if z < 0.55 else 0.0), z) for z in (0.965, 0.90, 0.80, 0.70, 0.60, 0.52, 0.47)],
                         0.0035, M['black'], C, n=6, subsurf=0)
        hood_edge = [(s*(-ring(*st)[4][0]) + s*0.003, st[0], ring(*st)[4][2] + 0.003) for st in STATIONS if 0.99 <= st[0] <= 2.16 and st[1] == 'hood']
        L.tube_along(f"POL_Seam_Hood_{nm}", hood_edge, 0.0035, M['black'], C, n=6, subsurf=0)
        trunk_edge = [(s*(-ring(*st)[4][0]) + s*0.003, st[0], ring(*st)[4][2] + 0.003) for st in STATIONS if -2.10 <= st[0] <= -1.46 and st[1] == 'tail']
        L.tube_along(f"POL_Seam_Trunk_{nm}", trunk_edge, 0.0035, M['black'], C, n=6, subsurf=0)
    for nm, size, loc in (("POL_FuelDoor_T", (0.004, 0.16, 0.004), (-0.838, -1.62, 0.86)), ("POL_FuelDoor_B", (0.004, 0.16, 0.004), (-0.844, -1.62, 0.72)),
                          ("POL_FuelDoor_F", (0.004, 0.004, 0.14), (-0.842, -1.54, 0.79)), ("POL_FuelDoor_R", (0.004, 0.004, 0.14), (-0.842, -1.70, 0.79))):
        L.box(nm, size, loc, M['black'], C, smooth=False)

def mirror(X, s, nm):
    M, C = X.M, X.col
    root = L.empty(f"POL_MirrorRoot_{nm}", (s*0.935, 0.78, 1.07), C, rot=(0, 0, -s*8))
    def rrect(y, sx, sz, n=16):
        return [(sx*math.copysign(abs(math.cos(t))**0.67, math.cos(t)), y, sz*math.copysign(abs(math.sin(t))**0.67, math.sin(t))) for t in [2*math.pi*k/n for k in range(n)]]
    secs = [rrect(0.093, 0.004, 0.003), rrect(0.088, 0.03, 0.018), rrect(0.075, 0.065, 0.042), rrect(0.045, 0.082, 0.052), rrect(0.0, 0.086, 0.054), rrect(-0.045, 0.086, 0.054),
            rrect(-0.068, 0.083, 0.052), rrect(-0.074, 0.074, 0.046), rrect(-0.052, 0.072, 0.045)]
    L.loft(f"POL_Mirror_{nm}", secs, M['black'], C, parent=root, caps=False)
    L.polygon(f"POL_MirrorGlass_{nm}", [(x, -0.062, z) for (x, y, z) in rrect(0.0, 0.0715, 0.0445, 24)], M['chrome'], C, parent=root)
    L.box(f"POL_MirrorBase_{nm}", (0.07, 0.075, 0.03), (s*0.86, 0.82, 1.035), M['black'], C, bevel=0.006)
    L.cyl_between(f"POL_MirrorArm_{nm}", (s*0.855, 0.81, 1.04), (s*0.89, 0.785, 1.06), 0.013, M['black'], C, segments=12)

# ---------------------------------------------------------------------------
# Rampe de gyrophares
# ---------------------------------------------------------------------------
BAR_Y = 0.08
BEACON_X = 0.40

def light_bar(X):
    M, C = X.M, X.col
    zr = ROOF_OUT - 0.02                               # pavillon à x = ±0.45
    L.box("POL_BarBase", (1.10, 0.20, 0.055), (0, BAR_Y, zr + 0.06), M['black'], C, bevel=0.012, segs=4)
    L.box("POL_BarCentre", (0.26, 0.16, 0.09), (0, BAR_Y, zr + 0.125), M['blue'], C, bevel=0.01, segs=4)
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"POL_BarFoot_{nm}", (0.08, 0.14, 0.05), (s*0.46, BAR_Y, zr + 0.01), M['black'], C, bevel=0.008)
        base = (s*BEACON_X, BAR_Y, zr + 0.0875)
        L.lathe(f"POL_BeaconBase_{nm}", [(0.0, 0.0), (0.095, 0.0), (0.095, 0.022), (0.086, 0.026), (0.0, 0.026)], M['black'], C, loc=base, steps=32)
        # réflecteur tournant + ampoule : le jeu fait tourner POL_BeaconMirror_* autour de Z local
        piv = L.empty(f"POL_BeaconMirror_{nm}", (base[0], base[1], base[2] + 0.026), C)
        L.box(f"POL_BeaconMirrorPlate_{nm}", (0.07, 0.012, 0.06), (0, -0.02, 0.055), M['reflector'], C, rot=(0, 0, 0), bevel=0.003, parent=piv)
        L.cyl(f"POL_BeaconBulb_{nm}", 0.011, 0.05, (0, 0, 0.05), M['bulb'], C, segments=12, parent=piv)
        L.lathe(f"POL_Beacon_{nm}", [(0.0, 0.135), (0.035, 0.132), (0.062, 0.118), (0.078, 0.095), (0.082, 0.06), (0.082, 0.0), (0.0, 0.0)], M['beacon'], C,
                loc=(base[0], base[1], base[2] + 0.026), steps=32, subsurf=1)

# ---------------------------------------------------------------------------
# Roues (jantes tôle + enjoliveur)
# ---------------------------------------------------------------------------
TIRE_PROF = [(0.18, -0.095), (0.26, -0.095), (0.285, -0.085), (0.297, -0.06), (0.30, -0.03), (0.30, 0.03), (0.297, 0.06), (0.285, 0.085), (0.26, 0.095), (0.18, 0.095), (0.18, -0.095)]
RIM_PROF = [(0.0, 0.02), (0.09, 0.025), (0.13, 0.005), (0.16, -0.015), (0.18, -0.025), (0.185, -0.06), (0.185, -0.09), (0.17, -0.095), (0.0, -0.095)]
CAP_PROF = [(0.0, 0.05), (0.04, 0.047), (0.07, 0.035), (0.085, 0.022), (0.088, 0.015), (0.0, 0.015)]

def wheels(X):
    M, C = X.M, X.col
    for y, tag in ((AXLE_F, "F"), (AXLE_R, "R")):
        for s, nm in ((-1, "L"), (1, "R")):
            root = L.empty(f"POL_Wheel_{tag}{nm}", (s*WHEEL_X, y, WHEEL_R), C, rot=(0, s*90, 0))     # +Z local = vers l'extérieur
            L.lathe(f"POL_Tire_{tag}{nm}", TIRE_PROF, M['tire'], C, parent=root, steps=48, subsurf=1)
            L.lathe(f"POL_Rim_{tag}{nm}", RIM_PROF, M['steel'], C, parent=root, steps=40, subsurf=1)
            L.lathe(f"POL_Hubcap_{tag}{nm}", CAP_PROF, M['chrome'], C, parent=root, steps=32, subsurf=1)
            for i in range(4):
                a = math.radians(45 + 90*i)
                L.cyl(f"POL_LugNut_{tag}{nm}{i}", 0.008, 0.01, (0.12*math.sin(a), 0.12*math.cos(a), 0.03), M['dark_metal'], C, parent=root, segments=8)

# ---------------------------------------------------------------------------
# Intérieur sommaire : on le voit par les vitres
# ---------------------------------------------------------------------------
def interior(X):
    M, C = X.M, X.col
    L.box("POL_Floor", (1.42, 2.40, 0.02), (0, -0.25, 0.44), M['interior'], C, smooth=False)
    L.box("POL_Firewall", (1.42, 0.02, 0.50), (0, 0.95, 0.68), M['interior'], C, smooth=False)
    L.box("POL_Dash", (1.46, 0.42, 0.22), (0, 0.76, 0.83), M['interior'], C, bevel=0.04, segs=4)
    L.box("POL_Console", (0.22, 0.70, 0.16), (0, 0.20, 0.52), M['interior'], C, bevel=0.02)
    # Dossiers inclinés vers l'ARRIÈRE : rot X positive = le haut part vers -Y (une valeur négative les faisait
    # pencher vers le pare-brise — « les fauteuils sont à l'envers »).
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"POL_Seat_{nm}_Cushion", (0.48, 0.50, 0.12), (s*0.36, -0.05, 0.52), M['seat'], C, bevel=0.03, segs=4)
        L.box(f"POL_Seat_{nm}_Back", (0.48, 0.10, 0.60), (s*0.36, -0.34, 0.86), M['seat'], C, rot=(14, 0, 0), bevel=0.03, segs=4)
        L.box(f"POL_Seat_{nm}_Headrest", (0.24, 0.09, 0.16), (s*0.36, -0.43, 1.22), M['seat'], C, rot=(14, 0, 0), bevel=0.03, segs=4)
    L.box("POL_Bench_Cushion", (1.40, 0.50, 0.12), (0, -0.95, 0.52), M['seat'], C, bevel=0.03, segs=4)
    L.box("POL_Bench_Back", (1.40, 0.08, 0.44), (0, -1.24, 0.765), M['seat'], C, rot=(18, 0, 0), bevel=0.03, segs=4)   # haut sous la plage arrière
    L.box("POL_Shelf", (1.44, 0.34, 0.02), (0, -1.30, 0.985), M['interior'], C, smooth=False)
    L.torus("POL_SteeringWheel", 0.19, 0.016, (-0.36, 0.44, 0.86), M['interior'], C, rot=(65, 0, 0))
    L.cyl("POL_SteeringHub", 0.05, 0.05, (-0.36, 0.44, 0.86), M['interior'], C, rot=(65, 0, 0), segments=16)
    L.cyl_between("POL_SteeringColumn", (-0.36, 0.47, 0.85), (-0.36, 0.78, 0.76), 0.025, M['interior'], C, segments=12)

# ---------------------------------------------------------------------------
# Scène de rendu (non exportée)
# ---------------------------------------------------------------------------
def env_scene(X):
    E = X.env
    L.cyl("ENV_Ground", 16.0, 0.02, (0, 0, -0.01), X.M['asphalt'], E, segments=64)
    tgt = (0.0, 0.0, 0.7)
    for name, energy, size, color, loc in (("ENV_Key", 2200.0, 3.0, (1.0, 0.95, 0.88), (5.0, 5.5, 4.5)),
                                           ("ENV_Fill", 900.0, 5.0, (0.82, 0.88, 1.0), (-6.0, 2.0, 3.0)),
                                           ("ENV_Rim", 1200.0, 2.5, (1.0, 1.0, 1.0), (-3.0, -7.0, 4.0))):
        l = bpy.data.lights.new(name, 'AREA'); l.energy = energy; l.size = size; l.color = color
        ob = bpy.data.objects.new(name, l); L.link_obj(ob, E); ob.location = loc; L.aim(ob, tgt)
    L.camera("CAM_Front34", (4.9, 5.6, 1.9), (0.0, 0.2, 0.68), 40, E, clip_start=0.05)
    L.camera("CAM_Rear34", (-4.9, -5.4, 1.8), (0.0, -0.3, 0.68), 40, E, clip_start=0.05)
    L.camera("CAM_Side", (7.4, 0.0, 1.0), (0.0, 0.0, 0.66), 50, E, clip_start=0.05)
    L.camera("CAM_Bar", (2.3, 1.9, 2.6), (0.0, 0.05, 1.40), 60, E, clip_start=0.05)
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1400, 800
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 64; scene.cycles.use_denoising = True
    scene.world = scene.world or bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = L.node_of(scene.world.node_tree, 'ShaderNodeBackground'); bg.inputs[0].default_value = (0.25, 0.28, 0.35, 1.0); bg.inputs[1].default_value = 0.6

VIEWS = [("CAM_Front34", "police_front34.png", []), ("CAM_Rear34", "police_rear34.png", []), ("CAM_Side", "police_side.png", []), ("CAM_Bar", "police_bar.png", [])]

def stats(col):
    """Triangles après modificateurs, et objets dont des sommets sortent du gabarit (épines, sommets projetés)."""
    bpy.context.view_layer.update(); dg = bpy.context.evaluated_depsgraph_get(); n = 0; out = {}
    for ob in col.all_objects:
        if ob.type != 'MESH' or ob.name.startswith(("CUT_", "ENV_")): continue
        ev = ob.evaluated_get(dg); me = ev.to_mesh(); n += sum(len(p.vertices) - 2 for p in me.polygons)
        for v in me.vertices:
            p = ob.matrix_world @ v.co
            if abs(p.x) > 1.05 or p.y > NOSE + 0.05 or p.y < TAIL - 0.05 or p.z > 2.0 or p.z < -0.01: out[ob.name] = out.get(ob.name, 0) + 1
        ev.to_mesh_clear()
    return n, out

def build():
    X = Ctx()
    body_shell(X); wheel_arches(X); glazing(X); livery(X)
    front(X); rear(X); sides(X); light_bar(X); wheels(X); interior(X); env_scene(X)
    L.hide_cutters(CUTTERS)
    tris, out = stats(X.col)
    print("Police car built:", len(X.col.all_objects), "objects,", tris, "tris")
    if out: print("HORS GABARIT (sommets au-delà de la caisse) :", out)
    return X

def main(export=True, render=True, save=True, views=None, pct=100):
    for ob in list(bpy.data.objects):                       # scène par défaut (Cube, Light, Camera)
        if ob.name in ("Cube", "Light", "Camera"): bpy.data.objects.remove(ob, do_unlink=True)
    X = build()
    if export:
        os.makedirs(MODELS, exist_ok=True)
        n, mb = L.export_glb(COL, os.path.join(MODELS, "police_car.glb")); print(f"export police_car.glb : {n} objets, {mb} Mo")
        L.hide_cutters(CUTTERS)
    if render:
        print("rendus :", L.render_views(views or VIEWS, RENDERS, pct=pct))
    if save: L.save_blend(os.path.join(_HERE, "police_car.blend"))

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    quick = [v for v in VIEWS if v[0] in ("CAM_Front34", "CAM_Bar")] if "--quick" in args else None
    main(export="--no-export" not in args, render="--no-render" not in args, save="--no-save" not in args,
         views=quick, pct=int(next((a.split("=")[1] for a in args if a.startswith("--pct=")), 100)))
