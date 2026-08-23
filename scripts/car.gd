extends CharacterBody3D
##
## Honda Civic EF (1990), boite manuelle 5 rapports + marche arriere.
## Vue premiere personne depuis le siege conducteur.
##
## Le modele est volontairement arcade : pas de simulation de couple moteur ni
## de patinage d'embrayage. Chaque rapport a une vitesse au rupteur et une
## poussee. Ca suffit pour que la boite se PILOTE comme une vraie : partir en
## 4e patine, rester en 2e hurle, rater un rapport se sent tout de suite.
##
## Reglages a bidouiller en priorite : GEAR_TOP, GEAR_PULL, engine_power,
## steer_rate, et camera_shake si le tremblement gene.
##

const CabinScript := preload("res://scripts/cabin.gd")
const DriverScript := preload("res://scripts/driver.gd")
const InteractionScript := preload("res://scripts/interaction.gd")
const CigPackScript := preload("res://scripts/cig_pack.gd")
const CanScript := preload("res://scripts/can.gd")
const EngineAudioScript := preload("res://scripts/engine_audio.gd")
const CabinAudioScript := preload("res://scripts/cabin_audio.gd")

# Position du conducteur (volant a gauche). L'oeil est a 1,15 m du sol.
const SEAT_X := -0.33
## Assis AU FOND du siege : le dossier du .glb presente sa face avant a z=0.410,
## le buste fait une dizaine de centimetres, l'epaule tombe donc a 0.30 et l'oeil
## juste devant, a 0.28. Avant il etait a 0.10 : le conducteur etait perche sur
## l'avant de l'assise, le nez sur le volant.
const HEAD_POS := Vector3(SEAT_X, 1.15, 0.28)
## Tete sortie par la vitre conducteur. A 1.14 m elle passe au-dessus de la
## ceinture de caisse (0.97) et sous le pavillon (1.275) : le trajet est degage,
## elle ne traverse ni la portiere ni le montant.
const HEAD_OUT := Vector3(-0.92, 1.14, 0.28)
## Tete quand on se retourne a droite : elle vient se placer entre les deux
## appuis-tete, la ou on regarde reellement par la lunette arriere. Deplacement
## comparable a celui de la vitre, 30 cm sur le cote et 24 cm en arriere.
## Verifie degage : entre les appuis-tete (x -0.21..-0.45 et 0.21..0.45),
## au-dessus d'eux (1.165) et sous le pavillon (1.275).
const HEAD_BACK := Vector3(SEAT_X + 0.30, 1.19, 0.50)

# --- boite de vitesses -----------------------------------------------------
const GEAR_NAMES := ["R", "N", "1", "2", "3", "4", "5"]
const GEAR_R := 0
const GEAR_N := 1
## Vitesse au rupteur, rapport par rapport (m/s). C'est CE tableau qui fixe la
## vitesse maxi de chaque rapport : ~50 / 86 / 122 / 155 / 180 km/h.
const GEAR_TOP := [8.0, 0.0, 14.0, 24.0, 34.0, 43.0, 50.0]
## Poussee relative : un rapport court tire fort, un rapport long ne tire plus.
const GEAR_PULL := [0.85, 0.0, 1.0, 0.68, 0.46, 0.33, 0.24]

