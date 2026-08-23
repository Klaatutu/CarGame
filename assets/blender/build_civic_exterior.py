# -*- coding: utf-8 -*-
"""
build_civic_exterior — carrosserie de la Honda Civic EF 3 portes (collection "Civic_Exterior").

Carrosserie = UNE coque fermée (loft de sections de 41 points : capot, pare-brise, pavillon, hayon,
flancs, dessous), subdivisée, épaissie (Solidify 12 mm, face interne en apprêt), puis découpée par
booléen : passages de roue + baies vitrées (contours partagés avec l'intérieur, civic_dims). Les
montants A, B, C sont la tôle qui reste entre les découpes ; chaque vitre = panneau + joint plat noir.
Les découpeurs (CUT_*) et le sol (ENV_*) ne sont pas exportés.
"""
import bpy, math, os, sys
_HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
if _HERE not in sys.path: sys.path.insert(0, _HERE)
import civic_lib as L
import civic_dims as D
import civic_materials as MATS
from mathutils import Vector, Matrix

ROOT = "Civic_Exterior"; CUTTERS = "Exterior_Cutters"

class Ctx:
    def __init__(self):
        L.clear_collection(ROOT)
        self.col = L.get_col(ROOT); self.cut = L.get_col(CUTTERS, self.col); self.M = MATS.exterior()

# ============================================================================
# Coque : demi-section = 5 pts de dessus + 3 pts de flanc haut + 13 pts de flanc bas (21 pts, le dernier au centre)
# ============================================================================
LOWER_CAB = [(0.806, 0.96), (0.822, 0.90), (0.834, 0.82), (0.8375, 0.72), (0.834, 0.62), (0.822, 0.54), (0.802, 0.478), (0.772, 0.462), (0.758, 0.40),
             (0.738, 0.33), (0.68, 0.26), (0.50, 0.215), (0.0, 0.21)]
HOOD_HALF = [(0.0, 0.915), (0.26, 0.911), (0.50, 0.898), (0.70, 0.872), (0.80, 0.822), (0.822, 0.81), (0.832, 0.80), (0.836, 0.79),
             (0.8375, 0.77), (0.836, 0.75), (0.8375, 0.72), (0.8375, 0.68), (0.834, 0.62), (0.822, 0.54), (0.802, 0.478), (0.772, 0.462), (0.758, 0.40),
             (0.738, 0.33), (0.68, 0.26), (0.50, 0.215), (0.0, 0.21)]
CROWN = {'ws': (0.004, 0.012, 0.022, 0.04), 'roof': (0.008, 0.028, 0.055, 0.08), 'hatch': (0.005, 0.015, 0.03, 0.06)}

def side_x_low(z):
    for i in range(len(LOWER_CAB) - 1):
        (x0, z0), (x1, z1) = LOWER_CAB[i], LOWER_CAB[i+1]
        if z1 <= z <= z0: return x0 + (x1 - x0)*(z0 - z)/(z0 - z1)
    return LOWER_CAB[-1][0] if z < LOWER_CAB[-1][1] else LOWER_CAB[0][0]

def half_profile(kind, zt, w, zb, belt):
    if kind in ('hood', 'tail'):
        pts = [(x*(w/D.HALF_W), zb + (z - 0.21)*(zt - zb)/(0.915 - 0.21)) for (x, z) in HOOD_HALF]
    else:
        c = CROWN[kind]; xe = 0.785 if kind == 'ws' else 0.79
        top = [(0.0, zt), (0.30, zt - c[0]), (0.55, zt - c[1]), (0.70, zt - c[2]), (xe, zt - c[3])]
        ze = zt - c[3]; belt_eff = min(belt, ze - 0.03)      # profil monotone : pas de pli (sinon épines après subdivision + épaisseur)
        side = []
        for f in (0.25, 0.55, 0.85):
            z = ze - (ze - belt_eff)*f; side.append((D.x_side(z) if z > 0.975 else 0.818, z))
        lower = [(x, z - (0.97 - belt_eff)*max(0.0, min(1.0, (z - 0.72)/0.25))) for (x, z) in LOWER_CAB]
        pts = top + side + lower
    assert len(pts) == 21, len(pts)
    return pts

