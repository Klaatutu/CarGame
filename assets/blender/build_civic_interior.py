# -*- coding: utf-8 -*-
"""
build_civic_interior — habitacle de la Honda Civic EF (collection "Civic_Interior").

Tout est construit en coordonnées monde (voir civic_dims pour le repère) ; les deux portes sont
obtenues par la même fonction avec s = -1 (gauche) / +1 (droite), donc rigoureusement symétriques.
Point d'entrée : build(). Lancer build_civic_all.py pour tout reconstruire, rendre et exporter.
"""
import bpy, math, os, sys
_HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
if _HERE not in sys.path: sys.path.insert(0, _HERE)
import civic_lib as L
import civic_dims as D
import civic_materials as MATS
from mathutils import Vector

ROOT = "Civic_Interior"

class Ctx:
    def __init__(self):
        L.clear_collection(ROOT)
        self.root = L.get_col(ROOT)
        self.c = {n: L.get_col(n, self.root) for n in ("Dashboard", "Steering", "Seats", "Console", "Doors", "Body", "Lighting")}
        self.M = MATS.interior()

# ============================================================================
# Planche de bord
# ============================================================================
def dash_body(X):
    C, M = X.c["Dashboard"], X.M
    def profile(x):
        wh = L.smoothstep(-0.64, -0.50, x)*(1 - L.smoothstep(-0.16, -0.02, x))   # casquette
        wr = L.smoothstep(-0.56, -0.49, x)*(1 - L.smoothstep(-0.17, -0.10, x))   # renfoncement des compteurs
        ws = L.smoothstep(-0.23, -0.16, x)*(1 - L.smoothstep(0.16, 0.23, x))     # face verticale du bloc central
        dy, dz = -0.05*wh, 0.02*wh; rec = 0.06*wr
        fy = lambda y: y*(1 - ws) + 0.585*ws
        return [(fy(0.585), D.DASH_BOT), (fy(0.575), 0.69), (fy(0.565), 0.76), (fy(0.558) + rec, 0.82), (fy(0.553) + rec, 0.86), (fy(0.552) + rec, 0.88),
                (0.552 + dy, 0.895 + dz), (0.562 + dy, 0.912 + dz), (0.585 + 0.85*dy, 0.922 + dz), (0.66 + 0.45*dy, 0.934 + 0.8*dz),
                (0.75, 0.94 + 0.3*dz), (0.84, 0.94), (0.90, 0.935), (D.COWL_Y, D.COWL_Z_IN), (D.COWL_Y, D.DASH_BOT)]
    stations = [-0.775, -0.72, -0.64, -0.58, -0.53, -0.48, -0.42, -0.36, -0.30, -0.24, -0.19, -0.14, -0.08, 0.0, 0.08, 0.14, 0.20, 0.28, 0.38, 0.50, 0.62, 0.72, 0.775]
    L.loft("DASH_Body", [[(x, y, z) for (y, z) in profile(x)] for x in stations], M['plastic_dark'], C,
           creases=[(0, 0.7), (13, 0.9), (14, 1.0), (6, 0.5), (7, 0.5)])
    # dégivrage
    L.box("DASH_Defrost", (1.10, 0.045, 0.003), (0, 0.85, 0.9425), M['gauge_face'], C, rot=(-4, 0, 0), bevel=0.001, segs=2)
    for i in range(22):
        L.box(f"DASH_DefrostRib{i}", (0.005, 0.038, 0.0025), (-0.525 + 0.05*i, 0.85, 0.944), M['plastic_dark'], C, rot=(-4, 0, 0), smooth=False)
    L.box("DASH_CenterDefrost", (0.15, 0.045, 0.003), (0, 0.70, 0.9425), M['gauge_face'], C, bevel=0.001, segs=2)

def center_stack(X):
    C, M = X.c["Dashboard"], X.M
    st = L.empty("DASH_CenterStack", (0.0, 0.575, 0.735), C)
    L.box("STK_Panel", (0.30, 0.016, 0.25), (0, 0, 0), M['plastic_grey'], C, bevel=0.005, segs=4, parent=st)
    for sx, nm in ((-0.075, "L"), (0.075, "R")):
        L.box(f"STK_Vent_{nm}", (0.11, 0.016, 0.045), (sx, -0.004, 0.09), M['plastic_dark'], C, bevel=0.003, parent=st)
        for k, zz in enumerate((-0.014, -0.0047, 0.0047, 0.014)):
            L.box(f"STK_VentSlat_{nm}{k}", (0.10, 0.005, 0.0035), (sx, -0.014, 0.09 + zz), M['plastic_grey'], C, bevel=0.001, segs=2, parent=st)
        L.box(f"STK_VentDivider_{nm}", (0.004, 0.005, 0.036), (sx + 0.02, -0.015, 0.09), M['plastic_grey'], C, bevel=0.001, segs=2, parent=st)
    L.box("STK_Hazard", (0.032, 0.01, 0.018), (-0.165, -0.01, 0.03), M['plastic_dark'], C, bevel=0.0025, parent=st)
    L.box("STK_Hazard_LED", (0.013, 0.003, 0.01), (-0.165, -0.016, 0.03), M['led_red'], C, bevel=0.001, segs=2, parent=st)
    L.box("STK_HVAC", (0.24, 0.01, 0.052), (0, -0.011, 0.033), M['plastic_dark'], C, bevel=0.003, parent=st)
    for i in range(5):
        L.box(f"STK_HVAC_Btn{i}", (0.029, 0.007, 0.014), (-0.075 + 0.0375*i, -0.019, 0.047), M['plastic_grey'], C, bevel=0.0018, parent=st)
    for j, zz in enumerate((0.027, 0.014)):
        L.box(f"STK_HVAC_Slot{j}", (0.19, 0.003, 0.0045), (0, -0.017, zz), M['gauge_face'], C, bevel=0.001, segs=2, parent=st)
        L.box(f"STK_HVAC_Slider{j}", (0.015, 0.01, 0.011), (-0.06 + 0.09*j, -0.021, zz), M['plastic_grey'], C, bevel=0.0025, parent=st)
    L.box("STK_Radio", (0.18, 0.01, 0.048), (0, -0.011, -0.028), M['radio'], C, bevel=0.0025, parent=st)
    L.box("STK_Radio_Display", (0.075, 0.003, 0.014), (-0.03, -0.0175, -0.021), M['display'], C, bevel=0.001, segs=2, parent=st)
    L.cyl("STK_Radio_Knob", 0.008, 0.011, (0.07, -0.021, -0.028), M['plastic_grey'], C, rot=(90, 0, 0), bevel=0.0018, parent=st)
    for i in range(5):
        L.box(f"STK_Radio_Btn{i}", (0.017, 0.004, 0.0065), (-0.065 + 0.024*i, -0.018, -0.043), M['plastic_grey'], C, bevel=0.001, segs=2, parent=st)
    L.box("STK_Radio_Slot", (0.09, 0.003, 0.0045), (-0.03, -0.0175, -0.035), M['gauge_face'], C, parent=st)
    L.box("STK_Pocket", (0.18, 0.01, 0.038), (-0.02, -0.011, -0.088), M['plastic_dark'], C, bevel=0.003, parent=st)
    L.box("STK_Pocket_Lip", (0.18, 0.012, 0.008), (-0.02, -0.014, -0.104), M['plastic_grey'], C, bevel=0.0025, parent=st)
    L.cyl("STK_Lighter", 0.008, 0.012, (0.11, -0.02, -0.084), M['chrome'], C, rot=(90, 0, 0), bevel=0.0018, parent=st)

