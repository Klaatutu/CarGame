# -*- coding: utf-8 -*-
"""
webley_lib — helpers de modélisation pour build_webley.py (compléments de civic_lib).

Toutes les cotes sont en MILLIMÈTRES ; les sommets sont créés en mètres (× M). Repère : Y = avant (canon), Z = haut,
X = droite du tireur.
"""
import bpy, bmesh, math
from mathutils import Vector, Matrix
from civic_lib import bm_to_obj, shade, add_bevel, add_subsurf, smooth_all, place

M = 0.001


# ---------------------------------------------------------------------------
# Contours 2D
# ---------------------------------------------------------------------------
def smooth_poly(pts, iters=2):
    """Arrondit un contour fermé (Chaikin). Un point (y, z, True) reste un coin vif."""
    P = [(Vector((p[0], p[1])), len(p) > 2 and bool(p[2])) for p in pts]
    for _ in range(iters):
        out = []
        n = len(P)
        for i in range(n):
            (p, kp), (q, kq) = P[i], P[(i + 1) % n]
            a = (p, True) if kp else (p * 0.75 + q * 0.25, False)
            b = (q, True) if kq else (p * 0.25 + q * 0.75, False)
            if not out or (out[-1][0] - a[0]).length > 1e-9: out.append(a)
            if (out[-1][0] - b[0]).length > 1e-9: out.append(b)
        if len(out) > 1 and (out[0][0] - out[-1][0]).length < 1e-9: out.pop()
        P = out
    return [(p.x, p.y) for p, _ in P]


def rounded_rect(w, h, r, n=3):
    """Rectangle w × h centré, coins de rayon r (liste de (a, b))."""
    hw, hh = w / 2 - r, h / 2 - r
    pts = []
    for cx, cy, a0 in ((hw, hh, 0.0), (-hw, hh, 90.0), (-hw, -hh, 180.0), (hw, -hh, 270.0)):
        for k in range(n + 1):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# ---------------------------------------------------------------------------
# Solides
# ---------------------------------------------------------------------------
def extrude_yz(name, pts, x0, x1, mat, col, origin=(0, 0, 0), bevel=1.5, segs=3, iters=2, angle=40, parent=None):
    """Profil (y, z) en mm extrudé de x0 à x1. L'origine de l'objet est placée en `origin` (mm) — utile pour les pivots."""
    pts = smooth_poly(pts, iters) if iters else [(p[0], p[1]) for p in pts]
    o = Vector(origin)
    bm = bmesh.new()
    lo = [bm.verts.new(((x0 - o.x) * M, (y - o.y) * M, (z - o.z) * M)) for y, z in pts]
    hi = [bm.verts.new(((x1 - o.x) * M, (y - o.y) * M, (z - o.z) * M)) for y, z in pts]
    bm.faces.new(lo); bm.faces.new(list(reversed(hi)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bm_to_obj(bm, name, mat, col)
    ob.location = o * M
    if parent is not None: ob.parent = parent; ob.matrix_parent_inverse = Matrix.Identity(4)
    if bevel: add_bevel(ob, bevel * M, segs, angle=30)
    shade(ob, angle)
    return ob


def revolve_y(name, profile, mats, col, steps=48, loc=(0, 0, 0), rfn=None, mat_fn=None, angle=50, parent=None):
    """Révolution du profil [(r, t)] (mm, t le long de l'axe local Y) autour de Y.
    rfn(theta, r, t) → rayon modifié (cannelures) ; mat_fn(r, t) → index de matériau de la face."""
    bm = bmesh.new(); rings = []
    for r, t in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, t * M, 0.0))])
        else:
            ring = []
            for i in range(steps):
                th = 2 * math.pi * i / steps
                rr = rfn(th, r, t) if rfn else r
                ring.append(bm.verts.new((rr * math.cos(th) * M, t * M, rr * math.sin(th) * M)))
            rings.append(ring)
    for k in range(len(profile) - 1):
        a, b = rings[k], rings[k + 1]
        (ra, ta), (rb, tb) = profile[k], profile[k + 1]
        if len(a) == 1 and len(b) == 1: continue
        mi = mat_fn((ra + rb) / 2, (ta + tb) / 2) if mat_fn else 0
        for i in range(steps):
            j = (i + 1) % steps
            if len(a) == 1: f = bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1: f = bm.faces.new((a[i], a[j], b[0]))
            else: f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mi
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bm_to_obj(bm, name, mats, col)
    ob.location = Vector(loc) * M
    if parent is not None: ob.parent = parent; ob.matrix_parent_inverse = Matrix.Identity(4)
    shade(ob, angle)
    return ob


def sweep(name, path, section, mat, col, subsurf=1, caps=True, parent=None):
    """Balaye une section 2D [(a, b)] (mm) le long d'une polyligne 3D (mm), repère transporté.
    a = le long de N (≈ X pour un chemin dans le plan YZ), b = le long de B = T × N."""
    P = [Vector(p) * M for p in path]
    T = []
    for i in range(len(P)):
        t = (P[1] - P[0]) if i == 0 else ((P[-1] - P[-2]) if i == len(P) - 1 else (P[i + 1] - P[i - 1]))
        T.append(t.normalized())
    up = Vector((0, 0, 1)) if abs(T[0].dot(Vector((0, 0, 1)))) < 0.9 else Vector((1, 0, 0))
    N = (T[0].cross(up)).normalized()
    bm = bmesh.new(); rings = []
    for i in range(len(P)):
        if i > 0:
            N = N - T[i] * N.dot(T[i]); N.normalize()
        B = T[i].cross(N).normalized()
        rings.append([bm.verts.new(P[i] + N * (a * M) + B * (b * M)) for a, b in section])
    n = len(section)
    for s in range(len(rings) - 1):
        for k in range(n):
            j = (k + 1) % n
            bm.faces.new((rings[s][k], rings[s][j], rings[s + 1][j], rings[s + 1][k]))
    if caps:
        bm.faces.new(list(reversed(rings[0]))); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bm_to_obj(bm, name, mat, col)
    if parent is not None: ob.parent = parent; ob.matrix_parent_inverse = Matrix.Identity(4)
    if subsurf: add_subsurf(ob, subsurf)
    smooth_all(ob)
    return ob


def cyl_y(name, r, y0, y1, loc, mat, col, steps=24, parent=None, r2=None):
    """Cylindre plein d'axe Y, de y0 à y1 (mm, relatifs à loc en mm)."""
    prof = [(0, y0), (r, y0), (r if r2 is None else r2, y1), (0, y1)]
    return revolve_y(name, prof, mat, col, steps=steps, loc=loc, angle=60, parent=parent)


def attach(ob, parent):
    """Parente en conservant la transformation monde (l'objet ne bouge pas)."""
    bpy.context.view_layer.update()
    mw = ob.matrix_world.copy()
    ob.parent = parent
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_world = mw
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)
