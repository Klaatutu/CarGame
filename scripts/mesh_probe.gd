extends RefCounted
##
## Le maillage de l'habitacle, range pour etre interroge vite.
##
## Mutualise par les sondes (probe_collisions.gd) ET par le jeu
## (scripts/cabin_shape.gd) : la question "ou est la tole ?" ne doit avoir
## qu'une seule reponse, sinon l'outil qui mesure et le jeu qui simule finissent
## par ne plus parler du meme habitacle — ce qui est exactement le defaut qu'on
## corrige.
##
## Deux services :
##   - `top_at(x, z)` — la surface la plus haute a l'aplomb d'un point, c'est-a-
##     dire ce sur quoi un objet se poserait. C'est l'algorithme de
##     probe_surfaces.gd, deplace ici pour ne plus vivre en double.
##   - `hits_box(centre, half)` — vrai si une boite mord la tole. C'est de quoi
##     dire "cet objet est ENFONCE DANS le decor", que rien ne mesurait.
##

## Faces plus inclinees que ca : ce n'est pas une surface, c'est un flanc.
const UP_MIN := 0.55
## Cote des cases de tri. Sans ce rangement, chaque question repasserait sur les
## dizaines de milliers de triangles du modele.
const CELL := 0.10

## Pieces qu'on ne veut jamais voir : le vitrage (on regarde au travers), les
## ceintures (diagonales, leur boite englobante ne veut rien dire) et les
## pieces qui BOUGENT — une boite figee sur un volant qui tourne est un mensonge.
const SKIP := ["Glass", "Windshield", "Belt", "Seatbelt", "Needle",
	"Visor", "Mirror", "Wheel", "STR_Rim", "STR_Spoke", "STR_Pad", "STR_Horn",
	"STR_H_", "STR_Badge", "ShiftLever", "ShiftKnob", "ShiftBadge", "ShiftBoot",
	"BrakeLever", "BrakeGrip", "BrakeButton", "CrankArm", "CrankKnob",
	"STR_Key", "Pedal"]

var tris: PackedVector3Array = PackedVector3Array()   # 3 sommets par triangle
var owner_of: PackedInt32Array = PackedInt32Array()   # index de piece par triangle
var names: PackedStringArray = PackedStringArray()
## Boite englobante de chaque piece, en espace voiture.
var boxes: Array[AABB] = []

var _col := {}                                        # Vector2i -> triangles (colonne x/z)
var _vox := {}                                        # Vector3i -> triangles (volume)


## Charge un .glb et range son maillage. `extra_skip` s'ajoute a SKIP.
func load_glb(path: String, extra_skip: PackedStringArray = PackedStringArray()) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("%s introuvable" % path)
		return
	var root := scene.instantiate()
	_gather(root, Transform3D(), extra_skip)
	root.free()
	_sort()


func _gather(n: Node, tf: Transform3D, extra: PackedStringArray) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var world := tf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null \
				and not _skipped(c.name, extra):
			_add(c as MeshInstance3D, world)
		_gather(c, world, extra)


func _skipped(name: String, extra: PackedStringArray) -> bool:
	for s in SKIP:
		if name.findn(s) >= 0:
			return true
	for s in extra:
		if name.findn(s) >= 0:
			return true
	return false


func _add(mi: MeshInstance3D, tf: Transform3D) -> void:
	var id := names.size()
	var kept := false
	var box := AABB()
	var mesh := mi.mesh
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var count := idx.size() if idx.size() > 0 else verts.size()
		var i := 0
		while i + 2 < count:
			var a := tf * verts[idx[i] if idx.size() > 0 else i]
			var b := tf * verts[idx[i + 1] if idx.size() > 0 else i + 1]
			var c := tf * verts[idx[i + 2] if idx.size() > 0 else i + 2]
			i += 3
			if (b - a).cross(c - a).length_squared() < 1e-14:
				continue
			if not kept:
				box = AABB(a, Vector3.ZERO)
				kept = true
			box = box.expand(a).expand(b).expand(c)
			tris.append_array([a, b, c])
			owner_of.append(id)
	if kept:
		names.append(mi.name)
		boxes.append(box)


func _sort() -> void:
	for t in tris.size() / 3:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		for i in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
			for j in range(int(floor(lo.z / CELL)), int(floor(hi.z / CELL)) + 1):
				var k := Vector2i(i, j)
				if not _col.has(k):
					_col[k] = PackedInt32Array()
				_col[k].append(t)
				for h in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
					var v := Vector3i(i, h, j)
					if not _vox.has(v):
						_vox[v] = PackedInt32Array()
					_vox[v].append(t)


# --------------------------------------------------------------------------

