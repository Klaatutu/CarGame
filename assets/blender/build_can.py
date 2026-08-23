# -*- coding: utf-8 -*-
"""
build_can.py — canettes 33 cl pour Route de nuit. Pour chaque boisson (nosleep, cariboon, kombo) : une version
intacte (collection "Can_<boisson>", objet CAN_<Boisson>) et LA MÊME écrasée ("Can_<boisson>_crushed",
CAN_<Boisson>_Crushed) : même maillage, mêmes UV, même matériau, déformée par un champ spatial
(compression + plis en losanges + enfoncement + couvercle penché), avec des paramètres propres à chaque boisson
pour que trois canettes écrasées côte à côte ne soient pas identiques.

Exécution :
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python assets/blender/build_can.py
  ou, Blender ouvert : sys.path.insert(0, ".../assets/blender"); import build_can; build_can.main()

Sorties : assets/models/can_<boisson>.glb + can_<boisson>_crushed.glb (texture embarquée), assets/blender/can.blend,
          assets/blender/renders/cans_34.png (les six) et cans_crushed.png (rangée des écrasées)
Textures : assets/blender/textures/can_label_<boisson>.png — générées par make_can_labels.py (Python système + Pillow)
           à partir des visuels de assets/blender/textures/src/.

Repère : Z vertical, base de la canette en z = 0, axe en (0, 0). glTF Y-up → Godot (x, z, -y) ;
chaque canette est exportée à l'origine, posée sur y = 0 dans Godot. Face avant de l'étiquette vers -Y.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path: sys.path.insert(0, HERE)
from civic_lib import (get_col, clear_collection, bm_to_obj, shade, tex_mat, mat, node_of, aim,
                       link_obj, camera, render_views, export_glb, save_blend)

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")
TEXDIR = os.path.join(HERE, "textures")

# ---------------------------------------------------------------------------
# Dimensions (canette 33 cl standard : Ø 66 mm, h 116 mm)
# ---------------------------------------------------------------------------
H = 0.116                              # hauteur totale
R = 0.033                              # rayon du corps
Z_BODY0, Z_BODY1 = 0.008, 0.098        # corps cylindrique (étiquette, zone des plis)
Z_LID = 0.1115                         # fond du creux du couvercle
STEPS = 36                             # segments autour de l'axe (6 par lobe de pli)

PROFILE = [  # (r, z) du centre du fond au centre du couvercle
    (0.000, 0.008), (0.012, 0.0075), (0.020, 0.005),      # dôme concave du fond
    (0.0245, 0.000), (0.0275, 0.000),                     # anneau d'appui
    (0.0305, 0.003), (R, Z_BODY0),                        # épaule basse
    (R, Z_BODY1),                                         # corps
    (0.0305, 0.105), (0.0290, 0.110), (0.0287, 0.1125),   # col
    (0.0297, 0.1140), (0.0297, 0.1160), (0.0280, 0.1160), # rebord serti
    (0.0265, 0.1135), (0.0258, Z_LID),                    # creux du couvercle
    (0.000, Z_LID),
]

# Boissons et paramètres d'écrasement propres à chacune :
#   k = hauteur conservée du corps, creases = plis par rangée (losanges : 2 rangées décalées), crease_a = profondeur
#   des plis (fraction du rayon), dent/dent_dir = enfoncement principal et sa direction (rad ; -Y = face avant),
#   phase = décalage angulaire des plis, tilt = inclinaison du couvercle (°, signe = sens), lean = cisaillement x += lean·z
#   u_off = décalage des UV (sans modulo : la texture se répète) pour amener le logo de l'atlas en face avant (-Y, u = 0.75)
DRINKS = ("nosleep", "cariboon", "kombo")
VARIANTS = {
    "nosleep":  dict(k=0.40, creases=5, crease_a=0.26, dent=0.30, dent_dir=-1.1, phase=0.3, tilt=15.0, lean=0.10, u_off=0.0),
    "cariboon": dict(k=0.35, creases=6, crease_a=0.24, dent=0.34, dent_dir=-0.7, phase=1.1, tilt=-12.0, lean=-0.08, u_off=-0.26),
    "kombo":    dict(k=0.46, creases=5, crease_a=0.28, dent=0.26, dent_dir=-1.9, phase=2.0, tilt=9.0, lean=0.12, u_off=0.0),
}


def clamp(v, lo=0.0, hi=1.0): return max(lo, min(hi, v))

def smoothstep(e0, e1, x):
    x = clamp((x - e0) / (e1 - e0)); return x * x * (3.0 - 2.0 * x)

def ang_diff(a, b): return (a - b + math.pi) % (2 * math.pi) - math.pi

def dense_profile(step=0.003):
    """Subdivise les segments verticaux longs tous les `step` m pour que l'écrasement ait des anneaux à plier."""
    out = []
    for i, (r, z) in enumerate(PROFILE):
        out.append((r, z))
        if i + 1 < len(PROFILE):
            r1, z1 = PROFILE[i + 1]
            if z1 - z > step * 1.5 and abs(r1 - r) < 1e-9:
                n = int(round((z1 - z) / step))
                out += [(r, z + (z1 - z) * k / n) for k in range(1, n)]
    return out

