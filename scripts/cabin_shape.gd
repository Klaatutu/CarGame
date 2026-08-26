extends Resource
##
## LA FORME DE L'HABITACLE, RELEVEE SUR LE MODELE.
##
## Une seule geometrie de collision pour les trois choses qui en demandaient
## chacune une : les objets qui tombent (prop.gd), la visee de depose
## (interaction.gd) et le mille-pattes qui marche (centipede.gd).
##
## POURQUOI ELLE EXISTE
## ---------------------------------------------------------------------------
## Avant, cabin.gd declarait trois listes de boites SAISIES A LA MAIN —
## `surfaces`, `solids`, `crawl_solids` — et rien ne garantissait qu'elles
## collent au .glb. Elles n'y collaient pas, et les trois defauts que voyait le
## joueur etaient le meme defaut :
##
##   - LES OBJETS LANCES S'ARRETAIENT DANS LES PAROIS. Les portieres etaient
##     declarees a x 0,79, qui est la TOLE ; la garniture qu'on voit est a 0,70.
##     Un objet s'arretait donc proprement — 9 cm DERRIERE le panneau visible.
##     Mesure avant correction (tools/probe_collisions.gd) : 28 % des lancers
##     pour le paquet, 59 % pour une canette, immobilises DANS une piece du
##     modele. Le banc `-- throwtest`, lui, etait vert : il mesurait les fuites
##     hors de la caisse, et une fuite n'est pas un enfoncement.
##   - ON NE POUVAIT PAS POSER SUR TOUT LE TABLEAU DE BORD. Le fond de planche
##     n'avait de boite que cote passager. Le maillage, lui, court d'un montant
##     a l'autre a 93-95 cm : la tole etait la, la surface de depose non.
##   - LE MILLE-PATTES NE MARCHAIT PAS SUR TOUT. `crawl_solids` ajoutait a la
##     main les trois faces verticales auxquelles on avait pense. Les autres —
##     montants, bas de caisse, tunnel, capot des compteurs, dossiers — n'y
##     etaient pas, donc elles n'existaient pas pour lui.
##
## CE QUE C'EST
## ---------------------------------------------------------------------------
## Deux releves, et chacun fait ce que l'autre fait mal.
##
##   - UN VOXEL (`solid`) — une case de 2 cm est pleine si un triangle du modele
##     la traverse. C'est ce qui ARRETE : il attrape les faces VERTICALES, que
##     rien d'autre ici ne voit — contre-portes, nez de planche, bas de caisse,
##     tunnel, dossiers. Deux cases ne peuvent pas se contredire, ce qui retire
##     d'un coup la regle "aucune boite ne doit en chevaucher une autre" que
##     cabin.gd tenait a la main et enfreignait treize fois.
##   - UN CHAMP DE HAUTEURS (`top`) — la cote exacte de la surface la plus haute
##     a l'aplomb de chaque colonne. C'est ce qui PORTE : un voxel poserait
##     l'objet au demi-centimetre pres, ce qui se verrait ; le champ le pose au
##     millimetre, sur la tole elle-meme.
##
## Le voxel dit "tu ne passes pas", le champ dit "tu te poses la". Aucun des
## deux ne sait faire les deux.
##
## LES SURPLOMBS TOMBENT TOUT SEULS. Une case n'est pleine que la ou il y a de
## la matiere : sous la planche de bord, le pedalier reste vide alors que le
## dessus de planche, 60 cm plus haut, est plein. C'est ce qu'un simple champ de
## hauteurs ne peut pas dire — il aurait rempli le pedalier jusqu'a la planche.
##
## ELLE EST CUITE, PAS CALCULEE AU DEMARRAGE. Rasteriser 108 000 triangles coute
## quelques secondes, ce qu'on ne paie pas a chaque lancement :
##
##   godot --headless --path . --script res://tools/bake_cabin.gd
##
## ecrit assets/cabin_shape.res. A relancer quand le .glb change — cabin.gd
## previent si le fichier manque.
##

