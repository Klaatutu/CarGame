extends Node3D
##
## Le geant. Premier ennemi du jeu.
##
## Il attend accroupi dans les sapins, se releve quand la voiture arrive, se met
## a courir derriere elle et essaie de l'ecraser du pied.
##
## TOUT SORT DE LA TAILLE DU PIED
## ------------------------------
## La seule mesure choisie est celle-la : son pied fait la voiture, 3,97 m sur
## 1,68 m. Chez l'humain le pied vaut 15,2 % de la stature — un pied de 3,97 m
## appartient donc a quelqu'un de 26 m. Cuisse, tibia, buste, bras, tete : ce
## sont les fractions anthropometriques habituelles multipliees par cette
## stature. On ne regle rien d'autre que le pied, et le reste suit. C'est ce qui
## evite le monstre en pate a modeler, celui dont les bras sont trop courts et
## dont personne ne sait dire pourquoi il sonne faux.
##
## SA VITESSE N'EST PAS CHOISIE NON PLUS
## -------------------------------------
## Deux animaux de meme forme et de tailles differentes bougent au meme nombre
## de Froude : les vitesses vont comme la racine de l'echelle, les cadences
## comme son inverse, les foulees comme l'echelle. Un sprinteur fait 10 m/s a
## 4,4 pas par seconde ; a l'echelle 14,9 (26,1 m pour 1,75 m) cela donne
## 38 m/s — 137 km/h — a 1,14 pas par seconde, soit 33 m par pas. Ces trois
## nombres sont COHERENTS entre eux (33 x 1,14 = 38), et c'est de la que vient
## l'impression de masse. Un geant qui court vite en piaffant a la cadence d'un
## homme ressemble immanquablement a une maquette filmee en accelere.
##
## Accessoirement cela repond a la question de jeu sans qu'on ait a l'arbitrer :
## la Civic plafonne a 50 m/s en 5e (GEAR_TOP), 43 en 4e, 34 en 3e. On ne le
## seme donc qu'en 5e, et lentement — 12 m/s d'ecart, il faut quinze secondes
## pleines pour prendre 200 m. En 4e on tient l'ecart sans le creuser. En 3e il
## gagne. Rater un rapport, caler, ou trop freiner en courbe, et il revient.
##
## LES PIEDS NE GLISSENT PAS
## -------------------------
## C'est le seul endroit ou une animation procedurale se fait prendre tout de
## suite. Un pied pose est POSE : on retient le point du monde ou il a touche et
## il y reste jusqu'au decollage, quoi que fasse le corps au-dessus. Le bassin,
## lui, ne monte jamais plus haut que ce que la jambe d'appui autorise — une
## jambe ne s'allonge pas. Ce sont ces deux contraintes, et rien d'autre, qui
## produisent le balancement vertical de la course : on n'ecrit aucune
## sinusoide de rebond, elle sort toute seule de la geometrie.
##
## En fin d'appui le pied PIVOTE SUR SES ORTEILS. Sans ce detail rien ne
## fonctionne : au decollage, la cheville se retrouve a 9,6 m derriere la
## hanche, pour une jambe de 12,8 m et un bassin a 11,5 m — le compte ne tombe
## pas. Le talon qui se leve rapproche la cheville de la hanche de deux metres
## et remonte de deux autres : c'est exactement ce que fait un sprinteur, et
## c'est ce qui referme le triangle. La pointe, elle, ne bouge pas d'un
## millimetre pendant ce temps.
##
## CE QU'IL FAIT A LA VOITURE
## --------------------------
## Rien de definitif, pour l'instant : le pied SECOUE, il ne tue pas. Un pas qui
## tombe a cote envoie une onde dans le sol, d'autant plus forte qu'il tombe
## pres ; un pied qui tombe DESSUS envoie 60 m/s^2 dans la caisse. Les deux
## passent par `car.impact()`, donc par les suspensions (la camera tressaute) et
## par `frame_accel` (tout ce qui traine dans l'habitacle decolle — le seuil de
## prop.gd est a 2,4 g, un pas proche le franchit).
##
## Il n'a pas de boite de collision. Un pied solide qui se pose sur une
## CharacterBody3D la catapulte au `move_and_slide` suivant, et un pied solide
## qui se pose a cote arrete net une voiture lancee a 160 km/h. Les deux
## demandent une reponse aux degats qui n'existe pas encore.
##

const Retro := preload("res://scripts/retro.gd")

# --------------------------------------------------------------------------
# Anatomie. Une seule mesure est choisie : le pied.
# --------------------------------------------------------------------------

## Le pied, c'est la voiture : Civic EF, 3,965 m sur 1,675 m.
const FOOT_LEN := 3.97
const FOOT_WIDE := 1.68
## La stature qui va avec ce pied (15,2 % chez l'humain).
const HEIGHT := FOOT_LEN / 0.152                  # 26,1 m
## Echelle par rapport a un homme d'1,75 m. Sert aux vitesses et aux cadences.
const SCALE := HEIGHT / 1.75                      # 14,9

const THIGH := 0.245 * HEIGHT                     #  6,40  hanche -> genou
const SHIN := 0.246 * HEIGHT                      #  6,42  genou -> cheville
const LEG := THIGH + SHIN                         # 12,82  ce que la jambe atteint
const ANKLE_H := 0.039 * HEIGHT                   #  1,02  cheville au-dessus du sol
const HIP_HALF := 0.095 * HEIGHT                  #  2,48  demi-ecart des hanches
const TORSO := 0.288 * HEIGHT                     #  7,52  hanche -> epaule
const SHOULDER_HALF := 0.123 * HEIGHT             #  3,21
const UPPER_ARM := 0.186 * HEIGHT                 #  4,86
const FOREARM := 0.146 * HEIGHT                   #  3,81
const HAND := 0.108 * HEIGHT                      #  2,82
const NECK := 0.052 * HEIGHT                      #  1,36
const SKULL := 0.130 * HEIGHT                     #  3,39

