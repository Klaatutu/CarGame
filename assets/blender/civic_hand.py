# -*- coding: utf-8 -*-
"""
civic_hand — mains et bras du conducteur : maillage de l'asset « Player_Arms » fourni par l'utilisateur
(assets/blender/ref/Player_Arms.blend, texture assets/blender/textures/player_hands.png), intégré tel quel.

Le bras gauche de l'asset (Cube.002 + Armature.001 : un seul maillage rigged, épaule → bouts des doigts) est chargé en
repère armature, mis à l'échelle (SCALE, anisotrope : l'asset est allongé), puis découpé en trois parties par tranches
le long du bras : bras (épaule → coude), avant-bras (coude → fin de la manche), main (paume + doigts + pouce) ; la zone
« poignet » de l'asset entre les deux est abandonnée, la manche étirée arrive à la base de la paume. Les trous des
coupes sont rebouchés. Doigts et pouce sont raccourcis (FINGER_SCALE, THUMB_*_SCALE) : l'asset est allongé.
- Main : posée en prise par skinning linéaire avec les poids de l'asset — les phalanges s'enroulent autour d'une barre
  d'axe X (la jante, wrap_chain), le pouce se couche le long de la jante — puis roulis ROLL autour de la jante et
  passage dans le repère « volant » de driver.gd (origine au centre de la jante, jante le long de Y, dos de la main vers
  +Z, doigts vers l'extérieur). Main droite = miroir de la gauche. Un vide DRV_Wrist_<L/R> (base de la paume = queue de
  l'os Wrist) marque le poignet : driver.gd y fait aboutir l'avant-bras.
- Bras et avant-bras : segments rigides, origine à l'articulation proximale, +Y local le long de l'os (= -Z Godot,
  convention de driver.gd), étirés à la longueur du jeu (UPPER_ARM / FOREARM), avec recouvrement aux articulations
  (OVERLAP) et le bras enfoncé dans le buste (SHOULDER_IN). Côté droit = miroir.
"""
import bpy, bmesh, math, os
import numpy as np
from mathutils import Vector, Matrix, Quaternion
import civic_lib as L

HERE = os.path.dirname(os.path.abspath(__file__))
REF_BLEND = os.path.join(HERE, "ref", "Player_Arms.blend")
REF_OBJECTS = ("Cube.002", "Armature.001")          # bras gauche de l'asset (le droit est son miroir)
TEX = os.path.join(HERE, "textures", "player_hands.png")
SCALE = (0.022, 0.031, 0.029)       # unités de l'asset → m : le long du bras, en largeur (y), en épaisseur (z) ; l'asset est allongé → main visible ≈ 18 cm
FINGER_SCALE = 0.90                 # raccourcit les doigts (autour de l'articulation MCP)
THUMB_META_SCALE, THUMB_DISTAL_SCALE = 0.85, 0.70   # raccourcit le pouce (métacarpe, phalange distale)
BAR_R = 0.0165                      # rayon de la jante
BAR_R_WIDE = 0.032                  # variante « prise large » (canette) : DRV_HandWide_*, affichée par driver.gd quand l'objet tenu est gros
BAR_BACK = 0.030                    # la jante passe 3 cm derrière les articulations
FINGER_HALF_T = 0.009               # demi-épaisseur d'un doigt (rayon d'enroulement = jante + doigt)
ROLL = -45.0                        # rotation de la main autour de la jante : poignet vers le conducteur
THUMB_META_OFFSET = (0.040, -0.012, 0.010)   # cible du MCP du pouce : (+X côté pouce, par rapport à jante - rayon, au-dessus du centre de jante)
THUMB_DISTAL_DIR = (0.96, 0.05, -0.25)       # direction du pouce couché le long de la jante (côté intérieur)
UV_CAP_SLEEVE = (0.25, 0.75); UV_CAP_SKIN = (0.16, 0.35)   # UV des bouchons : manche en jean / peau
FINGERS = ("Index", "Middle", "Ring", "Little")
OVERLAP = 0.6                       # recouvrement des segments de part et d'autre des articulations (unités de l'asset)
SHOULDER_IN = 0.03                  # le bras s'enfonce dans le buste (m)


# ======================================================================================================================
# Chargement de l'asset
# ======================================================================================================================
_REF = {}