## En dessous de ce recouvrement, une case est TOUCHEE et non PENETREE : on ne
## repousse pas. Voir push_out(), "un effleurement n'est pas une penetration".
const CONTACT := 0.001

## Cote d'une case, en metres.
@export var step := 0.02
## Coin bas de la grille, en espace voiture.
@export var origin := Vector3.ZERO
@export var nx := 0
@export var ny := 0
@export var nz := 0
## Occupation, un bit par case. Voir _index().
@export var solid := PackedByteArray()
## Surface la plus haute a l'aplomb de chaque colonne (nx * nz), -99 si rien.
@export var top := PackedFloat32Array()
## De quoi verifier que le releve correspond bien au modele charge.
@export var source := ""
@export var triangles := 0


# --------------------------------------------------------------------------
# Lecture
# --------------------------------------------------------------------------

func _index(i: int, j: int, k: int) -> int:
	return (k * ny + j) * nx + i


func _cell(p: Vector3) -> Vector3i:
	return Vector3i(
		int(floor((p.x - origin.x) / step)),
		int(floor((p.y - origin.y) / step)),
		int(floor((p.z - origin.z) / step)))


func _in_range(i: int, j: int, k: int) -> bool:
	return i >= 0 and i < nx and j >= 0 and j < ny and k >= 0 and k < nz


## La case (i, j, k) est-elle pleine ? Hors grille : vide — la coque de cabin.gd
## se charge de ce qui deborde, et elle le fait par des bornes, pas par des
## cases.
func at(i: int, j: int, k: int) -> bool:
	if not _in_range(i, j, k):
		return false
	var b := _index(i, j, k)
	return (solid[b >> 3] & (1 << (b & 7))) != 0


func set_at(i: int, j: int, k: int) -> void:
	if not _in_range(i, j, k):
		return
	var b := _index(i, j, k)
	solid[b >> 3] |= 1 << (b & 7)


## Boite d'une case, en espace voiture.
func cell_box(i: int, j: int, k: int) -> Array:
	var lo := origin + Vector3(float(i), float(j), float(k)) * step
	return [lo, lo + Vector3(step, step, step)]


## Cote EXACTE de la surface a l'aplomb de (x, z), -99 s'il n'y a rien. Relevee
## sur le triangle, pas sur la case : c'est ce qui evite de poser les objets par
## crans d'un demi-centimetre.
func height_at(x: float, z: float) -> float:
	var i := int(floor((x - origin.x) / step))
	var k := int(floor((z - origin.z) / step))
	if i < 0 or i >= nx or k < 0 or k >= nz:
		return -99.0
	return top[k * nx + i]


## Y a-t-il de la matiere juste sous l'objet ? `tol` est la hauteur de vide
## qu'on tolere sous lui.
##
## LE CHAMP DE HAUTEURS NE SAIT PAS REPONDRE A CA, et c'est pour ca que cette
## methode existe : il rend le dessus de la COLONNE, or sous la planche de bord
## ce dessus est la planche, 60 cm au-dessus des pieds. Un objet pose au
## pedalier passerait donc pour flottant. La grille, elle, connait les surplombs
## — une case n'est pleine que la ou il y a de la matiere.
func grounded_on(centre: Vector3, half: Vector3, tol := 0.004) -> bool:
	var y := centre.y - half.y - tol * 0.5
	var j := int(floor((y - origin.y) / step))
	var i0 := int(floor((centre.x - half.x - origin.x) / step))
	var i1 := int(floor((centre.x + half.x - origin.x) / step))
	var k0 := int(floor((centre.z - half.z - origin.z) / step))
	var k1 := int(floor((centre.z + half.z - origin.z) / step))
	for i in range(maxi(i0, 0), mini(i1, nx - 1) + 1):
		for k in range(maxi(k0, 0), mini(k1, nz - 1) + 1):
			if at(i, j, k):
				return true
	return false


