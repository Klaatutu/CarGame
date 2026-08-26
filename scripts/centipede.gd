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
const BODY_SCENE := preload("res://assets/models/centipede.glb")

enum {WAITING, ENTERING, ROAMING, CARRIED, FLYING}

# --- corps ------------------------------------------------------------------

## Nombre d'anneaux, tete comprise.
const SEGMENTS := 15
## Espacement des anneaux le long du corps.
const SEG_SPACING := 0.019
## Longueur totale : 26,6 cm. Une Scolopendra gigantea en fait 30 — assez gros
## pour qu'on le voie du siege, assez petit pour passer par une grille.
const BODY_LEN := float(SEGMENTS - 1) * SEG_SPACING
## EPAISSEUR DU CORPS — 6 mm, et ce chiffre est MESURE, pas choisi.
##
## tools/probe_vents.gd releve les lames des aerateurs a 10,3 mm d'entraxe pour
## 4 mm d'epaisseur : il reste 6,3 mm entre deux lames. C'est par la qu'il
## passe, donc c'est ce qu'il mesure. Un mille-pattes est plat pour exactement
## cette raison — c'est ce qui lui permet de vivre sous les pierres, et ici
## d'etre dans la voiture avant toi.
const BODY_T := 0.006
## Hauteur du ventre au-dessus de la surface : il est porte par ses pattes.
const RIDE := 0.005
## Plongee des pattes sous l'horizontale, appliquee au pivot a chaque image.
## Le reste de la patte — cuisse arquee, genou, pointe — est de la GEOMETRIE,
## figee dans le modele (assets/blender/build_centipede.py) : une seule
## rotation par patte suffit a la foulee.
const LEG_DROOP := 0.10

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
## faire. Voir _advance : une bestiole ne se teleporte pas. Serre : la ou deux
## boites du releve se contredisent, l'ecart est de 2-3 mm — 5 suffisent a la
## relaxation. A 12, le banc a vu la lèvre du nez de planche la faire SAUTER
## 17 mm en contrebas, et la morsure la renvoyer sur la face : un cycle a
## quatre images dont elle ne sortait plus.
const MAX_SNAP := 0.005
## Le mou de la SORTIE d'un dedans, lui, reste large : "ne traverse rien" est
## une contrainte, et la face de sortie peut etre a GRIP + RIDE d'ici — serrer
## ce budget-la laissait la tete UNE image dans la tole au banc.
const EXIT_SNAP := 0.012
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

## JAMAIS COINCE, cette fois au ras du sol. GOAL_TIMEOUT change d'etape au bout
## de neuf secondes, mais une etape neuve ne debloque pas une tete CALEE : la ou
## deux boites du releve se contredisent, le recollage rend chaque pas aussitot,
## et la bestiole piétine sur place — neuf secondes de sur-place, ca se voit.
## On mesure donc le PROGRES, pas l'age de l'etape : quelques battements de
## course sans avancer, et elle tourne franchement — une bestiole ne s'obstine
## pas contre un angle, elle le contourne.
const STUCK_TIME := 0.7
const STUCK_MOVE := 0.012

## Jour minimal au-dessus de la glace pour qu'un corps de 6 mm et ses pattes
## passent en VOL — jete, pas en rampant : en l'air, rien ne se faufile.
const THROW_GAP := 0.03

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

## Section du corps sous les doigts, pour interaction.gd (l'axe de prise
## traverse la longueur, seule la section compte pour fermer la main).
var half := Vector3(0.011, 0.13, 0.011)

