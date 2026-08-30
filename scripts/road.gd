extends Node3D
##
## Route infinie et lisse.
##
## Ce n'est PAS une suite de blocs poses bout a bout : on garde une ligne
## mediane echantillonnee tous les STEP metres, et on reconstruit un unique
## ruban de triangles qui la suit. Aucun joint, aucun chevauchement, aucune
## marche, meme en plein virage.
##
## Le ruban est reconstruit a chaque fois qu'on avance d'un echantillon
## (environ 10 fois par seconde a pleine vitesse) : ~1500 sommets, c'est gratuit.
##

const Retro := preload("res://scripts/retro.gd")
const PoliceCar := preload("res://scripts/police_car.gd")
const GiantScript := preload("res://scripts/giant.gd")
const StranglerScript := preload("res://scripts/strangler.gd")
const PortalScript := preload("res://scripts/portal.gd")
const TownScript := preload("res://scripts/town.gd")
## La geometrie de ruban, sortie d'ici. Elle n'est plus a nous : une rue de
## bourg est le meme ruban qu'une nationale, et les deux doivent poser les
## MEMES triangles — pas des triangles qui se ressemblent.
const Strip := preload("res://scripts/strip.gd")
## Le plan d'une ville. On ne lui prend ici que ses DEUX bornes de traversee
## (CROSS et PAD) : la ou le ruban s'efface est exactement la ou le bourg
## dessine, et deux nombres recopies a la main auraient fini par diverger d'un
## echantillon — soit deux metres de chaussee en double, en travers des phares.
## Aucune boucle : town_plan.gd ne charge que map.gd, et map.gd ne charge rien.
const TownPlan := preload("res://scripts/town_plan.gd")

# Les bifurcations. Un Y : le ruban vivant s'incurve d'un cote, un BRIN MORT
# de BRANCH_LEN echantillons diverge de l'autre et meurt dans le brouillard.
# Le cote que prend la voiture entre F+FORK_FROM et F+FORK_TO choisit l'arete
# suivante — passer sur le brin mort ECHANGE les deux rubans (voir _swap).
const BRANCH_LEN := 40          # echantillons du brin mort (80 m)
const FORK_BEND := 0.0075       # rad/m d'ecartement, sous MAX_CURVE
const FORK_SPAN := 30           # echantillons de virage force sur le vivant
const FORK_FROM := 8            # la fenetre de choix, depuis la fourche...
const FORK_TO := 26             # ...jusqu'ici (echantillons)
const FORK_SIGN_AT := 45        # le panneau en Y, tant d'echantillons avant

const STEP := 2.0               # distance entre deux points de la ligne mediane
const SAMPLES := 150            # ~300 m de route vivante
const BEHIND := 12              # echantillons conserves derriere la voiture
const ROAD_HALF := 3.4          # demi-largeur de la chaussee
const SHOULDER := 2.4           # accotement de chaque cote
const ROAD_COLS := 2            # decoupe en largeur du ruban
const SHOULDER_COLS := 1
const LINE_INSET := 0.45        # retrait de la ligne continue par rapport au bord
const LINE_HALF := 0.075
const DASH_HALF := 0.08
const DASH_EVERY := 4           # un pointille tous les N echantillons
const MAX_CURVE := 0.009        # rad/m -> rayon mini ~110 m

# La traversee d'un bourg. Le ruban n'y est ni coupe ni fige : il continue de
# naitre, seule sa COURBURE est bridee, parce que le quadrillage de rues est
# pose en coordonnees curvilignes et se cisaille si l'axe tourne trop.
#
# 0,0015 rad/m -> rayon 667 m : a 60 m de l'axe, le cote interieur est comprime
# de 9 %, ce qui ne se voit pas. A MAX_CURVE (rayon 111 m) il le serait de
# 54 % et les ilots se replieraient sur eux-memes.
const TOWN_CURVE := 0.0015

# LE SLALOM DE LA TRAVERSANTE. Le plafond ci-dessus n'a pas bouge d'un chiffre.
# C'est la LOI de la courbure qui change, et c'etait elle le probleme.
#
# CE QUI EST TOMBE. Il etait ecrit ici : « et surtout pas zero — 342 m de regle
# plate armeraient la monotonie de sleep.gd huit fois par nuit ; la ville doit
# se conduire, pas se subir ». L'intention etait juste, la conclusion fausse, et
# personne ne l'avait mesuree. Le banc l'a fait, au volant et non au rail : sur
# dix traversees, le plus long silence du volant valait 21,0 / 12,7 / 11,4 /
# 17,0 / 10,4 / 21,0 / 7,3 / 12,9 / 21,1 / 16,9 s — pour une traversee de
# 21,0 s. TROIS FOIS SUR DIX la traversee entiere sans un geste ; neuf fois sur
# dix au-dessus des 10 s ou la monotonie s'arme ; un seul lancement vert. La
# ville ARMAIT la monotonie ; elle ne la desarmait pas. La courbure bornee ne
# l'avait jamais desarmee — on l'avait ecrit, pas mesure.
#
# PREMIERE ARITHMETIQUE : LE REGIME PERMANENT NE PEUT PAS Y ARRIVER. Pour tenir
# une courbure k a la vitesse v il faut steer = v * k / (steer_rate * grip *
# stability) — a 12,5 m/s, steer = 13,5 * k (car.gd). Au plafond, 13,5 * 0,0015
# = 0,020 de volant : LA MOITIE du seuil de monotonie (0,04). Et le plafond ne
# peut pas monter pour compenser : la compression a 60 m de l'axe vaut 60 * k,
# donc les 12 % que le banc autorise plafonnent k a 0,0020 — soit 0,027. Aucune
# courbure conduisible par une ville n'amene le volant a 0,04 en regime etabli.
# Ce n'est pas un reglage, c'est une inegalite.
#
# DEUXIEME ARITHMETIQUE, CELLE QU'ON N'AVAIT PAS VUE : UNE COURBE CONSTANTE EST
# AUSSI MUETTE QU'UNE LIGNE DROITE. Le conducteur — celui du banc comme le
# joueur — a une bande morte : il ne touche au volant que quand l'ecart l'y
# force. Dans un virage de courbure constante, ce systeme a un POINT FIXE
# STABLE : la voiture se cale sur un ecart lateral ou la poussee vaut
# exactement les 0,020 qu'il faut, et le volant s'y gare. Il ne repassera pas
# 0,04 tant que la courbure ne CHANGERA pas. Un long virage regulier ne demande
# rien — il demande juste autre chose que rien une seule fois.
#
# TROISIEME PIEGE, PAYE AU BANC : UN SLALOM COURT EST PIRE QUE TOUT. Premiere
# tentative, demi-periode de 9 a 15 echantillons (18 a 30 m) : l'axe revient a
# son cap a chaque periode, donc les ecarts SE COMPENSENT et la voiture traverse
# tout droit sans jamais rien accumuler. Releve : silence 8,9 / 17,8 / 10,3 /
# 10,8 / 12,7 s. La route serpentait joliment et ne demandait rien.
#
# POURQUOI LES DEUX INVARIANTS NE TIRENT PAS EN SENS CONTRAIRE, CONTRAIREMENT
# A CE QU'ON A CRU. Le banc a conclu, noir sur blanc, que « la traversee ne
# desarme PAS la monotonie et ne peut pas le faire sans replier le quadrillage
# du bourg » — apres avoir essaye de monter l'ECART-TYPE du tirage centre sur
# zero : cap a 40 deg, silence a 5,1 s, vert... et compression a 41 %, quatre
# fois le seuil. La conclusion etait juste POUR CE LEVIER-LA, et fausse en
# general, parce que le levier melangeait deux grandeurs :
#   - la compression du quadrillage ne voit que |k|, la courbure ELLE-MEME ;
#   - le volant ne voit que dk/ds, la VITESSE A LAQUELLE elle change.
# Monter l'ecart-type monte les deux ensemble. Alterner le SIGNE a magnitude
# constante monte le second SANS TOUCHER AU PREMIER. C'est tout le tour : le
# plafond reste a 0,0015, la compression reste a 8,4-9,0 %, et le silence tombe
# de 21,0 a 3,3-6,2 s. Il n'y avait pas d'arbitrage, il y avait un raccourci.
#
# CE QUI MARCHE : LE CHANGEMENT DE SENS, A CADENCE TENUE, SUR DES BORDS ASSEZ
# LONGS POUR QU'IL FAILLE VRAIMENT ENTRER DEDANS. La consigne alterne de bord
# a chaque tirage et vise le plafond au lieu de le fuir. Entre deux
# renversements le volant se gare : la demi-periode FIXE donc le silence,
# presque a elle seule. Le balayage, cinq a six lancements par reglage, bord a
# 80 % du plafond et lissage a 0,26 :
#   24 a 42 ech. (48-84 m, 3,8-6,7 s) : 10,0 / 6,3 / 5,8 / 6,2 / 6,1 — un rouge
#   20 a 30 ech. (40-60 m, 3,2-4,8 s) : 4,0 / 5,5 / 4,5 / 3,5 / 5,1 / 7,9 — 7,9 frole
#   16 a 26 ech. (32-52 m, 2,6-4,2 s) : 3,5 / 4,0 / 3,2 / 7,0 / 3,6
# puis en DURCISSANT le renversement au lieu de raccourcir encore (bord a 90 %,
# lissage a 0,45) : 3,3 / 3,7 / 3,3 / 6,2 / 3,5 s. C'est la QUEUE de la
# distribution qu'on visait la — le renversement qui tombe du bon cote, ou la
# voiture est deja placee pour le bord qui vient et n'a rien a corriger. On la
# coupe en rendant le renversement plus franc, pas en le repetant plus souvent :
# plus court, on retombe dans le piege ci-dessus.
#
# LE RELEVE QUI FAIT FOI, reglage final, DIX lancements (la courbure est retiree
# a chaque lancement, un vert unique ne prouverait rien) :
#   silence du volant   3,0 / 3,7 / 4,2 / 3,3 / 5,6 / 3,7 / 3,4 / 3,7 / 3,1 /
#                       4,3 s      — seuil 8,0, et 10,0 pour la monotonie
#   |steer| maxi        0,074 a 0,082               — seuil 0,040
#   compression a 60 m  8,7 a 9,0 %                 — seuil 12
#   cap sur les 260 m   17 deg environ              — il valait 5,4 a 10,3
#   portion la plus plate  4 m                      — elle allait a 194 m
# Le pire silence releve, 5,6 s, tient sous les 10 s de mono_after avec de la
# marge : la traversee ne se contente plus de ne pas endormir, elle reveille.
#
# CE QUE LE BOURG Y GAGNE, ET CE N'EST PAS UNE CONSOLATION. Le cap de la
# traversante ne DERIVE plus, il oscille. Une courbure de meme signe tenue sur
# les 260 m bomberait l'axe de 0,0015 * 260^2 / 2 = 51 m ; le slalom deporte
# chaque bord de 0,8 a 2,0 m et rend l'axe au suivant. Le quadrillage est plus
# droit qu'avant DANS SON ENSEMBLE — c'est localement, d'un bord a l'autre,
# qu'il travaille, et la compression relevee reste a 8,7-9,0 % pour un seuil
# de 12.
#
# CE QUE LE JOUEUR CONDUIT : une traversante qui se deporte d'un a deux metres
# tous les quarante metres, comme une rue de village posee sur d'anciennes
# limites de champs. On ne la voit pas serpenter dans le brouillard — on la
# SENT dans les mains, et c'est exactement ce qu'on voulait.
#
# Les trois nombres :
#  - TOWN_WEAVE, la demi-periode, en echantillons. 32 a 52 m, 2,6 a 4,2 s a
#    12,5 m/s. Plus long, le volant se gare trop longtemps entre deux bords ;
#    plus court, les ecarts se compensent et il ne se leve plus du tout. Les
#    deux bornes sont des murs mesures, pas des gouts.
#  - TOWN_WEAVE_FLOOR : chaque bord vise au moins 90 % du plafond. Ce qui fait
#    la taille du transitoire, c'est l'ECART entre les deux bords consecutifs ;
#    un bord mou est un renversement mou.
#  - TOWN_SETTLE : le lissage. A 0,09 (celui de la nationale) la courbure
#    n'atteignait meme pas sa consigne avant d'en recevoir une autre —
#    constante de temps de 11 pas pour des bords de 16. A 0,45 le renversement
#    est fait en quatre echantillons, 8 m : le cap reste continu (rien ne casse
#    dans le ruban, virage releve 0,16 deg/pas pour un plafond de 1,03) et
#    c'est la COURBURE qui marche au pas, comme sur un virage de campagne pris
#    sans raccordement progressif.
const TOWN_WEAVE := Vector2i(16, 26)
const TOWN_WEAVE_FLOOR := 0.90
const TOWN_SETTLE := 0.45