def load_reference():
    """Bras gauche de l'asset en repère armature : sommets V (n,3), faces F, UV par boucle, poids W (n, os) normalisés,
    têtes/queues d'os. Les données importées sont purgées après lecture (une fois par session)."""
    if _REF: return _REF
    colls = (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images)
    before = [{d.name for d in c} for c in colls]
    with bpy.data.libraries.load(REF_BLEND, link=False) as (src, dst):
        dst.objects = list(REF_OBJECTS)
    objs = [o for o in dst.objects if o]
    ob = next(o for o in objs if o.type == 'MESH'); arm = next(o for o in objs if o.type == 'ARMATURE')
    for o in objs: bpy.context.scene.collection.objects.link(o)      # lien temporaire : matrices monde évaluées
    bpy.context.view_layer.update()
    M = arm.matrix_world.inverted() @ ob.matrix_world; me = ob.data
    V = np.array([list(M @ v.co) for v in me.vertices], dtype=float)
    F = [list(p.vertices) for p in me.polygons]
    uvl = me.uv_layers.active.data
    UV = [[(uvl[l].uv.x, uvl[l].uv.y) for l in p.loop_indices] for p in me.polygons]
    names = [g.name for g in ob.vertex_groups]; W = np.zeros((len(V), len(names)))
    for v in me.vertices:
        for g in v.groups: W[v.index, g.group] = g.weight
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    bones = {b.name: (np.array(b.head_local, dtype=float), np.array(b.tail_local, dtype=float)) for b in arm.data.bones}
    for o in objs: bpy.data.objects.remove(o, do_unlink=True)
    for c, names_before in zip(colls, before):          # ne retire que ce que l'import a apporté (pas les matériaux du conducteur)
        for d in [d for d in c if d.name not in names_before]: c.remove(d)
    _REF.update(V=V, F=F, UV=UV, names=names, W=W, bones=bones)
    return _REF


def _joints(ref):
    """x (unités asset) de l'épaule (bord du maillage), du coude (tête de LowArm), de la fin de la manche (queue de LowArm)
    et de la base de la paume (queue de Wrist)."""
    b = ref["bones"]
    return float(ref["V"][:, 0].min()), float(b["LowArm.L"][0][0]), float(b["LowArm.L"][1][0]), float(b["Wrist.L"][1][0])


def _face_parts(ref):
    """Parties de chaque face par tranches le long du bras, avec recouvrement OVERLAP autour du coude et du poignet :
    une face peut appartenir à deux segments, qui se chevauchent donc aux articulations (pas de trou quand le bras plie)."""
    V = ref["V"]; x_s, x_e, x_c, x_w = _joints(ref); parts = []
    for f in ref["F"]:
        cx = float(V[f, 0].mean()); p = set()
        if cx <= x_e + OVERLAP: p.add("upper")
        if x_e - OVERLAP <= cx <= x_c + OVERLAP: p.add("fore")      # la zone « poignet » de l'asset (x_c → x_w) n'est pas reprise
        if cx >= x_w - OVERLAP: p.add("hand")
        parts.append(p)
    return parts


# ======================================================================================================================
# Pose de prise
# ======================================================================================================================
def wrap_chain(mcp, lengths, cy, cz, R):
    """Chaîne de phalanges partant de mcp, s'enroulant dans le plan YZ autour du cercle (cy, cz, R) : le bout de chaque
    phalange est posé sur le cercle (premier angle de flexion cumulé qui l'atteint). Renvoie points et angles cumulés."""
    pts = [Vector(mcp)]; angs = []; phi = 0.0
    for i, Lg in enumerate(lengths):
        p = pts[-1]; lo = phi + math.radians(8) if i > 0 else 0.0; best = None; hit = None; k = 0
        while True:
            a = lo + math.radians(k * 0.1)
            if a > phi + math.radians(115): break
            q = Vector((p.x, p.y + Lg * math.cos(a), p.z - Lg * math.sin(a)))
            dist = math.hypot(q.y - cy, q.z - cz)
            if best is None or abs(dist - R) < best[0]: best = (abs(dist - R), a, q)
            if dist <= R: hit = (a, q); break
            k += 1
        phi, q = hit if hit else best[1:]
        pts.append(q); angs.append(phi)
    return pts, angs