var _dir := Vector3.FORWARD
var _goal := Vector3.ZERO
var _goal_age := 0.0
var _wait := 0.0
var _running := true
var _phase := 0.0
var _emerged := 0.0
var _vel := Vector3.ZERO           # vitesse en vol, espace voiture
var _through := false              # en vol : engage dans le jour d'une vitre
var _stuck_t := 0.0
var _stuck_ref := Vector3.ZERO
var _shell_mat: ShaderMaterial
var _shell_base := Color(0.26, 0.115, 0.048)
var _trail_pos: Array[Vector3] = []
var _trail_nrm: Array[Vector3] = []
var _segments: Array[Node3D] = []
var _legs: Array = []              # [[gauche, droite], ...] par anneau
var _antennae: Array[Node3D] = []


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
		CARRIED:
			# La main promene le NOEUD (interaction.gd) ; nous, on se debat
			# dedans, en espace local.
			_carried_pose(delta)
		FLYING:
			_fly_step(delta)

	if state != WAITING and state != CARRIED:
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
	_stuck_ref = head_pos
	_stuck_t = 0.0


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

	# Le garde-fou du sur-place (STUCK_*) : il ne compte que le temps de COURSE
	# — fige, il ne progresse pas, et c'est voulu.
	_stuck_t += delta
	if head_pos.distance_to(_stuck_ref) > STUCK_MOVE:
		_stuck_ref = head_pos
		_stuck_t = 0.0
	elif _stuck_t > STUCK_TIME:
		# Un ecart franc, pas une fuite : l'etape reste la meme — si elle est
		# vraiment injoignable, GOAL_TIMEOUT s'en chargera.
		var a := rng.randf_range(PI * 0.35, PI * 0.75)
		_dir = _dir.rotated(head_nrm, a if rng.randf() < 0.5 else -a).normalized()
		_stuck_ref = head_pos
		_stuck_t = 0.0
	return RUN_SPEED * delta


