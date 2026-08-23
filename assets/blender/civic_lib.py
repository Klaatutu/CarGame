# -*- coding: utf-8 -*-
"""
civic_lib — helpers de construction procédurale partagés par build_civic_interior / driver / exterior.

Principes : géométrie en coordonnées MONDE (pas de repère local par pièce, hors conducteur),
cages de subdivision pour les formes organiques, booléens pour les découpes, matériaux par nom.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix, Euler

SUBD = 2

# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------
def get_col(name, parent=None):
    col = bpy.data.collections.get(name)
    if not col:
        col = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(col)
    return col

def clear_collection(name):
    """Supprime la collection, ses enfants et tous leurs objets, puis purge les datablocks orphelins."""
    col = bpy.data.collections.get(name)
    if col:
        for c in list(col.children_recursive) + [col]:
            for ob in list(c.objects): bpy.data.objects.remove(ob, do_unlink=True)
            bpy.data.collections.remove(c)
    purge_orphans()

def purge_orphans():
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
        for d in list(coll):
            if d.users == 0: coll.remove(d)

def link_obj(ob, col):
    for c in ob.users_collection: c.objects.unlink(ob)
    col.objects.link(ob)

# ---------------------------------------------------------------------------
# Maillage de base
# ---------------------------------------------------------------------------
def bm_to_obj(bm, name, mats, col):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free(); me.update()
    ob = bpy.data.objects.new(name, me); link_obj(ob, col)
    for m in (mats if isinstance(mats, (list, tuple)) else [mats]):
        if m: me.materials.append(m)
    return ob

def place(ob, loc=(0,0,0), rot=(0,0,0), parent=None):
    if parent is not None:
        ob.parent = parent; ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.location = Vector(loc); ob.rotation_euler = Euler([math.radians(a) for a in rot], 'XYZ')
    return ob

def smooth_all(ob):
    me = ob.data; me.polygons.foreach_set("use_smooth", [True]*len(me.polygons)); me.update()

def shade(ob, angle=40):
    """Lissage avec arêtes vives au-delà de `angle` degrés."""
    me = ob.data; bm = bmesh.new(); bm.from_mesh(me)
    for f in bm.faces: f.smooth = True
    lim = math.radians(angle)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a = e.calc_face_angle(None)
            if a is not None and a > lim: e.smooth = False
    bm.to_mesh(me); bm.free(); me.update()

def add_bevel(ob, width, segs=3, angle=30):
    m = ob.modifiers.new("Bevel", 'BEVEL'); m.width = width; m.segments = segs
    m.limit_method = 'ANGLE'; m.angle_limit = math.radians(angle); m.harden_normals = True; return m

def add_subsurf(ob, levels=SUBD):
    m = ob.modifiers.new("Subdivision", 'SUBSURF'); m.levels = levels; m.render_levels = levels; return m

def add_solidify(ob, thickness, inner_material_offset=1):
    m = ob.modifiers.new("Sheet", 'SOLIDIFY'); m.thickness = thickness; m.offset = -1.0; m.use_even_offset = True
    m.material_offset = inner_material_offset; m.material_offset_rim = inner_material_offset; return m

def add_boolean_collection(ob, col, name="Cutouts"):
    m = ob.modifiers.new(name, 'BOOLEAN'); m.operation = 'DIFFERENCE'; m.operand_type = 'COLLECTION'; m.collection = col
    if hasattr(m, 'solver'): m.solver = 'EXACT'
    return m

def crease_layer(bm):
    cl = bm.edges.layers.float.get("crease_edge")
    return cl if cl is not None else bm.edges.layers.float.new("crease_edge")

# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------
def box(name, size, loc, mat, col, rot=(0,0,0), bevel=0.0, segs=3, smooth=True, parent=None):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = bm_to_obj(bm, name, mat, col); place(ob, loc, rot, parent)
    if bevel > 0: add_bevel(ob, bevel, segs)
    if smooth: shade(ob)
    return ob

def cyl(name, r, depth, loc, mat, col, rot=(0,0,0), r2=None, segments=32, bevel=0.0, segs=2, parent=None, smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r, radius2=(r if r2 is None else r2), depth=depth)
    ob = bm_to_obj(bm, name, mat, col); place(ob, loc, rot, parent)
    if bevel > 0: add_bevel(ob, bevel, segs)
    if smooth: shade(ob)
    return ob

def cyl_between(name, p1, p2, r, mat, col, r2=None, segments=16, parent=None):
    p1, p2 = Vector(p1), Vector(p2); d = p2 - p1
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r, radius2=(r if r2 is None else r2), depth=d.length)
    ob = bm_to_obj(bm, name, mat, col)
    if parent is not None: ob.parent = parent; ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.location = (p1 + p2)/2; ob.rotation_euler = d.to_track_quat('Z', 'Y').to_euler(); shade(ob); return ob

def torus(name, R, r, loc, mat, col, rot=(0,0,0), maj=48, minr=16, parent=None):
    bm = bmesh.new(); rings = []
    for i in range(maj):
        a = 2*math.pi*i/maj
        rings.append([bm.verts.new(((R + r*math.cos(b))*math.cos(a), (R + r*math.cos(b))*math.sin(a), r*math.sin(b))) for b in [2*math.pi*j/minr for j in range(minr)]])
    for i in range(maj):
        for j in range(minr):
            bm.faces.new((rings[i][j], rings[(i+1)%maj][j], rings[(i+1)%maj][(j+1)%minr], rings[i][(j+1)%minr]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bm_to_obj(bm, name, mat, col); place(ob, loc, rot, parent); smooth_all(ob); return ob

def ellipsoid(name, radii, loc, mat, col, parent=None, u=24, v=16):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
    ob = bm_to_obj(bm, name, mat, col); place(ob, loc, (0,0,0), parent); smooth_all(ob); return ob

def polygon(name, pts, mat, col, parent=None):
    bm = bmesh.new(); vs = [bm.verts.new(p) for p in pts]; bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bm_to_obj(bm, name, mat, col)
    if parent is not None: ob.parent = parent; ob.matrix_parent_inverse = Matrix.Identity(4)
    return ob

def empty(name, loc, col, rot=(0,0,0), parent=None, size=0.1):
    ob = bpy.data.objects.new(name, None); ob.empty_display_size = size; link_obj(ob, col); return place(ob, loc, rot, parent)

def set_world_axes(ob, x, y, z, loc):
    m = Matrix.Identity(4)
    for i in range(3): m[i][0] = x[i]; m[i][1] = y[i]; m[i][2] = z[i]; m[i][3] = loc[i]
    ob.matrix_world = m

def text_obj(name, body, size, loc, mat, col, parent=None, rot=(90, 0, 0)):
    cu = bpy.data.curves.new(name, 'FONT'); cu.body = body; cu.size = size; cu.align_x = 'CENTER'; cu.align_y = 'CENTER'
    ob = bpy.data.objects.new(name, cu); link_obj(ob, col); cu.materials.append(mat); return place(ob, loc, rot, parent)

def loft(name, rings, mats, col, closed=True, caps=True, subsurf=SUBD, creases=None, idx_fn=None, parent=None, loc=(0,0,0), rot=(0,0,0), smooth=True):
    """Relie des anneaux (même nombre de points) par des quads.
    closed : bool ou liste par anneau (quad de bouclage entre deux anneaux fermés consécutifs).
    creases : [(index_de_point, valeur)] sur les arêtes longitudinales."""
    n = len(rings[0]); m = len(rings)
    cl = [closed]*m if isinstance(closed, bool) else list(closed)
    bm = bmesh.new(); R = [[bm.verts.new(p) for p in ring] for ring in rings]
    for s in range(m-1):
        for k in range(n-1): bm.faces.new((R[s][k], R[s][k+1], R[s+1][k+1], R[s+1][k]))
        if cl[s] and cl[s+1]: bm.faces.new((R[s][n-1], R[s][0], R[s+1][0], R[s+1][n-1]))
    if caps:
        if cl[0]: bm.faces.new(list(reversed(R[0])))
        if cl[-1]: bm.faces.new(R[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if creases:
        lay = crease_layer(bm); idx = {}
        for s in range(m):
            for k, v in enumerate(R[s]):
                if v.is_valid: idx[v] = (s, k)
        for pt_k, val in creases:
            for e in bm.edges:
                a, b = idx.get(e.verts[0]), idx.get(e.verts[1])
                if a and b and a[0] != b[0] and a[1] == b[1] == pt_k: e[lay] = val
    ob = bm_to_obj(bm, name, mats, col); place(ob, loc, rot, parent)
    if idx_fn:
        for p in ob.data.polygons: p.material_index = idx_fn(p.center)
    if subsurf: add_subsurf(ob, subsurf)
    if smooth: smooth_all(ob)
    return ob

def grid_box(name, us, vs, ftop, fbot, mat, col, to_world=None, subsurf=SUBD, crease_bottom=0.0, side_rows=None, parent=None):
    """Cage fermée 100 % quads : dessus = grille (u, v) de hauteur ftop(u, v), dessous fbot(u, v), flancs.
    to_world(u, v, w) -> (x, y, z) permet d'orienter la cage (défaut : x=u, y=v, z=w)."""
    tw = to_world or (lambda u, v, w: (u, v, w))
    ft = ftop if callable(ftop) else (lambda u, v: ftop); fb = fbot if callable(fbot) else (lambda u, v: fbot)
    bm = bmesh.new(); nu, nv = len(us), len(vs)
    T = [[bm.verts.new(tw(us[i], vs[j], ft(us[i], vs[j]))) for j in range(nv)] for i in range(nu)]
    B = [[bm.verts.new(tw(us[i], vs[j], fb(us[i], vs[j]))) for j in range(nv)] for i in range(nu)]
    for i in range(nu-1):
        for j in range(nv-1):
            bm.faces.new((T[i][j], T[i+1][j], T[i+1][j+1], T[i][j+1])); bm.faces.new((B[i][j], B[i][j+1], B[i+1][j+1], B[i+1][j]))
    ring = [(i, 0) for i in range(nu-1)] + [(nu-1, j) for j in range(nv-1)] + [(i, nv-1) for i in range(nu-1, 0, -1)] + [(0, j) for j in range(nv-1, 0, -1)]
    n = len(ring); levels = [[B[i][j] for (i, j) in ring]]
    for fr in (side_rows or []):
        levels.append([bm.verts.new(tuple(B[i][j].co.lerp(T[i][j].co, fr))) for (i, j) in ring])
    levels.append([T[i][j] for (i, j) in ring])
    for L in range(len(levels)-1):
        lo, hi = levels[L], levels[L+1]
        for k in range(n): bm.faces.new((lo[k], lo[(k+1)%n], hi[(k+1)%n], hi[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if crease_bottom:
        lay = crease_layer(bm); bset = {v for row in B for v in row}
        for e in bm.edges:
            if e.verts[0] in bset and e.verts[1] in bset: e[lay] = crease_bottom
    ob = bm_to_obj(bm, name, mat, col); place(ob, (0,0,0), (0,0,0), parent)
    if subsurf: add_subsurf(ob, subsurf)
    smooth_all(ob); return ob

def lathe(name, profile, mat, col, loc=(0,0,0), rot=(0,0,0), parent=None, steps=32, subsurf=0):
    """Révolution d'un profil [(r, z), ...] autour de Z."""
    bm = bmesh.new(); vs = [bm.verts.new((r, 0.0, z)) for r, z in profile]
    es = [bm.edges.new((vs[i], vs[i+1])) for i in range(len(vs)-1)]
    bmesh.ops.spin(bm, geom=vs + es, cent=(0,0,0), axis=(0,0,1), dvec=(0,0,0), angle=2*math.pi, steps=steps, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5); bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = bm_to_obj(bm, name, mat, col); place(ob, loc, rot, parent)
    if subsurf: add_subsurf(ob, subsurf)
    shade(ob, angle=180 if subsurf else 60); return ob

def tube_along(name, pts, r, mat, col, n=8, subsurf=1, parent=None, caps=True, cap_scale=None):
    """Tube à section circulaire le long d'une polyligne (repère transporté). r : rayon ou liste par point."""
    P = [Vector(p) for p in pts]; T = []
    for i in range(len(P)):
        t = (P[1]-P[0]) if i == 0 else ((P[-1]-P[-2]) if i == len(P)-1 else (P[i+1]-P[i-1])); T.append(t.normalized())
    up = Vector((0,0,1)) if abs(T[0].dot(Vector((0,0,1)))) < 0.9 else Vector((1,0,0))
    N = (T[0].cross(up)).normalized(); B = T[0].cross(N).normalized(); rings = []
    radii = list(r) if isinstance(r, (list, tuple)) else [r]*len(P)
    if cap_scale:   # bouts arrondis
        rings.append([tuple(P[0] - T[0]*radii[0]*0.7 + (N*math.cos(a) + B*math.sin(a))*radii[0]*cap_scale) for a in [2*math.pi*k/n for k in range(n)]])
    for i in range(len(P)):
        if i > 0: N = N - T[i]*N.dot(T[i]); N.normalize(); B = T[i].cross(N).normalized()
        rings.append([tuple(P[i] + (N*math.cos(a) + B*math.sin(a))*radii[i]) for a in [2*math.pi*k/n for k in range(n)]])
    if cap_scale:
        rings.append([tuple(P[-1] + T[-1]*radii[-1]*0.7 + (N*math.cos(a) + B*math.sin(a))*radii[-1]*cap_scale) for a in [2*math.pi*k/n for k in range(n)]])
    return loft(name, rings, mat, col, closed=True, caps=caps, subsurf=subsurf, parent=parent)

def band(name, outer, inner, mat, col):
    """Bande plate entre deux contours 3D de même taille (joint de vitre, cadre)."""
    return loft(name, [list(outer), list(inner)], mat, col, closed=True, caps=False, subsurf=0, smooth=False)

# ---------------------------------------------------------------------------
# Maths
# ---------------------------------------------------------------------------
def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0)/(e1 - e0))); return t*t*(3 - 2*t)

