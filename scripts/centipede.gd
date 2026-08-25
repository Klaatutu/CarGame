extends Node3D
##
## LE MILLE-PATTES — second ennemi.
##
## Le geant piétine la voiture de l'exterieur. Celui-ci fait l'inverse : il
## n'essaie pas de casser la caisse, il ENTRE dedans. Et il entre par ou l'air
## entre — les bouches d'aeration — ou par la vitre, si tu l'as laissee ouverte.
##
## C'est ce qui en fait un ennemi et pas un decor : la voiture est le seul abri
## du jeu, et lui la traverse comme si elle n'en etait pas un.
##
## IL NE TOMBE PAS, IL MARCHE.
## -------------------------------------------------------------------------
## prop.gd simule des objets qui TOMBENT : gravite, frottement de Coulomb,
## rebond. Rien de tout ca ne s'applique ici. Une bestiole ne se pose pas sur
## une surface, elle s'y ACCROCHE — elle monte le montant, traverse le pavillon
## et redescend le pare-brise sans qu'aucune de ces trois choses ne soit "un
## sol". Le mille-pattes ne partage donc pas la simulation des objets ; il
## partage sa GEOMETRIE, ce qui est le seul point commun qu'il y ait vraiment.
##
## Sa marche tient en quatre lignes, repetees chaque image :
##
##   1. il avance selon `_dir`, tangent a la surface ou il est ;
##   2. on tire le point d'arrivee de GRIP vers l'interieur de la surface ;
##   3. on le RECOLLE a la surface la plus proche de l'habitacle (`_stick`) ;
##   4. `_dir` est reprojete dans le plan tangent de la nouvelle normale.
##
## L'etape 2 est celle qui fait tout. Sans elle, arrive au bord de la planche de
## bord, le mille-pattes continuerait tout droit dans le vide ; avec elle il se
## retrouve UN MILLIMETRE SOUS la tole, `_stick` le ressort par la face la plus
## proche — qui n'est plus le dessus mais le nez de la planche — et il bascule
## par-dessus l'arete pour continuer sur la face verticale. Passer un angle
## saillant n'est donc pas un cas particulier a coder : c'est ce que fait la
## regle generale, et c'est aussi ce que fait une vraie bestiole, qui ne
## "decide" pas de passer un angle, elle ne lache simplement jamais prise.
##
## Aucune topologie, aucun graphe de navigation, aucune arete a recoudre : la
## question "ou est la surface ?" est reposee de zero a chaque image sur une
## vingtaine de boites. Ajouter du mobilier a l'habitacle lui donne de nouveaux
## chemins sans qu'on ait rien a rebrancher.
##
## IL COURT PUIS IL SE FIGE.
## -------------------------------------------------------------------------
## A vitesse constante, ca ne se lit pas comme un insecte, ca se lit comme un
## petit train. Un mille-pattes va par a-coups : il detale, il s'arrete net, il
## repart. D'ou l'alternance `RUN` / `FREEZE`, et surtout : LES PATTES SONT
## ANIMEES PAR LA DISTANCE PARCOURUE, pas par le temps. Fige, il ne pedale donc
## pas dans le vide — seules les antennes continuent de fouiller, parce qu'une
## bestiole arretee n'est pas une bestiole eteinte.
##
## Et quand tu plantes les freins, il se plaque et s'arrete : `carrier.frame_accel`
## est deja publiee par car.gd pour les objets, elle sert ici a une bestiole qui
## s'agrippe. Il ne glisse pas, lui — s'agripper est tout son metier.
##

const Retro := preload("res://scripts/retro.gd")

enum {WAITING, ENTERING, ROAMING}

# --- corps ------------------------------------------------------------------

## Nombre d'anneaux, tete comprise.
const SEGMENTS := 15
## Espacement des anneaux le long du corps.
const SEG_SPACING := 0.019
## Longueur totale : 26,6 cm. Une Scolopendra gigantea en fait 30 — assez gros
## pour qu'on le voie du siege, assez petit pour passer par une grille.
const BODY_LEN := float(SEGMENTS - 1) * SEG_SPACING
const BODY_W := 0.022
## EPAISSEUR DU CORPS — 6 mm, et ce chiffre est MESURE, pas choisi.
##
## tools/probe_vents.gd releve les lames des aerateurs a 10,3 mm d'entraxe pour
## 4 mm d'epaisseur : il reste 6,3 mm entre deux lames. C'est par la qu'il
## passe, donc c'est ce qu'il mesure. Un mille-pattes est plat pour exactement
## cette raison — c'est ce qui lui permet de vivre sous les pierres, et ici
## d'etre dans la voiture avant toi.
const BODY_T := 0.006
const HEAD_W := 0.027
const HEAD_L := 0.021
## Hauteur du ventre au-dessus de la surface : il est porte par ses pattes.
const RIDE := 0.005
const LEG_LEN := 0.028
const LEG_THICK := 0.0024
## Ouverture de la CUISSE sous l'horizontale, et angle du GENOU par-dessus.
##
## Une patte droite ne se lit pas comme une patte : ca fait un peigne, et c'est
## ce que donnait la premiere version. Coudee, elle se lit du premier coup
## d'oeil — c'est le seul detail qui separe l'animal du rateau.
##
## Les deux angles sont pris pour que la POINTE touche : cuisse presque a plat
## (17,4 mm a 0,10 rad, soit 1,7 mm de chute), tarse plongeant a 0,52 rad sur
## 14 mm, soit 7,0 mm en tout — le ventre etant a 5, la pointe mord la tole de
## 2 mm et l'animal a l'air de s'y tenir. Des pattes plus plongeantes
## donneraient une araignee sur echasses, pas un mille-pattes, qui rampe a plat.
const LEG_DROOP := 0.10
const LEG_KNEE := 0.42
## Part de la patte qui revient a la cuisse ; le reste est le tarse.
const LEG_THIGH := 0.62
const ANTENNA_LEN := 0.032