# Ce que les props s'interdisent autour d'une ville, en echantillons de part et
# d'autre du dessin masque. 20 = 40 m : un arbre plante juste au bord du bourg
# pousse dans le trottoir, et le brouillard ne le cache qu'a moitie.
const PROP_QUIET := 20

# La trace : la ligne mediane DEJA PARCOURUE, un point sur TRAIL_EVERY (un
# tous les 8 m), dans un tampon circulaire. 4096 points = 32 Ko et 32 km, soit
# plus qu'une nuit entiere (~29 km). Le GPS s'en servira pour dire d'ou l'on
# vient. Ce n'est PAS la trajectoire de la voiture : c'est l'axe de la route.
#
# LA CADENCE SE COMPTE, ELLE NE SE LIT PAS DANS _index0. Elle l'a fait, et le
# banc l'a prise sur le fait : _swap_to_branch REPOSE _index0 sur
# _fork_g + 1 + start (l'index global continue, c'est voulu), et les index que
# le saut enjambe ne sont jamais pousses. Quand un multiple de TRAIL_EVERY
# tombait dans ce trou — 7 lancements sur 10 —, la trace passait de 8,00 m a
# 15,99 m entre deux points : exactement deux fois la cadence, un point perdu.
# Un compteur d'echantillons POUSSES ne connait pas les index et ne peut pas
# les rater.
const TRAIL_EVERY := 4
const TRAIL_MAX := 4096

# Hauteurs : tout est plat, seul l'ordre compte pour eviter le z-fighting.
const Y_SHOULDER := 0.0
const Y_ROAD := 0.02
const Y_PAINT := 0.026

const TREE_COUNT := 96
const POLE_COUNT := 18
const POLE_EVERY := 9           # echantillons entre deux poteaux

# Voiture de police garee sur l'accotement de droite, gyrophares allumes.
# La premiere a ~200 m du depart, les suivantes tous les 1,2 a 2,8 km.
const POLICE_FIRST := 110       # echantillon (global) de la premiere
const POLICE_EVERY_MIN := 600
const POLICE_EVERY_MAX := 1400
const POLICE_OFF := ROAD_HALF + 1.15   # centre de la caisse : sur l'accotement, hors de la voie
const POLICE_YAW := 7.0         # nez legerement tourne vers la route, comme garee a la hate
const POLICE_KEEP_BEHIND := 80.0      # on la laisse vivre tant qu'elle est a moins de 80 m derriere

# Le geant. Il est TAPI dans les arbres a l'echantillon prevu, bien avant que la
# voiture n'y arrive : c'est lui qui decide de se lever quand elle approche (voir
# giant.gd, notice_distance). La route ne fait que le poser et le rallumer.
#
# 480 m pour le premier, soit une vingtaine de secondes : le temps de partir, de
# passer les rapports et de croire qu'on est seul.
const GIANT_FIRST := 240              # echantillon (global)
const GIANT_EVERY_MIN := 900
const GIANT_EVERY_MAX := 1800
## Ecart a l'axe de la route. 15 m : dans la bande d'arbres (elle va jusqu'a
## 20 m), assez pres pour qu'il soit dans les phares en passant, assez loin pour
## qu'accroupi il se confonde avec les troncs.
const GIANT_OFF := 15.0

# L'etrangleur (strangler.gd). Lui ne se cache pas : il est POSE debout au
# milieu de la voie, face au sens de circulation, et il attend. Le premier
# vient apres le premier geant — on a appris qu'on pouvait fuir, et voila
# quelque chose qu'on ne fuit pas, qu'on evite ou qu'on abat.
const STRANGLER_FIRST := 420          # echantillon (global), ~820 m
const STRANGLER_EVERY_MIN := 800
const STRANGLER_EVERY_MAX := 1600
## Jeu lateral autour de l'axe : jamais exactement au milieu, comme quelqu'un
## qui est ARRIVE la, pas qui y a ete dessine.
const STRANGLER_JITTER := 0.8

var target: Node3D

## Les monstres ont-ils le droit d'apparaitre ? Vrai par defaut — les bancs
## d'essai gardent le monde d'avant. Le jeu normal le baisse : geant et
## etrangleur vivent dans le CAUCHEMAR (main.gd, la bascule du sommeil).
var monsters := true

var _pos := PackedVector3Array()      # points de la ligne mediane
var _right := PackedVector3Array()    # vecteur "droite" unitaire a chaque point
var _index0 := 0                      # index global du premier echantillon

var _head := Transform3D()
var _curve := 0.0
var _curve_goal := 0.0
var _until_new_curve := 16
var _rng := RandomNumberGenerator.new()

var _mesh := ArrayMesh.new()
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _f := PackedInt32Array()

var _mat_asphalt: ShaderMaterial
var _mat_shoulder: ShaderMaterial
var _mat_paint: ShaderMaterial
var _mat_bark: ShaderMaterial
var _mat_leaf: ShaderMaterial
var _mat_pole: ShaderMaterial

var _mesh_trunk: CylinderMesh
var _mesh_crown: CylinderMesh
var _mesh_pole: CylinderMesh
var _mesh_crossarm: BoxMesh

var _trees: Array[Node3D] = []
var _tree_i := 0
var _poles: Array[Node3D] = []
var _pole_i := 0
var _since_pole := 0

var police: Node3D
## Echantillon global ou la voiture de police est posee (-1 : nulle part).
var police_index := -1
var _police_next := POLICE_FIRST

var giant: Node3D
## Echantillon global ou le geant est tapi (-1 : il n'est nulle part).
var giant_index := -1
var _giant_next := GIANT_FIRST

var strangler: Node3D
## Echantillon global ou l'etrangleur est poste (-1 : nulle part).
var strangler_index := -1
var _strangler_next := STRANGLER_FIRST

## Le portail du cauchemar (portal.gd) : arme par set_portal, un seul.
var portal: Node3D
var portal_index := -1
var _portal_at := -1

## La ville franchie (le panneau vient d'etre depasse par la VOITURE).
signal town_reached(id: String)
## La ville rangee : on en est SORTI par le bout, elle vient de s'eteindre.
## Le pendant de town_reached — l'une ouvre la traversee, l'autre la ferme.
signal town_left(id: String)
## Le Y est tranche : "left"/"right", et la ville vers laquelle ce cote mene.
signal fork_committed(side: String, id: String)

## La ville en approche (town.gd, un seul exemplaire en pool).
var town: Node3D
var _town_g := -1
var _town_id := ""