def cluster(X):
    C, M = X.c["Dashboard"], X.M
    root = L.empty("DASH_ClusterRoot", (D.SEAT_X, 0.575, 0.815), C, rot=(-12, 0, 0))   # haut vers l'avant : face tournée vers les yeux
    L.box("CLU_Back", (0.34, 0.02, 0.13), (0, 0.0, 0), M['gauge_face'], C, parent=root)
    for nm, size, loc in (("CLU_Frame_T", (0.364, 0.03, 0.012), (0, -0.012, 0.071)), ("CLU_Frame_B", (0.364, 0.03, 0.012), (0, -0.012, -0.071)),
                          ("CLU_Frame_L", (0.012, 0.03, 0.154), (-0.176, -0.012, 0)), ("CLU_Frame_R", (0.012, 0.03, 0.154), (0.176, -0.012, 0))):
        L.box(nm, size, loc, M['plastic_grey'], C, bevel=0.003, parent=root)
    L.box("CLU_Glass", (0.34, 0.003, 0.13), (0, -0.0215, 0), M['gauge_glass'], C, parent=root)
    def gauge(name, cx, cz, r, needle_deg, labels=None, label_size=0.007, ticks=9):
        y = -0.012
        L.lathe(f"{name}_Face", [(0.0, 0.0), (r, 0.0), (r, 0.003)], M['gauge_face'], C, loc=(cx, y, cz), rot=(90, 0, 0), parent=root, steps=48)
        L.torus(f"{name}_Ring", r - 0.004, 0.001, (cx, y - 0.0042, cz), M['white_mark'], C, rot=(90, 0, 0), maj=48, minr=8, parent=root)
        for i in range(ticks):
            a = math.radians(-135 + 270.0*i/(ticks - 1)); rr = r - 0.010
            L.box(f"{name}_Tick{i}", (0.0022, 0.002, 0.006), (cx + rr*math.sin(a), y - 0.0045, cz + rr*math.cos(a)), M['white_mark'], C, rot=(0, math.degrees(a), 0), smooth=False, parent=root)
            if labels:
                rl = r - 0.021
                L.text_obj(f"{name}_Num{i}", labels[i], label_size, (cx + rl*math.sin(a), y - 0.004, cz + rl*math.cos(a) - label_size*0.1), M['white_mark'], C, parent=root)
        L.cyl(f"{name}_Hub", 0.0045, 0.004, (cx, y - 0.005, cz), M['gauge_face'], C, rot=(90, 0, 0), parent=root, segments=24)
        a = math.radians(needle_deg); Ln = r - 0.009
        L.box(f"{name}_Needle", (0.0024, 0.002, Ln), (cx + 0.5*Ln*math.sin(a), y - 0.0055, cz + 0.5*Ln*math.cos(a)), M['needle'], C, rot=(0, needle_deg, 0), smooth=False, parent=root)
    gauge("CLU_Tacho", -0.092, 0.0, 0.046, -110, labels=[str(v) for v in range(0, 9)], label_size=0.0072)
    gauge("CLU_Speedo", 0.02, 0.0, 0.053, -125, labels=[str(v) for v in range(0, 201, 20)], label_size=0.0062, ticks=11)
    gauge("CLU_Fuel", 0.122, 0.032, 0.022, 40, ticks=3)
    gauge("CLU_Temp", 0.122, -0.032, 0.022, -20, ticks=3)
    L.text_obj("CLU_Speedo_Unit", "km/h", 0.0042, (0.02, -0.016, -0.02), M['white_mark'], C, parent=root)
    L.text_obj("CLU_Tacho_Unit", "x1000 r/min", 0.003, (-0.092, -0.016, -0.018), M['white_mark'], C, parent=root)
    L.text_obj("CLU_Fuel_Lbl", "F", 0.004, (0.122, -0.016, 0.044), M['white_mark'], C, parent=root)
    L.text_obj("CLU_Temp_Lbl", "H", 0.004, (0.122, -0.016, -0.02), M['white_mark'], C, parent=root)
    for i, mname in enumerate(("lamp_green", "lamp_off", "led_red", "lamp_off", "lamp_blue")):
        L.box(f"CLU_Lamp{i}", (0.008, 0.002, 0.006), (-0.02 + 0.02*i, -0.0155, -0.047), M[mname], C, smooth=False, parent=root)