@export_group("Moteur")
## m/s^2 en 1re, a plein couple. 4.2 et pas 6.0 : a 6 la voiture abattait le
## 0-100 en 8,1 s, soit une Civic Si. La voila a 12,0 s, ce qu'est vraiment une
## EF de base. Les vitesses maxi ne changent pas, elles viennent de GEAR_TOP et
## du rupteur ; seul le temps pour y arriver s'allonge.
@export var engine_power := 4.2
@export var engine_brake := 3.4        # frein moteur en 1re
@export var coast_drag := 0.9          # deceleration au point mort
@export var over_rev_brake := 10.0     # freinage moteur en sur-regime
@export var idle_rpm := 850.0
@export var redline_rpm := 6800.0
## Vitesse a laquelle le regime retombe A VIDE (debraye ou au point mort), en
## tr/min par seconde, lineaire : le volant moteur freine a couple constant.
## 3500, c'est la ligne rouge au ralenti en 1,7 s. Avant il retombait en lerp
## a 7/s comme la montee : 6000 -> 1700 en un quart de seconde, inaudible.
@export var rpm_fall_rate := 3500.0
## Rupteur : duree de la coupure d'allumage quand le regime touche la ligne
## rouge. Plus c'est long, plus le rebond est ample et lent.
@export var limiter_cut_time := 0.06
## Faux, on peut passer les rapports sans debrayer.
@export var require_clutch := true
## Temps de neutralisation entre deux passages. Sans lui, un seul cran de
## molette envoie plusieurs evenements et on saute deux ou trois rapports.
@export var shift_cooldown := 0.35
## Outil de reglage : plein gaz permanent, sans passer par les touches.
@export var debug_full_throttle := false
## Idem pour le frein, afin de mesurer ce qui decroche dans l'habitacle.
@export var debug_full_brake := false
## Braquage force, -1 a 1. 0 = les touches reprennent la main.
@export var debug_full_steer := 0.0
## Trace dans la console chaque evenement clavier vise par le frein a main.
## Utile si la bascule se remet a partir en vrille.
@export var debug_input := false

@export_group("Chassis")
@export var brake_force := 17.0
## Frein a main en roulant. C'est un frein ARRIERE seulement : il ralentit, il
## n'arrete pas la voiture net. 4 m/s^2, contre 17 pour la pedale.
@export var handbrake_force := 4.0
## Sous 4 m/s il se raidit, sinon "serrer le frein" ne tiendrait pas la voiture.
@export var handbrake_hold := 20.0
## Traînee : proportionnelle a la vitesse, donc elle plafonne la vitesse maxi.
## A 0.16 elle ecrasait tout : chaque rapport butait a 60 km/h, 5e comprise.
@export var rolling_drag := 0.012
@export var max_reverse := 9.0
@export var steer_rate := 1.15         # rad/s a plein braquage et vitesse moyenne
## Acceleration laterale maxi, en m/s^2. C'est l'adherence des pneus : une Civic
## de 1990 sur pneus de route tient 0,8 g, pas 2. Elle fixe le rayon de braquage
## a haute vitesse (r = v^2 / max_lateral) et, par ricochet, ce qui reste en
## place dans l'habitacle en virage.
@export var max_lateral := 8.0
@export var steer_attack := 2.9        # vitesse de braquage du volant
@export var steer_return := 4.2        # rappel du volant au centre

@export_group("Camera")
@export var look_sensitivity := 0.0022
## Large des deux cotes : a droite on se retourne dans l'habitacle, a gauche on
## sort la tete par la vitre.
## 165 et pas 130 : la tete etant dehors, c'est seulement au-dela de 150 qu'on
## regarde vraiment le long du flanc de la voiture, et pas dans le champ.
@export var yaw_limit_left := 165.0
## 160 : torsion du buste (40) plus rotation du cou (120). Au-dela, la pose
## n'est plus tenable pour un humain assis dans un siege.
@export var yaw_limit_right := 160.0
## Au-dela de cet angle vers la droite, le conducteur se retourne : le buste
## pivote et la main droite va se poser sur l'appui-tete passager.
@export var look_back_start := 62.0
## Idem vers la gauche : le buste se penche, la tete sort par la vitre et la
## main gauche va se poser sur le haut de la portiere.
@export var lean_out_start := 62.0
@export var pitch_limit := 62.0
## 50 et pas 46 : la planche de bord du modele Blender est plus profonde que
## l'ancienne en primitives, et a 46 le volant passait sous le cadre.
@export var fov_base := 50.0
@export var fov_fast := 58.0
## Tremblement de caisse. 0 = camera parfaitement stable.
@export var camera_shake := 0.35

