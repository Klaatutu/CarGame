extends SceneTree
##
## Outil : releve la forme de l'habitacle sur le .glb et l'ecrit sur disque.
##
##   godot --headless --path . --script res://tools/bake_cabin.gd
##
## Produit assets/cabin_shape.res, que cabin.gd charge au demarrage. A relancer
## quand civic_interior.glb change ; cabin.gd previent si le fichier manque.
##
## POURQUOI CUIRE PLUTOT QUE CALCULER AU DEMARRAGE. Rasteriser 108 000 triangles
## coute quelques secondes. On ne les paie pas a chaque lancement, et surtout on
## ne les paie pas DEUX FOIS : le releve est le meme pour le jeu et pour les
## sondes, et un releve pose sur disque est un releve qu'on peut relire et
## comparer au modele.
##
## CE QU'ON N'Y MET PAS. Le vitrage (on regarde au travers, et la coque de
## cabin.gd s'en charge par des bornes) et les pieces qui BOUGENT — volant,
## levier, pare-soleil, retroviseur, manivelles, pedales. Une case figee sur un
## volant qui tourne serait un mensonge de plus, exactement du genre qu'on
## retire ici. Voir mesh_probe.gd, SKIP.
##

const MeshProbe := preload("res://scripts/mesh_probe.gd")
const Shape := preload("res://scripts/cabin_shape.gd")

const GLB := "res://assets/models/civic_interior.glb"
const OUT := "res://assets/cabin_shape.res"

const STEP := 0.02
## L'habitacle, un peu large. La coque de cabin.gd borne plus finement.
const LO := Vector3(-0.82, 0.10, -1.06)
const HI := Vector3(0.82, 1.36, 1.56)
## Au-dela, ce n'est plus une surface de depose : c'est le ciel de toit, les
## pare-soleil, le retroviseur. Meme plafond que probe_surfaces.gd.
const TOP_CAP := 1.10


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var mesh := MeshProbe.new()
	mesh.load_glb(GLB)
	print("maillage : %d triangles, %d pieces   (%d ms)" % [
		mesh.tris.size() / 3, mesh.names.size(), Time.get_ticks_msec() - t0])
	if mesh.tris.is_empty():
		push_error("aucun triangle : rien a cuire")
		quit(1)
		return

	var shape: Resource = Shape.new()
	shape.step = STEP
	shape.origin = LO
	shape.nx = int(ceil((HI.x - LO.x) / STEP))
	shape.ny = int(ceil((HI.y - LO.y) / STEP))
	shape.nz = int(ceil((HI.z - LO.z) / STEP))
	shape.source = GLB
	shape.triangles = mesh.tris.size() / 3

	var cells: int = shape.nx * shape.ny * shape.nz
	shape.solid.resize((cells + 7) / 8)
	shape.solid.fill(0)
	print("grille   : %d x %d x %d = %d cases de %.0f mm   (%d ko)" % [
		shape.nx, shape.ny, shape.nz, cells, STEP * 1000.0,
		shape.solid.size() / 1024])

	_voxelize(mesh, shape)
	_fill_voids(shape)
	_heights(mesh, shape)

	var err := ResourceSaver.save(shape, OUT)
	if err != OK:
		push_error("ecriture de %s impossible (%d)" % [OUT, err])
		quit(1)
		return
	print("\necrit : %s   (%d ms en tout)" % [OUT, Time.get_ticks_msec() - t0])
	_report(shape)
	quit()


# --------------------------------------------------------------------------

## Une case est pleine des qu'un triangle la traverse. Le test est exact
## (separation d'axes, mesh_probe.gd) : une tole de 2 mm posee en travers d'une
## case la remplit, ce qu'un test sur les seuls sommets raterait.
func _voxelize(mesh: MeshProbe, shape: Resource) -> void:
	var t0 := Time.get_ticks_msec()
	var half := Vector3(STEP, STEP, STEP) * 0.5
	var n := mesh.tris.size() / 3
	var filled := 0
	for t in n:
		var a := mesh.tris[t * 3]
		var b := mesh.tris[t * 3 + 1]
		var c := mesh.tris[t * 3 + 2]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		var i0 := int(floor((lo.x - LO.x) / STEP))
		var i1 := int(floor((hi.x - LO.x) / STEP))
		var j0 := int(floor((lo.y - LO.y) / STEP))
		var j1 := int(floor((hi.y - LO.y) / STEP))
		var k0 := int(floor((lo.z - LO.z) / STEP))
		var k1 := int(floor((hi.z - LO.z) / STEP))
		for i in range(maxi(i0, 0), mini(i1, shape.nx - 1) + 1):
			for j in range(maxi(j0, 0), mini(j1, shape.ny - 1) + 1):
				for k in range(maxi(k0, 0), mini(k1, shape.nz - 1) + 1):
					if shape.at(i, j, k):
						continue
					var centre := LO + Vector3(float(i), float(j), float(k)) * STEP + half
					if mesh._tri_box(a, b, c, centre, half):
						shape.set_at(i, j, k)
						filled += 1
	print("cases pleines : %d   (%.1f %% de la grille)   %d ms" % [
		filled, 100.0 * float(filled) / float(shape.nx * shape.ny * shape.nz),
		Time.get_ticks_msec() - t0])