# --- marche -----------------------------------------------------------------

## Vitesse de pointe, en m/s. Une scolopendre fait 0,5 : c'est vif, et c'est
## precisement ce qui rend la chose desagreable dans un espace de 2 m.
const RUN_SPEED := 0.42
const TURN_RATE := 5.0
## De combien on tire le point d'arrivee SOUS la surface avant de le recoller.
## C'est ce qui fait passer les angles saillants (voir l'en-tete).
const GRIP := 0.004
## Au-dela, on considere qu'il n'y a plus de surface a portee : il est en l'air.
const REACH := 0.12
## De combien un recollage peut deplacer la tete AU-DELA du pas qu'elle vient de
## faire. Voir _advance : une bestiole ne se teleporte pas.
const MAX_SNAP := 0.012
## De combien la tete doit avoir franchi la bouche avant de chercher a se
## raccrocher. 2 cm : de quoi degager le cadre de la grille et l'epaisseur de la
## garniture, pas assez pour qu'on voie un saut en se reposant.
const MOUTH_CLEAR := 0.02

const RUN_MIN := 0.45
const RUN_MAX := 1.5
const FREEZE_MIN := 0.20
const FREEZE_MAX := 1.4
## Acceleration de la voiture au-dela de laquelle il se plaque et attend.
## Le freinage pedale vaut 17 m/s^2, un virage a fond 8 : il se cramponne sur
## les gros coups de frein et ignore la conduite ordinaire.
const BRACE_ACCEL := 12.0

## Pas d'echantillonnage de la trace laissee par la tete.
const TRAIL_STEP := 0.006
const TRAIL_MAX := 160

## Distance a laquelle une etape est consideree atteinte.
const GOAL_REACHED := 0.07
## Au bout de ce temps sur la meme etape, on en change : jamais coince.
const GOAL_TIMEOUT := 9.0

## Ses coins de predilection, en espace voiture, avec leur poids. Ce ne sont pas
## des cases d'un quadrillage : c'est une liste de PLACES, et un mille-pattes va
## d'une place a une autre. Le poids penche vers le conducteur — un ennemi qui
## passerait sa vie sur la banquette arriere n'en serait pas un.
const HAUNTS := [
	[Vector3(-0.33, 0.52, 0.24), 3.0],    # assise conducteur
	[Vector3(-0.40, 0.37, 0.30), 3.0],    # plancher conducteur
	[Vector3(-0.70, 0.70, -0.10), 2.5],   # contre-porte conducteur
	[Vector3(0.0, 0.62, -0.24), 2.0],     # console
	[Vector3(0.0, 0.96, -0.80), 2.0],     # dessus de planche de bord
	[Vector3(0.0, 0.75, -0.55), 2.0],     # face de planche de bord
	[Vector3(0.0, 1.12, -0.60), 1.5],     # milieu du pare-brise
	[Vector3(0.33, 0.52, 0.24), 1.2],     # assise passager
	[Vector3(0.40, 0.37, 0.30), 1.2],     # plancher passager
	[Vector3(0.70, 0.70, -0.10), 1.0],    # contre-porte passager
	[Vector3(0.0, 1.28, 0.10), 1.0],      # ciel de toit, au-dessus des tetes
	[Vector3(0.0, 0.52, 1.00), 0.8],      # banquette arriere
]

## Delai avant la premiere entree, en secondes de jeu. Il ne doit pas etre la au
## demarrage : ce qu'on veut, c'est qu'il ARRIVE, et on n'assiste pas a une
## arrivee dont on n'a pas connu l'absence.
@export var first_delay := 14.0
## Vitre entrouverte d'au moins ca (0-1) : elle devient une entree. 0,03 fait
## 8 mm de jeu au-dessus de la glace, soit un peu plus que son epaisseur.
@export var window_min_open := 0.03
## Poids d'une vitre ouverte face a une bouche d'aeration. Une vitre baissee est
## une porte grande ouverte a cote d'une chatiere : elle doit peser plus lourd
## que les huit grilles reunies, sinon la laisser ouverte ne se paie pas.
@export var window_weight := 14.0