var speed := 0.0
var steer := 0.0
var throttle := 0.0
var braking := 0.0
var clutch := false
## Etat effectif du frein a main, lu par le HUD et le conducteur.
var handbrake_on := false
## Serre a l'arret : il reste actif sans tenir la touche.
var handbrake_latched := false
var _hb_press_used := false        # l'appui en cours a servi a desserrer
var gear := GEAR_N
var rpm := 850.0
## Acceleration de la caisse dans son propre repere, lue par les objets libres.
var frame_accel := Vector3.ZERO
var _prev_speed := 0.0
## Vrai pendant une coupure d'allumage du rupteur. Lu par le son.
var limiter_cut := false
var _limiter_timer := 0.0

var head: Node3D
var cam: Camera3D
var cabin
var driver
var interaction
var engine_audio
var cabin_audio

var _headlights: Array[SpotLight3D] = []
var _taillights: Array[SpotLight3D] = []
var _reverse_lights: Array[SpotLight3D] = []
var _lights_on := true
var _bob := 0.0
var _shift_timer := 0.0
var _cam_offset := Vector3.ZERO
var _hud: Label
var _flash: Label
var _flash_timer := 0.0
var _hint: Label
var _fps: Label
var _hint_timer := 11.0


func _ready() -> void:
	_build_collision()

	cabin = CabinScript.new()
	cabin.name = "Cabin"
	add_child(cabin)

	driver = DriverScript.new()
	driver.name = "Driver"
	add_child(driver)

	engine_audio = EngineAudioScript.new()
	engine_audio.name = "EngineAudio"
	engine_audio.idle_rpm = idle_rpm
	engine_audio.redline_rpm = redline_rpm
	add_child(engine_audio)

	cabin_audio = CabinAudioScript.new()
	cabin_audio.name = "CabinAudio"
	add_child(cabin_audio)
	# Le conducteur anime le volant et les leviers du modele Blender plutot que
	# d'en fabriquer en primitives.
	driver.use_controls(cabin.wheel_tilt, cabin.wheel_spin, cabin.shift_pivot,
		cabin.brake_pivot, cabin.knob_local, cabin.grip_local)

	_build_head()

	# Prendre et reposer les objets de l'habitacle. A construire apres la tete :
	# il lui faut la camera.
	interaction = InteractionScript.new()
	interaction.name = "Interaction"
	add_child(interaction)
	interaction.cam = cam
	interaction.driver = driver
	interaction.cabin = cabin
	interaction.carrier = self
	# Le plafonnier s'actionne a la main, comme on attrape un objet.
	if cabin.dome_light != null:
		interaction.usables.append(cabin.dome_light)
	# Retroviseur interieur et pare-soleil : on les place en maintenant le clic.
	interaction.adjustables = cabin.adjustables.duplicate()
	interaction.adjustables.append_array(cabin.visors)
	interaction.adjustables.append_array(cabin.windows)
	_spawn_props()

	_build_lights()
	_build_hud()