def ring(y, kind, zt, w, zb, belt=D.BELT):
    pts = half_profile(kind, zt, w, zb, belt)
    return [(-x, y, z) for (x, z) in pts] + [(x, y, z) for (x, z) in reversed(pts[1:-1])]     # 40 points fermés

STATIONS = [
    (1.995, 'hood', 0.50, 0.22, 0.42), (1.985, 'hood', 0.58, 0.55, 0.37), (1.965, 'hood', 0.67, 0.68, 0.33), (1.945, 'hood', 0.76, 0.73, 0.30),
    (1.90, 'hood', 0.79, 0.78, 0.26), (1.80, 'hood', 0.818, 0.815, 0.23), (1.60, 'hood', 0.852, D.HALF_W, 0.21), (1.35, 'hood', 0.878, D.HALF_W, 0.21),
    (1.10, 'hood', 0.898, D.HALF_W, 0.21), (0.96, 'hood', 0.912, D.HALF_W, 0.21),
    (0.92, 'ws', D.z_ws(0.92), D.HALF_W, 0.21), (0.84, 'ws', D.z_ws(0.84), D.HALF_W, 0.21), (0.70, 'ws', D.z_ws(0.70), D.HALF_W, 0.21),
    (0.55, 'ws', D.z_ws(0.55), D.HALF_W, 0.21), (0.42, 'ws', D.z_ws(0.42), D.HALF_W, 0.21), (0.34, 'ws', D.HEADER_Z_OUT + 0.02, D.HALF_W, 0.21),
    (0.26, 'roof', D.ROOF_OUT - 0.008, D.HALF_W, 0.21), (0.10, 'roof', D.ROOF_OUT, D.HALF_W, 0.21), (-0.15, 'roof', D.ROOF_OUT, D.HALF_W, 0.21),
    (-0.45, 'roof', D.ROOF_OUT, D.HALF_W, 0.21), (-0.75, 'roof', D.ROOF_OUT - 0.003, D.HALF_W, 0.21), (-1.00, 'roof', D.ROOF_OUT - 0.012, D.HALF_W, 0.21),
    (-1.08, 'hatch', D.HATCH_Z1_OUT, D.HALF_W, 0.21), (-1.25, 'hatch', D.z_hatch(-1.25), D.HALF_W, 0.21), (-1.45, 'hatch', D.z_hatch(-1.45), D.HALF_W, 0.21),
    (-1.65, 'hatch', D.z_hatch(-1.65), 0.832, 0.21), (-1.82, 'hatch', D.HATCH_Z0_OUT, 0.81, 0.22),
    (-1.88, 'tail', 0.88, 0.79, 0.23), (-1.93, 'tail', 0.78, 0.76, 0.26), (-1.96, 'tail', 0.68, 0.71, 0.31), (-1.98, 'tail', 0.60, 0.62, 0.36), (-1.995, 'tail', 0.50, 0.25, 0.42),
]
def belt_for(y):     # devant la porte, le haut du flanc redescend vers l'auvent (aile avant)
    return D.BELT - 0.065*L.smoothstep(0.80, 0.92, y)

def body_shell(X):
    rings = [ring(y, k, zt, w, zb, belt_for(y)) for (y, k, zt, w, zb) in STATIONS]
    body = L.loft("EXT_Body", rings, [X.M['paint'], X.M['inner']], X.col, creases=[(8, 0.75), (32, 0.75), (4, 0.5), (36, 0.5), (14, 0.7), (26, 0.7), (15, 0.4), (25, 0.4)])
    L.add_solidify(body, 0.012)
    L.add_boolean_collection(body, X.cut)
    return body

