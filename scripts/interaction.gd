extends Node3D
##
## Prendre et reposer les objets de l'habitacle.
##
## VISEE SANS PHYSIQUE. Elle est resolue analytiquement en ESPACE VOITURE, ou la
## camera, les objets et les surfaces sont immobiles les uns par rapport aux
## autres, que la caisse roule a 5 ou a 170 km/h.
##
## C'etait le bug "je ne peux pas saisir le paquet en roulant" : un rayon
## physique contre un corps accroche a la caisse tombait a cote, la position du
## corps n'arrivant au serveur qu'au pas suivant. A 24 m/s, 40 cm d'ecart.
##
## Les objets, eux, SONT des corps physiques : ils tombent, glissent et roulent.
## Tenus en main ils passent en `freeze`, et on leur rend la vitesse de la
## voiture quand on les lache.
##
## Poser se fait en deux temps : on MAINTIENT le clic pour viser (un fantome
## translucide montre ou l'objet atterrira) et on relache pour le lacher.
##
## Les objets UTILISABLES (plafonnier) se visent de la meme facon, mais la main
## ne les ramene pas : arrivee dessus, elle les actionne (`use()`) et revient.
##
## UNE ARME SE LEVE. Un objet qui expose `fire()` gagne un etat de plus : clic
## droit maintenu, la main monte dans l'axe du regard et l'objet pointe ou on
## regarde (RAISED). Le clic gauche n'y pose plus rien, il tire — les deux etats
## s'excluent, il n'y a donc aucune ambiguite a lui donner deux sens. Relacher le
## clic droit rabaisse l'arme et le clic gauche redevient "poser".
##
## ON PEUT AUSSI JETER. Clic molette, et ce qu'on tient part dans l'axe du
## regard. Poser vise une surface et prend son temps ; lancer ne vise rien et
## est immediat — c'est le meme objet, mais ce n'est pas le meme geste.
##
## CE QU'ON TOURNE se tient d'abord (`wind()`, GRIPPING) : clic gauche maintenu
## sur une manivelle de vitre, puis la MOLETTE cran par cran, camera libre. Le
## cran sert aussi de levier de vitesses, et c'est la main posee sur la poignee
## qui tranche — voir _unhandled_input.
##

const Bench := preload("res://scripts/bench.gd")


enum State { IDLE, REACHING, HELD, AIMING, PLACING, ADJUSTING, GRIPPING, RAISED,
	DRINKING, PHONE, TAPPING }

## Ou l'objet est tenu, FIXE dans l'espace de la voiture : devant la poitrine,
## un peu a droite, sous la ligne des yeux.
##
## Surtout pas en local camera : la main suivrait le regard, le bras se tordrait
## a chaque mouvement de tete et partirait en butee des qu'on regarde de cote.
## Une main ne suit pas les yeux.
## Recule avec le conducteur : l'oeil est passe de 0.10 a 0.28, un objet laisse
## a -0.22 se serait retrouve a un demi-metre du visage, hors de portee du geste.
const HOLD_POINT := Vector3(-0.21, 0.93, 0.0)

## Ou le POING monte quand on leve une arme, par rapport a l'oeil : dans l'axe du
## regard, a droite et SOUS la ligne de visee. L'arme est tenue par la crosse et
## mesure 26 cm : sa bouche arrive donc a 70 cm de l'oeil, et le canon monte en
## diagonale vers le centre de l'ecran sans jamais couvrir la route.
##
## Le bras tendu, pas replie. A 0,42 m le poing etait a 30 cm de l'epaule, coude
## casse et main plein cadre : elle mangeait l'ecran et cachait ce qu'elle
## tenait. Ne pas depasser 0,52 non plus — bras droit devant, l'epaule est a
## 0,58 m de portee et l'avant-bras se mettrait a s'etirer.
const AIM_REACH := 0.50
const AIM_SIDE := 0.070
const AIM_DROP := 0.100

## Boire : ou la canette vient (sous l'oeil, un peu en avant — on boit, on ne
## vise pas), combien de temps dure le geste (la longueur du glouglou), et de
## combien le poignet bascule au sommet.
const DRINK_FWD := 0.10
const DRINK_DROP := 0.085
const DRINK_TIME := 1.5
const DRINK_TILT := 45.0

## Consulter le telephone : distance de LECTURE, pas de visee — plus pres que
## l'arme (0,50), ecran cabre vers l'oeil.
##
## ET L'ECRAN SUR L'AXE DU REGARD, pas a cote. C'est le reticule qui touche :
## il doit tomber DANS l'ecran, sinon il n'y a rien a viser. L'appareil se
## posait 3 cm a droite et 8,5 cm sous la ligne des yeux — le reticule passait
## a un millimetre du bord gauche de la vitre, et screen_uv() rendait null a
## chaque image. On visait un ecran qu'on ne pouvait pas atteindre.
const PHONE_REACH := 0.34
const PHONE_TILT := 12.0
## Verrou entre deux pages tournees a la molette, en secondes. Sous Windows un
## seul cran produit plusieurs evenements — c'est deja pourquoi la boite a son
## `shift_cooldown` (car.gd). La manivelle et la cle s'en moquent, elles
## tournent d'autant plus ; une page, elle, se saute.
const PHONE_WHEEL_LOCK := 0.25
## Ou la ligne d'aide se pose sous le reticule, en pixels du HUD. Le telephone
## consulte descend la sienne sous l'appareil (voir _update_hud).
const HINT_DROP := 26.0
const HINT_DROP_PHONE := 200.0
## Ce que fait le recul a l'ARME, pas a la visee : elle se cabre et recule dans
## la main. Rendre la ligne de mire au joueur est son affaire, pas celle du code.
const RECOIL_RISE := 11.0
const RECOIL_BACK := 0.035