## Les quatre lignes de l'en-tete : avancer, mordre, recoller, reprojeter.
func _advance(delta: float, step: float, stick: bool) -> void:
	if step <= 0.0:
		_animate(delta)
		return

	var from := head_pos
	var nrm_prev := head_nrm
	var probe := head_pos + _dir * step - head_nrm * GRIP
	var hit := _nearest(probe)
	var glued := false
	if stick and hit["d"] < REACH:
		var glue: Vector3 = hit["q"] + (hit["n"] as Vector3) * RIDE
		if hit["inside"] or glue.distance_to(from) <= step + MAX_SNAP:
			head_pos = glue
			head_nrm = hit["n"]
			glued = true
		else:
			# UNE BESTIOLE NE SE TELEPORTE PAS. La surface la plus proche est a
			# plus d'un pas : y coller la tete d'un coup, c'est le saut que le
			# banc a vu a la lèvre du nez de planche — la tole derriere est
			# 17 mm plus bas, le recollage y jetait la tete, la morsure la
			# renvoyait sur la face, quatre images en boucle. On MARCHE vers la
			# surface a la vitesse du pas, SANS changer d'appui : le recollage
			# aboutira dans deux ou trois images, quand elle sera vraiment sous
			# le ventre — et l'appui ne bascule qu'une fois, a l'arrivee.
			# (Dedans, en revanche, on sort toujours : "ne traverse rien" est
			# une contrainte, pas un souhait — voir _nearest.)
			head_pos = from + (glue - from).limit_length(step)
			# Et l'approche n'a pas le droit de couper un angle A TRAVERS la
			# tole : si ce pas vient d'entrer dans une piece, on en sort tout
			# de suite, par la face la plus proche, comme toujours.
			var mid := _nearest(head_pos)
			if mid["inside"]:
				head_pos = (mid["q"] as Vector3) + (mid["n"] as Vector3) * RIDE
				head_nrm = mid["n"]
				glued = true
	else:
		# Rien a portee, ou bien il traverse encore son trou : il continue tout
		# droit plutot que de se teleporter sur la paroi la plus proche.
		head_pos = probe + head_nrm * GRIP

	# Meme un recollage "dedans" reste borne : la ou deux boites se recouvrent,
	# la face de sortie peut changer d'une image a l'autre — la relaxation
	# converge en deux ou trois images au lieu de faire sauter les anneaux.
	head_pos = from + (head_pos - from).limit_length(
		step + (EXIT_SNAP if hit["inside"] else MAX_SNAP))
	if stick:
		_contain(glued)

	# LE CAP TOURNE AVEC L'APPUI. Basculer par-dessus une arete, c'est subir la
	# rotation qui amene l'ancienne normale sur la nouvelle — le cap la subit
	# aussi : arrivee perpendiculaire a l'arete du nez de planche, la bestiole
	# CONTINUE vers le bas de la face. L'ancienne projection donnait zero dans
	# ce cas precis, et le fallback vertical la renvoyait vers le haut — donc
	# vers l'arete : elle faisait la navette sur la lèvre, et c'etait "il se
	# bloque a certains endroits".
	var swing := nrm_prev.cross(head_nrm)
	if swing.length_squared() > 0.000001:
		_dir = _dir.rotated(swing.normalized(), nrm_prev.angle_to(head_nrm))
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
##   - LA TOLE (`cabin.shape`, plus le vitrage de `cabin.shell`) — il marche
##     DESSUS, la normale sort de la matiere. Un point deja dedans compte comme
##     une distance egale a sa penetration, ce qui le fait ressortir par la face
##     la plus proche : il reste ainsi sur la peau exterieure la ou plusieurs
##     epaisseurs se superposent.
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
func _contain(glued := false) -> void:
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
		# La normale ne bascule que sur un VRAI depassement — a l'exact
		# millimetre pres, marcher sur le plancher touche la borne a chaque
		# image — et JAMAIS quand la tete est collee a une vraie surface : au
		# pied du pare-brise, l'auvent vit a 4 mm dans la marge de la coque, et
		# reecrire la normale du recollage y fabriquait un pat parfait — la
		# vitre reprenait l'appui, le cap se retransportait vers le bas, et la
		# meme image se rejouait a l'infini. La coque borne la POSITION ; la
		# normale, elle, appartient a ce qu'on touche.
		if over > 0.001 and not glued:
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

	# LA TOLE, relevee case par case sur le .glb (cabin_shape.gd). C'est ce qui
	# a remplace `solids + crawl_solids` : une vingtaine de boites saisies a la
	# main, dont trois n'existaient QUE pour lui — le nez de la planche de bord,
	# les contre-portes, le pare-brise — parce que personne n'avait pense aux
	# autres faces verticales. Les montants, le tunnel, le capot des compteurs,
	# les dossiers, les bas de caisse n'y etaient pas, donc ils n'existaient pas
	# pour lui : c'etait "il ne marche pas sur toutes les surfaces visibles".
	#
	# Il n'y a plus de liste a tenir. Ce qui se voit se parcourt, et ajouter du
	# mobilier au modele lui donne de nouveaux chemins sans qu'on rebranche rien
	# — il suffit de recuire.
	if cabin.shape != null:
		var r: Dictionary = cabin.shape.nearest(p, REACH)
		if r["d"] < INF:
			if r["inside"]:
				buried = true
				deep = r
			else:
				best = r

	# LE VITRAGE, qui n'est pas dans le releve : c'est par la qu'il grimpe au
	# pare-brise. Ces boites peuvent se recouvrir librement — on cherche la
	# surface LA PLUS PROCHE, pas les intersections.
	for s in cabin.shell:
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
			if not buried or d < deep["d"]:
				deep = {"q": q, "n": n, "d": d, "inside": true}
			buried = true
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
	_seed_trail()
	_stuck_ref = head_pos
	_stuck_t = 0.0
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
	transform = Transform3D()


## La trace de depart : droite, semee en arriere de la tete. A l'entree elle
## remplit le conduit ; posee ou jetee, elle donne au corps de quoi se re-payer
## anneau par anneau.
func _seed_trail() -> void:
	_trail_pos.clear()
	_trail_nrm.clear()
	var n := int(ceil(BODY_LEN / TRAIL_STEP)) + 4
	for i in n:
		_trail_pos.append(head_pos - _dir * (float(i) * TRAIL_STEP))
		_trail_nrm.append(head_nrm)