def bump(x, c, w):
    d = abs(x - c); return 0.0 if d >= w else 0.5*(1.0 + math.cos(math.pi*d/w))

def offset_outline(pts, d):
    """Décale un contour 2D [(a, b)] vers l'extérieur de d (d < 0 : vers l'intérieur), via le centroïde."""
    ca = sum(p[0] for p in pts)/len(pts); cb = sum(p[1] for p in pts)/len(pts); out = []
    for (a, b) in pts:
        v = Vector((a - ca, b - cb)); L = v.length
        out.append((ca + v.x*(L + d)/L, cb + v.y*(L + d)/L))
    return out

def offset_outline3d(pts, d, n=None, lift=0.0):
    c = sum((Vector(p) for p in pts), Vector())/len(pts); nn = Vector(n).normalized() if n else Vector((0,0,0)); out = []
    for p in pts:
        v = Vector(p) - c; L = v.length; out.append(tuple(c + v*(L + d)/L + nn*lift))
    return out

def aim(ob, target):
    ob.rotation_euler = (Vector(target) - ob.location).to_track_quat('-Z', 'Y').to_euler()

# ---------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------
def node_of(nt, idname):
    return next(n for n in nt.nodes if n.bl_idname == idname)

def mat(name, color, rough=0.5, metallic=0.0, grain=0.0, grain_scale=400.0, sheen=0.0, coat=0.0, alpha=1.0,
        emission=None, emit=0.0, specular=None, sss=0.0):
    """Matériau Principled (réutilisé s'il existe). grain : bump procédural (non exporté en glTF)."""
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree
    b = node_of(nt, 'ShaderNodeBsdfPrincipled')
    b.inputs['Base Color'].default_value = (*color, 1.0); b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metallic; b.inputs['Sheen Weight'].default_value = sheen
    b.inputs['Sheen Roughness'].default_value = 0.6; b.inputs['Coat Weight'].default_value = coat; b.inputs['Alpha'].default_value = alpha
    if specular is not None: b.inputs['Specular IOR Level'].default_value = specular
    if emission:
        b.inputs['Emission Color'].default_value = (*emission, 1.0); b.inputs['Emission Strength'].default_value = emit
    if sss > 0:
        b.inputs['Subsurface Weight'].default_value = sss; b.inputs['Subsurface Radius'].default_value = (1.0, 0.35, 0.2)
        b.inputs['Subsurface Scale'].default_value = 0.02
    if grain > 0:
        tc = nt.nodes.new('ShaderNodeTexCoord'); tc.location = (-900, 0)
        tex = nt.nodes.new('ShaderNodeTexNoise'); tex.location = (-650, 0)
        tex.inputs['Scale'].default_value = grain_scale; tex.inputs['Detail'].default_value = 8.0; tex.inputs['Roughness'].default_value = 0.7
        bp = nt.nodes.new('ShaderNodeBump'); bp.location = (-350, -200)
        bp.inputs['Strength'].default_value = grain; bp.inputs['Distance'].default_value = 0.002
        nt.links.new(tc.outputs['Object'], tex.inputs['Vector']); nt.links.new(tex.outputs[0], bp.inputs['Height']); nt.links.new(bp.outputs['Normal'], b.inputs['Normal'])
    if alpha < 1.0:
        if hasattr(m, 'surface_render_method'): m.surface_render_method = 'BLENDED'
        if hasattr(m, 'use_transparent_shadow'): m.use_transparent_shadow = True
    m.diffuse_color = (*color, alpha)
    return m