var carrier                        # la voiture, pour frame_accel
var cabin                          # pour ses boites et ses bouches

var state := WAITING
## Par ou il est entre, pour le HUD et les bancs d'essai.
var entry_label := ""
## Position et normale de la tete, en espace voiture.
var head_pos := Vector3.ZERO
var head_nrm := Vector3.UP
## Distance totale parcourue, en metres. C'est elle qui anime les pattes.
var walked := 0.0

var rng := RandomNumberGenerator.new()

var _dir := Vector3.FORWARD
var _goal := Vector3.ZERO
var _goal_age := 0.0
var _wait := 0.0
var _running := true
var _phase := 0.0
var _emerged := 0.0
var _trail_pos: Array[Vector3] = []
var _trail_nrm: Array[Vector3] = []
var _segments: Array[Node3D] = []
var _legs: Array = []              # [[gauche, droite], ...] par anneau
var _antennae: Array[Node3D] = []
var _crawl: Array = []             # boites sur lesquelles il marche


func _ready() -> void:
	_build_body()
	visible = false
	_wait = first_delay


# ---------------------------------------------------------------------------
# Marche
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if cabin == null or delta <= 0.0:
		return
	if _crawl.is_empty():
		_crawl = cabin.solids + cabin.crawl_solids

	match state:
		WAITING:
			_wait -= delta
			if _wait <= 0.0:
				_choose_entry()
		ENTERING:
			# PAS d'accrochage pendant l'emergence : ce qui le guide, c'est le
			# TROU, pas la tole. Le recoller ici le collerait a la premiere face
			# venue — et pour une vitre, cette face est la garniture DANS
			# laquelle il se trouve encore : il repartirait vers le vide de la
			# portiere au lieu d'entrer dans la voiture.
			_advance(delta, _emerge_step(delta), false)
		ROAMING:
			_advance(delta, _roam_step(delta), true)

	if state != WAITING:
		_place_segments()


## Combien de metres la tete franchit cette image pendant l'emergence.
##
## Il sort tout droit, et il ne rend la main que quand il est VRAIMENT dehors :
## degage de la bouche (MOUTH_CLEAR), hors de toute boite, et avec de quoi se
## raccrocher a portee. Les trois conditions comptent, et chacune a coute une
## bestiole quelque part — celle qui se recollait sous la planche de bord, celle
## qui repartait dans la portiere, celle qui restait pendue en l'air.
func _emerge_step(delta: float) -> float:
	var step := RUN_SPEED * 0.55 * delta
	_emerged += step
	var hit := _nearest(head_pos)
	if _emerged > MOUTH_CLEAR and not hit["inside"] and hit["d"] < REACH:
		_land()
	elif _emerged > BODY_LEN * 4.0:
		# Filet : une bouche mal placee ne doit pas produire une bestiole qui
		# s'en va tout droit a l'infini.
		_land()
	return step


func _land() -> void:
	state = ROAMING
	_pick_goal()


## Idem en promenade : cap vers l'etape en cours, avec la respiration
## course/arret. Rendre 0 fige le corps ET les pattes, puisque celles-ci sont
## animees par la distance.
func _roam_step(delta: float) -> float:
	_goal_age += delta
	if head_pos.distance_to(_goal) < GOAL_REACHED or _goal_age > GOAL_TIMEOUT:
		_pick_goal()

	# Coup de frein : il se cramponne. Ce n'est pas un glissement (il ne glisse
	# pas), c'est une bestiole qui attend que ca passe.
	if carrier != null and carrier.frame_accel.length() > BRACE_ACCEL:
		_running = false
		_wait = maxf(_wait, 0.25)

	_wait -= delta
	if _wait <= 0.0:
		_running = not _running
		_wait = rng.randf_range(RUN_MIN, RUN_MAX) if _running \
			else rng.randf_range(FREEZE_MIN, FREEZE_MAX)
	if not _running:
		return 0.0

	# Cap : la composante de "vers l'etape" qui vit dans le plan tangent. Un but
	# situe droit au-dessus de lui (donc sans composante tangente) ne dit rien
	# sur la direction a prendre — on garde alors celle qu'on avait.
	var want := _goal - head_pos
	want -= head_nrm * want.dot(head_nrm)
	if want.length_squared() > 0.000001:
		var to := want.normalized()
		var t := clampf(TURN_RATE * delta, 0.0, 1.0)
		_dir = (_dir.lerp(to, t)).normalized()
	return RUN_SPEED * delta