# ---------------------------------------------------------------------------
# La main : il s'attrape comme un objet, et il se jette
# ---------------------------------------------------------------------------
#
# C'est le seul geste qui le sorte de la voiture — et il ne marche que vitre
# assez baissee. Le trajet complet : attraper (il se debat dans le poing),
# viser le jour au-dessus de la glace, clic molette. Rate, il retombe quelque
# part dans l'habitacle et y detale. Vitre fermee, il rebondit sur la glace —
# on ne jette rien a travers une vitre. La regle du jeu est symetrique de son
# entree : la vitre ouverte le laisse entrer, et c'est aussi par elle qu'on
# s'en debarrasse.

## Rayon de visee. On n'attrape que ce qui SE PROMENE : ni l'absent, ni celui
## encore dans l'epaisseur de la planche, ni ce qu'on tient deja.
func grab_radius() -> float:
	return 0.065 if state == ROAMING else 0.0


## L'axe du corps en main se couche sur l'axe du poing : on le tient comme un
## baton — qui se tortille.
func grip_axis() -> Vector3:
	return Vector3.UP


func front_axis() -> Vector3:
	return Vector3.BACK


func rest_height() -> float:
	return RIDE


func set_highlight(on: bool) -> void:
	_shell_mat.set_shader_parameter("modulate",
		_shell_base * 1.6 if on else _shell_base)


## Attrape : la marche se tait, interaction.gd promene le noeud, et le corps se
## debat en espace LOCAL autour du poing (_carried_pose).
func hold() -> void:
	state = CARRIED
	_through = false


## Pose : interaction.gd vient d'ecrire notre transform sur la surface visee,
## tourne vers le conducteur. On y reprend la promenade — droit devant, c'est
## la fuite, pas le retour.
func release() -> void:
	head_pos = position
	head_nrm = Vector3.UP
	var d := -transform.basis.z
	d.y = 0.0
	_dir = d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD
	transform = Transform3D(Basis(), head_pos)
	_seed_trail()
	_resume(rng.randf_range(0.9, 1.4))
	_place_segments()


## Jete : il part en l'air — un etat que la marche ne connait pas. La trace est
## reprise sur le corps TEL QU'IL EST dans le poing : il se deroule en vol au
## lieu d'apparaitre tout droit.
func throw(v: Vector3) -> void:
	_trail_pos.clear()
	_trail_nrm.clear()
	for s in _segments:
		_trail_pos.append(transform * (s as Node3D).position)
		_trail_nrm.append((transform.basis * (s as Node3D).basis.y).normalized())
	head_pos = _trail_pos[0]
	transform = Transform3D(Basis(), head_pos)
	_vel = v
	_dir = v.normalized() if v.length_squared() > 0.000001 else Vector3.FORWARD
	head_nrm = _any_tangent(_dir)
	_through = false
	state = FLYING