def _rx(a):
    """Flexion autour de X : (0, 1, 0) → (0, cos a, -sin a)."""
    c, s = math.cos(a), math.sin(a); return np.array([[1.0, 0.0, 0.0], [0.0, c, s], [0.0, -s, c]])


def _rot_between(a, b):
    q = Vector(a).rotation_difference(Vector(b)); return np.array(q.to_matrix(), dtype=float)


def _hand_transforms(ref, to_c, bar_y, bar_z, bar_r=BAR_R):
    """Transformation rigide (R, t) par os pour la prise : doigts enroulés sur la jante, pouce le long de la jante.
    Les os absents du dictionnaire (poignet, métacarpes) restent immobiles."""
    bones = ref["bones"]; T = {}; I = np.eye(3)
    def scale_about(c, d, s):          # affine (A, b) : homothétie de rapport s le long de d, autour de c
        d = np.asarray(d, dtype=float); d = d / np.linalg.norm(d); A = I + (s - 1.0) * np.outer(d, d); return A, c - A @ c
    def compose(A2, b2, A1, b1): return A2 @ A1, A2 @ b1 + b2
    for fn in FINGERS:
        h0 = [to_c(bones[f"{fn}{k}.L"][0]) for k in (2, 3, 4)]; tip0 = to_c(bones[f"{fn}4.L"][1])
        S, bS = scale_about(h0[0], tip0 - h0[0], FINGER_SCALE)           # doigt raccourci autour du MCP
        h = [S @ p + bS for p in h0]; tip = S @ tip0 + bS
        Ls = [float(np.linalg.norm(h[1] - h[0])), float(np.linalg.norm(h[2] - h[1])), float(np.linalg.norm(tip - h[2]))]
        _, angs = wrap_chain(Vector(h[0]), Ls, bar_y, bar_z, bar_r + FINGER_HALF_T)
        R_prev, t_prev, a_prev = I, np.zeros(3), 0.0
        for k in range(3):
            Rl = _rx(angs[k] - a_prev); tl = h[k] - Rl @ h[k]
            R = R_prev @ Rl; t = R_prev @ tl + t_prev
            T[f"{fn}{k + 2}.L"] = compose(R, t, S, bS); R_prev, t_prev, a_prev = R, t, angs[k]
    h1, t1 = (to_c(v) for v in bones["Thumb1.L"]); h2 = to_c(bones["Thumb2.L"][0]); h3, t3 = (to_c(v) for v in bones["Thumb3.L"])
    S1, bS1 = scale_about(h1, t1 - h1, THUMB_META_SCALE)                 # métacarpe raccourci vers la racine
    S3, bS3 = scale_about(h3, t3 - h3, THUMB_DISTAL_SCALE)               # phalange distale raccourcie
    target = np.array([h1[0] + THUMB_META_OFFSET[0], bar_y - bar_r + THUMB_META_OFFSET[1], bar_z + THUMB_META_OFFSET[2]])
    R1 = _rot_between(t1 - h1, target - h1); A1, b1 = compose(R1, h1 - R1 @ h1, S1, bS1)
    c = A1 @ h2 + b1                                                      # MCP du pouce posé
    R3l = _rot_between(R1 @ (t3 - h3), np.array(THUMB_DISTAL_DIR))
    A3, b3 = compose(R3l, c - R3l @ c, *compose(A1, b1, S3, bS3))
    T["Thumb1.L"] = (A1, b1); T["Thumb2.L"] = (A3, b3); T["Thumb3.L"] = (A3, b3)
    return T


def _skin(Vc, W, names, T):
    """Skinning linéaire : p' = Σ w_os (R_os p + t_os)."""
    acc = np.zeros_like(Vc); wsum = np.zeros(len(Vc))
    for gi, n in enumerate(names):
        w = W[:, gi]; sel = w > 1e-6
        if not sel.any(): continue
        R, t = T.get(n, (np.eye(3), np.zeros(3)))
        acc[sel] += (Vc[sel] @ R.T + t) * w[sel, None]; wsum[sel] += w[sel]
    out = Vc.copy(); ok = wsum > 1e-6; out[ok] = acc[ok] / wsum[ok, None]
    return out