def side_vents_glovebox(X):
    C, M = X.c["Dashboard"], X.M
    for sx, nm in ((-0.62, "L"), (0.62, "R")):
        root = L.empty(f"DASH_SideVentRoot_{nm}", (sx, 0.562, 0.84), C, rot=(7, 0, 0))
        L.box(f"DASH_SideVent_{nm}", (0.09, 0.024, 0.055), (0, 0, 0), M['plastic_dark'], C, bevel=0.004, parent=root)
        L.box(f"DASH_SideVentFrame_{nm}", (0.10, 0.008, 0.065), (0, -0.01, 0), M['plastic_grey'], C, bevel=0.003, parent=root)
        L.box(f"DASH_SideVentInner_{nm}", (0.082, 0.01, 0.047), (0, -0.011, 0), M['gauge_face'], C, parent=root)
        for k, zz in enumerate((-0.016, -0.0053, 0.0053, 0.016)):
            L.box(f"DASH_SideVentSlat_{nm}{k}", (0.078, 0.005, 0.0035), (0, -0.013, zz), M['plastic_grey'], C, bevel=0.001, segs=2, parent=root)
    gb = L.empty("DASH_GloveboxRoot", (0.42, 0.574, 0.70), C, rot=(7, 0, 0))
    L.box("GLV_Door", (0.44, 0.016, 0.15), (0, 0, 0), M['plastic_dark'], C, bevel=0.006, segs=4, parent=gb)
    L.box("GLV_Pull", (0.065, 0.008, 0.022), (0, -0.01, 0.056), M['plastic_grey'], C, bevel=0.003, parent=gb)
    L.box("GLV_PullRecess", (0.046, 0.005, 0.01), (0, -0.014, 0.059), M['gauge_face'], C, bevel=0.0018, segs=2, parent=gb)
    L.cyl("GLV_Lock", 0.0065, 0.005, (0.058, -0.01, 0.056), M['chrome'], C, rot=(90, 0, 0), parent=gb, segments=24)

# ============================================================================
# Volant, colonne, pédales
# ============================================================================
def steering(X):
    C, M = X.c["Steering"], X.M
    w = L.empty("STR_Root", D.WHEEL_C, C, rot=(D.WHEEL_TILT, 0, 0))
    L.torus("STR_Rim", D.WHEEL_RADIUS, 0.0155, (0, 0, 0), M['rubber'], C, maj=72, minr=20, parent=w)
    for name, deg in (("STR_Spoke_UL", 170), ("STR_Spoke_UR", 10), ("STR_Spoke_LL", 245), ("STR_Spoke_LR", 295)):
        a = math.radians(deg); secs = []
        for u, wd, t in ((0.03, 0.042, 0.02), (0.10, 0.03, 0.018), (D.WHEEL_RADIUS + 0.005, 0.024, 0.016)):
            secs.append([(u*math.cos(a) - v*math.sin(a), u*math.sin(a) + v*math.cos(a), z) for v, z in ((-wd/2, -t/2), (wd/2, -t/2), (wd/2, t/2), (-wd/2, t/2))])
        L.loft(name, secs, M['rubber'], C, parent=w)
    L.grid_box("STR_Pad", [-0.072, -0.056, -0.03, 0.0, 0.03, 0.056, 0.072], [-0.082, -0.066, -0.037, -0.008, 0.02, 0.041, 0.05],
               lambda x, y: 0.022 + 0.012*max(0.0, 1.0 - (x/0.082)**2 - ((y + 0.016)/0.076)**2), -0.01, M['rubber'], C, parent=w, crease_bottom=0.6)
    L.box("STR_BadgePlate", (0.04, 0.036, 0.003), (0, 0.0, 0.0338), M['plastic_dark'], C, bevel=0.0012, parent=w)
    for nm, size, loc in (("STR_H_Left", (0.006, 0.025, 0.004), (-0.0115, 0, 0.0365)), ("STR_H_Right", (0.006, 0.025, 0.004), (0.0115, 0, 0.0365)), ("STR_H_Bar", (0.018, 0.006, 0.004), (0, 0, 0.0365))):
        L.box(nm, size, loc, M['chrome'], C, bevel=0.001, segs=2, parent=w)
    for sx, nm in ((-0.05, "L"), (0.05, "R")):
        L.box(f"STR_Horn_{nm}", (0.02, 0.016, 0.005), (sx, 0.0, 0.0295), M['plastic_dark'], C, bevel=0.002, parent=w)
    L.cyl("STR_Shaft", 0.016, 0.14, (0, 0, -0.09), M['metal_dark'], C, parent=w)
    L.lathe("STR_Shroud", [(0.0, -0.26), (0.040, -0.26), (0.043, -0.23), (0.047, -0.17), (0.050, -0.12), (0.046, -0.08), (0.036, -0.06), (0.0, -0.055)], M['plastic_dark'], C, parent=w, subsurf=1, steps=40)
    for s, nm in ((-1, "TurnSignal"), (1, "Wiper")):
        L.cyl_between(f"STR_Stalk_{nm}", (s*0.04, 0.0, -0.125), (s*0.155, 0.012, -0.10), 0.007, M['plastic_dark'], C, parent=w)
        L.box(f"STR_StalkTip_{nm}", (0.036, 0.02, 0.012), (s*0.16, 0.013, -0.099), M['plastic_dark'], C, rot=(0, 0, s*-8), bevel=0.0035, parent=w)
    L.cyl("STR_Ignition", 0.012, 0.02, (0.058, -0.02, -0.16), M['chrome'], C, rot=(0, 90, 0), bevel=0.002, parent=w, segments=24)
    L.box("STR_Key", (0.03, 0.003, 0.02), (0.082, -0.02, -0.16), M['chrome'], C, bevel=0.001, segs=2, parent=w)
    L.box("STR_KeyHead", (0.016, 0.005, 0.028), (0.104, -0.02, -0.16), M['plastic_dark'], C, bevel=0.0025, parent=w)