## De combien l'objet est avance avant de partir. Lache exactement dans le
## poing il naitrait a moitie dans le buste du conducteur, et la boite du siege
## le renverrait aussitot en arriere : un lancer qui recule.
const THROW_CLEARANCE := 0.10
## Ce que la main fait apres le lacher : elle poursuit le geste avant de
## retomber. Sans ca le bras se retracte a l'instant meme ou l'objet part, et
## c'est l'objet qui a l'air de s'echapper tout seul.
const THROW_FOLLOW := 0.16

## Portee du bras. Le paquet sur le siege passager est a 0,9 m de l'oeil.
@export var reach := 1.25
## Duree du geste, aller chercher comme reposer.
@export var reach_time := 0.45
## Position de l'objet dans le poing (origine de la main = axe de prise).
@export var in_hand := Vector3(0.0, 0.0, 0.0)
## Vitesse de depart d'un objet lance, en m/s. Un jet a la main dans un
## habitacle : assez pour traverser la cabine et cogner le pare-brise, pas assez
## pour qu'on perde l'objet de vue. La DIRECTION, elle, est exactement celle du
## regard — c'est le viseur qui vise, pas une parabole corrigee.
@export var throw_speed := 4.5

var cam: Camera3D
var driver
var cabin
var carrier                        # la voiture, pour sa vitesse
var grabbables: Array[Node3D] = []
## Objets a actionner sur place : `use()`, `use_hint()`, et comme les autres
## `grab_radius()` et `set_highlight()`.
var usables: Array[Node3D] = []
## Objets qu'on ORIENTE en maintenant le clic : `swivel(Vector2)`,
## `adjust_hint()`. Les retroviseurs, pour l'instant.
var adjustables: Array[Node3D] = []
## Vrai tant qu'un reglage est en cours. car.gd y lit qu'il doit bloquer le
## regard et lui renvoyer la souris.
var adjusting := false
var held: Node3D
var target: Node3D

var _state := State.IDLE
var _blend := 0.0
var _drink_t := 0.0                # progression du geste de boire, en secondes
var _tap_uv := Vector2.ZERO        # ou le doigt va taper (TAPPING), en uv ecran
## L'oeil et le regard FIGES a la levee du telephone (espace voiture) : c'est
## d'eux que la pose de lecture est calculee, et d'eux seuls. Voir State.PHONE.
var _phone_eye := Vector3.ZERO
var _phone_dir := Vector3.FORWARD
var _phone_wheel := 0.0            # verrou de molette du telephone, en secondes
var _drop_is_dock := false         # la depose en cours vise le berceau
var _goal := Vector3.ZERO          # ou la main doit aller, espace voiture
var _drop := Transform3D()         # pose finale de l'objet, espace voiture
var _surface_hit := false
var _surface_point := Vector3.ZERO
var _ghost: Node3D
var _hint: Label
var _dot: ColorRect


func _ready() -> void:
	_build_hud()