func _physics_process(delta: float) -> void:
	throttle = 1.0 if debug_full_throttle else Input.get_action_strength("accelerate")
	braking = 1.0 if debug_full_brake else Input.get_action_strength("brake")
	clutch = Input.is_action_pressed("clutch")
	var steer_input := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	if debug_full_steer != 0.0:
		steer_input = debug_full_steer

	# Frein a main : maintenu en roulant, verrouille a l'arret.
	# L'etat "tenu" vient directement de l'entree, pas d'une bascule : c'est ce
	# qui rend le comportement impossible a desynchroniser.
	var hb_held := Input.is_action_pressed("handbrake") and not _hb_press_used
	handbrake_on = hb_held or handbrake_latched

	var v := absf(speed)
	var engaged := not clutch and gear != GEAR_N

	# --- rupteur ---------------------------------------------------------
	# Coupure d'allumage : des que le regime touche la ligne rouge, plus de
	# poussee pendant limiter_cut_time, frein moteur, puis ca repart. C'est ce
	# qui fixe la vitesse maxi de chaque rapport (GEAR_TOP), et ce qui fait
	# rebondir l'aiguille a vide. En prise on regarde la vitesse plutot que le
	# regime lisse : lui n'atteint la ligne rouge qu'asymptotiquement.
	_limiter_timer = maxf(_limiter_timer - delta, 0.0)
	var at_redline: bool = v >= GEAR_TOP[gear] if engaged else rpm >= redline_rpm - 1.0
	if throttle > 0.0 and at_redline and _limiter_timer <= 0.0:
		_limiter_timer = limiter_cut_time
	limiter_cut = _limiter_timer > 0.0

	# --- transmission ----------------------------------------------------
	if engaged:
		var top: float = GEAR_TOP[gear]
		var pull: float = GEAR_PULL[gear]
		if throttle > 0.0 and not limiter_cut:
			var dir := -1.0 if gear == GEAR_R else 1.0
			speed += dir * engine_power * pull * throttle * _torque(rpm) * delta
		else:
			# Pied leve, ou allumage coupe par le rupteur : frein moteur.
			speed = move_toward(speed, 0.0, engine_brake * pull * delta)

		# Sur-regime : retrograder trop bas fait hurler le moteur, et freine fort.
		if v > top:
			speed = move_toward(speed, signf(speed) * top, over_rev_brake * delta)
	else:
		speed = move_toward(speed, 0.0, coast_drag * delta)

	if braking > 0.0:
		speed = move_toward(speed, 0.0, brake_force * braking * delta)
	# Frein a main : faible en roulant, ferme a l'arret.
	if handbrake_on:
		var grab := lerpf(handbrake_force, handbrake_hold,
			clampf(1.0 - absf(speed) / 4.0, 0.0, 1.0))
		speed = move_toward(speed, 0.0, grab * delta)

	speed -= speed * rolling_drag * delta
	speed = clampf(speed, -max_reverse, GEAR_TOP[GEAR_NAMES.size() - 1])

	# Si on tient le frein jusqu'a l'arret complet, il se verrouille : c'est
	# devenu un frein de stationnement, il faudra un nouvel appui pour l'oter.
	if hb_held and absf(speed) < 0.3:
		handbrake_latched = true

	# --- regime moteur ---------------------------------------------------
	var target_rpm := 0.0
	if engaged:
		target_rpm = idle_rpm + (v / GEAR_TOP[gear]) * (redline_rpm - idle_rpm)
	elif limiter_cut:
		target_rpm = idle_rpm          # allumage coupe : le regime retombe
	else:
		# Debraye ou au point mort : le moteur suit l'accelerateur, et vise
		# AU-DELA de la ligne rouge. C'est le rupteur qui l'arrete, pas un
		# plafond : avec un lerp, un plafond ne serait jamais atteint.
		target_rpm = lerpf(idle_rpm, redline_rpm * 1.06, throttle)
	if not engaged and target_rpm < rpm:
		# A vide, le regime retombe a couple constant, donc lineairement :
		# l'inertie du volant moteur. C'est ce qui donne a entendre la descente,
		# et ce qui fait que le rupteur rebondit de 200 tr/min et pas de 1000.
		rpm = move_toward(rpm, target_rpm, rpm_fall_rate * delta)
	else:
		rpm = lerpf(rpm, target_rpm, clampf(delta * 7.0, 0.0, 1.0))
	rpm = clampf(rpm, idle_rpm, redline_rpm)

	# --- braquage --------------------------------------------------------
	if absf(steer_input) > 0.01:
		steer = move_toward(steer, steer_input, steer_attack * delta)
	else:
		steer = move_toward(steer, 0.0, steer_return * delta)
	steer = clampf(steer, -1.0, 1.0)

	v = absf(speed)
	# Il faut rouler pour tourner, et on braque moins fort a haute vitesse.
	var grip := clampf(v / 5.0, 0.0, 1.0)
	var stability := lerpf(1.0, 0.38, clampf(v / 40.0, 0.0, 1.0))
	var yaw_rate := steer * steer_rate * grip * stability * signf(speed)
	# Plafond d'adherence. Un pneu ne tient qu'une acceleration laterale donnee ;
	# au-dela la voiture SOUS-VIRE, elle ne pivote pas plus vite. Sans ce plafond
	# le modele generait jusqu'a 2,1 g et un rayon de 42 m a 100 km/h — de quoi
	# arracher tout ce qui traine dans l'habitacle a chaque courbe.
	if v > 0.5:
		var cap := max_lateral / v
		yaw_rate = clampf(yaw_rate, -cap, cap)
	rotate_y(yaw_rate * delta)

	# Acceleration de la caisse dans SON PROPRE repere. Les objets poses dedans
	# en ressentent l'oppose : c'est ce qui les fait glisser au freinage et en
	# virage. Lateral = acceleration centripete (omega * v), longitudinal = la
	# variation de vitesse, l'avant etant -Z.
	if delta > 0.0:
		# Bornee et lissee : un changement de rapport ou le rupteur font sauter
		# `speed` d'une image a l'autre, ce qui donnerait une pointe a plusieurs
		# centaines de m/s^2 et catapulterait tout ce qui traine dans l'habitacle.
		# 60 et pas 25 : le plafond doit laisser passer un CHOC (6 g), sinon rien
		# ne peut plus decrocher ce qui est pose. Voir prop.gd static_mu.
		var raw := Vector3(-yaw_rate * speed, 0.0, -(speed - _prev_speed) / delta)
		frame_accel = frame_accel.lerp(raw.limit_length(60.0),
			clampf(delta * 20.0, 0.0, 1.0))
	_prev_speed = speed

	velocity = -global_transform.basis.z * speed
	velocity.y = 0.0
	move_and_slide()


