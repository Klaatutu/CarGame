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
const WHEEL_MAX_ANGLE := 110.0     # degres de rotation a plein braquage

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
const HEADREST_GRIP := Vector3(0.23, 1.14, 0.47)
## De combien le buste accompagne le bras qui va chercher un objet. Sans ca
## l'epaule reste en arriere et le bras bute en butee de longueur : le paquet
## sur le siege passager est a 63 cm de l'epaule, pour 62 cm de bras.
const REACH_LEAN := 0.13
const DOOR_GRIP := Vector3(-0.87, 0.98, -0.26)
const LEAN_OUT := Vector3(-0.30, -0.02, -0.02)

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
	update_pose(0.0, 0.0, 0.0, false, 1, false, false, 0.0, 0.0, 0.0)


## Appele chaque frame par car.gd.
## `hold_lever` : vrai tant que le frein est tenu a la main.
## `look_back` : 0 = regard vers l'avant, 1 = retourne vers l'arriere a droite.
## `look_out`  : 0 = assis normalement, 1 = penche, tete sortie par la vitre.
func update_pose(steer: float, throttle: float, braking: float,
		clutch: bool, gear: int, handbrake: bool, hold_lever: bool,
		look_back: float, look_out: float, delta: float) -> void:
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
	wheel_spin.rotation.y = steer * deg_to_rad(WHEEL_MAX_ANGLE)
	_update_lever(gear, k)

	_breath += delta * 1.15
	var breath := sin(_breath) * 0.005

	# --- buste -----------------------------------------------------------
	# Une tete ne tourne pas a 130 degres toute seule : le buste pivote pour
	# absorber l'exces, a droite quand on se retourne, a gauche quand on se
	# penche a la vitre. Les deux ne peuvent pas arriver ensemble.
	var twist := Basis(Vector3.UP,
		deg_to_rad(TWIST_MAX) * (look_out * 0.75 - look_back))
	var lean := LEAN_OUT * look_out
	# Tendre le bras : le buste accompagne, mais SEULEMENT quand on va vraiment
	# chercher loin. Pencher pour un objet tenu devant la poitrine ferait bouger
	# le buste en permanence, sans raison.
	if item_blend > 0.001:
		var away := item_point - (SHOULDER_L if item_left else SHOULDER_R)
		away.y = 0.0
		var stretch := clampf((away.length() - 0.42) / 0.25, 0.0, 1.0)
		if stretch > 0.0 and away.length_squared() > 0.000001:
			lean += away.normalized() * (REACH_LEAN * item_blend * stretch)
	_torso.position = SPINE + lean + Vector3(0.0, breath, 0.0)
	_torso.basis = twist

	# --- mains -----------------------------------------------------------
	# Calcul analytique : on ne depend pas de l'ordre de mise a jour des
	# transforms par le moteur.
	var wheel_tf := wheel_tilt.transform * wheel_spin.transform
	# Mains a 10 h 10 : la jante est tournee autour de l'axe du volant (Y local)
	# et la main avec, pour que ses doigts restent perpendiculaires a la jante.
	var grip_l := Basis(Vector3.UP, -deg_to_rad(GRIP_ANGLE))
	var grip_r := Basis(Vector3.UP, deg_to_rad(GRIP_ANGLE))
	var tf_l := wheel_tf * Transform3D(grip_l, grip_l * Vector3(-WHEEL_RADIUS, 0.0, 0.0))
	var tf_r := wheel_tf * Transform3D(grip_r, grip_r * Vector3(WHEEL_RADIUS, 0.0, 0.0))

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
	_apply_fingers(_skel_l, _poses_l, _bones_l, r_l, c_l)
	_apply_fingers(_skel_r, _poses_r, _bones_r, r_r, c_r)

	var offset := lean + Vector3(0.0, breath, 0.0)
	var sh_l := _twisted(SHOULDER_L, twist) + offset
	var sh_r := _twisted(SHOULDER_R, twist) + offset
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
	_set_bone(_thigh_l, HIP_L, knee_l)
	_set_bone(_shin_l, knee_l, ankle_l)
	_set_bone(_thigh_r, HIP_R, knee_r)
	_set_bone(_shin_r, knee_r, ankle_r)


# --------------------------------------------------------------------------
# Commandes
# --------------------------------------------------------------------------

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


## Main posee a plat sur le haut de l'appui-tete passager, paume vers le bas.
func _headrest_grip() -> Transform3D:
	return _aligned_grip(HEADREST_GRIP, _elbow_r)


## Main gauche agrippee au haut de la portiere quand on sort la tete.
func _door_grip() -> Transform3D:
	return Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(160.0), deg_to_rad(12.0), 0.0)),
		DOOR_GRIP)


## Fait pivoter un point autour de l'axe vertical du buste.
func _twisted(p: Vector3, twist: Basis) -> Vector3:
	var pivot := Vector3(SPINE.x, p.y, SPINE.z)
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