## Hauteur de bassin en course : 0,44 de la stature, pas 0,53. Un sprinteur
## court GENOUX FLECHIS, et il le faut ici aussi — a 0,53 la jambe est tendue au
## repos et il ne reste plus un centimetre pour aller poser le pied devant soi.
const HIP_RUN := 0.44 * HEIGHT                    # 11,49
## A l'arret il se redresse.
const HIP_STAND := 0.50 * HEIGHT                  # 13,06
## Accroupi dans les sapins : il ne depasse plus des cimes (6 a 11 m).
const HIP_CROUCH := 0.155 * HEIGHT                #  4,05

## Epaisseurs. Il est SEC : des membres de tronc mort, pas de muscles. Le
## brouillard n'en montrera qu'une silhouette, et une silhouette maigre parmi
## des sapins morts, on la prend pour un arbre jusqu'a ce qu'elle bouge.
const THICK_THIGH := 0.052 * HEIGHT
const THICK_SHIN := 0.040 * HEIGHT
const THICK_ARM := 0.036 * HEIGHT
const THICK_NECK := 0.045 * HEIGHT

# --------------------------------------------------------------------------
# Allure. Froude, comme explique en tete.
# --------------------------------------------------------------------------

## Cadence de course, en PAS par seconde : 4,4 (sprinteur) / racine(14,9).
const RUN_CADENCE := 1.14
## Cadence de marche : 2,0 / racine(14,9).
const WALK_CADENCE := 0.52
## Fraction du cycle passee au sol par chaque pied. 0,24 en course — c'est le
## chiffre d'un sprinteur, et il est bas : les deux pieds sont en l'air plus de
## la moitie du temps. A 0,35 la hanche parcourt 23 m pendant l'appui, il
## faudrait aller poser le pied a 9 m devant soi, et la jambe n'en fait que 12,8.
const DUTY_RUN := 0.24
const DUTY_WALK := 0.62

@export_group("Course")
## Vitesse de pointe, m/s. 10 m/s x racine(14,9) = 38,6. Voir l'en-tete : c'est
## ce nombre qui decide qu'on ne le seme qu'en 5e.
@export var run_speed := 38.0
## Allure tranquille, quand il vient de se relever : 1,4 m/s x racine(14,9).
@export var walk_speed := 5.4
## Ce qu'il gagne ou perd par seconde. Une masse pareille ne s'arrete pas net.
@export var accel := 7.0
@export var brake := 11.0
## Acceleration laterale qu'il peut tenir, m/s^2. Comme la voiture (max_lateral
## = 8) : au-dela on ne tourne pas plus vite, on derape. A 38 m/s cela fait
## 0,22 rad/s, soit un rayon de 170 m — plus large que les courbes de la route
## (110 m mini). Il ne SUIT donc pas la route : il coupe a travers bois en
## ligne de fuite, ce qui lui rend en distance ce que le virage lui coute.
@export var max_lateral := 8.5
## Plafond de rotation a basse vitesse, rad/s. Sans lui il pivoterait sur place
## a 2 rad/s des qu'il ralentit, ce qu'aucun corps de 26 m ne fait.
@export var turn_max := 0.55

@export_group("Apparition")
## Distance a laquelle il remarque la voiture et se leve.
@export var notice_distance := 72.0
## Duree pour se deplier, en secondes.
@export var rise_time := 2.2
## Au-dela, et pendant lose_time, il abandonne.
@export var lose_distance := 200.0
@export var lose_time := 3.0

@export_group("Le pied")
## Secondes entre deux tentatives d'ecrasement. Sans ce delai il viserait la
## voiture a chaque pas et ne courrait plus, il piocherait.
@export var stomp_cooldown := 2.6
## Ce qu'un pied qui tombe DESSUS envoie dans la caisse, en m/s^2. Le plafond de
## frame_accel est a 60 : c'est le choc maximal que le jeu sait transmettre.
@export var stomp_hit_accel := 60.0
## Ce qu'un pas ordinaire envoie dans le sol, juste a cote. 26 m/s^2 = 2,65 g,
## au-dessus du static_mu de prop.gd (2,4 g) : un pas tout pres decroche les
## canettes, un pas a vingt metres ne fait que trembler.
@export var ground_accel := 26.0
## Distance a laquelle l'onde est tombee de moitie.
@export var shock_falloff := 14.0
## De combien le pied monte pendant un pas ordinaire, et pendant un pietinement.
@export var swing_lift := 2.6
@export var stomp_lift := 9.0

@export_group("Voix")
@export var step_volume_db := -1.0
@export var roar_volume_db := 2.0
## A quelle distance le son vaut encore sa pleine intensite. 30 m : a 150 m il
## reste -14 dB, on l'entend donc bien avant de le voir dans le brouillard.
@export var sound_unit := 30.0

enum {
	HIDDEN,      ## eteint, hors du monde
	DORMANT,     ## accroupi dans les arbres, il attend
	RISING,      ## il se deplie
	CHASING,     ## il court apres la voiture
	GIVING_UP,   ## seme : il ralentit et s'eteint
}

## La voiture. Pose par road.gd avec arm().
var target: Node3D
var state := HIDDEN
var speed := 0.0

## Phase du cycle de pas, en tours. Un tour = DEUX pas.
var _phase := 0.0
var _cadence := 0.0
var _duty := DUTY_RUN
var _rise := 0.0                                  # 0 accroupi, 1 debout
var _hip := HIP_CROUCH
var _stomp_wait := 0.0
var _lost := 0.0
var _speed_goal := 0.0
var _lean := 0.0                                  # inclinaison du buste, rad

