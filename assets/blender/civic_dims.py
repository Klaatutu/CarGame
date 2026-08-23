# -*- coding: utf-8 -*-
"""
civic_dims — toutes les cotes partagées de la Honda Civic EF (1990, 3 portes).

Repère Blender : sol Z = 0, milieu de la voiture Y = 0, AVANT = +Y, conducteur à gauche (-X).
Export glTF -> Godot : (x, y, z)_Blender -> (x, z, -y)_Godot (avant = -Z), identique à scripts/cabin.gd.
Les valeurs marquées [cabin.gd] / [driver.gd] / [car.gd] viennent du jeu et ne doivent pas bouger
sans mettre à jour le code GDScript.
"""
import math
from mathutils import Vector

# ---------------------------------------------------------------------------
# Caisse [cabin.gd]
# ---------------------------------------------------------------------------
FLOOR      = 0.33            # dessus du plancher
HALF_W     = 0.8375          # demi-largeur hors tout (1675 mm)
BELT       = 0.97            # ceinture de caisse
SILL       = 0.47            # bas de caisse
ROOF_IN    = 1.295           # dessous du ciel de toit
ROOF_OUT   = 1.345           # peau extérieure du pavillon (1340 mm hors tout)
ROOF_EDGE  = 1.265           # bord du pavillon / gouttière
ROOF_BACK  = -1.06           # fin du pavillon
NOSE, TAIL = 1.98, -1.98
AXLE_F, AXLE_R = 1.18, -1.32
WHEEL_R    = 0.29
WHEEL_X    = HALF_W - 0.10   # axe des roues en X
COWL_Y, COWL_Z_IN, COWL_Z_OUT = 0.92, 0.93, 0.94          # bas du pare-brise (int / ext)
HEADER_Y, HEADER_Z_IN, HEADER_Z_OUT = 0.34, 1.28, 1.29    # haut du pare-brise (int / ext)
HATCH_Y0, HATCH_Z0_IN, HATCH_Z0_OUT = -1.82, 0.92, 0.935  # bas de lunette
HATCH_Y1, HATCH_Z1_IN, HATCH_Z1_OUT = -1.08, 1.295, 1.31  # haut de lunette

# ---------------------------------------------------------------------------
# Habitacle (choix validés avec l'utilisateur)
# ---------------------------------------------------------------------------
SEAT_X     = -0.33           # axe du siège conducteur [cabin.gd]
SEAT_Y     = -0.28           # centre de l'assise (cabin.gd : -0.24, reculé de 4 cm)
DASH_BOT   = 0.62            # bas de la planche de bord
DOOR_X     = 0.73            # face intérieure des contre-portes
DOOR_Y_FRONT, DOOR_Y_REAR = 0.66, -0.60   # porte 3 portes : 1,26 m à la ceinture
PILLAR_B_Y = DOOR_Y_REAR - 0.03
WIN_TOP    = 1.235           # haut des vitres latérales (3 cm sous le bord de toit)

# ---------------------------------------------------------------------------
# Poste de conduite [driver.gd] (Godot -> Blender)
# ---------------------------------------------------------------------------
WHEEL_C    = Vector((SEAT_X, 0.38, 0.78)); WHEEL_TILT = 68.0; WHEEL_RADIUS = 0.18
LEVER_BASE = Vector((0.0, 0.30, 0.58)); LEVER_LEN = 0.22
HB_BASE    = Vector((0.0, -0.18, 0.46)); HB_LEN = 0.26; HB_DOWN = 62.0
HB_FORWARD = True            # True : pivot arrière, levier qui monte vers l'avant (convention driver.gd)
SHOULDER_L = Vector((SEAT_X - 0.185, 0.95, 0.18)); SHOULDER_R = Vector((SEAT_X + 0.185, 0.95, 0.18))   # repère Godot
UPPER_ARM, FOREARM = 0.30, 0.28                  # = driver.gd (REST_LEN et IK) : bras 30 cm, avant-bras 28 cm
COLUMN_PULL = 0.02                                # = cabin.gd : la colonne de direction est ramenée vers le conducteur (repère Godot, +z)
SPINE  = Vector((SEAT_X, 0.0, 0.36))                                   # repère Godot
HIP_L, HIP_R   = Vector((SEAT_X - 0.12, 0.50, 0.30)), Vector((SEAT_X + 0.12, 0.50, 0.30))
KNEE_L, KNEE_R = Vector((SEAT_X - 0.13, 0.48, -0.20)), Vector((SEAT_X + 0.12, 0.48, -0.20))
ANKLE_L, ANKLE_R = Vector((SEAT_X - 0.19, 0.40, -0.66)), Vector((SEAT_X + 0.09, 0.40, -0.68))
HEAD_POS = Vector((SEAT_X, 1.15, 0.10))                                # [car.gd] œil, repère Godot
PEDAL_Y = 0.84; PEDALS = dict(Accel=SEAT_X + 0.09, Brake=SEAT_X - 0.06, Clutch=SEAT_X - 0.19)   # [cabin.gd]
THIGH_LEN, SHIN_LEN = 0.50, 0.48

PAINT = (0.10, 0.10, 0.11)   # gris anthracite métallisé

