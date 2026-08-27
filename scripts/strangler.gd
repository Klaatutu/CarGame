extends Node3D
##
## L'ETRANGLEUR — troisieme ennemi.
##
## Le geant ecrase la voiture de dehors, le mille-pattes la traverse comme si
## elle n'existait pas. Celui-ci fait la troisieme chose, la pire : il considere
## que la voiture n'est pas un abri mais UNE POIGNEE. Un humanoide decharne,
## debout au milieu de la voie, dont les bras descendent aux chevilles. Le
## percuter ou le froler, c'est passer a portee de ces bras-la : il s'agrippe a
## la caisse et il ne la lache plus.
##
## IL NE MARCHE PAS SUR LA VOITURE, IL VA DE PRISE EN PRISE.
## -------------------------------------------------------------------------
## La carrosserie n'est pas un sol, c'est une suite de POIGNEES : le bord du
## capot, l'auvent d'essuie-glaces, le montant A, la ceinture de caisse. Chaque
## prise est un point nomme, avec sa normale (ou est l'air) et la direction des
## doigts (ce que la main enserre). De chacune, une seule suivante mene vers la
## portiere du meme cote — pas de graphe, pas de recherche de chemin : une
## chaine, comme les prises d'une voie d'escalade.
##
## La regle des mains est celle du volant (driver.gd) : UNE MAIN NE LACHE QUE
## SI L'AUTRE TIENT. Une main plantee est plantee — point fixe en espace
## voiture, doigts refermes — pendant que l'autre vole vers la prise suivante.
## Le corps, lui, n'est tenu par rien d'autre : il pend sous les mains sur les
## flancs, il rampe accroupi sur le capot, et c'est la position des prises qui
## decide de la posture, pas un etat de plus.
##
## Chaque main qui claque sur la tole passe par car.impact() : le joueur SENT
## chaque prise dans la suspension avant meme de tourner la tete. C'est le
## meme canal que les pas du geant — la caisse est l'instrument, tout le monde
## en joue.
##
## LA PORTIERE EST UNE FIN DE VOIE.
## -------------------------------------------------------------------------
## Arrive a la ceinture de caisse, il secoue la poignee exterieure — plusieurs
## fois, le temps qu'on comprenne ce qui arrive — puis la porte s'ouvre
## (cabin.set_door) et il entre par l'ouverture : voiture lancee, il arrache le
## conducteur de son siege et le jette sur la chaussee ; voiture arretee, il
## referme les mains sur sa gorge. Les deux fins passent par le signal
## `caught`, c'est main.gd qui filme la suite.
##
## Si la vitre de cette portiere est deja bien descendue, il ne s'embarrasse
## pas de la poignee : il passe les bras par le jour. Une vitre ouverte etait
## deja une entree pour le mille-pattes ; elle l'est pour tout le monde.
##
## ON L'ARRETE AU REVOLVER, ET SEULEMENT LA.
## -------------------------------------------------------------------------
## Ni le freinage ni les embardees ne le decrochent (il se cramponne, comme le
## mille-pattes sous 12 m/s^2 — s'agripper est son metier a lui aussi). Ce qui
## le decroche, c'est HEALTH balles : le rayon du revolver le teste par le
## groupe "shootable", analytiquement, capsule par capsule — pas de corps
## physique, donc pas le retard d'une image du serveur qui faisait deja rater
## le paquet de cigarettes a 24 m/s (README, la visee sans physique). La tete
## compte double : c'est une tete.
##
## CHAQUE BALLE QUI PORTE SE VOIT PORTER.
## -------------------------------------------------------------------------
## Trois retours par impact, aucun n'est un chiffre. Le corps ENCAISSE : le
## buste part avec le coup, le bassin recule d'un pas de rien, la tete claque
## en arriere — et tout revient pendant le temps d'arret. Les mains, elles,
## ne bougent pas : la regle du volant tient aussi sous les balles. Une GERBE
## de gouttes s'echappe le long de la normale, en espace monde et avec la
## vitesse de la caisse (impact_burst.gd — l'eclair de bouche l'eclaire). Et
## l'impact RESTE : un point sombre plante dans l'os touche, qui suit le
## membre jusqu'au tas final. Un tir sur le cadavre eclabousse et marque
## encore ; il ne fait plus rien d'autre.
##
## Mort, il lache tout : parti avec la vitesse de la voiture, il culbute sur la
## chaussee et y reste, tas d'os dans le retroviseur.
##

const Retro := preload("res://scripts/retro.gd")
const Burst := preload("res://scripts/impact_burst.gd")

# --------------------------------------------------------------------------
# Anatomie. Un homme trop grand dont TOUT l'exces est parti dans les bras.
# --------------------------------------------------------------------------

## Stature. 2,02 m : grand, pas geant — c'est un homme, et c'est bien pire.
const HEIGHT := 2.02
## Bassin debout. 0,475 de la stature, genoux legerement flechis.
const HIP_STAND := 0.96
const HIP_HALF := 0.085
const TORSO := 0.56                    # bassin -> epaules
const SHOULDER_HALF := 0.20
const NECK := 0.10
const SKULL_H := 0.26                  # crane etire en hauteur
const SKULL_W := 0.15

## LES BRAS. Chez l'homme, epaule -> poignet fait 0,31 de la stature (0,63 m
## ici). Les siens font plus du double : mains ballantes, les doigts frolent
## ses chevilles. C'est LA mesure qui fait le personnage — tout le reste est
## un homme maigre.
const UPPER_ARM := 0.64
const FOREARM := 0.60
const PALM := 0.10
const FINGER_1 := 0.13                 # phalange proximale
const FINGER_2 := 0.11                 # le reste du doigt
## Portee epaule -> bout des doigts. Sert a la prise ET aux bancs d'essai.
const ARM_REACH := UPPER_ARM + FOREARM + PALM + FINGER_1 + FINGER_2   # 1,58

const THIGH := 0.50
const SHIN := 0.48
const FOOT_LEN := 0.30

## Epaisseurs : des os habilles. Le geant est sec, lui est DECHARNE.
const THICK_ARM := 0.044
const THICK_FORE := 0.037
const THICK_THIGH := 0.058
const THICK_SHIN := 0.046
const THICK_FINGER := 0.012

## Les os qui arretent une balle : les segments du squelette de l'image (_j),
## testes capsule par capsule. Le crane est une sphere a part — il compte
## double. La meme table sert au rayon (ray_hit) et a poser les marques.
const CAPS := [
	["chest", "pelvis", 0.13],
	["neck", "chest", 0.07],
	["shoulder_l", "elbow_l", THICK_ARM + 0.02],
	["elbow_l", "wrist_l", THICK_FORE + 0.02],
	["shoulder_r", "elbow_r", THICK_ARM + 0.02],
	["elbow_r", "wrist_r", THICK_FORE + 0.02],
	["hip_l", "knee_l", THICK_THIGH + 0.02],
	["knee_l", "ankle_l", THICK_SHIN + 0.02],
	["hip_r", "knee_r", THICK_THIGH + 0.02],
	["knee_r", "ankle_r", THICK_SHIN + 0.02],
]

## Le sang : sombre, a peine rouge — dans les phares un rouge de nuit, hors
## d'eux un trou de plus dans la silhouette pale. La marque est plus sombre
## encore : sur une peau a 0,34, des trous lisent mieux que des braises.
const BLOOD := Color(0.11, 0.022, 0.018)
const WOUND := Color(0.045, 0.010, 0.009)
## La gerbe d'un impact : combien de gouttes, a quelle vitesse, vivant combien.
const GORE_COUNT := 7
const GORE_SPEED := 3.4
const GORE_SIZE := 0.017
const GORE_LIFE := 0.55

# --------------------------------------------------------------------------
# Les prises. En espace voiture, cote GAUCHE ; la droite est le miroir en x.
# --------------------------------------------------------------------------
##
## p : ou la paume se pose.  n : normale, vers l'air.  f : direction des
## doigts, ce que la main enserre (le bord du capot, la ceinture...). n et f
## sont redressees a la construction de la pose, pas besoin d'etre exactes.
##
## Les cotes sortent de civic_dims.py : nez a z -1,98, ceinture a 0,97, tole de
## flanc a 0,82, auvent a z -0,92, montant A de (0,80, 0,95, -0,90) a
## (0,75, 1,28, -0,35). La poignee exterieure est a (0,825, 0,90, 0,42).
const GRIPS := {
	"bumper": {"p": Vector3(-0.42, 0.70, -1.96), "n": Vector3(0.0, 0.50, -0.87),
		"f": Vector3(0.0, 0.87, 0.50)},
	"hood_lo": {"p": Vector3(-0.45, 0.80, -1.50), "n": Vector3(0.0, 1.0, 0.0),
		"f": Vector3(0.0, 0.0, 1.0)},
	"hood_hi": {"p": Vector3(-0.52, 0.88, -1.05), "n": Vector3(0.0, 1.0, 0.0),
		"f": Vector3(0.0, 0.0, 1.0)},
	"cowl": {"p": Vector3(-0.50, 0.94, -0.90), "n": Vector3(0.0, 0.90, -0.44),
		"f": Vector3(0.0, 0.44, 0.90)},
	"apillar": {"p": Vector3(-0.77, 1.12, -0.60), "n": Vector3(-0.93, 0.10, -0.35),
		"f": Vector3(0.09, 0.51, 0.85)},
	"sill_front": {"p": Vector3(-0.818, 0.98, -0.35), "n": Vector3(-1.0, 0.12, 0.0),
		"f": Vector3(0.85, -0.50, 0.0)},
	"door": {"p": Vector3(-0.818, 0.98, 0.08), "n": Vector3(-1.0, 0.12, 0.0),
		"f": Vector3(0.85, -0.50, 0.0)},
	"sill_rear": {"p": Vector3(-0.818, 0.98, 0.52), "n": Vector3(-1.0, 0.12, 0.0),
		"f": Vector3(0.85, -0.50, 0.0)},
	"quarter": {"p": Vector3(-0.825, 0.98, 1.15), "n": Vector3(-1.0, 0.12, 0.0),
		"f": Vector3(0.85, -0.50, 0.0)},
	"tail": {"p": Vector3(-0.45, 0.93, 1.96), "n": Vector3(0.0, 0.35, 0.94),
		"f": Vector3(0.0, 0.94, -0.35)},
}