def pedals(X):
    C, M = X.c["Steering"], X.M
    for nm, size, zc in (("Accel", (0.05, 0.01, 0.12), D.FLOOR + 0.08), ("Brake", (0.07, 0.01, 0.05), D.FLOOR + 0.09), ("Clutch", (0.065, 0.01, 0.05), D.FLOOR + 0.09)):
        x = D.PEDALS[nm]
        L.box(f"PED_{nm}", size, (x, D.PEDAL_Y, zc), M['rubber'], C, rot=(-32, 0, 0), bevel=0.0035)
        L.cyl_between(f"PED_{nm}_Arm", (x, D.PEDAL_Y + 0.01, zc + size[2]*0.4), (x, 0.93, D.DASH_BOT - 0.02), 0.006, M['metal_dark'], C)
    L.box("PED_Footrest", (0.065, 0.01, 0.14), (D.SEAT_X - 0.30, 0.82, D.FLOOR + 0.08), M['rubber'], C, rot=(-35, 0, 0), bevel=0.0035)

# ============================================================================
# Sièges
# ============================================================================
def front_seat(X, prefix, x, inboard):
    C, M = X.c["Seats"], X.M
    root = L.empty(prefix + "_Root", (x, D.SEAT_Y, D.FLOOR), C)
    L.box(prefix + "_Base", (0.40, 0.42, 0.05), (0, 0.0, 0.045), M['plastic_dark'], C, bevel=0.01, segs=4, parent=root)
    for sx, nm in ((-0.16, "L"), (0.16, "R")):
        L.box(prefix + f"_Rail_{nm}", (0.025, 0.58, 0.022), (sx, 0.0, 0.011), M['metal_dark'], C, bevel=0.004, segs=2, parent=root)
    def ctop(xx, yy):
        bol = L.smoothstep(0.10, 0.21, abs(xx))
        return 0.11 + 0.035*bol + 0.012*L.smoothstep(0.10, 0.25, yy) - 0.018*L.smoothstep(0.05, 0.24, -yy)*(1 - bol)
    L.grid_box(prefix + "_Cushion", [-0.24, -0.20, -0.13, -0.06, 0.06, 0.13, 0.20, 0.24], [-0.25, -0.20, -0.10, 0.05, 0.17, 0.22, 0.25], ctop, 0.05, M['cloth'], C,
               parent=root, crease_bottom=0.5, side_rows=[0.5])
    # dossier incliné de 14° : pivot rot X = 104°, face sculptée en -Z local (= vers l'avant)
    piv = L.empty(prefix + "_BackPivot", (0, -0.22, 0.11), C, rot=(104, 0, 0), parent=root)
    secs = []
    for yy in (0.0, 0.06, 0.16, 0.28, 0.40, 0.48, 0.55, 0.60):
        w = 0.23 - 0.04*L.smoothstep(0.3, 0.60, yy)
        b = 0.04*(1 - L.smoothstep(0.38, 0.60, yy))*L.smoothstep(-0.05, 0.10, yy) + 0.012
        lum = 0.012*L.bump(yy, 0.18, 0.16); f0 = 0.05
        ring = [(-w, f0 + 0.008), (-w*0.84, f0 + b), (-w*0.58, f0 + b*0.55 + lum*0.5), (0.0, f0 + lum), (w*0.58, f0 + b*0.55 + lum*0.5), (w*0.84, f0 + b), (w, f0 + 0.008),
                (w*0.9, -0.035), (0.0, -0.045), (-w*0.9, -0.035)]
        secs.append([(px, yy, -pz) for (px, pz) in ring])
    L.loft(prefix + "_Back", secs, M['cloth'], C, parent=piv)
    L.grid_box(prefix + "_Headrest", [-0.11, -0.085, -0.035, 0.035, 0.085, 0.11], [0.66, 0.69, 0.73, 0.77], 0.03,
               lambda xx, yy: -(0.05 + 0.015*max(0, 1 - (xx/0.11)**2) - 0.012*L.smoothstep(0.73, 0.77, yy)), M['cloth'], C, parent=piv)
    for sx, nm in ((-0.05, "L"), (0.05, "R")):
        L.cyl_between(prefix + f"_Post_{nm}", (sx, 0.57, 0.01), (sx, 0.675, 0.01), 0.0055, M['metal_dark'], C, parent=piv)
    bx = inboard*0.245
    L.cyl_between(prefix + "_BuckleStalk", (bx, -0.05, 0.06), (bx + inboard*0.02, -0.08, 0.17), 0.01, M['rubber'], C, parent=root)
    L.box(prefix + "_Buckle", (0.026, 0.045, 0.06), (bx + inboard*0.02, -0.085, 0.20), M['plastic_dark'], C, rot=(-12, 0, 0), bevel=0.005, parent=root)
    L.box(prefix + "_BuckleBtn", (0.016, 0.005, 0.012), (bx + inboard*0.02, -0.109, 0.218), M['led_red'], C, bevel=0.0018, segs=2, parent=root)
    L.box(prefix + "_Recline", (0.012, 0.08, 0.022), (-inboard*0.25, -0.2, 0.11), M['plastic_dark'], C, bevel=0.0035, parent=root)

def seats(X):
    C, M = X.c["Seats"], X.M
    front_seat(X, "SEAT_Driver", D.SEAT_X, +1); front_seat(X, "SEAT_Pass", -D.SEAT_X, -1)
    rx = [-0.64, -0.60, -0.52, -0.38, -0.20, 0.0, 0.20, 0.38, 0.52, 0.60, 0.64]
    L.grid_box("SEAT_Rear_Cushion", rx, [-1.24, -1.20, -1.10, -0.96, -0.84, -0.80],
               lambda x, y: D.FLOOR + 0.13 + 0.015*L.bump(x, 0, 0.22) + 0.01*L.smoothstep(-0.96, -0.80, y) - 0.015*L.smoothstep(0.55, 0.64, abs(x)), D.FLOOR + 0.03, M['cloth'], C, crease_bottom=0.5)
    rb = L.empty("SEAT_Rear_BackPivot", (0, -1.22, D.FLOOR + 0.12), C, rot=(102, 0, 0))
    L.grid_box("SEAT_Rear_Back", rx, [0.0, 0.05, 0.16, 0.30, 0.40, 0.46, 0.50], 0.04,
               lambda x, y: -(0.065 + 0.015*L.bump(x, -0.34, 0.28) + 0.015*L.bump(x, 0.34, 0.28) + 0.015*L.bump(x, 0, 0.14) - 0.015*L.smoothstep(0.42, 0.50, y)), M['cloth'], C, parent=rb)
    for sx, nm in ((-0.34, "L"), (0.34, "R")):
        L.grid_box(f"SEAT_Rear_Headrest_{nm}", [sx-0.10, sx-0.075, sx-0.03, sx+0.03, sx+0.075, sx+0.10], [0.55, 0.58, 0.62, 0.65], 0.026,
                   lambda xx, yy, sx=sx: -(0.048 + 0.012*max(0, 1 - ((xx-sx)/0.10)**2)), M['cloth'], C, parent=rb)
        for px, tag in ((sx-0.045, "a"), (sx+0.045, "b")):
            L.cyl_between(f"SEAT_Rear_Post_{nm}{tag}", (px, 0.47, 0.01), (px, 0.565, 0.01), 0.0055, M['metal_dark'], C, parent=rb)

