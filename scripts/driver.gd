extends Node3D
##
## Le conducteur : corps visible depuis la vue subjective, bras resolus en
## IK 2 os, mains posees sur les commandes.
##
## Le corps vient du modele Blender civic_driver.glb (build_civic_driver.py),
## decoupe en segments modelises chacun dans le repere que ce script anime :
## origine a l'articulation proximale, axe -Z vers l'articulation distale pour
## les bras et les jambes ; repere du volant pour les mains ; cheville pour les
## pieds ; SPINE pour le buste (tete comprise, masquee en vue subjective).
## _set_bone etire chaque segment le long de -Z pour coller a la longueur de
## l'os (REST_LEN = longueur de modelisation).
##
## Il ne FABRIQUE pas le volant, le levier ni le frein a main : ceux-ci
## viennent du modele de l'habitacle (cabin.gd), qui lui passe leurs pivots via
## use_controls(). Le conducteur ne fait plus que les faire bouger et y
## accrocher ses mains.
##
## Position de conduite d'une Civic EF : on est assis BAS, jambes tendues.
##

const DRIVER := preload("res://assets/models/civic_driver.glb")
## Facteur applique aux albedos du .glb : meme palette de nuit que l'habitacle.
const BODY_DIM := 0.66
## Longueurs de modelisation des segments (civic_dims.py).
const REST_LEN := {"ArmUpper": 0.30, "Forearm": 0.28, "Thigh": 0.50, "Shin": 0.48}

## Couche de rendu du corps, hors de celle que regardent les miroirs.
## Voir _set_layer() et mirror.gd.
const DRIVER_LAYER := 2

const SEAT_X := -0.33

const WHEEL_RADIUS := 0.180        # rayon de prehension de la jante
const GRIP_ANGLE := 30.0           # mains a 10 h 10 : degres au-dessus de l'horizontale
## Rayons de prise (m) : jante, pommeau, poignee de frein a main, haut de portiere.
const WHEEL_GRIP_R := 0.0165
const KNOB_GRIP_R := 0.024
const HB_GRIP_R := 0.015
const DOOR_GRIP_R := 0.020
## Poses de doigts du modele (civic_hand.POSES) : rayon de barre de chaque pose.
const POSE_NAMES := ["g10", "g16", "g25", "g32"]
const POSE_RADII := [0.010, 0.0165, 0.025, 0.032]
## Direction, dans le repere de la main, qui s'eloigne de la paume (voir held_offset).
## Main ouverte sur un pare-soleil / retroviseur : les bouts des doigts sont a
## FINGER_REACH de l'origine (sous la paume) ; les doigts se replient un peu sur
## le bord (PANEL_CLOSE, fraction de la pose de prise la plus serree).
const FINGER_REACH := 0.06
## Direction des doigts tendus dans le repere de la main (voir PALM_AWAY).
const FINGER_DIR_L := Vector3(-0.7071, -0.7071, 0.0)
const FINGER_DIR_R := Vector3(0.7071, -0.7071, 0.0)
const PANEL_CLOSE := 0.3
const PALM_AWAY_L := Vector3(0.7071, -0.7071, 0.0)
const PALM_AWAY_R := Vector3(-0.7071, -0.7071, 0.0)
## Degres de rotation du volant a plein braquage, d'un cote. 270, soit trois
## quarts de tour, 540 de butee a butee : une direction courte, de voiture qui
## se pilote. 110 etait une course de jouet — un quart de tour en tout et pour
## tout, alors que les roues, elles, allaient bien jusqu'a leurs 30 degres
## (cabin.WHEEL_STEER_MAX).
##
## Surtout PAS 360 ni un multiple : un tour complet ramene la jante et le logo
## du moyeu exactement dans la position du volant droit, et plein braquage
## devient impossible a distinguer du centre d'un coup d'oeil. A 270 la butee
## tombe a un quart de tour de cette ambiguite, et se lit sans hesitation.
## Au-dela, les deux tours et demi d'une Civic d'origine ne tiennent de toute
## facon pas : les bras finiraient croises dans le buste.
const WHEEL_MAX_ANGLE := 270.0
## --- enchainement de prises ------------------------------------------------
## Les mains suivent la jante AU DEGRE PRES tant qu'elles la tiennent. Au bout
## de sa course, une main LACHE, passe au-dessus de la jante et se repose plus
## loin pendant que l'autre tient — c'est ce qui permet d'aller jusqu'aux 270
## degres de WHEEL_MAX_ANGLE sans qu'un bras ait a faire trois quarts de tour.
##
## Deux butees par main, parce que le geste n'est pas symetrique : celle qui
## TIRE (la gauche qui descend vers 7 h en braquant a gauche) travaille dans
## l'axe de son epaule et va loin ; celle qui POUSSE traverse devant le buste et
## est en bout de bras bien avant. C'est cette difference qui fait ALTERNER les
## deux mains au lieu de les faire lacher ensemble : a partir de 10 h 10, la
## main qui pousse arrive en butee GRIP_PULL - GRIP_PUSH degres de volant avant
## l'autre, et l'ecart se conserve d'une prise a la suivante.
##
## Les deux valeurs sont MESUREES, pas devinees : `-- wheeltest` imprime la
## portee epaule -> poignet le long de la jante. Descendre de son cote ne coute
## rien (la main droite est plus pres de son epaule a 4 h qu'a 10 h 10, 0,63 m
## contre 0,65) ; traverser coute 2 cm tous les 25 degres, et c'est ce qui borne
## GRIP_PUSH. En dessous de 65 la main lacherait dans un virage de route
## ordinaire, ce qu'aucun conducteur ne fait.
const GRIP_PULL := 105.0
const GRIP_PUSH := 65.0
## Marge gardee a la reprise : on ne se repose pas pile sur sa butee opposee,
## sinon la main relacherait des le degre suivant. La course utile d'une prise
## vaut donc GRIP_PULL + GRIP_PUSH - REGRIP_MARGIN.
const REGRIP_MARGIN := 15.0
## Duree du transfert, jante lachee -> main reposee dessus. Elle se raccourcit
## quand on braque vite : c'est ce qu'on fait, et surtout c'est ce qui permet a
## la SECONDE main de partir a son tour. Un transfert de duree fixe tenait la
## main suivante bloquee 180 ms a plein braquage — le volant tournait de 85
## degres pendant qu'elle attendait, et elle finissait au fond de sa reserve.
const REGRIP_TIME := 0.26
const REGRIP_TIME_MIN := 0.13
## Vitesse de rotation (deg/s) au-dela de laquelle le geste presse le pas.
const REGRIP_HURRY := 250.0
## De combien la main s'ecarte de la jante en passant (m, vers le conducteur :
## on passe la main AU-DESSUS du volant, on ne la fait pas glisser dedans), et
## de combien les doigts s'ouvrent au passage.
##
## C'est ce retrait, et lui seul, qui separe les mains quand elles se croisent —
## et elles se croisent forcement, c'est le geste. A 45 mm le banc les relevait
## a 16 mm l'une de l'autre, c'est-a-dire l'une DANS l'autre.
const REGRIP_LIFT := 0.085
const REGRIP_OPEN := 0.85
## Quand l'autre main n'est pas libre de prendre le relais — elle est au levier,
## au frein a main, sur l'appui-tete, a la portiere ou elle tient un objet — la
## main qui reste ne peut PAS lacher : la jante file alors sous sa paume,
## comprimee en tangente hyperbolique vers cette reserve, jamais atteinte.
## Sans elle, a plein braquage le coude se retournerait.
const GRIP_RESERVE := 30.0
## Au-dela de ce fondu, une main partie ailleurs ne compte plus comme une prise.
const BUSY_LET_GO := 0.35
## Ecart minimum entre les deux mains sur la jante (degres). On ne se repose pas
## la ou l'autre main SERA : pendant qu'une main traverse, l'autre continue de
## descendre avec la jante, et la cible calculee au depart peut se retrouver
## pile sous elle. Le banc les relevait alors a 49 mm l'une de l'autre — soit
## l'une dans l'autre. 45 degres de jante, c'est 14 cm de separation.
const GRIP_SEPARATION := 45.0
## Ecart entre les deux positions de repos (10 h 10) : deux fois GRIP_ANGLE plus
## les 180 degres qui separent 9 h de 3 h. Sert a comparer les deux mains, qui
## comptent chacune leurs angles depuis SA position de repos.
const GRIP_ANCHOR_GAP := 180.0 - 2.0 * GRIP_ANGLE
## En dessous de cette vitesse de rotation (rad/s), le volant est pose.
##
## IL N'Y A PAS DE RANGEMENT AUTOMATIQUE DES MAINS. Une main qui ne tourne pas
## reste agrippee la ou elle tient, meme de travers — c'est ce qu'on fait, et
## une main qui se replace toute seule pendant qu'on ne tourne pas se remarque
## immediatement. Ce qui les ramene a 10 h 10 apres une manoeuvre, c'est le
## volant qui rentre et leur file sous les paumes (SLIP_HOME).
##
## Ce seuil ne sert donc qu'a une chose : savoir si une prise se prend POUR LA
## SUITE d'un mouvement, ou s'il n'y a plus de suite.
const WHEEL_STILL := 0.35