def prism(X, name, outline, d, ext=0.12):
    d = Vector(d).normalized()
    ob = L.loft(name, [[tuple(Vector(p) - d*ext) for p in outline], [tuple(Vector(p) + d*ext) for p in outline]], None, X.cut, closed=True, caps=True, subsurf=0, smooth=False)
    ob.display_type = 'WIRE'; ob.hide_render = True; return ob

def wheel_arches(X):
    M = X.M
    for y, tag in ((D.AXLE_F, "F"), (D.AXLE_R, "R")):
        for s, nm in ((-1, "L"), (1, "R")):
            cut = L.cyl(f"CUT_Arch_{tag}{nm}", 0.40, 0.70, (s*0.87, y, D.WHEEL_R + 0.02), None, X.cut, rot=(0, 90, 0), segments=48, smooth=False)
            cut.display_type = 'WIRE'; cut.hide_render = True
            angs = [-10 + 200*k/15 for k in range(16)]
            zc = lambda a: D.WHEEL_R + 0.02 + 0.405*math.sin(math.radians(a))
            outer = [(s*(side_x_low(zc(a)) - 0.006), y + 0.405*math.cos(math.radians(a)), zc(a)) for a in angs]
            mid = [(s*0.52, y + 0.405*math.cos(math.radians(a)), zc(a)) for a in angs]
            inner = [(s*0.52, y + 0.10*math.cos(math.radians(a)), D.WHEEL_R + 0.02 + 0.10*math.sin(math.radians(a))) for a in angs]
            L.loft(f"EXT_WheelWell_{tag}{nm}", [outer, mid, inner], M['well'], X.col, closed=False, caps=False, subsurf=1)
            lip = [(s*(side_x_low(D.WHEEL_R + 0.02 + 0.40*math.sin(math.radians(a))) + 0.006), y + 0.40*math.cos(math.radians(a)), D.WHEEL_R + 0.02 + 0.40*math.sin(math.radians(a))) for a in [-8 + 196*k/22 for k in range(23)]]
            L.tube_along(f"EXT_ArchLip_{tag}{nm}", lip, 0.009, M['paint'], X.col, n=8, subsurf=1)

def glazing(X):
    """Découpes des baies + vitres + joints plats + montant B noir + gouttières + baguettes de ceinture."""
    M = X.M
    for s, nm in ((-1, "L"), (1, "R")):
        prism(X, f"CUT_DoorWin_{nm}", [(s*0.80, y, z) for (y, z) in D.DOOR_WIN], (s, 0, 0), 0.14)
        prism(X, f"CUT_QtrWin_{nm}", [(s*0.80, y, z) for (y, z) in D.QTR_WIN], (s, 0, 0), 0.14)
    prism(X, "CUT_Windshield", D.WS_WIN, D.WS_N, 0.10); prism(X, "CUT_Hatch", D.HATCH_WIN, D.HATCH_N, 0.10)
    def band_side(name, s, outline, width=0.022, lip=0.012):
        o = [(s*(D.x_side(z) + 0.004), y, z) for (y, z) in L.offset_outline(outline, lip)]
        i = [(s*(D.x_side(z) + 0.004), y, z) for (y, z) in L.offset_outline(outline, lip - width)]
        return L.band(name, o, i, M['black'], X.col)
    def band_plane(name, outline3d, n, width=0.024, lip=0.012):
        return L.band(name, L.offset_outline3d(outline3d, lip, n, 0.004), L.offset_outline3d(outline3d, lip - width, n, 0.004), M['black'], X.col)
    for s, nm in ((-1, "L"), (1, "R")):
        L.polygon(f"EXT_DoorGlass_{nm}", D.side_glass_pts(s, D.DOOR_WIN, 0.003), M['glass'], X.col)
        L.polygon(f"EXT_QtrGlass_{nm}", D.side_glass_pts(s, D.QTR_WIN, 0.003), M['glass'], X.col)
        band_side(f"EXT_DoorWinSeal_{nm}", s, D.DOOR_WIN); band_side(f"EXT_QtrWinSeal_{nm}", s, D.QTR_WIN)
        pts = [(s*(D.x_side(z) + 0.005), y, z) for (y, z) in ((D.DOOR_Y_REAR + 0.005, 0.975), (D.DOOR_Y_REAR + 0.005, 1.245), (D.DOOR_Y_REAR - 0.07, 1.245), (D.DOOR_Y_REAR - 0.07, 0.975))]
        L.polygon(f"EXT_PillarB_Black_{nm}", pts if s > 0 else list(reversed(pts)), M['black'], X.col)
        L.tube_along(f"EXT_Gutter_{nm}", [(s*0.793, 0.36, D.ROOF_EDGE + 0.004), (s*0.793, -0.40, D.ROOF_EDGE + 0.006), (s*0.793, -1.09, D.ROOF_EDGE + 0.004)], 0.006, M['black'], X.col)
        L.box(f"EXT_BeltMolding_{nm}", (0.008, 2.46, 0.018), (s*0.823, -0.38, D.BELT + 0.004), M['black'], X.col, bevel=0.002)
    L.polygon("EXT_WindshieldGlass", D.plane_glass_pts(D.WS_WIN, D.WS_N, 0.003), M['glass'], X.col)
    L.polygon("EXT_HatchGlass", D.plane_glass_pts(D.HATCH_WIN, D.HATCH_N, 0.003), M['glass'], X.col)
    band_plane("EXT_WindshieldSeal", D.WS_WIN, D.WS_N); band_plane("EXT_HatchSeal", D.HATCH_WIN, D.HATCH_N)