# ======================================================================================================================
# Maillages
# ======================================================================================================================
def _part_mesh(ref, part, coords, uv_cap, mirror=False):
    """bmesh d'une partie : faces de l'asset dont l'os dominant est dans la partie, UV de l'asset, trous rebouchés."""
    parts = _face_parts(ref)
    faces = [f for f, p in zip(ref["F"], parts) if part in p]; uvs = [u for u, p in zip(ref["UV"], parts) if part in p]
    used = sorted({i for f in faces for i in f}); remap = {i: k for k, i in enumerate(used)}
    bm = bmesh.new(); uv_layer = bm.loops.layers.uv.new("UVMap")
    verts = [bm.verts.new(Vector(coords[i])) for i in used]
    for f, u in zip(faces, uvs):
        try: bf = bm.faces.new([verts[remap[i]] for i in f])
        except ValueError: continue
        bf.smooth = False
        for loop, uvv in zip(bf.loops, u): loop[uv_layer].uv = uvv
    res = bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
    for bf in res["faces"]:
        bf.smooth = False
        for loop in bf.loops: loop[uv_layer].uv = uv_cap
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if mirror: bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return bm


def _canon(ref):
    """Coordonnées canoniques (m) de la main gauche : origine à la base de la paume (queue de l'os Wrist), +Y vers les
    doigts (x asset), +Z dos de la main, pouce côté +X (= -y asset)."""
    sx, sy, sz = SCALE; x_w = ref["bones"]["Wrist.L"][1][0]
    return lambda p: np.array([-p[1] * sy, (p[0] - x_w) * sx, p[2] * sz])


def build_hand(nm, side, mat, col, bar_r=BAR_R, name="DRV_Hand", wrist=True):
    """Main `nm` ('L'/'R'), side = -1 gauche / +1 droite, refermée sur une barre de rayon `bar_r`. Renvoie le vide racine
    <name>_<nm> (origine = centre de la barre) avec le maillage <name>_<nm>_Mesh et, si `wrist`, le vide DRV_Wrist_<nm>."""
    ref = load_reference(); to_c = _canon(ref); bones = ref["bones"]
    Vc = np.stack([to_c(p) for p in ref["V"]])
    mcp_y = float(np.mean([to_c(bones[f"{fn}2.L"][0])[1] for fn in FINGERS]))
    palm = (Vc[:, 1] > mcp_y - 0.05) & (Vc[:, 1] < mcp_y) & (np.abs(Vc[:, 0]) < 0.045)
    bar_y = mcp_y - BAR_BACK; bar_z = float(Vc[palm, 2].min()) - bar_r - 0.002
    Vp = _skin(Vc, ref["W"], ref["names"], _hand_transforms(ref, to_c, bar_y, bar_z, bar_r))
    cr, sr = math.cos(math.radians(ROLL)), math.sin(math.radians(ROLL))
    def grip(p):        # → repère volant : X sortant (side), Y le long de la jante (pouce vers +Y), Z vers le conducteur
        x, y, z = p[0], p[1] - bar_y, p[2] - bar_z
        y, z = y * cr - z * sr, y * sr + z * cr
        return (side * y, x, z)
    Vg = np.array([grip(p) for p in Vp])
    bm = _part_mesh(ref, "hand", Vg, UV_CAP_SKIN, mirror=(side > 0))
    root = L.empty(f"{name}_{nm}", (0, 0, 0), col, size=0.05)
    ob = L.bm_to_obj(bm, f"{name}_{nm}_Mesh", mat, col); L.place(ob, parent=root)
    if wrist: L.empty(f"DRV_Wrist_{nm}", grip(to_c(bones["Wrist.L"][1])), col, parent=root, size=0.02)
    return root