# ============================================================================
# Plancher, console, levier, frein à main
# ============================================================================
def floor_console(X):
    C, B, M = X.c["Console"], X.c["Body"], X.M
    L.box("BODY_Floor", (1.42, 3.00, 0.02), (0, -0.30, D.FLOOR - 0.01), M['carpet'], B, smooth=False)
    L.box("BODY_Tunnel", (0.26, 1.90, 0.10), (0, -0.05, D.FLOOR + 0.02), M['carpet'], B, bevel=0.03, segs=5)
    L.box("BODY_Firewall", (1.42, 0.03, 0.30), (0, 0.945, D.FLOOR + 0.14), M['carpet'], B, smooth=False)
    L.box("BODY_RearFloorStep", (1.42, 0.46, 0.10), (0, -1.02, D.FLOOR + 0.03), M['carpet'], B, bevel=0.02)
    for sx, nm in ((D.SEAT_X, "L"), (-D.SEAT_X, "R")):
        L.box(f"BODY_Mat_{nm}", (0.46, 0.60, 0.008), (sx, 0.50, D.FLOOR + 0.004), M['rubber'], B, bevel=0.0025, segs=2)
    y0 = 0.06 if D.HB_FORWARD else -0.16
    L.box("CON_Body", (0.22, 0.64 - y0, 0.25), (0, (0.64 + y0)*0.5, D.FLOOR + 0.125), M['plastic_dark'], C, bevel=0.008, segs=4)
    L.box("CON_Top", (0.18, 0.24, 0.01), (0, D.LEVER_BASE.y, D.LEVER_BASE.z + 0.004), M['plastic_grey'], C, bevel=0.003)
    L.box("CON_Tray", (0.13, 0.10, 0.01), (0, y0 + 0.08, D.LEVER_BASE.z + 0.003), M['gauge_face'], C, bevel=0.0025, segs=2)
    lb = D.LEVER_BASE
    L.lathe("CON_ShiftBoot", [(0.0, 0.0), (0.052, 0.0), (0.05, 0.01), (0.042, 0.028), (0.037, 0.036), (0.032, 0.05), (0.029, 0.056), (0.024, 0.07), (0.022, 0.076), (0.018, 0.09), (0.014, 0.10), (0.0, 0.10)],
            M['rubber'], C, loc=lb + Vector((0, 0, 0.008)), subsurf=1, steps=40)
    L.torus("CON_ShiftRing", 0.052, 0.005, lb + Vector((0, 0, 0.01)), M['plastic_grey'], C, maj=48, minr=10)
    L.cyl("CON_ShiftLever", 0.007, D.LEVER_LEN - 0.04, lb + Vector((0, 0, 0.10)), M['chrome'], C, segments=24)
    L.lathe("CON_ShiftKnob", [(0.0, 0.0), (0.011, 0.0), (0.018, 0.011), (0.023, 0.028), (0.0225, 0.042), (0.017, 0.052), (0.0, 0.056)], M['rubber'], C, loc=lb + Vector((0, 0, D.LEVER_LEN - 0.026)), subsurf=1, steps=40)
    L.cyl("CON_ShiftBadge", 0.01, 0.002, lb + Vector((0, 0, D.LEVER_LEN + 0.0295)), M['white_mark'], C, segments=24)
    sgn = 1.0 if D.HB_FORWARD else -1.0
    ax = Vector((0, sgn*math.sin(math.radians(D.HB_DOWN)), math.cos(math.radians(D.HB_DOWN)))); rot = (-sgn*D.HB_DOWN, 0, 0); hb = D.HB_BASE
    L.box("CON_BrakeHousing", (0.13, 0.20, 0.07), (0, hb.y + sgn*0.03, hb.z - 0.035), M['plastic_dark'], C, bevel=0.008, segs=4)
    L.lathe("CON_BrakeBoot", [(0.0, 0.0), (0.034, 0.0), (0.032, 0.012), (0.022, 0.03), (0.015, 0.045), (0.0, 0.045)], M['rubber'], C, loc=hb - 0.015*ax, rot=rot, subsurf=1)
    L.cyl("CON_BrakeLever", 0.009, D.HB_LEN - 0.09, hb + (0.03 + (D.HB_LEN - 0.09)*0.5)*ax, M['metal_dark'], C, rot=rot, segments=24)
    L.lathe("CON_BrakeGrip", [(0.0, 0.0), (0.01, 0.0), (0.0135, 0.01), (0.015, 0.04), (0.0145, 0.07), (0.0125, 0.09), (0.01, 0.10), (0.0, 0.10)], M['rubber'], C, loc=hb + (D.HB_LEN - 0.10)*ax, rot=rot, subsurf=1)
    L.cyl("CON_BrakeButton", 0.0055, 0.012, hb + (D.HB_LEN + 0.005)*ax, M['chrome'], C, rot=rot, segments=20)