## La prise SUIVANTE, vers la portiere du meme cote. Une chaine par versant :
## tout ce qui accroche a l'avant remonte le capot et redescend par le montant,
## tout ce qui accroche a l'arriere longe la ceinture. "door" est la fin.
const CHAIN := {
	"bumper": "hood_lo",
	"hood_lo": "hood_hi",
	"hood_hi": "cowl",
	"cowl": "apillar",
	"apillar": "sill_front",
	"sill_front": "door",
	"tail": "quarter",
	"quarter": "sill_rear",
	"sill_rear": "door",
	"door": "",
}

## Poignee exterieure de portiere (espace voiture, cote gauche).
const HANDLE_P := Vector3(-0.825, 0.90, 0.42)
## L'oeil du conducteur (car.HEAD_POS) — c'est la qu'il regarde, et c'est la
## que ses mains finissent.
const DRIVER_EYE := Vector3(-0.33, 1.15, 0.28)

# --------------------------------------------------------------------------
# Reglages
# --------------------------------------------------------------------------

@export_group("Sur la route")
## Distance a laquelle il ecarte les bras. C'est un geste de gardien de but :
## il annonce la prise, et il bouche la voie. 42 m : juste au bord de ce que
## les phares revelent — la premiere image qu'on a de lui est la croix.
@export var spread_distance := 42.0
## Vitesse de son pas de cote quand il se place devant la voiture, m/s. Assez
## pour qu'un coup de volant mou ne suffise pas, pas assez pour etre imparable.
@export var sidestep_speed := 2.6
## Rayon de prise : distance entre son buste et la CAISSE en dessous de
## laquelle il s'agrippe au passage. Ses bras font 1,58 m ; on garde 1,15 —
## il lui faut le temps de refermer la main.
@export var grab_reach := 1.15

@export_group("Sur la voiture")
## Pause entre deux mouvements de main, en secondes.
@export var move_pause := 0.16
## Duree de vol d'une main : base, plus tant par metre.
@export var fly_time := 0.24
@export var fly_per_meter := 0.42
## Ce qu'une main qui claque envoie dans la caisse, m/s^2. Sous le seuil des
## objets (23,5) : les canettes tremblent, elles ne decollent pas — lui n'est
## pas un pied de geant, c'est une main.
@export var plant_accel := 9.0
## Le choc initial quand la voiture le PERCUTE, m/s^2.
@export var hit_accel := 38.0
## Secousses de la voiture au-dela desquelles il s'arrete et se cramponne,
## comme le mille-pattes. Freiner a mort achete une seconde, pas plus.
@export var brace_accel := 14.0

@export_group("La portiere")
## Nombre de secousses de poignee avant que la porte cede, et leur periode.
@export var yank_count := 5
@export var yank_period := 0.75
## Duree d'ouverture de la porte, et son angle.
@export var door_time := 0.55
@export var door_angle := 62.0
## Vitre descendue d'au moins ca : il passe par le jour au lieu de la poignee.
@export var window_min_open := 0.55
## Duree du geste final, des mains qui partent aux mains qui se referment.
@export var reach_time := 1.5
## En dessous de cette vitesse (m/s) il etrangle ; au-dessus il jette dehors.
@export var throw_speed := 2.5

@export_group("Le corps")
## Balles a encaisser. La tete compte double.
@export var health_max := 5.0
## Temps d'arret apres une balle : il encaisse, il ne l'ignore pas.
@export var stagger_time := 0.45
## L'encaissement qui se VOIT : debattement du buste (degres) et recul du
## bassin (metres) sous une balle. L'un et l'autre partent avec le coup et
## reviennent pendant le temps d'arret — les mains, elles, restent plantees.
@export var flinch_deg := 15.0
@export var flinch_shift := 0.09
## Une fois mort sur la chaussee, temps avant de s'eteindre.
@export var corpse_time := 9.0

@export_group("Voix")
@export var scream_volume_db := 1.0
@export var thump_volume_db := -2.0
@export var breath_volume_db := -6.0
@export var sound_unit := 10.0

enum {
	HIDDEN,      ## eteint, hors du monde
	ROAD,        ## debout au milieu de la voie, il attend
	CLIMBING,    ## agrippe, il va de prise en prise
	AT_DOOR,     ## pendu a la portiere, il secoue la poignee
	OPENING,     ## la porte cede
	ATTACKING,   ## les bras passent dans l'habitacle
	CAUGHT,      ## les mains sont sur le conducteur ; main.gd filme
	FALLING,     ## abattu : il part en culbute
	CORPSE,      ## en tas sur la chaussee
}

## Les mains sont sur le joueur. mode : "throw" ou "strangle".
signal caught(mode: String)
## Il est tombe (abattu), d'ou qu'il soit tombe.
signal died

## La voiture. Pose par road.gd avec arm().
var target: Node3D
var state := HIDDEN
var health := 5.0

## Cote vise : -1 portiere gauche, +1 droite. Fixe par la prise d'accrochage.
var door_side := -1.0

# Ce que les bancs d'essai relisent.
var plants := 0                        ## mains posees depuis l'accrochage
var yanks := 0                         ## secousses de poignee
var last_grip := ""                    ## derniere prise atteinte par le corps
var caught_mode := ""
var wounds := 0                        ## impacts marques sur le corps
var gore := 0                          ## gouttes parties, en cumul

var _home: Node                        ## parent d'origine (la route)
var _rng := RandomNumberGenerator.new()

# --- route ------------------------------------------------------------------
var _spread := 0.0                     ## bras ecartes, 0..1
var _sway := 0.0

# --- escalade ---------------------------------------------------------------
## Etat de chaque main (0 gauche, 1 droite du MONSTRE) :
##   name/gside : la prise tenue (gside est le cote voiture de la prise)
##   pos        : position courante de la paume, espace parent
##   from/to    : bornes du vol en cours, t sa progression (-1 : plantee)
var _hands := [{}, {}]
var _hand_t := [-1.0, -1.0]
var _hand_from := [Vector3.ZERO, Vector3.ZERO]
var _hand_curl := [0.3, 0.3]
var _body_grip := ""
var _lead := 0                         ## la main qui volera la prochaine
var _pause := 0.0
var _stagger := 0.0
## L'encaissement d'une balle, 1 a l'impact puis 0 : les poses le lisent.
var _flinch := 0.0
var _flinch_dir := Vector3.FORWARD     ## espace noeud : ou la balle pousse
var _flinch_head := false
var _wound_marks: Array = []           ## les impacts poses sur les os
var _pelvis := Vector3.ZERO            ## espace parent
var _basis := Basis()
## Pieds : point plante en espace parent, et vol de rattrapage.
var _feet := [Vector3.ZERO, Vector3.ZERO]
var _foot_t := [-1.0, -1.0]
var _foot_from := [Vector3.ZERO, Vector3.ZERO]

# --- portiere ---------------------------------------------------------------
var _yank_t := 0.0
var _door_amount := 0.0
var _through_window := false

# --- attaque ----------------------------------------------------------------
var _reach_t := 0.0

# --- chute ------------------------------------------------------------------
var _fall_vel := Vector3.ZERO
var _fall_axis := Vector3.RIGHT
var _fall_rate := 0.0
var _corpse_t := 0.0

# --- corps ------------------------------------------------------------------
var _mat_skin: ShaderMaterial
var _mat_dark: ShaderMaterial
var _mat_wound: ShaderMaterial
var _hips_m: MeshInstance3D
var _chest_m: MeshInstance3D
var _shoulder_m: MeshInstance3D
var _neck_m: MeshInstance3D
var _skull_m: MeshInstance3D
var _jaw: Node3D
var _head: Node3D
var _upper_m: Array[MeshInstance3D] = []
var _fore_m: Array[MeshInstance3D] = []
var _thigh_m: Array[MeshInstance3D] = []
var _shin_m: Array[MeshInstance3D] = []
var _foot_m: Array[MeshInstance3D] = []
var _hand_n: Array[Node3D] = []        ## noeud de paume, doigts en dessous
var _fingers: Array = []               ## [main][doigt] -> [proximal, distal]
var _joint_m: Array[MeshInstance3D] = []
var _jaw_open := 0.0
## Squelette de l'image, en espace MONDE : c'est la-dessus qu'on tire.
var _j := {}

var _scream_snd: AudioStreamPlayer3D
var _hurt_snd: AudioStreamPlayer3D
var _breath_snd: AudioStreamPlayer3D
var _thump_snd: Array[AudioStreamPlayer3D] = []
var _rattle_snd: AudioStreamPlayer3D
var _creak_snd: AudioStreamPlayer3D


