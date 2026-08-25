extends SceneTree
##
## Outil : carte de hauteurs du DESSUS reel de l'habitacle, en espace voiture.
##
##   godot --headless --path . --script res://tools/probe_surfaces.gd
##
## Pourquoi. Les surfaces de depose de cabin.gd sont des boites saisies a la
## main ; rien ne garantissait qu'elles collent au modele. Cette sonde lit le
## .glb, projette tous les triangles TOURNES VERS LE HAUT sur une grille en x/z
## et garde le plus haut : c'est exactement ce sur quoi un objet se poserait.
##
## Elle imprime aussi, pour chaque boite declaree, l'ecart entre son plan et le
## maillage qu'elle est censee representer.
##

const GLB := "res://assets/models/civic_interior.glb"
## Faces plus inclinees que ca : ce n'est pas une surface, c'est un flanc.
const UP_MIN := 0.55
## On ignore ce qui pend au-dessus (pavillon, pare-soleil, retroviseur).
const Y_CAP := 1.10
## Vitrage et pieces qu'on ne veut pas voir dans la carte.
const SKIP := ["Glass", "Windshield", "Belt", "Seatbelt"]

## Cote des cases de tri (broad phase) : sans ca, chaque point de mesure
## repasserait sur les dizaines de milliers de triangles du modele.
const CELL := 0.10

var _tris: PackedVector3Array = PackedVector3Array()   # 3 sommets par triangle
var _owner: PackedInt32Array = PackedInt32Array()      # index de nom par triangle
var _names: PackedStringArray = PackedStringArray()
var _bins := {}                                        # Vector2i -> PackedInt32Array


func _initialize() -> void:
	var root := (load(GLB) as PackedScene).instantiate()
	_gather(root, Transform3D())
	_sort_tris()
	print("triangles retenus : %d, pieces : %d" % [_tris.size() / 3, _names.size()])

	_map("PLANCHE DE BORD", -0.85, 0.85, 0.05, -0.95, -0.40, 0.025, 0.70, 1.05)
	_map("CAPOT DES COMPTEURS", -0.60, -0.05, 0.025, -0.82, -0.44, 0.02, 0.80, 1.05)
	_map("SIEGES ET CONSOLE", -0.85, 0.85, 0.05, -0.45, 0.70, 0.05, 0.30, 1.00)
	_map("ARRIERE", -0.85, 0.85, 0.05, 0.70, 1.50, 0.05, 0.20, 1.00)
	_map("PLANCHER", -0.85, 0.85, 0.05, -0.95, 1.50, 0.10, 0.10, 0.55)

	_check()
	quit()


# --------------------------------------------------------------------------

func _gather(n: Node, tf: Transform3D) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var world := tf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and not _skipped(c.name):
			_add_mesh(c as MeshInstance3D, world)
		_gather(c, world)


func _skipped(name: String) -> bool:
	for s in SKIP:
		if name.findn(s) >= 0:
			return true
	return false


func _add_mesh(mi: MeshInstance3D, tf: Transform3D) -> void:
	var id := _names.size()
	var kept := false
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
			var nrm := (b - a).cross(c - a)
			# Valeur ABSOLUE : le loft de la planche de bord sort avec des normales
			# retournees, et filtrer sur le signe faisait disparaitre tout son
			# dessus de la carte. Ce qui compte ici, c'est qu'une face soit plate.
			if nrm.length_squared() < 1e-12 or absf(nrm.normalized().y) < UP_MIN:
				continue
			if maxf(a.y, maxf(b.y, c.y)) > Y_CAP:
				continue
			_tris.append_array([a, b, c])
			_owner.append(id)
			kept = true
	if kept:
		_names.append(mi.name)


## Range chaque triangle dans les cases qu'il survole.
func _sort_tris() -> void:
	for t in _tris.size() / 3:
		var a := _tris[t * 3]
		var b := _tris[t * 3 + 1]
		var c := _tris[t * 3 + 2]
		var i0 := int(floor(minf(a.x, minf(b.x, c.x)) / CELL))
		var i1 := int(floor(maxf(a.x, maxf(b.x, c.x)) / CELL))
		var j0 := int(floor(minf(a.z, minf(b.z, c.z)) / CELL))
		var j1 := int(floor(maxf(a.z, maxf(b.z, c.z)) / CELL))
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var k := Vector2i(i, j)
				if not _bins.has(k):
					_bins[k] = PackedInt32Array()
				_bins[k].append(t)