# ---------------------------------------------------------------------------
# Géométrie (tout dans un seul bmesh → un seul objet, un seul matériau)
# ---------------------------------------------------------------------------
def add_lathe(bm, uv, profile, steps=STEPS, u_off=0.0):
    """Révolution autour de Z. UV cylindriques : u = i/steps + u_off (pas de couture à recoller), v = z/H."""
    rings = []
    for r, z in profile:
        if r < 1e-6: rings.append([bm.verts.new((0.0, 0.0, z))])
        else: rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / steps), r * math.sin(2 * math.pi * i / steps), z))
                            for i in range(steps)])
    def setuv(face, uvs):
        for l, (u, v) in zip(face.loops, uvs): l[uv].uv = (u, v)
    for a, b in zip(rings, rings[1:]):
        va, vb = a[0].co.z / H, b[0].co.z / H
        for i in range(steps):
            j = (i + 1) % steps; u0, u1 = i / steps + u_off, (i + 1) / steps + u_off
            if len(a) == 1 and len(b) == 1: continue
            if len(a) == 1:
                f = bm.faces.new((a[0], b[i], b[j])); setuv(f, [((u0 + u1) / 2, va), (u0, vb), (u1, vb)])
            elif len(b) == 1:
                f = bm.faces.new((a[i], a[j], b[0])); setuv(f, [(u0, va), (u1, va), ((u0 + u1) / 2, vb)])
            else:
                f = bm.faces.new((a[i], a[j], b[j], b[i])); setuv(f, [(u0, va), (u1, va), (u1, vb), (u0, vb)])

def add_prism(bm, uv, pts, z0, z1, uvpt):
    """Extrusion verticale d'un contour 2D (liste (x, y)), bouchons en n-gones. UV sur un pixel fixe."""
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts]
    faces = [bm.faces.new(tuple(reversed(lo))), bm.faces.new(tuple(hi))]
    m = len(pts)
    for i in range(m):
        j = (i + 1) % m
        faces.append(bm.faces.new((lo[i], lo[j], hi[j], hi[i])))
    for f in faces:
        for l in f.loops: l[uv].uv = uvpt
    return faces

def add_tab(bm, uv):
    """Languette : stade 21 × 10.5 mm, 0.7 mm d'épaisseur, à plat sur le couvercle, rivet vers le centre."""
    L, W, T = 0.021, 0.0105, 0.0007
    n, rr = 8, W / 2
    cy0, cy1 = -0.0045, -0.0045 + L - W          # centres des deux demi-cercles
    pts = [(rr * math.cos(a), cy0 + rr * math.sin(a)) for a in (math.pi + math.pi * k / n for k in range(n + 1))]
    pts += [(rr * math.cos(a), cy1 + rr * math.sin(a)) for a in (math.pi * k / n for k in range(n + 1))]
    add_prism(bm, uv, pts, Z_LID + 0.0001, Z_LID + 0.0001 + T, (0.5, 0.95))        # pixel alu de l'atlas
    riv = [(0.0025 * math.cos(2 * math.pi * k / 12), -0.0025 + 0.0025 * math.sin(2 * math.pi * k / 12)) for k in range(12)]
    add_prism(bm, uv, riv, Z_LID + 0.0001 + T, Z_LID + 0.0001 + T + 0.0007, (0.5, 0.93))