func _process(delta: float) -> void:
	_phone_wheel = maxf(_phone_wheel - delta, 0.0)
	if cam == null or driver == null or cabin == null:
		_update_hud()
		return

	# La camera, ramenee dans le repere de la voiture.
	var eye := global_transform.affine_inverse() * cam.global_transform
	var origin := eye.origin
	var dir := -eye.basis.z
	var k := clampf(delta * 7.0, 0.0, 1.0)

	match _state:
		State.IDLE:
			_surface_hit = false
			_set_target(_aimed_object(origin, dir))
			_blend = move_toward(_blend, 0.0, delta / reach_time)
			# L'ecran au berceau se survole du regard : les boutons
			# s'allument sous le reticule avant meme qu'on tape.
			if target != null and target.has_method("screen_uv") \
					and target.get("docked") == true:
				var uvh = target.call("screen_uv", cam.global_position,
					-cam.global_transform.basis.z)
				if uvh != null:
					target.call("hover", uvh)
		State.REACHING:
			# La main va au-devant de l'objet, qui n'a pas encore bouge.
			_goal = to_local(target.global_position) if target != null else _goal
			_blend = move_toward(_blend, 1.0, delta / reach_time)
			if _blend >= 1.0:
				if target != null and target.has_method("use"):
					_use()
				else:
					_pick_up()
		State.HELD:
			_blend = 1.0
			_goal = _goal.lerp(HOLD_POINT, k)
			_surface_hit = false
		State.RAISED:
			# L'arme est levee : le poing monte dans l'axe du regard et l'arme
			# pointe ou on regarde. La CAMERA RESTE LIBRE — c'est elle qui vise.
			#
			# Le relachement du clic droit est aussi lu ici : sans ca, lacher le
			# bouton pendant que la souris est libre (Echap) laisserait l'arme
			# levee pour de bon.
			if not Input.is_action_pressed("aim_weapon"):
				_state = State.HELD
			_blend = 1.0
			_goal = _goal.lerp(_aim_point(origin, dir), k)
			_surface_hit = false
		State.DRINKING:
			# La canette vient A LA BOUCHE — sous l'oeil, pas dans l'axe du
			# regard : on boit, on ne vise pas, et la camera reste libre (les
			# yeux sur la route, c'est tout l'interet). Meme filet qu'en
			# RAISED : le relachement est relu ici.
			if not Input.is_action_pressed("aim_weapon"):
				if held != null and held.has_method("stop_sip"):
					held.call("stop_sip")
				_state = State.HELD
			_blend = 1.0
			_drink_t += delta
			_goal = _goal.lerp(_drink_point(origin, dir), k)
			_surface_hit = false
			if _drink_t >= DRINK_TIME and held != null and held.has_method("drain"):
				# Bue jusqu'au bout : l'effet part a la jauge par la voiture
				# (elle seule sait ou vit le sommeil), la canette s'ecrase.
				held.call("drain")
				if carrier != null and carrier.has_method("on_drink"):
					carrier.call("on_drink", held.get("drink"))
				_state = State.HELD
		State.PHONE:
			# Le telephone consulte : il monte a distance de LECTURE, ecran
			# face a l'oeil, et la camera reste libre — LE RETICULE EST LE
			# DOIGT. Le survol est pousse au viewport chaque image, le clic
			# gauche tape (_unhandled_input). Meme filet de relachement
			# qu'en RAISED.
			#
			# LA POSE EST FIGEE (_phone_eye, _phone_dir, pris a la levee), et
			# c'est ce qui rend l'ecran visable. Une arme levee SUIT le regard,
			# c'est elle qu'on pointe ; un telephone qui suivrait le regard
			# emporterait l'ecran avec le reticule, et le meme point resterait
			# sous le doigt pour toujours — on ne pouvait viser aucune icone.
			# Ici il tient dans l'espace de la voiture, comme une main qui ne
			# suit pas les yeux : le regard PROMENE le reticule sur la vitre.
			if not Input.is_action_pressed("aim_weapon"):
				if held != null and held.has_method("set_viewing"):
					held.call("set_viewing", false)
				_state = State.HELD
			_blend = 1.0
			_goal = _goal.lerp(_phone_point(), k)
			_surface_hit = false
			if held != null:
				var uv = held.call("screen_uv", cam.global_position,
					-cam.global_transform.basis.z)
				if uv != null:
					held.call("hover", uv)
		State.TAPPING:
			# Le doigt part toucher l'ecran du telephone AU BERCEAU : le
			# geste du plafonnier, parametre par le point d'ecran vise.
			if target == null:
				_state = State.IDLE
			else:
				_goal = to_local(target.call("screen_point", _tap_uv))
				_blend = move_toward(_blend, 1.0, delta / (reach_time * 0.6))
				if _blend >= 1.0:
					target.call("tap", _tap_uv)
					_state = State.IDLE
		State.AIMING:
			# On garde l'objet en main et on montre ou il ira.
			_blend = 1.0
			_goal = _goal.lerp(HOLD_POINT, k)
			_aim_surface(origin, dir)
			_show_ghost()
		State.PLACING:
			_blend = 1.0
			_goal = _goal.lerp(_drop.origin, k)
			if _goal.distance_to(_drop.origin) < 0.015:
				_put_down()
		State.ADJUSTING:
			# La main va se poser sur le retroviseur ou le pare-soleil et le suit
			# pendant le reglage (le pare-soleil bouge sous la main). Sans bras
			# dans le modele, plus rien ne traverse l'ecran : main gauche pour ce
			# qui est du cote conducteur, droite pour le reste (choisi au clic).
			_surface_hit = false
			if target != null:
				_goal = _hand_point_of(target)
			_blend = move_toward(_blend, 1.0, delta / reach_time)
		State.GRIPPING:
			# La main tient la poignee et la suit pendant qu'elle tourne. La
			# CAMERA RESTE LIBRE, contrairement au reglage a la souris : une
			# manivelle, on la tourne sans la regarder, les yeux sur la route.
			_surface_hit = false
			if target != null:
				_goal = _hand_point_of(target)
				# La manivelle rattrape les crans deja donnes. Les crans, eux,
				# ne sont pris qu'une fois la main arrivee sur la poignee —
				# c'est _unhandled_input qui le verifie.
				target.call("wind", delta)
			_blend = move_toward(_blend, 1.0, delta / reach_time)

	driver.item_point = _goal
	driver.item_blend = _blend

	# L'objet tenu suit la main, pas la visee. Transforms locales : l'objet et la
	# main sont tous deux exprimes dans le repere de la voiture. Son axe de prise
	# (grip_axis) se couche sur celui du poing (-Z local de la main, cote pouce),
	# et il tourne autour pour presenter sa face avant (front_axis) au joueur.
	#
	# Une arme LEVEE inverse le rapport : c'est le regard qui la pose, et elle
	# qui impose son orientation au poing.
	if held != null:
		var tf: Transform3D
		if _state == State.RAISED:
			tf = _aimed_transform(dir)
		elif _state == State.PHONE:
			tf = _phone_transform()
		else:
			tf = _held_transform(origin)
		if _state == State.DRINKING:
			# La bascule du poignet : le fond se leve, le bord vient aux
			# levres. L'angle suit le geste — il ne claque pas, il se verse.
			var flat := Vector3(dir.x, 0.0, dir.z)
			flat = flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
			var tip := deg_to_rad(DRINK_TILT) \
				* smoothstep(0.15, 1.0, _drink_t / DRINK_TIME)
			tf.basis = Basis(flat.cross(Vector3.UP).normalized(), tip) * tf.basis
		held.transform = tf
		# Un objet qui sait comment on l'empoigne (hand_local) oriente la main
		# lui-meme. Sans ca elle s'oriente d'apres le coude, ce qui suffit a une
		# canette mais laisse une crosse de travers dans le poing.
		if held.has_method("hand_local"):
			driver.item_aim = _blend
			driver.item_aim_basis = tf.basis * held.call("hand_local")
		else:
			driver.item_aim = 0.0
	else:
		driver.item_aim = 0.0

	_update_hud()


## Un cran de souris pendant un reglage. car.gd nous l'envoie au lieu de tourner
## la tete du conducteur : on ne peut pas viser et orienter avec le meme geste.
## Transform de l'objet tenu (repere voiture). `eye` : position de l'oeil.
##
## Deux regles, selon que l'objet SUBIT la main ou la COMMANDE.
##
## Une canette la subit : son axe de prise se couche sur celui du poing, et le
## poing est oriente par le coude. La main mene, l'objet suit. C'est le cas
## ci-dessous.
##
## Une arme, elle, commande le poing (`hand_local`). Lui faire en plus LIRE
## l'orientation de ce poing fermerait la boucle : l'arme se poserait sur ce que
## dit la main, la main sur ce que dit l'arme, et l'ensemble se figerait la ou le
## transitoire l'a laisse — canon en l'air une fois, en bas ou de travers la
## suivante. Elle passe donc par _carried_transform(), qui la pose sur une
## reference EXTERIEURE.
func _held_transform(eye: Vector3) -> Transform3D:
	if held.has_method("hand_local"):
		return _carried_transform(eye)
	var hand: Transform3D = driver.hand_right().transform
	var a1: Vector3 = (held.call("grip_axis") if held.has_method("grip_axis") else Vector3.UP).normalized()
	var front: Vector3 = held.call("front_axis") if held.has_method("front_axis") else Vector3.BACK
	var a2 := (front - a1 * front.dot(a1)).normalized()
	var off: Vector3 = driver.held_offset()
	var pos: Vector3 = hand * (in_hand + off)
	var g := (hand.basis * Vector3(0.0, 0.0, -1.0)).normalized()      # axe de prise du poing, cote pouce
	var d: Vector3 = eye - pos
	d = d - g * d.dot(g)                                              # au mieux, en tournant autour du poing
	if d.length_squared() < 0.000001:
		d = hand.basis.y
	d = d.normalized()
	var target := Basis(g, d, g.cross(d))
	var local := Basis(a1, a2, a1.cross(a2))
	var pose := target * local.transposed()
	return Transform3D(pose, pos - pose * _grip_offset())