## --- le volant qui revient tout seul ---------------------------------------
## Sortie de virage, on ne RAMENE pas le volant : on desserre les doigts et on
## le laisse filer sous les paumes, rendu au centre par le couple d'auto-
## alignement des roues (car.gd, `steer_return`). Les mains, elles, rentrent a
## 10 h 10 a leur propre rythme, sans rapport avec la vitesse de la jante — c'est
## exactement ce qui distingue un volant rendu d'un volant tourne.
##
## `wheel_slip` est ecrit par car.gd : vrai quand le rappel agit et que le joueur
## ne braque pas. Le glissement ne s'invente pas ici, il se lit dans la commande.
const SLIP_HOME := 2.5             # vitesse de retour des mains a 10 h 10 (1/s)
const SLIP_OPEN := 0.45            # de combien les doigts se desserrent
const SLIP_SMOOTH := 7.0           # lissage de l'entree, pour ne pas claquer

## --- conduire une main prise ------------------------------------------------
## Une canette, une arme : la main libre ne peut plus enserrer la jante — on
## conduit PAUME A PLAT dessus, et on la fait tourner par appui. La paume repose
## sur la face du volant tournee vers le conducteur, d'ou ce decalage : l'origine
## de la main est au centre de la barre qu'elle tient normalement, il faut la
## sortir du tube pour la poser dessus.
const PALM_LIFT := 0.020
## Fermeture des doigts dans cette pose : detendus, pas ouverts en croix.
const FLAT_CLOSE := 0.12
## Mais on ne conduit a plat que PENDANT qu'on tourne : passe ce delai sans que
## la jante bouge, la main libre REFERME LES DOIGTS DESSUS et la tient, comme
## n'importe quelle main au volant.
##
## Le delai n'est pas la pour faire joli, il evite que la main ouvre et referme
## entre deux corrections de trajectoire. Mais une demi-seconde se voyait comme
## une hesitation : on referme la main sur un volant des qu'on cesse de le
## tourner, pas apres reflexion. 0,2 s de silence de la jante, plus le fondu,
## et la prise est reprise en un tiers de seconde.
const FLAT_GRAB_DELAY := 0.2
const FLAT_SMOOTH := 9.0
## Et dans l'AUTRE SENS, ce n'est pas une question de temps mais de CHEMIN : la
## main ne s'ouvre qu'apres ce nombre de degres de jante parcourus depuis
## qu'elle s'est agrippee. Une main posee sur un volant ne se remet pas a plat
## parce qu'il a bouge — elle le fait quand le mouvement s'installe, et une
## correction de trajectoire n'est pas un mouvement qui s'installe.
##
## Le compteur repart de zero des que la jante se tait : il faut de nouveau tout
## ce chemin-la, sinon une suite de petites corrections finirait par l'ouvrir.
const FLAT_TURN_TRAVEL := 40.0
## S'ouvrir se fait plus lentement que se refermer. On lache une prise sans y
## penser ; on la reprend d'un coup.
const FLAT_OPEN_SMOOTH := 4.0

const LEVER_SIDE_ANGLE := 13.0     # debattement lateral de la grille
const LEVER_LONG_ANGLE := 12.0     # debattement avant/arriere
## Grille en H, indices alignes sur GEAR_NAMES de car.gd : R N 1 2 3 4 5.
## x : -1 gauche / +1 droite.  y : +1 vers l'avant / -1 vers l'arriere.
const GEAR_GATE := [
	Vector2(1.0, -1.0),    # R
	Vector2(0.0, 0.0),     # N
	Vector2(-1.0, 1.0),    # 1
	Vector2(-1.0, -1.0),   # 2
	Vector2(0.0, 1.0),     # 3
	Vector2(0.0, -1.0),    # 4
	Vector2(1.0, 1.0),     # 5
]

## Le modele Blender est pose levier de frein BAISSE : on applique donc un
## DELTA de rotation, pas un angle absolu.
const HB_TRAVEL := 34.0            # degres entre baisse et tire
const HB_GESTURE := 0.75           # duree du geste de la main, aller-retour

## Dos cale contre le dossier (face avant a z=0.410 dans le .glb) : l'articulation
## de l'epaule est une dizaine de centimetres devant, soit 0.30.
const SHOULDER_L := Vector3(SEAT_X - 0.185, 0.95, 0.30)
const SHOULDER_R := Vector3(SEAT_X + 0.185, 0.95, 0.30)
## Rallonges de 3 et 4 cm en meme temps qu'on recule le buste. Sans elles la
## jante est a 70 cm pour 62 cm de bras : _solve_elbow bute en butee et
## _set_bone etire l'avant-bras pour rattraper — bras de gorille.
const UPPER_ARM := 0.30
const FOREARM := 0.28

## Axe vertical du buste : c'est autour de lui qu'on pivote pour se retourner.
const SPINE := Vector3(SEAT_X, 0.0, 0.44)
const TWIST_MAX := 40.0
## Et penche : le dos ne s'appuie plus nulle part, le buste S'ENROULE AUTOUR DU
## SIEGE. 95 degres, c'est le chiffre qui fait passer l'epaule droite DERRIERE
## le plan du dossier (z 0.53) au lieu de la laisser coincee devant : elle
## tombe a (-0.21, 0.64) contre (-0.15, 0.57) a 70. C'est ce qui donne acces a
## ce qui traine derriere son propre siege — sinon le bras bute sur le dossier.
##
## Ce sont aussi les 95 degres qui, avec les 95 du cou, couvrent les 190 que la
## tete s'autorise alors (car.lean_yaw_bonus), au lieu de tout faire porter a la
## nuque. Un buste assis ne se vrille pas comme ca ; un buste qui a quitte son
## dossier pour aller chercher derriere, si.
const TWIST_MAX_LEAN := 95.0
## Et le pivot recule vers le dossier : on ne se vrille pas sur place, on
## contourne le siege. Sans ce recul, l'epaule tourne autour d'un axe place
## DEVANT le dossier et revient vers l'avant au lieu de passer derriere.
const SPINE_WRAP := Vector3(SEAT_X, 0.0, 0.56)
const HEADREST_GRIP := Vector3(0.23, 1.14, 0.47)
## De combien le buste accompagne le bras qui va chercher un objet. Sans ca
## l'epaule reste en arriere et le bras bute en butee de longueur : le paquet
## sur le siege passager est a 63 cm de l'epaule, pour 62 cm de bras.
const REACH_LEAN := 0.13
## Et de combien il s'y autorise quand on est DEJA penche. Le dos a quitte le
## dossier : le buste est en porte-a-faux, libre d'aller chercher les 20 cm qui
## manquent au fond de la voiture. C'est ce qui met la banquette a portee.
const REACH_LEAN_OFF_SEAT := 0.30
const DOOR_GRIP := Vector3(-0.87, 0.98, -0.26)
const LEAN_OUT := Vector3(-0.30, -0.02, -0.02)

## --- se pencher (car.gd, clic droit maintenu) ------------------------------
## Le buste suit la tete, un peu en retrait : le cou s'allonge de sa part a lui,
## et le bassin ne fait qu'un quart du chemin — on se penche depuis les hanches,
## on ne quitte pas le siege. Les pieds, eux, ne bougent pas des pedales.
const LEAN_BODY := 0.85
const LEAN_HIP := 0.25
## Debattement a pleine amplitude (m) : c'est `lean_reach` de car.gd. Sert a
## ramener le vecteur recu a un 0..1, dont tout le reste depend.
const LEAN_FULL := 0.42

## Bassin dans le creux du siege, la ou l'assise rejoint le dossier. Les genoux
## reculent d'autant, sinon la cuisse s'allonge de 10 cm.
const HIP_L := Vector3(SEAT_X - 0.12, 0.50, 0.40)
const HIP_R := Vector3(SEAT_X + 0.12, 0.50, 0.40)
const KNEE_L := Vector3(SEAT_X - 0.13, 0.50, -0.14)
const KNEE_R := Vector3(SEAT_X + 0.12, 0.50, -0.14)
const ANKLE_L := Vector3(SEAT_X - 0.19, 0.40, -0.66)
const ANKLE_R := Vector3(SEAT_X + 0.09, 0.40, -0.68)
const BRAKE_X := SEAT_X - 0.06     # ou glisse le pied droit pour freiner

# Commandes empruntees au modele Blender.
var wheel_tilt: Node3D
var wheel_spin: Node3D
var lever: Node3D
var handbrake_lever: Node3D
var _knob_local := Vector3.ZERO
var _grip_local := Vector3.ZERO

## Ou la main droite doit aller chercher / tenir un objet (espace voiture), et
## a quel point elle y est. Pilote par interaction.gd.
var item_point := Vector3.ZERO
var item_blend := 0.0
## Rayon de l'objet tenu (m) : les doigts se referment dessus. 0 = main ouverte
## (pare-soleil, retroviseur, trajet a vide).
var item_radius := 0.0
## Le geste (item_point / item_blend) est fait de la main GAUCHE : pare-soleil
## conducteur, retroviseur gauche. Sinon la droite.
var item_left := false
## Orientation IMPOSEE au poing droit par ce qu'il tient, et a quel point elle
## l'emporte (0 : la main s'oriente d'apres le coude, comme pour tout le reste).
## Ecrites par interaction.gd a partir de l'objet lui-meme.
##
## Une canette s'en passe : quel que soit l'angle du poignet, elle a l'air tenue.
## Une crosse, non — elle se voit de travers immediatement, et une arme braquee
## a cote de la main qui la tient est la seule chose qu'on regarde.
var item_aim := 0.0
var item_aim_basis := Basis()