## En main : le corps s'enroule le long de l'axe du poing et se debat. Les
## pattes rament au TEMPS, pas a la distance — une bestiole tenue ne marche
## pas, elle panique. Les extremites gigotent plus que le milieu, qui est
## serre dans les doigts.
func _carried_pose(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var hl := BODY_LEN * 0.5
	var pts: Array[Vector3] = []
	for i in SEGMENTS:
		var s := float(i) * SEG_SPACING
		var amp := 0.006 + 0.022 * absf(hl - s) / hl
		pts.append(Vector3(
			amp * sin(s * 34.0 - t * 9.0),
			hl - s,
			amp * 0.6 * cos(s * 27.0 - t * 11.5)))
	for i in SEGMENTS:
		var fwd: Vector3 = pts[maxi(i - 1, 0)] - pts[mini(i + 1, SEGMENTS - 1)]
		fwd = fwd.normalized() if fwd.length_squared() > 0.000001 else Vector3.UP
		var up := Vector3.BACK - fwd * Vector3.BACK.dot(fwd)
		up = up.normalized() if up.length_squared() > 0.000001 else Vector3.RIGHT
		var right := up.cross(fwd).normalized()
		_segments[i].transform = Transform3D(Basis(right, up, -fwd), pts[i])
		var pair: Array = _legs[i]
		var flail := sin(t * 16.0 + float(i) * 0.9) * 0.8
		var claw := 0.35 + 0.25 * sin(t * 7.0 + float(i) * 1.7)
		(pair[0] as Node3D).rotation = Vector3(0.0, flail, claw)
		(pair[1] as Node3D).rotation = Vector3(0.0, -flail, -claw)
	_animate(delta)


## En vol. La marche colle a la tole ; ici rien ne colle — gravite, l'elan de
## la voiture en moins (meme raisonnement que prop.gd), et deux issues : le
## jour d'une vitre baissee, ou n'importe quelle tole ou il retombe.
func _fly_step(delta: float) -> void:
	var drive := Vector3.ZERO
	if carrier != null:
		drive = -carrier.frame_accel
		drive.y = 0.0
	_vel += (drive + Vector3.DOWN * 9.8) * delta
	head_pos += _vel * delta
	walked += _vel.length() * delta       # les pattes rament dans l'air
	if _vel.length_squared() > 0.000001:
		head_nrm = _any_tangent(_vel.normalized())

	# Le jour au-dessus de la glace baissee — le geste demande au joueur :
	# ouvrir AVANT de jeter. La glace, elle, est toujours dans les boites du
	# vitrage : une trajectoire trop basse la cogne comme une vraie vitre.
	if not _through:
		for w in cabin.windows:
			var gap: float = w.travel * w.open
			if gap < THROW_GAP:
				continue
			if signf(head_pos.x) != signf(w.side):
				continue
			var box: AABB = w.glass_box
			# Le plan de sortie est celui de la COQUE, pas celui de la glace :
			# la glace du modele est montee dans la peau de porte, a 8 cm
			# AU-DELA de la coque — un seuil pris sur sa boite serait
			# inatteignable, la borne de vol rabattant la tete avant. C'est la
			# convention de l'entree (_window_entry), rejouee en sens inverse.
			if absf(head_pos.x) < cabin.HULL_MAX.x - RIDE - 0.005:
				continue
			if head_pos.y < box.end.y - gap + 0.006 or head_pos.y > box.end.y:
				continue
			if head_pos.z < box.position.z + 0.02 or head_pos.z > box.end.z - 0.02:
				continue
			_through = true
			break

	if _through:
		# Engage dans le jour : plus rien ne l'arrete. Dehors pour de bon une
		# fois la QUEUE passee — elle est a une longueur de corps de la tete.
		if absf(head_pos.x) > cabin.HULL_MAX.x + BODY_LEN + 0.15:
			_escape()
			return
	else:
		var hit := _nearest(head_pos)
		if hit["inside"] or (hit["d"] as float) <= RIDE:
			_land_on((hit["q"] as Vector3) + (hit["n"] as Vector3) * RIDE, hit["n"])
		else:
			# La coque le retient partout ou il n'y a pas de vitre : pavillon,
			# lunette, plancher n'ont pas de boite a eux.
			var lo: Vector3 = cabin.HULL_MIN + Vector3(RIDE, RIDE, RIDE)
			var hi: Vector3 = cabin.HULL_MAX - Vector3(RIDE, RIDE, RIDE)
			for a in 3:
				var n := Vector3.ZERO
				if head_pos[a] < lo[a]:
					head_pos[a] = lo[a]
					n[a] = 1.0
				elif head_pos[a] > hi[a]:
					head_pos[a] = hi[a]
					n[a] = -1.0
				if n != Vector3.ZERO:
					_land_on(head_pos, n)
					break

	_push_trail()
	_animate(delta)


## Retombe : il se raccroche ou il a touche et DETALE — une longue course
## d'abord, les pauses reviendront apres.
func _land_on(q: Vector3, n: Vector3) -> void:
	head_pos = q
	head_nrm = n
	var tang := _vel - n * _vel.dot(n)
	_dir = tang.normalized() if tang.length_squared() > 0.000001 else _any_tangent(n)
	_resume(rng.randf_range(1.0, 1.6))


func _resume(dash: float) -> void:
	state = ROAMING
	_running = true
	_wait = dash
	_pick_goal()
	_stuck_ref = head_pos
	_stuck_t = 0.0


## Dehors. Ce n'est pas une mort : la voiture n'a pas moins de bouches
## qu'avant, et la vitre est peut-etre restee ouverte. Il reviendra — mais on a
## achete du calme, et c'etait le prix du geste.
func _escape() -> void:
	state = WAITING
	visible = false
	entry_label = ""
	transform = Transform3D()
	_wait = rng.randf_range(25.0, 45.0)


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
	# Le NOEUD chevauche la tete, et les anneaux s'expriment par rapport a elle.
	# Ce n'est pas une coquetterie : interaction.gd vise `global_position` — un
	# noeud reste a l'origine de la voiture serait une cible fantome a un metre
	# de la bestiole. Le repere, lui, reste celui de la voiture (base identite).
	position = head_pos
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
		seg.transform = Transform3D(Basis(right, up, -fwd), p - head_pos)

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
	_shell_mat = Retro.mat(_shell_base, 0.32, 0.22)
	var limb := Retro.mat(Color(0.46, 0.26, 0.075), 0.48, 0.05)
	var eye := Retro.mat(Color(0.02, 0.02, 0.025), 0.12, 0.30)
	var fang := Retro.mat(Color(0.30, 0.14, 0.05), 0.35, 0.15)

	# Le corps vient du .glb (assets/blender/build_centipede.py) : plaques
	# bombees, pattes arquees a pointe griffue, antennes en fouet — la ou les
	# BoxMesh d'origine faisaient un train de cubes. Les pivots y portent les
	# memes places que ceux qu'on construisait ici : le jeu continue d'ecrire
	# rotation = (0, houle, ±droop) sur chaque hanche, sans rien savoir de la
	# geometrie qui pend dessous.
	var scene: Node = BODY_SCENE.instantiate()
	for i in SEGMENTS:
		var seg := scene.find_child("CPD_Seg%02d" % i, true, false) as Node3D
		seg.get_parent().remove_child(seg)
		_disown(seg)
		add_child(seg)
		seg.transform = Transform3D()
		_segments.append(seg)
		_legs.append([
			seg.find_child("CPD_LegL%02d" % i, true, false) as Node3D,
			seg.find_child("CPD_LegR%02d" % i, true, false) as Node3D,
		])
		if i == 0:
			# L d'abord : _animate donne side = +1 au premier, et c'est ce qui
			# ecarte chaque antenne vers SON exterieur.
			_antennae.append(seg.find_child("CPD_AntL", true, false) as Node3D)
			_antennae.append(seg.find_child("CPD_AntR", true, false) as Node3D)
		_dress(seg, limb, eye, fang)
	scene.free()


## Les matieres du jeu sur les maillages du .glb, pas celles de l'export : tout
## le jeu passe par le shader de tramage (retro.gd), et ces couleurs-la ont ete
## remontees deux fois pour se detacher de la planche — on ne laisse pas
## l'importeur les rejouer en StandardMaterial.
func _dress(n: Node, limb: Material, eye: Material, fang: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if nm.begins_with("CPD_Shell"):
			mi.material_override = _shell_mat
		elif nm.begins_with("CPD_Eye"):
			mi.material_override = eye
		elif nm.begins_with("CPD_Fang"):
			mi.material_override = fang
		else:
			mi.material_override = limb
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_dress(c, limb, eye, fang)


func _disown(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_disown(c)


# ---------------------------------------------------------------------------
# Ce que les bancs d'essai regardent
# ---------------------------------------------------------------------------

## Ecart entre le ventre et la surface la plus proche. Doit valoir RIDE : au-dela
## il vole, en dessous il est dans la tole.
func clearance() -> float:
	return _nearest(head_pos)["d"]


## Position monde de la tete, pour viser ou pour cadrer une capture. Le noeud
## chevauche deja la tete (_place_segments) : head_pos est en espace voiture,
## donc dans le repere du PARENT.
func head_point() -> Vector3:
	return get_parent_node_3d().global_transform * head_pos


## Position en espace voiture de chaque anneau : de quoi verifier que le corps
## ne se decoud pas. Les anneaux sont locaux au noeud, qui chevauche la tete —
## on les repasse par sa transform.
func segment_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in _segments:
		out.append(transform * (s as Node3D).position)
	return out