## LES BORNES DE LA TRAVERSEE, en echantillons globaux. _town_in est le premier
## echantillon que la ville dessine (PAD avant son panneau), _town_out le
## dernier de la traversee (le panneau de sortie) ; le dessin de la ville va
## jusqu'a _town_out + PAD. (-1, -1) : aucune ville dans le monde.
##
## ELLES SONT POSEES A L'ARMEMENT, ET SURTOUT PAS DANS program_town. La
## navigation programme la ville SUIVANTE a l'instant ou le panneau de la
## COURANTE est franchi (main.gd, branche a une sortie) : un jeu unique de
## bornes pose par program_town sauterait de ~475 echantillons a l'echantillon
## zero de la traversee, et le ruban national se re-triangulerait en travers du
## bourg, coplanaire avec ses rues au meme Y_ROAD.
var _town_in := -1
var _town_out := -1
## Le masque ne mord que quand la ville dessine VRAIMENT sa traversante :
## town.gd repond par draws_trunk(), qui n'est vrai qu'une fois ses six
## surfaces versees. LE MASQUE TOURNE, et il se mesure SUR LE DESSIN — c'est
## LE MASQUE EST OUVERT (villetest, vingt lancements) : 0 triangle du ruban
## national dans la fenetre que le bourg occupe, contre 2 188 a 3 052 selon le
## lancement dans la MEME fenetre, a la MEME image, une fois le masque referme
## a la main — ce compte-la suit la courbure tiree au lancement, pas la regle ;
## c'est le zero qui est l'invariant. Au meme endroit, la couture vaut
## 0,000000 m d'ecart sur les douze sommets compares, aux vingt lancements.
var _town_ready := false

## La traversee PRE-CALCULEE : les transforms des echantillons a naitre, du
## panneau jusqu'a PAD apres la sortie. La ville a besoin de sa ligne mediane
## ENTIERE au moment ou elle se batit, et ces echantillons n'existent pas
## encore — la tete de fenetre est justement le panneau. On les simule donc a
## l'armement, et _append_sample les CONSOMME au lieu de tirer au sort : la
## traversante du bourg et le ruban sont le meme point, pas deux points
## calcules pareil.
var _town_heads: Array[Transform3D] = []
var _town_curves := PackedFloat32Array()
var _town_i := 0

## La trace : tampon circulaire de TRAIL_MAX points (x, z), rempli a mesure que
## les echantillons sortent par l'arriere de la fenetre.
var _trail := PackedVector2Array()
var _trail_i := 0
var _trail_n := 0
## Echantillons restants avant le prochain point de trace. A 1 pour que le tout
## premier echantillon range parte dans la trace, comme le faisait _index0 % 4
## avec _index0 a zero.
var _trail_due := 1

## La fourche en cours. _fork_state : "" (aucune), "grow" (posee, brin mort
## construit), "window" (la voiture choisit), "done" (tranchee, le brin mort
## reste en decor jusqu'a passer derriere).
var _fork_g := -1
var _fork_left := ""
var _fork_right := ""
var _fork_main := "left"
var _fork_state := ""
var _bpos := PackedVector3Array()
var _bright := PackedVector3Array()
var _bhead := Transform3D()
var _bhead_end := Transform3D()
var _branch_mesh := ArrayMesh.new()
var _branch_mi: MeshInstance3D
var _fork_sign: Node3D


func _ready() -> void:
	_rng.randomize()
	_trail.resize(TRAIL_MAX)
	_build_resources()
	_build_prop_pools()

	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# On demarre la route derriere la voiture, et bien droite au depart.
	_head = Transform3D(Basis(), Vector3(0.0, 0.0, BEHIND * STEP))
	for i in SAMPLES:
		_append_sample()
	_rebuild()


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var forward := -target.global_transform.basis.z
	var moved := false
	var guard := 0
	while guard < SAMPLES:
		# ON PROJETTE SUR LA TANGENTE DU RUBAN, PAS SUR LE NEZ DE LA VOITURE.
		# Avec le nez, rouler 100 m EN TRAVERS de la route faisait defiler
		# (100 - 24) / 2 = 38 echantillons : la route avancait sous une voiture
		# qui n'avait pas avance dessus. Dans une rue laterale — et il va y en
		# avoir — ca aurait fait defiler la nationale entiere.
		#
		# La tangente se relit a chaque tour parce que _pos[0] change a chaque
		# tour : c'est la tangente SOUS le premier echantillon garde qu'on veut,
		# pas celle d'il y a 150 echantillons.
		#
		# `forward`, lui, reste le nez de la voiture pour l'extinction de la
		# police plus bas : deux questions differentes, deux vecteurs
		# differents. « Ai-je avance sur la route ? » n'est pas « qu'est-ce que
		# j'ai laisse derriere moi ? ».
		var tang := _pos[1] - _pos[0]
		tang.y = 0.0
		tang = tang.normalized()
		if (target.global_position - _pos[0]).dot(tang) < BEHIND * STEP:
			break
		_retire_trail(_pos[0])
		_pos.remove_at(0)
		_right.remove_at(0)
		_index0 += 1
		_append_sample()
		moved = true
		guard += 1
	if moved:
		_rebuild()
	# Une fois depassee, la voiture de police reste visible un moment (retroviseurs),
	# puis s'eteint jusqu'a la prochaine.
	if police.visible and (target.global_position - police.global_position).dot(forward) > POLICE_KEEP_BEHIND:
		police.visible = false
		police.set_process(false)
		police_index = -1

	# Le geant s'eteint tout seul une fois seme. On lui donne alors un nouveau
	# rendez-vous, loin devant : il faut avoir eu le temps de se croire tire
	# d'affaire avant de retomber sur le suivant.
	if giant_index >= 0 and giant.asleep():
		giant_index = -1
		_giant_next = _index0 + SAMPLES + _rng.randi_range(GIANT_EVERY_MIN, GIANT_EVERY_MAX)

	# L'etrangleur pareil : depasse, abattu ou vainqueur, il s'eteint de
	# lui-meme, et le suivant prend rendez-vous.
	if strangler_index >= 0 and strangler.asleep():
		strangler_index = -1
		_strangler_next = _index0 + SAMPLES \
			+ _rng.randi_range(STRANGLER_EVERY_MIN, STRANGLER_EVERY_MAX)

	# La ville : le panneau depasse par la VOITURE, l'evenement part ; le
	# decor, lui, vit encore un moment (retroviseurs) puis s'eteint.
	if _town_g >= 0 and head_index() >= _town_g:
		var id := _town_id
		_town_g = -1
		town_reached.emit(id)
	# L'EXTINCTION, ET PLUS AUCUN PRODUIT SCALAIRE AVEC LE CAP DE LA VOITURE.
	# « Le bourg est-il derriere moi ? » se lisait dans le nez de la voiture ;
	# ca n'a plus de sens des qu'on tourne dans une rue — nez au nord, ville a
	# l'ouest, elle passait pour depassee et s'eteignait sous les phares.
	#
	# Deux conditions, et il faut les deux : on est sorti PAR LE BOUT (65
	# echantillons, 130 m, apres le panneau de sortie) ET on n'est plus dedans.
	# La seconde interdit d'eteindre une ville dans laquelle on a fait
	# demi-tour — c'est le pop le plus voyant du jeu, deja paye une fois.
	if town != null and town.visible and _town_out >= 0 \
			and head_index() > _town_out + 65 \
			and not _town_contains(target.global_position):
		var left := String(town.town_name)
		town.sleep()
		_forget_town()
		town_left.emit(left)

	# La fourche. Dans la fenetre, la voiture choisit PAR SA TRAJECTOIRE :
	# plus pres du brin mort que du vivant d'une largeur de voie, on echange
	# les deux rubans — rien n'apparait ni ne disparait a moins de 200 m.
	if _fork_state == "grow" and head_index() >= _fork_g + FORK_FROM:
		_fork_state = "window"
	if _fork_state == "window":
		if head_index() > _fork_g + FORK_TO:
			# Le verdict — meme si la fenetre entiere a ete avalee par une
			# grosse image (machine chargee : releve au banc, grow -> window
			# -> commit dans le meme _process). Ou la voiture est-elle, LA :
			# plus pres du brin mort, c'est lui qu'elle a pris.
			if _closest_dist(_bpos, target.global_position) + 0.5 \
					< _closest_dist(_pos, target.global_position):
				_swap_to_branch()
			else:
				_fork_state = "done"
				fork_committed.emit(_fork_main,
					_fork_left if _fork_main == "left" else _fork_right)
		else:
			var d_main := _closest_dist(_pos, target.global_position)
			var d_branch := _closest_dist(_bpos, target.global_position)
			if d_branch + 2.2 < d_main:
				_swap_to_branch()
	# Le vieux ruban et le panneau se rangent une fois TOUT LEUR LOIN derriere
	# nous : apres un echange, l'ancienne fenetre s'etendait 280 m au-dela de
	# la fourche — la ranger trop tot ferait disparaitre une route sous les
	# yeux du retroviseur.
	if _fork_g >= 0 and _fork_state != "" and _fork_g < _index0 - 170:
		_clear_fork()


# --------------------------------------------------------------------------
# Ligne mediane
# --------------------------------------------------------------------------

