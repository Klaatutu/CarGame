extends SceneTree
##
## Outil : ce que la grille et le maillage disent d'UN point precis.
##
##   godot --headless --path . --script res://tools/check_spot.gd
##
## Quand un balayage designe un coupable — "126 canettes dans DOOR_R_Sill a
## x 0,727" — il reste a savoir POURQUOI la grille ne les arrete pas la ou la
## tole est. On pose donc la question aux deux, au meme endroit.
##

const MeshProbe := preload("res://scripts/mesh_probe.gd")
const SHAPE := "res://assets/cabin_shape.res"
const GLB := "res://assets/models/civic_interior.glb"

const HALF_CAN := Vector3(0.033, 0.0575, 0.033)


func _initialize() -> void:
	var shape: Resource = load(SHAPE)
	var mesh := MeshProbe.new()
	mesh.load_glb(GLB)

	var spots := [
		Vector3(0.687, 0.387, 0.267),
	]
	# Le point exact ou le balayage laisse la canette, avec les bornes que
	# prop.gd passe reellement.
	var hull_lo := Vector3(-0.72, 0.33, -0.92)
	var hull_hi := Vector3(0.72, 1.30, 1.43)
	for p in spots:
		print("=== push_out AVEC bornes en %s ===" % str(p))
		var a: Array = shape.push_out(p, HALF_CAN, hull_lo, hull_hi)
		print("  touche=%s  vers %s  -> %s" % [
			a[2], str(a[1]), str((a[0] as Vector3).snappedf(0.001))])
		var b: Array = shape.push_out(p, HALF_CAN)
		print("  sans bornes : touche=%s  vers %s  -> %s" % [
			b[2], str(b[1]), str((b[0] as Vector3).snappedf(0.001))])
		# Les cases pleines que la boite recouvre vraiment.
		var lo: Vector3 = p - HALF_CAN
		var hi: Vector3 = p + HALF_CAN
		print("  boite x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % [
			lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
		var hits := PackedStringArray()
		for i in range(int(floor((lo.x - shape.origin.x) / shape.step)),
				int(floor((hi.x - shape.origin.x) / shape.step)) + 1):
			for j in range(int(floor((lo.y - shape.origin.y) / shape.step)),
					int(floor((hi.y - shape.origin.y) / shape.step)) + 1):
				for k in range(int(floor((lo.z - shape.origin.z) / shape.step)),
						int(floor((hi.z - shape.origin.z) / shape.step)) + 1):
					if shape.at(i, j, k):
						var c: Array = shape.cell_box(i, j, k)
						hits.append(str((c[0] as Vector3).snappedf(0.01)))
		print("  cases pleines recouvertes : %d   %s" % [
			hits.size(), ", ".join(hits.slice(0, 10))])
	for p in spots:
		print("\n=== %s ===" % str(p))
		print("  maillage mord : '%s'" % mesh.hits_box(p, HALF_CAN - Vector3(0.0015, 0.0015, 0.0015)))
		var r: Array = shape.push_out(p, HALF_CAN)
		print("  grille        : touche=%s  vers %s  -> %s" % [
			r[2], str(r[1]), str((r[0] as Vector3).snappedf(0.001))])
		# La colonne de cases a hauteur du point, de x 0,60 a 0,82.
		var line := "  cases en x    : "
		var i := 0
		while i < shape.nx:
			var x: float = shape.origin.x + (float(i) + 0.5) * shape.step
			if absf(x) >= 0.60 and signf(x) == signf(p.x if p.x != 0.0 else 1.0):
				var c: Vector3i = shape._cell(Vector3(x, p.y, p.z))
				line += "%s%s " % [
					"%.2f" % x, "#" if shape.at(c.x, c.y, c.z) else "."]
			i += 1
		print(line)
		# Et ce que le maillage a vraiment a cette hauteur, en x.
		var found := PackedStringArray()
		var x2 := 0.60
		while x2 <= 0.82:
			var n := mesh.hits_box(Vector3(signf(p.x if p.x != 0.0 else 1.0) * x2, p.y, p.z),
				Vector3(0.005, 0.005, 0.005))
			if n != "":
				found.append("%.2f:%s" % [x2, n])
			x2 += 0.01
		print("  tole en x     : %s" % ", ".join(found))

		# La tranche que la canette OCCUPE vraiment : y de 0,33 a 0,45, x de 0,64
		# a 0,80. C'est la qu'il faut regarder, pas sur une seule ligne.
		print("  tranche (x en colonnes, y en lignes) :")
		var yy := 0.45
		while yy >= 0.32:
			var row := "    y=%.2f  " % yy
			var xx := 0.64
			while xx <= 0.80:
				var c2: Vector3i = shape._cell(Vector3(xx, yy, p.z))
				row += "#" if shape.at(c2.x, c2.y, c2.z) else "."
				xx += 0.02
			# Et le maillage sur la meme tranche.
			row += "   tole:"
			xx = 0.64
			while xx <= 0.80:
				row += "#" if mesh.hits_box(Vector3(xx, yy, p.z),
					Vector3(0.008, 0.008, 0.008)) != "" else "."
				xx += 0.02
			print(row)
			yy -= 0.02
		print("    x =        0.64 .. 0.80 par 2 cm")
	quit()