# ============================================================================
# Portes (même fonction pour les deux côtés, coordonnées monde : u = Y, v = Z, w = vers l'habitacle)
# ============================================================================
def door(X, s):
    C, M = X.c["Doors"], X.M; nm = "L" if s < 0 else "R"
    tw = lambda u, v, w: (s*(D.DOOR_X - w), u, v)
    P = lambda u, v, w: (s*(D.DOOR_X - w), u, v)
    def card_top(u, v):
        w = 0.022
        w += 0.06*L.smoothstep(-0.36, -0.24, u)*(1 - L.smoothstep(0.08, 0.22, u))*L.smoothstep(0.66, 0.70, v)*(1 - L.smoothstep(0.745, 0.80, v))   # accoudoir
        w += 0.025*L.smoothstep(-0.10, 0.0, u)*(1 - L.smoothstep(0.22, 0.32, u))*L.smoothstep(D.SILL, D.SILL + 0.07, v)*(1 - L.smoothstep(0.60, 0.65, v))  # vide-poche
        return w
    L.grid_box(f"DOOR_{nm}_Card", [D.DOOR_Y_REAR, -0.54, -0.46, -0.34, -0.22, -0.10, 0.0, 0.10, 0.22, 0.34, 0.46, 0.56, D.DOOR_Y_FRONT],
               [D.SILL + 0.005, D.SILL + 0.05, D.SILL + 0.13, 0.64, 0.68, 0.71, 0.745, 0.78, 0.82, 0.88, 0.93, D.BELT - 0.005], card_top, -0.06, M['plastic_dark'], C, to_world=tw, crease_bottom=1.0)
    L.grid_box(f"DOOR_{nm}_Cloth", [-0.52, -0.46, -0.20, 0.05, 0.25, 0.36, 0.42], [0.815, 0.835, 0.87, 0.90, 0.92], 0.036, 0.014, M['cloth'], C, to_world=tw)
    L.box(f"DOOR_{nm}_HandleRecess", (0.01, 0.09, 0.032), P(0.46, 0.86, 0.026), M['gauge_face'], C, bevel=0.0035)
    L.box(f"DOOR_{nm}_Handle", (0.009, 0.06, 0.016), P(0.47, 0.862, 0.036), M['chrome'], C, bevel=0.0028)
    L.cyl(f"DOOR_{nm}_CrankHub", 0.013, 0.02, P(-0.20, 0.72, 0.036), M['plastic_dark'], C, rot=(0, 90, 0), bevel=0.0028, segments=24)
    L.box(f"DOOR_{nm}_CrankArm", (0.008, 0.09, 0.016), P(-0.16, 0.745, 0.048), M['plastic_dark'], C, rot=(-s*30, 0, 0), bevel=0.0028)
    L.cyl(f"DOOR_{nm}_CrankKnob", 0.01, 0.028, P(-0.12, 0.768, 0.066), M['plastic_dark'], C, rot=(0, 90, 0), bevel=0.0028, segments=24)
    L.box(f"DOOR_{nm}_PullRecess", (0.01, 0.11, 0.028), P(0.0, 0.725, 0.086), M['gauge_face'], C, bevel=0.0035)
    L.lathe(f"DOOR_{nm}_Speaker", [(0.0, 0.0), (0.058, 0.0), (0.066, 0.008), (0.069, 0.016), (0.06, 0.02), (0.0, 0.021)], M['plastic_grey'], C, loc=P(0.50, 0.57, 0.02), rot=(0, -s*90, 0), steps=48)
    L.torus(f"DOOR_{nm}_SpeakerRing", 0.062, 0.003, P(0.50, 0.57, 0.04), M['plastic_dark'], C, rot=(0, 90, 0), maj=48, minr=8)
    for k, rr in enumerate((0.018, 0.032, 0.046)):
        L.torus(f"DOOR_{nm}_SpeakerGrille{k}", rr, 0.0015, P(0.50, 0.57, 0.0415), M['gauge_face'], C, rot=(0, 90, 0), maj=40, minr=6)
    dl = D.DOOR_Y_FRONT - D.DOOR_Y_REAR; dm = (D.DOOR_Y_FRONT + D.DOOR_Y_REAR)*0.5
    L.cyl(f"DOOR_{nm}_LockKnob", 0.0055, 0.028, P(D.DOOR_Y_REAR + 0.06, D.BELT + 0.01, 0.036), M['plastic_dark'], C, bevel=0.0018, segments=16)
    L.box(f"DOOR_{nm}_BeltTrim", (0.022, dl + 0.02, 0.04), P(dm, D.BELT + 0.008, 0.02), M['plastic_dark'], C, bevel=0.006)
    L.box(f"DOOR_{nm}_Sill", (0.02, dl + 0.02, 0.08), P(dm, D.SILL - 0.005, 0.03), M['plastic_dark'], C, bevel=0.006)
    L.box(f"DOOR_{nm}_Skin", (0.015, dl + 0.04, 0.47), P(dm, 0.725, -0.055), M['plastic_dark'], C, smooth=False)
    L.box(f"DOOR_{nm}_KickPanel", (0.026, 0.95 - D.DOOR_Y_FRONT + 0.02, D.DASH_BOT + 0.02 - D.FLOOR), (s*0.738, (0.95 + D.DOOR_Y_FRONT)*0.5, (D.DASH_BOT + 0.02 + D.FLOOR)*0.5), M['plastic_dark'], C, bevel=0.006)
    # vitres intérieures (mêmes contours que les baies extérieures, 1,5 cm en retrait)
    L.polygon(f"DOOR_{nm}_Glass", D.side_glass_pts(s, D.DOOR_WIN, 0.015), M['glass'], C)
    L.polygon(f"QTR_{nm}_Glass", D.side_glass_pts(s, D.QTR_WIN, 0.015), M['glass'], C)
    # montants et rails (sous la tôle extérieure)
    p1, p2 = Vector((s*0.762, D.COWL_Y - 0.005, D.COWL_Z_OUT - 0.01)), Vector((s*0.745, D.HEADER_Y + 0.06, D.HEADER_Z_OUT - 0.065)); d = p2 - p1; Lp = d.length
    def dsec(z, a, b):
        pts = []
        for k in range(16):
            t = 2*math.pi*k/16; x, y = a*math.cos(t), b*math.sin(t)
            if y > 0: y *= 0.3
            pts.append((x, y, z))
        return pts
    pil = L.loft(f"PILLAR_A_{nm}", [dsec(0.0, 0.03, 0.026), dsec(Lp*0.35, 0.028, 0.024), dsec(Lp*0.7, 0.026, 0.022), dsec(Lp, 0.022, 0.02)], M['headliner'], C)
    pil.location = p1; pil.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    L.cyl_between(f"PILLAR_A_{nm}_Seal", (s*0.738, D.COWL_Y - 0.005, D.COWL_Z_IN - 0.004), (s*0.708, D.HEADER_Y + 0.015, D.HEADER_Z_IN - 0.03), 0.004, M['rubber'], C, segments=10)
    bsecs = [[(s*(0.784 - 0.042*(0.5 + 0.5*math.cos(2*math.pi*k/16))), D.PILLAR_B_Y + 0.05*math.sin(2*math.pi*k/16), z) for k in range(16)] for z in (D.BELT - 0.01, (D.BELT + D.ROOF_IN)*0.5, D.ROOF_IN - 0.045)]
    L.loft(f"PILLAR_B_{nm}", bsecs, M['headliner'], C, subsurf=1)
    rsecs = [[(s*(0.746 + 0.026*math.cos(2*math.pi*k/12)), y, 1.245 + 0.011*math.sin(2*math.pi*k/12)) for k in range(12)] for y in (0.30, 0.0, D.DOOR_Y_REAR - 0.06)]
    L.loft(f"ROOF_Rail_{nm}", rsecs, M['headliner'], C, subsurf=1)
    L.cyl_between(f"DOOR_{nm}_Seal", (s*0.755, 0.30, 1.238), (s*0.755, D.DOOR_Y_REAR - 0.04, 1.238), 0.006, M['rubber'], C, segments=12)
    qf = D.PILLAR_B_Y - 0.04
    L.box(f"QTR_{nm}_Panel", (0.028, qf + 1.74, D.BELT - D.SILL - 0.02), (s*0.762, (qf - 1.74)*0.5, (D.SILL + D.BELT)*0.5), M['plastic_dark'], C, bevel=0.008)
    c1, c2 = Vector((s*0.77, -1.64, 0.975)), Vector((s*0.74, -1.12, 1.22)); dc = c2 - c1; Lc = dc.length
    cp = L.loft(f"PILLAR_C_{nm}", [[(0.012*math.cos(2*math.pi*k/12), 0.02*math.sin(2*math.pi*k/12), z) for k in range(12)] for z in (0.0, Lc*0.5, Lc)], M['headliner'], C, subsurf=1)
    cp.location = c1; cp.rotation_euler = dc.to_track_quat('Z', 'Y').to_euler()
    # ceinture de sécurité (enrouleur sur le montant B)
    L.box(f"BELT_{nm}_Strap", (0.008, 0.046, 0.62), (s*0.74, D.PILLAR_B_Y + 0.02, 0.84), M['rubber'], C, smooth=False)
    L.box(f"BELT_{nm}_Guide", (0.024, 0.06, 0.045), (s*0.74, D.PILLAR_B_Y, 1.16), M['plastic_dark'], C, bevel=0.006)
    L.box(f"BELT_{nm}_Anchor", (0.026, 0.055, 0.036), (s*0.735, D.PILLAR_B_Y + 0.10, D.SILL + 0.05), M['plastic_dark'], C, bevel=0.005)
    L.cyl_between(f"BELT_{nm}_Lap", (s*0.725, D.PILLAR_B_Y + 0.10, D.SILL + 0.07), (s*0.08, D.SEAT_Y - 0.10, D.FLOOR + 0.20), 0.002, M['rubber'], C, segments=6)