## EST PLEIN TOUT CE QUE L'OBJET NE PEUT PAS ATTEINDRE.
##
## La rasterisation ne marque que les cases TRAVERSEES par un triangle : elle
## produit une coque, pas un volume. Prise telle quelle, elle laisse creux le
## tunnel de transmission, la console, les sieges — et un objet qui y entre n'a
## plus rien pour l'en sortir : il tombe au fond et s'y arrete. Elle laisse aussi
## ouverte une chose plus vicieuse, parce qu'elle est ouverte pour de vrai : le
## VIDE ENTRE LE BORD DU PLANCHER ET LA LEVRE DE BAS DE CAISSE. Le modele ne le
## remplit pas, il communique avec le dessous de la voiture, et une canette
## poussee par un virage s'y glissait pour s'arreter le coin dans la tole.
##
## D'ou la definition, qui est plus simple que "boucher les trous" et qui les
## boucherait tous : **l'air de l'habitacle est ce qu'on atteint depuis la place
## du conducteur, et tout le reste est plein.** On part donc de l'oeil et on
## propage dans le vide, BORNE PAR LA COQUE (cabin.gd, HULL_MIN/MAX) : ce qui
## est hors de la coque n'est pas de l'air d'habitacle, quand bien meme on y
## accederait par une baie sans vitre.
##
## Ce que ca donne, sans qu'on ait eu a les enumerer : le dessous du plancher,
## l'interieur du tunnel, celui des sieges, le caisson des portieres, le vide du
## bas de caisse, et tout l'exterieur de la voiture — pleins. La grille fait
## alors elle-meme le travail de la coque, et les deux ne peuvent plus se
## contredire puisque l'une est construite sur l'autre.
##
## LE GARDE-FOU N'EST PAS DECORATIF. Si l'oeil se retrouvait un jour dans une
## case pleine — modele modifie, coque deplacee — la propagation ne partirait de
## nulle part et la voiture entiere deviendrait un bloc, sans rien casser de
## visible et avec tous les bancs au vert le temps qu'on s'en apercoive. On
## verifie donc qu'il reste de l'air, et beaucoup, avant d'ecrire.
func _fill_voids(shape: Resource) -> void:
	var t0 := Time.get_ticks_msec()
	var cabin := load("res://scripts/cabin.gd")
	var hull_lo: Vector3 = cabin.HULL_MIN
	var hull_hi: Vector3 = cabin.HULL_MAX
	var nx: int = shape.nx
	var ny: int = shape.ny
	var nz: int = shape.nz
	var seen := PackedByteArray()
	seen.resize(nx * ny * nz)
	seen.fill(0)

	# Depart : l'oeil du conducteur (cabin.gd, EYE_REF).
	var eye := Vector3i(
		int((-0.33 - LO.x) / STEP), int((1.15 - LO.y) / STEP), int((0.28 - LO.z) / STEP))
	if shape.at(eye.x, eye.y, eye.z):
		push_error("la place du conducteur est dans la tole : rien n'est ecrit.")
		quit(1)
		return
	var eye_b: int = (eye.z * ny + eye.y) * nx + eye.x
	seen[eye_b] = 1
	var stack := PackedInt32Array([eye_b])

	while not stack.is_empty():
		var b: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var i: int = b % nx
		var j: int = (b / nx) % ny
		var k: int = b / (nx * ny)
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var ii: int = i + d.x
			var jj: int = j + d.y
			var kk: int = k + d.z
			if ii < 0 or ii >= nx or jj < 0 or jj >= ny or kk < 0 or kk >= nz:
				continue
			if shape.at(ii, jj, kk):
				continue
			# Borne par la coque : le centre de la case doit etre dedans.
			var c := LO + Vector3(float(ii) + 0.5, float(jj) + 0.5, float(kk) + 0.5) * STEP
			if c.x < hull_lo.x or c.x > hull_hi.x or c.y < hull_lo.y or c.y > hull_hi.y \
					or c.z < hull_lo.z or c.z > hull_hi.z:
				continue
			var bb: int = (kk * ny + jj) * nx + ii
			if seen[bb] != 0:
				continue
			seen[bb] = 1
			stack.append(bb)

	var air := 0
	for v in seen:
		air += v
	# Un habitacle, c'est de l'ordre du metre cube : a 2 cm la case, ca fait des
	# dizaines de milliers de cases. Beaucoup moins veut dire que la propagation
	# s'est arretee tout de suite, et qu'on s'apprete a ecrire un bloc.
	if air < 20000:
		push_error(("l'air d'habitacle ne fait que %d cases : la propagation " +
			"n'a pas pris. Rien n'est ecrit.") % air)
		quit(1)
		return

	var added := 0
	for i in nx:
		for j in ny:
			for k in nz:
				var b2: int = (k * ny + j) * nx + i
				if seen[b2] != 0 or shape.at(i, j, k):
					continue
				shape.set_at(i, j, k)
				added += 1
	print("air d'habitacle : %d cases   /   rempli : %d cases   %d ms" % [
		air, added, Time.get_ticks_msec() - t0])