def can_material(drink):
    m = tex_mat(f"CAN_{drink}", os.path.join(TEXDIR, f"can_label_{drink}.png"), rough=0.38, interp='Closest', specular=0.7)
    b = node_of(m.node_tree, 'ShaderNodeBsdfPrincipled'); b.inputs['Metallic'].default_value = 0.35
    return m

def build_can(name, col, material, deform=None, sharp_angle=60, u_off=0.0):
    bm = bmesh.new(); uv = bm.loops.layers.uv.new("UVMap")
    add_lathe(bm, uv, dense_profile(), u_off=u_off); add_tab(bm, uv)
    if deform:
        for v in bm.verts: v.co = deform(v.co)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bm_to_obj(bm, name, material, col)
    shade(ob, angle=sharp_angle)
    return ob

# ---------------------------------------------------------------------------
# Champ d'écrasement (fonction lisse de l'espace → appliquée à tous les sommets, languette comprise)
# ---------------------------------------------------------------------------
def make_crush(P):
    k, n_cr, crease_a, dent_a, dent_dir = P["k"], P["creases"], P["crease_a"], P["dent"], P["dent_dir"]
    phase0, tilt, lean = P["phase"], math.radians(P["tilt"]), P["lean"]
    zc = Z_BODY0 + (Z_BODY1 - Z_BODY0) * k            # sommet du corps écrasé = pivot du couvercle

    def crush(p):
        x, y, z = p
        r = math.hypot(x, y); th = math.atan2(y, x)
        t = clamp((z - Z_BODY0) / (Z_BODY1 - Z_BODY0))          # 0 en bas du corps, 1 en haut
        inside = 0.0 < t < 1.0                                   # les anneaux sertis (fond, col) restent ronds
        # Deux rangées de plis en V vers l'intérieur (1 - |cos|), séparées par une arête horizontale à mi-hauteur
        # (t = 0.5, rayon conservé) ; la rangée haute est décalée d'une demi-période → losanges.
        w = abs(math.sin(2 * math.pi * t)) ** 0.7 if inside else 0.0
        phase = phase0 + (math.pi / 2) * smoothstep(0.42, 0.58, t)
        crease = 1.0 - abs(math.cos(n_cr * th / 2 + phase))
        # Ovalisation légère + enfoncement principal d'un côté, sur toute la hauteur du corps
        wd = math.sin(math.pi * t) ** 0.8 if inside else 0.0
        dent = 0.05 * math.cos(2 * th + 1.3) + dent_a * math.exp(-(ang_diff(th, dent_dir) / 0.8) ** 2)
        r2 = r * (1.0 - w * crease_a * crease - wd * dent)
        # Compression du corps seulement (fond et couvercle conservent leur hauteur)
        if z < Z_BODY0: z2 = z
        elif z <= Z_BODY1: z2 = Z_BODY0 + (z - Z_BODY0) * k
        else: z2 = zc + (z - Z_BODY1)
        x2, y2 = r2 * math.cos(th), r2 * math.sin(th)
        # Couvercle penché : rotation autour de Y, pivot au sommet du corps écrasé, fondue sur les 2.5 derniers cm
        a = tilt * clamp((z - (Z_BODY1 - 0.025)) / 0.025)
        dx, dz = x2, z2 - zc
        x3 = dx * math.cos(a) + dz * math.sin(a)
        z3 = -dx * math.sin(a) + dz * math.cos(a) + zc
        x3 += lean * z3                                          # la canette penche
        return Vector((x3, y2, z3))
    return crush