## Pose d'une arme simplement PORTEE, pas encore levee (repere voiture).
##
## Bouche vers le CIEL, et l'arme tourne autour de cet axe pour presenter son
## flanc au joueur. C'est la position d'attente : on ne roule pas en braquant sa
## cuisse, et c'est aussi la seule qui se lise d'un coup d'oeil.
##
## Rien ici ne depend de l'ORIENTATION de la main — seulement de sa position, et
## encore, pour le seul reglage du flanc. C'est ce qui rend la pose reproductible
## d'une prise a l'autre : deux references fixes (la verticale, l'oeil) au lieu
## d'un poing qui attendait lui-meme de savoir comment se tourner.
func _carried_transform(eye: Vector3) -> Transform3D:
	var hand: Transform3D = driver.hand_right().transform
	var pos: Vector3 = hand * (in_hand + driver.held_offset())

	var f := Vector3.UP
	var d := eye - pos
	d -= f * d.dot(f)                       # a l'horizontale : l'arme ne se couche pas
	if d.length_squared() < 0.000001:
		d = Vector3.BACK
	d = d.normalized()

	var a: Vector3 = (held.call("aim_axis") if held.has_method("aim_axis") else Vector3.UP).normalized()
	var front: Vector3 = held.call("front_axis") if held.has_method("front_axis") else Vector3.BACK
	front = front - a * front.dot(a)
	if front.length_squared() < 0.000001:
		front = a.cross(Vector3.RIGHT)
	front = front.normalized()

	var world := Basis(f, d, f.cross(d))
	var local := Basis(a, front, a.cross(front))
	var pose := world * local.transposed()
	return Transform3D(pose, pos - pose * _grip_offset())


## Pose de l'arme LEVEE (repere voiture). Sa bouche suit le regard, son dessus
## reste vers le ciel, et le recul la fait se cabrer autour de son axe droit.
## Le poing, lui, est deja parti au point de visee : l'arme s'y accroche par sa
## crosse (`hold_point`), pas par le milieu de son volume.
func _aimed_transform(dir: Vector3) -> Transform3D:
	var hand: Transform3D = driver.hand_right().transform
	var pos: Vector3 = hand * (in_hand + driver.held_offset())

	var f := dir.normalized()
	# Le dessus de l'arme, redresse : on ne roule pas le poignet quand on leve
	# les yeux, on garde la bande de visee a plat.
	var up := Vector3.UP - f * Vector3.UP.dot(f)
	if up.length_squared() < 0.000001:
		up = Vector3.BACK - f * Vector3.BACK.dot(f)
	up = up.normalized()
	var right := f.cross(up)

	var a: Vector3 = held.call("aim_axis") if held.has_method("aim_axis") else Vector3.FORWARD
	var u: Vector3 = held.call("up_axis") if held.has_method("up_axis") else Vector3.UP
	var world := Basis(f, up, right)
	var local := Basis(a, u, a.cross(u))
	var pose := world * local.transposed()

	var kick: float = held.call("recoil") if held.has_method("recoil") else 0.0
	if kick > 0.0:
		pose = Basis(right, deg_to_rad(RECOIL_RISE) * kick) * pose
		pos -= f * (RECOIL_BACK * kick)

	return Transform3D(pose, pos - pose * _grip_offset())


## Ou le poing monte quand on leve l'arme (repere voiture).
func _aim_point(origin: Vector3, dir: Vector3) -> Vector3:
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	return origin + dir * AIM_REACH + right * AIM_SIDE - up * AIM_DROP


## Ou la canette vient quand on boit : la bouche. En avant de l'oeil A PLAT —
## la composante verticale du regard est ecartee, sans quoi boire en
## regardant le retroviseur enfoncerait la canette dans le front.
func _drink_point(origin: Vector3, dir: Vector3) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
	return origin + flat * DRINK_FWD + Vector3.DOWN * DRINK_DROP


## Le repere du telephone consulte : l'ecran FACE a l'oeil (fige), cabre de
## quelques degres — le haut recule, on lit un ecran, on ne le vise pas.
##
## LA CONVENTION DU BOITIER, celle du berceau (cabin.phone_dock_pose) : +Y sort
## de la vitre, +Z va vers le BAS de l'appareil, +X a la droite du lecteur. Une
## base GAUCHE (determinant -1) la trahissait ici : elle retournait l'image, on
## la redressait au materiau de l'ecran, et cette retouche cassait tout le
## reste — la vitre du berceau se lisait la tete en bas, et le doigt tapait le
## miroir vertical de ce que le reticule visait. Une base propre, et il n'y a
## plus rien a rattraper nulle part.
func _phone_basis() -> Basis:
	var n := -_phone_dir                           # normale d'ecran, vers l'oeil
	var right := n.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = -right.normalized()                    # +X boitier = droite du lecteur
	var up := n.cross(right).normalized()
	var tilt := deg_to_rad(PHONE_TILT)
	var n2 := (n * cos(tilt) + up * sin(tilt)).normalized()
	return Basis(right, n2, right.cross(n2).normalized())