def tex_mat(name, image_path, rough=0.5, interp='Closest', specular=None):
    """Matériau Principled dont la couleur de base vient d'une image (réutilisé s'il existe). interp='Closest' = look PS1."""
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree
    b = node_of(nt, 'ShaderNodeBsdfPrincipled'); b.inputs['Roughness'].default_value = rough
    if specular is not None: b.inputs['Specular IOR Level'].default_value = specular
    img = bpy.data.images.load(image_path, check_existing=True)
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = img; t.interpolation = interp; t.location = (-400, 0)
    nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
    return m

# ---------------------------------------------------------------------------
# Scène : caméras, rendu, sauvegarde, export, vérification
# ---------------------------------------------------------------------------
def camera(name, loc, target, lens, col, clip_start=0.02):
    cam = bpy.data.objects.get(name)
    if not cam: cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    link_obj(cam, col); cam.data.lens = lens; cam.data.sensor_width = 36; cam.data.clip_start = clip_start; cam.data.display_size = 0.15
    cam.location = loc; aim(cam, target); return cam

def render_views(views, out_dir, pct=100):
    """views : [(camera_name, filename, [préfixes d'objets à masquer])]. Rend en PNG et restaure l'état."""
    scene = bpy.context.scene; os.makedirs(out_dir, exist_ok=True)
    scene.render.image_settings.file_format = 'PNG'; old_pct = scene.render.resolution_percentage; scene.render.resolution_percentage = pct
    old_cam = scene.camera; prev = {o.name: o.hide_render for o in bpy.data.objects}; paths = []
    try:
        for camname, fname, hide_prefixes in views:
            for o in bpy.data.objects:
                if hide_prefixes and o.name.startswith(tuple(hide_prefixes)): o.hide_render = True
            scene.camera = bpy.data.objects[camname]; scene.render.filepath = os.path.join(out_dir, fname)
            bpy.ops.render.render(write_still=True); paths.append(scene.render.filepath)
            for o in bpy.data.objects:
                if o.name in prev: o.hide_render = prev[o.name]
    finally:
        scene.camera = old_cam; scene.render.resolution_percentage = old_pct
    return paths