var _hand_l: Node3D
var _hand_r: Node3D
var _wrist_l := Vector3.ZERO   # poignet du modele (DRV_Wrist_L), dans le repere de la main
var _wrist_r := Vector3.ZERO
var _skel_l: Skeleton3D       # squelettes des mains (os de phalanges du modele)
var _skel_r: Skeleton3D
var _poses_l := {}             # nom de pose -> {os: Quaternion}, lues dans les animations du .glb
var _poses_r := {}
var _bones_l := {}             # os -> index dans le squelette
var _bones_r := {}
var _elbow_r := Vector3.ZERO   # coude droit de la frame precedente : oriente la main qui tient un objet
var _elbow_l := Vector3.ZERO
var _arm_lu: Dictionary
var _arm_lf: Dictionary
var _arm_ru: Dictionary
var _arm_rf: Dictionary
var _thigh_l: Dictionary
var _shin_l: Dictionary
var _thigh_r: Dictionary
var _shin_r: Dictionary
var _torso: Node3D
var _foot_l: Node3D
var _foot_r: Node3D

## Epaule droite de la frame en cours, buste tourne et penche compris. Lue par
## le banc d'essai : c'est d'elle que depend tout ce que le bras peut atteindre.
var _shoulder_r_now := SHOULDER_R
var _shoulder_l_now := SHOULDER_L

## --- prises sur la jante, index 0 = main gauche, 1 = main droite -----------
## Angle du point TENU sur la jante : tant que la main tient, son angle dans
## l'habitacle vaut _rim + angle du volant, donc elle suit la jante au degre
## pres. Lacher et se reposer ailleurs, c'est changer _rim.
var _rim: Array[float] = [0.0, 0.0]
## Angle de chaque main dans l'habitacle (rad), compte depuis sa position de
## repos (10 h 10). C'est ce que la pose utilise.
var _theta: Array[float] = [0.0, 0.0]
## Progression du transfert en cours, 0..1 ; negatif : la main tient la jante.
var _move: Array[float] = [-1.0, -1.0]
var _from: Array[float] = [0.0, 0.0]
var _to: Array[float] = [0.0, 0.0]
## Duree du transfert en cours (s) : elle se decide au moment ou la main lache.
var _span: Array[float] = [REGRIP_TIME, REGRIP_TIME]
## Retrait de la main hors du plan de la jante, et ouverture des doigts.
var _lift: Array[float] = [0.0, 0.0]
var _open: Array[float] = [0.0, 0.0]
## De quel cote de la jante se trouve le conducteur (+1 / -1 le long de l'axe du
## volant) : c'est vers lui que la main se retire en changeant de prise.
var _toward_driver := 1.0
var _wheel_prev := 0.0

## Le volant revient au centre tout seul : ecrit par car.gd, chaque image.
var wheel_slip := 0.0
var _slip := 0.0
## Fermeture des doigts de chaque main a l'image precedente : sert au banc.
var _close: Array[float] = [1.0, 1.0]
## Depuis combien de temps la jante ne bouge plus, et a quel point la main libre
## est POSEE A PLAT dessus plutot qu'agrippee.
var _still := 0.0
var _flat := 0.0
## Course de jante parcourue depuis que la main s'est agrippee (rad).
var _travel := 0.0

var _breath := 0.0
var _shift_blend := 0.0            # 0 = main sur le volant, 1 = main sur le levier
var _clutch_amt := 0.0
var _brake_amt := 0.0              # transfert du pied droit vers la pedale de frein
var _hb_on := false
var _hb_timer := 0.0
var _hb_reach := 0.0
var _hb_pulled := 0.0

## Scene du .glb, jamais ajoutee a l'arbre : on y pioche les pieces.
var _parts: Node
var _mat_cache := {}


func _ready() -> void:
	_parts = DRIVER.instantiate()
	_build_hands()
	_build_body()
	_build_arms()
	_build_legs()
	_parts.free()
	_parts = null
	_set_layer(self)