# ============================================================================
# Faces avant / arrière
# ============================================================================
def front(X):
    M, C = X.M, X.col; FR = (14, 0, 0)
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"EXT_Headlight_{nm}_Housing", (0.36, 0.04, 0.11), (s*0.47, 1.95, 0.70), M['black'], C, rot=FR, bevel=0.004)
        L.box(f"EXT_Headlight_{nm}_Reflector", (0.34, 0.02, 0.095), (s*0.47, 1.957, 0.703), M['reflector'], C, rot=FR)
        L.box(f"EXT_Headlight_{nm}_Lens", (0.35, 0.008, 0.10), (s*0.47, 1.973, 0.708), M['headlight'], C, rot=FR, bevel=0.002)
        L.box(f"EXT_TurnSignal_{nm}", (0.14, 0.03, 0.065), (s*0.62, 1.965, 0.56), M['amber'], C, rot=(14, 0, s*25), bevel=0.004)
    L.box("EXT_Grille", (0.54, 0.03, 0.045), (0, 1.965, 0.72), M['black'], C, rot=FR, bevel=0.004)
    for i in range(3): L.box(f"EXT_GrilleBar{i}", (0.50, 0.012, 0.006), (0, 1.978, 0.705 + 0.014*i), M['black'], C, rot=FR)
    for nm, size, loc in (("EXT_Logo_L", (0.006, 0.005, 0.026), (-0.012, 1.985, 0.72)), ("EXT_Logo_R", (0.006, 0.005, 0.026), (0.012, 1.985, 0.72)), ("EXT_Logo_Bar", (0.018, 0.005, 0.006), (0, 1.985, 0.72))):
        L.box(nm, size, loc, M['chrome'], C, rot=FR)
    L.box("EXT_FrontBumperStrip", (1.06, 0.025, 0.045), (0, 1.982, 0.50), M['black'], C, bevel=0.006)
    L.box("EXT_FrontAirDam", (1.10, 0.03, 0.06), (0, 1.93, 0.33), M['black'], C, bevel=0.006)
    L.box("EXT_FrontPlate", (0.50, 0.008, 0.11), (0, 1.992, 0.44), M['plate'], C, bevel=0.002)
    ws_on = lambda x, v, h=0.012: tuple(Vector(D.ws_pt(x, v)) + D.WS_N*h)
    for nm, px, b0, b1 in (("L", -0.36, (-0.68, 0.03), (-0.20, 0.115)), ("R", 0.20, (-0.14, 0.045), (0.34, 0.12))):
        L.cyl(f"EXT_WiperPivot_{nm}", 0.012, 0.03, (px, 0.925, 0.925), M['black'], C, rot=(-31, 0, 0), segments=16)
        mid = ((b0[0] + b1[0])*0.5, (b0[1] + b1[1])*0.5)
        L.cyl_between(f"EXT_WiperArm_{nm}", (px, 0.925, 0.935), ws_on(mid[0], mid[1], 0.02), 0.005, M['black'], C, segments=10)
        L.cyl_between(f"EXT_WiperBlade_{nm}", ws_on(*b0), ws_on(*b1), 0.0065, M['black'], C, segments=10)