def save_blend(path):
    bpy.ops.wm.save_as_mainfile(filepath=path)

def export_glb(colname, path, skip_prefixes=("CUT_", "ENV_")):
    """Exporte tous les maillages de la collection (et sous-collections) en .glb, modificateurs appliqués."""
    import io, contextlib
    c = bpy.data.collections[colname]
    objs = [o for cc in ([c] + list(c.children_recursive)) for o in cc.objects if o.type not in ('CAMERA', 'LIGHT') and not o.name.startswith(tuple(skip_prefixes))]
    for o in bpy.data.objects: o.select_set(False)
    for o in objs: o.hide_set(False); o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                                  export_materials='EXPORT', export_image_format='AUTO', export_extras=False,
                                  export_animation_mode='NLA_TRACKS')   # une animation par piste NLA (poses des mains) ; en mode ACTIONS, Blender 5 exporte le repos
    for o in bpy.data.objects: o.select_set(False)
    return len(objs), round(os.path.getsize(path)/1e6, 2)

def poke_check(body_name, collections, min_report=0.012, max_samples=400):
    """Liste les objets dont des sommets sont au-delà de la tôle `body_name` (rayon sommet -> axe de l'habitacle)."""
    bpy.context.view_layer.update(); dg = bpy.context.evaluated_depsgraph_get()
    body_ev = bpy.data.objects[body_name].evaluated_get(dg); offenders = {}
    for cname in collections:
        for ob in bpy.data.collections[cname].all_objects:
            if ob.type != 'MESH' or ob.hide_render: continue
            mw = ob.matrix_world; worst = 0.0; cnt = 0; verts = ob.data.vertices; step = max(1, len(verts)//max_samples)
            for i in range(0, len(verts), step):
                pw = mw @ verts[i].co
                if abs(pw.y) > 2.0 or pw.z < 0.25: continue
                t = Vector((0.0, max(-1.6, min(1.0, pw.y)), 0.75)); d = t - pw; L = d.length
                if L < 0.05: continue
                hit, loc, nrm, idx = body_ev.ray_cast(pw, d/L, distance=L)
                if hit: cnt += 1; worst = max(worst, (loc - pw).length)
            if cnt and worst > min_report: offenders[ob.name] = (cnt, round(worst, 3))
    return dict(sorted(offenders.items(), key=lambda kv: -kv[1][1]))

def hide_cutters(colname="Exterior_Cutters"):
    col = bpy.data.collections.get(colname)
    if col:
        for o in col.objects: o.hide_set(True); o.hide_render = True