## Les quatre lignes de l'en-tete : avancer, mordre, recoller, reprojeter.
func _advance(delta: float, step: float, stick: bool) -> void:
	if step <= 0.0:
		_animate(delta)
		return

	var from := head_pos
	var probe := head_pos + _dir * step - head_nrm * GRIP
	var hit := _nearest(probe)
	if stick and hit["d"] < REACH:
		head_pos = hit["q"] + (hit["n"] as Vector3) * RIDE
		head_nrm = hit["n"]
	else:
		# Rien a portee, ou bien il traverse encore son trou : il continue tout
		# droit plutot que de se teleporter sur la paroi la plus proche.
		head_pos = probe + head_nrm * GRIP

	# UNE BESTIOLE NE SE TELEPORTE PAS. La ou deux boites se recouvrent, "la
	# surface la plus proche" peut changer de face d'une image a l'autre, et le
	# recollage ferait alors sauter la tete de plusieurs centimetres — ce qui se
	# voit, et ce qui creuse un trou dans la trace ou les anneaux s'ecartent. On
	# borne donc son deplacement au pas qu'elle vient de faire ; s'il reste du
	# chemin, elle le fera a l'image suivante. C'est une relaxation, pas une
	# contrainte : elle converge en deux ou trois images.
	head_pos = from + (head_pos - from).limit_length(step + MAX_SNAP)
	if stick:
		_contain()

	_dir -= head_nrm * _dir.dot(head_nrm)
	if _dir.length_squared() < 0.000001:
		_dir = _any_tangent(head_nrm)
	_dir = _dir.normalized()

	walked += step
	_push_trail()
	_animate(delta)


## Surface la plus proche de `p` : le point `q` dessus, sa normale `n` tournee
## vers l'air, et la distance `d`.
##
## Deux familles, et elles se mesurent de la meme facon pour pouvoir se
## departager d'un seul comparatif :
##
##   - LE MOBILIER (`solids` + `crawl_solids`) — il marche DESSUS, la normale
##     sort de la boite. Un point deja dedans compte comme une distance egale a
##     sa penetration, ce qui fait gagner la boite dans laquelle il est le moins
##     enfonce : il reste ainsi sur la peau exterieure quand deux boites se
##     recouvrent.
##   - LA COQUE (`HULL_MIN/MAX`) — il marche DEDANS, la normale rentre. C'est ce
##     qui lui donne le pavillon et la lunette arriere sans avoir a les declarer
##     deux fois.
## LA COQUE BORNE LA TETE, elle ne la repousse pas.
##
## C'est exactement l'argument de prop.gd : le mobilier pousse DEHORS, la coque
## retient DEDANS, et une borne par axe ne peut pas fuir — il n'y a pas de
## recouvrement a detecter, donc ni angle ni vitesse qui la prenne en defaut.
##
## Sans elle, il suffit de faire le tour d'une paroi pour se retrouver a marcher
## sur la carrosserie, vu de l'exterieur : les portieres, le pavillon et le fond
## de coffre ont tous une face qui DEBORDE de la coque, et rien dans "va vers la
## surface la plus proche" ne distingue le bon cote d'une tole du mauvais. Le
## banc l'a relevee a 41 mm dehors.
##
## Les bornes sont rentrees de RIDE, ce qui les met exactement la ou le ventre
## se pose quand il marche sur une face de la coque : le plancher, le pavillon
## et la lunette arriere ne sont declares nulle part ailleurs, et il y marche
## sans que la coque et le recollage se contredisent d'un millimetre.
func _contain() -> void:
	var lo: Vector3 = cabin.HULL_MIN + Vector3(RIDE, RIDE, RIDE)
	var hi: Vector3 = cabin.HULL_MAX - Vector3(RIDE, RIDE, RIDE)
	for a in 3:
		var over := 0.0
		var sign := 0.0
		if head_pos[a] < lo[a]:
			over = lo[a] - head_pos[a]
			head_pos[a] = lo[a]
			sign = 1.0
		elif head_pos[a] > hi[a]:
			over = head_pos[a] - hi[a]
			head_pos[a] = hi[a]
			sign = -1.0
		# La normale ne bascule que sur un VRAI depassement. A l'exact
		# millimetre pres, marcher sur le plancher touche la borne a chaque
		# image : la reecrire la ferait vibrer pour rien.
		if over > 0.001:
			var n := Vector3.ZERO
			n[a] = sign
			head_nrm = n