## Triangle le plus haut a l'aplomb de (px, pz) sous `yhi`, et la piece a qui il
## est. Retourne [hauteur, index de piece] ; hauteur -99 si rien.
func _top_at(px: float, pz: float, ylo: float, yhi: float) -> Array:
	var k := Vector2i(int(floor(px / CELL)), int(floor(pz / CELL)))
	if not _bins.has(k):
		return [-99.0, -1]
	var best := -99.0
	var who := -1
	for t in _bins[k]:
		var y := _height_at(_tris[t * 3], _tris[t * 3 + 1], _tris[t * 3 + 2], px, pz)
		if is_nan(y) or y < ylo or y > yhi or y <= best:
			continue
		best = y
		who = _owner[t]
	return [best, who]


## Carte de hauteurs : une ligne par z, une colonne par x, hauteur en cm.
func _map(title: String, x0: float, x1: float, dx: float,
		z0: float, z1: float, dz: float, ylo: float, yhi: float) -> void:
	var nx := int(round((x1 - x0) / dx)) + 1
	var nz := int(round((z1 - z0) / dz)) + 1
	var h := PackedFloat32Array()
	var who := PackedInt32Array()
	h.resize(nx * nz)
	who.resize(nx * nz)
	h.fill(-99.0)
	who.fill(-1)

	for j in nz:
		for i in nx:
			var r := _top_at(x0 + dx * i, z0 + dz * j, ylo, yhi)
			h[j * nx + i] = r[0]
			who[j * nx + i] = r[1]

	print("\n=== %s ===  (hauteur en cm, '.' = rien entre %.2f et %.2f)" % [title, ylo, yhi])
	var head := "   z\\x "
	for i in nx:
		head += "%4d" % int(round((x0 + dx * i) * 100.0))
	print(head)
	for j in nz:
		var line := "%7.3f" % (z0 + dz * j)
		for i in nx:
			var v := h[j * nx + i]
			line += "   ." if v < -90.0 else "%4d" % int(round(v * 100.0))
		print(line)

	# Qui est au-dessus, piece par piece.
	var seen := {}
	for k in who.size():
		if who[k] >= 0:
			seen[_names[who[k]]] = int(seen.get(_names[who[k]], 0)) + 1
	var keys := seen.keys()
	keys.sort_custom(func(p, q): return seen[p] > seen[q])
	var parts := PackedStringArray()
	for n in keys:
		parts.append("%s(%d)" % [n, seen[n]])
	print("  pieces : " + ", ".join(parts))


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


## Les boites declarees par cabin.gd, confrontees au maillage sous leur emprise.
func _check() -> void:
	var cabin: Node = load("res://scripts/cabin.gd").new()
	cabin._build_surfaces()
	print("\n=== BOITES DECLAREES (cabin.gd) vs MAILLAGE ===")
	print("  %-4s %-8s %-30s %s" % ["#", "plan", "emprise x / z", "maillage dessous"])
	var n := 0
	for s in cabin.surfaces:
		var lo: Vector2 = s["min"]
		var hi: Vector2 = s["max"]
		var y: float = s["y"]
		var lowest := 99.0
		var highest := -99.0
		var who_lo := ""
		var who_hi := ""
		var hits := 0
		var cells := 0
		var steps := 12
		for i in steps + 1:
			for j in steps + 1:
				var px := lerpf(lo.x, hi.x, float(i) / steps)
				var pz := lerpf(lo.y, hi.y, float(j) / steps)
				cells += 1
				var r := _top_at(px, pz, y - 0.30, y + 0.25)
				var best: float = r[0]
				if best > -90.0:
					hits += 1
					if best < lowest:
						lowest = best
						who_lo = _names[r[1]]
					if best > highest:
						highest = best
						who_hi = _names[r[1]]
		var txt := "aucun maillage" if hits == 0 else \
			"%.3f (%s) .. %.3f (%s)   ecart %+.3f..%+.3f   couverture %d%%" % [
				lowest, who_lo, highest, who_hi, lowest - y, highest - y,
				100 * hits / cells]
		print("  %-4d y=%.3f  x %.2f..%.2f  z %.2f..%.2f   %s" % [
			n, y, lo.x, hi.x, lo.y, hi.y, txt])
		n += 1
	cabin.free()