func _append_sample() -> void:
	var g := _index0 + _pos.size()

	# LA TRAVERSEE SE CONSOMME, ELLE NE SE TIRE PAS. Si une ville est armee,
	# ses echantillons ont deja ete calcules (a l'armement, _simulate_town_path)
	# et le bourg s'est bati dessus : on repose ici la tete telle quelle. La
	# traversante et le ruban ne sont pas deux lignes qui se ressemblent, c'est
	# la meme ligne — la couture est nulle par identite, pas par arithmetique.
	var on_town_path := _town_i < _town_heads.size() and g <= _town_out + TownPlan.PAD
	if on_town_path:
		_head = _town_heads[_town_i]
		_curve = _town_curves[_town_i]
		# Le but suit la traversee : sans ca, la sortie de ville repartirait
		# vers une consigne d'avant la ville, tiree avant le panneau.
		_curve_goal = _curve
		_town_i += 1
	else:
		_advance_curve()

	# Le programme d'arete plie la geometrie : droit a l'approche d'une
	# ville (on arrive SUR un bourg, pas en glissade), ecarte au Y.
	#
	# Les deux regles se taisent sur la traversee, et c'est un constat autant
	# qu'une garde : la tete vient d'etre REPOSEE telle que la ville l'a batie,
	# donc rien de ce qu'on ecrirait ici dans _curve ne deplacerait le prochain
	# echantillon — il sera repose lui aussi. Le dire tout haut evite de croire
	# qu'on redresse quelque chose. La regle de ville ci-dessous vaut pour
	# l'APPROCHE ; celle du Y ne peut plus se presenter du tout depuis que
	# program_fork tient sa zone droite hors de la traversee.
	if not on_town_path and _town_g >= 0 and absi(g - _town_g) < 20:
		_curve = lerpf(_curve, 0.0, 0.4)
		_curve_goal = 0.0
	# Au Y, le ruban VIVANT file DROIT — du panneau jusqu'au bout du
	# raccord : continuer ne demande rien, c'est la sortie qui diverge. Tout
	# droit est un choix qu'on fait sans le savoir, braquer un choix qu'on
	# fait expres — et le panneau se lit sur une route qui ne tourne pas.
	#
	# Cette ligne ne redresse RIEN toute seule : elle ne s'applique qu'aux
	# echantillons a naitre. C'est program_fork qui la rend vraie, en posant
	# le Y au-dela du deja-bati — sans ce plancher, la fenetre entiere etait
	# coulee avant que le Y n'existe, et le ruban traversait la fourche en
	# plein virage (0,87 deg par pas, releve).
	if not on_town_path and _fork_g >= 0 and _fork_state in ["", "grow"] \
			and g >= _fork_g - FORK_SIGN_AT and g <= _fork_g + FORK_SPAN:
		_curve = 0.0
		_curve_goal = 0.0

	var forward := -_head.basis.z
	_pos.append(_head.origin)
	_right.append(forward.cross(Vector3.UP).normalized())

	# Le panneau en Y, 90 m avant la fourche. Il se pose sur l'echantillon
	# qui vient de naitre : c'est le plancher de program_fork qui lui donne
	# ses 90 m. Sans lui, le premier echantillon a naitre satisfaisait deja
	# le test et le panneau se plantait SUR le Y — a lire quand il est trop
	# tard pour braquer.
	if _fork_g >= 0 and _fork_state == "" and not _fork_sign.visible \
			and g >= _fork_g - FORK_SIGN_AT:
		_arm_fork_sign(_pos.size() - 1)
	# La fourche elle-meme : le brin mort part d'ici, le vivant s'incurve.
	# Le recalage ci-dessous est un FILET, plus le chemin normal : depuis que
	# program_fork pose son plancher au-dela du deja-bati, g tombe pile sur
	# _fork_g et la ligne ne change rien.
	if _fork_g >= 0 and _fork_state == "" and g >= _fork_g:
		_fork_g = g                    # si la fenetre l'a depasse : ici meme
		_bhead = _head
		_fork_state = "grow"
		_grow_branch()
	# La ville : posee a son echantillon, la traversee commence au panneau.
	# Sans condition de visibilite : l'echantillon arme est ~300 m devant la
	# voiture, la ville precedente est loin derriere (l'arete la plus courte
	# fait 950 m) — et une ville qui manque parce que la precedente trainait
	# encore serait pire que tout.
	if _town_g >= 0 and g == _town_g and town != null:
		# LES BORNES ET LE CHEMIN SE POSENT ICI, a l'armement, et nulle part
		# ailleurs (voir _town_in). _town_in est deja PAD echantillons derriere
		# la tete de fenetre, donc a l'index local 129 quand la voiture est au
		# 12 : 234 m devant elle. _rebuild() re-triangule toute la fenetre a
		# chaque avance, le masque sera donc en place bien avant qu'on y
		# arrive — le trou n'est jamais vu nu.
		_town_in = g - TownPlan.PAD
		_town_out = g + TownPlan.CROSS
		# La courbure sous le panneau est bridee elle aussi : c'est elle qui
		# mene du panneau au premier echantillon simule. L'approche l'a deja
		# ramenee a ~1e-7 (20 echantillons de lissage a 0,4), mais un bourg
		# pose par le filet de main.gd sur le premier echantillon a naitre
		# n'aurait pas eu cette approche — et la premiere ligne de la traversee
		# aurait tourne a MAX_CURVE.
		_curve = clampf(_curve, -TOWN_CURVE, TOWN_CURVE)
		_simulate_town_path()
		var r := _right[_pos.size() - 1]
		town.arm(Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)),
			_pos[_pos.size() - 1]), _town_id)

	_place_props(_pos.size() - 1)
	_head.origin += forward * STEP
	_head = _head.rotated_local(Vector3.UP, _curve * STEP)


func _advance_curve() -> void:
	_until_new_curve -= 1
	if _until_new_curve <= 0:
		_until_new_curve = _rng.randi_range(14, 40)
		_curve_goal = clampf(_rng.randfn(0.0, 0.005), -MAX_CURVE, MAX_CURVE)
	# Lissage : la courbure ne change jamais d'un coup, sinon on sent la cassure.
	_curve = lerpf(_curve, _curve_goal, 0.09)


## LA TRAVERSEE, CALCULEE D'AVANCE. Appele une seule fois par ville, a
## l'armement, quand _head est exactement sur le panneau et _curve deja bridee.
##
## Pourquoi d'avance : la ville a besoin de sa ligne mediane jusqu'a
## _town_out + PAD pour extruder ses chaussees, ses trottoirs et son
## quadrillage, et ces echantillons-la n'existent pas — la tete de fenetre EST
## le panneau. Les tirer maintenant et les ranger, c'est la seule facon que le
## ruban et le bourg posent le MEME point : _append_sample les repose ensuite
## tels quels au lieu de tirer au sort.
##
## On reproduit exactement l'avance de _append_sample (origine + STEP dans le
## sens de la marche, puis rotation locale de curve * STEP). La courbure, elle,
## n'erre PLUS comme celle de la nationale : elle slalome d'un bord a l'autre,
## a la force du plafond, et c'est le seul reglage qui rende la traversee
## conduisible — voir TOWN_WEAVE, qui porte les releves.
##
## Le hasard vient d'un RNG A PART, seme par (nom de la ville, panneau) : le
## chemin d'une ville ne depend pas de combien de fois _rng a servi avant, et
## deux traversees du meme bourg au meme endroit se ressemblent. Le _rng du
## ruban, lui, n'est pas touche — la route d'apres la ville reste celle du
## hasard de la nuit.
func _simulate_town_path() -> void:
	_town_heads.clear()
	_town_curves.resize(0)
	_town_i = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_town_id) * 1000003 + _town_g
	var h := _head
	var curve := _curve
	var goal := 0.0
	var until := 1
	# Le bord de depart est tire, pas choisi : deux bourgs voisins ne se
	# traversent pas du meme geste. Il s'inverse au premier tirage ci-dessous.
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	for k in TownPlan.CROSS + TownPlan.PAD:
		# D'abord l'avance vers l'echantillon suivant, avec la courbure de
		# CELUI QU'ON QUITTE : c'est l'ordre de _append_sample, ou l'avance
		# suit l'ajout. L'inverser decalerait la traversee d'un pas.
		h.origin += -h.basis.z * STEP
		h = h.rotated_local(Vector3.UP, curve * STEP)
		until -= 1
		if until <= 0:
			# LA CONSIGNE CHANGE DE BORD, ELLE N'ERRE PAS (voir TOWN_WEAVE).
			# Le hasard ne decide plus du SENS — il ne decide que de la duree du
			# bord et de sa force. Un tirage centre sur zero rendait une ville
			# sur deux rigoureusement plate ; ici toutes demandent le meme
			# travail, et aucune ne demande le meme dessin.
			until = rng.randi_range(TOWN_WEAVE.x, TOWN_WEAVE.y)
			side = -side
			goal = side * TOWN_CURVE * rng.randf_range(TOWN_WEAVE_FLOOR, 1.0)
		# Le clamp reste, et pas seulement sur le tirage : la consigne est deja
		# dans la fourchette, mais la courbure qui la rejoint part d'une valeur
		# heritee du panneau — et ce sont les 171 echantillons DESSINES qu'on
		# doit garantir, pas le tirage.
		curve = clampf(lerpf(curve, goal, TOWN_SETTLE), -TOWN_CURVE, TOWN_CURVE)
		_town_heads.append(h)
		_town_curves.append(curve)


## Efface la ville du monde de la route : les bornes, le masque, le chemin
## pre-calcule. N'eteint PAS le maillage — l'appelant vient de le faire ou
## sait pourquoi il ne le fait pas.
func _forget_town() -> void:
	_town_in = -1
	_town_out = -1
	_town_ready = false
	_town_heads.clear()
	_town_curves.resize(0)
	_town_i = 0


## La voiture est-elle DANS la ville ? town.gd repond depuis le J3 : contains()
## teste l'enveloppe de son plan, elargie de INSIDE_MARGIN. L'extinction tient
## donc VRAIMENT a ses deux conditions, et plus a la seule premiere.
##
## Ce que le banc en dit, sur vingt lancements de villetest : pendant le
## demi-tour au volant et le retour au panneau, contains() a repondu vrai sur
## TOUTES les images, a chaque lancement, sans une seule exception (LE
## DEMI-TOUR TIENT) — et la ville ne s'est eteinte sur AUCUNE image de la
## traversee, du demi-tour et du retour (LA VILLE NE S'ETEINT PAS DEDANS). Le
## nombre d'images, lui, ne prouve rien et ne se cite que pour l'ordre de
## grandeur : de 963 a 4 140 pour le demi-tour et le retour, de 1 303 a 6 495
## pour l'ensemble, selon les images par seconde du lancement.
func _town_contains(p: Vector3) -> bool:
	if town == null or not town.visible:
		return false
	if town.has_method("contains"):
		return town.contains(p)
	return false