## La plus haute des colonnes que l'objet couvre. Un objet pose a cheval sur
## deux hauteurs repose sur la plus haute des deux — sinon un coin s'enfonce.
func support(centre: Vector3, half: Vector3) -> float:
	var best := -99.0
	var i0 := int(floor((centre.x - half.x - origin.x) / step))
	var i1 := int(floor((centre.x + half.x - origin.x) / step))
	var k0 := int(floor((centre.z - half.z - origin.z) / step))
	var k1 := int(floor((centre.z + half.z - origin.z) / step))
	for i in range(maxi(i0, 0), mini(i1, nx - 1) + 1):
		for k in range(maxi(k0, 0), mini(k1, nz - 1) + 1):
			best = maxf(best, top[k * nx + i])
	return best


# --------------------------------------------------------------------------
# Collision d'une boite
# --------------------------------------------------------------------------

## Sort la boite (centre, demi-cotes) de la matiere, et dit par ou.
##
## LE POINT IMPORTANT EST QU'ON RESOUT CONTRE L'UNION, PAS BOITE PAR BOITE.
##
## L'ancien prop.gd parcourait les solides l'un apres l'autre et sortait de
## chacun independamment. Deux solides qui se recouvrent se contredisent alors :
## le second defait ce que le premier vient de faire, et l'objet vibre sur place
## ou part de travers. C'est ce qui obligeait cabin.gd a s'interdire tout
## chevauchement — une regle tenue a la main, donc une regle qu'on enfreint.
##
## Ici, pour chacune des six directions de sortie, on prend le deplacement qui
## degage TOUTES les cases a la fois (le maximum), puis on retient la direction
## la moins couteuse. Le resultat ne depend plus de l'ordre, aucune case ne peut
## en contredire une autre, et il n'y a plus rien a s'interdire.
##
## ON NE SORT PAS PAR DEHORS, et il a fallu le lui dire.
##
## "La direction la moins couteuse" ne sait pas ou est l'interieur de la
## voiture. Contre le bas de caisse, l'objet est a quelques centimetres de la
## portiere et a un demi-metre du milieu de l'habitacle : le moins couteux est
## donc de le pousser DEHORS, a travers la tole. La coque le ramenait aussitot
## dedans, la grille le repoussait dehors, et il restait plante dans le panneau
## en vibrant. Mesure : 126 canettes sur 900 dans DOOR_R_Sill, et 13 % des
## lancers jamais stabilises.
##
## `bound_lo`/`bound_hi` sont les bornes de l'habitacle (cabin.gd,
## HULL_MIN/MAX) : le deplacement calcule y est rabattu axe par axe, si bien
## qu'une sortie qui traverserait la carrosserie s'arrete a la coque au lieu de
## la franchir. Les passer est facultatif — sans elles, la resolution est la
## meme, simplement sans garde-fou.
##
## Renvoie [nouveau centre, normale de sortie, touche]. Normale nulle si libre.
func push_out(centre: Vector3, half: Vector3,
		bound_lo := Vector3.ZERO, bound_hi := Vector3.ZERO) -> Array:
	var i0 := int(floor((centre.x - half.x - origin.x) / step))
	var i1 := int(floor((centre.x + half.x - origin.x) / step))
	var j0 := int(floor((centre.y - half.y - origin.y) / step))
	var j1 := int(floor((centre.y + half.y - origin.y) / step))
	var k0 := int(floor((centre.z - half.z - origin.z) / step))
	var k1 := int(floor((centre.z + half.z - origin.z) / step))

	# Ce qu'il faut parcourir dans chaque sens. L'ordre est [+x, -x, +y, -y,
	# +z, -z], et CHAQUE CASE NE VOTE QUE POUR UN SENS : le sien.
	var need := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var touched := false
	var b_lo := centre - half
	var b_hi := centre + half

	for i in range(maxi(i0, 0), mini(i1, nx - 1) + 1):
		for j in range(maxi(j0, 0), mini(j1, ny - 1) + 1):
			for k in range(maxi(k0, 0), mini(k1, nz - 1) + 1):
				if not at(i, j, k):
					continue
				var lo := origin + Vector3(float(i), float(j), float(k)) * step
				var hi := lo + Vector3(step, step, step)
				# Recouvrement reel sur les trois axes, sinon ce n'est qu'un
				# contact et il n'y a rien a sortir.
				var d := Vector3(minf(hi.x, b_hi.x) - maxf(lo.x, b_lo.x),
					minf(hi.y, b_hi.y) - maxf(lo.y, b_lo.y),
					minf(hi.z, b_hi.z) - maxf(lo.z, b_lo.z))
				if d.x <= 0.0 or d.y <= 0.0 or d.z <= 0.0:
					continue
				touched = true
				# L'axe de MOINDRE penetration de CETTE case, et le sens qui
				# eloigne l'objet de son centre.
				var a := 1
				if d.x <= d.y and d.x <= d.z:
					a = 0
				elif d.z <= d.y:
					a = 2
				# UN EFFLEUREMENT N'EST PAS UNE PENETRATION.
				#
				# Un objet pose deborde toujours un peu sur les cases voisines —
				# d'un dixieme de millimetre, parce qu'il est tombe la. Ces
				# cases-la ont leur plus petit recouvrement sur un axe HORIZONTAL,
				# et sans ce seuil elles poussaient l'objet de cote de ce dixieme
				# de millimetre, a chaque image, indefiniment. Il n'etait jamais
				# coince, mais il n'etait jamais pose non plus : il rampait. Le
				# banc l'a vu tout de suite — 32 % des lancers ne se stabilisaient
				# plus, contre 5 % avant.
				if d[a] < CONTACT:
					continue
				var away: bool = centre[a] > lo[a] + step * 0.5
				var slot := a * 2 + (0 if away else 1)
				if need[slot] < d[a]:
					need[slot] = d[a]

	if not touched:
		return [centre, Vector3.ZERO, false]

	var bounded := bound_hi != bound_lo

	# ON APPLIQUE LES TROIS AXES ENSEMBLE, PAS LE MOINS CHER.
	#
	# Le premier jet cherchait UNE translation qui degage TOUTE l'union, et c'est
	# trop fort : une canette posee sur le plancher et mordant la levre de bas de
	# caisse aurait du, pour "sortir de l'union", quitter aussi le plancher sur
	# lequel elle repose legitimement — 8 cm. Le moins couteux devenait alors de
	# GLISSER LE LONG de la levre (6,6 cm en z) sans jamais s'en degager, et elle
	# y restait plantee. Le banc l'a chiffre : 127 canettes sur 900 dans
	# DOOR_R_Sill, toutes a l'aplomb exact de la borne de coque.
	#
	# Une case est un CONTACT LOCAL : elle ne demande qu'a etre quittee par sa
	# propre face la plus proche. Le plancher demande 11 mm vers le haut, la
	# levre 20 mm de cote, et les deux ensemble reglent la question — ce
	# qu'aucune translation unique ne pouvait faire.
	#
	# Le resultat ne depend toujours pas de l'ordre des cases : on prend un
	# maximum par sens, et l'ordre d'un maximum n'existe pas.
	var move := Vector3.ZERO
	for a in 3:
		var plus: float = need[a * 2]
		var minus: float = need[a * 2 + 1]
		# Coince entre deux faces : on suit la plus profonde, la coque tranchera.
		move[a] = plus if plus >= minus else -minus
		if bounded:
			var to: float = centre[a] + move[a]
			move[a] = clampf(to, bound_lo[a] + half[a], bound_hi[a] - half[a]) - centre[a]

	if move == Vector3.ZERO:
		return [centre, Vector3.ZERO, true]
	# La normale rendue est la direction DOMINANTE : c'est elle qui decide du
	# rebond et de l'appui, et un appui vaut par sa composante verticale.
	var n := Vector3.ZERO
	var big := move.abs().max_axis_index()
	n[big] = signf(move[big])
	return [centre + move, n, true]