func _process(delta: float) -> void:
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	var v := absf(speed)

	# --- regard : se retourner a droite, sortir la tete a gauche ----------
	var yaw := rad_to_deg(head.rotation.y)
	var look_back := smoothstep(look_back_start, yaw_limit_right - 8.0, -yaw)
	var look_out := smoothstep(lean_out_start, yaw_limit_left - 8.0, yaw)

	# La camera se DEPLACE, comme dans Euro Truck : on se penche, on ne fait pas
	# que pivoter la tete. Le lerp donne du poids au mouvement.
	var head_target := HEAD_POS.lerp(HEAD_BACK, look_back).lerp(HEAD_OUT, look_out)
	head.position = head.position.lerp(head_target, clampf(delta * 7.0, 0.0, 1.0))

	for r in _reverse_lights:
		r.visible = gear == GEAR_R

	# --- camera ----------------------------------------------------------
	# Tremblement de caisse : lent et minuscule. A 60 cm du volant, un centimetre
	# de camera se voit enormement, d'ou des amplitudes de l'ordre du millimetre.
	_bob += delta * (1.3 + v * 0.14)
	var shake := (0.0007 + v * 0.00011) * camera_shake
	cam.position = _cam_offset + Vector3(sin(_bob * 1.15) * shake * 1.2, sin(_bob * 1.9) * shake, 0.0)

	# Roulis : inclinaison dans les virages, plus l'epaule qui tombe quand on se
	# penche a la vitre ou qu'on se retourne.
	var roll := -steer * 0.022 * clampf(v / 8.0, 0.0, 1.0) \
		+ look_out * 0.10 - look_back * 0.05
	cam.rotation.z = lerpf(cam.rotation.z, roll, 4.0 * delta)
	cam.fov = lerpf(cam.fov, lerpf(fov_base, fov_fast, clampf(v / 40.0, 0.0, 1.0)), 3.0 * delta)

	# Tant que le frein est simplement tenu, la main reste sur le levier ;
	# une fois verrouille, elle repart au volant.
	driver.update_pose(steer, throttle, braking, clutch, gear,
		handbrake_on, handbrake_on and not handbrake_latched,
		look_back, look_out, delta)
	var win_open := _window_openness()
	engine_audio.update(rpm, throttle, not clutch and gear != GEAR_N, delta, limiter_cut, win_open)
	cabin_audio.update(speed, gear, handbrake_on, delta, win_open)
	cabin.set_gauges(absf(speed) * 3.6, rpm)
	cabin.set_wheels(speed, steer, delta)
	# Apres la camera : les miroirs se calent sur l'oeil, pas sur la voiture.
	cabin.aim_mirrors(cam.global_position)
	_update_hud(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Reglage d'un retroviseur : la souris l'oriente, LUI, et le regard est
		# bloque. Viser et orienter avec le meme geste est impossible — on
		# perdrait la glace de vue au premier mouvement.
		if interaction.adjusting:
			interaction.adjust(event.relative)
			return
		head.rotation.y = clampf(
			head.rotation.y - event.relative.x * look_sensitivity,
			-deg_to_rad(yaw_limit_right), deg_to_rad(yaw_limit_left))
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * look_sensitivity,
			-deg_to_rad(pitch_limit), deg_to_rad(pitch_limit))
	elif event.is_action_pressed("gear_up"):
		_change_gear(1)
	elif event.is_action_pressed("gear_down"):
		_change_gear(-1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_select_gear(GEAR_N)   # clic molette : point mort direct (debraye)
	elif event is InputEventKey and event.is_action("handbrake"):
		_handbrake_key(event)
	elif event.is_action_pressed("headlights"):
		_lights_on = not _lights_on
		for l in _headlights:
			l.visible = _lights_on
		for t in _taillights:
			t.visible = _lights_on


## Un appui sur Espace ne sert qu'a DESSERRER le frein de stationnement.
## Le reste du temps c'est le maintien de la touche qui agit, lu directement
## dans _physics_process.
func _handbrake_key(event: InputEventKey) -> void:
	if event.pressed and not event.is_echo():
		if handbrake_latched:
			handbrake_latched = false
			# Le meme appui ne doit pas re-serrer aussitot : on le neutralise
			# jusqu'au relachement.
			_hb_press_used = true
		else:
			_hb_press_used = false
	elif not event.pressed:
		_hb_press_used = false
	if debug_input:
		print("[frein a main] pressed=%s echo=%s serre=%s neutralise=%s" % [
			event.pressed, event.is_echo(), handbrake_latched, _hb_press_used])


## Ouverture "acoustique" des vitres, de 0 (fermees) a 1 (une grande ouverte),
## lue par le son. Celle du conducteur compte plein, celle du passager 70 % :
## elle est plus loin de l'oreille. Deux vitres ouvertes ne font pas deux fois
## plus de bruit, d'ou le produit des fermetures.
func _window_openness() -> float:
	var closed := 1.0
	for w in cabin.windows:
		closed *= 1.0 - w.open * (1.0 if w.side < 0.0 else 0.7)
	return 1.0 - closed


## Courbe de couple grossiere : creux sous 2000 tr/min, plein entre 3200 et
## 5000, ca retombe vers le rupteur. C'est ce qui rend le choix du rapport utile.
func _torque(r: float) -> float:
	var rise := clampf((r - 800.0) / 2400.0, 0.0, 1.0)
	var fade := clampf((redline_rpm - r) / 1800.0, 0.0, 1.0)
	return (0.35 + 0.65 * rise) * lerpf(0.55, 1.0, fade)


## Molette vers le haut : R -> N -> 1 -> 2 ... Vers le bas : l'inverse.
func _change_gear(step: int) -> void:
	_select_gear(clampi(gear + step, 0, GEAR_NAMES.size() - 1))


## Passe directement au rapport `next` (molette, ou clic molette pour le point
## mort). Memes garde-fous que la molette : cooldown, embrayage, marche arriere.
func _select_gear(next: int) -> void:
	# La boite est verrouillee juste apres un passage : un cran de molette
	# produit plusieurs evenements, sans ca on saute deux ou trois rapports.
	# Silencieux exprès, sinon le HUD clignoterait a chaque cran avale.
	if _shift_timer > 0.0:
		return
	if require_clutch and not clutch:
		_show_flash("DEBRAYE (MAJ)")
		return
	if next == gear:
		return
	if next == GEAR_R and speed > 2.0:
		_show_flash("TROP RAPIDE POUR LA MARCHE ARRIERE")
		return
	gear = next
	_shift_timer = shift_cooldown


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

## Les objets ramassables sont enfants de la caisse et se simulent dans SON
## repere : voir cig_pack.gd. Ils ne touchent jamais au serveur physique.
func _spawn_props() -> void:
	var pack := CigPackScript.new()
	pack.name = "CigPack"
	pack.carrier = self
	pack.cabin = cabin
	cabin.add_child(pack)
	pack.position = CabinScript.PACK_SPAWN
	pack.rotation.y = deg_to_rad(-24.0)
	interaction.grabbables.append(pack)          # reste le premier : les bancs d'essai le cherchent la

	# Canettes, intactes et ecrasees, aux emplacements de cabin.gd.
	for spec in CabinScript.CAN_SPAWNS:
		var can := CanScript.new()
		can.name = "Can_%s%s" % [spec[0], "_Crushed" if spec[1] else ""]
		can.drink = spec[0]
		can.crushed = spec[1]
		can.carrier = self
		can.cabin = cabin
		can.reset_point = spec[2]
		cabin.add_child(can)
		can.position = spec[2]
		can.rotation.y = deg_to_rad(spec[3])
		interaction.grabbables.append(can)


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.675, 1.34, 3.965)     # cotes reelles d'une Civic EF
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.67, 0.0)
	add_child(col)