## La cote de la surface la plus haute de chaque colonne. Le voxel dit ou est la
## matiere au demi-centimetre pres ; celle-ci dit ou se POSE un objet, au
## millimetre. Sans elle, un paquet pose sur la planche de bord se caserait par
## crans de 2 cm, ce qui se voit tout de suite.
##
## ON PREND LE MAXIMUM SUR LA CASE, PAS LA VALEUR AU CENTRE.
##
## Le centre est le point que la case represente, et c'est ce qu'on relevait
## d'abord. Mais prop.gd s'en sert pour POSER un objet, et un objet couvre
## plusieurs cases : il lui faut une borne SUPERIEURE de la tole sous lui, pas
## une valeur juste au milieu. Sur une surface bombee — un coussin de siege — la
## tole entre deux centres monte plus haut qu'aux deux centres, et l'objet pose a
## la valeur du centre s'enfonce dedans. C'etait 13 canettes dans
## SEAT_Driver_Cushion.
##
## Sur une surface plane, les neuf echantillons donnent la meme valeur et le
## releve est exact : on ne perd la precision que la ou il y a une pente, et on
## la perd du bon cote — un objet qui flotte d'un millimetre se voit moins qu'un
## objet enfonce d'un millimetre.
func _heights(mesh: MeshProbe, shape: Resource) -> void:
	var t0 := Time.get_ticks_msec()
	shape.top.resize(shape.nx * shape.nz)
	shape.top.fill(-99.0)
	var hits := 0
	for i in shape.nx:
		for k in shape.nz:
			var best := -99.0
			for u in 3:
				var x := LO.x + (float(i) + 0.5 * float(u)) * STEP
				for v in 3:
					var z := LO.z + (float(k) + 0.5 * float(v)) * STEP
					var r := mesh.top_at(x, z, LO.y, TOP_CAP)
					best = maxf(best, r[0])
			if best > -90.0:
				shape.top[k * shape.nx + i] = best
				hits += 1
	print("colonnes portantes : %d sur %d   (%.0f %%)   %d ms" % [
		hits, shape.top.size(), 100.0 * float(hits) / float(shape.top.size()),
		Time.get_ticks_msec() - t0])


## De quoi verifier d'un coup d'oeil que le releve tient debout : la hauteur
## relevee a quelques endroits dont on connait la reponse.
func _report(shape: Resource) -> void:
	print("\n=== SONDAGES ===")
	var spots := [
		["planche, milieu", Vector3(0.0, 0.0, -0.80)],
		["planche, cote conducteur", Vector3(-0.35, 0.0, -0.66)],
		["planche, cote passager", Vector3(0.35, 0.0, -0.66)],
		["capot des compteurs", Vector3(-0.33, 0.0, -0.78)],
		["assise conducteur", Vector3(-0.33, 0.0, 0.24)],
		["console", Vector3(0.0, 0.0, -0.24)],
		["plancher conducteur", Vector3(-0.40, 0.0, 0.30)],
		["banquette arriere", Vector3(0.0, 0.0, 1.00)],
		["pedalier (sous la planche)", Vector3(-0.35, 0.0, -0.75)],
	]
	for s in spots:
		var p: Vector3 = s[1]
		print("  %-28s : dessus a %.3f m" % [s[0], shape.height_at(p.x, p.z)])