def arm_part(name, kind, length, side, mat, col):
    """Segment 'upper' (bras) ou 'fore' (avant-bras) de l'asset, rigide : origine à l'articulation proximale, +Y local le
    long de l'os, étiré à `length` (m). side = -1 gauche (asset tel quel) / +1 droite (miroir)."""
    ref = load_reference(); sx, sy, sz = SCALE; x_s, x_e, x_c, x_w = _joints(ref)
    if kind == "upper":     # bord de l'épaule à -SHOULDER_IN (dans le buste), coude à `length`
        y = lambda x: -SHOULDER_IN + (x - x_s) * (length + SHOULDER_IN) / (x_e - x_s)
    else:                   # coude à 0, fin de la manche à `length` (= DRV_Wrist, base de la paume : la manche y arrive directement)
        y = lambda x: (x - x_e) * length / (x_c - x_e)
    V = np.array([[side * p[1] * sy, y(p[0]), p[2] * sz] for p in ref["V"]])
    bm = _part_mesh(ref, kind, V, UV_CAP_SLEEVE, mirror=(side > 0))
    return L.bm_to_obj(bm, name, mat, col)


# ======================================================================================================================
# Main articulée : squelette (os de l'asset) + poses de prise exportées en animations, mélangées par driver.gd
# ======================================================================================================================
POSES = (("open", None), ("g10", 0.010), ("g16", 0.0165), ("g25", 0.025), ("g32", 0.032))   # (nom, rayon de barre) ; open = repos
RIG_GROUPS = {"Hand": ("Wrist.L", "Index1.L", "Middle1.L", "Ring1.L", "Little1.L", "LowArm.L", "UpperArm.L", "Bone", "Bone.001"),
              "Thumb1": ("Thumb1.L",), "Thumb3": ("Thumb2.L", "Thumb3.L")}
for _fn in FINGERS:
    for _k in (2, 3, 4): RIG_GROUPS[f"{_fn}{_k}"] = (f"{_fn}{_k}.L",)


def _scale_about(c, d, s):
    """Affine (A, b) : homothétie de rapport s le long de d, autour de c."""
    d = np.asarray(d, dtype=float); d = d / np.linalg.norm(d); A = np.eye(3) + (s - 1.0) * np.outer(d, d); return A, c - A @ c


def _compose(A2, b2, A1, b1): return A2 @ A1, A2 @ b1 + b2


def _rest_rig(ref, to_c):
    """Repos de la main articulée : affines d'échelle par os de l'asset (doigts/pouce raccourcis) et articulations du
    squelette après raccourcissement, en repère canonique. joints[os du rig] = (tête, queue)."""
    bones = ref["bones"]; scales = {}; joints = {}
    for fn in FINGERS:
        h0 = [to_c(bones[f"{fn}{k}.L"][0]) for k in (2, 3, 4)]; tip0 = to_c(bones[f"{fn}4.L"][1])
        S, bS = _scale_about(h0[0], tip0 - h0[0], FINGER_SCALE)
        for k in (2, 3, 4): scales[f"{fn}{k}.L"] = (S, bS)
        h = [S @ p + bS for p in h0]; tip = S @ tip0 + bS
        joints[f"{fn}2"] = (h[0], h[1]); joints[f"{fn}3"] = (h[1], h[2]); joints[f"{fn}4"] = (h[2], tip)
    h1, t1 = (to_c(v) for v in bones["Thumb1.L"]); h2 = to_c(bones["Thumb2.L"][0]); h3, t3 = (to_c(v) for v in bones["Thumb3.L"])
    S1, bS1 = _scale_about(h1, t1 - h1, THUMB_META_SCALE); S3, bS3 = _scale_about(h3, t3 - h3, THUMB_DISTAL_SCALE)
    scales["Thumb1.L"] = (S1, bS1); scales["Thumb2.L"] = _compose(S1, bS1, S3, bS3); scales["Thumb3.L"] = scales["Thumb2.L"]
    joints["Thumb1"] = (h1, S1 @ t1 + bS1)
    A, b = scales["Thumb3.L"]; joints["Thumb3"] = (A @ h2 + b, A @ t3 + b)
    return scales, joints