func _build_head() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = HEAD_POS
	add_child(head)

	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov_base
	cam.near = 0.04
	cam.far = 400.0
	head.add_child(cam)
	_cam_offset = Vector3.ZERO


func _build_lights() -> void:
	for side in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.name = "Headlight%s" % ("L" if side < 0.0 else "R")
		l.position = Vector3(side * 0.53, 0.78, -2.04)
		l.rotation_degrees = Vector3(-3.5, side * 3.0, 0.0)
		l.light_color = Color(1.0, 0.95, 0.86)
		l.light_energy = 12.0
		l.spot_range = 80.0
		l.spot_angle = 36.0
		l.spot_angle_attenuation = 0.35
		l.spot_attenuation = 0.85
		# Bas volontairement : sinon la boule de brouillard autour de l'ampoule
		# deborde du capot et se voit depuis le siege.
		l.light_volumetric_fog_energy = 0.12
		l.shadow_enabled = true
		l.shadow_bias = 0.05
		add_child(l)
		_headlights.append(l)

	# Feux arriere. Ils ne servent pas a voir : ils posent une flaque rouge de
	# quelques metres derriere la caisse, et c'est la SEULE chose que les
	# retroviseurs ont a refleter la nuit sur une route deserte. Sans eux les
	# trois glaces sont noires et le joueur croit qu'elles ne marchent pas.
	for side in [-1.0, 1.0]:
		var t := SpotLight3D.new()
		t.name = "Tail%s" % ("L" if side < 0.0 else "R")
		t.position = Vector3(side * 0.62, 0.88, 1.96)
		# Peu plongeant, et une portee de 16 m : les glaces de portiere cadrent la
		# chaussee entre 7 et 14 m en arriere. Une flaque tombee au pied de la
		# caisse serait sous leur champ, donc invisible.
		t.rotation_degrees = Vector3(-11.0, 180.0, 0.0)  # le spot eclaire vers -Z
		t.light_color = Color(1.0, 0.14, 0.09)
		t.light_energy = 3.0
		t.spot_range = 16.0
		t.spot_angle = 62.0
		t.spot_angle_attenuation = 0.6
		t.light_volumetric_fog_energy = 0.16
		t.shadow_enabled = false
		add_child(t)
		_taillights.append(t)

	# Feux de recul : sans eux, se retourner ne montre qu'un mur noir.
	for side in [-1.0, 1.0]:
		var r := SpotLight3D.new()
		r.name = "Reverse%s" % ("L" if side < 0.0 else "R")
		r.position = Vector3(side * 0.45, 0.72, 2.02)
		r.rotation_degrees = Vector3(-9.0, 180.0, 0.0)   # le spot eclaire vers -Z
		r.light_color = Color(0.92, 0.95, 1.0)
		r.light_energy = 5.5
		r.spot_range = 26.0
		r.spot_angle = 48.0
		r.spot_angle_attenuation = 0.5
		r.light_volumetric_fog_energy = 0.10
		r.shadow_enabled = false
		r.visible = false
		add_child(r)
		_reverse_lights.append(r)

	# Pas de lumiere d'habitacle ici : le plafonnier (dome_light.gd, cree par la
	# cabine) est la seule, et il s'allume et s'eteint a la main.


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud.offset_left = -300.0
	_hud.offset_top = -118.0
	_hud.offset_right = -24.0
	_hud.offset_bottom = -22.0
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hud.add_theme_font_size_override("font_size", 26)
	_hud.add_theme_color_override("font_color", Color(1.0, 0.45, 0.22, 0.85))
	layer.add_child(_hud)

	_flash = Label.new()
	_flash.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_flash.offset_left = -260.0
	_flash.offset_top = -170.0
	_flash.offset_right = 260.0
	_flash.offset_bottom = -140.0
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 17)
	_flash.add_theme_color_override("font_color", Color(1.0, 0.35, 0.20, 0.9))
	_flash.modulate.a = 0.0
	layer.add_child(_flash)

	_fps = Label.new()
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.offset_left = -140.0
	_fps.offset_top = 16.0
	_fps.offset_right = -20.0
	_fps.offset_bottom = 40.0
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps.add_theme_font_size_override("font_size", 13)
	_fps.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 0.35))
	layer.add_child(_fps)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 24.0
	_hint.offset_top = -76.0
	_hint.offset_right = 700.0
	_hint.offset_bottom = -22.0
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.text = "ZQSD / WASD / fleches : conduire    Maj : embrayage    Molette : rapports, clic : point mort\nH : phares    Espace : frein a main    Souris : regarder"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88, 0.5))
	layer.add_child(_hint)


func _show_flash(text: String) -> void:
	_flash.text = text
	_flash_timer = 1.4


func _update_hud(delta: float) -> void:
	var kmh := int(round(absf(speed) * 3.6))
	_hud.text = "%s    %d km/h\n%d tr/min%s" % [
		GEAR_NAMES[gear], kmh, int(round(rpm)),
		"\nFREIN A MAIN" if handbrake_on else ""]
	_hud.add_theme_color_override("font_color",
		Color(1.0, 0.25, 0.15, 0.95) if rpm > redline_rpm * 0.9
		else Color(1.0, 0.45, 0.22, 0.85))

	_fps.text = "%d ips" % Engine.get_frames_per_second()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		_flash.modulate.a = clampf(_flash_timer / 0.5, 0.0, 1.0)

	if _hint_timer > 0.0:
		_hint_timer -= delta
		_hint.modulate.a = clampf(_hint_timer / 2.5, 0.0, 1.0)