## `inside` dit qu'il est DANS une boite : pendant l'emergence c'est ce qui
## distingue "sorti dans l'habitacle" de "encore dans l'epaisseur de la
## garniture", et les deux donnent la meme petite distance.
## ETRE DEDANS PRIME SUR ETRE PRES, et ce n'est pas un detail de tri.
##
## Les deux se mesurent en metres et se comparaient donc sur le meme pied. Le
## banc a montre ou ca menait : sous la banquette arriere, le plancher est a
## 5 mm sous le ventre tandis que le coussin, lui, englobe la bestiole sur
## 13 cm — la face du plancher gagnait, et elle marchait ENTERREE DANS LE
## SIEGE, tranquillement, sur toute la longueur de l'habitacle.
##
## L'ordre correct n'est pas une question de distance mais de nature : "ne
## traverse rien" est une contrainte, "reste pres de quelque chose" est un
## souhait. On sort donc d'abord de ce dans quoi on est — par la face la plus
## proche, la moins spectaculaire — et on ne cherche la surface voisine que
## quand on n'est plus dans rien. Le mille-pattes GRIMPE alors sur la banquette
## au lieu d'y disparaitre, sans qu'on ait eu a lui parler de banquette.
##
## (Les boites de `solids` sont EPAISSES VERS LE BAS a dessein, cf. cabin.gd :
## elles se recouvrent donc par le bas, et c'est justement pour ca qu'on sort
## par la face la plus proche et pas par le haut.)
func _nearest(p: Vector3) -> Dictionary:
	var best := {"q": p, "n": head_nrm, "d": INF, "inside": false}
	var deep := {"q": p, "n": head_nrm, "d": INF, "inside": true}
	var buried := false

	for s in _crawl:
		var lo: Vector3 = s["min"]
		var hi: Vector3 = s["max"]
		var q := p.clamp(lo, hi)
		var d := p.distance_to(q)
		var n: Vector3
		var inside := false
		if d > 0.000001:
			n = (p - q) / d
		else:
			inside = true
			# Dedans : on ressort par la face la plus proche, comme prop.gd.
			var out_x := hi.x - p.x if hi.x - p.x < p.x - lo.x else lo.x - p.x
			var out_y := hi.y - p.y if hi.y - p.y < p.y - lo.y else lo.y - p.y
			var out_z := hi.z - p.z if hi.z - p.z < p.z - lo.z else lo.z - p.z
			if absf(out_y) <= absf(out_x) and absf(out_y) <= absf(out_z):
				d = absf(out_y)
				n = Vector3(0.0, signf(out_y), 0.0)
			elif absf(out_x) <= absf(out_z):
				d = absf(out_x)
				n = Vector3(signf(out_x), 0.0, 0.0)
			else:
				d = absf(out_z)
				n = Vector3(0.0, 0.0, signf(out_z))
			q = p + n * d
		if inside:
			buried = true
			if d < deep["d"]:
				deep = {"q": q, "n": n, "d": d, "inside": true}
		elif d < best["d"]:
			best = {"q": q, "n": n, "d": d, "inside": false}

	if buried:
		return deep

	# La coque ne concourt que si on n'est dans rien : elle n'est pas un solide,
	# c'est une borne, et _contain() s'en charge par ailleurs.
	var lo_h: Vector3 = cabin.HULL_MIN
	var hi_h: Vector3 = cabin.HULL_MAX
	for a in 3:
		for face in [[lo_h[a], 1.0], [hi_h[a], -1.0]]:
			var d: float = absf(p[a] - face[0])
			if d >= best["d"]:
				continue
			var n := Vector3.ZERO
			n[a] = face[1]
			var q := p
			q[a] = face[0]
			best = {"q": q, "n": n, "d": d, "inside": false}

	return best


## Tangente a `n` la plus proche de la VERTICALE. "N'importe laquelle" ferait
## l'affaire pour la geometrie, mais pas a l'oeil : sortant d'un aerateur qui
## souffle a l'horizontale, une tangente prise au hasard le fait emerger couche
## sur le flanc. Celle-ci le sort ventre en bas.
func _any_tangent(n: Vector3) -> Vector3:
	var t := Vector3.UP - n * Vector3.UP.dot(n)
	if t.length_squared() < 0.000001:
		t = Vector3.FORWARD - n * Vector3.FORWARD.dot(n)
	return t.normalized()


func _pick_goal() -> void:
	var total := 0.0
	for h in HAUNTS:
		total += h[1]
	var pick := rng.randf() * total
	for h in HAUNTS:
		pick -= h[1]
		if pick <= 0.0:
			# Un peu de jeu autour de la place : il ne revient jamais poser la
			# tete au meme centimetre, ce qui se remarquerait des la deuxieme
			# visite.
			_goal = (h[0] as Vector3) + Vector3(
				rng.randf_range(-0.08, 0.08), rng.randf_range(-0.05, 0.05),
				rng.randf_range(-0.10, 0.10))
			break
	_goal_age = 0.0


# ---------------------------------------------------------------------------
# Entrer
# ---------------------------------------------------------------------------