def rear(X):
    M, C = X.M, X.col; RR = (-22, 0, 0)
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"EXT_TailLight_{nm}_Housing", (0.40, 0.03, 0.17), (s*0.52, -1.955, 0.745), M['black'], C, rot=RR, bevel=0.004)
        L.box(f"EXT_TailLight_{nm}_Red", (0.22, 0.012, 0.15), (s*0.47, -1.967, 0.745), M['red'], C, rot=RR, bevel=0.002)
        L.box(f"EXT_TailLight_{nm}_Amber", (0.10, 0.012, 0.15), (s*0.645, -1.967, 0.745), M['amber'], C, rot=RR, bevel=0.002)
        L.box(f"EXT_TailLight_{nm}_Reverse", (0.06, 0.012, 0.15), (s*0.33, -1.967, 0.745), M['white_lens'], C, rot=RR, bevel=0.002)
    L.box("EXT_RearPlateRecess", (0.54, 0.02, 0.16), (0, -1.95, 0.735), M['black'], C, rot=RR, bevel=0.004)
    L.box("EXT_RearPlate", (0.50, 0.006, 0.11), (0, -1.963, 0.735), M['plate'], C, rot=RR, bevel=0.002)
    L.box("EXT_RearBumperStrip", (1.06, 0.025, 0.045), (0, -1.982, 0.50), M['black'], C, bevel=0.006)
    L.box("EXT_HatchHandle", (0.14, 0.02, 0.03), (0, -1.93, 0.885), M['black'], C, rot=RR, bevel=0.005)
    L.cyl("EXT_HatchLock", 0.011, 0.01, (0.12, -1.935, 0.885), M['chrome'], C, rot=(68, 0, 0), segments=20)
    L.cyl_between("EXT_Exhaust", (0.36, -1.70, 0.27), (0.36, -2.0, 0.27), 0.022, M['dark_metal'], C, segments=20)
    hatch_on = lambda x, v, h=0.012: tuple(Vector(D.hatch_pt(x, v)) + D.HATCH_N*h)
    L.cyl("EXT_RearWiperPivot", 0.012, 0.03, hatch_on(0.12, -0.02, 0.0), M['black'], C, rot=(27, 0, 0), segments=16)
    L.cyl_between("EXT_RearWiperArm", hatch_on(0.12, -0.02, 0.012), hatch_on(0.04, 0.06, 0.022), 0.005, M['black'], C, segments=10)
    L.cyl_between("EXT_RearWiperBlade", hatch_on(-0.18, 0.035), hatch_on(0.26, 0.085), 0.0065, M['black'], C, segments=10)
    L.box("EXT_ThirdBrakeLight", (0.22, 0.025, 0.03), (0, -1.045, D.ROOF_OUT - 0.02), M['red'], C, rot=(20, 0, 0), bevel=0.003)