# --------------------------------------------------------------------------
# Ruban
# --------------------------------------------------------------------------

func _rebuild() -> void:
	_mesh.clear_surfaces()

	# LE MASQUE. La ou la ville dessine sa propre traversante, le ruban
	# national ne dessine plus rien : deux chaussees coplanaires au meme
	# Y_ROAD, ce n'est pas une route plus epaisse, c'est du z-fighting en
	# travers des phares.
	#
	# On coupe des QUADS, jamais des sommets (strip.gd) : le trou tombe pile
	# SUR le sommet _pos[_town_in], qui est aussi le premier point de la
	# traversante du bourg — le meme point, donc zero ecart, et rien a
	# renumeroter. Le quad (sf-1 -> sf) est emis, le quad (sf -> sf+1) non.
	#
	# _town_ready garde le tout : tant que la ville n'a pas fini de se batir
	# (ou, aujourd'hui, tant qu'elle ne sait pas se batir du tout), on ne
	# creuse rien. Un trou de quatre images serait pire que la couture.
	_town_ready = _town_in >= 0 and town != null and town.visible \
		and town.has_method("draws_trunk") and town.draws_trunk()
	var sf := -1
	var st := -1
	if _town_ready:
		sf = maxi(_town_in - _index0, 0)
		st = mini(_town_out + TownPlan.PAD - _index0, _pos.size())

	_reset()
	_strip(-(ROAD_HALF + SHOULDER), -ROAD_HALF, Y_SHOULDER, SHOULDER_COLS, sf, st)
	_strip(ROAD_HALF, ROAD_HALF + SHOULDER, Y_SHOULDER, SHOULDER_COLS, sf, st)
	_commit(_mat_shoulder)

	_reset()
	_strip(-ROAD_HALF, ROAD_HALF, Y_ROAD, ROAD_COLS, sf, st)
	_commit(_mat_asphalt)

	_reset()
	var e := ROAD_HALF - LINE_INSET
	_strip(-e - LINE_HALF, -e + LINE_HALF, Y_PAINT, 1, sf, st)
	_strip(e - LINE_HALF, e + LINE_HALF, Y_PAINT, 1, sf, st)
	_dashes(sf, st)
	_commit(_mat_paint)


## Le brin mort d'une fourche : le meme ruban, les memes bandes, dans SON
## maillage — nu, sans pointilles ni props, et il meurt dans le brouillard.
func _rebuild_branch() -> void:
	_branch_mesh.clear_surfaces()
	if _bpos.size() < 2:
		return
	_reset()
	_strip_of(_bpos, _bright, -(ROAD_HALF + SHOULDER), -ROAD_HALF, Y_SHOULDER, SHOULDER_COLS)
	_strip_of(_bpos, _bright, ROAD_HALF, ROAD_HALF + SHOULDER, Y_SHOULDER, SHOULDER_COLS)
	_commit_into(_mat_shoulder, _branch_mesh)
	_reset()
	_strip_of(_bpos, _bright, -ROAD_HALF, ROAD_HALF, Y_ROAD, ROAD_COLS)
	_commit_into(_mat_asphalt, _branch_mesh)
	_reset()
	var e := ROAD_HALF - LINE_INSET
	_strip_of(_bpos, _bright, -e - LINE_HALF, -e + LINE_HALF, Y_PAINT, 1)
	_strip_of(_bpos, _bright, e - LINE_HALF, e + LINE_HALF, Y_PAINT, 1)
	_commit_into(_mat_paint, _branch_mesh)


## Distance de p au plus proche echantillon d'une ligne (2 m de pas : bien
## assez fin pour departager deux chaussees qui s'ecartent).
func _closest_dist(line: PackedVector3Array, p: Vector3) -> float:
	var best := 1.0e18
	for q in line:
		var d := Vector2(p.x - q.x, p.z - q.z).length_squared()
		if d < best:
			best = d
	return sqrt(best)


func _reset() -> void:
	_v.clear()
	_n.clear()
	_f.clear()


## Bande continue entre deux decalages lateraux, le long de toute la route.
## Le corps est dans strip.gd, avec l'enroulement horaire et ce qu'il coute
## de s'y tromper.
##
## (skip_from, skip_to) : les quads d'indices locaux a ne pas emettre — la
## traversee d'un bourg. Par defaut (-1, -1), rien n'est saute.
func _strip(off_a: float, off_b: float, y: float, cols: int,
		skip_from := -1, skip_to := -1) -> void:
	Strip.ribbon(_v, _n, _f, _pos, _right, off_a, off_b, y, cols, skip_from, skip_to)


## La meme bande, sur une ligne quelconque : le brin mort d'une fourche — un
## seul code de geometrie, deux maillages.
##
## skip_from a -1 : le brin mort est dessine ENTIER. Il meurt dans le
## brouillard 80 m plus loin, aucune ville ne peut tomber dessus, il n'y a
## donc rien a masquer.
func _strip_of(pos: PackedVector3Array, right: PackedVector3Array,
		off_a: float, off_b: float, y: float, cols: int) -> void:
	Strip.ribbon(_v, _n, _f, pos, right, off_a, off_b, y, cols, -1, -1)


## Pointilles centraux : un quad par echantillon, un echantillon sur DASH_EVERY.
## On rassemble les quatre coins de chacun — sans leur hauteur, strip.gd la
## pose — et on les verse d'un seul appel.
##
## Le meme masque que le ruban, et pour la meme raison : une ville n'a pas de
## bande centrale au milieu de sa traversante, et un pointille survivant
## flotterait tout seul entre deux trottoirs.
func _dashes(skip_from := -1, skip_to := -1) -> void:
	var corners := PackedVector3Array()
	for i in _pos.size() - 1:
		if (_index0 + i) % DASH_EVERY != 0:
			continue
		if i >= skip_from and i < skip_to:
			continue
		corners.append(_pos[i] - _right[i] * DASH_HALF)
		corners.append(_pos[i] + _right[i] * DASH_HALF)
		corners.append(_pos[i + 1] - _right[i + 1] * DASH_HALF)
		corners.append(_pos[i + 1] + _right[i + 1] * DASH_HALF)
	Strip.quads(_v, _n, _f, corners, Y_PAINT)


func _commit(mat: Material) -> void:
	_commit_into(mat, _mesh)


func _commit_into(mat: Material, mesh: ArrayMesh) -> void:
	Strip.commit(_v, _n, _f, mat, mesh)


# --------------------------------------------------------------------------
# Decor
# --------------------------------------------------------------------------