## Choisit une ouverture et s'y engage.
##
## LA REGLE DU JEU EST LA : les bouches d'aeration sont TOUJOURS ouvertes — une
## voiture ne se ferme pas de ce cote-la — tandis qu'une vitre n'est une entree
## que si tu l'as baissee. Rouler vitres fermees ne le tient donc pas dehors, ca
## le force seulement a prendre le chemin long. C'est une contrepartie de plus a
## la vitre ouverte, comme le plafonnier en est une a y voir clair.
func _choose_entry() -> void:
	var options: Array = []
	for v in cabin.vents:
		options.append([v, 1.0])
	for w in cabin.windows:
		if w.open >= window_min_open:
			options.append([_window_entry(w), window_weight])
	if options.is_empty():
		_wait = 1.0                    # aucune ouverture : il repassera
		return

	var total := 0.0
	for o in options:
		total += o[1]
	var pick := rng.randf() * total
	var chosen: Dictionary = options[0][0]
	for o in options:
		pick -= o[1]
		if pick <= 0.0:
			chosen = o[0]
			break

	# Une fente n'a pas qu'un milieu. Le degivrage fait 1,10 m de large : en
	# sortir toujours au meme point serait une porte, pas une grille. cabin.gd
	# donne l'etendue de la fente, epaisseur retiree, il ne reste qu'a tirer
	# dedans — sans aller jusqu'aux bords, ou il chevaucherait le cadre.
	if chosen.has("span"):
		chosen = chosen.duplicate()
		var span: Vector3 = chosen["span"]
		chosen["pos"] = (chosen["pos"] as Vector3) + Vector3(
			span.x * rng.randf_range(-0.8, 0.8),
			span.y * rng.randf_range(-0.8, 0.8),
			span.z * rng.randf_range(-0.8, 0.8))
	enter_by(chosen)


## L'ouverture au-dessus d'une glace descendue : le bord superieur de la vitre,
## contre la face interne de la portiere.
##
## La hauteur est LUE sur la glace, pas ecrite ici : window.gd descend le pivot
## de `travel * open`, donc le haut de la vitre est a `glass_box.end.y` moins
## cette course. Le jour au-dessus s'ouvre au fur et a mesure, et l'entree monte
## avec la ceinture de caisse si le modele change.
func _window_entry(w) -> Dictionary:
	var top: float = w.glass_box.end.y - w.travel * w.open
	var x: float = signf(w.side) * (cabin.HULL_MAX.x - 0.01)
	return {
		"label": "vitre %s" % ("conducteur" if w.side < 0.0 else "passager"),
		"pos": Vector3(x, top + 0.004, w.glass_box.get_center().z),
		# Il bascule par-dessus l'arete et descend a l'INTERIEUR de la portiere.
		"dir": Vector3(-signf(w.side), -0.35, 0.0).normalized(),
	}


## S'engage dans une ouverture donnee. La TRACE est semee a l'avance, droite,
## en arriere dans le conduit : c'est ce qui fait que les anneaux SORTENT DU
## TROU un par un au lieu d'apparaitre tous ensemble a l'air libre. Le corps
## etait deja la, on ne le voyait pas.
func enter_by(entry: Dictionary) -> void:
	entry_label = entry["label"]
	head_pos = entry["pos"]
	_dir = (entry["dir"] as Vector3).normalized()
	head_nrm = _any_tangent(_dir)
	_emerged = 0.0
	walked = 0.0
	_trail_pos.clear()
	_trail_nrm.clear()
	var n := int(ceil(BODY_LEN / TRAIL_STEP)) + 4
	for i in n:
		_trail_pos.append(head_pos - _dir * (float(i) * TRAIL_STEP))
		_trail_nrm.append(head_nrm)
	state = ENTERING
	visible = true
	_running = true
	_wait = 0.0
	_place_segments()


## Le fait entrer tout de suite, sans attendre `first_delay` : les bancs d'essai
## n'ont pas quatorze secondes a perdre.
func enter_now() -> void:
	if state == WAITING:
		_choose_entry()


## Le remet dehors, comme s'il n'etait jamais entre. Le banc d'essai tire deux
## cents entrees d'affilee pour relever par ou il passe : sans ca il faudrait
## deux cents habitacles.
func rewind() -> void:
	state = WAITING
	visible = false
	entry_label = ""
	walked = 0.0
	_wait = 0.0


# ---------------------------------------------------------------------------
# Corps
# ---------------------------------------------------------------------------

## LE CORPS SUIT UN CHEMIN, PAS UNE SUITE D'IMAGES.
##
## Semer un echantillon par image marche tant que la tete avance de moins d'un
## pas ; le jour ou elle en franchit trois d'un coup — un recollage, une image
## longue — la trace garde un trou, les anneaux qui y tombent s'ecartent, et le
## corps s'etire au lieu de suivre. Le banc l'a vu : 28 mm entre deux anneaux
## espaces de 19. On seme donc les echantillons MANQUANTS, pas seulement le
## dernier.
func _push_trail() -> void:
	if _trail_pos.is_empty():
		_trail_pos.push_front(head_pos)
		_trail_nrm.push_front(head_nrm)
		return
	var last: Vector3 = _trail_pos[0]
	var last_n: Vector3 = _trail_nrm[0]
	var d := head_pos.distance_to(last)
	if d < TRAIL_STEP:
		return

	var n := clampi(int(d / TRAIL_STEP), 1, 12)
	for i in range(1, n + 1):
		var f := float(i) / float(n)
		var nrm := last_n.lerp(head_nrm, f)
		_trail_pos.push_front(last.lerp(head_pos, f))
		_trail_nrm.push_front(head_nrm if nrm.length_squared() < 0.000001 \
			else nrm.normalized())
	if _trail_pos.size() > TRAIL_MAX:
		_trail_pos.resize(TRAIL_MAX)
		_trail_nrm.resize(TRAIL_MAX)