## Le conducteur est seul sur sa couche de rendu : les retroviseurs ne la
## regardent pas. Le modele est fait pour la vue subjective — la tete est
## masquee — et un buste sans tete dans le retroviseur interieur serait bien
## pire que pas de buste du tout.
func _set_layer(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = DRIVER_LAYER
	for c in n.get_children():
		_set_layer(c)


## Branche les commandes du modele Blender. Appele par car.gd juste apres la
## construction de la caisse.
func use_controls(tilt: Node3D, spin: Node3D, shift: Node3D, brake: Node3D,
		knob_local: Vector3, grip_local: Vector3) -> void:
	wheel_tilt = tilt
	wheel_spin = spin
	lever = shift
	handbrake_lever = brake
	_knob_local = knob_local
	_grip_local = grip_local
	# De quel cote de la jante sont les epaules : c'est vers la qu'une main se
	# retire pour changer de prise. Deduit du modele plutot que devine — le
	# volant est incline de 68 degres, le signe de son axe n'est pas une
	# evidence, et se tromper ferait passer la main DANS la colonne.
	var axis := (tilt.transform.basis * Vector3.UP).normalized()
	var center := tilt.transform * spin.position
	_toward_driver = signf(((SHOULDER_L + SHOULDER_R) * 0.5 - center).dot(axis))
	if _toward_driver == 0.0:
		_toward_driver = 1.0
	update_pose(0.0, 0.0, 0.0, false, 1, false, false, 0.0, 0.0, Vector3.ZERO, 0.0)


## Appele chaque frame par car.gd.
## `hold_lever` : vrai tant que le frein est tenu a la main.
## `look_back` : 0 = regard vers l'avant, 1 = retourne vers l'arriere a droite.
## `look_out`  : 0 = assis normalement, 1 = penche, tete sortie par la vitre.
## `lean_off`  : de combien la TETE s'est deplacee en se penchant (clic droit),
##               dans le repere de la voiture. car.gd l'a deja borne a
##               l'habitacle ; ici on ne fait que faire suivre le corps.
func update_pose(steer: float, throttle: float, braking: float,
		clutch: bool, gear: int, handbrake: bool, hold_lever: bool,
		look_back: float, look_out: float, lean_off: Vector3, delta: float) -> void:
	if wheel_spin == null:
		return                      # commandes pas encore branchees
	var k := clampf(delta * 6.0, 0.0, 1.0)

	# --- frein a main ----------------------------------------------------
	if handbrake != _hb_on:
		_hb_on = handbrake
		_hb_timer = HB_GESTURE
	_hb_timer = maxf(_hb_timer - delta, 0.0)
	# La main reste sur le levier tant qu'on le tient ; sinon elle fait
	# l'aller-retour et revient au volant.
	var want_lever := hold_lever or _hb_timer > 0.18
	_hb_reach = lerpf(_hb_reach, 1.0 if want_lever else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	_hb_pulled = lerpf(_hb_pulled, 1.0 if _hb_on else 0.0, clampf(delta * 6.5, 0.0, 1.0))
	handbrake_lever.rotation.x = deg_to_rad(HB_TRAVEL) * _hb_pulled

	_clutch_amt = lerpf(_clutch_amt, 1.0 if clutch else 0.0, k)
	# La main droite ne quitte le volant pour le levier que si on debraye.
	_shift_blend = lerpf(_shift_blend, 1.0 if clutch else 0.0, k)

	# Braquer a gauche (steer > 0) fait tourner le volant dans le sens
	# antihoraire vu du conducteur. L'axe pointe vers lui : pas de signe moins.
	var wheel_angle := steer * deg_to_rad(WHEEL_MAX_ANGLE)
	wheel_spin.rotation.y = wheel_angle
	_update_lever(gear, k)

	_breath += delta * 1.15
	var breath := sin(_breath) * 0.005

	# --- buste -----------------------------------------------------------
	# Une tete ne tourne pas a 130 degres toute seule : le buste pivote pour
	# absorber l'exces, a droite quand on se retourne, a gauche quand on se
	# penche a la vitre. Les deux ne peuvent pas arriver ensemble.
	# --- se pencher ------------------------------------------------------
	# Le buste part avec la tete. C'est ce qui met la banquette a portee : sans
	# se pencher, l'epaule droite est a 0,80 m d'une canette posee dessus, pour
	# 0,58 m de bras — l'avant-bras s'etirait pour rattraper.
	var lean_amt := clampf(lean_off.length() / LEAN_FULL, 0.0, 1.0)
	# Penche, le dos ne s'appuie plus : le buste pivote bien plus loin.
	var twist := Basis(Vector3.UP,
		deg_to_rad(lerpf(TWIST_MAX, TWIST_MAX_LEAN, lean_amt))
			* (look_out * 0.75 - look_back))
	# S'ENROULER AUTOUR DU SIEGE. Se retourner a droite ET se pencher, c'est le
	# geste qu'on fait pour attraper ce qui traine DERRIERE SOI : on ne se
	# contente pas de se vriller sur place, on contourne le dossier. L'axe du
	# mouvement recule donc vers le dossier, et l'epaule droite passe derriere
	# son plan au lieu de rester coincee devant.
	#
	# Les deux conditions comptent. Se retourner seul garde le dos cale contre
	# le dossier, qui est justement ce qui empeche de s'enrouler ; se pencher
	# seul, vers l'avant, n'a aucune raison de deplacer l'axe.
	var wrap := look_back * lean_amt
	var pivot_z := lerpf(SPINE.z, SPINE_WRAP.z, wrap)
	var lean := LEAN_OUT * look_out + lean_off * LEAN_BODY
	# LES MAINS RESTENT AU VOLANT en se penchant. Une version precedente leur
	# faisait lacher la jante pour aller se retenir a la console ou au dossier
	# passager, au motif que l'epaule s'eloigne de la jante. Mais on conduit :
	# une main qui quitte le volant des qu'on se penche coute plus cher que les
	# quelques centimetres d'allonge qu'elle economise. Le bras se tend, c'est
	# tout — voir forearm_stretch() et le banc `-- leantest`, qui le mesure.

	# Tendre le bras : le buste accompagne, mais SEULEMENT quand on va vraiment
	# chercher loin. Pencher pour un objet tenu devant la poitrine ferait bouger
	# le buste en permanence, sans raison.
	if item_blend > 0.001:
		# Depuis l'epaule REELLE — tournee et penchee. La mesurer depuis sa
		# position assise surestimait ce qui reste a parcourir des qu'on bouge,
		# et le buste repartait chercher une distance deja franchie.
		var sh_ref := _twisted(SHOULDER_L if item_left else SHOULDER_R, twist, pivot_z) + lean
		var away := item_point - sh_ref
		away.y = 0.0
		var stretch := clampf((away.length() - 0.42) / 0.25, 0.0, 1.0)
		if stretch > 0.0 and away.length_squared() > 0.000001:
			var reach_lean := lerpf(REACH_LEAN, REACH_LEAN_OFF_SEAT, lean_amt)
			lean += away.normalized() * (reach_lean * item_blend * stretch)
	# Le maillage du buste est modelise depuis SPINE : pour qu'il tourne autour
	# de l'axe recule et pas autour de son origine, on deplace celle-ci de ce
	# que la rotation lui fait subir. `wrap` a zero, ca redonne SPINE.
	var pivot := Vector3(SPINE.x, SPINE.y, pivot_z)
	_torso.position = pivot + twist * (SPINE - pivot) + lean + Vector3(0.0, breath, 0.0)
	_torso.basis = twist

	# --- mains -----------------------------------------------------------
	# Calcul analytique : on ne depend pas de l'ordre de mise a jour des
	# transforms par le moteur.
	#
	# Chaque main a desormais SA position sur la jante et son propre etat : elle
	# tient, ou elle est en train de changer de prise. Une main occupee ailleurs
	# ne tient plus rien — et interdit donc a l'autre de lacher.
	var busy: Array[float] = [
		maxf(look_out, item_blend if item_left else 0.0),
		maxf(maxf(_shift_blend, look_back),
			maxf(_hb_reach, 0.0 if item_left else item_blend)),
	]
	_update_grips(wheel_angle, delta, busy)
	var tf_l := _rim_grip(0)
	var tf_r := _rim_grip(1)
	# Une main prise par un objet : l'autre conduit paume a plat sur la jante.
	var flat_l := _flat_amount(0, item_blend, item_left)
	var flat_r := _flat_amount(1, item_blend, item_left)
	if flat_l > 0.001:
		tf_l = tf_l.interpolate_with(_flat_grip(0, tf_l, _elbow_l), flat_l)
	if flat_r > 0.001:
		tf_r = tf_r.interpolate_with(_flat_grip(1, tf_r, _elbow_r), flat_r)

	# Une main reste toujours au volant : celle du cote oppose au regard.
	var left := tf_l.interpolate_with(_door_grip(), look_out)
	if item_left:
		var goal := _open_grip(item_point, _elbow_l, true) if item_radius <= 0.0 else _aligned_grip(item_point, _elbow_l)
		left = left.interpolate_with(goal, item_blend)
	_hand_l.transform = left
	var right := tf_r.interpolate_with(_knob_grip(), _shift_blend)
	right = right.interpolate_with(_headrest_grip(), look_back)
	right = right.interpolate_with(_handbrake_grip(), _hb_reach)
	# Un objet en main l'emporte sur tout le reste.
	if not item_left:
		right = right.interpolate_with(_item_grip(), item_blend)
		# ... et s'il sait comment on l'empoigne, il oriente le poing lui-meme.
		# Seulement l'orientation : la POSITION reste celle du geste, qui sait
		# ou est le bras et jusqu'ou il peut aller.
		if item_aim > 0.0:
			# LES DEUX bases doivent etre orthonormales : slerp() les caste en
			# quaternion, et Godot refuse d'y couler autre chose. Celle de la
			# main sort de la chaine de interpolate_with() ci-dessus, qui la
			# denormalise d'un cheveu — ses vecteurs restent unitaires et
			# orthogonaux a 1e-4 pres, assez pour que le cast proteste a chaque
			# image ou l'on tient l'arme levee.
			right.basis = right.basis.orthonormalized().slerp(
				item_aim_basis.orthonormalized(), clampf(item_aim, 0.0, 1.0))
	_hand_r.transform = right

	# --- doigts : ils se referment sur ce que la main tient ---------------
	# (rayon de l'objet, fermeture) suivent les memes fondus que la position.
	var r_r := WHEEL_GRIP_R
	var c_r := 1.0
	r_r = lerpf(r_r, KNOB_GRIP_R, _shift_blend)
	c_r = lerpf(c_r, 0.0, look_back)                  # appui-tete : main a plat
	r_r = lerpf(r_r, HB_GRIP_R, _hb_reach)
	c_r = lerpf(c_r, 1.0, _hb_reach)
	var r_l := lerpf(WHEEL_GRIP_R, DOOR_GRIP_R, look_out)
	var c_l := 1.0
	if item_blend > 0.0:
		# Ouverte pendant le trajet, refermee a l'arrivee si l'objet a un rayon
		# (pas pour un pare-soleil ou un retroviseur : paume posee dessus).
		var w := item_blend
		var closing := smoothstep(0.75, 1.0, w) * (1.0 if item_radius > 0.0 else PANEL_CLOSE)
		var c_item := clampf(1.0 - smoothstep(0.0, 0.3, w) + closing, 0.0, 1.0)
		var k_item := smoothstep(0.0, 0.25, w)
		if item_left:
			c_l = lerpf(c_l, c_item, k_item)
			if item_radius > 0.0:
				r_l = lerpf(r_l, item_radius, w)
		else:
			c_r = lerpf(c_r, c_item, k_item)
			if item_radius > 0.0:
				r_r = lerpf(r_r, item_radius, w)
	# Main en train de changer de prise : elle a LACHE. Les doigts s'ouvrent au
	# decollage et se referment a la repose, dans le meme sinus que le retrait —
	# une main qui se deplace poing ferme au-dessus du volant se voit tout de
	# suite, c'est le geste d'un mannequin, pas d'un conducteur.
	c_l *= 1.0 - _open[0]
	c_r *= 1.0 - _open[1]
	# Paume a plat sur la jante : les doigts se detendent, ils n'enserrent plus.
	c_l = lerpf(c_l, FLAT_CLOSE, flat_l)
	c_r = lerpf(c_r, FLAT_CLOSE, flat_r)
	# Volant rendu : on desserre pour le laisser filer. Seulement la main qui est
	# encore sur la jante — celle qui est au levier ne desserre rien.
	c_l *= 1.0 - SLIP_OPEN * _slip * (1.0 - clampf(busy[0], 0.0, 1.0))
	c_r *= 1.0 - SLIP_OPEN * _slip * (1.0 - clampf(busy[1], 0.0, 1.0))
	_close[0] = c_l
	_close[1] = c_r
	_apply_fingers(_skel_l, _poses_l, _bones_l, r_l, c_l)
	_apply_fingers(_skel_r, _poses_r, _bones_r, r_r, c_r)

	var offset := lean + Vector3(0.0, breath, 0.0)
	var sh_l := _twisted(SHOULDER_L, twist, pivot_z) + offset
	var sh_r := _twisted(SHOULDER_R, twist, pivot_z) + offset
	_shoulder_r_now = sh_r
	_shoulder_l_now = sh_l
	# L'avant-bras vise le poignet du modele, pas le centre de la jante : la main
	# tient la jante dans sa paume, le poignet est ~8 cm plus pres du conducteur.
	var pos_l := _hand_l.transform * _wrist_l
	var pos_r := _hand_r.transform * _wrist_r

	var elbow_l := _solve_elbow(sh_l, pos_l, sh_l + Vector3(-0.30, -0.42, 0.16))
	var elbow_r := _solve_elbow(sh_r, pos_r, sh_r + Vector3(0.30, -0.42, 0.16))

	_set_bone(_arm_lu, sh_l, elbow_l)
	# L'avant-bras prend le roulis de la main (son dos suit le dos de la main),
	# sinon la manche arrive vrillee au poignet des que la main se tourne.
	_set_bone(_arm_lf, elbow_l, pos_l, _hand_l.transform.basis.y)
	_set_bone(_arm_ru, sh_r, elbow_r)
	_set_bone(_arm_rf, elbow_r, pos_r, _hand_r.transform.basis.y)
	_elbow_r = elbow_r
	_elbow_l = elbow_l

	# --- pieds -----------------------------------------------------------
	# Le transfert vers le frein a son propre amortissement : l'entree passe de
	# 0 a 1 en une frame, sans ca le pied se teleporte d'une pedale a l'autre.
	# Il se souleve aussi au passage, il ne glisse pas a plat sur le plancher.
	_brake_amt = lerpf(_brake_amt, braking, clampf(delta * 5.5, 0.0, 1.0))
	var lift := sin(_brake_amt * PI) * 0.035

	var push := maxf(throttle, _brake_amt)
	var ankle_l := ANKLE_L + Vector3(0.0, 0.0, -0.055 * _clutch_amt)
	var ankle_r := Vector3(
		lerpf(ANKLE_R.x, BRAKE_X, _brake_amt),
		ANKLE_R.y + lift,
		ANKLE_R.z - 0.030 * push)

	_foot_l.position = ankle_l
	_foot_l.rotation.x = lerpf(_foot_l.rotation.x, -0.08 - 0.34 * _clutch_amt, k)
	_foot_r.position = ankle_r
	_foot_r.rotation.x = lerpf(_foot_r.rotation.x,
		-0.06 - throttle * 0.26 - _brake_amt * 0.30, k)

	var knee_r := Vector3(lerpf(KNEE_R.x, KNEE_R.x - 0.06, _brake_amt), KNEE_R.y, KNEE_R.z)
	var knee_l := KNEE_L + Vector3(0.0, 0.0, -0.02 * _clutch_amt)
	# Le bassin accompagne le buste d'un quart. Sans ca, se pencher decolle la
	# cuisse du tronc ; avec, on voit qu'on glisse sur l'assise. Les genoux
	# suivent le bassin, mais pas les chevilles : les pieds restent aux pedales.
	var hip := lean_off * LEAN_HIP
	_set_bone(_thigh_l, HIP_L + hip, knee_l + hip * 0.5)
	_set_bone(_shin_l, knee_l + hip * 0.5, ankle_l)
	_set_bone(_thigh_r, HIP_R + hip, knee_r + hip * 0.5)
	_set_bone(_shin_r, knee_r + hip * 0.5, ankle_r)


# --------------------------------------------------------------------------
# Commandes
# --------------------------------------------------------------------------

## Enchainement de prises : ou chaque main tient la jante, quand elle lache et
## ou elle va se reposer. Appelee une fois par image, avant la pose.
##
## `busy` dit, pour chaque main, a quel point elle est partie ailleurs (levier,
## frein a main, appui-tete, portiere, objet en main).
##
## Le cycle d'une main est le meme dans les deux sens de braquage : elle suit la
## jante au degre pres, atteint sa butee, lache, passe au-dessus du volant
## jusqu'a l'autre bout de sa course, et reprend. Ce qui l'empeche de le faire
## n'importe quand, c'est la seule regle qui compte : UNE MAIN NE LACHE QUE SI
## L'AUTRE TIENT.
func _update_grips(wheel_angle: float, delta: float, busy: Array[float]) -> void:
	# Volant pose : au bout d'un moment les mains se remettent a 10 h 10.
	var rate := (wheel_angle - _wheel_prev) / maxf(delta, 0.0001)
	var speed := absf(rate)
	_wheel_prev = wheel_angle
	_slip = lerpf(_slip, clampf(wheel_slip, 0.0, 1.0),
		clampf(delta * SLIP_SMOOTH, 0.0, 1.0))

	# On ne conduit paume a plat que PENDANT qu'on tourne. Le volant repose, la
	# main libre se referme sur la jante et la tient, comme n'importe quelle main
	# au volant : on ne reste pas la paume posee dessus a ne rien faire.
	#
	# Seule la POSE change — la main ne se deplace pas d'un degre en refermant
	# les doigts, et les butees restent celles de la main a plat tant que l'objet
	# est en main. Les resserrer ici ramenerait la main de 272 degres a sa butee
	# d'un coup, c'est-a-dire un saut d'un demi-tour de jante.
	if speed > WHEEL_STILL:
		_still = 0.0
		_travel += speed * delta
	else:
		_still += delta
		# La jante s'est tue : le chemin parcouru ne compte plus. Il faudra le
		# refaire en entier pour rouvrir la main.
		if _still >= FLAT_GRAB_DELAY:
			_travel = 0.0
	var want_flat := _still < FLAT_GRAB_DELAY and _travel >= deg_to_rad(FLAT_TURN_TRAVEL)
	_flat = lerpf(_flat, 1.0 if want_flat else 0.0,
		clampf(delta * (FLAT_OPEN_SMOOTH if want_flat else FLAT_SMOOTH), 0.0, 1.0))

	for h in 2:
		# Partie ailleurs : elle ne tient plus rien. Son point de prise revient
		# doucement au repos, pour qu'elle retrouve la jante a 10 h 10 et pas la
		# ou le dernier virage l'avait laissee — le fondu qui la ramene au volant
		# sauterait sinon d'un quart de tour.
		if busy[h] > BUSY_LET_GO:
			_move[h] = -1.0
			_lift[h] = 0.0
			_open[h] = 0.0
			_rim[h] = lerpf(_rim[h], -wheel_angle, clampf(delta * 4.0, 0.0, 1.0))
			_theta[h] = _rim[h] + wheel_angle
			continue

		# Transfert en cours : la main ne suit plus la jante, elle vise un point
		# de l'habitacle. La jante file dessous, et c'est bien le but.
		if _move[h] >= 0.0:
			_move[h] += delta / _span[h]
			# Le volant s'immobilise pendant le transfert — butee de braquage,
			# ou le joueur a simplement rendu la main. Aller au bout de sa course
			# n'a alors plus d'objet : cette course-la se prend pour la SUITE du
			# mouvement, et il n'y en a plus. La main se repose donc la ou l'on
			# tient un volant, sinon elle y allait quand meme et en repartait
			# 0,6 s plus tard, pour rien.
			if speed <= WHEEL_STILL:
				_to[h] = lerpf(_to[h], 0.0, clampf(delta * 4.0, 0.0, 1.0))
			if _move[h] < 1.0:
				var p := _move[h]
				_theta[h] = lerpf(_from[h], _to[h], smoothstep(0.0, 1.0, p))
				# La main se leve d'un coup et se repose doucement : la racine
				# donne tout le retrait des le debut du geste. Avec un sinus nu,
				# les deux mains se croisaient a 5 cm — c'est-a-dire au moment ou
				# le retrait n'avait pas encore atteint sa valeur.
				var up := sqrt(sin(PI * p))
				_lift[h] = REGRIP_LIFT * up
				_open[h] = REGRIP_OPEN * up
				continue
			# Reposee : c'est ce point de la jante qu'elle tient desormais.
			_move[h] = -1.0
			_rim[h] = _to[h] - wheel_angle

		_lift[h] = 0.0
		_open[h] = 0.0
		var theta := _rim[h] + wheel_angle
		# Volant rendu : la jante FILE SOUS LA PAUME. La main cesse de la suivre
		# et rentre a 10 h 10 a son propre rythme ; on recale son point de prise
		# au passage, pour qu'elle reprenne d'ou elle est des que le joueur
		# retouche au volant. C'est le geste qu'on fait vraiment en sortie de
		# virage — on ne ramene pas le volant, on le laisse revenir.
		if _slip > 0.001:
			var home := lerpf(_theta[h], 0.0, clampf(delta * SLIP_HOME, 0.0, 1.0))
			theta = lerpf(theta, home, _slip)
			_rim[h] = theta - wheel_angle
		var lim := _limits(h)
		var lo := lim.x
		var hi := lim.y
		# L'autre main est prise : le poignet ne s'enroule pas autour du tube, et
		# la main libre ACCOMPAGNE la jante d'un bout a l'autre du braquage au
		# lieu de buter en chemin. Les butees ne valent que pour un poing referme
		# sur un volant qu'on tourne des deux mains.
		#
		# On les garde elargies meme quand elle re-agrippe a l'arret (`_flat`) :
		# c'est la POSE qui change alors, pas la place de la main. Les resserrer
		# la ramenerait de 272 degres a sa butee d'un coup.
		var flat := 0.0 if ((h == 0) == item_left) else clampf(item_blend, 0.0, 1.0)
		if flat > 0.0:
			var full := deg_to_rad(WHEEL_MAX_ANGLE)
			lo = lerpf(lo, -full, flat)
			hi = lerpf(hi, full, flat)
		var margin := deg_to_rad(REGRIP_MARGIN)
		var goal := 0.0
		# UNE MAIN NE LACHE QUE SI ELLE Y EST FORCEE, c'est-a-dire au bout de sa
		# course. Volant immobile, elle reste agrippee la ou elle tient, meme de
		# travers : c'est ce qu'on fait, et une main qui se replace toute seule
		# pendant qu'on ne tourne pas se remarque immediatement — un tic.
		#
		# Ce qui remet les mains a 10 h 10 apres une manoeuvre, ce n'est donc pas
		# un rangement : c'est le volant qui rentre et leur file sous les paumes
		# (voir `_slip` plus haut), et il les y ramene tout seul.
		var change := theta > hi or theta < lo
		# On ne se repose a l'autre bout de sa course que si le volant TOURNE
		# ENCORE : c'est une prise qu'on prend pour la suite du mouvement. Volant
		# pose, il n'y a pas de suite — la main se repose la ou l'on tient un
		# volant. Sans ca, braquage tenu a fond, chaque main faisait deux gestes
		# de suite : un pour aller au bout de sa course, un pour en revenir.
		if theta > hi:
			goal = 0.0 if speed <= WHEEL_STILL else lo + margin
		elif theta < lo:
			goal = 0.0 if speed <= WHEEL_STILL else hi - margin
		if change and _free_to_hold(1 - h, busy):
			# On part d'ou la main est VUE, pas de l'angle brut de la jante. Les
			# deux different des que la main a du attendre son tour, bornee par
			# _soft_limit : partir de l'angle brut la faisait sauter d'un quart
			# de tour sur l'image du lacher.
			_from[h] = _soft_limit(theta, lo, hi)
			_move[h] = 0.0
			# Plus on braque vite, plus la main passe vite : sinon l'autre attend
			# son tour pendant que la jante lui file sous la paume.
			_span[h] = clampf(REGRIP_TIME * REGRIP_HURRY / maxf(rad_to_deg(speed), 1.0),
				REGRIP_TIME_MIN, REGRIP_TIME)
			_to[h] = _keep_clear(h, _from[h], goal, wheel_angle, rate * _span[h])
			_theta[h] = _from[h]
		else:
			# Personne pour prendre le relais : on tient, et la jante finit par
			# filer sous la paume plutot que de retourner le coude.
			_theta[h] = _soft_limit(theta, lo, hi)
			# ... et jamais SUR l'autre main. Une main bloquee en butee ne bouge
			# plus pendant que l'autre continue de suivre la jante : celle-ci
			# finit par lui arriver dessus, et le banc les relevait a 63 mm. Elle
			# s'arrete a distance et laisse la jante filer — ce qu'elle fait de
			# toute facon deja une fois en butee.
			if _move[1 - h] < 0.0 and busy[1 - h] <= BUSY_LET_GO:
				_theta[h] = _keep_off(h, _theta[h])


## Butee basse et haute d'une main (rad). La gauche TIRE en descendant vers 7 h
## (theta > 0) et POUSSE en montant vers 1 h ; la droite fait l'inverse.
func _limits(h: int) -> Vector2:
	return Vector2(
		-deg_to_rad(GRIP_PUSH if h == 0 else GRIP_PULL),
		deg_to_rad(GRIP_PULL if h == 0 else GRIP_PUSH))


## Raccourcit une reprise qui se poserait sur l'autre main.
##
## `drift` est ce que l'autre main va parcourir pendant le transfert : elle tient
## la jante, donc elle suit le volant. C'est bien sa position D'ARRIVEE qu'il
## faut degager, pas celle qu'elle occupe au moment ou l'on lache — a plein
## braquage elle parcourt 70 degres de jante dans l'intervalle.
func _keep_clear(h: int, from: float, goal: float, wheel_angle: float, drift: float) -> float:
	var dir := signf(goal - from)
	if dir == 0.0:
		return goal
	var gap := deg_to_rad(GRIP_ANCHOR_GAP) * (1.0 if h == 0 else -1.0)
	# Ou l'autre main sera a l'arrivee. Son angle passe par _soft_limit comme
	# celui de n'importe quelle main qui attend son tour : sans ca, une main
	# bloquee en butee etait creditee d'une derive qu'elle ne fait pas, on la
	# croyait partie, et on venait se poser dessus — 5 mm au releve.
	var o := 1 - h
	var lim := _limits(o)
	var theirs := _soft_limit(_rim[o] + wheel_angle + drift, lim.x, lim.y) - gap
	theirs = goal + wrapf(theirs - goal, -PI, PI)
	var sep := deg_to_rad(GRIP_SEPARATION)
	if absf(goal - theirs) >= sep:
		return goal
	# On s'arrete court, du cote d'ou l'on vient — jamais au-dela du point de
	# depart, sinon la main reculerait au lieu de changer de prise.
	var stop := theirs - dir * sep
	return stop if (stop - from) * dir > 0.0 else from


## Empeche une main d'en rattraper une autre sur la jante. Les deux comptent
## leurs angles depuis des reperes distants de GRIP_ANCHOR_GAP : au repos elles
## sont donc a 120 degres l'une de l'autre, tres au-dela de la separation exigee,
## et cette borne ne mord jamais en conduite normale.
func _keep_off(h: int, theta: float) -> float:
	var gap := deg_to_rad(GRIP_ANCHOR_GAP) * (1.0 if h == 0 else -1.0)
	var theirs := _theta[1 - h] - gap
	theirs = theta + wrapf(theirs - theta, -PI, PI)
	var sep := deg_to_rad(GRIP_SEPARATION)
	var d := theta - theirs
	if absf(d) >= sep:
		return theta
	return theirs + (sep if d >= 0.0 else -sep)


## L'autre main est-elle en etat de tenir le volant a elle seule ?
func _free_to_hold(other: int, busy: Array[float]) -> bool:
	return _move[other] < 0.0 and busy[other] <= BUSY_LET_GO


## Suivi de la jante borne en douceur. Dans [lo, hi] la main suit AU DEGRE PRES —
## c'est ce qui fait que le volant a l'air tenu et pas seulement anime. Au-dela,
## l'exces est comprime en tangente hyperbolique et tend vers GRIP_RESERVE sans
## jamais l'atteindre. La pente vaut 1 au raccord : il ne se voit pas.
func _soft_limit(theta: float, lo: float, hi: float) -> float:
	var span := deg_to_rad(GRIP_RESERVE)
	if theta > hi:
		return hi + span * tanh((theta - hi) / span)
	if theta < lo:
		return lo - span * tanh((lo - theta) / span)
	return theta


## Pose d'une main sur la jante (0 = gauche, 1 = droite), a l'angle que
## _update_grips lui a donne. `GRIP_ANGLE` place son point de repos a 10 h 10 :
## la jante est tournee autour de l'axe du volant (Y local) et la main avec,
## pour que ses doigts restent perpendiculaires a la jante.
func _rim_grip(h: int) -> Transform3D:
	return _rim_grip_at(h, _theta[h], _lift[h])


## Main POSEE A PLAT sur la jante, au meme point qu'elle tiendrait autrement.
##
## C'est la pose de celui qui a une main prise — une canette, une arme : l'autre
## ne peut plus enserrer le volant, elle se pose dessus et le fait tourner par
## appui. La paume regarde la face du volant tournee vers le conducteur, les
## doigts prolongent l'avant-bras a plat dans le plan de la jante.
##
## Le poing ferme ne convient pas : la meme main tiendrait la jante ET l'objet.
## Et une main a plat n'a pas besoin de lacher pour laisser filer la jante — la
## saturation de _soft_limit, qui est une rustine quand on serre, devient ici
## le geste lui-meme.
func _flat_grip(h: int, rim: Transform3D, elbow: Vector3) -> Transform3D:
	var axis := (wheel_tilt.transform.basis * Vector3.UP).normalized() * _toward_driver
	var point := rim.origin
	# Doigts dans le prolongement du bras, rabattus dans le plan de la jante.
	var f := point - elbow
	f -= axis * f.dot(axis)
	if f.length_squared() < 0.000001:
		f = rim.basis.x - axis * rim.basis.x.dot(axis)
	f = f.normalized()
	var fd := FINGER_DIR_L if h == 0 else FINGER_DIR_R
	var pd := PALM_AWAY_L if h == 0 else PALM_AWAY_R
	# PALM_AWAY est la normale SORTANTE de la paume — c'est ainsi que
	# `_open_grip` la pose sur un pare-soleil et que `held_offset` ecarte l'objet
	# tenu. La paume regarde donc la jante, vers l'AVANT, et c'est le dos de la
	# main qui se retrouve tourne vers le joueur. L'envoyer sur l'axe cote
	# conducteur retournait la main : paume face au joueur, dos contre le volant,
	# et la main passait de l'autre cote de la jante.
	var target := Basis(f, -axis, f.cross(-axis))
	var local := Basis(fd, pd, fd.cross(pd))
	return Transform3D(target * local.transposed(), point + axis * PALM_LIFT)


## A quel point cette main conduit a plat : c'est le fondu de l'objet tenu par
## l'AUTRE main. Une main en train de changer de prise ne compte pas — elle est
## en l'air, elle n'est posee sur rien.
func _flat_amount(h: int, blend: float, left_holds: bool) -> float:
	if (h == 0) == left_holds:
		return 0.0                  # c'est cette main-la qui tient l'objet
	return clampf(blend, 0.0, 1.0) * _flat * (1.0 - _open[h] / REGRIP_OPEN)


func _rim_grip_at(h: int, theta: float, lift: float) -> Transform3D:
	var side := -1.0 if h == 0 else 1.0
	var grip := Basis(Vector3.UP, side * deg_to_rad(GRIP_ANGLE))
	var local := grip * Vector3(side * WHEEL_RADIUS, 0.0, 0.0)
	local.y += lift * _toward_driver
	return wheel_tilt.transform \
		* Transform3D(Basis(Vector3.UP, theta), wheel_spin.position) \
		* Transform3D(grip, local)


func _update_lever(gear: int, k: float) -> void:
	var gate: Vector2 = GEAR_GATE[clampi(gear, 0, GEAR_GATE.size() - 1)]
	lever.rotation.x = lerpf(lever.rotation.x, -gate.y * deg_to_rad(LEVER_LONG_ANGLE), k)
	lever.rotation.z = lerpf(lever.rotation.z, -gate.x * deg_to_rad(LEVER_SIDE_ANGLE), k)


## Main refermee sur le pommeau. On part du pommeau REEL du modele plutot que
## d'une longueur devinee, et on le couche de 90 degres pour l'envelopper.
func _knob_grip() -> Transform3D:
	# +90 autour de X : axe de prise du poing (Z local) le long du levier, dos de
	# la main (+Y local) vers le conducteur, pouce (-Z local) vers le haut du pommeau.
	return Transform3D(
		lever.transform.basis * Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0)),
		lever.transform * _knob_local)