def _pose_rotations(joints, bar_y, bar_z, bar_r):
    """Rotations rigides (R, t) par os du rig pour une prise sur une barre d'axe X de rayon bar_r, relatives au repos."""
    I = np.eye(3); T = {}
    for fn in FINGERS:
        h = [joints[f"{fn}{k}"][0] for k in (2, 3, 4)]; tip = joints[f"{fn}4"][1]
        Ls = [float(np.linalg.norm(h[1] - h[0])), float(np.linalg.norm(h[2] - h[1])), float(np.linalg.norm(tip - h[2]))]
        _, angs = wrap_chain(Vector(h[0]), Ls, bar_y, bar_z, bar_r + FINGER_HALF_T)
        R_prev, t_prev, a_prev = I, np.zeros(3), 0.0
        for k in range(3):
            Rl = _rx(angs[k] - a_prev); tl = h[k] - Rl @ h[k]
            R = R_prev @ Rl; t = R_prev @ tl + t_prev
            T[f"{fn}{k + 2}"] = (R, t); R_prev, t_prev, a_prev = R, t, angs[k]
    h1, t1 = joints["Thumb1"]; h2, t3 = joints["Thumb3"]
    target = np.array([h1[0] + THUMB_META_OFFSET[0], bar_y - bar_r + THUMB_META_OFFSET[1], bar_z + THUMB_META_OFFSET[2]])
    R1 = _rot_between(t1 - h1, target - h1); b1 = h1 - R1 @ h1
    c = R1 @ h2 + b1
    R3l = _rot_between(R1 @ (t3 - h2), np.array(THUMB_DISTAL_DIR))
    T["Thumb1"] = (R1, b1); T["Thumb3"] = _compose(R3l, c - R3l @ c, R1, b1)
    return T


def _mat4(R, t):
    m = Matrix.Identity(4)
    for i in range(3):
        for j in range(3): m[i][j] = float(R[i][j])
        m[i][3] = float(t[i])
    return m