## Chaque anneau se pose sur la trace, a sa distance de la tete. Le corps epouse
## donc la surface derriere lui — il se plie sur l'arete de la planche de bord
## pendant que la tete est deja sur la face verticale, ce qu'aucune chaine de
## ressorts ne donnerait aussi simplement.
func _place_segments() -> void:
	var last := _trail_pos.size() - 1
	# On avance dans la trace en cumulant sa LONGUEUR, pas ses indices. C'est ce
	# qui rend l'espacement des anneaux exact quel que soit le pas des
	# echantillons — et ce pas n'est PAS regulier : la tete parcourt 7 mm dans
	# une image, 12 dans la suivante. Compter en indices revenait a supposer le
	# contraire, et le banc a mesure 27 mm entre deux anneaux espaces de 19.
	# `want` ne fait que croitre, la remontee coute donc un seul parcours.
	var k := 0
	var acc := 0.0
	for i in _segments.size():
		var want := float(i) * SEG_SPACING
		var span := 0.0
		while k < last:
			span = _trail_pos[k].distance_to(_trail_pos[k + 1])
			if acc + span >= want or span <= 0.0:
				break
			acc += span
			k += 1
		var k2 := mini(k + 1, last)
		var f := clampf((want - acc) / span, 0.0, 1.0) if span > 0.000001 else 0.0
		var p: Vector3 = _trail_pos[k].lerp(_trail_pos[k2], f)
		var up: Vector3 = _trail_nrm[k].lerp(_trail_nrm[k2], f)
		if up.length_squared() < 0.000001:
			up = Vector3.UP
		up = up.normalized()

		# Tangente locale : de l'echantillon suivant vers le precedent, donc vers
		# l'avant. Sur le premier anneau il n'y a pas de precedent, on prend la
		# direction de la tete.
		var fwd: Vector3 = _dir if k == 0 else (_trail_pos[maxi(k - 1, 0)] - _trail_pos[k2])
		fwd -= up * fwd.dot(up)
		if fwd.length_squared() < 0.000001:
			fwd = _any_tangent(up)
		fwd = fwd.normalized()

		var right := up.cross(fwd).normalized()
		var seg := _segments[i]
		seg.transform = Transform3D(Basis(right, up, -fwd), p)

		# Ondulation metachronale : une VAGUE qui descend le corps, pas des
		# pattes qui battent ensemble. C'est la seule chose qui distingue un
		# mille-pattes d'un mille-pattes en plastique.
		var ph := _phase - float(i) * 0.85
		var pair: Array = _legs[i]
		(pair[0] as Node3D).rotation = Vector3(0.0, sin(ph) * 0.55, LEG_DROOP)
		(pair[1] as Node3D).rotation = Vector3(0.0, sin(ph + PI) * 0.55, -LEG_DROOP)


## Les pattes suivent la DISTANCE, les antennes suivent le TEMPS.
##
## Fige, il ne pedale donc pas dans le vide — c'est le defaut classique, et il
## saute aux yeux — mais il continue de fouiller l'air devant lui, ce que fait
## une bestiole arretee.
func _animate(_delta: float) -> void:
	_phase = walked / SEG_SPACING * 1.6
	var t := Time.get_ticks_msec() * 0.001
	for i in _antennae.size():
		var side := 1.0 if i == 0 else -1.0
		(_antennae[i] as Node3D).rotation = Vector3(
			sin(t * 5.5 + side) * 0.22,
			side * 0.45 + sin(t * 4.1 + side * 2.0) * 0.30, 0.0)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