## ON SE POSE SUR LA TOLE, PAS SUR LE BORD DE LA CASE.
##
## Arrete par la grille, un objet repose sur le bord d'une case de 2 cm : il se
## caserait donc par crans d'un demi-centimetre et pourrait leviter de 12 mm
## au-dessus de la planche de bord. C'est exactement le defaut que
## probe_surfaces.gd avait releve sur les anciennes boites saisies a la main
## (8 a 35 mm de flottement), et il se voit du premier coup d'oeil.
##
## LE RECALAGE EST A PART DE `push_out`, ET C'EST NECESSAIRE. Pose sur la tole
## exacte, l'objet est forcement DANS la case qui contient cette tole — une case
## fait 2 cm, la tole est quelque part dedans. Le recalage et la resolution se
## contredisent donc par construction : les enchainer ferait remonter l'objet a
## la case, redescendre au triangle, remonter... c'est le tremblement qu'a releve
## le banc (9 % des lancers jamais stabilises). On resout d'abord, autant de fois
## qu'il faut, et on se pose UNE SEULE FOIS, a la fin.
##
## DEUX GARDE-FOUS, et les deux ont coute une mesure :
##
##   - TOUTES les colonnes sous l'objet doivent porter une hauteur. Une colonne
##     sans face horizontale — le flanc du tunnel, le nez de la planche, la
##     marche du plancher arriere — n'en a pas, et la moyenne des autres est
##     alors PLUS BASSE que la tole qu'elle ignore : l'objet descendait dedans.
##     C'etait 31 canettes dans BODY_Tunnel et 20 dans DASH_Body.
##   - On ne descend que d'une case au plus. Au-dela, le champ ne parle pas de
##     la meme tole que la case : sous la planche de bord il rend le dessus de
##     la planche, 60 cm au-dessus des pieds.
##
## Renvoie la cote corrigee du centre, ou `centre.y` s'il n'y a rien a corriger.
func settle(centre: Vector3, half: Vector3) -> float:
	var i0 := int(floor((centre.x - half.x - origin.x) / step))
	var i1 := int(floor((centre.x + half.x - origin.x) / step))
	var k0 := int(floor((centre.z - half.z - origin.z) / step))
	var k1 := int(floor((centre.z + half.z - origin.z) / step))
	var best := -99.0
	for i in range(maxi(i0, 0), mini(i1, nx - 1) + 1):
		for k in range(maxi(k0, 0), mini(k1, nz - 1) + 1):
			var h := top[k * nx + i]
			if h < -90.0:
				return centre.y     # une colonne sans tole : on ne touche a rien
			best = maxf(best, h)
	if best < -90.0:
		return centre.y
	var want := best + half.y
	if want > centre.y or centre.y - want > step:
		return centre.y
	return want