## Main refermee sur la poignee du frein a main.
func _handbrake_grip() -> Transform3D:
	# Le levier monte vers l'avant : axe de prise du poing (Z local) le long du
	# levier (base -> poignee), pouce (-Z) vers le bouton au bout, dos de la main
	# (+Y) vers le haut. Tout est exprime dans le repere du pivot du levier.
	var tf := handbrake_lever.transform
	var along := _grip_local.normalized()
	if along.length_squared() < 0.5:
		along = Vector3.FORWARD
	var z := -along
	var y := (Vector3.UP - z * Vector3.UP.dot(z)).normalized()
	return Transform3D(tf.basis * Basis(y.cross(z), y, z), tf * _grip_local)


## Main refermee sur un objet, paume tournee vers le conducteur.
func _item_grip() -> Transform3D:
	if item_radius <= 0.0:
		return _open_grip(item_point, _elbow_r, false)
	return _aligned_grip(item_point, _elbow_r)


## Main orientee d'apres l'avant-bras : son axe poignet (+Y local, base de la
## paume) vise le coude, et le pouce (-Z local) pointe vers le haut autant que
## possible. Un angle fixe laissait le poignet casse des que le coude bougeait.
func _aligned_grip(point: Vector3, elbow: Vector3) -> Transform3D:
	var y := elbow - point
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	y = y.normalized()
	var z := Vector3.DOWN - y * Vector3.DOWN.dot(y)
	if z.length_squared() < 0.0001:
		z = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	z = z.normalized()
	return Transform3D(Basis(y.cross(z), y, z), point)