# ============================================================================
# Côtés : poignées, rétroviseurs, baguettes, lignes de panneaux, trappe, antenne
# ============================================================================
def sides(X):
    M, C = X.M, X.col
    for s, nm in ((-1, "L"), (1, "R")):
        L.box(f"EXT_DoorHandle_{nm}", (0.02, 0.13, 0.036), (s*(side_x_low(0.90) + 0.004), -0.42, 0.90), M['black'], C, bevel=0.006)
        L.cyl(f"EXT_DoorLock_{nm}", 0.009, 0.006, (s*(side_x_low(0.90) + 0.004), -0.30, 0.90), M['chrome'], C, rot=(0, 90, 0), segments=20)
        mirror(X, s, nm)
        L.box(f"EXT_SideMolding_{nm}", (0.012, 3.10, 0.03), (s*(D.HALF_W + 0.004), 0.05, 0.70), M['black'], C, bevel=0.003)
        for y, tag in ((D.DOOR_Y_FRONT, "Front"), (D.DOOR_Y_REAR, "Rear")):
            L.tube_along(f"EXT_Seam_Door{tag}_{nm}", [(s*(side_x_low(z) + 0.003), y, z) for z in (0.965, 0.90, 0.80, 0.70, 0.60, 0.52, 0.47)], 0.0035, M['black'], C, n=6, subsurf=0)
        hood_edge = [(s*(-ring(*st)[4][0]) + s*0.003, st[0], ring(*st)[4][2] + 0.003) for st in STATIONS if 0.92 <= st[0] <= 1.945 and st[1] == 'hood']
        if hood_edge: L.tube_along(f"EXT_Seam_Hood_{nm}", hood_edge, 0.0035, M['black'], C, n=6, subsurf=0)
        L.tube_along(f"EXT_Seam_Hatch_{nm}", [(s*0.70, -1.86, 0.905), (s*0.72, -1.905, 0.80), (s*0.715, -1.955, 0.66)], 0.0035, M['black'], C, n=6, subsurf=0)
    for nm, size, loc in (("EXT_FuelDoor_T", (0.004, 0.16, 0.004), (-0.831, -1.52, 0.90)), ("EXT_FuelDoor_B", (0.004, 0.16, 0.004), (-0.836, -1.52, 0.74)),
                          ("EXT_FuelDoor_F", (0.004, 0.004, 0.16), (-0.834, -1.44, 0.82)), ("EXT_FuelDoor_R", (0.004, 0.004, 0.16), (-0.834, -1.60, 0.82))):
        L.box(nm, size, loc, M['black'], C, smooth=False)
    L.cyl_between("EXT_Antenna", (0.74, 1.36, 0.87), (0.78, 1.16, 1.55), 0.004, M['chrome'], C, segments=8)
    L.cyl("EXT_AntennaBase", 0.014, 0.02, (0.74, 1.36, 0.865), M['black'], C, segments=16)

def mirror(X, s, nm):
    """Coque creuse (sections XZ en rectangle arrondi, nez avant -> rebord arrière -> lèvre rentrante), glace en retrait, pincée de 8° vers le conducteur."""
    M, C = X.M, X.col
    root = L.empty(f"EXT_MirrorRoot_{nm}", (s*0.925, 0.70, 1.03), C, rot=(0, 0, -s*8))
    def rrect(y, sx, sz, n=16):
        return [(sx*math.copysign(abs(math.cos(t))**0.67, math.cos(t)), y, sz*math.copysign(abs(math.sin(t))**0.67, math.sin(t))) for t in [2*math.pi*k/n for k in range(n)]]
    secs = [rrect(0.093, 0.004, 0.003), rrect(0.088, 0.03, 0.018), rrect(0.075, 0.065, 0.042), rrect(0.045, 0.082, 0.052), rrect(0.0, 0.086, 0.054), rrect(-0.045, 0.086, 0.054),
            rrect(-0.068, 0.083, 0.052), rrect(-0.074, 0.074, 0.046), rrect(-0.052, 0.072, 0.045)]
    L.loft(f"EXT_Mirror_{nm}", secs, M['black'], C, parent=root, caps=False)
    L.polygon(f"EXT_MirrorGlass_{nm}", [(x, -0.062, z) for (x, y, z) in rrect(0.0, 0.0715, 0.0445, 24)], M['chrome'], C, parent=root)
    L.box(f"EXT_MirrorBase_{nm}", (0.07, 0.075, 0.03), (s*0.85, 0.74, 0.995), M['black'], C, bevel=0.006)
    L.cyl_between(f"EXT_MirrorArm_{nm}", (s*0.845, 0.73, 1.0), (s*0.88, 0.705, 1.02), 0.013, M['black'], C, segments=12)