# --------------------------------------------------------------------------
# Visee
# --------------------------------------------------------------------------

## Premier point de la tole rencontre par le rayon, en espace voiture. Renvoie
## [touche, point, normale].
##
## AUCUN RAYON PHYSIQUE, comme avant : on marche dans la grille. La camera, les
## surfaces et les objets sont immobiles les uns par rapport aux autres dans le
## repere de la voiture, que la caisse roule a 5 ou a 170 km/h — c'est ce qui
## avait corrige "je ne peux pas saisir le paquet en roulant".
##
## Ce qui change, c'est ce qu'on peut viser : dix boites horizontales saisies a
## la main, contre la tole elle-meme. Le fond de planche cote conducteur, le
## capot des compteurs, le tunnel, les bas de caisse — tout ce qui se voit se
## vise, sans que personne ait eu a en taper les cotes.
##
## La HAUTEUR RENDUE est celle du champ, pas celle de la case : on entre par la
## case, on se pose sur le triangle.
func raycast(from: Vector3, dir: Vector3, far: float) -> Array:
	if step <= 0.0:
		return [false, Vector3.ZERO, Vector3.UP]
	var c := _cell(from)
	var i := c.x
	var j := c.y
	var k := c.z

	# Marche de Amanatides & Woo : on avance d'une case a la fois, en suivant
	# celui des trois plans qui vient en premier.
	var stepi := [signi(int(signf(dir.x))), signi(int(signf(dir.y))),
		signi(int(signf(dir.z)))]
	var t_max := [INF, INF, INF]
	var t_delta := [INF, INF, INF]
	var cell := [i, j, k]
	for a in 3:
		if absf(dir[a]) < 1e-9:
			continue
		var bound: float = origin[a] + float(cell[a] + (1 if stepi[a] > 0 else 0)) * step
		t_max[a] = (bound - from[a]) / dir[a]
		t_delta[a] = step / absf(dir[a])

	var t := 0.0
	var axis := 1
	while t <= far:
		if at(i, j, k):
			var n := Vector3.ZERO
			n[axis] = -float(stepi[axis])
			var p := from + dir * t
			# On se pose sur la tole relevee, pas sur le bord de la case.
			if axis == 1 and n.y > 0.0:
				var h := height_at(p.x, p.z)
				if h > -90.0:
					p.y = h
			return [true, p, n]
		axis = 0
		if t_max[1] < t_max[axis]:
			axis = 1
		if t_max[2] < t_max[axis]:
			axis = 2
		if stepi[axis] == 0:
			return [false, Vector3.ZERO, Vector3.UP]
		t = t_max[axis]
		t_max[axis] += t_delta[axis]
		if axis == 0:
			i += stepi[0]
		elif axis == 1:
			j += stepi[1]
		else:
			k += stepi[2]
		if not _in_range(i, j, k):
			return [false, Vector3.ZERO, Vector3.UP]
	return [false, Vector3.ZERO, Vector3.UP]