func _ready() -> void:
	_rng.randomize()
	_build_body()
	_build_audio()
	_home = get_parent()
	add_to_group("shootable")
	visible = false
	set_process(false)


# --------------------------------------------------------------------------
# Vie et mort
# --------------------------------------------------------------------------

## Le pose debout sur la chaussee, face a la voiture. road.gd place le noeud
## puis appelle ceci ; il ne bouge plus jusqu'a ce qu'elle arrive.
func arm(car: Node3D) -> void:
	if get_parent() != _home:
		reparent(_home, false)
	target = car
	state = ROAD
	health = health_max
	door_side = -1.0
	plants = 0
	yanks = 0
	last_grip = ""
	caught_mode = ""
	wounds = 0
	gore = 0
	_clear_wounds()
	_spread = 0.0
	_stagger = 0.0
	_flinch = 0.0
	_door_amount = 0.0
	_through_window = false
	_jaw_open = 0.0
	_pelvis = global_position + Vector3.UP * HIP_STAND
	_basis = global_transform.basis
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_feet[i] = global_position + global_transform.basis.x * (side * 0.14)
		_foot_t[i] = -1.0
		_hand_t[i] = -1.0
		_hands[i] = {}
		_hand_curl[i] = 0.3
	visible = true
	set_process(true)
	if _breath_snd != null and _breath_snd.stream != null:
		_breath_snd.play()
	_pose(0.0)


func asleep() -> bool:
	return state == HIDDEN


func sleep() -> void:
	state = HIDDEN
	visible = false
	set_process(false)
	if _breath_snd != null:
		_breath_snd.stop()
	if get_parent() != _home:
		reparent(_home, false)


# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_stagger = maxf(_stagger - delta, 0.0)
	_flinch = maxf(_flinch - delta / maxf(stagger_time, 0.05), 0.0)

	match state:
		ROAD:
			_road(delta)
		CLIMBING:
			_climb(delta)
		AT_DOOR:
			_door_rattle(delta)
		OPENING:
			_door_open(delta)
		ATTACKING:
			_attack(delta)
		CAUGHT:
			pass                        # main.gd filme ; les mains restent
		FALLING:
			_fall(delta)
		CORPSE:
			_corpse_t -= delta
			if _corpse_t <= 0.0:
				sleep()
				return

	_pose(delta)


# --------------------------------------------------------------------------
# Sur la route
# --------------------------------------------------------------------------

## Debout dans la voie. Il fait face, il se decale pour rester devant, et
## quand la voiture est a portee de bras — ou dedans — il s'agrippe.
func _road(delta: float) -> void:
	var p := target.to_local(global_position)   # moi, en espace voiture

	# Depasse et hors de portee : il n'existe plus, la route en posera un autre.
	if p.z > 26.0:
		sleep()
		return

	# Face a la voiture, toujours.
	var to_car := target.global_position - global_position
	to_car.y = 0.0
	if to_car.length_squared() > 0.01:
		rotation.y = atan2(-to_car.x, -to_car.z)

	var dist := to_car.length()
	_spread = move_toward(_spread, 1.0 if dist < spread_distance else 0.0, delta * 2.2)
	_sway += delta * (0.6 + _spread * 1.5)

	# Le pas de cote : il vise l'axe de la trajectoire, pas la position — la
	# voiture bouge, lui predit. Deplacement en espace voiture, borne pour
	# qu'un vrai evitement reste possible.
	if dist < 65.0 and p.z < -3.0:
		var shift := clampf(-p.x, -sidestep_speed * delta, sidestep_speed * delta)
		var right := target.global_transform.basis.x
		global_position += right * shift
	global_position.y = 0.0

	# La prise. Point de la caisse le plus proche du buste, en espace voiture :
	# s'il est a portee de bras, les bras servent.
	var chest := target.to_local(global_position + Vector3.UP * 1.3)
	var box := Vector3(0.84, 0.0, 1.98)
	var q := Vector3(clampf(chest.x, -box.x, box.x), chest.y,
		clampf(chest.z, -box.z, box.z))
	var gap := Vector2(chest.x - q.x, chest.z - q.z).length()
	var inside := absf(chest.x) < box.x + 0.10 and absf(chest.z) < box.z + 0.30
	if gap < grab_reach or inside:
		_latch(chest, inside)


## Il s'agrippe. La prise d'accrochage est la plus proche de son buste ; elle
## fixe le cote, donc la portiere visee, donc toute la voie.
func _latch(chest_car: Vector3, rammed: bool) -> void:
	var best := ""
	var best_side := -1.0
	var best_d := INF
	for name in GRIPS:
		for side in [-1.0, 1.0]:
			var g := _grip(name, side)
			var d: float = (g["p"] as Vector3).distance_to(chest_car)
			if d < best_d:
				best_d = d
				best = name
				best_side = side
	door_side = best_side

	if rammed:
		# Percute : la caisse encaisse le corps entier, et tout ce qui traine
		# dans l'habitacle decolle (le seuil des objets est a 23,5 m/s^2).
		target.impact((Vector3.UP * 0.7 + Vector3.BACK * 0.7).normalized() * hit_accel)

	reparent(target, true)
	state = CLIMBING
	_body_grip = best
	last_grip = best
	_pause = 0.35 if rammed else 0.1
	_lead = 0
	plants = 0

	# Les deux mains claquent sur la prise d'accrochage, cote a cote.
	var g0 := _grip(best, door_side)
	for i in 2:
		_hands[i] = {"name": best, "off": _hand_offset(i, g0)}
		_hand_t[i] = -1.0
		_hand_curl[i] = 0.85
		_plant_noise(i)
	# Le corps part d'ou il est — le reparentage a garde la pose monde, donc
	# transform est deja la meme chose en espace voiture. L'origine du noeud
	# etait au sol : le bassin demarre une stature de bassin plus haut, et le
	# ressort de _pose_climb l'amene a la prise.
	_pelvis = transform.origin + Vector3.UP * HIP_STAND
	_basis = transform.basis
	for i in 2:
		_feet[i] = _pelvis + Vector3.DOWN * 0.8
		_foot_t[i] = -1.0
	_scream()
	_jaw_open = 1.0


## Une prise, resolue pour un cote. Les cotes du dictionnaire sont ceux du
## flanc GAUCHE ; le flanc droit est leur miroir en x.
func _grip(name: String, side: float) -> Dictionary:
	var g: Dictionary = GRIPS[name]
	if side > 0.0:
		return {"p": _mx(g["p"]), "n": _mx(g["n"]), "f": _mx(g["f"])}
	return {"p": g["p"], "n": g["n"], "f": g["f"]}