## Ou le BOITIER se pose quand on le consulte. Ce qu'on centre sur l'axe du
## regard, c'est l'ECRAN — c'est lui qu'on touche, et il n'est pas au centre du
## boitier : le boitier s'en deduit.
func _phone_body() -> Vector3:
	var b := _phone_basis()
	var off := Vector3.ZERO
	if held != null and held.has_method("screen_center_local"):
		off = held.call("screen_center_local")
	return _phone_eye + _phone_dir * PHONE_REACH - b * off


## Ou la MAIN va le tenir : la prise du boitier (son tiers bas, derriere la
## vitre), deduite de la pose de lecture.
func _phone_point() -> Vector3:
	return _phone_body() + _phone_basis() * _grip_offset()


## La pose du telephone consulte. La main mene — elle est encore en chemin
## pendant que l'appareil monte — et la prise du boitier tombe dans le poing,
## exactement comme pour un objet simplement tenu.
func _phone_transform() -> Transform3D:
	var b := _phone_basis()
	return Transform3D(b, _goal - b * _grip_offset())


## Point de l'objet tenu qui doit tomber dans le poing, dans SON repere. Son
## origine par defaut ; un revolver, lui, se tient par la crosse.
func _grip_offset() -> Vector3:
	if held != null and held.has_method("hold_point"):
		return held.call("hold_point")
	return Vector3.ZERO


## Point ou la main saisit l'objet (repere voiture) : son `hand_point()` s'il en
## a un (coin du pare-soleil, bord du retroviseur), sinon son origine.
func _hand_point_of(t: Node3D) -> Vector3:
	if t.has_method("hand_point"):
		return to_local(t.call("hand_point"))
	return to_local(t.global_position)


func adjust(rel: Vector2) -> void:
	# Rien ne bouge tant que la main n'est pas arrivee sur l'objet.
	if _state == State.ADJUSTING and target != null and _blend >= 1.0:
		target.call("swivel", rel)