# --------------------------------------------------------------------------
# Ramper
# --------------------------------------------------------------------------

## La tole la plus proche de `p` : le point dessus, sa normale tournee vers
## l'air, la distance, et si `p` est DEDANS.
##
## Meme contrat que l'ancien `_nearest` de centipede.gd, meme ordre de priorite
## — etre dedans prime sur etre pres, parce que "ne traverse rien" est une
## contrainte et "reste pres de quelque chose" un souhait. Ce qui change est la
## matiere consultee : toutes les cases pleines du modele, au lieu d'une
## vingtaine de boites dont trois avaient ete ajoutees a la main pour lui.
##
## On cherche en couronnes croissantes autour de `p` et on s'arrete des qu'une
## couronne ne peut plus faire mieux que ce qu'on tient : le cout ne depend donc
## pas de la taille de l'habitacle mais de la distance a la tole, qui est de
## quelques millimetres puisqu'il marche dessus.
func nearest(p: Vector3, reach: float) -> Dictionary:
	var c := _cell(p)
	var best := {"q": p, "n": Vector3.UP, "d": INF, "inside": false, "from": p}
	var rings := maxi(1, int(ceil(reach / step)) + 1)

	# DEDANS D'ABORD : si la case qui le contient est pleine, il faut en sortir,
	# et on ne va pas chercher plus loin. "Etre dedans prime sur etre pres" —
	# ne traverse rien est une contrainte, reste pres est un souhait.
	if at(c.x, c.y, c.z):
		return _escape(p, c)

	for r in range(0, rings + 1):
		# Une couronne a distance r ne peut rien apporter de mieux que
		# (r - 1) * step : inutile de la parcourir.
		if best["d"] < float(r - 1) * step:
			break
		for di in range(-r, r + 1):
			for dj in range(-r, r + 1):
				for dk in range(-r, r + 1):
					# Seulement la PEAU de la couronne : l'interieur a deja ete vu.
					if maxi(absi(di), maxi(absi(dj), absi(dk))) != r:
						continue
					var i := c.x + di
					var j := c.y + dj
					var k := c.z + dk
					if not at(i, j, k):
						continue
					var box := cell_box(i, j, k)
					var q: Vector3 = p.clamp(box[0], box[1])
					var d := p.distance_to(q)
					if d >= best["d"]:
						continue
					var n := p - q
					if n.length_squared() < 1e-12:
						continue
					best = {"q": q, "n": n.normalized(), "d": d,
						"inside": false, "from": p}
	return _refine(best)