# Etat des deux jambes. 0 = gauche, 1 = droite.
var _planted: Array[bool] = [true, true]
## Point du monde sous la cheville, au posage. C'est LUI qui ne bouge pas.
var _plant: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Cap du pied au posage : pendant l'appui il ne tourne plus avec le corps.
var _plant_yaw: Array[float] = [0.0, 0.0]
var _swing_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swing_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Part du vol qui n'est que le deplacement du corps. Voir _hip_share.
var _track: Array[float] = [0.0, 0.0]
var _prev_p: Array[float] = [0.0, 0.5]
## Decalage de phase de chaque jambe. Nominalement 0 et 0,5 — un demi-cycle
## d'ecart, c'est ce qui fait marcher plutot que sautiller. On y touche quand
## une jambe doit reposer le pied en catastrophe (voir _stride), et il revient
## tout seul a sa valeur : un coureur qui trebuche retrouve son pas en deux
## foulees, il ne boite pas jusqu'a la fin de ses jours.
var _off: Array[float] = [0.0, 0.5]
## Jambe a qui l'on a confie le pietinement en cours (-1 : aucune).
var _stomp_leg := -1
## Vitesse de rotation appliquee cette image, rad/s. Sert a viser le point de
## pose : pendant qu'un pied vole, le corps a tourne.
var _yaw_rate := 0.0
var _running := false

# Ce qu'on relit dans le banc d'essai.
## Position du monde du dernier pied pose, et s'il a touche la voiture.
var last_step := Vector3.ZERO
var last_step_hit := false
var last_step_stomp := false
var steps := 0
var stomps := 0
var hits := 0

var _mat_hide: ShaderMaterial
var _mat_eye: ShaderMaterial
var _thigh: Array[MeshInstance3D] = []
var _shin: Array[MeshInstance3D] = []
var _foot: Array[Node3D] = []
var _upper: Array[MeshInstance3D] = []
var _fore: Array[MeshInstance3D] = []
var _hand: Array[MeshInstance3D] = []
var _hips: MeshInstance3D
var _chest: MeshInstance3D
var _neck: MeshInstance3D
var _head: Node3D
var _step_snd: Array[AudioStreamPlayer3D] = []
var _roar_snd: AudioStreamPlayer3D


func _ready() -> void:
	_build_body()
	_build_audio()
	visible = false
	set_process(false)


# --------------------------------------------------------------------------
# Vie et mort
# --------------------------------------------------------------------------

## Le pose accroupi dans les arbres, pret a se relever. road.gd l'appelle apres
## avoir place le noeud ; il ne se passe rien tant que la voiture n'approche pas.
func arm(car: Node3D) -> void:
	target = car
	state = DORMANT
	speed = 0.0
	_speed_goal = 0.0
	_phase = 0.0
	_rise = 0.0
	_hip = HIP_CROUCH
	_lean = deg_to_rad(62.0)
	_stomp_wait = 0.0
	_lost = 0.0
	_stomp_leg = -1
	_off = [0.0, 0.5]
	_yaw_rate = 0.0
	_running = false
	steps = 0
	stomps = 0
	hits = 0
	# Les deux pieds a plat sous les hanches, la ou il est accroupi.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_plant[i] = global_position + global_transform.basis.x * (side * HIP_HALF)
		_plant[i].y = 0.0
		_plant_yaw[i] = rotation.y
		_planted[i] = true
		_swing_from[i] = _plant[i]
		_swing_to[i] = _plant[i]
		_track[i] = 0.0
	_prev_p = [0.0, 0.5]
	visible = true
	set_process(true)
	_pose(0.0)


func asleep() -> bool:
	return state == HIDDEN


func sleep() -> void:
	state = HIDDEN
	visible = false
	set_process(false)


# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_stomp_wait = maxf(_stomp_wait - delta, 0.0)

	match state:
		DORMANT:
			_speed_goal = 0.0
			if _flat_distance() < notice_distance:
				state = RISING
				_roar()
		RISING:
			_speed_goal = 0.0
			_rise = minf(_rise + delta / rise_time, 1.0)
			if _rise >= 1.0:
				state = CHASING
		CHASING:
			_chase(delta)
		GIVING_UP:
			_speed_goal = 0.0
			if speed < 0.4:
				sleep()
				return

	_steer(delta)
	_stride(delta)
	_pose(delta)


## Il vise la voiture, et il ralentit quand elle n'est pas devant lui : on ne
## court pas a 137 km/h vers quelque chose qu'on a sur le cote.
func _chase(delta: float) -> void:
	var err := absf(_heading_error())
	_speed_goal = run_speed * lerpf(1.0, 0.35, clampf(err / (PI * 0.5), 0.0, 1.0))
	# Il vient de se relever : il demarre en marchant, la course s'installe.
	_speed_goal = maxf(_speed_goal, walk_speed)

	if _flat_distance() > lose_distance:
		_lost += delta
		if _lost > lose_time:
			state = GIVING_UP
	else:
		_lost = 0.0


## Cap et avance. Le plafond de rotation vient de l'acceleration laterale : a
## pleine vitesse il tourne dix fois moins vite qu'a l'arret.
func _steer(delta: float) -> void:
	var rate := minf(max_lateral / maxf(speed, 1.0), turn_max)
	var before := rotation.y
	rotation.y = _turn_toward(rotation.y, rotation.y + _heading_error(), rate * delta)
	_yaw_rate = angle_difference(before, rotation.y) / maxf(delta, 0.0001)

	var goal := _speed_goal
	var rise := accel if goal > speed else brake
	speed = move_toward(speed, goal, rise * delta)
	global_position += -global_transform.basis.z * speed * delta
	global_position.y = 0.0


func _heading_error() -> float:
	var to_car := target.global_position - global_position
	to_car.y = 0.0
	if to_car.length_squared() < 0.01:
		return 0.0
	return angle_difference(rotation.y, atan2(-to_car.x, -to_car.z))