## CHITINE ROUSSE ET VERNIE, et il a fallu la remonter deux fois.
##
## Elle etait d'abord aussi sombre que la planche de bord — 0,06 d'albedo, la
## meme valeur que le plastique une fois rabattu sur la palette de nuit
## (cabin.gd, INTERIOR_DIM). Resultat en capture : une bestiole de 27 cm posee
## en plein sur le tableau de bord, et on ne la voyait pas. Un ennemi qu'on ne
## voit pas n'en est pas encore un.
##
## Elle est donc quatre fois plus claire que la tole, et rousse la ou tout
## l'habitacle est gris : ce sont les deux ecarts qui la detachent, et une
## scolopendre est reellement de cette couleur-la. Les pattes, plus ambrees
## encore, dessinent la frange qui fait lire l'animal.
##
## Le VERNI compte autant que la couleur. Rugosite 0,32 et un peu de metallicite
## font de la chitine un objet qui accroche des speculaires — la lueur des
## compteurs, le retour des phares sur le pare-brise, le plafonnier — la ou le
## plastique mat de la planche (0,94) ne renvoie rien. C'est ce qui la trahit
## quand elle bouge, et c'est exactement ce que fait un insecte a la lumiere.
func _build_body() -> void:
	var shell := Retro.mat(Color(0.26, 0.115, 0.048), 0.32, 0.22)
	var limb := Retro.mat(Color(0.46, 0.26, 0.075), 0.48, 0.05)

	for i in SEGMENTS:
		var seg := Node3D.new()
		seg.name = "Seg%02d" % i
		add_child(seg)
		_segments.append(seg)

		var head := i == 0
		# Le corps s'affine vers la queue : les trois derniers anneaux passent de
		# pleine largeur a 45 %. Un tube d'epaisseur constante se lit comme un
		# cable, pas comme un animal.
		var taper := 1.0 - 0.55 * clampf(
			(float(i) - float(SEGMENTS - 4)) / 3.0, 0.0, 1.0)
		var w := HEAD_W if head else BODY_W * taper
		# PLUS COURT QUE L'ESPACEMENT, pour qu'il reste 3 mm entre deux anneaux.
		# A 1,25 fois l'espacement ils se recouvraient et le corps se lisait comme
		# un ruban : c'est la SEGMENTATION qui fait le myriapode, pas la longueur.
		var l := HEAD_L if head else SEG_SPACING * 0.84

		var mesh := BoxMesh.new()
		mesh.size = Vector3(w, BODY_T, l)
		var mi := MeshInstance3D.new()
		mi.name = "Shell"
		mi.mesh = mesh
		mi.material_override = shell
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.add_child(mi)

		var pair: Array = []
		for s in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.name = "Leg%s" % ("L" if s < 0.0 else "R")
			pivot.position = Vector3(s * w * 0.45, 0.0, 0.0)
			seg.add_child(pivot)
			pivot.add_child(_limb(limb, s))
			pair.append(pivot)
		_legs.append(pair)

		if head:
			for s in [-1.0, 1.0]:
				var pivot := Node3D.new()
				pivot.name = "Antenna%s" % ("L" if s < 0.0 else "R")
				pivot.position = Vector3(s * HEAD_W * 0.3, 0.0, -HEAD_L * 0.5)
				seg.add_child(pivot)
				var ant := MeshInstance3D.new()
				var am := BoxMesh.new()
				am.size = Vector3(LEG_THICK * 0.8, LEG_THICK * 0.8, ANTENNA_LEN)
				ant.mesh = am
				ant.position = Vector3(0.0, 0.0, -ANTENNA_LEN * 0.5)
				ant.material_override = limb
				ant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pivot.add_child(ant)
				_antennae.append(pivot)


## Une patte : cuisse presque a plat, puis tarse coude vers le sol. Le tarse est
## ENFANT de la cuisse, donc il suit la foulee sans qu'on ait a l'animer : une
## seule rotation par patte, comme avant, pour deux fois plus de lisibilite.
func _limb(mat: Material, s: float) -> Node3D:
	var thigh := MeshInstance3D.new()
	thigh.name = "Thigh"
	var tm := BoxMesh.new()
	tm.size = Vector3(LEG_LEN * LEG_THIGH, LEG_THICK, LEG_THICK)
	thigh.mesh = tm
	thigh.position = Vector3(s * LEG_LEN * LEG_THIGH * 0.5, 0.0, 0.0)
	thigh.material_override = mat
	thigh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var knee := Node3D.new()
	knee.name = "Knee"
	# Au BOUT de la cuisse, exprime dans le repere de la cuisse elle-meme.
	knee.position = Vector3(s * LEG_LEN * LEG_THIGH * 0.5, 0.0, 0.0)
	knee.rotation.z = -s * LEG_KNEE
	thigh.add_child(knee)

	var toe := MeshInstance3D.new()
	toe.name = "Tarsus"
	var sm := BoxMesh.new()
	sm.size = Vector3(LEG_LEN * (1.0 - LEG_THIGH), LEG_THICK * 0.75, LEG_THICK * 0.75)
	toe.mesh = sm
	toe.position = Vector3(s * LEG_LEN * (1.0 - LEG_THIGH) * 0.5, 0.0, 0.0)
	toe.material_override = mat
	toe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	knee.add_child(toe)
	return thigh


# ---------------------------------------------------------------------------
# Ce que les bancs d'essai regardent
# ---------------------------------------------------------------------------

## Ecart entre le ventre et la surface la plus proche. Doit valoir RIDE : au-dela
## il vole, en dessous il est dans la tole.
func clearance() -> float:
	return _nearest(head_pos)["d"]


## Position monde de la tete, pour viser ou pour cadrer une capture.
func head_point() -> Vector3:
	return global_transform * head_pos


## Position en espace voiture de chaque anneau : de quoi verifier que le corps
## ne se decoud pas.
func segment_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in _segments:
		out.append((s as Node3D).position)
	return out
