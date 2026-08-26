extends SceneTree
##
## Outil : relit assets/cabin_shape.res et verifie qu'il est utilisable.
##
##   godot --headless --path . --script res://tools/check_shape.gd
##
## Une ressource cuite qui ne se relit pas est pire qu'une ressource absente :
## le jeu demarre, la forme est vide, et tout traverse tout sans que rien ne le
## dise. On le dit ici.
##

const PATH := "res://assets/cabin_shape.res"


func _initialize() -> void:
	var shape: Resource = load(PATH)
	if shape == null:
		push_error("%s illisible" % PATH)
		quit(1)
		return
	print("relu : %s" % PATH)
	print("  grille %d x %d x %d, cases de %.0f mm, origine %s" % [
		shape.nx, shape.ny, shape.nz, shape.step * 1000.0, str(shape.origin)])
	print("  source %s, %d triangles" % [shape.source, shape.triangles])
	print("  octets d'occupation : %d   hauteurs : %d" % [
		shape.solid.size(), shape.top.size()])

	var filled := 0
	for b in shape.solid:
		filled += _bits(b)
	print("  cases pleines : %d" % filled)

	# Une case dont on connait la reponse : le dessus de la planche de bord.
	var h: float = shape.height_at(-0.35, -0.66)
	print("  planche cote conducteur : %.3f m" % h)

	# La descente d'un objet sur cette planche doit s'y arreter, pas la traverser.
	var half := Vector3(0.0275, 0.011, 0.0425)
	var p := Vector3(-0.35, 1.05, -0.66)
	var steps := 0
	while p.y > 0.5 and steps < 200:
		p.y -= 0.005
		var r: Array = shape.push_out(p, half)
		steps += 1
		if r[2]:
			p = r[0]
			# Comme prop.gd : on resout d'abord, on se pose ensuite. Sans cette
			# ligne on mesure le bord de la case (0,971) et pas la tole (0,959).
			p.y = shape.settle(p, half)
			break
	print("  un paquet lache dessus s'arrete a y=%.3f   (attendu ~%.3f)" % [
		p.y, h + half.y])

	# Le rayon de visee doit trouver la meme tole.
	var hit: Array = shape.raycast(Vector3(-0.33, 1.15, 0.28),
		(Vector3(-0.35, 0.94, -0.66) - Vector3(-0.33, 1.15, 0.28)).normalized(), 2.0)
	print("  visee depuis l'oeil : touche=%s  point=%s  normale=%s" % [
		hit[0], str((hit[1] as Vector3).snappedf(0.001)), str(hit[2])])

	# Et le mille-pattes doit trouver la tole a portee.
	var near: Dictionary = shape.nearest(Vector3(-0.35, 0.955, -0.66), 0.12)
	print("  tole la plus proche : d=%.4f m  normale=%s  dedans=%s" % [
		near["d"], str(near["n"]), near["inside"]])
	quit()


func _bits(b: int) -> int:
	var n := 0
	for i in 8:
		if b & (1 << i):
			n += 1
	return n