def build_hand_rig(nm, side, mat, col):
    """Main `nm` ('L'/'R') articulée : vide racine DRV_Hand_<nm> (origine = centre de la jante) > armature <nm>_Rig
    (os Hand, Index2..4, ..., Thumb1, Thumb3) > maillage skinné DRV_Hand_<nm>_Mesh, + vide DRV_Wrist_<nm>.
    Une action par pose (POSES), poussée en piste NLA pour l'export glTF ; l'armature est laissée posée sur g16."""
    ref = load_reference(); to_c = _canon(ref); bones = ref["bones"]
    Vc = np.stack([to_c(p) for p in ref["V"]])
    mcp_y = float(np.mean([to_c(bones[f"{fn}2.L"][0])[1] for fn in FINGERS]))
    palm = (Vc[:, 1] > mcp_y - 0.05) & (Vc[:, 1] < mcp_y) & (np.abs(Vc[:, 0]) < 0.045)
    bar_y = mcp_y - BAR_BACK; palm_z = float(Vc[palm, 2].min())
    bar_z16 = palm_z - BAR_R - 0.002                                     # origine de la main : jante de 16,5 mm
    scales, joints = _rest_rig(ref, to_c)
    Vr = _skin(Vc, ref["W"], ref["names"], scales)                        # maillage de repos raccourci
    # repère de prise (miroir en X du canonique pour la droite, puis rotation propre)
    Sm = np.diag([-1.0, 1.0, 1.0]) if side > 0 else np.eye(3)        # main droite = miroir en X du canonique (gauche)
    cr, sr = math.cos(math.radians(ROLL)), math.sin(math.radians(ROLL))
    G = np.array([[0.0, -cr, sr], [1.0, 0.0, 0.0], [0.0, sr, cr]]) if side < 0 else np.array([[0.0, cr, -sr], [-1.0, 0.0, 0.0], [0.0, sr, cr]])
    # G : (x, y', z') -> gauche (-y', x, z') / droite (y', -x, z'), avec (y', z') = roulis de (y - bar_y, z - bar_z16)
    origin = np.array([0.0, bar_y, bar_z16])
    def grip(p): return G @ (Sm @ (np.asarray(p, dtype=float) - origin))
    def grip_rot(R): return G @ Sm @ R @ Sm @ G.T
    Vg = np.array([grip(p) for p in Vr])
    # --- maillage skinné ---
    parts = _face_parts(ref)
    faces = [f for f, p in zip(ref["F"], parts) if "hand" in p]; uvs = [u for u, p in zip(ref["UV"], parts) if "hand" in p]
    used = sorted({i for f in faces for i in f}); remap = {i: k for k, i in enumerate(used)}
    bm = _part_mesh(ref, "hand", Vg, UV_CAP_SKIN, mirror=(side > 0))
    root = L.empty(f"DRV_Hand_{nm}", (0, 0, 0), col, size=0.05)
    arm_data = bpy.data.armatures.new(f"{nm}_Rig"); arm_ob = bpy.data.objects.new(f"{nm}_Rig", arm_data); L.link_obj(arm_ob, col)
    L.place(arm_ob, parent=root)
    ob = L.bm_to_obj(bm, f"DRV_Hand_{nm}_Mesh", mat, col); L.place(ob, parent=arm_ob)
    # groupes de sommets : poids de l'asset regroupés par os du rig (ordre des sommets = `used`, comme dans _part_mesh)
    names = ref["names"]; W = ref["W"]
    for gname, srcs in RIG_GROUPS.items():
        idx = [names.index(s) for s in srcs if s in names]
        if not idx: continue
        vg = ob.vertex_groups.new(name=gname)
        for i in used:
            w = float(W[i, idx].sum())
            if w > 1e-4: vg.add([remap[i]], w, 'REPLACE')
    # --- os (repère de prise) ---
    bpy.context.view_layer.objects.active = arm_ob; arm_ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    hand = eb.new("Hand"); hand.head = (0.0, 0.0, 0.0); hand.tail = tuple(grip(origin + np.array([0.0, 0.03, 0.0])))
    parent_of = {"Thumb1": "Hand", "Thumb3": "Thumb1"}
    for fn in FINGERS: parent_of[f"{fn}2"] = "Hand"; parent_of[f"{fn}3"] = f"{fn}2"; parent_of[f"{fn}4"] = f"{fn}3"
    order = [f"{fn}{k}" for fn in FINGERS for k in (2, 3, 4)] + ["Thumb1", "Thumb3"]
    for bn in order:
        b = eb.new(bn); h, t = joints[bn]; b.head = tuple(grip(h)); b.tail = tuple(grip(t)); b.parent = eb[parent_of[bn]]
    bpy.ops.object.mode_set(mode='OBJECT')
    mod = ob.modifiers.new("Armature", 'ARMATURE'); mod.object = arm_ob
    rest = {b.name: b.matrix_local.copy() for b in arm_data.bones}
    # --- poses : une action par pose, en piste NLA ---
    adt = arm_ob.animation_data_create()
    for pb in arm_ob.pose.bones: pb.rotation_mode = 'QUATERNION'
    keep = None
    for pname, r in POSES:
        rots = _pose_rotations(joints, bar_y, palm_z - r - 0.002, r) if r is not None else {}
        act = bpy.data.actions.new(f"{nm}_{pname}"); adt.action = act
        if hasattr(act, "slots"):                                        # Blender ≥ 4.4 : sans slot assigné, keyframe_insert n'écrit rien
            slot = act.slots.new(id_type='OBJECT', name=arm_ob.name); adt.action_slot = slot
        world = {"Hand": (np.eye(3), np.zeros(3))}
        for bn in order:
            R, t = rots.get(bn, (np.eye(3), np.zeros(3))); world[bn] = (grip_rot(R), G @ Sm @ (R @ origin + t - origin))   # affine canonique → repère de prise
        quats = {}
        for pb in arm_ob.pose.bones:
            bn = pb.name
            if bn == "Hand": q = Quaternion((1, 0, 0, 0))
            else:
                Rk, tk = world[bn]; Rp, tp = world[parent_of[bn]]
                Tk = _mat4(Rk, tk); Tp = _mat4(Rp, tp)
                Lk = rest[bn].inverted() @ (Tp.inverted() @ Tk) @ rest[bn]
                q = Lk.to_quaternion()
            pb.rotation_quaternion = q; quats[bn] = q
            pb.keyframe_insert("rotation_quaternion", frame=1)
        adt.action = None
        track = adt.nla_tracks.new(); track.name = act.name; strip = track.strips.new(act.name, 1, act)
        if hasattr(strip, "action_slot") and len(act.slots): strip.action_slot = act.slots[0]
        if pname == "g16": keep = quats
    for pb in arm_ob.pose.bones: pb.rotation_quaternion = keep[pb.name]      # la scène montre la prise jante
    L.empty(f"DRV_Wrist_{nm}", tuple(grip(to_c(bones["Wrist.L"][1]))), col, parent=root, size=0.02)
    return root