# ============================================================================
# Pavillon, vitrage avant / arrière, accessoires
# ============================================================================
def roof(X):
    B, M = X.c["Body"], X.M
    hl = lambda x, y: D.ROOF_IN + 0.012 - 0.068*(x/0.77)**2 - 0.012*((y + 0.36)/0.72)**2
    L.grid_box("BODY_Headliner", [-0.77, -0.70, -0.56, -0.32, 0.0, 0.32, 0.56, 0.70, 0.77], [D.ROOF_BACK - 0.02, -0.88, -0.64, -0.36, -0.08, 0.16, D.HEADER_Y + 0.02],
               lambda x, y: hl(x, y) + 0.010, hl, M['headliner'], B)
    L.polygon("BODY_Windshield", D.plane_glass_pts(D.WS_WIN, D.WS_N, 0.012), M['glass'], B)
    inner_ws = D.plane_glass_pts(D.WS_WIN, D.WS_N, 0.013)
    L.band("BODY_WindshieldFrit", inner_ws, L.offset_outline3d(inner_ws, -0.04), M['gauge_face'], B)
    L.polygon("BODY_RearGlass", D.plane_glass_pts(D.HATCH_WIN, D.HATCH_N, 0.012), M['glass'], B)
    L.box("BODY_Header", (1.40, 0.07, 0.04), (0, D.HEADER_Y + 0.025, D.HEADER_Z_IN - 0.024), M['headliner'], B, bevel=0.012, segs=4)
    L.box("BODY_WindshieldSeal", (1.38, 0.03, 0.006), (0, D.HEADER_Y + 0.03, D.HEADER_Z_IN - 0.036), M['rubber'], B, rot=(-31, 0, 0), bevel=0.002, segs=2)
    L.box("BODY_RearHeader", (1.30, 0.07, 0.035), (0, D.ROOF_BACK - 0.01, D.ROOF_IN - 0.06), M['headliner'], B, bevel=0.01, segs=4)
    for y, tag in ((0.17, "F"), (-0.11, "R")):
        L.cyl_between(f"BODY_GrabPost_{tag}", (0.67, y, D.ROOF_IN - 0.03), (0.67, y, D.ROOF_IN - 0.062), 0.011, M['plastic_grey'], B, segments=16)
        L.box(f"BODY_GrabPad_{tag}", (0.045, 0.045, 0.012), (0.67, y, D.ROOF_IN - 0.031), M['plastic_grey'], B, bevel=0.004)
    L.cyl_between("BODY_GrabHandle", (0.67, 0.19, D.ROOF_IN - 0.066), (0.67, -0.13, D.ROOF_IN - 0.066), 0.012, M['plastic_grey'], B, segments=16)
    L.box("BODY_RearShelf", (1.38, 0.32, 0.03), (0, -1.36, D.BELT), M['carpet'], B, smooth=False)
    for sx, nm in ((-0.38, "L"), (0.38, "R")):
        s = -1 if sx < 0 else 1
        L.box(f"BODY_Visor_{nm}", (0.30, 0.13, 0.008), (sx, 0.442, 1.20), M['headliner'], B, rot=(-31, 0, 0), bevel=0.0035)
        L.cyl_between(f"BODY_VisorRod_{nm}", (sx - 0.155, 0.385, 1.242), (sx + 0.155, 0.385, 1.242), 0.0045, M['plastic_dark'], B)
        L.box(f"BODY_VisorMount_{nm}", (0.022, 0.028, 0.024), (sx + s*0.16, 0.382, 1.242), M['plastic_dark'], B, bevel=0.003)
        L.box(f"BODY_VisorClip_{nm}", (0.016, 0.02, 0.018), (sx - s*0.13, 0.385, 1.243), M['plastic_dark'], B, bevel=0.0025)
    L.box("BODY_Mirror", (0.25, 0.018, 0.06), (0, 0.40, 1.155), M['plastic_dark'], B, bevel=0.006, segs=4)
    L.box("BODY_MirrorGlass", (0.23, 0.003, 0.048), (0, 0.39, 1.155), M['chrome'], B)
    L.cyl_between("BODY_MirrorStalk", (0, 0.40, 1.18), (0, 0.455, 1.203), 0.007, M['plastic_dark'], B)
    L.box("BODY_DomeLight", (0.17, 0.11, 0.022), (0, -0.15, D.ROOF_IN - 0.006), M['plastic_grey'], B, bevel=0.005)
    L.box("BODY_DomeLens", (0.13, 0.075, 0.008), (0, -0.155, D.ROOF_IN - 0.019), M['white_mark'], B, bevel=0.002, segs=2)
    L.box("DOME_Switch", (0.028, 0.012, 0.006), (0.0, -0.10, D.ROOF_IN - 0.02), M['plastic_dark'], B, bevel=0.0015, segs=2)