func _turn_toward(from: float, to: float, max_step: float) -> float:
	var d := angle_difference(from, to)
	return from + clampf(d, -max_step, max_step)


func _flat_distance() -> float:
	var d := target.global_position - global_position
	d.y = 0.0
	return d.length()


# --------------------------------------------------------------------------
# Les pas
# --------------------------------------------------------------------------

## Avance la phase du cycle et gere les deux transitions qui comptent : le
## decollage (on choisit ou le pied va se poser) et le posage (le pied se plante,
## le sol tremble).
func _leg_phase(i: int) -> float:
	return fposmod(_phase + _off[i], 1.0)


func _stride(delta: float) -> void:
	# Cadence et fraction d'appui suivent la vitesse : plus on va vite, plus la
	# cadence monte ET plus la foulee s'allonge, chacune comme la racine de
	# l'autre. Marcher et courir ne sont pas deux animations, c'est la meme.
	var f := clampf(speed / run_speed, 0.0, 1.0)
	_cadence = lerpf(WALK_CADENCE, RUN_CADENCE, sqrt(f))
	_duty = lerpf(DUTY_WALK, DUTY_RUN, f)
	var cycle_rate := _cadence * 0.5              # un cycle = deux pas

	if speed < 0.6:
		_running = false
		return                                    # a l'arret, les pieds restent ou ils sont

	_running = true

	# Les jambes reviennent doucement a leur demi-cycle d'ecart apres un pas de
	# rattrapage. 0,12 tour par seconde : deux foulees pour effacer une bevue.
	for i in 2:
		var nom := 0.5 * float(i)
		var d := angle_difference(_off[i] * TAU, nom * TAU) / TAU
		_off[i] = fposmod(_off[i] + clampf(d, -0.12 * delta, 0.12 * delta), 1.0)

	_phase = fposmod(_phase + cycle_rate * delta, 1.0)

	for i in 2:
		var p := _leg_phase(i)
		# Le posage se reconnait au BOUCLAGE de la phase, pas a un seuil : a
		# 0,3 image de retard on saute par-dessus n'importe quel seuil etroit.
		if p < _prev_p[i]:
			_land(i)
		# Le decollage, lui, ne se lit PAS sur un franchissement de seuil, et
		# c'est le piege : le seuil, c'est `_duty`, et `_duty` bouge avec la
		# vitesse. En passant de l'arret a la course il tombe de 0,62 a 0,24 —
		# une jambe posee a la phase 0,50 se retrouve du mauvais cote sans avoir
		# rien franchi du tout, et reste plantee un cycle entier pendant que le
		# corps s'en va sans elle. On enonce donc l'invariant plutot que sa
		# derivee : une jambe dont la phase dit "en l'air" n'est pas au sol.
		if _planted[i] and p >= _duty:
			_lift(i, cycle_rate)
		_prev_p[i] = p

	# Le PAS DE RATTRAPAGE. Malgre la prevision, un pied pose peut sortir de sa
	# portee : il suffit d'un coup de volant du joueur pour que le geant vire
	# plus fort que prevu et que la hanche s'eloigne du pied plus vite qu'elle
	# ne le devrait. Une jambe ne s'allonge pas, et un pied ne glisse pas : il
	# ne reste donc qu'une issue, celle qu'un coureur prend aussi — reposer le
	# pied tout de suite, hors du rythme. La phase de cette jambe saute a la fin
	# de l'appui, elle repart, et le decalage se resorbe en deux foulees.
	for i in 2:
		if not _planted[i] or _leg_phase(i) < _duty * 0.25:
			continue
		var h := hip(i)
		var a := ankle(i)
		if Vector2(h.x - a.x, h.z - a.z).length() > LEG * 0.94:
			_off[i] = fposmod(_duty - _phase, 1.0)
			_prev_p[i] = _duty
			_lift(i, cycle_rate)


## Decollage : on choisit MAINTENANT le point du monde ou ce pied ira se poser,
## et on n'en change plus. Un pied qui corrigerait sa cible en vol glisserait a
## l'atterrissage.
func _lift(i: int, cycle_rate: float) -> void:
	_planted[i] = false
	# On repart d'OU LA CHEVILLE EST, pas du point ou le pied s'etait pose. En
	# fin d'appui elle est dressee sur la pointe : deux metres plus haut et un
	# metre plus en avant. Repartir du point de pose la ferait retomber d'un
	# coup au ras du sol, a l'image ou le pied quitte le sol — un sursaut visible
	# et, pire, une jambe brusquement trop tendue.
	_swing_from[i] = ankle(i)

	var swing_time := (1.0 - _duty) / cycle_rate
	# Ou sera la hanche quand ce pied touchera le sol. Deux corrections, et
	# aucune des deux n'est un raffinement :
	#
	#   - IL ACCELERE pendant que le pied vole. A 7 m/s^2 sur 1,3 s de vol,
	#     viser avec la vitesse du DEPART place le pied neuf metres trop court,
	#     et neuf metres trop court sur une jambe de treize, c'est le grand
	#     ecart a l'atterrissage. On vise donc avec la vitesse moyenne du vol.
	#   - IL TOURNE pendant ce temps. A 0,55 rad/s, 1,3 s font quarante degres.
	#     On vise le MILIEU de l'arc, pas le cap du moment.
	var v_end := move_toward(speed, _speed_goal, accel * swing_time)
	var advance := (speed + v_end) * 0.5 * swing_time
	var swept := Basis(Vector3.UP, _yaw_rate * swing_time * 0.5)
	var fwd: Vector3 = swept * -global_transform.basis.z
	var right: Vector3 = swept * global_transform.basis.x
	var side := -1.0 if i == 0 else 1.0
	var hip_then := global_position + fwd * advance
	hip_then.y = 0.0

	# Le pietinement : si a cet instant-la le pied peut atteindre la voiture,
	# c'est elle qu'il vise au lieu du sol.
	if _stomp_wait <= 0.0 and state == CHASING:
		var car_vel: Vector3 = target.velocity if "velocity" in target else Vector3.ZERO
		var car_then := target.global_position + car_vel * swing_time
		car_then.y = 0.0
		if hip_then.distance_to(car_then) < _reach() * 0.95:
			_stomp_leg = i
			_swing_to[i] = car_then
			_track[i] = _hip_share(i, advance)
			return

	# Pas ordinaire. Pendant l'appui la hanche parcourt `travel` : le pied se
	# pose en avant d'elle et repart en arriere, et les deux doivent faire la
	# somme, sinon le pied glisse ou le corps saute. On prend 40 % devant,
	# 60 % derriere — a condition que la jambe y arrive.
	var travel := v_end * _duty / cycle_rate
	var ahead := minf(0.40 * travel, _reach() * 0.85)
	_swing_to[i] = hip_then + fwd * ahead + right * (side * HIP_HALF)
	_swing_to[i].y = 0.0
	_track[i] = _hip_share(i, advance)