## Prendre : un clic. Poser : on MAINTIENT pour viser, on relache pour lacher.
## Lever une arme : clic droit maintenu. Tirer : clic gauche, arme levee.
func _unhandled_input(event: InputEvent) -> void:
	# La souris doit etre a nous. Un banc y a droit SANS la capturer : ses
	# clics sont synthetiques, ils n'ont pas de curseur a prendre — et deux
	# cents lancements par chantier le prenaient a quelqu'un (bench.gd).
	if not Bench.mouse_ours():
		return

	# --- l'arme, et la canette --------------------------------------------
	# Le meme clic droit maintenu PORTE A USAGE ce qu'on a en main : une arme
	# se leve (fire), une canette pleine se boit (sip). Les deux s'excluent
	# par nature — un objet n'est jamais les deux.
	if event.is_action_pressed("aim_weapon"):
		# On ne leve que ce qui se tire, et seulement une fois en main.
		if _state == State.HELD and held != null and held.has_method("fire"):
			_state = State.RAISED
			get_viewport().set_input_as_handled()
		elif _state == State.HELD and held != null and held.has_method("sip") \
				and held.call("sip"):
			# sip() dit s'il reste quelque chose a boire — et lance le
			# glouglou avec le geste. Une ecrasee ne repond pas : le clic
			# droit redevient alors le "se pencher" de car.gd.
			_state = State.DRINKING
			_drink_t = 0.0
			get_viewport().set_input_as_handled()
		elif _state == State.HELD and held != null and cam != null \
				and held.has_method("screen_uv"):
			# Le telephone se CONSULTE : il monte a distance de lecture, et il
			# S'Y FIGE. L'oeil et le regard sont pris ICI, une fois pour toute
			# la consultation : c'est ce qui laisse le reticule se promener sur
			# l'ecran au lieu de l'emporter avec lui.
			var eye_now := global_transform.affine_inverse() * cam.global_transform
			_phone_eye = eye_now.origin
			_phone_dir = -eye_now.basis.z
			_state = State.PHONE
			if held.has_method("set_viewing"):
				held.call("set_viewing", true)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released("aim_weapon"):
		if _state == State.RAISED:
			_state = State.HELD
			get_viewport().set_input_as_handled()
		elif _state == State.DRINKING:
			# Interrompue avant la fin : rien de bu, rien de gagne.
			if held != null and held.has_method("stop_sip"):
				held.call("stop_sip")
			_state = State.HELD
			get_viewport().set_input_as_handled()
		elif _state == State.PHONE:
			if held != null and held.has_method("set_viewing"):
				held.call("set_viewing", false)
			_state = State.HELD
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reload"):
		if held != null and held.has_method("reload"):
			held.call("reload")
			get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return

	# --- la manivelle ------------------------------------------------------
	# Poignee en main, la molette tourne la manivelle : vers le bas la vitre
	# descend, vers le haut elle remonte. Le sens est celui du regard, pas celui
	# de la rosace — la manivelle de droite tourne en miroir de celle de gauche,
	# et il n'y a qu'un seul geste a apprendre.
	#
	# Le meme cran PASSE LES RAPPORTS (car.gd). Les deux cohabitent comme le clic
	# molette et le lancer : on ne le consomme que la main POSEE sur la poignee,
	# et interaction.gd voit l'evenement avant la voiture — il est son enfant
	# dans l'arbre. Main ailleurs, le cran passe et descend jusqu'au levier.
	if event.button_index == MOUSE_BUTTON_WHEEL_UP \
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# `_blend >= 1.0` : la main doit etre arrivee. Sans ca, les crans donnes
		# pendant que le bras part encore chercher la poignee feraient tourner
		# une manivelle que personne ne tient encore.
		if event.pressed and _state == State.GRIPPING and _blend >= 1.0 \
				and target != null and target.has_method("crank"):
			target.call("crank",
				1.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
			get_viewport().set_input_as_handled()
		elif event.pressed and _state == State.PHONE and held != null \
				and held.has_method("scroll"):
			# Telephone consulte, la molette TOURNE LES PAGES (phone_apps.gd)
			# — on ne passe pas les rapports en lisant ses avis, et c'est dit
			# par le hint. Vers le bas on va vers la droite de la barre
			# d'onglets : le meme sens que le cran de la manivelle. Le cran
			# est verrouille (PHONE_WHEEL_LOCK), mais l'evenement est mange
			# dans tous les cas : on ne passe pas un rapport avec le rebond
			# d'une molette qui tournait les pages.
			if _phone_wheel <= 0.0:
				_phone_wheel = PHONE_WHEEL_LOCK
				held.call("scroll",
					1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			get_viewport().set_input_as_handled()
		return

	# --- le lancer ---------------------------------------------------------
	# Clic molette. Le bouton sert AUSSI a passer au point mort (car.gd), et les
	# deux ne se marchent pas dessus : on ne lance que ce qu'on a en main, et
	# interaction.gd voit l'evenement avant la voiture — il est son enfant dans
	# l'arbre, et l'entree non geree remonte des feuilles vers la racine. Main
	# vide, le clic passe donc et descend jusqu'au levier.
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and cam != null and held != null and held.has_method("throw") \
				and _state in [State.HELD, State.AIMING, State.RAISED]:
			var eye := global_transform.affine_inverse() * cam.global_transform
			_throw(-eye.basis.z)
			get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		match _state:
			State.RAISED:
				# Arme levee, le clic gauche ne pose plus : il tire.
				if held != null and held.has_method("fire"):
					held.call("fire")
			State.PHONE:
				# Telephone consulte, le clic gauche TAPE ou tombe le regard.
				if held != null:
					var uvp = held.call("screen_uv", cam.global_position,
						-cam.global_transform.basis.z)
					if uvp != null:
						held.call("tap", uvp)
			State.IDLE:
				if target == null:
					return
				# L'ecran au berceau est un bouton, son corps une poignee :
				# le regard sur la vitre TAPE, le regard sur le bord PREND.
				if target.has_method("screen_uv") and target.get("docked") == true:
					var uvt = target.call("screen_uv", cam.global_position,
						-cam.global_transform.basis.z)
					if uvt != null:
						_tap_uv = uvt
						driver.item_left = false
						driver.item_radius = 0.0
						_blend = 0.0
						_state = State.TAPPING
						get_viewport().set_input_as_handled()
						return
				_goal = to_local(target.global_position)
				# Ce qu'on manoeuvre SUR PLACE se prend de la main la plus proche :
				# pare-soleil conducteur, retro gauche, manivelle gauche a la main
				# gauche ; le reste (retro interieur, cote passager, objets) a
				# droite.
				var in_place: bool = target.has_method("swivel") or target.has_method("wind")
				driver.item_left = in_place and _goal.x <= driver.SEAT_X + 0.05
				driver.item_radius = 0.0          # main ouverte jusqu'a la prise (ou a plat sur un reglage)
				_goal = _hand_point_of(target)
				if target.has_method("wind"):
					# Une manivelle se TIENT : la main s'y referme et y reste, et
					# la camera n'est pas bloquee.
					driver.item_radius = 0.014    # les doigts se referment sur la poignee
					_state = State.GRIPPING
				elif target.has_method("swivel"):
					_state = State.ADJUSTING
					adjusting = true
				else:
					_state = State.REACHING
			State.HELD:
				_state = State.AIMING
			_:
				return                   # geste en cours, on ne l'interrompt pas
	elif _state == State.ADJUSTING:
		# Relachement : le reglage est garde tel quel, il n'y a rien a valider.
		_state = State.IDLE
		adjusting = false
	elif _state == State.GRIPPING:
		# On tient la poignee tant qu'on tient le clic : la lacher, c'est lacher
		# le bouton. La vitre reste evidemment ou elle en est — y compris si des
		# crans restaient a rattraper, que la manivelle oublie en meme temps.
		if target != null and target.has_method("release_grip"):
			target.call("release_grip")
		_state = State.IDLE
		driver.item_radius = 0.0
	else:
		if _state != State.AIMING:
			return                       # c'est le relachement du clic de prise
		if _surface_hit:
			_drop = _rest_on(_surface_point)
			# Le berceau AIMANTE le telephone : vise a moins de dix
			# centimetres, il s'y pose DANS le support, pas a cote.
			_drop_is_dock = false
			if held != null and held.has_method("set_docked") \
					and cabin.has_method("phone_dock_pose"):
				var dp: Transform3D = cabin.phone_dock_pose()
				if _surface_point.distance_to(dp.origin) < 0.10:
					_drop = dp
					_drop_is_dock = true
			_state = State.PLACING
		else:
			_state = State.HELD          # rien sous le viseur : on garde en main
		_clear_ghost()

	get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Visee, en espace voiture
# --------------------------------------------------------------------------

## Objet attrapable sous le viseur, le plus proche. Test rayon/sphere : viser
## une boite de 5 cm a un metre au pixel pres serait injouable.
func _aimed_object(origin: Vector3, dir: Vector3) -> Node3D:
	var best: Node3D = null
	var best_t := reach
	for list in [grabbables, usables, adjustables]:
		for obj in list:
			if obj == held or not is_instance_valid(obj):
				continue
			var m := to_local(obj.global_position) - origin
			var t := m.dot(dir)
			if t < 0.0 or t > best_t:
				continue
			var r: float = obj.grab_radius() if obj.has_method("grab_radius") else 0.07
			if m.length_squared() - t * t > r * r:
				continue
			best = obj
			best_t = t
	return best


## Surface de depose sous le viseur : la premiere tole que le rayon rencontre,
## en ESPACE VOITURE.
##
## TOUJOURS AUCUN RAYON PHYSIQUE — c'est ce qui avait corrige "je ne peux pas
## saisir le paquet en roulant" : un corps statique accroche a une caisse qui
## roule ne transmet sa position au serveur qu'au pas suivant, et a 24 m/s le
## rayon tombe 40 cm a cote. Ici la camera et la tole sont immobiles l'une par
## rapport a l'autre, que la caisse roule a 5 ou a 170 km/h.
##
## CE QUI CHANGE EST CE QU'ON PEUT VISER. Avant, dix boites horizontales saisies
## a la main dans cabin.gd : les deux assises, la banquette, la console, le
## plancher, et la planche de bord en quatre morceaux dont AUCUN ne couvrait le
## fond de planche cote conducteur. Le maillage, lui, y court d'un montant a
## l'autre a 93-95 cm — la tole etait la, la surface de depose non, et c'etait
## "je ne peux pas poser les objets sur tout le tableau de bord".
##
## Maintenant on marche dans la grille relevee sur le .glb : tout ce qui se voit
## se vise. Le fond de planche cote conducteur, le capot des compteurs, le
## tunnel, les bas de caisse, le dessus des contre-portes — sans que personne
## ait eu a en taper les cotes, et sans qu'aucun ne puisse se desynchroniser du
## modele.
##
## ON NE POSE QUE SUR CE QUI EST A PEU PRES PLAT. Un pare-brise ou une
## contre-porte sont de la tole comme le reste et le rayon les trouve ; y poser
## un paquet n'aurait aucun sens. Le seuil est la normale rendue par la grille.
func _aim_surface(origin: Vector3, dir: Vector3) -> void:
	_surface_hit = false
	if cabin.shape == null:
		return
	var hit: Array = cabin.shape.raycast(origin, dir, reach)
	if not hit[0]:
		return
	var n: Vector3 = hit[2]
	if n.y < 0.5:
		return                            # une paroi : on n'y pose rien
	_surface_point = hit[1]
	_surface_hit = true


## Pose l'objet a plat sur la surface, tourne vers le conducteur. Espace voiture.
func _rest_on(point: Vector3) -> Transform3D:
	var eye := global_transform.affine_inverse() * cam.global_transform
	var fwd := -eye.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()

	var lift := 0.02
	if held != null and held.has_method("rest_height"):
		lift = held.call("rest_height")
	return Transform3D(Basis(right, Vector3.UP, -fwd), point + Vector3.UP * lift)


func _pick_up() -> void:
	held = target
	# Rayon de prise : demi-diagonale de la section perpendiculaire a l'axe de prise
	# (un peu reduite : les doigts epousent les angles), bornee aux poses du modele.
	if held.has_method("grip_radius"):
		# Un objet qui a une vraie poignee la connait mieux que ses demi-cotes :
		# ceux du revolver donneraient la longueur du canon.
		driver.item_radius = held.call("grip_radius")
	else:
		var half: Vector3 = held.get("half") if held.get("half") != null else Vector3(0.02, 0.02, 0.02)
		var ga: Vector3 = (held.call("grip_axis") if held.has_method("grip_axis") else Vector3.UP).abs()
		var ext := [half.x, half.y, half.z]
		ext.remove_at(ga.max_axis_index())
		driver.item_radius = maxf(sqrt(ext[0] * ext[0] + ext[1] * ext[1]) * 0.7, 0.008)
	_set_target(null)
	if held.has_method("hold"):
		held.call("hold")                # la physique se tait, la main commande
	_state = State.HELD


func _put_down() -> void:
	held.transform = _drop
	driver.item_radius = 0.0
	if held.has_method("release"):
		held.call("release")
	# Pose au berceau : le support reprend le verrou que la main vient de
	# rendre, et l'ecran s'y rallume.
	if _drop_is_dock and held.has_method("set_docked"):
		held.call("set_docked", true)
	_drop_is_dock = false
	held = null
	_state = State.IDLE


## Jeter ce qu'on tient dans l'axe du regard. `dir` est en espace voiture,
## normalise.
##
## Rien a viser, rien a attendre : l'objet part a l'instant du clic. C'est ce
## qui distingue le lancer de la depose, qui elle cherche une surface et fait
## faire tout un geste au bras. On jette une canette sans regarder ou elle
## tombe.
##
## Il part de la MAIN, la ou il etait : sa transform est deja celle du poing,
## _process l'y a mise a l'image precedente. On l'avance seulement d'une paume
## pour qu'il sorte du buste.
func _throw(dir: Vector3) -> void:
	var obj := held
	held = null
	driver.item_radius = 0.0          # la main s'ouvre
	_clear_ghost()
	_state = State.IDLE
	obj.position += dir * THROW_CLEARANCE
	obj.call("throw", dir * throw_speed)
	# La main accompagne le lancer, puis IDLE la ramene (`_blend` vers zero).
	_goal += dir * THROW_FOLLOW


## Actionner sur place : la main est arrivee, l'objet bascule, et elle revient
## d'elle-meme (IDLE ramene `_blend` a zero). L'objet reste sous le viseur, donc
## il est aussitot re-cible : un second clic le rebascule.
func _use() -> void:
	target.call("use")
	_set_target(null)
	_state = State.IDLE


# --------------------------------------------------------------------------
# Fantome de depose
# --------------------------------------------------------------------------

func _show_ghost() -> void:
	if _ghost == null:
		_build_ghost()
	if _ghost == null:
		return
	_ghost.visible = _surface_hit
	if _surface_hit:
		_ghost.transform = _rest_on(_surface_point)


## Copie des meshes de l'objet, en translucide. On ne duplique PAS le noeud :
## son script rejouerait _ready() et reconstruirait sa geometrie en double.
func _build_ghost() -> void:
	if held == null:
		return
	_ghost = Node3D.new()
	_ghost.name = "Ghost"
	add_child(_ghost)
	_ghost_meshes(held, Transform3D())


## Copie a plat des maillages de l'objet, transforms cumulees. Un seul niveau
## suffisait tant que les objets etaient d'un bloc ; le revolver, lui, range sa
## geometrie sous ses pivots, et un fantome non recursif serait vide.
func _ghost_meshes(n: Node, tf: Transform3D) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var local := tf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var g := MeshInstance3D.new()
			g.mesh = (c as MeshInstance3D).mesh
			g.transform = local
			g.material_override = _ghost_material()
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghost.add_child(g)
		_ghost_meshes(c, local)


func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


## Non eclaire : dans une voiture de nuit, un fantome ombre ne se verrait pas.
func _ghost_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.72, 0.40, 0.38)
	return m


## Vrai quand le clic droit, ou les deux mains, sont deja pris : arme levee (le
## bouton lui appartient, c'est elle qui l'a consomme), retroviseur en cours de
## reglage, manivelle tenue. car.gd y lit qu'il ne doit pas se pencher — un
## buste qui part alors que la main est posee sur une manivelle etirerait
## l'avant-bras pour la garder.
func lean_blocked() -> bool:
	return _state == State.RAISED or _state == State.ADJUSTING \
		or _state == State.GRIPPING or _state == State.DRINKING \
		or _state == State.PHONE


## Lache ce qui est en main SANS le reposer : l'objet reste ou il est, la main
## revient d'elle-meme. Sert au banc d'essai, qui doit pouvoir remettre une
## canette exactement a sa place entre deux mesures — la reposer au viseur la
## laisserait a quelques centimetres de la, et les deux mesures ne se
## compareraient plus.
func let_go() -> void:
	if held != null and held.has_method("release"):
		held.call("release")
	held = null
	driver.item_radius = 0.0
	_clear_ghost()
	_state = State.IDLE


## Vrai si une surface de depose est sous le viseur. Sert au banc d'essai.
func has_surface() -> bool:
	return _surface_hit


## Vrai si le fantome est affiche. Sert au banc d'essai.
func ghost_visible() -> bool:
	return _ghost != null and _ghost.visible


## Nombre de maillages copies dans le fantome. Sert au banc d'essai : un fantome
## present mais VIDE se voit exactement comme pas de fantome du tout.
func ghost_parts() -> int:
	return _ghost.get_child_count() if _ghost != null else -1


func _set_target(next: Node3D) -> void:
	if next == target:
		return
	if target != null and target.has_method("set_highlight"):
		target.call("set_highlight", false)
	target = next
	if target != null and target.has_method("set_highlight"):
		target.call("set_highlight", true)


# --------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InteractHUD"
	layer.layer = 1
	add_child(layer)

	# Petit point central, visible seulement quand il y a quelque chose a viser :
	# un reticule permanent n'a rien a faire dans un jeu d'ambiance.
	_dot = ColorRect.new()
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.offset_left = -2.0
	_dot.offset_top = -2.0
	_dot.offset_right = 2.0
	_dot.offset_bottom = 2.0
	_dot.color = Color(1.0, 0.85, 0.65, 0.55)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.visible = false
	layer.add_child(_dot)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	# Large : la ligne de l'objet en main enumere trois gestes (poser, lever,
	# lancer) et se ferait couper a 520 px.
	_hint.offset_left = -340.0
	_hint.offset_top = HINT_DROP
	_hint.offset_right = 340.0
	_hint.offset_bottom = HINT_DROP + 26.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82, 0.75))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)