## Main OUVERTE posee sur un panneau (pare-soleil, retroviseur) : les doigts
## prolongent l'avant-bras vers le point de saisie, la paume regarde vers
## l'avant (le panneau fait face au conducteur), les bouts des doigts sont sur le
## point. `left` : main gauche (doigts vers -X local) ou droite (+X).
func _open_grip(point: Vector3, elbow: Vector3, left: bool) -> Transform3D:
	var f := point - elbow
	if f.length_squared() < 0.0001:
		f = Vector3.UP
	f = f.normalized()
	var p := Vector3.FORWARD - f * Vector3.FORWARD.dot(f)
	if p.length_squared() < 0.0001:
		p = Vector3.UP - f * Vector3.UP.dot(f)
	p = p.normalized()
	# Dans le repere de la main, doigts et paume ne sont pas sur des axes : le
	# roulis de la prise jante y est cuit. On envoie la direction des doigts sur
	# f et celle de la paume sur p, par changement de base.
	var fd := FINGER_DIR_L if left else FINGER_DIR_R
	var pd := PALM_AWAY_L if left else PALM_AWAY_R
	var target := Basis(f, p, f.cross(p))
	var local := Basis(fd, pd, fd.cross(pd))
	return Transform3D(target * local.transposed(), point - f * FINGER_REACH)


