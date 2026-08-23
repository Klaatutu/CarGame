# -*- coding: utf-8 -*-
"""
build_civic_driver — conducteur assis (collection "Civic_Driver"), t-shirt blanc, jean, baskets, peau claire.

driver.gd n'utilise pas de squelette : chaque segment est un MeshInstance3D posé par _set_bone(from, to)
(origine = articulation proximale, axe -Z Godot vers l'articulation distale), les mains vivent dans le
repère du volant (jante le long de +Z local, tourné de 68° en X), les pieds ont leur origine à la
cheville, le buste tourne autour de SPINE. Chaque objet DRV_* est donc MODÉLISÉ DANS SON REPÈRE LOCAL
GODOT (converti en Blender : Godot (X, Y, Z) -> Blender (X, -Z, Y)), puis seulement POSÉ dans la voiture
via sa transform objet (position de repos : mains sur le volant, pieds sur les pédales).

Dans Godot : prendre `mesh` de chaque noeud DRV_* et le mettre sous le pivot correspondant de driver.gd
avec une transform identité (sans la rotation -90° des capsules), puis scale.z = d / longueur_repos.

    Segment           origine        longueur repos   remplace
    DRV_ArmUpper_L/R  épaule         0.32 (UPPER_ARM) _arm_lu / _arm_ru
    DRV_Forearm_L/R   coude          0.30 (FOREARM)   _arm_lf / _arm_rf
    DRV_Thigh_L/R     hanche         0.50             _thigh_l / _thigh_r
    DRV_Shin_L/R      genou          0.48             _shin_l / _shin_r
    DRV_Hand_L/R      repère volant  -                enfants de _hand_l / _hand_r
    DRV_Foot_L/R      cheville       -                enfants de _foot_l / _foot_r
    DRV_Torso (+Belt, Neck, Head…)   SPINE (sol)      enfants de _torso
"""
import bpy, math, os, sys
_HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
if _HERE not in sys.path: sys.path.insert(0, _HERE)
import civic_lib as L
import civic_dims as D
import civic_materials as MATS
import civic_hand as H
from mathutils import Vector, Matrix

ROOT = "Civic_Driver"
GRIP_ANGLE = 30.0   # mains à 10 h 10, comme driver.gd
C_G2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))     # Blender = C · Godot

def godot_tf(x_axis, y_axis, z_axis, origin):
    """Transform objet Blender équivalente à Transform3D(Basis(x, y, z), origin) de Godot."""
    Bg = Matrix((x_axis, y_axis, z_axis)).transposed(); Bb = C_G2B @ Bg @ C_G2B.transposed()
    return Matrix.Translation(C_G2B @ Vector(origin)) @ Bb.to_4x4()

def bone_tf(frm, to, up_hint=None):
    """Même construction que _set_bone de driver.gd : -Z local = from -> to ; up_hint (repère Godot) fixe le roulis."""
    frm, to = Vector(frm), Vector(to); d = to - frm; fwd = d.normalized()
    up = Vector(up_hint).normalized() if up_hint is not None else Vector((0, 1, 0))
    if abs(fwd.dot(up)) > 0.995: up = Vector((0, 0, -1))
    right = fwd.cross(up).normalized(); nup = right.cross(fwd).normalized()
    return godot_tf(right, nup, -fwd, frm), d.length