## Quelle part du chemin du pied n'est que le deplacement du corps.
##
## C'est le nombre qui decide de la forme du vol, et il n'a rien d'arbitraire.
## Pendant qu'un pied fait ses soixante-cinq metres, la hanche en fait cinquante
## — les quinze autres sont le pas proprement dit, celui qui ramene le pied de
## derriere a devant. Interpoler betement entre les deux bouts (un smoothstep du
## depart a l'arrivee) donne un pied qui reste sur place pendant que le corps
## demarre : au quart du vol il traine treize metres en arriere de la hanche,
## pour une jambe qui en fait douze. La jambe casse.
##
## En rendant cette part-la LINEAIRE — le pied suit le corps, tout simplement —
## et en ne lissant que le reste, l'ecart au bassin ne peut plus depasser la
## longueur du pas lui-meme. Ce qui est la definition d'une jambe qui tient.
func _hip_share(i: int, advance: float) -> float:
	var span := _swing_from[i].distance_to(_swing_to[i])
	return clampf(advance / maxf(span, 0.001), 0.0, 1.0)


## Posage : le pied se plante, et le sol prend le coup.
func _land(i: int) -> void:
	_planted[i] = true
	_plant[i] = _swing_to[i]
	_plant_yaw[i] = rotation.y
	steps += 1

	var stomp := _stomp_leg == i
	if stomp:
		_stomp_leg = -1
		_stomp_wait = stomp_cooldown
		stomps += 1

	last_step = _plant[i]
	last_step_stomp = stomp
	last_step_hit = _foot_covers(i, target.global_position)
	if last_step_hit:
		hits += 1

	_boom(i, stomp)
	_shake(i, stomp)


## Le pied couvre-t-il ce point ? Test dans le repere du pied : la voiture et le
## pied font la meme taille a quelques centimetres pres, donc on somme leurs
## demi-cotes. On ne tient pas compte de l'angle de la voiture : au ras d'un
## pied de 4 m, quinze degres de travers ne changent pas la reponse.
func _foot_covers(i: int, p: Vector3) -> bool:
	var d := p - _plant[i]
	d.y = 0.0
	var c := cos(-_plant_yaw[i])
	var s := sin(-_plant_yaw[i])
	var x := d.x * c + d.z * s
	var z := -d.x * s + d.z * c
	# Origine du pied a la cheville : le talon est en arriere (+Z) d'un quart,
	# la pointe en avant (-Z) de trois quarts.
	return absf(x) < FOOT_WIDE * 0.5 + 0.84 \
		and z < FOOT_LEN * 0.25 + 1.98 and z > -FOOT_LEN * 0.75 - 1.98


## Ce que le pas envoie dans la voiture. Un coup droit dessus vaut le plafond ;
## a cote, l'onde tombe en 1/(1+(d/L)^2) — a 14 m il en reste la moitie, a 60 m
## presque rien.
func _shake(i: int, stomp: bool) -> void:
	if not target.has_method("impact"):
		return
	var to_car := target.global_position - _plant[i]
	to_car.y = 0.0
	var d := to_car.length()

	var strength: float
	if last_step_hit:
		strength = stomp_hit_accel
	else:
		strength = ground_accel * (1.6 if stomp else 1.0) / (1.0 + pow(d / shock_falloff, 2.0))
	if strength < 0.5:
		return

	# Le sol pousse vers le haut, et un peu dans le sens oppose au pied : la
	# caisse est chassee par la bosse. En repere voiture, la ou frame_accel vit.
	var away := to_car.normalized() if d > 0.01 else Vector3.ZERO
	var local: Vector3 = target.global_transform.basis.inverse() * away
	target.impact((Vector3.UP * 0.8 + local * 0.6).normalized() * strength)


# --------------------------------------------------------------------------
# La pose
# --------------------------------------------------------------------------

## Distance horizontale maximale a laquelle la hanche peut poser un pied, compte
## tenu de sa hauteur. C'est du Pythagore, et c'est ce qui borne la foulee.
func _reach() -> float:
	var v := _hip - ANKLE_H
	var r := LEG * 0.97
	return sqrt(maxf(r * r - v * v, 0.0))