## La main droite, pour qu'un objet tenu puisse la suivre exactement.
func hand_right() -> Node3D:
	return _hand_r


func hand_left() -> Node3D:
	return _hand_l


## Ou en est une main sur la jante, en degres depuis sa position de repos
## (10 h 10) : positif = elle est descendue du cote gauche du volant.
func grip_angle(right: bool) -> float:
	return rad_to_deg(_theta[1 if right else 0])


## Cette main est-elle en train de changer de prise (donc de ne rien tenir) ?
func grip_moving(right: bool) -> bool:
	return _move[1 if right else 0] >= 0.0


## Combien de mains tiennent la jante en ce moment. C'est ce que le banc d'essai
## surveille : ce nombre ne doit JAMAIS tomber a zero en conduisant.
func grips_held() -> int:
	var n := 0
	for h in 2:
		if _move[h] < 0.0:
			n += 1
	return n


## Distance epaule -> poignet d'une main, en metres. Le modele n'ayant plus de
## bras (mains seules, facon FPS), forearm_stretch() ne mesure plus rien : c'est
## cette distance-la, comparee a arm_span(), qui dit si une prise est vraiment a
## portee ou si le bras invisible traverse le buste pour y arriver.
func hand_reach(right: bool) -> float:
	var hand := _hand_r if right else _hand_l
	var wrist := hand.transform * (_wrist_r if right else _wrist_l)
	var shoulder := _shoulder_r_now if right else _shoulder_l_now
	return shoulder.distance_to(wrist)


## Fermeture des doigts d'une main : 1 = refermee sur la jante, 0 = ouverte.
func grip_close(right: bool) -> float:
	return _close[1 if right else 0]


## Angle (degres) entre le DOS d'une main et l'axe du volant cote conducteur.
##
## Proche de 0 : la main est POSEE A PLAT sur la jante, dos tourne vers le
## joueur et paume sur le volant — la pose de celui qui a l'autre main prise.
## Proche de 90 : le poing est referme autour du tube. Au-dela, la main est
## retournee, c'est-a-dire passee de l'autre cote de la jante.
##
## C'est la mesure qui distingue les trois, et elle ne depend d'aucun etat
## interne : elle se lit sur la transform de la main.
func palm_tilt(right: bool) -> float:
	var back := -((_hand_r if right else _hand_l).transform.basis \
		* (PALM_AWAY_R if right else PALM_AWAY_L))
	var axis := (wheel_tilt.transform.basis * Vector3.UP).normalized() * _toward_driver
	return rad_to_deg(acos(clampf(back.normalized().dot(axis), -1.0, 1.0)))


## Portee epaule -> poignet qu'AURAIT cette main posee a `deg` de sa position de
## repos, sans rien deplacer. C'est avec ca que se calent GRIP_PULL et
## GRIP_PUSH : passe un certain angle, la prise n'est plus atteignable que par un
## bras qui s'allonge, et le modele n'ayant plus de bras, rien ne le montrerait.
func reach_at(right: bool, deg: float) -> float:
	var h := 1 if right else 0
	var tf := _rim_grip_at(h, deg_to_rad(deg), 0.0)
	var wrist := tf * (_wrist_r if right else _wrist_l)
	return (_shoulder_r_now if right else _shoulder_l_now).distance_to(wrist)


## Ou est l'epaule droite en ce moment (repere voiture) : torsion du buste et
## penchement compris. Sert au banc d'essai.
func shoulder_right() -> Vector3:
	return _shoulder_r_now


## Etirement de l'avant-bras droit. 1 = longueur de modelisation ; au-dela,
## _set_bone a allonge le segment pour rattraper une main hors de portee du
## bras. C'est LA mesure du bras de gorille, et donc de ce qui rend la banquette
## arriere vraiment atteignable ou seulement atteignable a l'ecran.
func forearm_stretch() -> float:
	if _arm_rf.is_empty():
		return 1.0
	return (_arm_rf["mesh"] as MeshInstance3D).scale.z


## Idem pour le bras GAUCHE. C'est lui qu'il faut surveiller depuis que les
## mains restent au volant : quand le buste part en arriere, c'est la gauche qui
## tient encore la jante, et donc elle qui s'allonge s'il part trop loin.
func forearm_stretch_left() -> float:
	if _arm_lf.is_empty():
		return 1.0
	return (_arm_lf["mesh"] as MeshInstance3D).scale.z


## Portee du bras droit, epaule -> poignet, telle que la voit _solve_elbow.
func arm_span() -> float:
	return UPPER_ARM + FOREARM


## Main posee a plat sur le haut de l'appui-tete passager, paume vers le bas.
func _headrest_grip() -> Transform3D:
	return _aligned_grip(HEADREST_GRIP, _elbow_r)


## Main gauche agrippee au haut de la portiere quand on sort la tete.
func _door_grip() -> Transform3D:
	return Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(160.0), deg_to_rad(12.0), 0.0)),
		DOOR_GRIP)


## Fait pivoter un point autour de l'axe vertical du buste. `pivot_z` recule
## vers le dossier quand on s'enroule autour du siege (voir SPINE_WRAP).
func _twisted(p: Vector3, twist: Basis, pivot_z := SPINE.z) -> Vector3:
	var pivot := Vector3(SPINE.x, p.y, pivot_z)
	return pivot + twist * (p - pivot)


# --------------------------------------------------------------------------
# IK 2 os
# --------------------------------------------------------------------------

## Renvoie la position du coude pour que l'epaule atteigne la main.
## `pole` indique vers ou le coude doit pointer.
func _solve_elbow(shoulder: Vector3, hand: Vector3, pole: Vector3) -> Vector3:
	var dir := hand - shoulder
	var raw := dir.length()
	if raw < 0.0001:
		return shoulder + Vector3.DOWN * UPPER_ARM
	var n := dir / raw
	var d := clampf(raw, absf(UPPER_ARM - FOREARM) + 0.02, UPPER_ARM + FOREARM - 0.02)
	var l := (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + d * d) / (2.0 * d)
	var h := sqrt(maxf(UPPER_ARM * UPPER_ARM - l * l, 0.0))

	var pole_dir := pole - shoulder
	pole_dir -= n * pole_dir.dot(n)
	if pole_dir.length_squared() < 0.000001:
		pole_dir = Vector3.DOWN - n * Vector3.DOWN.dot(n)
	return shoulder + n * l + pole_dir.normalized() * h