## Le decor de bord de route, a l'echantillon local i.
##
## ON FILTRE PAR CATEGORIE, ET ON NE SORT JAMAIS DE LA FONCTION. Un `return`
## en tete aurait ete plus court et aurait eteint le PORTAIL DU CAUCHEMAR (le
## dernier bloc), c'est-a-dire la seule sortie du cauchemar : enferme dans le
## rouge parce qu'on a traverse un bourg. Le portail n'est jamais filtre.
##
## Ce que `quiet` retire, et pourquoi : les arbres tombent entre 6,4 et 20,4 m
## de l'axe, exactement la ou la ville pose ses trottoirs et ses facades — ils
## poussent DEJA dans les maisons de town.gd, le brouillard le cache. Les
## poteaux, eux, se plantent a 4,84 m de l'axe : DANS la chaussee du tronc, qui
## fait 8,0 m de demi-emprise. Un poteau telegraphique au milieu de la rue
## principale, qu'on traverse sans le sentir. La police, le geant et
## l'etrangleur n'ont rien a faire dans une rue non plus : un bourg n'est pas
## un bas-cote.
##
## LE SILENCE SE LIT SUR LA PROMESSE, PAS SUR LES BORNES. Il se lisait sur
## _town_in / _town_out, et le banc a compte ce que ca laissait passer :
## 10 a 14 arbres et 2 a 3 poteaux DANS les 171 echantillons que la ville
## dessine, dix fois sur dix. Tous nes dans les 20 d'avant le panneau, aucun
## apres — le decoupage du releve le disait deja, on ne l'avait pas lu.
##
## La raison est une horloge, pas un seuil : les bornes se posent A
## L'ARMEMENT, quand la tete de fenetre atteint le panneau. Or la ville dessine
## PAD echantillons AVANT lui, et ces echantillons-la sont nes 20 pas plus tot,
## quand _town_in valait encore -1. Le filtre ne peut pas remonter le temps.
##
## _town_g, lui, est pose par la navigation ~475 echantillons a l'avance : il
## est connu bien avant que le premier echantillon de la zone ne naisse. On
## calcule donc la zone a partir de LUI — memes bornes exactement, puisque
## _town_in = _town_g - PAD et _town_out = _town_g + CROSS —, et on garde
## l'ancien test en second : _town_g est rendu quand la VOITURE franchit le
## panneau, alors que la fin de la zone (jusqu'a +170) nait encore pendant
## 32 echantillons apres ca. Les deux fenetres se relaient sans laisser de
## trou ; aucune ne suffit seule.
##
## L'autre voie qu'on n'a pas prise : balayer les pools a l'armement et
## eteindre les props deja poses dans la zone. Elle repare au lieu d'empecher,
## et elle coute plus cher qu'il n'y parait — un arbre ne sait pas de quel
## echantillon il vient, il faudrait le SITUER a la distance sur 211
## echantillons ; et il faudrait defaire aussi la police, le geant et
## l'etrangleur, chacun avec son rendez-vous a repousser. Un test de plus dans
## une fonction qui en fait deja six coute une comparaison.
func _place_props(i: int) -> void:
	var g := _index0 + i
	var quiet := _town_g >= 0 \
		and g >= _town_g - TownPlan.PAD - PROP_QUIET \
		and g <= _town_g + TownPlan.CROSS + TownPlan.PAD + PROP_QUIET
	if not quiet:
		quiet = _town_in >= 0 \
			and g >= _town_in - PROP_QUIET \
			and g <= _town_out + TownPlan.PAD + PROP_QUIET

	# Les arbres. Rien a menager dans le tirage : un arbre refuse economise
	# aussi les sept tirages de sa forme, donc la suite du hasard bouge de
	# toute facon des qu'un bourg passe. Autant l'ecrire dans l'ordre ou on le
	# lit — on ne tire pas un arbre qu'on ne posera pas.
	if not quiet and _rng.randf() < 0.55:
		var tree := _trees[_tree_i]
		_tree_i = (_tree_i + 1) % _trees.size()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var off := _rng.randf_range(ROAD_HALF + SHOULDER + 0.6, ROAD_HALF + 17.0)
		tree.position = _pos[i] + _right[i] * (side * off)
		tree.visible = true
		var s := _rng.randf_range(0.75, 1.5)
		tree.scale = Vector3(s * _rng.randf_range(0.8, 1.1), s, s * _rng.randf_range(0.8, 1.1))
		tree.rotation = Vector3(
			_rng.randf_range(-0.04, 0.04),
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.04, 0.04))

	# La cadence des poteaux court meme en ville — on saute la POSE, pas le
	# compte : sinon le premier poteau d'apres le bourg se planterait a
	# l'echantillon suivant la sortie, a 2 m du panneau.
	_since_pole += 1
	if _since_pole >= POLE_EVERY:
		_since_pole = 0
		if not quiet:
			var pole := _poles[_pole_i]
			_pole_i = (_pole_i + 1) % _poles.size()
			var r := _right[i]
			# Traverse perpendiculaire a la route : on aligne X sur le vecteur droite.
			pole.transform = Transform3D(
				Basis(r, Vector3.UP, -Vector3.UP.cross(r)),
				_pos[i] - r * (ROAD_HALF + SHOULDER * 0.6))
			pole.visible = true

	# Voiture de police : a l'echantillon prevu, posee sur l'accotement de droite,
	# dans le sens de la route (France : on roule a droite, elle est garee dans
	# notre sens), le nez un peu vers la chaussee. En ville le rendez-vous
	# ATTEND — elle se posera au premier echantillon apres le bourg, une
	# patrouille a la sortie plutot qu'une patrouille dans un carrefour.
	if g >= _police_next and not police.visible and not quiet:
		var r := _right[i]
		var basis := Basis(r, Vector3.UP, -Vector3.UP.cross(r)).rotated(Vector3.UP, deg_to_rad(POLICE_YAW))
		police.transform = Transform3D(basis, _pos[i] + r * POLICE_OFF)
		police.visible = true
		police.set_process(true)
		police_index = g
		_police_next = g + _rng.randi_range(POLICE_EVERY_MIN, POLICE_EVERY_MAX)

	# Le geant, tapi dans les arbres d'un cote ou de l'autre, tourne vers la
	# route. Il est pose ICI, a 275 m devant la voiture, et il ne bougera pas
	# avant qu'elle soit a 72 m : le temps qu'elle arrive, il fait partie du
	# paysage.
	if monsters and g >= _giant_next and giant_index < 0 and target != null and not quiet:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var r := _right[i]
		var basis := Basis(r, Vector3.UP, -Vector3.UP.cross(r)).rotated(
			Vector3.UP, deg_to_rad(90.0 * side + _rng.randf_range(-25.0, 25.0)))
		giant.transform = Transform3D(basis, _pos[i] + r * (side * GIANT_OFF))
		giant.arm(target)
		giant_index = g

	# L'etrangleur, debout au milieu de la voie, tourne vers la voiture qui
	# vient. Pose a ~275 m devant : le temps que les phares le trouvent, il est
	# la depuis toujours.
	if monsters and g >= _strangler_next and strangler_index < 0 and target != null \
			and not quiet:
		var r := _right[i]
		var basis := Basis(r, Vector3.UP, -Vector3.UP.cross(r)) \
			.rotated(Vector3.UP, PI)
		strangler.transform = Transform3D(basis,
			_pos[i] + r * _rng.randf_range(-STRANGLER_JITTER, STRANGLER_JITTER))
		strangler.arm(target)
		strangler_index = g

	# Le portail du cauchemar : pose en travers de la voie a l'echantillon
	# demande — ou au premier qui nait apres lui, si la fenetre vivante l'a
	# deja depasse quand la demande arrive (la distance est un "au moins").
	#
	# PAS DE `quiet` ICI, ET C'EST LE POINT DE TOUTE LA FONCTION. Le portail est
	# la seule sortie du cauchemar. Le filtrer, ou pire sortir de la fonction
	# plus haut, enfermerait le joueur dans le rouge parce qu'une ville s'est
	# trouvee sur son chemin. Une ville ne bouche pas une porte.
	if _portal_at >= 0 and g >= _portal_at:
		var r := _right[i]
		portal.arm(Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)), _pos[i]))
		portal_index = g
		_portal_at = -1


## L'echantillon global a hauteur de voiture : la distance parcourue, en pas
## de STEP. C'est l'unite des rendez-vous — monstres, portail.
func head_index() -> int:
	return _index0 + BEHIND


# --------------------------------------------------------------------------
# Ce que le reste du jeu a le droit de demander a la route
# --------------------------------------------------------------------------
#
# Tout ce qui suit existe pour une raison simple : personne d'autre n'a a
# tendre la main dans _pos, _town_in ou _closest_dist. GDScript ne dit RIEN
# quand un membre prive change de nom ou de sens — il continue de tourner, et
# c'est le juge de course (taxi.gd) qui se met a noter n'importe quoi, en
# silence, une nuit entiere.


## La voiture est-elle sur la traversee d'un bourg ? Les DEUX bornes, et la
## basse compte autant que la haute : une ville s'arme 234 m devant la
## voiture, et ne regarder que _town_out la mettrait en ville pendant tout ce
## qui reste de nationale avant le panneau.
func in_town() -> bool:
	return _town_in >= 0 and head_index() >= _town_in and head_index() <= _town_out


## Les bornes de la traversee en echantillons globaux, (-1, -1) si aucune
## ville n'est dans le monde. x = premier echantillon dessine par le bourg,
## y = le panneau de sortie.
func town_span() -> Vector2i:
	return Vector2i(_town_in, _town_out)


## L'echantillon global du panneau de sortie (-1 : aucune ville). C'est de la
## que la navigation compte ce qui vient apres le bourg.
func town_exit_g() -> int:
	return _town_out


## A quelle distance d'une chaussee est ce point ? La nationale, et les rues
## du bourg quand il y en a un — le juge de course s'en sert pour savoir si la
## voiture racle le bas-cote, et une rue laterale n'est pas un bas-cote.
##
## town.gd repond depuis le J3, par street_dist, et c'est le MINIMUM des deux
## qui part au juge. Le demi-tour de villetest le montre en une mesure : plein
## braquage a 4 m/s, la voiture s'ecarte a 8,0 m de l'axe du tronc — hors des
## 5,8 m de chaussee plus accotement —, et off_road_dist ne monte qu'a 2,83 a
## 3,08 m selon le lancement (vingt lancements, seuil 5,80). Ces trois
## metres ne viennent pas de la nationale mais de la transversale sur laquelle
## le demi-tour se fait : le temoin du banc pose le meme ecart de 9 m ENTRE deux
## transversales, la ou aucune rue ne repond, et off_road_dist rend 9,00 m.
func off_road_dist(p: Vector3) -> float:
	var d := _closest_dist(_pos, p)
	if town != null and town.visible and town.has_method("street_dist"):
		d = minf(d, town.street_dist(p))
	return d


## LA LIGNE MEDIANE DEJA PARCOURUE, un point tous les 8 m, du plus ancien au
## plus recent. Le GPS en fera le trait de la route derriere nous.
##
## Ce n'est PAS la trajectoire de la voiture : c'est l'AXE DE LA ROUTE. Un
## demi-tour, un ecart, un tour de rond-point n'y laissent rien. La dessiner
## comme une trace de pneus serait un mensonge a l'ecran.
func trail() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(_trail_n)
	var start := (_trail_i - _trail_n + TRAIL_MAX) % TRAIL_MAX
	for k in _trail_n:
		out[k] = _trail[(start + k) % TRAIL_MAX]
	return out


## Un echantillon sort du monde vivant : on le COMPTE, et un sur TRAIL_EVERY
## entre dans la trace. C'est la seule porte — le defile normal y passe, et le
## saut d'index de l'echange aussi (voir _swap_to_branch).
func _retire_trail(p: Vector3) -> void:
	_trail_due -= 1
	if _trail_due <= 0:
		_trail_due = TRAIL_EVERY
		_push_trail(p)


func _push_trail(p: Vector3) -> void:
	_trail[_trail_i] = Vector2(p.x, p.z)
	_trail_i = (_trail_i + 1) % TRAIL_MAX
	_trail_n = mini(_trail_n + 1, TRAIL_MAX)


## Demande un portail a l'echantillon global g (a venir). Le precedent, s'il
## en restait un, s'eteint.
func set_portal(g: int) -> void:
	portal.sleep()
	portal_index = -1
	_portal_at = g


## Eteint tout ce qui vit et repousse les rendez-vous loin devant : le reveil
## du cauchemar. Les monstres ne reviendront que si `monsters` remonte.
func clear_monsters() -> void:
	if not giant.asleep():
		giant.sleep()
	giant_index = -1
	_giant_next = _index0 + SAMPLES + _rng.randi_range(GIANT_EVERY_MIN, GIANT_EVERY_MAX)
	if not strangler.asleep():
		strangler.sleep()
	strangler_index = -1
	_strangler_next = _index0 + SAMPLES \
		+ _rng.randi_range(STRANGLER_EVERY_MIN, STRANGLER_EVERY_MAX)