# ============================================================================
# Caméras, lumières, rendu
# ============================================================================
def cameras_lights(X):
    Lc = X.c["Lighting"]; scene = bpy.context.scene
    eye = D.g2b(D.HEAD_POS)
    L.camera("CAM_DriverPOV", eye, (D.SEAT_X + 0.05, 0.90, 0.80), 24, Lc)
    L.camera("CAM_Main", (0.02, -0.62, 1.12), (-0.14, 0.62, 0.72), 22, Lc)
    L.camera("CAM_Door", (1.10, -0.32, 0.98), (-0.25, 0.50, 0.70), 26, Lc)
    L.camera("CAM_Driver34", (0.52, -0.62, 1.12), (-0.30, 0.15, 0.78), 24, Lc)
    scene.camera = bpy.data.objects["CAM_Main"]
    w = scene.world or bpy.data.worlds.new("World"); scene.world = w; w.use_nodes = True; nt = w.node_tree
    for n in list(nt.nodes):
        if n.bl_idname not in ('ShaderNodeBackground', 'ShaderNodeOutputWorld'): nt.nodes.remove(n)
    bg = L.node_of(nt, 'ShaderNodeBackground')
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ'); mr = nt.nodes.new('ShaderNodeMapRange'); mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    mr.inputs['From Min'].default_value = -0.15; mr.inputs['From Max'].default_value = 0.7
    mix.inputs[6].default_value = (0.80, 0.74, 0.64, 1.0); mix.inputs[7].default_value = (0.30, 0.50, 0.90, 1.0)
    nt.links.new(tc.outputs['Generated'], sep.inputs['Vector']); nt.links.new(sep.outputs['Z'], mr.inputs['Value'])
    nt.links.new(mr.outputs['Result'], mix.inputs[0]); nt.links.new(mix.outputs[2], bg.inputs['Color']); bg.inputs['Strength'].default_value = 0.75
    for nm in ("LGT_Sun", "LGT_Fill"):
        o = bpy.data.objects.get(nm)
        if o: bpy.data.objects.remove(o, do_unlink=True)
    sd = bpy.data.lights.new("LGT_Sun", 'SUN'); sd.energy = 6.0; sd.angle = math.radians(3); sd.color = (1.0, 0.96, 0.9)
    sun = bpy.data.objects.new("LGT_Sun", sd); L.link_obj(sun, Lc); sun.location = (0.4, 2.5, 2.8); L.aim(sun, (0, 0.3, 0.7))
    fd = bpy.data.lights.new("LGT_Fill", 'AREA'); fd.energy = 10.0; fd.size = 1.2; fd.color = (0.95, 0.97, 1.0)
    fill = bpy.data.objects.new("LGT_Fill", fd); L.link_obj(fill, Lc); fill.location = (0.0, -0.9, 1.25); L.aim(fill, (0, 0.5, 0.8))
    scene.render.engine = 'BLENDER_EEVEE'; scene.render.resolution_x = 1600; scene.render.resolution_y = 1000; scene.render.resolution_percentage = 100
    scene.eevee.taa_render_samples = 48; scene.eevee.use_shadows = True; scene.eevee.use_raytracing = True
    scene.view_settings.view_transform = 'AgX'; scene.unit_settings.system = 'METRIC'; scene.unit_settings.scale_length = 1.0

def build():
    X = Ctx()
    dash_body(X); center_stack(X); cluster(X); side_vents_glovebox(X)
    steering(X); pedals(X)
    seats(X)
    floor_console(X)
    door(X, -1); door(X, +1)
    roof(X)
    cameras_lights(X)
    n = len(X.root.all_objects)
    print("Civic interior built:", n, "objects"); return n

if __name__ == "__main__":
    build()