func _mx(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## Ou la main i se pose sur une prise : cote a cote, ecartees le long des
## doigts croises avec la normale (la tangente de la prise).
func _hand_offset(i: int, g: Dictionary) -> Vector3:
	var t: Vector3 = (g["n"] as Vector3).cross(g["f"]).normalized()
	return t * (0.11 if i == 0 else -0.11)


func _hand_pos(i: int) -> Vector3:
	if _hand_t[i] >= 0.0:
		return _hand_from[i].lerp(_hand_goal(i), _fly_ease(_hand_t[i])) \
			+ _fly_lift(i)
	return _hand_goal(i)


func _hand_goal(i: int) -> Vector3:
	var h: Dictionary = _hands[i]
	if h.is_empty():
		return _pelvis
	var g := _grip(h["name"], door_side)
	return (g["p"] as Vector3) + (h["off"] as Vector3)


func _fly_ease(t: float) -> float:
	return smoothstep(0.0, 1.0, t)


## L'arc du vol : la main se souleve le long de la normale de la prise visee.
func _fly_lift(i: int) -> Vector3:
	var g := _grip(_hands[i]["name"], door_side)
	return (g["n"] as Vector3) * (0.16 * sin(PI * clampf(_hand_t[i], 0.0, 1.0)))


# --------------------------------------------------------------------------
# L'escalade
# --------------------------------------------------------------------------

func _climb(delta: float) -> void:
	# Secousse de la caisse : il se cramponne et attend que ca passe. Ca
	# n'achete qu'une pause — s'agripper est son metier.
	if target.frame_accel.length() > brace_accel:
		_pause = maxf(_pause, 0.5)

	_advance_hands(delta)

	# Les deux mains tiennent, la pause est purgee : la suivante decolle.
	if _hand_t[0] < 0.0 and _hand_t[1] < 0.0 and _stagger <= 0.0:
		_pause -= delta
		if _pause <= 0.0:
			_next_move()

	if _body_grip == "door" and _hand_t[0] < 0.0 and _hand_t[1] < 0.0 \
			and String(_hands[0]["name"]) == "door" \
			and String(_hands[1]["name"]) == "door":
		_arrive_at_door()


func _advance_hands(delta: float) -> void:
	for i in 2:
		if _hand_t[i] < 0.0:
			continue
		var d: float = _hand_from[i].distance_to(_hand_goal(i))
		var dur := fly_time + fly_per_meter * d
		_hand_t[i] += delta / maxf(dur, 0.05)
		_hand_curl[i] = lerpf(_hand_curl[i], 0.25, clampf(delta * 10.0, 0.0, 1.0))
		if _hand_t[i] >= 1.0:
			_hand_t[i] = -1.0
			_hand_curl[i] = 0.85
			plants += 1
			_plant_noise(i)
			_pause = move_pause


## Le prochain geste. Les mains avancent en echelle : celle de tete part vers
## la prise suivante, le corps la rejoint, l'autre main la rattrape. Une seule
## main en vol a la fois — l'autre TIENT, c'est la regle du volant.
func _next_move() -> void:
	var lead_h: Dictionary = _hands[_lead]
	var trail := 1 - _lead
	if String(lead_h["name"]) == _body_grip:
		# Les deux mains sont sur la prise du corps : la main de tete part.
		var next: String = CHAIN.get(_body_grip, "")
		if next == "":
			return
		_fly_hand(_lead, next)
	else:
		# La main de tete est deja sur la prise d'apres : le corps s'y avance
		# et la main arriere la rejoint.
		_body_grip = String(lead_h["name"])
		last_grip = _body_grip
		_fly_hand(trail, _body_grip)
		_lead = trail


func _fly_hand(i: int, grip_name: String) -> void:
	_hand_from[i] = _hand_pos(i)
	_hands[i] = {"name": grip_name}
	var g := _grip(grip_name, door_side)
	_hands[i]["off"] = _hand_offset(i, g)
	_hand_t[i] = 0.0


## Une main claque sur la tole : le bruit, et le coup dans la caisse.
func _plant_noise(i: int) -> void:
	if state == HIDDEN:
		return
	var p := _thump_snd[i]
	if p != null and p.stream != null:
		p.pitch_scale = 1.0 + _rng.randf_range(-0.08, 0.08)
		p.play()
	if target != null and target.has_method("impact"):
		var g := _grip(_hands[i]["name"], door_side)
		var away: Vector3 = -(g["n"] as Vector3)
		target.impact((away * 0.8 + Vector3.DOWN * 0.4).normalized() * plant_accel)


func _arrive_at_door() -> void:
	# La vitre de ce cote est-elle assez descendue pour passer les bras ? Et
	# la porte n'est-elle pas DEJA ouverte — un survivant du precedent ne l'a
	# peut-etre jamais refermee ?
	_through_window = false
	var already_open := false
	if "cabin" in target and target.cabin != null:
		for w in target.cabin.windows:
			if signf(w.side) == signf(door_side) and w.open >= window_min_open:
				_through_window = true
		already_open = target.cabin.door_amount(
			"L" if door_side < 0.0 else "R") > deg_to_rad(25.0)
	if _through_window or already_open:
		state = ATTACKING
		_reach_t = 0.0
		_scream()
	else:
		state = AT_DOOR
		_yank_t = yank_period * 0.6
		yanks = 0


# --------------------------------------------------------------------------
# La portiere
# --------------------------------------------------------------------------

## Pendu a la ceinture, une main sur la poignee exterieure : il secoue. C'est
## la fenetre de tir la plus confortable — il est immobile, a un metre, de
## l'autre cote d'une vitre qui n'arrete pas les balles.
func _door_rattle(delta: float) -> void:
	if _stagger > 0.0:
		return
	_yank_t += delta
	if _yank_t >= yank_period:
		_yank_t = 0.0
		yanks += 1
		if _rattle_snd != null and _rattle_snd.stream != null:
			_rattle_snd.pitch_scale = 1.0 + _rng.randf_range(-0.06, 0.06)
			_rattle_snd.play()
		if target.has_method("impact"):
			target.impact(Vector3(door_side, 0.15, 0.0).normalized() * 6.0)
		if yanks >= yank_count:
			state = OPENING
			_door_amount = 0.0
			if _creak_snd != null and _creak_snd.stream != null:
				_creak_snd.play()
			_scream()
			_jaw_open = 1.0


func _door_open(delta: float) -> void:
	_door_amount = minf(_door_amount + delta / door_time, 1.0)
	_set_door(_door_amount)
	if _door_amount >= 1.0:
		if target.has_method("impact"):
			target.impact(Vector3(door_side, 0.2, 0.0).normalized() * 10.0)
		state = ATTACKING
		_reach_t = 0.0


func _set_door(amount: float) -> void:
	if "cabin" in target and target.cabin != null \
			and target.cabin.has_method("set_door"):
		target.cabin.set_door("L" if door_side < 0.0 else "R",
			amount * deg_to_rad(door_angle))


# --------------------------------------------------------------------------
# L'attaque
# --------------------------------------------------------------------------

## Les bras passent dans l'habitacle et vont chercher le conducteur. C'est la
## DERNIERE fenetre de tir : les deux mains sont parties, rien ne tient plus
## que l'epaule calee dans l'ouverture.
func _attack(delta: float) -> void:
	_reach_t += delta * (0.0 if _stagger > 0.0 else 1.0)
	_jaw_open = 1.0
	if _reach_t >= reach_time:
		state = CAUGHT
		caught_mode = "strangle" if absf(target.speed) < throw_speed else "throw"
		_hand_curl[0] = 0.95
		_hand_curl[1] = 0.95
		caught.emit(caught_mode)


# --------------------------------------------------------------------------
# Balles, chute, cadavre
# --------------------------------------------------------------------------

## Le rayon du revolver. `from` et `dir` en espace MONDE ; on repond la
## distance du premier os touche, capsule par capsule sur le squelette de
## l'image. La tete est une sphere a part : elle compte double.
func ray_hit(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	if state == HIDDEN or _j.is_empty():
		return {}
	var best_d := max_d
	var best_q := Vector3.ZERO
	var head := false
	for c in CAPS:
		var r := _ray_capsule(from, dir, _j[c[0]], _j[c[1]], c[2])
		if r >= 0.0 and r < best_d:
			best_d = r
			best_q = from + dir * r
			head = false
	var rh := _ray_sphere(from, dir, _j["skull"], 0.17)
	if rh >= 0.0 and rh < best_d:
		best_d = rh
		best_q = from + dir * rh
		head = true
	if best_d >= max_d:
		return {}
	var n: Vector3 = (best_q - (_j["chest"] as Vector3)).normalized()
	return {"d": best_d, "pos": best_q, "n": n, "head": head}


## Une balle. Le revolver appelle hit(position, normale) sur ce qu'il touche —
## le meme contrat que pour tout le reste du monde. La normale sert a la
## gerbe (elle part vers l'air) et a l'encaissement (le corps part a l'oppose).
func hit(pos: Vector3, nrm: Vector3) -> void:
	if state == HIDDEN:
		return
	var head := pos.distance_to(_j.get("skull", Vector3.INF)) < 0.24
	# L'impact se voit TOUJOURS, cadavre compris : la marque reste plantee
	# dans l'os, la gerbe part avec la vitesse du corps.
	_mark(pos, head)
	_splash(pos, nrm)
	if state in [FALLING, CORPSE]:
		return
	health -= 2.0 if head else 1.0
	_stagger = stagger_time
	# L'encaissement : le corps part avec le coup — buste, bassin, tete — et
	# revient pendant le temps d'arret. Les poses le lisent dans _flinch.
	_flinch = 1.0
	_flinch_head = head
	var push := -nrm
	if push.length() < 0.5:
		push = global_transform.basis.z
	_flinch_dir = (global_transform.basis.inverse() * push).normalized()
	_jaw_open = 1.0
	if _hurt_snd != null and _hurt_snd.stream != null:
		_hurt_snd.pitch_scale = 1.0 + _rng.randf_range(-0.1, 0.1)
		_hurt_snd.play()
	if health <= 0.0:
		_die()


## La marque d'une balle : un point sombre plante dans l'os touche. Sur la
## tete il est fils du crane et suit tout seul ; sur le reste du corps, la
## pose reecrit les os a chaque image, donc la marque memorise SA place —
## quel segment, ou le long de lui, de quel cote — et _update_wounds la
## repose apres chaque pose.
func _mark(pos_w: Vector3, head: bool) -> void:
	wounds += 1
	var m := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.023
	ball.height = 0.046
	ball.radial_segments = 6
	ball.rings = 3
	m.mesh = ball
	m.material_override = _mat_wound
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if head:
		_head.add_child(m)
		var lp: Vector3 = _head.global_transform.affine_inverse() * pos_w
		m.position = lp * 1.05
		_wound_marks.append({"m": m})
		return
	# Le segment le plus proche du point d'impact — le meme squelette que
	# ray_hit, la meme table CAPS.
	var best_a := ""
	var best_b := ""
	var best_t := 0.0
	var best_d := INF
	for c in CAPS:
		var a: Vector3 = _j[c[0]]
		var b: Vector3 = _j[c[1]]
		var ab := b - a
		var t := 0.0
		if ab.length_squared() > 0.0001:
			t = clampf((pos_w - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := pos_w.distance_to(a.lerp(b, t))
		if d < best_d:
			best_d = d
			best_a = c[0]
			best_b = c[1]
			best_t = t
	var axis_p: Vector3 = (_j[best_a] as Vector3).lerp(_j[best_b], best_t)
	var rad := pos_w - axis_p
	if rad.length() < 0.005:
		rad = global_transform.basis.x
	add_child(m)
	_wound_marks.append({"m": m, "a": best_a, "b": best_b, "t": best_t,
		"rad": (global_transform.basis.inverse() * rad).normalized(),
		"r": clampf(rad.length(), 0.02, 0.20)})
	_update_wounds()


## Repose les marques sur les os de l'image. La direction radiale est gardee
## en espace noeud puis reprojetee hors de l'axe : le membre peut se replier,
## la marque reste du cote ou la balle est entree, a l'epaisseur de l'os.
func _update_wounds() -> void:
	for w in _wound_marks:
		if not w.has("a"):
			continue
		var a: Vector3 = _j[w["a"]]
		var b: Vector3 = _j[w["b"]]
		var ax := b - a
		if ax.length_squared() < 0.0001:
			continue
		ax = ax.normalized()
		var rad: Vector3 = global_transform.basis * (w["rad"] as Vector3)
		rad -= ax * ax.dot(rad)
		if rad.length() < 0.01:
			rad = ax.cross(Vector3.UP)
			if rad.length() < 0.01:
				rad = ax.cross(Vector3.RIGHT)
		rad = rad.normalized()
		(w["m"] as Node3D).global_position = a.lerp(b, w["t"]) \
			+ rad * (w["r"] as float)


func _clear_wounds() -> void:
	for w in _wound_marks:
		if is_instance_valid(w["m"]):
			(w["m"] as Node).queue_free()
	_wound_marks.clear()


## La gerbe. Elle part le long de la normale AVEC la vitesse du corps : celle
## de la caisse quand il y est accroche, la sienne quand il tombe. Elle vit
## en espace monde — la caisse s'en va, les gouttes retombent ou elles sont.
func _splash(pos_w: Vector3, nrm: Vector3) -> void:
	var v := Vector3.ZERO
	if state == FALLING:
		v = _fall_vel
	elif target != null and is_instance_valid(target) \
			and get_parent() == target and "velocity" in target:
		v = target.velocity
	gore += GORE_COUNT
	Burst.spawn(self, pos_w, nrm, BLOOD, GORE_COUNT, GORE_SPEED, GORE_SIZE,
		GORE_LIFE, v)


func _die() -> void:
	_jaw_open = 0.0
	if state in [ROAD]:
		# Debout sur la chaussee : il s'effondre sur place.
		state = FALLING
		_fall_vel = Vector3.UP * 0.5
		_fall_axis = _basis.x
		_fall_rate = 2.6
	else:
		# Accroche : il lache tout, part avec la vitesse de la voiture et
		# culbute sur la chaussee. La porte reste comme elle est.
		var away := Vector3.ZERO
		if _body_grip != "":
			var g := _grip(_body_grip, door_side)
			away = target.global_transform.basis * (g["n"] as Vector3)
		var v: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
		reparent(_home, true)
		state = FALLING
		_fall_vel = v * 0.85 + away * 2.0 + Vector3.UP * 1.6
		_fall_axis = Vector3(_rng.randf_range(-1, 1), 0.3,
			_rng.randf_range(-1, 1)).normalized()
		_fall_rate = _rng.randf_range(4.0, 7.0)
	died.emit()
	if _breath_snd != null:
		_breath_snd.stop()


## La culbute. Pas de moteur physique : la gravite, une rotation, le sol.
func _fall(delta: float) -> void:
	if get_parent() != _home:
		reparent(_home, true)
	_fall_vel += Vector3.DOWN * 9.81 * delta
	global_position += _fall_vel * delta
	global_rotate(_fall_axis, _fall_rate * delta)
	if global_position.y <= 0.55 and _fall_vel.y < 0.0:
		# Il touche : un rebond mou, puis il glisse et s'arrete.
		global_position.y = 0.55
		if absf(_fall_vel.y) > 2.0:
			_fall_vel.y = absf(_fall_vel.y) * 0.25
			_fall_vel.x *= 0.6
			_fall_vel.z *= 0.6
			_thud()
		else:
			_fall_vel.y = 0.0
			var flat := Vector2(_fall_vel.x, _fall_vel.z)
			flat = flat.move_toward(Vector2.ZERO, 14.0 * delta)
			_fall_vel.x = flat.x
			_fall_vel.z = flat.y
			_fall_rate = move_toward(_fall_rate, 0.0, 9.0 * delta)
			if flat.length() < 0.3:
				_settle_corpse()


func _settle_corpse() -> void:
	state = CORPSE
	_corpse_t = corpse_time
	# A plat dos sur la chaussee : l'axe du corps a l'horizontale, la poitrine
	# vers le ciel, le bassin a hauteur d'os.
	var h := -global_transform.basis.z
	h.y = 0.0
	if h.length_squared() < 0.01:
		h = Vector3.FORWARD
	h = h.normalized()
	var y := h
	var z := -Vector3.UP
	var x := y.cross(z).normalized()
	global_transform = Transform3D(Basis(x, y, z).orthonormalized(),
		Vector3(global_position.x, 0.16, global_position.z))
	_thud()


func _thud() -> void:
	var p := _thump_snd[0]
	if p != null and p.stream != null:
		p.pitch_scale = 0.7
		p.play()


# --------------------------------------------------------------------------
# La pose
# --------------------------------------------------------------------------

func _pose(delta: float) -> void:
	match state:
		ROAD:
			_pose_stand(delta)
		CLIMBING, AT_DOOR, OPENING, ATTACKING, CAUGHT:
			_pose_climb(delta)
		FALLING, CORPSE:
			_pose_limp(delta)
	_record_joints()
	_update_wounds()


## Debout dans la voie. Les bras pendent — jusqu'aux chevilles — puis
## s'ecartent quand la voiture approche : il bouche la route de toute son
## envergure, et cette envergure est le personnage.
func _pose_stand(delta: float) -> void:
	var hip := Vector3(0.0, HIP_STAND + sin(_sway * 0.8) * 0.012, 0.0)
	var lean := deg_to_rad(6.0) + _spread * deg_to_rad(7.0)
	var torso := Basis(Vector3.RIGHT, -lean)
	# La balle : le buste part avec le coup, le bassin recule d'un pas de
	# rien, et tout revient pendant le temps d'arret. Les pieds sont plantes.
	var punch := _flinch * _flinch
	var fl_off := Vector3.ZERO
	if punch > 0.001:
		torso = _flinch_swing(punch) * torso
		fl_off = Vector3(_flinch_dir.x, 0.0, _flinch_dir.z) \
			* (flinch_shift * punch)
		hip += fl_off
	var up: Vector3 = torso * Vector3.UP
	var chest := hip + up * TORSO

	_bone(_hips_m, hip + Vector3(-HIP_HALF, 0, 0), hip + Vector3(HIP_HALF, 0, 0),
		THICK_THIGH * 1.35)
	_bone(_chest_m, hip, chest, 0.105)
	_bone(_shoulder_m, chest + Vector3(-SHOULDER_HALF, 0.0, 0.0),
		chest + Vector3(SHOULDER_HALF, 0.0, 0.0), 0.052)
	_head_pose(chest, up, delta)

	# Jambes : plantees ou elles sont (espace parent -> local).
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hipw := Vector3(side * HIP_HALF, HIP_STAND, 0.0) + fl_off
		var ankle := to_local_p(_stand_foot(i, delta)) + Vector3.UP * 0.06
		var knee := _two_bone(hipw, ankle, THIGH, SHIN, Vector3.FORWARD)
		_bone(_thigh_m[i], hipw, knee, THICK_THIGH)
		_bone(_shin_m[i], knee, ankle, THICK_SHIN)
		_foot_box(i, ankle, Vector3.FORWARD)

	# Bras : ballants, puis en croix. Les doigts s'ouvrent avec.
	#
	# Ballants, les poignets tombent LE LONG des cuisses, coudes a peine casses
	# — et pas du meme angle a gauche et a droite : deux bras parfaitement
	# paralleles font une rambarde, pas un corps. Le coude pointe en arriere,
	# comme sur n'importe qui.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sh := chest + Vector3(side * SHOULDER_HALF, 0.0, 0.0)
		var slack := 0.955 if i == 0 else 0.936
		var hang := sh + Vector3(side * 0.045, -(UPPER_ARM + FOREARM) * slack, 0.05) \
			+ Vector3(sin(_sway * 0.9 + float(i) * 2.6) * 0.018, 0.0,
				cos(_sway * 0.7 + float(i) * 1.7) * 0.014)
		# En croix, les coudes TOMBENT — un epouvantail, pas une marionnette
		# tiree vers le haut — et les mains pendent au bout, doigts vers le
		# sol.
		var wide := chest + Vector3(side * (UPPER_ARM + FOREARM) * 0.955, 0.02, -0.10)
		var wrist := hang.lerp(wide, _spread)
		var pole := Vector3(side * 0.4, 0.0, 0.9).lerp(
			Vector3(side * 0.55, -0.4, -0.45), _spread)
		var elbow := _two_bone(sh, wrist, UPPER_ARM, FOREARM, pole)
		_bone(_upper_m[i], sh, elbow, THICK_ARM)
		_bone(_fore_m[i], elbow, wrist, THICK_FORE)
		var fdir := ((wrist - elbow).normalized()).lerp(
			Vector3(side * 0.25, -1.0, -0.1).normalized(), _spread * 0.7).normalized()
		var palm_n := Vector3(0, 0, -1) if _spread > 0.5 else Vector3(side, 0, 0)
		_place_hand(i, wrist, fdir, palm_n)
		_hand_curl[i] = lerpf(_hand_curl[i], 0.25 - _spread * 0.15,
			clampf(delta * 6.0, 0.0, 1.0))
	_jaw_open = move_toward(_jaw_open, _spread * 0.7, delta * 3.0)


## Pied au sol qui SUIT par petits pas quand le corps se decale — un pied
## plante ne glisse pas, meme ici.
func _stand_foot(i: int, delta: float) -> Vector3:
	var side := -1.0 if i == 0 else 1.0
	var ideal := to_global_p(Vector3(side * 0.15, 0.0, 0.0))
	ideal.y = 0.0
	if _foot_t[i] >= 0.0:
		_foot_t[i] += delta / 0.15
		if _foot_t[i] >= 1.0:
			_foot_t[i] = -1.0
			_feet[i] = ideal
		else:
			var e := smoothstep(0.0, 1.0, _foot_t[i])
			var p: Vector3 = _foot_from[i].lerp(ideal, e)
			p.y = 0.08 * sin(PI * _foot_t[i])
			return p
	elif _feet[i].distance_to(ideal) > 0.22 and _foot_t[1 - i] < 0.0:
		_foot_from[i] = _feet[i]
		_foot_t[i] = 0.0
	return _feet[i]


## Accroche a la caisse. La posture sort des prises : normale au flanc, il
## PEND, chest contre la tole ; normale au ciel (capot), il RAMPE accroupi.
func _pose_climb(delta: float) -> void:
	var g := _grip(_body_grip, door_side)
	var n: Vector3 = g["n"]
	var f: Vector3 = g["f"]
	var deck := clampf(n.y, 0.0, 1.0)
	var nh := Vector3(n.x, 0.0, n.z)
	nh = nh.normalized() if nh.length() > 0.05 else Vector3(0, 0, -1)

	# Ou le bassin veut etre. La pendaison est reglee pour que le CRANE tombe
	# au milieu de la glace (0,97-1,235) : bassin 60 cm sous la ceinture, buste
	# et cou remontent de 76 — mesure au banc, crane a 1,14 m. A 48 cm il
	# depassait du toit de la vitre et le joueur qui tournait la tete voyait un
	# torse sans visage.
	var hang_p: Vector3 = (g["p"] as Vector3) + nh * 0.26 + Vector3.DOWN * 0.66
	var deck_p: Vector3 = (g["p"] as Vector3) - f * 0.58 + n * 0.335
	var want := hang_p.lerp(deck_p, deck)
	if state == ATTACKING or state == CAUGHT:
		# Dans l'ouverture : le corps vient au chambranle, BAS — le crane
		# arrive SOUS l'oeil du conducteur et le regarde d'en dessous. Plus
		# haut (0,80 essaye au banc), le visage restait au-dessus du champ et
		# le joueur ne voyait qu'un avant-bras. Par la vitre, seuls les bras
		# passent : le corps reste a hauteur du jour.
		# 0,72 : le crane finit un peu AU-DESSUS de la ligne des bras tendus —
		# a 0,64 il se cachait derriere son propre avant-bras, a 0,80 il
		# passait au-dessus du champ.
		var door_p := Vector3(door_side * 0.88,
			0.88 if _through_window else 0.72,
			DRIVER_EYE.z - 0.05 + (0.0 if _through_window else 0.05))
		want = want.lerp(door_p, clampf(_reach_t / (reach_time * 0.6), 0.0, 1.0)) \
			if state == ATTACKING else door_p
	# L'encaissement : la balle pousse le CORPS, pas les mains — le bassin
	# part sous les prises, et le ressort du dessous le ramene.
	var punch := _flinch * _flinch
	if punch > 0.001:
		want += (transform.basis * _flinch_dir) * (flinch_shift * 1.4 * punch)
	var k := 1.0 - exp(-7.0 * delta) if delta > 0.0 else 1.0
	_pelvis = _pelvis.lerp(want, k)

	# L'orientation, du meme tissu.
	# Le corps pend A PLOMB (l'ecart au panneau vient du bassin, pas d'une
	# inclinaison) : c'est ce qui garde le crane au niveau de la glace au lieu
	# de l'envoyer au-dessus du toit.
	var fwd_hang := (-nh + Vector3.UP * 0.22).normalized()
	var up_hang := (Vector3.UP + nh * 0.12).normalized()
	var fwd_deck := (f - n * 0.5).normalized()
	var up_deck := n
	var fwd := fwd_hang.lerp(fwd_deck, deck).normalized()
	var upv := up_hang.lerp(up_deck, deck).normalized()
	var x := upv.cross(-fwd).normalized()
	var b := Basis(x, upv, x.cross(upv)).orthonormalized()
	_basis = Basis(Quaternion(_basis).slerp(Quaternion(b), k))
	transform = Transform3D(_basis, _pelvis)

	var hip := Vector3.ZERO
	# Voute partout : pendu il s'arrondit sur la glace (le crane descend au
	# milieu de la vitre), en attaque il S'ENGOUFFRE — 46 degres, la tete
	# passe sous le cadre de porte.
	var hunch := deg_to_rad(lerpf(30.0, 36.0, deck))
	if state == ATTACKING or state == CAUGHT:
		hunch = deg_to_rad(46.0)
	var torso := Basis(Vector3.RIGHT, -hunch)
	if punch > 0.001:
		torso = _flinch_swing(punch) * torso
	var up: Vector3 = torso * Vector3.UP
	var chest := hip + up * TORSO

	_bone(_hips_m, Vector3(-HIP_HALF, 0, 0), Vector3(HIP_HALF, 0, 0),
		THICK_THIGH * 1.35)
	_bone(_chest_m, hip, chest, 0.105)
	_bone(_shoulder_m, chest + Vector3(-SHOULDER_HALF, 0.0, 0.0),
		chest + Vector3(SHOULDER_HALF, 0.0, 0.0), 0.052)
	_head_pose(chest, up, delta)

	# Les mains. Deux cas particuliers par-dessus l'escalade : la main de
	# poignee pendant AT_DOOR, et les deux mains vers la gorge en attaque.
	for i in 2:
		var wrist_p: Vector3
		var curl_goal := 0.85 if _hand_t[i] < 0.0 else 0.25
		var fdir: Vector3
		var palm_n: Vector3
		if state == AT_DOOR and i == 1:
			var hp := HANDLE_P
			if door_side > 0.0:
				hp = _mx(hp)
			var tug := 0.05 * maxf(0.0, sin(TAU * _yank_t / yank_period))
			wrist_p = hp + Vector3(door_side * 0.03, 0.10 + tug, 0.0)
			fdir = Vector3(-door_side, -0.7, 0.0).normalized()
			palm_n = Vector3(door_side, 0.2, 0.0).normalized()
			curl_goal = 0.9
		elif state in [ATTACKING, CAUGHT]:
			# La gorge : sous l'oeil, un peu en avant et cote portiere — a
			# quinze centimetres de la camera, pas a cinq : plus pres, les
			# poignets passent sous le plan proche (4 cm) et l'etreinte est
			# invisible. La, les doigts se referment DANS l'image.
			var neck := DRIVER_EYE + Vector3(door_side * 0.06, -0.08, -0.09)
			if door_side > 0.0:
				neck.x = -DRIVER_EYE.x + door_side * 0.06
			neck.x += door_side * -0.02 * (1.0 if i == 0 else -1.0)
			var t := clampf(_reach_t / reach_time, 0.0, 1.0)
			var from_g := _hand_goal(i)
			wrist_p = from_g.lerp(neck, smoothstep(0.0, 1.0, t)) \
				if state == ATTACKING else neck
			fdir = Vector3(-door_side, -0.1, 0.0).normalized()
			palm_n = Vector3(0, -1, 0.2).normalized()
			curl_goal = 0.4 + 0.55 * t
		else:
			wrist_p = _hand_pos(i)
			var gg := _grip(_hands[i]["name"], door_side)
			fdir = (gg["f"] as Vector3).normalized()
			palm_n = -(gg["n"] as Vector3)
		var wrist := to_local_p(wrist_p)
		var side := -1.0 if i == 0 else 1.0
		var sh := chest + Vector3(side * SHOULDER_HALF, 0.0, 0.0)
		var pole := Vector3(side * 1.2, 0.55, -0.25)
		var elbow := _two_bone(sh, wrist, UPPER_ARM, FOREARM, pole)
		_bone(_upper_m[i], sh, elbow, THICK_ARM)
		_bone(_fore_m[i], elbow, wrist, THICK_FORE)
		_place_hand(i, wrist, transform.basis.inverse() * fdir,
			transform.basis.inverse() * palm_n)
		_hand_curl[i] = lerpf(_hand_curl[i], curl_goal, clampf(delta * 9.0, 0.0, 1.0))

	# Les pieds : un appui, garde tant qu'il porte — la meme dette que les
	# mains. Sur le capot ils se posent DESSUS, derriere le corps ; en
	# pendaison ils se calent contre le BAS DE CAISSE (x 0,72, y 0,42), jamais
	# sur la chaussee : elle defile dessous, un pied pose dessus serait un
	# patin a 90 km/h.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hipw := Vector3(side * HIP_HALF, 0.0, 0.0)
		var gp: Vector3 = g["p"]
		var deck_ideal: Vector3 = gp - f * 0.80 + _basis.x * (side * 0.17)
		deck_ideal.y = gp.y + 0.02
		var hang_ideal: Vector3 = _pelvis - nh * 0.34 + _basis.x * (side * 0.17)
		hang_ideal.y = clampf(_pelvis.y - 0.42, 0.28, 0.55)
		var ideal_par := hang_ideal.lerp(deck_ideal, deck)
		var foot_par := _climb_foot(i, ideal_par, delta)
		var ankle := to_local_p(foot_par)
		var knee := _two_bone(hipw, ankle, THIGH, SHIN,
			Vector3(side * 0.9, 0.1, -0.5))
		_bone(_thigh_m[i], hipw, knee, THICK_THIGH)
		_bone(_shin_m[i], knee, ankle, THICK_SHIN)
		_foot_box(i, ankle, Vector3(side * 0.4, -0.3, -0.85).normalized())


func _climb_foot(i: int, ideal: Vector3, delta: float) -> Vector3:
	if _foot_t[i] >= 0.0:
		_foot_t[i] += delta / 0.16
		if _foot_t[i] >= 1.0:
			_foot_t[i] = -1.0
			_feet[i] = ideal
		else:
			return _foot_from[i].lerp(ideal, smoothstep(0.0, 1.0, _foot_t[i]))
	elif _feet[i].distance_to(ideal) > 0.30 and _foot_t[1 - i] < 0.0:
		_foot_from[i] = _feet[i]
		_foot_t[i] = 0.0
	return _feet[i]


## Abattu : plus personne ne tient les membres. Les cibles d'IK s'effondrent
## vers le corps et tout part en culbute avec le noeud.
func _pose_limp(delta: float) -> void:
	var hip := Vector3.ZERO
	var torso := Basis(Vector3.RIGHT, -deg_to_rad(8.0))
	var up: Vector3 = torso * Vector3.UP
	var chest := hip + up * (TORSO * 0.98)
	_bone(_hips_m, Vector3(-HIP_HALF, 0, 0), Vector3(HIP_HALF, 0, 0),
		THICK_THIGH * 1.35)
	_bone(_chest_m, hip, chest, 0.105)
	_bone(_shoulder_m, chest + Vector3(-SHOULDER_HALF, 0.0, 0.0),
		chest + Vector3(SHOULDER_HALF, 0.0, 0.0), 0.052)
	_head_pose(chest, up, delta)

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var sh := chest + Vector3(side * SHOULDER_HALF, 0.0, 0.0)
		# Un bras rejete au-dessus de la tete, l'autre en travers : la symetrie
		# est le premier signe de vie qu'un cadavre perd — un corps tombe
		# n'importe comment, pas en etoile.
		var wrist: Vector3
		if i == 0:
			wrist = sh + Vector3(side * 0.52, 0.74, 0.10)
		else:
			wrist = sh + Vector3(side * 1.02, -0.30, -0.16)
		var elbow := _two_bone(sh, wrist, UPPER_ARM, FOREARM,
			Vector3(side, 0.3, 0.4))
		_bone(_upper_m[i], sh, elbow, THICK_ARM)
		_bone(_fore_m[i], elbow, wrist, THICK_FORE)
		_place_hand(i, wrist, (wrist - elbow).normalized(), Vector3(0, 0, 1))
		_hand_curl[i] = lerpf(_hand_curl[i], 0.55, clampf(delta * 4.0, 0.0, 1.0))

		# Les jambes s'allongent DANS L'AXE DU CORPS (-Y local : vers les
		# pieds), pas devant lui : couche sur le dos, "devant lui" serait le
		# ciel et le cadavre leverait les jambes.
		var hipw := Vector3(side * HIP_HALF, 0.0, 0.0)
		var ankle := hipw + Vector3(side * 0.24, -(THIGH + SHIN) * 0.82, -0.18)
		var knee := _two_bone(hipw, ankle, THIGH, SHIN, Vector3(side * 0.4, -0.3, -1.0))
		_bone(_thigh_m[i], hipw, knee, THICK_THIGH)
		_bone(_shin_m[i], knee, ankle, THICK_SHIN)
		_foot_box(i, ankle, Vector3(side * 0.3, -0.6, -0.6).normalized())
	_jaw_open = move_toward(_jaw_open, 0.35, delta * 2.0)


## La tete. Elle REGARDE LE CONDUCTEUR, tout le temps, d'ou qu'il soit : c'est
## le meme fil que la tete du geant — le corps fait sa vie, le regard jamais.
func _head_pose(chest: Vector3, up: Vector3, delta: float) -> void:
	var neck_top := chest + up * NECK
	_bone(_neck_m, chest, neck_top, 0.045)
	_head.position = neck_top + up * (SKULL_H * 0.42)
	if state in [FALLING, CORPSE] or target == null:
		_head.rotation = _head.rotation.lerp(Vector3(0.2, 0.3, 0.1),
			clampf(delta * 3.0, 0.0, 1.0))
	else:
		var eye_par: Vector3
		if get_parent() == target:
			eye_par = DRIVER_EYE
		else:
			eye_par = target.to_global(DRIVER_EYE)
		var aim := to_local_p(eye_par) - _head.position
		var yaw := clampf(atan2(-aim.x, -aim.z), deg_to_rad(-80.0), deg_to_rad(80.0))
		var pitch := clampf(atan2(aim.y, Vector2(aim.x, aim.z).length()),
			deg_to_rad(-45.0), deg_to_rad(45.0))
		_head.rotation = Vector3(pitch, yaw, 0.0)
		if _flinch > 0.001:
			# La tete claque — en arriere sur un tir en tete, un sursaut
			# sinon — puis le regard revient : il n'a jamais cesse de viser.
			var punch := _flinch * _flinch
			var amp := 0.85 if _flinch_head else 0.22
			_head.rotation.x += punch * amp
			_head.rotation.y += clampf(-_flinch_dir.x, -1.0, 1.0) \
				* punch * amp * 0.7
	_jaw.rotation.x = deg_to_rad(34.0) * _jaw_open


## La rotation d'encaissement : le haut du buste part dans la direction ou la
## balle pousse. Moitie moins sur un tir en tete — la, c'est la tete qui
## claque, pas le buste.
func _flinch_swing(k: float) -> Basis:
	var ax := Vector3.UP.cross(_flinch_dir)
	if ax.length() < 0.05:
		return Basis()
	return Basis(ax.normalized(),
		deg_to_rad(flinch_deg) * k * (0.5 if _flinch_head else 1.0))


## Paume et doigts. Le poignet est un point, la main est une BASE : -Z les
## doigts, -Y la paume. On la construit depuis la direction des doigts et la
## normale de paume, redressees l'une contre l'autre.
func _place_hand(i: int, wrist: Vector3, fingers: Vector3, palm_away: Vector3) -> void:
	var z := -fingers.normalized()
	var y := palm_away - z * palm_away.dot(z)
	y = y.normalized() if y.length() > 0.001 else Vector3.UP
	var x := y.cross(z)
	_hand_n[i].transform = Transform3D(Basis(x, y, z).orthonormalized(), wrist)
	var pair: Array = _fingers[i]
	for fi in pair.size():
		var seg: Array = pair[fi]
		# Chaque doigt a SA fermeture : a la meme, la main est une fourchette.
		var curl: float = _hand_curl[i] * (0.86 + 0.075 * float(fi))
		(seg[0] as Node3D).rotation.x = -0.25 - curl * 1.15
		(seg[1] as Node3D).rotation.x = -0.15 - curl * 1.35


func _foot_box(i: int, ankle: Vector3, dir: Vector3) -> void:
	var d := dir.normalized()
	var y := Vector3.UP - d * Vector3.UP.dot(d)
	y = y.normalized() if y.length() > 0.01 else Vector3.BACK
	var x := y.cross(-d)
	_foot_m[i].transform = Transform3D(
		Basis(x, y, -d).orthonormalized().scaled(Vector3(1, 1, 1)),
		ankle + d * (FOOT_LEN * 0.30) - y * 0.03)


## Squelette de l'image en espace monde, pour les balles et les bancs.
##
## Convention de _bone : la matrice envoie (0, -0,5, 0) sur le DEBUT de l'os
## (l'attache : epaule, hanche) et (0, +0,5, 0) sur sa FIN (coude, poignet).
## La premiere version lisait a l'envers — le "poignet" etait le coude, la
## capsule de l'avant-bras un point, et le banc mesurait des doigts a 65 cm du
## sol sur un corps dont ils le touchent.
func _record_joints() -> void:
	var g := global_transform
	_j["pelvis"] = g * Vector3.ZERO
	_j["chest"] = g * (_chest_m.transform * Vector3(0, 0.5, 0))
	_j["neck"] = g * (_neck_m.transform * Vector3(0, 0.5, 0))
	_j["skull"] = g * _head.position
	for i in 2:
		var s := "_l" if i == 0 else "_r"
		_j["shoulder" + s] = g * (_upper_m[i].transform * Vector3(0, -0.5, 0))
		_j["elbow" + s] = g * (_upper_m[i].transform * Vector3(0, 0.5, 0))
		_j["wrist" + s] = g * (_fore_m[i].transform * Vector3(0, 0.5, 0))
		_j["hip" + s] = g * (_thigh_m[i].transform * Vector3(0, -0.5, 0))
		_j["knee" + s] = g * (_thigh_m[i].transform * Vector3(0, 0.5, 0))
		_j["ankle" + s] = g * (_shin_m[i].transform * Vector3(0, 0.5, 0))


# --------------------------------------------------------------------------
# Geometrie (les memes briques que le geant)
# --------------------------------------------------------------------------

func to_local_p(parent_point: Vector3) -> Vector3:
	return transform.affine_inverse() * parent_point


func to_global_p(local_point: Vector3) -> Vector3:
	return transform * local_point


func _two_bone(root: Vector3, tip: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var axis := tip - root
	var d := axis.length()
	if d < 0.001:
		return root + Vector3(0.0, -l1, 0.0)
	d = clampf(d, absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := axis / axis.length()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var side := pole - dir * pole.dot(dir)
	if side.length_squared() < 0.0001:
		side = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	return root + dir * a + side.normalized() * h


func _bone(mi: MeshInstance3D, a: Vector3, b: Vector3, thick: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var y := d / l
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	mi.transform = Transform3D(Basis(x * thick, y * l, x.cross(y) * thick), (a + b) * 0.5)


## Distance le long du rayon jusqu'a une capsule, -1 si rate.
func _ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	# On echantillonne le segment : huit spheres se recouvrant largement. Pas
	# elegant, exact a un demi-rayon pres — et un canon de revolver n'en
	# demande pas plus a un torse de 30 cm.
	var best := -1.0
	for k in 8:
		var q := a.lerp(b, float(k) / 7.0)
		var t := _ray_sphere(o, d, q, r)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var m := o - c
	var bq := m.dot(d)
	var cq := m.dot(m) - r * r
	if cq > 0.0 and bq > 0.0:
		return -1.0
	var disc := bq * bq - cq
	if disc < 0.0:
		return -1.0
	return maxf(-bq - sqrt(disc), 0.0)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

## PALE, et c'est un choix d'eclairage avant d'etre un choix de peau. Tout le
## decor absorbe (troncs 0,075, geant 0,070) : lui renvoie 0,34 — cinq fois le
## reste de la nuit. Dans les phares, a 40 m, c'est une silhouette blanche
## debout au milieu de la voie ; hors des phares il n'existe pas. Un ennemi
## qui vit DANS la lumiere du joueur, la ou le geant vit dans son brouillard.
func _build_body() -> void:
	_mat_skin = Retro.mat(Color(0.34, 0.325, 0.29), 0.62)
	# Un souffle d'auto-lueur — 0,04, tres loin du seuil de glow (0,95). Hors
	# des phares rien d'autre ne l'eclaire : sans elle, pendu a la portiere il
	# etait un trou noir dans une nuit noire, et le joueur qui tournait la tete
	# ne trouvait RIEN a viser. Avec, c'est un cadavre au clair de lune.
	_mat_skin.set_shader_parameter("emission", Color(0.040, 0.038, 0.034))
	_mat_dark = Retro.mat(Color(0.012, 0.010, 0.010), 0.9)
	_mat_wound = Retro.mat(WOUND, 0.7)

	var limb := CylinderMesh.new()
	limb.top_radius = 0.42
	limb.bottom_radius = 0.5
	limb.height = 1.0
	limb.radial_segments = 8
	limb.rings = 1

	_hips_m = _mesh(limb)
	_chest_m = _mesh(limb)
	_shoulder_m = _mesh(limb)
	_neck_m = _mesh(limb)
	for i in 2:
		_upper_m.append(_mesh(limb))
		_fore_m.append(_mesh(limb))
		_thigh_m.append(_mesh(limb))
		_shin_m.append(_mesh(limb))

	var joint := SphereMesh.new()
	joint.radius = 0.5
	joint.height = 1.0
	joint.radial_segments = 8
	joint.rings = 4

	var foot := BoxMesh.new()
	foot.size = Vector3(0.10, 0.05, FOOT_LEN)
	for i in 2:
		var fm := MeshInstance3D.new()
		fm.mesh = foot
		fm.material_override = _mat_skin
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fm)
		_foot_m.append(fm)

	# La tete : un crane trop haut, deux orbites creuses, une machoire qui
	# S'OUVRE — c'est elle qui crie, pas un haut-parleur.
	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)

	var skull := SphereMesh.new()
	skull.radius = SKULL_W * 0.5
	skull.height = SKULL_H
	skull.radial_segments = 14
	skull.rings = 8
	_skull_m = MeshInstance3D.new()
	_skull_m.mesh = skull
	_skull_m.material_override = _mat_skin
	_skull_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(_skull_m)

	var eye := SphereMesh.new()
	eye.radius = 0.026
	eye.height = 0.052
	eye.radial_segments = 6
	eye.rings = 3
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = eye
		e.material_override = _mat_dark
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.position = Vector3(side * 0.042, SKULL_H * 0.10, -SKULL_W * 0.42)
		_head.add_child(e)

	_jaw = Node3D.new()
	_jaw.name = "Jaw"
	_jaw.position = Vector3(0.0, -SKULL_H * 0.16, -0.01)
	_head.add_child(_jaw)
	var jaw_m := MeshInstance3D.new()
	var jaw_box := BoxMesh.new()
	jaw_box.size = Vector3(SKULL_W * 0.72, SKULL_H * 0.30, SKULL_W * 0.78)
	jaw_m.mesh = jaw_box
	jaw_m.material_override = _mat_skin
	jaw_m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jaw_m.position = Vector3(0.0, -SKULL_H * 0.13, -SKULL_W * 0.06)
	_jaw.add_child(jaw_m)
	var mouth := MeshInstance3D.new()
	var mouth_box := BoxMesh.new()
	mouth_box.size = Vector3(SKULL_W * 0.56, SKULL_H * 0.16, SKULL_W * 0.60)
	mouth.mesh = mouth_box
	mouth.material_override = _mat_dark
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mouth.position = Vector3(0.0, -SKULL_H * 0.04, -SKULL_W * 0.10)
	_jaw.add_child(mouth)

	# Les mains. Quatre doigts et un pouce par paume, DEUX phalanges par doigt
	# qui se replient ensemble : c'est la fermeture de ces doigts sur la
	# ceinture de caisse, vue par la vitre, qui fait tout le personnage.
	for i in 2:
		var hn := Node3D.new()
		hn.name = "Hand%s" % ("L" if i == 0 else "R")
		add_child(hn)
		_hand_n.append(hn)

		var palm := MeshInstance3D.new()
		var palm_box := BoxMesh.new()
		palm_box.size = Vector3(0.085, 0.028, PALM)
		palm.mesh = palm_box
		palm.material_override = _mat_skin
		palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		palm.position = Vector3(0.0, 0.0, -PALM * 0.5)
		hn.add_child(palm)

		var fingers: Array = []
		for fi in 5:
			var thumb := fi == 4
			var fx := (float(fi) - 1.5) * 0.024
			var root := Node3D.new()
			root.position = Vector3(0.045 if i == 0 else -0.045, 0.0, -PALM * 0.35) \
				if thumb else Vector3(fx, 0.0, -PALM)
			if thumb:
				root.rotation.y = (0.9 if i == 0 else -0.9)
			hn.add_child(root)

			var l1 := FINGER_1 * (0.7 if thumb else 1.0)
			var l2 := FINGER_2 * (0.7 if thumb else 1.0)
			var prox := _finger_seg(root, l1)
			var mid := Node3D.new()
			mid.position = Vector3(0.0, 0.0, -l1)
			prox.add_child(mid)
			var dist := _finger_seg(mid, l2)
			fingers.append([prox, mid])
		_fingers.append(fingers)


## Une phalange : un pivot qui plie en X, une barre le long de -Z.
func _finger_seg(parent: Node3D, len_: float) -> Node3D:
	var piv := Node3D.new()
	parent.add_child(piv)
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(THICK_FINGER, THICK_FINGER, len_)
	m.mesh = box
	m.material_override = _mat_skin
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(0.0, 0.0, -len_ * 0.5)
	piv.add_child(m)
	return piv


func _mesh(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat_skin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_audio() -> void:
	var bus := "Cabine" if AudioServer.get_bus_index("Cabine") >= 0 else "Master"
	_scream_snd = _sound("res://assets/audio/strangler/scream.wav", bus, scream_volume_db)
	_hurt_snd = _sound("res://assets/audio/strangler/hurt.wav", bus, scream_volume_db - 3.0)
	_breath_snd = _sound("res://assets/audio/strangler/breath.wav", bus, breath_volume_db)
	_breath_snd.unit_size = 3.0
	_rattle_snd = _sound("res://assets/audio/strangler/rattle.wav", bus, thump_volume_db)
	_creak_snd = _sound("res://assets/audio/strangler/creak.wav", bus, thump_volume_db + 2.0)
	for i in 2:
		var t := _sound("res://assets/audio/strangler/thump.wav", bus, thump_volume_db)
		_hand_n[i].add_child(t)
		_thump_snd.append(t)
	_head.add_child(_scream_snd)
	_head.add_child(_hurt_snd)
	_head.add_child(_breath_snd)
	add_child(_rattle_snd)
	add_child(_creak_snd)


func _sound(path: String, bus: String, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.volume_db = db
	p.unit_size = sound_unit
	p.max_distance = 0.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if ResourceLoader.exists(path):
		p.stream = load(path)
	else:
		push_warning("son de l'etrangleur : %s manque, lancer tools/make_strangler_sounds.py" % path)
	return p


func _scream() -> void:
	if _scream_snd != null and _scream_snd.stream != null:
		_scream_snd.pitch_scale = 1.0 + _rng.randf_range(-0.07, 0.07)
		_scream_snd.play()


# --------------------------------------------------------------------------
# Ce que les bancs d'essai regardent
# --------------------------------------------------------------------------

func hand_point(i: int) -> Vector3:
	return _hand_n[i].global_position


func skull_point() -> Vector3:
	return _j.get("skull", global_position)


func hands_flying() -> int:
	var n := 0
	for i in 2:
		if _hand_t[i] >= 0.0:
			n += 1
	return n


func debug_line() -> String:
	var names := ["eteint", "sur la voie", "escalade", "poignee", "la porte cede",
		"les bras entrent", "il tient le conducteur", "il tombe", "en tas"]
	return "%-22s  vie %.0f/%.0f  prise %-10s  cote %s  mains posees %d  secousses %d%s" % [
		names[state], health, health_max,
		last_grip if last_grip != "" else "-",
		"G" if door_side < 0.0 else "D", plants, yanks,
		"  (" + caught_mode + ")" if caught_mode != "" else ""]