## Ou est la cheville de la jambe i, en coordonnees du monde.
##
## Au sol : au-dessus du point plante, remontee par le pivotement sur la pointe
## en fin d'appui. En l'air : sur un arc entre le point de depart et la cible.
func _ankle(i: int) -> Vector3:
	var p := _leg_phase(i)
	if _planted[i] or speed < 0.6:
		var lift := _heel_off(i)
		var yaw: float = _plant_yaw[i]
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		# Rotation autour de la POINTE, qui est a 0,75 x FOOT_LEN devant la
		# cheville. La cheville monte et se rapproche de la pointe ; la pointe,
		# elle, ne bouge pas — c'est tout l'interet.
		var toe := _plant[i] + fwd * (FOOT_LEN * 0.75)
		var arm := _plant[i] + Vector3(0.0, ANKLE_H, 0.0) - toe
		var back := -arm.dot(fwd)                 # distance en arriere de la pointe
		var c := cos(lift)
		var s := sin(lift)
		var back2 := back * c - ANKLE_H * s
		var up2 := back * s + ANKLE_H * c
		return toe - fwd * back2 + Vector3(0.0, up2, 0.0)

	var q := clampf((p - _duty) / maxf(1.0 - _duty, 0.001), 0.0, 1.0)
	# La part du chemin qui n'est que le deplacement du corps avance a vitesse
	# constante ; seul le pas proprement dit est lisse. Voir _hip_share.
	var w: float = _track[i]
	var e := w * q + (1.0 - w) * smoothstep(0.0, 1.0, q)
	var flat: Vector3 = _swing_from[i].lerp(_swing_to[i], e)
	var lift := stomp_lift if _stomp_leg == i else swing_lift
	# Le pietinement retombe VITE : la montee prend les deux tiers du vol, la
	# chute le dernier tiers. Un pied qui redescend au meme rythme qu'il est
	# monte n'ecrase rien, il se pose.
	var arc: float
	if _stomp_leg == i:
		arc = (sin(PI * pow(q, 0.62)) if q < 1.0 else 0.0)
	else:
		arc = sin(PI * q)
	# La hauteur suit son propre chemin : elle part de la cheville TELLE QU'ELLE
	# EST au decollage — dressee sur la pointe, deux metres en l'air — et revient
	# a la hauteur du pied a plat pour l'atterrissage. L'arc se pose par-dessus.
	var base := lerpf(_swing_from[i].y, ANKLE_H, smoothstep(0.0, 1.0, q))
	return Vector3(flat.x, base + lift * arc, flat.z)


## Angle de decollement du talon, en radians. Rien pendant la premiere moitie de
## l'appui, puis la cheville se leve jusqu'a 52 degres. Sans ca la jambe est
## trop courte de deux metres au moment de repartir.
func _heel_off(i: int) -> float:
	if not _planted[i] or speed < 0.6:
		return 0.0
	var p := _leg_phase(i)
	var q := clampf(p / maxf(_duty, 0.001), 0.0, 1.0)
	return deg_to_rad(52.0) * smoothstep(0.45, 1.0, q)


func _pose(delta: float) -> void:
	# --- le bassin --------------------------------------------------------
	# Il vise sa hauteur nominale, mais aucune jambe posee ne peut s'allonger :
	# c'est cette borne, et elle seule, qui fait le balancement de la course.
	var stand := lerpf(HIP_STAND, HIP_RUN, clampf(speed / run_speed, 0.0, 1.0))
	var goal := lerpf(HIP_CROUCH, stand, _rise)
	if delta > 0.0:
		_hip = lerpf(_hip, goal, clampf(delta * 9.0, 0.0, 1.0))
	else:
		_hip = goal

	var ankles: Array[Vector3] = [_ankle(0), _ankle(1)]
	for i in 2:
		if not _planted[i]:
			continue
		var side := -1.0 if i == 0 else 1.0
		var hip_w := global_position + global_transform.basis.x * (side * HIP_HALF)
		var flat := Vector2(hip_w.x - ankles[i].x, hip_w.z - ankles[i].z).length()
		var span := LEG * 0.995
		var vmax := sqrt(maxf(span * span - flat * flat, 0.0))
		_hip = minf(_hip, ankles[i].y + vmax)
	_hip = maxf(_hip, HIP_CROUCH * 0.6)

	# --- le buste ---------------------------------------------------------
	# On se penche d'autant plus qu'on va vite : 4 degres a l'arret, 17 lance.
	var lean_goal := lerpf(deg_to_rad(62.0), lerpf(deg_to_rad(4.0),
		deg_to_rad(17.0), clampf(speed / run_speed, 0.0, 1.0)), _rise)
	if delta > 0.0:
		_lean = lerpf(_lean, lean_goal, clampf(delta * 4.0, 0.0, 1.0))
	else:
		_lean = lean_goal

	var hip_c := Vector3(0.0, _hip, 0.0)
	var torso := Basis(Vector3.RIGHT, -_lean)
	var up: Vector3 = torso * Vector3.UP
	var shoulder_c: Vector3 = hip_c + up * TORSO

	_bone(_hips, hip_c - Vector3(HIP_HALF, 0.0, 0.0), hip_c + Vector3(HIP_HALF, 0.0, 0.0),
		THICK_THIGH * 1.5)
	_bone(_chest, hip_c, shoulder_c, THICK_THIGH * 1.9)
	_bone(_neck, shoulder_c, shoulder_c + up * NECK, THICK_NECK)

	# --- les jambes -------------------------------------------------------
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hip := Vector3(side * HIP_HALF, _hip, 0.0)
		var ankle := to_local(ankles[i])
		var knee := _two_bone(hip, ankle, THIGH, SHIN, Vector3.FORWARD)
		_bone(_thigh[i], hip, knee, THICK_THIGH)
		_bone(_shin[i], knee, ankle, THICK_SHIN)
		# Le pied garde SON cap et SON inclinaison : il ne suit pas le corps.
		var yaw: float = _plant_yaw[i] - rotation.y if _planted[i] else 0.0
		var pitch := -_heel_off(i)
		if not _planted[i]:
			# En vol il pointe vers le bas au debut, a plat a l'arrivee : il se
			# prepare a frapper a plat.
			var p := _leg_phase(i)
			var q := clampf((p - _duty) / maxf(1.0 - _duty, 0.001), 0.0, 1.0)
			pitch = -deg_to_rad(28.0) * (1.0 - smoothstep(0.35, 0.95, q))
		_foot[i].transform = Transform3D(
			Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), ankle)

	# --- les bras ---------------------------------------------------------
	# Ils balancent a l'oppose de la jambe du meme cote. Amplitude et flexion du
	# coude montent avec l'allure : bras ballants a l'arret, coudes fermes lance.
	var f := clampf(speed / run_speed, 0.0, 1.0)
	var swing := deg_to_rad(lerpf(4.0, 46.0, f)) * _rise
	var elbow := deg_to_rad(lerpf(12.0, 78.0, f)) * _rise
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := shoulder_c + Vector3(side * SHOULDER_HALF, 0.0, 0.0)
		# +0,5 de dephasage : le bras droit part avec la jambe gauche.
		var a := swing * sin(TAU * (_leg_phase(i) + 0.5))
		var dir: Vector3 = torso * (Basis(Vector3.RIGHT, a)
			* Basis(Vector3.BACK, side * deg_to_rad(9.0)) * Vector3.DOWN)
		var elb := shoulder + dir * UPPER_ARM
		var dir2: Vector3 = torso * (Basis(Vector3.RIGHT, a + elbow)
			* Basis(Vector3.BACK, side * deg_to_rad(9.0)) * Vector3.DOWN)
		var wrist := elb + dir2 * FOREARM
		_bone(_upper[i], shoulder, elb, THICK_ARM)
		_bone(_fore[i], elb, wrist, THICK_ARM * 0.86)
		_bone(_hand[i], wrist, wrist + dir2 * HAND, THICK_ARM * 0.92)

	# --- la tete ----------------------------------------------------------
	# Elle regarde la voiture. C'est le detail qui fait qu'on se sent suivi : le
	# corps court tout droit, la tete, elle, ne lache jamais.
	var head_pos: Vector3 = shoulder_c + up * (NECK + SKULL * 0.5)
	_head.position = head_pos
	var aim := to_local(target.global_position) - head_pos
	var yaw_h := clampf(atan2(-aim.x, -aim.z), deg_to_rad(-75.0), deg_to_rad(75.0))
	var pitch_h := clampf(atan2(aim.y, Vector2(aim.x, aim.z).length()),
		deg_to_rad(-50.0), deg_to_rad(40.0))
	_head.rotation = Vector3(lerpf(-_lean, pitch_h, _rise), yaw_h * _rise, 0.0)