func _update_hud() -> void:
	# La ligne d'aide se tient sous le reticule — sauf telephone consulte :
	# l'appareil occupe le milieu de l'image depuis qu'on peut le viser, et la
	# ligne se lisait par-dessus l'ecran qu'elle explique. Elle passe dessous.
	var drop := HINT_DROP_PHONE if _state == State.PHONE else HINT_DROP
	if not is_equal_approx(_hint.offset_top, drop):
		_hint.offset_top = drop
		_hint.offset_bottom = drop + 26.0

	match _state:
		State.IDLE:
			_dot.visible = target != null
			if target == null:
				_hint.text = ""
			elif target.has_method("use_hint"):
				_hint.text = target.call("use_hint")
			elif target.has_method("grip_hint"):
				_hint.text = target.call("grip_hint")
			elif target.has_method("adjust_hint"):
				_hint.text = target.call("adjust_hint")
			elif target.has_method("screen_uv") and target.get("docked") == true:
				_hint.text = "Clic : toucher l'ecran    viser le bord : prendre"
			else:
				_hint.text = "Clic gauche : prendre"
		State.HELD:
			_dot.visible = true
			if held != null and held.has_method("fire"):
				_hint.text = "Maintiens clic gauche : poser    clic droit : lever    molette : lancer"
			elif held != null and held.has_method("sip") and held.get("full"):
				_hint.text = "Maintiens clic gauche : poser    clic droit : boire    molette : lancer"
			elif held != null and held.has_method("screen_uv"):
				_hint.text = "Maintiens clic gauche : poser    clic droit : consulter"
			else:
				_hint.text = "Maintiens clic gauche : poser    molette : lancer"
		State.DRINKING:
			_dot.visible = false
			_hint.text = ""
		State.PHONE:
			# Le point du HUD est le doigt : il reste allume sur l'ecran.
			_dot.visible = true
			_hint.text = "Clic : toucher    molette : changer de page"
		State.TAPPING:
			_dot.visible = true
			_hint.text = ""
		State.RAISED:
			_dot.visible = true
			if held != null and held.has_method("ammo_hint"):
				_hint.text = held.call("ammo_hint")
			else:
				_hint.text = "Clic gauche : tirer"
		State.AIMING:
			_dot.visible = true
			_hint.text = "Relache pour poser" if _surface_hit else "Vise une surface"
		State.GRIPPING:
			# Le viseur reste allume : on tient toujours la poignee, meme si le
			# regard est parti ailleurs.
			_dot.visible = true
			_hint.text = target.call("held_hint") if target != null else ""
		State.ADJUSTING:
			_dot.visible = true
			_hint.text = "Souris : orienter    relache : terminer"
		_:
			_dot.visible = false
			_hint.text = ""