# --------------------------------------------------------------------------
# Le programme d'arete : ce que la carte demande, la route l'execute
# --------------------------------------------------------------------------

## Une ville a l'echantillon global g (a venir). Le ruban arrive droit
## dessus, le panneau tombe a g, l'evenement part quand la voiture y est.
##
## CETTE FONCTION NE POSE PAS _town_in / _town_out, ET N'EN EFFACE PLUS
## AUCUNE. Elle ne touche qu'a L'ANNONCE, et c'est tout ce qu'elle a le droit
## de toucher.
##
## CE QU'IL Y AVAIT ICI, ET POURQUOI CA NE POUVAIT PAS ETRE JUSTE. Le corps
## commencait par `if town != null and _town_g >= 0: town.sleep();
## _forget_town()`. La garde interrogeait la PROMESSE (« une ville est-elle
## annoncee ? ») et l'action frappait la ville ARMEE (le maillage dans le
## monde, ses deux bornes, son chemin pre-calcule). Ce sont DEUX ETATS
## DIFFERENTS, et ils coexistent pendant 138 echantillons : la ville s'arme
## quand la tete de fenetre atteint son panneau, _town_g n'est rendu que
## quand la VOITURE l'atteint, 276 m plus tard. Dans cette fenetre-la,
## reprogrammer eteignait un bourg que le joueur avait deja sous les yeux.
##
## Pire cas encore, et celui qui rend la garde franchement fausse : la
## navigation annonce la ville SUIVANTE a l'instant ou le panneau de la
## courante est franchi. Passe cet instant, _town_g decrit B pendant que
## _town_in / _town_out decrivent A, qu'on est en train de traverser. Un
## deuxieme appel — reprogrammer B en C — lisait « B est promise » et
## eteignait A sous les phares. La navigation d'aujourd'hui ne fait jamais ce
## deuxieme appel : ce code n'a donc jamais rien eteint, et n'aurait jamais pu
## rien eteindre d'utile. Mort ou destructeur, jamais entre les deux.
##
## Ce qu'on garde de son intention : une ville ARMEE ne s'annule pas. Elle est
## dans le monde. C'est l'extinction par le bout (130 m derriere, et pas dans
## le bourg) qui la range, et elle seule. Une ville seulement PROMISE, elle,
## n'a aucune emprise sur le ruban — ni maillage, ni bornes, ni chemin — donc
## la remplacer, c'est exactement ecrire les deux lignes ci-dessous.
func program_town(g: int, id: String) -> void:
	_town_g = g
	_town_id = id


## LE CAUCHEMAR ANNULE LA CARTE. La ville PROMISE ne viendra pas : dans le
## rouge, la navigation n'a plus cours.
##
## Celle qui est deja ARMEE reste. Elle est dans le monde, a 276 m devant, et
## l'eteindre serait le meme pop voyant que program_town s'interdit — sauf
## qu'ici il tomberait au moment ou le joueur s'endort. On la noircit si elle
## sait le faire (town.gd du J3 : lumieres eteintes, fenetres mortes) : une
## ville qu'on connait, traversee dans le noir absolu, est une image que rien
## d'autre ne donne.
func suspend_town() -> void:
	_town_g = -1
	_town_id = ""
	if town != null and town.visible and town.has_method("set_dark"):
		town.set_dark(true)


## Un Y a l'echantillon global g : le cote gauche mene a left_id, le droit a
## right_id, et le ruban VIVANT continue du cote main_side — l'autre devient
## le brin mort. La voiture tranche au volant dans la fenetre.
##
## g est un PLANCHER, pas un rendez-vous, et c'est tout le sujet. Le Y ne
## tient que si le ruban vivant file DROIT du panneau (FORK_SIGN_AT, 90 m
## avant) jusqu'au bout du raccord — et un echantillon DEJA POSE ne se
## redresse plus. Or la fenetre vivante est batie 138 echantillons (276 m)
## devant la voiture : un Y demande plus pres tombait entierement dans le
## deja-bati, et le redressement ne mordait sur rien.
##
## Ce que ca donnait, releve au banc (maptest, avant ce correctif) : Y demande
## a +60 echantillons, pose a +137 ; le ruban tournait encore a 0,87 deg par
## PAS sous la fourche elle-meme ; le panneau se plantait SUR le Y au lieu de
## 90 m avant ; et une voiture qui rendait le volant au panneau se retrouvait
## a 8,4 m de l'axe au bout de la fenetre — hors de la chaussee ET de
## l'accotement (5,8 m). Elle n'avait pas choisi une sortie, elle avait rate
## un virage ; une fois sur trois le jeu comptait ca comme "il a pris a
## droite". PRENDRE UNE SORTIE ETAIT UN TIRAGE AU SORT.
##
## On repousse donc le Y au premier echantillon a naitre, plus les 90 m du
## panneau : 183 echantillons, 366 m devant la voiture, releves au banc.
##
## Ce que ca coute, et qu'il faut savoir : le Y ne tombe plus ou la navigation
## croit le poser — main.gd le demande 120 m apres le bourg
## (FORK_AFTER_TOWN_M) et il sort a 366 m ; l'arete mesure d'autant plus long.
## Elle mesurait deja trop avant (274 m au lieu de 120 : le Y tombait sur le
## premier echantillon a naitre), la constante n'a donc jamais decrit le
## monde. fork_index() rend la position VRAIE : c'est a elle que la navigation
## doit compter le reste de l'arete, pas a sa constante.
##
## LE DEUXIEME PLANCHER : LA TRAVERSEE D'UN BOURG COMPTE COMME DU DEJA-BATI.
## Les echantillons de la traversee ne sont pas encore nes, mais ils sont
## DECIDES — la ville s'est batie dessus, et rien ici n'a le droit de les
## redresser sans decoudre la traversante. Or main.gd demande le Y a l'instant
## meme ou le panneau du bourg est franchi, et le premier plancher ne regardait
## que le deja-NE.
##
## Les chiffres, releves au banc (maptest, premier Y, Corbeny) : Y demande a
## 549, premier plancher a 672, donc panneau du Y a 627 — quand la traversee
## dessinee court jusqu'a 638. DOUZE ECHANTILLONS de la zone qui doit etre
## RIGOUREUSEMENT droite tombaient dans la ville.
##
## Ce qu'ils coutaient : 24 m a 0,0015 rad/m font 0,036 rad de cap ; sur les
## ~120 m qui restent jusqu'au verdict, la voiture qui a rendu le volant au
## panneau derive de ~4,8 m — pour 2,2 m qui tranchent le Y. Releve : maptest
## perdait « LE COTE VIVANT MENE » deux fois sur vingt-deux lancements, la
## voiture partant sur le brin mort sans que personne ait touche au volant. La
## meme faute que le premier plancher, par une autre porte.
##
## On repousse donc aussi d'un echantillon apres la fin de la traversee, plus
## les 90 m du panneau : Y a 684, panneau a 639, la ville finit a 638. Sans
## ville en cours, cette ligne ne mord sur rien.
##
## ET LA CONDITION TIENT SUR _town_out SEUL, depuis qu'on a compte ce qui la
## tenait vraiment. Elle demandait EN PLUS que le chemin pre-calcule ne soit
## pas epuise (_town_i < _town_heads.size()). Ce qui rendait ce test vrai a
## l'instant ou main.gd demande le Y — le panneau du bourg franchi par la
## voiture — n'etait pas un raisonnement mais une soustraction : la tete de
## fenetre est alors a CROSS + PAD - (SAMPLES - BEHIND) = 150 - 138 = DOUZE
## echantillons de la fin du dessin. Douze, produit de quatre constantes
## reparties sur deux fichiers. PAD a 8, ou SAMPLES a 162, et le test passait
## a faux : le second plancher s'effacait SANS UN MOT, la zone qui doit etre
## rigoureusement droite retombait dans la ville, et on repayait les deux
## « LE COTE VIVANT MENE » perdus sur vingt-deux lancements.
##
## Le retirer ne coute rien, et c'est verifiable : quand le chemin EST epuise,
## la fenetre est deja nee jusqu'a _town_out + PAD au moins, donc le premier
## plancher (tete de fenetre + 45) domine deja _town_out + PAD + 1 + 45. Le
## second ne peut mordre que la ou il doit mordre.
func program_fork(g: int, left_id: String, right_id: String,
		main_side: String) -> void:
	_clear_fork()
	var floor_g := _index0 + _pos.size() + FORK_SIGN_AT
	if _town_out >= 0:
		floor_g = maxi(floor_g, _town_out + TownPlan.PAD + 1 + FORK_SIGN_AT)
	_fork_g = maxi(g, floor_g)
	_fork_left = left_id
	_fork_right = right_id
	_fork_main = main_side
	_fork_state = ""


func fork_state() -> String:
	return _fork_state


## Ou le Y tombe VRAIMENT (-1 : aucun). program_fork repousse la demande
## quand elle vise du deja-bati : c'est ce nombre-la qui fait foi, pas celui
## qu'on a demande.
func fork_index() -> int:
	return _fork_g


## Le brin mort : la SORTIE. Il diverge du cote oppose au vivant (qui file
## droit), se detend, et s'arrete a BRANCH_LEN — 80 m, la moitie de ce que
## le brouillard laisse voir, et il s'incurve pour derober sa fin.
func _grow_branch() -> void:
	_bpos = PackedVector3Array()
	_bright = PackedVector3Array()
	var h := _bhead
	var curve := -2.0 * FORK_BEND * (1.0 if _fork_main == "left" else -1.0)
	for i in BRANCH_LEN:
		var fwd := -h.basis.z
		h.origin += fwd * STEP
		h = h.rotated_local(Vector3.UP, curve * STEP)
		if i > 18:
			curve = lerpf(curve, 0.0, 0.12)
		fwd = -h.basis.z
		_bpos.append(h.origin)
		_bright.append(fwd.cross(Vector3.UP).normalized())
	# La tete de reprise vit UN PAS AU-DELA du dernier point — comme dans
	# _append_sample, ou l'avance suit l'ajout. La ranger SUR le dernier
	# point dupliquait l'echantillon a l'echange : un segment de longueur
	# nulle, une normale en 0/0 et un faux virage de 90 degres au releve.
	h.origin += -h.basis.z * STEP
	_bhead_end = h
	_rebuild_branch()