## Place le genou (ou le coude) : intersection des deux spheres de rayon l1 et
## l2 centrees sur la hanche et la cheville, ramenee dans le demi-plan indique
## par `pole` — le genou plie vers l'avant, jamais vers l'arriere.
func _two_bone(root: Vector3, tip: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var axis := tip - root
	var d := axis.length()
	if d < 0.001:
		return root + Vector3(0.0, -l1, 0.0)
	# Jambe trop tendue ou trop repliee : on rabat sur ce qui est atteignable,
	# sinon la racine carree passe dans les negatifs et le membre disparait.
	d = clampf(d, absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := axis / axis.length()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var side := pole - dir * pole.dot(dir)
	if side.length_squared() < 0.0001:
		side = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	return root + dir * a + side.normalized() * h


## Etire un cylindre unite entre deux points.
func _bone(mi: MeshInstance3D, a: Vector3, b: Vector3, thick: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var y := d / l
	# Un axe de reference qui n'est jamais colineaire a l'os : sans cette
	# precaution la base se retourne quand le membre passe a la verticale, et le
	# membre pivote d'un demi-tour sur lui-meme d'une image a l'autre.
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	mi.transform = Transform3D(Basis(x * thick, y * l, x.cross(y) * thick), (a + b) * 0.5)


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _build_body() -> void:
	# La meme famille de couleurs que les troncs de road.gd (0,075 / 0,068 /
	# 0,058), a peine plus sombre. A PEINE : la premiere version etait a 0,052,
	# et de nuit il n'existait tout simplement pas.
	#
	# Il n'a que deux sources : une lune a 0,15 sans ombres, et l'ambiante a
	# 0,055. Les phares regardent devant, les feux arriere ne portent qu'a seize
	# metres, et il est toujours derriere. Ce qui le rend visible n'est donc pas
	# ce qui l'eclaire, c'est le BROUILLARD DEVANT LUI : a cinquante metres, le
	# brouillard a 0,038 remplit les trois quarts du pixel, et lui le quart qui
	# reste. Il ne se lit qu'en tache un peu plus sombre que la nuit. Le
	# descendre a 0,05 revient a effacer cette tache — et un ennemi qu'on ne
	# distingue pas d'un mur noir n'est pas terrifiant, il est absent.
	_mat_hide = Retro.mat(Color(0.070, 0.064, 0.055), 0.97)
	# Les yeux debordent de 1 : le seuil du glow est a 0,95, c'est ce qui leur
	# donne leur halo. Ce sont les deux SEULS points de lui qu'on verra a plus de
	# cent metres — la nuit, les feux arriere ne portent qu'a seize.
	_mat_eye = Retro.mat(Color(0.0, 0.0, 0.0), 1.0)
	_mat_eye.set_shader_parameter("emission", Color(4.2, 1.35, 0.30))

	var limb := CylinderMesh.new()
	limb.top_radius = 0.5
	limb.bottom_radius = 0.5
	limb.height = 1.0
	limb.radial_segments = 7                      # comme les sapins
	limb.rings = 1

	_hips = _mesh(limb)
	_chest = _mesh(limb)
	_neck = _mesh(limb)

	var sole := BoxMesh.new()
	sole.size = Vector3(FOOT_WIDE, ANKLE_H * 0.85, FOOT_LEN)

	for i in 2:
		_thigh.append(_mesh(limb))
		_shin.append(_mesh(limb))
		_upper.append(_mesh(limb))
		_fore.append(_mesh(limb))
		_hand.append(_mesh(limb))

		# Le pied : noeud a la CHEVILLE, semelle decalee. La cheville est au
		# quart avant du talon, comme chez l'humain.
		var foot := Node3D.new()
		foot.name = "Foot_%s" % ("L" if i == 0 else "R")
		add_child(foot)
		var mi := MeshInstance3D.new()
		mi.mesh = sole
		mi.material_override = _mat_hide
		mi.position = Vector3(0.0, -ANKLE_H + ANKLE_H * 0.425, -FOOT_LEN * 0.25)
		foot.add_child(mi)
		_foot.append(foot)

	_head = Node3D.new()
	_head.name = "Head"
	add_child(_head)

	var skull := BoxMesh.new()
	skull.size = Vector3(SKULL * 0.62, SKULL, SKULL * 0.78)
	var sm := MeshInstance3D.new()
	sm.mesh = skull
	sm.material_override = _mat_hide
	_head.add_child(sm)

	var eye := SphereMesh.new()
	eye.radius = SKULL * 0.055
	eye.height = SKULL * 0.11
	eye.radial_segments = 8
	eye.rings = 4
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = eye
		e.material_override = _mat_eye
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.position = Vector3(side * SKULL * 0.17, SKULL * 0.06, -SKULL * 0.40)
		_head.add_child(e)

	# Une braise, pas un phare : elle ne doit rien eclairer, juste marquer les
	# yeux dans le brouillard volumetrique quand il est loin derriere.
	var glow := OmniLight3D.new()
	glow.name = "EyeGlow"
	glow.light_color = Color(1.0, 0.36, 0.10)
	glow.light_energy = 1.6
	glow.omni_range = 7.0
	glow.omni_attenuation = 2.0
	glow.light_volumetric_fog_energy = 1.2
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, SKULL * 0.06, -SKULL * 0.42)
	_head.add_child(glow)


func _mesh(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat_hide
	# Rien de lui ne projette d'ombre : la lune n'en a pas (main.gd coupe les
	# ombres directionnelles) et les phares en auraient une passe entiere a
	# payer pour un objet qui est presque toujours derriere la voiture.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_audio() -> void:
	# Bus de la cabine : ses pas sont DEHORS, ils doivent passer la caisse comme
	# la route et le vent, et s'ouvrir quand on baisse une vitre. Si la voiture
	# n'a pas encore cree le bus, on retombe sur Master sans rien casser.
	var bus := "Cabine" if AudioServer.get_bus_index("Cabine") >= 0 else "Master"
	for i in 2:
		var p := _sound("res://assets/audio/giant/step.wav", bus, step_volume_db)
		_foot[i].add_child(p)
		_step_snd.append(p)
	_roar_snd = _sound("res://assets/audio/giant/roar.wav", bus, roar_volume_db)
	_head.add_child(_roar_snd)


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
		push_warning("son du geant : %s manque, lancer tools/make_giant_sounds.py" % path)
	return p


## Le pas. Le pietinement descend d'une tierce et monte de six decibels : c'est
## la meme masse qui tombe de plus haut et plus vite.
func _boom(i: int, stomp: bool) -> void:
	var p := _step_snd[i]
	if p.stream == null:
		return
	p.pitch_scale = (0.80 if stomp else 1.0) + randf_range(-0.04, 0.04)
	p.volume_db = step_volume_db + (6.0 if stomp else 0.0)
	p.play()


func _roar() -> void:
	if _roar_snd != null and _roar_snd.stream != null:
		_roar_snd.play()


# --------------------------------------------------------------------------
# Ce que le banc d'essai a besoin de voir
# --------------------------------------------------------------------------

## La POINTE du pied i, en coordonnees du monde.
##
## C'est le point qui ne doit pas bouger d'un millimetre pendant tout l'appui :
## pied a plat au debut, pied dresse sur ses orteils a la fin, c'est toujours
## lui le pivot. Le banc d'essai le suit image par image — s'il derive, le geant
## patine, et un geant qui patine se voit au premier coup d'oeil.
func toe(i: int) -> Vector3:
	return _foot[i].global_transform * Vector3(0.0, -ANKLE_H, -FOOT_LEN * 0.75)


## La cheville i (l'origine du noeud du pied), en coordonnees du monde.
func ankle(i: int) -> Vector3:
	return _foot[i].global_position


## La hanche i, en coordonnees du monde. Sa distance a la cheville ne peut pas
## depasser LEG : c'est l'autre moitie du test de patinage.
func hip(i: int) -> Vector3:
	var side := -1.0 if i == 0 else 1.0
	return global_position + global_transform.basis.x * (side * HIP_HALF) \
		+ Vector3(0.0, _hip, 0.0)


func planted(i: int) -> bool:
	return _planted[i]


func hip_height() -> float:
	return _hip


## Cadence courante, en pas par seconde.
func cadence() -> float:
	return _cadence


## Ce que le banc d'essai imprime.
func debug_line() -> String:
	var names := ["eteint", "tapi", "se leve", "court", "abandonne"]
	var to_car := 0.0
	var err := 0.0
	if target != null and is_instance_valid(target):
		to_car = _flat_distance()
		err = rad_to_deg(_heading_error())
	return "%-9s  %5.1f m/s  a %6.1f m  ecart de cap %+6.1f deg  bassin %5.2f m  " \
		% [names[state], speed, to_car, err, _hip] \
		+ "%.2f pas/s  appuis %s%s  pas %d  pietinements %d  touches %d" \
		% [_cadence, "G" if _planted[0] else "-", "D" if _planted[1] else "-",
			steps, stomps, hits]