## Surface TOURNEE VERS LE HAUT la plus haute a l'aplomb de (px, pz), dans
## [ylo, yhi]. C'est exactement ce sur quoi un objet se poserait.
## Renvoie [hauteur, index de piece] ; hauteur -99 si rien.
func top_at(px: float, pz: float, ylo: float, yhi: float) -> Array:
	var k := Vector2i(int(floor(px / CELL)), int(floor(pz / CELL)))
	if not _col.has(k):
		return [-99.0, -1]
	var best := -99.0
	var who := -1
	for t in _col[k]:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		# Valeur ABSOLUE : le loft de la planche de bord sort avec des normales
		# retournees, et filtrer sur le signe faisait disparaitre tout son dessus.
		# Ce qui compte ici, c'est qu'une face soit PLATE.
		var nrm := (b - a).cross(c - a)
		if absf(nrm.normalized().y) < UP_MIN:
			continue
		var y := _height_at(a, b, c, px, pz)
		if is_nan(y) or y < ylo or y > yhi or y <= best:
			continue
		best = y
		who = owner_of[t]
	return [best, who]


## TOUTES les surfaces plates a l'aplomb de (px, pz), triees du bas vers le
## haut. C'est de quoi decrire une colonne d'habitacle avec ses SURPLOMBS : sous
## la planche de bord, on y lit le plancher a 0,33, le dessous de la planche a
## 0,80 et son dessus a 0,95 — trois niveaux, et le pedalier est le vide entre
## les deux premiers.
##
## LE SIGNE DE LA NORMALE N'EST PAS FIABLE et c'est pour ca qu'on ne s'en sert
## pas pour separer "dessus" de "dessous" : le loft de la planche de bord sort
## du .glb avec ses normales retournees (probe_surfaces.gd l'avait deja releve).
## On ne retient donc qu'une chose, qui elle est sure : la face est PLATE.
func column_at(px: float, pz: float, ylo: float, yhi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var k := Vector2i(int(floor(px / CELL)), int(floor(pz / CELL)))
	if not _col.has(k):
		return out
	for t in _col[k]:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		if absf((b - a).cross(c - a).normalized().y) < UP_MIN:
			continue
		var y := _height_at(a, b, c, px, pz)
		if is_nan(y) or y < ylo or y > yhi:
			continue
		out.append(y)
	out.sort()
	return out


## Hauteur du triangle a l'aplomb de (px, pz), NAN si en dehors.
func _height_at(a: Vector3, b: Vector3, c: Vector3, px: float, pz: float) -> float:
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 1e-12:
		return NAN
	var w0 := ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / d
	var w1 := ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / d
	var w2 := 1.0 - w0 - w1
	var e := -0.0001
	if w0 < e or w1 < e or w2 < e:
		return NAN
	return w0 * a.y + w1 * b.y + w2 * c.y


# --------------------------------------------------------------------------

## La boite (centre, demi-cotes) mord-elle un triangle du modele ? C'est la
## question "cet objet est-il ENFONCE DANS le decor visible ?", et c'est le
## defaut que le joueur rapporte : l'objet ne traverse pas la caisse, il
## s'arrete DEDANS, la ou une boite de collision trop grosse l'a arrete.
##
## Renvoie le nom de la piece mordue, "" sinon.
func hits_box(centre: Vector3, half: Vector3) -> String:
	var lo := centre - half
	var hi := centre + half
	var seen := {}
	for i in range(int(floor(lo.x / CELL)), int(floor(hi.x / CELL)) + 1):
		for h in range(int(floor(lo.y / CELL)), int(floor(hi.y / CELL)) + 1):
			for j in range(int(floor(lo.z / CELL)), int(floor(hi.z / CELL)) + 1):
				var v := Vector3i(i, h, j)
				if not _vox.has(v):
					continue
				for t in _vox[v]:
					if seen.has(t):
						continue
					seen[t] = true
					if _tri_box(tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2],
							centre, half):
						return names[owner_of[t]]
	return ""


## Separation d'axes triangle / boite alignee (Akenine-Moller) : 3 axes de la
## boite, la normale du triangle, et les 9 produits croises arete x axe.
func _tri_box(a: Vector3, b: Vector3, c: Vector3, centre: Vector3, half: Vector3) -> bool:
	var v0 := a - centre
	var v1 := b - centre
	var v2 := c - centre

	# 1. Les trois axes de la boite.
	for i in 3:
		var lo := minf(v0[i], minf(v1[i], v2[i]))
		var hi := maxf(v0[i], maxf(v1[i], v2[i]))
		if lo > half[i] or hi < -half[i]:
			return false

	# 2. La normale du triangle.
	var n := (v1 - v0).cross(v2 - v0)
	var d := n.dot(v0)
	var r := half.x * absf(n.x) + half.y * absf(n.y) + half.z * absf(n.z)
	if absf(d) > r:
		return false

	# 3. Les neuf produits croises.
	var edges := [v1 - v0, v2 - v1, v0 - v2]
	var verts := [v0, v1, v2]
	for e in edges:
		for i in 3:
			var axis := Vector3.ZERO
			axis[i] = 1.0
			var ax: Vector3 = (e as Vector3).cross(axis)
			if ax.length_squared() < 1e-12:
				continue
			var p0 := ax.dot(verts[0])
			var p1 := ax.dot(verts[1])
			var p2 := ax.dot(verts[2])
			var rr := half.x * absf(ax.x) + half.y * absf(ax.y) + half.z * absf(ax.z)
			if minf(p0, minf(p1, p2)) > rr or maxf(p0, maxf(p1, p2)) < -rr:
				return false
	return true
