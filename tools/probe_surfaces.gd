extends SceneTree
##
## Outil : carte de hauteurs du DESSUS reel de l'habitacle, en espace voiture.
##
##   godot --headless --path . --script res://tools/probe_surfaces.gd
##
## Pourquoi. Les surfaces de depose de cabin.gd ETAIENT des boites saisies a la
## main ; rien ne garantissait qu'elles collent au modele. Cette sonde lit le
## .glb, projette tous les triangles PLATS sur une grille en x/z et garde le
## plus haut : c'est exactement ce sur quoi un objet se poserait.
##
## Elle imprime aussi, pour chaque boite declaree, l'ecart entre son plan et le
## maillage qu'elle est censee representer.
##
## CES BOITES NE SONT PLUS CELLES DU JEU. Le jeu se sert desormais du releve
## complet (scripts/cabin_shape.gd, cuit par tools/bake_cabin.gd), et cabin.gd
## ne garde `_build_surfaces()` que pour cette comparaison-ci. C'est elle qui a
## motive le releve, et un avant/apres qu'on efface est un avant/apres qu'on ne
## peut plus refaire : les ecarts ci-dessous — jusqu'a 164 mm sous une assise,
## 35 mm sous la planche passager — sont la raison d'etre de tout le reste.
##
## LE RELEVE EST CELUI DU JEU, pas une seconde implementation. Cette sonde
## posait la meme question que la cuisson avec son propre code : deux reponses
## a "ou est la tole ?" finissent par diverger, et c'est precisement le defaut
## qu'on corrige ailleurs. Les deux passent maintenant par
## scripts/mesh_probe.gd.
##

const MeshProbe := preload("res://scripts/mesh_probe.gd")

const GLB := "res://assets/models/civic_interior.glb"
## On ignore ce qui pend au-dessus (pavillon, pare-soleil, retroviseur).
const Y_CAP := 1.10

var _mesh: MeshProbe


func _initialize() -> void:
	_mesh = MeshProbe.new()
	_mesh.load_glb(GLB)
	print("triangles retenus : %d, pieces : %d" % [
		_mesh.tris.size() / 3, _mesh.names.size()])

	_map("PLANCHE DE BORD", -0.85, 0.85, 0.05, -0.95, -0.40, 0.025, 0.70, 1.05)
	_map("CAPOT DES COMPTEURS", -0.60, -0.05, 0.025, -0.82, -0.44, 0.02, 0.80, 1.05)
	_map("SIEGES ET CONSOLE", -0.85, 0.85, 0.05, -0.45, 0.70, 0.05, 0.30, 1.00)
	_map("ARRIERE", -0.85, 0.85, 0.05, 0.70, 1.50, 0.05, 0.20, 1.00)
	_map("PLANCHER", -0.85, 0.85, 0.05, -0.95, 1.50, 0.10, 0.10, 0.55)

	_check()
	quit()


# --------------------------------------------------------------------------

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
			var r := _mesh.top_at(x0 + dx * i, z0 + dz * j, ylo, minf(yhi, Y_CAP))
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
			seen[_mesh.names[who[k]]] = int(seen.get(_mesh.names[who[k]], 0)) + 1
	var keys := seen.keys()
	keys.sort_custom(func(p, q): return seen[p] > seen[q])
	var parts := PackedStringArray()
	for n in keys:
		parts.append("%s(%d)" % [n, seen[n]])
	print("  pieces : " + ", ".join(parts))


## Les boites HISTORIQUES de cabin.gd, confrontees au maillage sous leur emprise.
func _check() -> void:
	var cabin: Node = load("res://scripts/cabin.gd").new()
	cabin._build_surfaces()
	print("\n=== BOITES HISTORIQUES (cabin.gd) vs MAILLAGE ===")
	print("  (elles ne servent plus au jeu : voir l'en-tete)")
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
				var r := _mesh.top_at(px, pz, y - 0.30, y + 0.25)
				var best: float = r[0]
				if best > -90.0:
					hits += 1
					if best < lowest:
						lowest = best
						who_lo = _mesh.names[r[1]]
					if best > highest:
						highest = best
						who_hi = _mesh.names[r[1]]
		var txt := "aucun maillage" if hits == 0 else \
			"%.3f (%s) .. %.3f (%s)   ecart %+.3f..%+.3f   couverture %d%%" % [
				lowest, who_lo, highest, who_hi, lowest - y, highest - y,
				100 * hits / cells]
		print("  %-4d y=%.3f  x %.2f..%.2f  z %.2f..%.2f   %s" % [
			n, y, lo.x, hi.x, lo.y, hi.y, txt])
		n += 1
	cabin.free()
