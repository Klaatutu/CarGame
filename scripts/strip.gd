extends RefCounted
##
## LE RUBAN — la geometrie que la route et la ville ont en commun.
##
## C'est le code de road.gd (_strip_of, les pointilles, la remise au maillage)
## sorti tel quel et pose en fonctions STATIQUES, sans etat. Pourquoi le
## sortir : une rue de bourg est LE MEME ruban que la nationale, et si les deux
## sont ecrits deux fois, ils finissent par ne plus dire tout a fait la meme
## chose. Un ecart de un centimetre a la couture n'est pas une imprecision,
## c'est un trait de brouillard qui traverse la chaussee a 2 m des phares.
## Ici il n'y a rien a synchroniser : c'est le meme code, donc les memes
## triangles, par identite et pas par arithmetique.
##
## ENROULEMENT HORAIRE vu du dessus. Godot prend les faces horaires pour les
## faces avant : intervertir deux indices ne donne pas une route plus sombre,
## ca donne une route PUREMENT ET SIMPLEMENT INVISIBLE. Le depot l'a paye deux
## fois. L'ordre des indices ne se touche pas au raisonnement, il se verifie a
## la capture.
##
## Les tableaux (v, n, f) restent la propriete de l'appelant : GDScript passe
## les PackedArray par reference, on ecrit dedans, on ne rend rien. C'est ce
## qui permet a plusieurs bandes de s'empiler dans une meme surface avant
## d'etre versees d'un coup.
##


## Bande continue entre deux decalages lateraux, le long de toute une ligne :
## le ruban vivant, le brin mort d'une fourche, ou la traversante d'un bourg.
##
## Le masque (skip_from, skip_to) saute les QUADS d'indices [skip_from,
## skip_to) et JAMAIS les sommets. C'est la que se joue tout l'interet de la
## chose : les sommets sont tous emis, dans le meme ordre, aux memes indices,
## donc il n'y a rien a renumeroter et aucune faute d'indice n'est possible.
## Le trou tombe pile SUR le sommet skip_from, qui est aussi le premier point
## de ce que la ville dessinera : la couture est nulle parce que c'est le meme
## point, pas parce qu'on l'a calculee.
##
## Par defaut (-1, -1) rien n'est saute : `i >= -1` est toujours vrai, `i < -1`
## jamais — le ruban est celui d'avant, au bit pres.
static func ribbon(v: PackedVector3Array, n: PackedVector3Array, f: PackedInt32Array,
		pos: PackedVector3Array, right: PackedVector3Array,
		off_a: float, off_b: float, y: float, cols: int,
		skip_from := -1, skip_to := -1) -> void:
	var base := v.size()
	var lift := Vector3(0.0, y, 0.0)
	var count := pos.size()
	var stride := cols + 1
	for i in count:
		for c in stride:
			var t := float(c) / float(cols)
			v.append(pos[i] + right[i] * lerpf(off_a, off_b, t) + lift)
			n.append(Vector3.UP)
	for i in count - 1:
		if i >= skip_from and i < skip_to:
			continue
		for c in cols:
			var a := base + i * stride + c
			var b := a + stride
			f.append_array([a, b, b + 1, a, b + 1, a + 1])


## Des quads poses a plat, quatre coins a la fois, dans l'ordre (arriere
## gauche, arriere droit, avant gauche, avant droit) : les pointilles centraux
## de la route, et demain les paves de carrefour d'un bourg.
##
## Les coins arrivent SANS leur hauteur, c'est ici qu'on les souleve — un seul
## endroit qui connait l'ordre des couches, un seul endroit ou se tromper.
## Meme enroulement horaire que le ruban : c'est le meme monde, vu du meme
## dessus.
static func quads(v: PackedVector3Array, n: PackedVector3Array, f: PackedInt32Array,
		corners: PackedVector3Array, y: float) -> void:
	var lift := Vector3(0.0, y, 0.0)
	for q in corners.size() / 4:
		var base := v.size()
		for k in 4:
			v.append(corners[q * 4 + k] + lift)
			n.append(Vector3.UP)
		f.append_array([base, base + 2, base + 3, base, base + 3, base + 1])


## Verse les tableaux dans une surface neuve du maillage, avec son materiau.
##
## Les tableaux sont DUPLIQUES : l'appelant les vide aussitot pour empiler la
## surface suivante, et le maillage doit garder les siens. Sans triangle on ne
## verse rien du tout : Godot refuse une surface vide (ERR_INVALID_DATA, deux
## lignes rouges par appel) — c'est le cas du brin mort d'une fourche tant
## qu'il n'a pas ses deux premiers points.
static func commit(v: PackedVector3Array, n: PackedVector3Array, f: PackedInt32Array,
		mat: Material, mesh: ArrayMesh) -> void:
	if f.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v.duplicate()
	arrays[Mesh.ARRAY_NORMAL] = n.duplicate()
	arrays[Mesh.ARRAY_INDEX] = f.duplicate()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