## L'ECHANGE. La voiture est passee sur la sortie : la fenetre vivante
## REPART du brin, depuis l'echantillon sous la voiture — et l'ANCIENNE
## fenetre entiere (le troncon d'avant la fourche PLUS la continuation qu'on
## n'a pas prise, d'un seul tenant) devient le decor de la route qu'on
## quitte. Rien n'a besoin de l'echantillon de fourche : il peut etre sorti
## de la fenetre depuis longtemps — c'etait le piege de la premiere version,
## BEHIND ne garde que 24 m derriere la voiture et l'echange n'etait
## geometriquement possible que onze echantillons durant.
func _swap_to_branch() -> void:
	var j := _closest_index(_bpos, target.global_position)
	var start := maxi(j - BEHIND, 0)
	var old_p := _pos
	var old_r := _right
	# LES ECHANTILLONS QUE LE SAUT ENJAMBE. Quand la voiture tranche TOT — moins
	# de BEHIND echantillons apres la fourche —, `start` bute sur zero et la
	# nouvelle fenetre demarre DEVANT l'ancienne : ces echantillons-la ne
	# sortiront jamais par l'arriere, et personne ne les rangera. Ils ont
	# pourtant ete roules, c'est le tronc jusqu'a la fourche.
	#
	# Sans ca, la trace sautait a 14,00 m entre deux points au lieu de 8,00 —
	# non plus un point perdu (la cadence, elle, est reparee) mais six metres
	# d'axe absents. On les fait sortir par la meme porte, dans l'ordre.
	var new_i0 := _fork_g + 1 + start
	for k in range(0, clampi(new_i0 - _index0, 0, old_p.size())):
		_retire_trail(old_p[k])
	_pos = _bpos.slice(start)
	_right = _bright.slice(start)
	# L'index global repart de la fourche : la METRIQUE continue — a un pas
	# pres, et le pas fait deux metres.
	_index0 = new_i0
	_head = _bhead_end
	_curve = 0.0
	_curve_goal = 0.0
	# La traversee pre-calculee decrivait le ruban qu'on vient de quitter : sur
	# le brin, elle ne veut plus rien dire. En pratique elle est deja vide (le
	# plancher de program_fork tient le Y 33 echantillons au-dela de la fin du
	# dessin de la ville), et c'est bien pour ca qu'on peut la jeter sans
	# menager personne — mais un chemin survivant a un echange reposerait des
	# tetes de l'ancienne route sur la nouvelle, et la route sauterait.
	_town_heads.clear()
	_town_curves.resize(0)
	_town_i = 0
	_bpos = old_p
	_bright = old_r
	_rebuild_branch()
	while _pos.size() < SAMPLES:
		_append_sample()
	_rebuild()
	_fork_state = "done"
	var side := "right" if _fork_main == "left" else "left"
	fork_committed.emit(side, _fork_left if side == "left" else _fork_right)


func _closest_index(line: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var bd := 1.0e18
	for i in line.size():
		var d := Vector2(p.x - line[i].x, p.z - line[i].z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


func _clear_fork() -> void:
	_fork_g = -1
	_fork_state = ""
	_bpos = PackedVector3Array()
	_bright = PackedVector3Array()
	_branch_mesh.clear_surfaces()
	if _fork_sign != null:
		_fork_sign.visible = false


## Le panneau en Y : un poteau, deux toles inclinees, les deux noms — la
## meme tole et la meme peinture que les panneaux de ville (town.gd).
func _build_fork_sign() -> Node3D:
	var mat_metal := Retro.mat(Color(0.10, 0.11, 0.13), 0.5)
	var mat_pole := Retro.mat(Color(0.055, 0.055, 0.06), 0.9)
	var root := Node3D.new()
	root.name = "ForkSign"
	root.visible = false
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.05
	pcyl.bottom_radius = 0.06
	pcyl.height = 2.9
	pole.mesh = pcyl
	pole.material_override = mat_pole
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position = Vector3(0.0, 1.45, 0.0)
	root.add_child(pole)
	for spec in [["PlateL", 2.55, 24.0], ["PlateR", 1.95, -24.0]]:
		var plate := Node3D.new()
		plate.name = spec[0]
		plate.position = Vector3(0.0, spec[1], 0.0)
		plate.rotation_degrees.y = spec[2]
		root.add_child(plate)
		var tin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 0.5, 0.04)
		tin.mesh = box
		tin.material_override = mat_metal
		tin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plate.add_child(tin)
		var label := Label3D.new()
		label.name = "Name"
		label.text = "?"
		label.font_size = 52
		label.pixel_size = 0.004
		label.modulate = Color(0.72, 0.74, 0.70)
		label.position = Vector3(0.0, 0.0, 0.035)
		plate.add_child(label)
	return root


func _arm_fork_sign(i: int) -> void:
	if _fork_sign == null:
		return
	(_fork_sign.get_node("PlateL/Name") as Label3D).text = _fork_left.to_upper()
	(_fork_sign.get_node("PlateR/Name") as Label3D).text = _fork_right.to_upper()
	var r := _right[i]
	_fork_sign.global_transform = Transform3D(
		Basis(r, Vector3.UP, -Vector3.UP.cross(r)),
		_pos[i] + r * (ROAD_HALF + SHOULDER + 0.4))
	_fork_sign.visible = true


## Pose (centre de la chaussee, face a la route) a l'echantillon global g, ou
## l'identite s'il n'est plus dans la fenetre vivante. Sert aux bancs d'essai.
func sample_at(g: int) -> Transform3D:
	var i := g - _index0
	if i < 0 or i >= _pos.size():
		return Transform3D()
	var r := _right[i]
	return Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)), _pos[i])


func _build_prop_pools() -> void:
	police = PoliceCar.new()
	police.name = "PoliceCar"
	police.visible = false
	police.set_process(false)
	add_child(police)

	# Un seul portail : arme au fond du cauchemar, rendormi au reveil.
	portal = PortalScript.new()
	portal.name = "Portal"
	add_child(portal)

	# Une seule ville a la fois (comme la police), le maillage du brin mort,
	# et le panneau en Y — le decor du graphe (map.gd).
	town = TownScript.new()
	town.name = "Town"
	add_child(town)

	_branch_mi = MeshInstance3D.new()
	_branch_mi.name = "Branch"
	_branch_mi.mesh = _branch_mesh
	_branch_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_branch_mi)

	_fork_sign = _build_fork_sign()
	add_child(_fork_sign)

	# Un seul geant, reutilise : il n'y en a jamais deux a la fois.
	giant = GiantScript.new()
	giant.name = "Giant"
	add_child(giant)

	# Un seul etrangleur aussi. Il change de parent quand il s'accroche a la
	# voiture, et revient ici en s'eteignant.
	strangler = StranglerScript.new()
	strangler.name = "Strangler"
	add_child(strangler)

	for i in TREE_COUNT:
		var tree := Node3D.new()
		tree.visible = false
		add_child(tree)
		_add_mesh(tree, _mesh_trunk, _mat_bark, Vector3(0.0, 1.6, 0.0))
		_add_mesh(tree, _mesh_crown, _mat_leaf, Vector3(0.0, 5.6, 0.0))
		_trees.append(tree)

	for i in POLE_COUNT:
		var pole := Node3D.new()
		pole.visible = false
		add_child(pole)
		_add_mesh(pole, _mesh_pole, _mat_pole, Vector3(0.0, 3.75, 0.0))
		_add_mesh(pole, _mesh_crossarm, _mat_pole, Vector3(0.0, 7.1, 0.0))
		_poles.append(pole)


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _build_resources() -> void:
	_mat_asphalt = Retro.mat(Color(0.085, 0.086, 0.094), 0.55, 0.10)
	_mat_shoulder = Retro.mat(Color(0.060, 0.058, 0.052), 0.94)
	_mat_paint = Retro.mat(Color(0.58, 0.56, 0.50), 0.70)
	_mat_bark = Retro.mat(Color(0.075, 0.068, 0.058), 0.96)
	_mat_leaf = Retro.mat(Color(0.038, 0.045, 0.036), 0.96)
	_mat_pole = Retro.mat(Color(0.085, 0.082, 0.076), 0.86)

	_mesh_trunk = CylinderMesh.new()
	_mesh_trunk.top_radius = 0.10
	_mesh_trunk.bottom_radius = 0.17
	_mesh_trunk.height = 3.2
	_mesh_trunk.radial_segments = 6
	_mesh_trunk.rings = 3

	# Sapin mort : un cone tres etroit, parfait dans le brouillard.
	_mesh_crown = CylinderMesh.new()
	_mesh_crown.top_radius = 0.0
	_mesh_crown.bottom_radius = 1.15
	_mesh_crown.height = 6.5
	_mesh_crown.radial_segments = 7
	_mesh_crown.rings = 5

	_mesh_pole = CylinderMesh.new()
	_mesh_pole.top_radius = 0.09
	_mesh_pole.bottom_radius = 0.13
	_mesh_pole.height = 7.5
	_mesh_pole.radial_segments = 6
	_mesh_pole.rings = 6

	_mesh_crossarm = BoxMesh.new()
	_mesh_crossarm.size = Vector3(1.5, 0.09, 0.09)
	_mesh_crossarm.subdivide_width = 4