def rotx_axes(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return Vector((1, 0, 0)), Vector((0, c, s)), Vector((0, -s, c))

def solve_elbow(shoulder, hand, pole):
    d = hand - shoulder; raw = d.length; n = d/raw
    dd = max(min(raw, D.UPPER_ARM + D.FOREARM - 0.02), abs(D.UPPER_ARM - D.FOREARM) + 0.02)
    l = (D.UPPER_ARM**2 - D.FOREARM**2 + dd**2)/(2*dd); h = math.sqrt(max(D.UPPER_ARM**2 - l**2, 0.0))
    pd = pole - shoulder; pd = pd - n*pd.dot(n)
    return shoulder + n*l + pd.normalized()*h

# --- profils des membres (t le long du segment, rx, rz) ---
UPPER_PROF = [(-0.14, 0.022, 0.022), (-0.07, 0.048, 0.046), (0.05, 0.052, 0.05), (0.25, 0.049, 0.047), (0.40, 0.047, 0.046), (0.43, 0.047, 0.046),
              (0.45, 0.041, 0.040), (0.62, 0.042, 0.041), (0.85, 0.038, 0.037), (1.0, 0.034, 0.033), (1.08, 0.026, 0.026), (1.13, 0.012, 0.012)]
FORE_PROF = [(-0.10, 0.016, 0.016), (-0.02, 0.033, 0.033), (0.12, 0.040, 0.038), (0.35, 0.036, 0.034), (0.60, 0.030, 0.028), (0.78, 0.026, 0.022), (0.85, 0.025, 0.020), (0.90, 0.016, 0.013)]
THIGH_PROF = [(-0.12, 0.035, 0.035), (-0.02, 0.074, 0.070), (0.20, 0.074, 0.070), (0.50, 0.068, 0.064), (0.80, 0.060, 0.058), (0.97, 0.054, 0.052), (1.06, 0.044, 0.044), (1.13, 0.020, 0.020)]
SHIN_PROF = [(-0.10, 0.028, 0.028), (-0.01, 0.056, 0.054), (0.18, 0.058, 0.062), (0.45, 0.052, 0.054), (0.75, 0.047, 0.047), (0.90, 0.046, 0.046),
             (0.925, 0.046, 0.046), (0.94, 0.036, 0.034), (1.0, 0.035, 0.033), (1.06, 0.026, 0.024), (1.10, 0.010, 0.010)]

def ring_xz(y, rx, rz, cx=0.0, cz=0.0, n=16):
    return [(cx + rx*math.cos(2*math.pi*k/n), y, cz + rz*math.sin(2*math.pi*k/n)) for k in range(n)]

def ring_xy(z, rx, ry, cx=0.0, cy=0.0, n=20):
    return [(cx + rx*math.cos(2*math.pi*k/n), cy + ry*math.sin(2*math.pi*k/n), z) for k in range(n)]

def limb(name, Lseg, prof, mats, col, idx_fn=None):
    return L.loft(name, [ring_xz(t*Lseg, rx, rz) for (t, rx, rz) in prof], mats, col, idx_fn=idx_fn)

def hand(nm, side, M, col):
    """Main de l'asset Player_Arms posée en prise (civic_hand) dans le repère du volant : origine au centre de la jante, jante
    le long de Y, dos de la main côté conducteur (+Z), doigts enroulés vers l'extérieur (side*X), pouce le long de la jante (+Y)."""
    return H.build_hand(nm, side, M['hand'], col)

def foot(nm, M, col):
    root = L.empty(f"DRV_Foot_{nm}", (0, 0, 0), col, size=0.05)
    upper = [(-0.055, 0.022, 0.016, -0.028), (-0.035, 0.040, 0.028, -0.026), (0.0, 0.044, 0.036, -0.021), (0.04, 0.046, 0.033, -0.024), (0.09, 0.047, 0.027, -0.031),
             (0.14, 0.049, 0.021, -0.036), (0.19, 0.046, 0.016, -0.040), (0.225, 0.036, 0.012, -0.043), (0.248, 0.016, 0.006, -0.047)]
    L.loft(f"DRV_Foot_{nm}_Upper", [ring_xz(y, rx, rz, cz=cz) for (y, rx, rz, cz) in upper], M['shoe'], col, parent=root)
    sole = [(-0.058, 0.024, 0.008, -0.050), (-0.03, 0.044, 0.009, -0.050), (0.04, 0.05, 0.009, -0.050), (0.12, 0.052, 0.009, -0.050), (0.20, 0.050, 0.009, -0.050), (0.25, 0.022, 0.008, -0.050)]
    L.loft(f"DRV_Foot_{nm}_Sole", [ring_xz(y, rx, rz, cz=cz) for (y, rx, rz, cz) in sole], M['sole'], col, parent=root, subsurf=1)
    L.box(f"DRV_Foot_{nm}_Laces", (0.034, 0.07, 0.006), (0, 0.085, 0.004), M['lace'], col, parent=root, bevel=0.002)
    L.box(f"DRV_Foot_{nm}_Collar", (0.07, 0.06, 0.012), (0, -0.01, 0.016), M['shoe'], col, parent=root, bevel=0.004)
    return root

def torso(M, col):
    """Origine SPINE (au sol, sous l'axe du buste) ; +Y local = avant, +Z = haut. Profondeur = boîte chest de driver.gd. Sans cou ni tête."""
    rings = [(0.44, 0.165, 0.115, 0.055), (0.50, 0.19, 0.13, 0.055), (0.555, 0.185, 0.128, 0.055), (0.62, 0.17, 0.12, 0.05), (0.70, 0.175, 0.122, 0.048),
             (0.78, 0.185, 0.126, 0.046), (0.86, 0.20, 0.126, 0.046), (0.92, 0.21, 0.115, 0.05), (0.965, 0.175, 0.09, 0.07), (1.0, 0.10, 0.068, 0.095), (1.02, 0.062, 0.054, 0.105)]
    t = L.loft("DRV_Torso", [ring_xy(z, rx, ry, cy=cy) for (z, rx, ry, cy) in rings], [M['shirt'], M['jeans']], col, idx_fn=lambda c: 1 if c.z < 0.552 else 0)
    L.loft("DRV_Belt", [ring_xy(z, 0.191, 0.126, cy=0.06) for z in (0.54, 0.568)], M['belt'], col, parent=t, subsurf=1)
    L.box("DRV_Buckle", (0.045, 0.008, 0.03), (0, 0.06 + 0.126 + 0.003, 0.554), M['buckle'], col, parent=t, bevel=0.002)
    # pas de cou ni de tête : vue subjective, la caméra est à la place de la tête (demande utilisateur)
    return t

def build():
    L.clear_collection(ROOT); col = L.get_col(ROOT); M = MATS.driver()
    parts = {}
    sleeve = lambda c: 0 if c.y < 0.44*D.UPPER_ARM else 1
    hem = lambda c: 0 if c.y < 0.93*D.SHIN_LEN else 1
    for nm in ("L", "R"):
        # pas de bras ni d'avant-bras (demande utilisateur : mains seules, façon FPS) ; H.arm_part() reste disponible
        parts[f"Thigh_{nm}"] = limb(f"DRV_Thigh_{nm}", D.THIGH_LEN, THIGH_PROF, M['jeans'], col)
        parts[f"Shin_{nm}"] = limb(f"DRV_Shin_{nm}", D.SHIN_LEN, SHIN_PROF, [M['jeans'], M['shirt']], col, hem)
    parts["Hand_L"] = H.build_hand_rig("L", -1, M['hand'], col); parts["Hand_R"] = H.build_hand_rig("R", 1, M['hand'], col)   # mains articulées (squelette + poses)
    parts["Foot_L"] = foot("L", M, col); parts["Foot_R"] = foot("R", M, col)
    t = torso(M, col)
    # --- pose de repos (mêmes maths que driver.gd) ---
    wx, wy, wz = rotx_axes(D.WHEEL_TILT)
    wc = Vector((D.WHEEL_C.x, D.WHEEL_C.z, -D.WHEEL_C.y + D.COLUMN_PULL))   # centre du volant en repère Godot (WHEEL_C est en Blender), colonne ramenée comme dans cabin.gd
    ca, sa = math.cos(math.radians(GRIP_ANGLE)), math.sin(math.radians(GRIP_ANGLE))      # mains à 10 h 10 (GRIP_ANGLE de driver.gd)
    xr, zr = wx*ca - wz*sa, wx*sa + wz*ca; xl, zl = wx*ca + wz*sa, -wx*sa + wz*ca
    hand_l = wc + xl*(-D.WHEEL_RADIUS); hand_r = wc + xr*(D.WHEEL_RADIUS)
    parts["Hand_L"].matrix_world = godot_tf(xl, wy, zl, hand_l); parts["Hand_R"].matrix_world = godot_tf(xr, wy, zr, hand_r)
    bpy.context.view_layer.update()
    def wrist_g(root):          # poignet du modèle (vide DRV_Wrist_*) en repère Godot : l'avant-bras y aboutit, comme dans driver.gd
        w = next((c for c in root.children if c.name.startswith("DRV_Wrist_")), None)
        pw = (root.matrix_world @ w.location) if w else root.matrix_world.translation
        return Vector((pw.x, pw.z, -pw.y))
    rest = {"Thigh": D.THIGH_LEN, "Shin": D.SHIN_LEN}
    for key, frm, to in (("Thigh_L", D.HIP_L, D.KNEE_L), ("Shin_L", D.KNEE_L, D.ANKLE_L), ("Thigh_R", D.HIP_R, D.KNEE_R), ("Shin_R", D.KNEE_R, D.ANKLE_R)):
        tf, d = bone_tf(frm, to); parts[key].matrix_world = tf; parts[key].scale = (1.0, d/rest[key.split("_")[0]], 1.0)
    fx, fy, fz = rotx_axes(math.degrees(-0.07))
    parts["Foot_L"].matrix_world = godot_tf(fx, fy, fz, D.ANKLE_L); parts["Foot_R"].matrix_world = godot_tf(fx, fy, fz, D.ANKLE_R)
    t.matrix_world = godot_tf(Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), D.SPINE)
    n = len(col.all_objects); print("Driver built:", n, "objects"); return n

if __name__ == "__main__":
    build()