## Etire et oriente une capsule entre deux points (espace local du conducteur).
func _set_bone(bone: Dictionary, from: Vector3, to: Vector3, up_hint := Vector3.ZERO) -> void:
	if bone.is_empty():
		return                      # segment absent du modele (bras retires)
	var dir := to - from
	var d := dir.length()
	if d < 0.0001:
		return
	var fwd := dir / d
	var up := up_hint.normalized() if up_hint.length_squared() > 0.001 else Vector3.UP
	if absf(fwd.dot(up)) > 0.995:
		up = Vector3.FORWARD if absf(fwd.dot(Vector3.FORWARD)) < 0.995 else Vector3.UP
	var right := fwd.cross(up).normalized()
	var nup := right.cross(fwd).normalized()

	var pivot: Node3D = bone["pivot"]
	pivot.transform = Transform3D(Basis(right, nup, -fwd), from)

	# Le maillage part de l'origine du pivot et s'etend le long de -Z sur sa
	# longueur de modelisation : on l'etire pour rattraper la longueur de l'os.
	var mi: MeshInstance3D = bone["mesh"]
	mi.scale = Vector3(1.0, 1.0, d / float(bone["rest"]))


# --------------------------------------------------------------------------
# Construction du corps (pieces de civic_driver.glb)
# --------------------------------------------------------------------------

func _build_hands() -> void:
	# Les poses se lisent dans les animations du .glb AVANT d'adopter les mains :
	# le lecteur d'animation reste dans le modele source, qui sera libere.
	var player := _parts.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_poses_l = _read_poses(player, "L_")
	_poses_r = _read_poses(player, "R_")
	_hand_l = _adopt("DRV_Hand_L", self)
	_hand_l.name = "HandL"
	_hand_r = _adopt("DRV_Hand_R", self)
	_hand_r.name = "HandR"
	_wrist_l = _wrist_of(_hand_l, "DRV_Wrist_L")
	_wrist_r = _wrist_of(_hand_r, "DRV_Wrist_R")
	_skel_l = _hand_l.find_child("Skeleton3D", true, false) as Skeleton3D
	_skel_r = _hand_r.find_child("Skeleton3D", true, false) as Skeleton3D
	_bones_l = _bone_indices(_skel_l, _poses_l)
	_bones_r = _bone_indices(_skel_r, _poses_r)
	if _skel_l == null or _poses_l.is_empty():
		push_warning("mains sans squelette ou sans poses dans civic_driver.glb : doigts figes")


## Poses d'une main : une animation d'une image par pose (`L_open`, `L_g16`...),
## exportees par civic_hand.py. On echantillonne chaque piste de rotation a t=0.
func _read_poses(player: AnimationPlayer, prefix: String) -> Dictionary:
	var poses := {}
	if player == null:
		return poses
	for anim_name in player.get_animation_list():
		if not anim_name.begins_with(prefix):
			continue
		var anim := player.get_animation(anim_name)
		var rots := {}
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var path := anim.track_get_path(i)
			# Chaque animation exportee contient les pistes des DEUX squelettes (l'autre
			# main au repos) : on ne garde que celles de cette main.
			if path.get_subname_count() == 0 or not String(path).contains("DRV_Hand_" + prefix.trim_suffix("_")):
				continue
			rots[String(path.get_subname(0))] = anim.rotation_track_interpolate(i, 0.0)
		poses[anim_name.trim_prefix(prefix)] = rots
	return poses


func _bone_indices(skel: Skeleton3D, poses: Dictionary) -> Dictionary:
	var idx := {}
	if skel == null or not poses.has("open"):
		return idx
	for bone in poses["open"]:
		var i := skel.find_bone(bone)
		if i >= 0:
			idx[bone] = i
	return idx


## Pose des doigts pour une prise de rayon `radius` (m), fermee a `closed` (0 = main
## ouverte, 1 = refermee). La prise est interpolee entre les poses de rayon voisin.
func _apply_fingers(skel: Skeleton3D, poses: Dictionary, idx: Dictionary, radius: float, closed: float) -> void:
	if skel == null or idx.is_empty():
		return
	var r := clampf(radius, POSE_RADII[0], POSE_RADII[POSE_RADII.size() - 1])
	var k := 0
	while k < POSE_RADII.size() - 2 and r > POSE_RADII[k + 1]:
		k += 1
	var t := clampf((r - POSE_RADII[k]) / (POSE_RADII[k + 1] - POSE_RADII[k]), 0.0, 1.0)
	var a: Dictionary = poses[POSE_NAMES[k]]
	var b: Dictionary = poses[POSE_NAMES[k + 1]]
	var open: Dictionary = poses["open"]
	for bone in idx:
		var grip: Quaternion = (a[bone] as Quaternion).slerp(b[bone], t)
		var q: Quaternion = (open[bone] as Quaternion).slerp(grip, closed)
		skel.set_bone_pose_rotation(idx[bone], q)


## Decalage de l'objet tenu par rapport a l'origine de la main (repere de la main) :
## les poses sont construites autour d'une barre tangente a la paume, dont le centre
## s'eloigne de la paume quand le rayon grandit.
func held_offset() -> Vector3:
	var away := PALM_AWAY_L if item_left else PALM_AWAY_R
	return away * maxf(item_radius - WHEEL_GRIP_R, 0.0)


func _build_body() -> void:
	# Le buste du modele est exprime depuis SPINE : le noeud pivote sur l'axe du
	# buste quand on se retourne, il ne doit donc pas etre a l'origine du conducteur.
	_torso = _adopt("DRV_Torso", self)
	_torso.name = "Torso"
	# La camera EST la tete : on ne la dessine pas.
	var head := _torso.find_child("DRV_Head", true, false)
	if head != null:
		head.visible = false


func _wrist_of(hand: Node3D, wrist_name: String) -> Vector3:
	var w := hand.find_child(wrist_name, true, false) as Node3D
	if w == null:
		push_warning("%s absent du modele : l'avant-bras visera la jante" % wrist_name)
		return Vector3.ZERO
	return w.position


func _build_arms() -> void:
	_arm_lu = _make_bone("DRV_ArmUpper_L", "ArmUpper")
	_arm_lf = _make_bone("DRV_Forearm_L", "Forearm")
	_arm_ru = _make_bone("DRV_ArmUpper_R", "ArmUpper")
	_arm_rf = _make_bone("DRV_Forearm_R", "Forearm")


func _build_legs() -> void:
	_thigh_l = _make_bone("DRV_Thigh_L", "Thigh")
	_shin_l = _make_bone("DRV_Shin_L", "Shin")
	_thigh_r = _make_bone("DRV_Thigh_R", "Thigh")
	_shin_r = _make_bone("DRV_Shin_R", "Shin")

	_foot_l = _adopt("DRV_Foot_L", self)
	_foot_l.name = "FootL"
	_foot_l.position = ANKLE_L
	_foot_r = _adopt("DRV_Foot_R", self)
	_foot_r.name = "FootR"
	_foot_r.position = ANKLE_R


## Detache un noeud du .glb (avec ses enfants) et le place sous `parent` a la
## transform identite : ses enfants gardent leurs positions dans son repere.
func _adopt(part_name: String, parent: Node3D) -> Node3D:
	var n := _parts.find_child(part_name, true, false) as Node3D
	if n == null:
		push_error("%s introuvable dans civic_driver.glb" % part_name)
		n = Node3D.new()
	elif n.get_parent() != null:
		n.get_parent().remove_child(n)
	# Les noeuds du .glb appartiennent a leur scene d'origine : on rompt ce lien,
	# sinon Godot se plaint d'un "owner" incoherent a chaque add_child.
	_disown(n)
	parent.add_child(n)
	n.transform = Transform3D()
	_dim(n)
	_no_shadows(n)
	return n


## Un "os" = un pivot plus le maillage du segment, oriente le long de -Z du pivot.
func _make_bone(part_name: String, kind: String) -> Dictionary:
	var src := _parts.find_child(part_name, true, false) as MeshInstance3D
	if src == null:
		return {}                   # segment absent du modele (les bras ont ete retires) : ignore
	var pivot := Node3D.new()
	pivot.name = part_name
	add_child(pivot)

	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	pivot.add_child(mi)
	_dim(mi)
	_no_shadows(mi)

	return {"pivot": pivot, "mesh": mi, "rest": REST_LEN[kind]}


## Rabat les albedos du modele sur la palette de nuit (voir cabin.gd).
func _dim(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(s)
				if src == null:
					continue
				if not _mat_cache.has(src):
					var copy := src.duplicate()
					if copy is BaseMaterial3D:
						var c: Color = (copy as BaseMaterial3D).albedo_color
						(copy as BaseMaterial3D).albedo_color = Color(
							c.r * BODY_DIM, c.g * BODY_DIM, c.b * BODY_DIM, c.a)
					if (copy as BaseMaterial3D).albedo_texture != null:
						(copy as BaseMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					_mat_cache[src] = copy
				mi.set_surface_override_material(s, _mat_cache[src])
	for c in n.get_children():
		_dim(c)


func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


func _disown(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_disown(c)