# ---------------------------------------------------------------------------
# Godot <-> Blender
# ---------------------------------------------------------------------------
def g2b(v):
    """Vecteur Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))

# ---------------------------------------------------------------------------
# Vitrage : contours définis UNE fois, partagés par l'intérieur et l'extérieur
# ---------------------------------------------------------------------------
def z_ws(y):
    """Peau extérieure du pare-brise à la longueur y."""
    return COWL_Z_OUT + (COWL_Y - y)/(COWL_Y - HEADER_Y)*(HEADER_Z_OUT - COWL_Z_OUT)

def z_hatch(y):
    """Peau extérieure de la lunette à la longueur y."""
    return HATCH_Z0_OUT + (y - HATCH_Y0)/(HATCH_Y1 - HATCH_Y0)*(HATCH_Z1_OUT - HATCH_Z0_OUT)

def pillar_y(z):
    """Ligne du montant A dans le plan YZ (du bas de pare-brise au bandeau)."""
    z0, z1 = COWL_Z_OUT - 0.01, HEADER_Z_OUT
    return COWL_Y - (z - z0)/(z1 - z0)*(COWL_Y - HEADER_Y)

def x_side(z):
    """Demi-largeur du flanc vitré (tumblehome) entre la ceinture et le bord du pavillon."""
    return 0.818 - 0.065*max(0.0, z - 0.975)

WS_N = Vector((0, HEADER_Z_OUT - COWL_Z_OUT, COWL_Y - HEADER_Y)).normalized()        # normale du pare-brise (extérieur)
WS_S = Vector((0, -(COWL_Y - HEADER_Y), HEADER_Z_OUT - COWL_Z_OUT)).normalized()     # direction montante du pare-brise
HATCH_N = Vector((0, -(HATCH_Z1_OUT - HATCH_Z0_OUT), HATCH_Y1 - HATCH_Y0)).normalized()
HATCH_S = Vector((0, HATCH_Y1 - HATCH_Y0, HATCH_Z1_OUT - HATCH_Z0_OUT)).normalized()
WS_BASE = Vector((0, 0.905, z_ws(0.905))); HATCH_BASE = Vector((0, -1.79, z_hatch(-1.79)))
WS_VTOP = (0.905 - 0.375)/abs(WS_S.y); HATCH_VTOP = (1.79 - 1.12)/abs(HATCH_S.y)

def ws_pt(x, v): p = WS_BASE + WS_S*v; return (x, p.y, p.z)
def hatch_pt(x, v): p = HATCH_BASE + HATCH_S*v; return (x, p.y, p.z)

def round_outline(pts, radii, n=5):
    """Arrondit chaque sommet d'un polygone 2D (liste de (a, b)) avec le rayon correspondant."""
    out = []; m = len(pts)
    for i in range(m):
        P = Vector(pts[i]); A = Vector(pts[i-1]); B = Vector(pts[(i+1) % m]); r = radii[i]
        u = (A - P).normalized(); w = (B - P).normalized()
        ang = math.acos(max(-0.999, min(0.999, u.dot(w))))
        if r <= 0 or ang > 3.0:
            out.append((P.x, P.y)); continue
        t = min(r/math.tan(ang/2), (A - P).length*0.48, (B - P).length*0.48); rr = t*math.tan(ang/2)
        c = P + (u + w).normalized()*(rr/math.sin(ang/2)); p0 = P + u*t; p1 = P + w*t
        a0 = math.atan2(p0.y - c.y, p0.x - c.x); a1 = math.atan2(p1.y - c.y, p1.x - c.x); da = a1 - a0
        if da > math.pi: da -= 2*math.pi
        if da < -math.pi: da += 2*math.pi
        for k in range(n + 1):
            a = a0 + da*k/n; out.append((c.x + rr*math.cos(a), c.y + rr*math.sin(a)))
    return out

# Vitres latérales : contours (y, z). Vitre de porte : bord avant le long du montant A.
DOOR_WIN = round_outline([(pillar_y(0.975) - 0.06, 0.975), (pillar_y(WIN_TOP) - 0.075, WIN_TOP), (DOOR_Y_REAR + 0.02, WIN_TOP), (DOOR_Y_REAR + 0.02, 0.975)],
                         (0.03, 0.09, 0.06, 0.03))
QTR_WIN = round_outline([(DOOR_Y_REAR - 0.085, 0.975), (DOOR_Y_REAR - 0.085, WIN_TOP), (-1.09, WIN_TOP), (-1.60, 0.975)], (0.03, 0.05, 0.07, 0.04))
# Pare-brise et lunette : contours 3D sur la peau extérieure de la vitre
WS_WIN = [ws_pt(x, v) for (x, v) in round_outline([(-0.745, 0.0), (0.745, 0.0), (0.715, WS_VTOP), (-0.715, WS_VTOP)], (0.12, 0.12, 0.10, 0.10), n=6)]
HATCH_WIN = [hatch_pt(x, v) for (x, v) in round_outline([(-0.66, 0.0), (0.66, 0.0), (0.63, HATCH_VTOP), (-0.63, HATCH_VTOP)], (0.10, 0.10, 0.09, 0.09), n=6)]

def side_glass_pts(s, outline, inset):
    """Contour (y, z) -> points 3D sur le flanc vitré du côté s, décalés de `inset` vers l'habitacle."""
    pts = [(s*(x_side(z) - inset), y, z) for (y, z) in outline]
    return pts if s > 0 else list(reversed(pts))

def plane_glass_pts(outline3d, n, inset):
    """Contour 3D d'une vitre plane décalé de `inset` vers l'intérieur le long de la normale n."""
    return [tuple(Vector(p) - Vector(n)*inset) for p in outline3d]