# ---------------------------------------------------------------------------
# Scène de contrôle (sol, lumières, caméras) — collection Can_Env, jamais exportée
# ---------------------------------------------------------------------------
def setup_scene():
    scene = bpy.context.scene
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(bpy.data.collections): clear_collection(c.name)
    env = get_col("Can_Env")
    w = scene.world or bpy.data.worlds.new("World"); scene.world = w; w.use_nodes = True
    bg = node_of(w.node_tree, 'ShaderNodeBackground')
    bg.inputs['Color'].default_value = (0.28, 0.29, 0.33, 1.0); bg.inputs['Strength'].default_value = 0.35
    scene.view_settings.view_transform = 'Standard'     # couleurs telles que Godot les affichera (pas de tonemapping)
    # sol
    bm = bmesh.new(); s = 0.8
    bm.faces.new([bm.verts.new(p) for p in ((-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0))])
    bm_to_obj(bm, "ENV_Floor", mat("ENV_Floor", (0.20, 0.20, 0.22), rough=0.85), env)
    # lumières
    tgt = (0.0, 0.0, 0.05)
    for name, energy, size, color, loc in (("ENV_Key", 14.0, 0.5, (1.0, 0.93, 0.85), (0.45, -0.50, 0.55)),
                                           ("ENV_Fill", 5.0, 0.8, (0.8, 0.88, 1.0), (-0.50, -0.25, 0.40)),
                                           ("ENV_Rim", 7.0, 0.4, (1.0, 1.0, 1.0), (0.10, 0.60, 0.45))):
        l = bpy.data.lights.new(name, 'AREA'); l.energy = energy; l.size = size; l.color = color
        ob = bpy.data.objects.new(name, l); link_obj(ob, env); ob.location = loc; aim(ob, tgt)
    # caméras : les six en 3/4, puis la rangée des écrasées de face
    camera("CAM_34", (0.34, -0.46, 0.26), (0.0, 0.0, 0.05), 50, env)
    camera("CAM_Crushed", (0.0, -0.50, 0.20), (0.0, -0.03, 0.035), 40, env)
    scene.render.resolution_x, scene.render.resolution_y = 1400, 800
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    return env

# ---------------------------------------------------------------------------
def tri_count(ob): return sum(len(p.vertices) - 2 for p in ob.data.polygons)

def main(export=True, render=True, save=True):
    for d in DRINKS:
        if not os.path.exists(os.path.join(TEXDIR, f"can_label_{d}.png")):
            raise FileNotFoundError(f"can_label_{d}.png manquante : lancer d'abord make_can_labels.py (Python système + Pillow)")
    setup_scene()
    cans = {}
    for d in DRINKS:
        m = can_material(d); cap = d.capitalize(); P = VARIANTS[d]
        intact = build_can(f"CAN_{cap}", get_col(f"Can_{d}"), m, u_off=P["u_off"])
        crushed = build_can(f"CAN_{cap}_Crushed", get_col(f"Can_{d}_crushed"), m, deform=make_crush(P), sharp_angle=45, u_off=P["u_off"])
        zs = [v.co.z for v in crushed.data.vertices]
        print(f"{cap} : {tri_count(intact)} tris, intacte h = {H*1000:.0f} mm, écrasée h = {max(zs)*1000:.0f} mm")
        cans[d] = (intact, crushed)
    os.makedirs(MODELS, exist_ok=True)
    if export:
        for d in DRINKS:
            for colname, fname in ((f"Can_{d}", f"can_{d}.glb"), (f"Can_{d}_crushed", f"can_{d}_crushed.glb")):
                n, mb = export_glb(colname, os.path.join(MODELS, fname)); print(f"export {fname} : {n} objet(s), {mb} Mo")
    if render:
        for i, d in enumerate(DRINKS):                      # intactes derrière, écrasées devant
            cans[d][0].location = ((i - 1) * 0.15, 0.07, 0.0)
            cans[d][1].location = ((i - 1) * 0.15, -0.07, 0.0)
        paths = render_views([("CAM_34", "cans_34.png", []), ("CAM_Crushed", "cans_crushed.png", [])],
                             os.path.join(HERE, "renders"))
        print("rendus :", paths)
        for d in DRINKS:
            cans[d][0].location = cans[d][1].location = (0.0, 0.0, 0.0)
    if save: save_blend(os.path.join(HERE, "can.blend"))

if __name__ == "__main__":
    main()