# ============================================================================
# Roues
# ============================================================================
TIRE_PROF = [(0.17, -0.095), (0.25, -0.095), (0.275, -0.085), (0.287, -0.06), (0.29, -0.03), (0.29, 0.03), (0.287, 0.06), (0.275, 0.085), (0.25, 0.095), (0.17, 0.095), (0.17, -0.095)]
RIM_PROF = [(0.0, 0.035), (0.05, 0.04), (0.10, 0.03), (0.15, 0.015), (0.172, 0.0), (0.178, -0.03), (0.178, -0.09), (0.165, -0.095), (0.0, -0.095)]

def wheels(X):
    M, C = X.M, X.col
    for y, tag in ((D.AXLE_F, "F"), (D.AXLE_R, "R")):
        for s, nm in ((-1, "L"), (1, "R")):
            root = L.empty(f"EXT_Wheel_{tag}{nm}", (s*D.WHEEL_X, y, D.WHEEL_R), C, rot=(0, s*90, 0))     # +Z local = vers l'extérieur
            L.lathe(f"EXT_Tire_{tag}{nm}", TIRE_PROF, M['tire'], C, parent=root, steps=48, subsurf=1)
            L.lathe(f"EXT_Rim_{tag}{nm}", RIM_PROF, M['rim'], C, parent=root, steps=40, subsurf=1)
            for i in range(5):
                a = 72*i
                L.box(f"EXT_Spoke_{tag}{nm}{i}", (0.034, 0.12, 0.018), (0.105*math.sin(math.radians(a)), 0.105*math.cos(math.radians(a)), 0.032), M['rim'], C, rot=(0, 0, -a), bevel=0.003, parent=root)
            L.lathe(f"EXT_Hub_{tag}{nm}", [(0.0, 0.055), (0.03, 0.052), (0.045, 0.04), (0.048, 0.03), (0.0, 0.03)], M['chrome'], C, parent=root, steps=32, subsurf=1)
            for i in range(4):
                a = math.radians(45 + 90*i)
                L.cyl(f"EXT_LugNut_{tag}{nm}{i}", 0.008, 0.01, (0.065*math.sin(a), 0.065*math.cos(a), 0.048), M['dark_metal'], C, parent=root, segments=8)

def env_cameras(X):
    L.cyl("ENV_Ground", 14.0, 0.02, (0, 0, -0.01), X.M['asphalt'], X.col, segments=64)
    L.camera("CAM_ExtFront34", (3.6, 3.4, 1.45), (0.0, 0.15, 0.62), 42, X.col, clip_start=0.05)
    L.camera("CAM_ExtRear34", (-3.5, -3.4, 1.4), (0.0, -0.25, 0.62), 42, X.col, clip_start=0.05)
    L.camera("CAM_ExtSide", (5.2, 0.0, 0.95), (0.0, 0.0, 0.62), 50, X.col, clip_start=0.05)

def build():
    X = Ctx()
    body_shell(X); wheel_arches(X); glazing(X)
    front(X); rear(X); sides(X); wheels(X); env_cameras(X)
    L.hide_cutters(CUTTERS)
    n = len(X.col.all_objects); print("Exterior built:", n, "objects"); return n

if __name__ == "__main__":
    build()