## SORTIR DE LA MATIERE, pas de la case.
##
## Le premier jet sortait de la SEULE case qui contenait le point, par sa face
## la plus proche. Deux defauts, et le banc les a montres tous les deux :
##
##   - un point pose exactement sur une face donne une distance NULLE de ce
##     cote-la, qui gagne toujours — meme si c'est un mur ;
##   - une tole fait souvent plusieurs cases d'epaisseur dans le sens ou on
##     sort, et on se retrouvait a marcher DANS la piece suivante.
##
## On balaie donc les six directions jusqu'a trouver du vide, et on retient la
## moins couteuse. Sur le dessus de la planche de bord, remonter coute une case
## et reculer en coute quatre : la reponse tombe toute seule, et c'est celle
## qu'une bestiole donnerait.
func _escape(p: Vector3, c: Vector3i) -> Dictionary:
	const DIRS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN,
		Vector3.BACK, Vector3.FORWARD]
	const AXIS := [0, 0, 1, 1, 2, 2]
	var best_d := INF
	var best_n := Vector3.UP
	for a in 6:
		var n: Vector3 = DIRS[a]
		var s := int(signf(n[AXIS[a]]))
		var i := c.x
		var j := c.y
		var k := c.z
		var walked := 0
		# Jusqu'a 12 cases : au-dela ce n'est plus une tole, c'est un bloc, et
		# la sortie est ailleurs.
		while walked < 12 and at(i, j, k):
			if AXIS[a] == 0: i += s
			elif AXIS[a] == 1: j += s
			else: k += s
			walked += 1
		if at(i, j, k):
			continue                      # ce cote-la ne debouche pas
		# La face de sortie est le bord de la derniere case pleine.
		var face: float = origin[AXIS[a]] + float(
			(i if AXIS[a] == 0 else (j if AXIS[a] == 1 else k))
			+ (0 if s > 0 else 1)) * step
		var d: float = absf(face - p[AXIS[a]])
		if d < best_d:
			best_d = d
			best_n = n
	if not is_finite(best_d):
		return {"q": p, "n": Vector3.UP, "d": 0.0, "inside": true, "from": p}
	var q := p + best_n * best_d
	return _refine({"q": q, "n": best_n, "d": best_d, "inside": true, "from": p})


## LE VOXEL DIT OU, LE CHAMP DIT A QUELLE HAUTEUR.
##
## Une case fait 2 cm : s'arreter sur son bord poserait tout ce qui se pose sur
## la planche de bord par crans d'un demi-centimetre, et un objet qui levite de
## 12 mm au-dessus de la tole se voit du premier coup d'oeil — c'est meme
## exactement le defaut que probe_surfaces.gd avait releve sur les anciennes
## boites (8 a 35 mm de flottement).
##
## Des que le contact est HORIZONTAL et tourne vers le haut, on remplace donc la
## cote de la case par celle du triangle. Sur une face verticale il n'y a rien a
## recaler : la case y est deja la bonne a 2 cm pres, et 2 cm de decalage
## LATERAL ne se lisent pas comme 2 cm de flottement.
func _refine(hit: Dictionary) -> Dictionary:
	var n: Vector3 = hit["n"]
	if n.y < 0.99:
		return hit
	var q: Vector3 = hit["q"]
	var h := height_at(q.x, q.z)
	# Le champ doit parler de la MEME tole que la case : au-dela d'une case
	# d'ecart il designe autre chose (typiquement le dessus de la planche de
	# bord quand on est dans le pedalier, 60 cm plus bas), et le suivre
	# telelporterait le contact.
	if h < -90.0 or absf(h - q.y) > step:
		return hit
	var moved := Vector3(q.x, h, q.z)
	hit["q"] = moved
	# `d` doit rester la distance a `q`, sinon clearance() et le test de portee
	# de centipede.gd parlent d'un point et mesurent l'autre.
	hit["d"] = (hit["from"] as Vector3).distance_to(moved)
	return hit
