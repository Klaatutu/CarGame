extends Node3D
##
## Point d'entree du prototype.
## Construit l'ambiance de nuit, la route infinie et la voiture.
##

const CarScript := preload("res://scripts/car.gd")
const RoadScript := preload("res://scripts/road.gd")
const DayCycleScript := preload("res://scripts/daycycle.gd")
const SleepScript := preload("res://scripts/sleep.gd")
const Retro := preload("res://scripts/retro.gd")
const DriverScript := preload("res://scripts/driver.gd")
const GiantScript := preload("res://scripts/giant.gd")
## Le maillage de l'habitacle, pour les BANCS D'ESSAI seulement : c'est le seul
## juge de "il est dans la tole" qui n'ait pas participe a y mettre la bestiole.
const MeshProbeScript := preload("res://scripts/mesh_probe.gd")

@export_group("Ambiance")
## Densite du brouillard : plus c'est haut, moins on voit loin.
@export var fog_density := 0.030
@export var volumetric := true
## Le clair de lune pose sur le decor.
##
## C'etait 0,05 quand la lune etait a 52 degres de hauteur. A 9 degres le rayon
## est rasant : le sol ne recoit plus que sin(9) = 0,16 de l'energie au lieu de
## 0,79, tandis qu'un tronc, une face verticale tournee vers elle, en prend 0,99
## au lieu de 0,62. Aucune valeur ne peut donc rendre exactement la nuit d'avant
## — a 0,15 le sol est un peu plus sombre qu'il ne l'etait et les troncs, eux,
## se detachent nettement. C'est ce que fait une lune basse : elle rase.
## Premier bouton a baisser si la nuit parait trop claire.
@export var moon_energy := 0.15
## Hauteur de la lune au-dessus de l'horizon, en degres.
##
## Mesure faite au pare-brise (fov 50, 720 px) : le pavillon coupe le ciel a
## 11 degres et la cime des sapins monte a 10 — il ne reste qu'une bande etroite
## ou la lune se voit en roulant. Au-dela de 12 on ne la trouve plus qu'en se
## penchant a la portiere ; a 9 elle est dans la bande, et les arbres qui
## passent devant ne font que la voiler par intermittence.
@export var moon_elevation := 9.0
## Ecart avec l'axe de la route au depart, en degres. Negatif = a gauche.
@export var moon_azimuth := -16.0
## Diametre apparent, en degres. La vraie lune fait 0,5 : on triche d'un facteur
## six, sinon elle ne pese rien a l'ecran une fois tramee — et surtout elle ne
## se lit plus dans les trouees entre les sapins, qui la cachent la moitie du
## temps. 3,2 degres font une lune basse de fin de nuit, un peu grosse.
@export var moon_apparent_size := 3.2

# Dans les 400 m du plan lointain de la camera, et bien au-dela du decor.
const MOON_DISTANCE := 260.0
# Le quad est plus large que le disque : le surplus loge le halo. A 3.6 le halo
# s'arretait net et faisait une boule de brume posee sur le ciel ; il lui faut
# de la place pour mourir loin du limbe.
const MOON_HALO_RATIO := 6.0

var car
var road
## Le cycle jour/nuit : le proprietaire de l'ambiance du monde normal.
var daycycle
## La jauge de veille et ses paupieres (sleep.gd).
var sleep
## "normal" ou "nightmare". Le cauchemar, c'est le monde d'avant : les
## monstres armes, la nuit rouge — on y entre en s'endormant, on en sort par
## le portail. Voir la section "le sommeil et le cauchemar" plus bas.
var world_mode := "normal"
## Le sommeil ne compte qu'en partie normale : les bancs d'essai gardent un
## conducteur d'acier. _start_normal_world le leve.
var sleep_enabled := false
var _ground: MeshInstance3D
var _moon: Node3D
var _env: Environment
var _auto_shot := -1
## Charge a la premiere question d'un banc, jamais en jeu. Voir _mesh_probe().
var _mesh_cache


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_environment()
	_build_moon()
	_build_ground()
	_build_dither_overlay()

	# Le cycle jour/nuit. Il photographie la nuit que _build_environment vient
	# de poser (sa reference), et devient le seul a ecrire dans l'Environment.
	daycycle = DayCycleScript.new()
	daycycle.name = "DayCycle"
	daycycle.env = _env
	daycycle.moon = _moon
	daycycle.night_moon_energy = moon_energy
	add_child(daycycle)

	car = CarScript.new()
	car.name = "Car"
	add_child(car)

	road = RoadScript.new()
	road.name = "Road"
	road.target = car
	add_child(road)

	# L'etrangleur previent quand il tient le conducteur ; la suite — camera
	# arrachee ou vision qui s'eteint — se joue ici, ou vivent l'ecran et la
	# camera. Voir la section "l'etrangleur" en fin de fichier.
	road.strangler.caught.connect(_on_strangler_caught)
	road.strangler.died.connect(_on_strangler_died)

	# La jauge de veille. Elle previent quand tout se ferme ; la bascule vers
	# le cauchemar se joue ici, ou vivent l'ecran, l'ambiance et la route.
	sleep = SleepScript.new()
	sleep.name = "Sleep"
	sleep.car = car
	sleep.daycycle = daycycle
	add_child(sleep)
	sleep.fell_asleep.connect(_enter_nightmare)

	# Les bancs et les captures supposent la nuit de reference : le cycle est
	# gele a 23 h — l'image d'avant le cycle, au bit pres, puisque la nuit est
	# photographiee sur l'Environment. daytest le manoeuvre lui-meme.
	if not OS.get_cmdline_user_args().is_empty():
		daycycle.frozen = true
		daycycle.set_hour(23.0)
	else:
		# Une PARTIE : le monde normal — pas de monstres sur la route du
		# soir, le mille-pattes dort, et le sommeil compte.
		_start_normal_world()

	# Lance le jeu avec  -- shot  pour capturer des images puis quitter,
	# ou  -- geartest  pour relever la vitesse maxi de chaque rapport.
	if "shot" in OS.get_cmdline_user_args():
		_auto_capture()
	elif "geartest" in OS.get_cmdline_user_args():
		_gear_test()
	elif "hbtest" in OS.get_cmdline_user_args():
		_handbrake_test()
	elif "audiotest" in OS.get_cmdline_user_args():
		_audio_test()
	elif "packtest" in OS.get_cmdline_user_args():
		_pack_test()
	elif "mirrortest" in OS.get_cmdline_user_args():
		_mirror_test()
	elif "visortest" in OS.get_cmdline_user_args():
		_visor_test()
	elif "windowtest" in OS.get_cmdline_user_args():
		_window_test()
	elif "revolvertest" in OS.get_cmdline_user_args():
		_revolver_test()
	elif "leantest" in OS.get_cmdline_user_args():
		_lean_test()
	elif "wheeltest" in OS.get_cmdline_user_args():
		_wheel_test()
	elif "wraptest" in OS.get_cmdline_user_args():
		_wrap_test()
	elif "moontest" in OS.get_cmdline_user_args():
		_moon_test()
	elif "throwtest" in OS.get_cmdline_user_args():
		_throw_test()
	elif "stalltest" in OS.get_cmdline_user_args():
		_stall_test()
	elif "glaretest" in OS.get_cmdline_user_args():
		_glare_test()
	elif "gianttest" in OS.get_cmdline_user_args():
		_giant_test()
	elif "centipedetest" in OS.get_cmdline_user_args():
		_centipede_test()
	elif "bugthrowtest" in OS.get_cmdline_user_args():
		_bugthrow_test()
	elif "stranglertest" in OS.get_cmdline_user_args():
		_strangler_test()
	elif "daytest" in OS.get_cmdline_user_args():
		_day_test()
	elif "sleeptest" in OS.get_cmdline_user_args():
		_sleep_test()


func _process(delta: float) -> void:
	# Le sol suit la voiture : on ne voit jamais son bord dans le brouillard.
	if is_instance_valid(car):
		_ground.global_position = Vector3(car.global_position.x, -0.04, car.global_position.z)
		# La lune suit aussi, mais en translation seulement : son orientation
		# reste celle du monde. On ne s'en rapproche donc jamais (pas de
		# parallaxe a 260 m), et la route serpente librement dessous — elle
		# passe devant, puis sur le cote, puis dans le retroviseur.
		_moon.global_position = Vector3(car.global_position.x, 0.0, car.global_position.z)
	_process_doom(delta)
	# Le sommeil ne compte qu'en partie normale, jamais pendant que
	# l'etranglement ou l'ecran de fin tiennent la camera.
	sleep.suspended = (not sleep_enabled) or doom_mode != "" \
		or game_over_shown or world_mode == "nightmare"
	# Le portail : franchi (et pas deja pris a la gorge), on se reveille.
	if world_mode == "nightmare" and doom_mode == "" and not game_over_shown \
			and road.portal.crossed_by(car.global_position):
		_exit_nightmare()


func _unhandled_input(event: InputEvent) -> void:
	if game_over_shown and ((event is InputEventKey and event.pressed
			and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE])
			or (event is InputEventMouseButton and event.pressed)):
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# La molette sert a passer les rapports : elle ne doit pas recapturer.
		# Et souris deja capturee, le clic gauche sert a attraper les objets.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		_screenshot(false)


## F12 : capture d'ecran dans le dossier utilisateur du projet.
func _screenshot(_unused: bool) -> void:
	await _shot("shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://%s" % fname
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT: ", ProjectSettings.globalize_path(path))


## Verifie qu'un retroviseur reflete vraiment : ou est sa camera virtuelle, ce
## qu'elle voit devant elle, et si son rendu n'est pas une image vide.
##
## Le test qui compte est le premier : la camera doit se trouver EXACTEMENT au
## symetrique de l'oeil par rapport au plan de la glace. Une image plausible peut
## sortir d'une camera mal placee — pas une erreur de 0 mm.
func _probe_mirror(m: Node3D) -> void:
	var cam: Camera3D = m.get_node("View/Eye")
	var eye: Vector3 = car.cam.global_position
	var n: Vector3 = m.global_transform.basis.z.normalized()
	var d: float = (eye - m.global_position).dot(n)
	var want: Vector3 = eye - 2.0 * d * n

	var img: Image = (m.get_node("View") as SubViewport).get_texture().get_image()
	var sum := 0.0
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y).get_luminance()
	var mean := sum / float(img.get_width() * img.get_height())

	print("  %-22s oeil reflechi a %.4f m du calcul   vise %s   near=%.2f  luminance=%.3f" % [
		m.name, cam.global_position.distance_to(want),
		(cam.global_transform.basis * Vector3.FORWARD).snappedf(0.01),
		cam.near, mean])


## Verifie que le tramage est bien present : imprime un bloc de 12x6 pixels.
## Si les valeurs sont toutes identiques, le motif ne sort pas.
func _probe_dither(at: Vector2i, label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var lines := "-- tramage, zone %s --\n" % label
	for y in 6:
		for x in 12:
			lines += "%4d" % int(round(img.get_pixel(at.x + x, at.y + y).r * 255.0))
		lines += "\n"
	print(lines)


## Injecte deux cycles appui/relachement d'Espace et imprime l'etat du frein a
## main apres chacun. A bascule, on doit lire : vrai, vrai, faux, faux.
func _handbrake_test() -> void:
	await get_tree().create_timer(0.4).timeout
	Engine.time_scale = 3.0
	car.gear = 5                 # 4e
	car.speed = 25.0             # 90 km/h

	# 1. En roulant : actif tant qu'on tient la touche, et seulement tant qu'on
	#    la tient.
	await _send_space(true, false, 0.25)
	print("roule, touche tenue       -> %s" % car.handbrake_on)
	await _send_space(false, false, 0.25)
	print("roule, touche relachee    -> %s" % car.handbrake_on)

	# 2. Tenu jusqu'a l'arret : il se verrouille tout seul et reste serre.
	car.speed = 6.0
	await _send_space(true, false, 0.0)
	var guard := 0.0
	while absf(car.speed) > 0.05 and guard < 20.0:
		await get_tree().physics_frame
		guard += get_physics_process_delta_time()
	await get_tree().create_timer(0.2, true, false, true).timeout
	print("arret atteint             -> verrouille=%s" % car.handbrake_latched)
	await _send_space(false, false, 0.25)
	print("touche relachee a l'arret -> %s" % car.handbrake_on)

	# 3. Nouvel appui : il se desserre.
	await _send_space(true, false, 0.25)
	print("nouvel appui              -> %s" % car.handbrake_on)
	await _send_space(false, false, 0.25)
	print("touche relachee           -> %s" % car.handbrake_on)

	# 4. Efficacite.
	car.gear = 5
	car.speed = 25.0
	car.handbrake_latched = true
	var t := 0.0
	while car.speed > 0.5 and t < 60.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	print("90 km/h -> arret, frein seul : %.1f s" % t)

	car.gear = 2                 # 1re
	car.debug_full_throttle = true
	await get_tree().create_timer(3.0, true, false, true).timeout
	print("plein gaz en 1re, frein serre : %.1f km/h" % (car.speed * 3.6))

	Engine.time_scale = 1.0
	get_tree().quit()


func _send_space(pressed: bool, echo: bool, wait: float) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = pressed
	ev.echo = echo
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	if wait > 0.0:
		await get_tree().create_timer(wait, true, false, true).timeout


## Banc d'essai du son moteur : coup de gaz embrayage enfonce, puis depart en
## 1re jusqu'au rupteur et levee de pied. Imprime ce que fait le noeud audio
## (boucles choisies, pitch, volumes). En --headless le mixage est muet mais
## toute la logique tourne, c'est suffisant pour la verifier.
func _audio_test() -> void:
	var ea = car.engine_audio
	print("boucles moteur : ", ea.loop_rpms())
	print("boucle WAV     : ", ea.loop_info())
	await get_tree().create_timer(0.5).timeout
	print("ralenti        ", ea.debug_line())

	Input.action_press("clutch")
	Input.action_press("accelerate")
	for i in 8:
		await get_tree().create_timer(0.25).timeout
		print("coup de gaz    ", ea.debug_line())
	Input.action_release("accelerate")
	for i in 4:
		await get_tree().create_timer(0.25).timeout
		print("retombee       ", ea.debug_line())

	Input.action_release("clutch")
	car.gear = 2
	Input.action_press("accelerate")
	for i in 14:
		await get_tree().create_timer(0.5).timeout
		print("1re plein gaz  ", ea.debug_line())
	Input.action_release("accelerate")
	for i in 4:
		await get_tree().create_timer(0.5).timeout
		print("pied leve      ", ea.debug_line())

	# Habitacle : route et vent a la vitesse atteinte, puis un passage et le
	# frein a main, pour verifier que les transitions declenchent les sons.
	var ca = car.cabin_audio
	print("habitacle      ", ca.debug_line())
	car.gear = 3
	await get_tree().process_frame
	await get_tree().process_frame
	print("passage 2e     ", ca.debug_line())
	Input.action_press("handbrake")
	await get_tree().create_timer(0.4).timeout
	print("frein tire     ", ca.debug_line())
	Input.action_release("handbrake")
	await get_tree().create_timer(0.4).timeout
	print("frein lache    ", ca.debug_line())

	# Vitre conducteur ouverte a 90 km/h : le vent, le battement et la couche
	# "dehors" du moteur doivent monter, puis retomber quand on la ferme.
	if not car.cabin.windows.is_empty():
		car.gear = 5
		car.speed = 25.0
		car.cabin.windows[0].open = 1.0
		await get_tree().create_timer(0.5).timeout
		print("vitre ouverte  ", ca.debug_line())
		print("               ", ea.debug_line())
		car.cabin.windows[0].open = 0.0
		await get_tree().create_timer(0.3).timeout
		print("vitre fermee   ", ca.debug_line())
		print("               ", ea.debug_line())
	get_tree().quit()


## Banc d'essai de la vitre conducteur : viser la manivelle, la tourner.
##
## Ce qu'on veut prouver : la manivelle tourne vraiment, la vitre descend assez
## bas pour disparaitre sous la ceinture de caisse, et les DEUX glaces bougent —
## celle de l'habitacle et celle de la carrosserie. N'en bouger qu'une laisserait
## l'autre en l'air, bien visible de l'exterieur.
func _window_test() -> void:
	const State_IDLE := 0             # interaction.State.IDLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.8).timeout
	var inter = car.interaction
	var win: Node3D = car.cabin.windows[0]           # portiere conducteur
	var inner: MeshInstance3D = car.cabin.find_child("DOOR_L_Glass", true, false)
	var outer: MeshInstance3D = car.cabin.find_child("EXT_DoorGlass_L", true, false)
	var trim: MeshInstance3D = car.cabin.find_child("DOOR_L_BeltTrim", true, false)
	var belt_y: float = _panel_box(trim).end.y

	# Vitre fermee, vue par la portiere : c'est la reference. Les deux captures
	# doivent etre prises du MEME endroit, sinon on ne compare rien.
	_env.ambient_light_energy = 2.2
	await _aim_at(Vector3(-1.6, 1.05, -0.2))
	await get_tree().create_timer(0.4).timeout
	await _shot("18_vitre_haute.png")

	await _aim_at(car.to_local(win.global_position))
	print("vise la manivelle   : cible=%s   indice=%s" % [
		inter.target == win, inter._hint.text])
	var up_in := _panel_box(inner)
	var up_out := _panel_box(outer)

	await _mouse(true)
	# La main part chercher la poignee : rien ne tourne avant qu'elle y soit.
	await get_tree().create_timer(0.9).timeout
	var crank0: float = win._crank.rotation.x
	print("poignee saisie      : indice=%s" % inter._hint.text)

	# LE POINT DU GESTE : la camera reste libre. On tourne la tete PENDANT qu'on
	# manoeuvre, ce qui est impossible avec un reglage a la souris.
	var head0: Vector3 = car.head.rotation
	await _move_mouse(Vector2(120.0, 0.0))
	print("  CAMERA LIBRE      : %s   (tete bougee de %.3f rad)" % [
		head0.distance_to(car.head.rotation) > 0.05,
		head0.distance_to(car.head.rotation)])
	print("  RIEN N'A TOURNE   : %s   (la souris ne commande pas la manivelle)" % [
		absf(win._crank.rotation.x - crank0) < 0.0001])

	# Le cran ne doit pas descendre au levier tant que la poignee est tenue. On
	# DEBRAYE avant de le verifier : pedale relevee la boite refuserait de toute
	# facon, et un rapport inchange ne prouverait rien.
	await _act("clutch", true)
	var gear0: int = car.gear

	# Molette vers le bas : la vitre descend. Huit crans a 0,15 couvrent la
	# course entiere, et on laisse a la manivelle le temps de les rattraper —
	# elle ne saute pas a la butee, elle y va a `open_rate`.
	await _wheel(8, MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().create_timer(2.6).timeout
	print("  BOITE INTACTE     : %s   (rapport %d, etait %d)" % [
		car.gear == gear0, car.gear, gear0])
	await _act("clutch", false)
	print("baissee a fond      : ouverture=%.2f   manivelle %.1f tours" % [
		win.open, absf(win._crank.rotation.x - crank0) / TAU])
	print("  ELLE A TOURNE     : %s" % (absf(win._crank.rotation.x - crank0) > TAU))

	var low_in := _panel_box(inner)
	var low_out := _panel_box(outer)
	print("  glace habitacle   : haut y=%.3f (etait %.3f)   ceinture a %.3f" % [
		low_in.end.y, up_in.end.y, belt_y])
	print("  ELLE A DISPARU    : %s   (descendue de %.0f mm)" % [
		low_in.end.y < belt_y, (up_in.end.y - low_in.end.y) * 1000.0])
	print("  LES DEUX BOUGENT  : %s   (carrosserie descendue de %.0f mm)" % [
		absf((up_out.end.y - low_out.end.y) - (up_in.end.y - low_in.end.y)) < 0.001,
		(up_out.end.y - low_out.end.y) * 1000.0])
	# On regarde par la portiere SANS lacher la poignee : c'est justement ce que
	# la camera libre permet.
	await _aim_at(Vector3(-1.6, 1.05, -0.2))
	await get_tree().create_timer(0.4).timeout
	await _shot("18_vitre_baissee.png")

	# Molette vers le haut : elle remonte exactement d'ou elle vient.
	await _wheel(8, MOUSE_BUTTON_WHEEL_UP)
	await get_tree().create_timer(2.6).timeout
	print("remontee            : ouverture=%.2f   haut y=%.3f" % [
		win.open, _panel_box(inner).end.y])
	print("  ELLE EST FERMEE   : %s" % (
		absf(_panel_box(inner).end.y - up_in.end.y) < 0.002))

	# On la rouvre a fond, puis on LACHE LE CLIC EN COURS DE ROUTE : la main doit
	# lacher, la vitre rester ou elle en est, et les crans pas encore rattrapes
	# etre oublies. Verifier le relachement vitre fermee ne prouverait rien, elle
	# serait deja en butee ; le verifier une fois la course finie non plus, il ne
	# resterait rien a oublier. D'ou les 0,5 s : six crans demandes, un quart de
	# la course faite.
	await _wheel(6, MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().create_timer(0.5).timeout
	await _mouse(false)
	var mid: float = win.open
	await get_tree().create_timer(0.6).timeout
	print("clic relache a %.2f  : la main a lache=%s   ouverture=%.2f" % [
		mid, inter._state == State_IDLE, win.open])
	print("  A MI-COURSE       : %s   (ni fermee ni en butee)" % (
		mid > 0.02 and mid < 0.98))
	print("  ELLE RESTE LA     : %s   (les crans en attente sont oublies)" % (
		absf(win.open - mid) < 0.001))

	# Et la molette ne doit plus rien faire a la vitre : la poignee n'est plus en
	# main, le cran est redescendu au levier de vitesses.
	await _wheel(3, MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().create_timer(0.5).timeout
	print("  MOLETTE SANS MAIN : %s   (ouverture toujours %.2f)" % [
		absf(win.open - mid) < 0.001, win.open])
	get_tree().quit()


## Banc d'essai des pare-soleil : viser, maintenir, placer a la souris.
##
## Ce qu'on veut prouver : la souris en bas le rabat VRAIMENT sous la ligne des
## yeux (sinon il ne sert a rien) ; la souris de cote l'emmene vers la vitre ;
## et il ne peut pas partir sur le cote tant qu'il est range, sinon il balaierait
## le ciel de toit.
func _visor_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.8).timeout
	var inter = car.interaction
	var visor: Node3D = car.cabin.visors[0]          # celui du conducteur
	var panel: MeshInstance3D = car.cabin.find_child("BODY_Visor_L", true, false)
	var eye_y: float = car.head.position.y
	# La tige : c'est par rapport a elle qu'on juge de quel cote le panneau part.
	var rod: MeshInstance3D = car.cabin.find_child("BODY_VisorRod_L", true, false)
	var rod_z: float = _panel_box(rod).get_center().z
	# Face inferieure du ciel de toit : au-dessus, un pare-soleil est invisible.
	var liner: MeshInstance3D = car.cabin.find_child("BODY_Headliner", true, false)
	var liner_y: float = _panel_box(liner).position.y

	await _aim_at(car.to_local(visor.global_position))
	print("vise le pare-soleil : cible=%s   indice=%s" % [
		inter.target == visor, inter._hint.text])
	var up := _panel_box(panel)
	_env.ambient_light_energy = 2.2
	await get_tree().create_timer(0.3).timeout
	await _shot("17_pare_soleil_range.png")

	await _mouse(true)
	print("clic maintenu       : reglage=%s" % inter.adjusting)
	await get_tree().create_timer(0.6).timeout   # la main doit etre arrivee : avant, rien ne bouge

	# 1. Souris en bas, a fond : il doit descendre sous la ligne des yeux, sinon
	#    il ne sert a rien.
	for i in 30:
		await _move_mouse(Vector2(0.0, 24.0))
	var low := _panel_box(panel)
	print("deploye a fond      : angle=%+.1f deg   bord bas y=%.3f (range %.3f)" % [
		visor.angle, low.position.y, up.position.y])
	print("  IL EST DESCENDU   : %s   (%.0f mm)" % [
		low.position.y < up.position.y - 0.02,
		(up.position.y - low.position.y) * 1000.0])
	print("  IL FAIT DE L'OMBRE: %s   (%.0f mm sous l'oeil)" % [
		low.position.y < eye_y, (eye_y - low.position.y) * 1000.0])
	await _shot("17_pare_soleil_deploye.png")

	# 2. Souris en haut, a fond : retour a plat. Deux choses a prouver, pas une.
	#    A PLAT : la boite englobante s'aplatit a l'epaisseur du panneau.
	#    VERS LE JOUEUR : elle passe DERRIERE la tige, pas devant.
	for i in 60:
		await _move_mouse(Vector2(0.0, -24.0))
	var flat := _panel_box(panel)
	print("range a fond        : angle=%+.1f deg   hauteur %.3f m   z=%.3f..%.3f" % [
		visor.angle, flat.size.y, flat.position.z, flat.end.z])
	print("  IL EST A PLAT     : %s   (%.0f mm d'epaisseur)" % [
		flat.size.y < 0.035, flat.size.y * 1000.0])
	print("  VERS LE JOUEUR    : %s   (tige a z=%.3f)" % [
		flat.position.z > rod_z - 0.01, rod_z])
	# Et surtout : il doit DEPASSER du ciel de toit, sinon on est revenu au
	# defaut d'origine, un pare-soleil enterre dans la garniture.
	print("  PAS ENTERRE       : %s   (%.0f mm sous la garniture, qui est a %.3f)" % [
		flat.position.y < liner_y - 0.005, (liner_y - flat.position.y) * 1000.0,
		liner_y])
	# On se remet a regarder devant : vise sur le pare-soleil, la capture ne
	# montrerait que le plafond.
	await _aim_at(Vector3(car.SEAT_X, 1.30, -1.4))
	await _shot("17_pare_soleil_range_a_plat.png")
	await _mouse(false)
	get_tree().quit()


## Boite englobante du panneau, en espace voiture.
func _panel_box(panel: MeshInstance3D) -> AABB:
	return car.global_transform.affine_inverse() \
		* panel.global_transform * panel.mesh.get_aabb()


## Banc d'essai du reglage du retroviseur : viser, maintenir, orienter.
## Ce qu'on veut prouver : pendant le reglage la tete du conducteur ne bouge
## PLUS et la glace, elle, bouge — et l'inverse une fois le clic relache.
func _mirror_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.8).timeout
	var inter = car.interaction
	var mirror: Node3D = car.cabin.adjustables[0]

	await _aim_at(car.to_local(mirror.global_position))
	print("vise le retroviseur : cible=%s   indice=%s" % [
		inter.target == mirror, inter._hint.text])

	car.cam.fov = 11.0
	_env.ambient_light_energy = 2.2      # de nuit on ne verrait pas le cadre bouger
	await get_tree().create_timer(0.4).timeout
	await _shot("16_retro_avant.png")

	var head0: Vector3 = car.head.rotation
	var n0: Vector3 = mirror.global_transform.basis.z
	await _mouse(true)
	print("clic maintenu       : reglage=%s" % inter.adjusting)
	await get_tree().create_timer(0.6).timeout   # la main doit etre arrivee : avant, rien ne bouge

	for i in 12:
		await _move_mouse(Vector2(9.0, 4.0))
	var head1: Vector3 = car.head.rotation
	var n1: Vector3 = mirror.global_transform.basis.z
	print("souris pendant      : tete bougee de %.4f rad   glace de %.2f deg" % [
		head0.distance_to(head1), rad_to_deg(n0.angle_to(n1))])
	print("  REGARD BLOQUE     : %s" % (head0.distance_to(head1) < 0.0001))
	print("  GLACE ORIENTEE    : %s" % (rad_to_deg(n0.angle_to(n1)) > 1.0))

	# La camera virtuelle doit avoir suivi : sans ca on regle un cadre vide.
	var cam: Camera3D = mirror.get_node("View/Eye")
	var eye: Vector3 = car.cam.global_position
	var d: float = (eye - mirror.global_position).dot(n1.normalized())
	print("  CAMERA SUIVIE     : ecart %.4f m" % cam.global_position.distance_to(
		eye - 2.0 * d * n1.normalized()))

	await _shot("16_retro_apres.png")

	await _mouse(false)
	print("clic relache        : reglage=%s" % inter.adjusting)
	var n2: Vector3 = mirror.global_transform.basis.z
	for i in 12:
		await _move_mouse(Vector2(9.0, 4.0))
	print("souris apres        : tete bougee de %.4f rad   glace de %.2f deg" % [
		head1.distance_to(car.head.rotation), rad_to_deg(n2.angle_to(
			mirror.global_transform.basis.z))])
	print("  REGARD REVENU     : %s" % (head1.distance_to(car.head.rotation) > 0.01))
	print("  REGLAGE CONSERVE  : %s" % (rad_to_deg(n2.angle_to(
		mirror.global_transform.basis.z)) < 0.01))
	get_tree().quit()


## Banc d'essai du calage et du demarreur.
##
## Ce qu'on veut prouver tient en une phrase : c'est LACHER L'EMBRAYAGE qui
## cale, pas rouler doucement. Les deux premiers essais sont donc la meme
## situation — a l'arret, un rapport engage, pied leve — et ne different que par
## la pedale d'embrayage. Si les deux calaient, ou si aucun ne calait, le
## mecanisme serait branche sur autre chose que ce qu'on croit.
##
## On verifie ensuite qu'on peut PARTIR. C'est le vrai risque de cette
## fonctionnalite : a l'instant ou l'on lache l'embrayage a l'arret, la vitesse
## est nulle, donc le regime aussi, et un calage immediat rendrait tout depart
## impossible. C'est stall_grace qui l'evite, et il faut le montrer.
func _stall_test() -> void:
	await get_tree().create_timer(0.6).timeout
	print("au lancement       : %d tr/min   cale=%s   (point mort)" % [
		roundi(car.rpm), car.stalled])
	print("  son du demarreur : %s" % (car._starter_snd != null))
	print("  son du calage    : %s" % (car._stall_snd != null))

	# --- 1. debraye, a l'arret, en 1re : il TIENT --------------------------
	car.gear = 2
	car.speed = 0.0
	await _act("clutch", true)
	await get_tree().create_timer(car.stall_grace + 0.4).timeout
	print("debraye, a l'arret : %d tr/min   cale=%s" % [roundi(car.rpm), car.stalled])
	print("  IL TIENT         : %s   (rien ne tire le moteur vers le bas)" %
		(not car.stalled))

	# --- 2. le meme, embrayage lache : il CALE -----------------------------
	await _act("clutch", false)
	var died: bool = await _until(func(): return car.stalled, car.stall_grace + 1.5)
	print("embrayage lache    : cale=%s   %d tr/min" % [died, roundi(car.rpm)])
	print("  IL CALE          : %s" % died)

	# Le moteur doit s'ETEINDRE, pas rester a regime : c'est ce que le son suit.
	await get_tree().create_timer(0.8).timeout
	print("  moteur eteint    : %s   (%d tr/min)" % [car.rpm < 60.0, roundi(car.rpm)])

	# --- 3. cale, l'accelerateur ne commande plus rien ---------------------
	car.debug_full_throttle = true
	await get_tree().create_timer(1.2).timeout
	print("plein gaz, cale    : %.2f km/h" % (car.speed * 3.6))
	print("  RIEN NE PART     : %s" % (absf(car.speed) < 0.05))
	car.debug_full_throttle = false

	# --- 4. le demarreur, rapport engage : il POUSSE, il ne lance pas ------
	var before: float = car.speed
	var reached: bool = await _turn_key(true)
	print("cle visee et prise : %s" % reached)
	# On suit la POINTE pendant le coup de demarreur, pas l'etat apres. La
	# voiture sursaute et retombe : le demarreur s'arrete au bout de start_time
	# et stall_drag la ramene a zero en un dixieme de seconde. Relever la vitesse
	# une fois tout fini, c'est mesurer le retour au calme et conclure qu'il ne
	# s'est rien passe — ce que ce banc a commence par faire.
	var peak := 0.0
	var left: float = car.start_time + 0.4
	while left > 0.0:
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
		peak = maxf(peak, absf(car.speed - before))
	print("demarreur en prise : cale=%s   pointe %.2f m/s" % [car.stalled, peak])
	print("  IL NE PART PAS   : %s   (on demarre embraye)" % car.stalled)
	print("  ELLE SURSAUTE    : %s   (%.2f m/s pendant le lancement)" % [
		peak > 0.05, peak])

	# --- 5. la cle, embraye : elle LANCE -----------------------------------
	# Deux captures encadrent le geste : le sens de rotation ne se lit dans aucun
	# chiffre — un signe faux donnerait exactement les memes degres, du mauvais
	# cote de l'axe. Il faut le voir.
	_env.ambient_light_energy = 2.2
	await _act("clutch", true)
	var angle_off: float = car.cabin.ignition._angle
	await _aim_at(car.to_local(car.cabin.ignition.global_position))
	await _shot("19_cle_arret.png")
	await _turn_key(true)
	var lit: bool = await _until(func(): return not car.stalled, car.start_time + 1.5)
	print("cle tournee embraye: demarre=%s   %d tr/min" % [lit, roundi(car.rpm)])
	print("  ELLE DEMARRE     : %s" % lit)
	print("  AU RALENTI       : %s   (%d tr/min, ralenti %d)" % [
		absf(car.rpm - car.idle_rpm) < 200.0, roundi(car.rpm), roundi(car.idle_rpm)])

	# La cle doit AVOIR TOURNE, et etre revenue du demarreur au contact toute
	# seule. Un moteur qui demarre sans que rien ne bouge a l'ecran, c'est une
	# touche deguisee en geste.
	await get_tree().create_timer(0.6).timeout
	var angle_run: float = car.cabin.ignition._angle
	print("  ELLE A TOURNE    : %s   (arret %.0f deg -> contact %.0f deg)" % [
		absf(angle_run - angle_off) > 5.0, angle_off, angle_run])
	print("  REVENUE DU START : %s   (contact %.0f, demarreur %.0f)" % [
		absf(angle_run) < car.cabin.ignition.start_angle - 5.0,
		angle_run, -car.cabin.ignition.start_angle])
	await _aim_at(car.to_local(car.cabin.ignition.global_position))
	await _shot("19_cle_contact.png")

	# --- 5 bis. molette vers le BAS : on coupe -----------------------------
	await _turn_key(false)
	await get_tree().create_timer(0.5).timeout
	print("molette bas        : cale=%s   %d tr/min   cle a %.0f deg" % [
		car.stalled, roundi(car.rpm), car.cabin.ignition._angle])
	print("  CONTACT COUPE    : %s" % car.stalled)
	print("  CLE SUR L'ARRET  : %s" % (absf(car.cabin.ignition._angle) < 5.0))
	# Et on le relance pour la suite.
	await _turn_key(true)
	await _until(func(): return not car.stalled, car.start_time + 1.5)

	# --- 6. on peut PARTIR de l'arret ---------------------------------------
	# Le risque de cette fonctionnalite, et la raison d'etre de stall_grace.
	car.speed = 0.0
	car.gear = 2
	car.debug_full_throttle = true
	await _act("clutch", false)
	await get_tree().create_timer(2.5).timeout
	print("depart plein gaz   : cale=%s   %.1f km/h" % [car.stalled, car.speed * 3.6])
	print("  ELLE PART        : %s   (sans caler)" % (
		not car.stalled and car.speed * 3.6 > 8.0))
	car.debug_full_throttle = false

	# --- 7. pied leve au meme endroit : elle cale ---------------------------
	# Le pendant du precedent. Meme rapport, meme depart, seule la pedale de
	# droite change : c'est elle qui fait la difference, et rien d'autre.
	car.speed = 0.0
	var stalls: bool = await _until(func(): return car.stalled, car.stall_grace + 1.5)
	print("depart pied leve   : cale=%s" % stalls)
	print("  ELLE CALE        : %s" % stalls)

	# --- 8. la demultiplication decide, pas un reglage ----------------------
	# On ne cale pas a la meme vitesse selon le rapport, et personne n'a ecrit
	# ces vitesses nulle part : elles sortent de GEAR_TOP.
	print("vitesse de ralenti par rapport (en dessous, il faut debrayer) :")
	for g in range(car.GEAR_NAMES.size()):
		if g == car.GEAR_N:
			continue
		print("  %-2s  %5.1f km/h" % [car.GEAR_NAMES[g], car._creep_speed(g) * 3.6])

	# Et on le VERIFIE sur deux rapports opposes, a une MEME vitesse choisie
	# entre les deux : la 5e doit caler la ou la 1re tient sans broncher.
	#
	# La vitesse est MAINTENUE pendant la mesure, et c'est tout le sujet. Pied
	# leve, une voiture ralentit jusqu'a l'arret et finit par caler dans
	# n'importe quel rapport : un banc qui la laisse faire mesure le frein
	# moteur, pas la demultiplication, et il voit deux calages qui ne prouvent
	# rien. En tenant la vitesse, le seul terme qui change d'un essai a l'autre
	# est le rapport engage.
	var probe: float = car._creep_speed(2) * 0.8      # 80 % du ralenti de 1re
	for g in [2, 6]:
		await _restart_engine()
		car.gear = g
		await _act("clutch", false)
		for i in 100:                                  # ~1,7 s a vitesse tenue
			car.speed = probe
			await get_tree().physics_frame
		print("  a %.1f km/h en %-2s : %4d tr/min   cale=%s" % [
			probe * 3.6, car.GEAR_NAMES[g], roundi(car.rpm), car.stalled])
	get_tree().quit()


## Remet le moteur en marche entre deux essais, au point mort pour qu'il y reste.
func _restart_engine() -> void:
	car.gear = car.GEAR_N
	await _act("clutch", true)
	if car.stalled:
		await _turn_key(true)
		await _until(func(): return not car.stalled, car.start_time + 1.5)


## Vise la cle de contact, la prend, et donne UN cran de molette.
##
## `up` vrai : vers le haut, on lance. Faux : vers le bas, on coupe.
##
## C'est le geste complet, avec de vrais clics et de vrais crans — pas un appel
## direct a car.key_start(). Ce qui doit etre eprouve ici, c'est justement la
## chaine visee -> prise -> molette : appeler la methode par-dessous prouverait
## que le moteur demarre, et rien du tout sur la facon dont on le demarre.
func _turn_key(up: bool) -> bool:
	var key: Node3D = car.cabin.ignition
	if key == null:
		print("PAS DE CLE DE CONTACT dans le .glb")
		return false
	var inter = car.interaction
	var aimed := false
	for i in 3:
		await _aim_at(car.to_local(key.global_position))
		aimed = inter.target == key
		if aimed:
			break
	if not aimed:
		return false

	await _mouse(true)
	# La main part chercher la cle : un cran donne avant qu'elle y soit ne
	# compterait pas (interaction.gd exige _blend >= 1).
	await get_tree().create_timer(0.9).timeout
	await _wheel(1, MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN)
	await _mouse(false)
	return true


func _move_mouse(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


## Banc d'essai du paquet de cigarettes : viser, prendre, deplacer, reposer.
func _pack_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.8).timeout
	var inter = car.interaction
	var pack: Node3D = inter.grabbables[0]
	# Le paquet vit dans le monde : on le ramene en espace voiture pour viser.
	var local: Vector3 = car.to_local(pack.global_position)
	print("paquet trouve      : %s   pos voiture=%s" % [pack != null, local.snappedf(0.001)])
	print("repose sur l'assise: %s   (dessus a 0.484)" % (absf(local.y - 0.495) < 0.02))

	await _aim_at(local)
	print("vise le paquet     : cible=%s" % (inter.target == pack))

	# Le bras part le chercher : la prise n'est pas immediate.
	await _click()
	print("juste apres clic   : tenu=%s (le bras part)" % (inter.held == pack))
	await get_tree().create_timer(0.9).timeout
	print("geste termine      : tenu=%s   fige=%s" % [inter.held == pack, pack.held])

	# La main ne doit PAS suivre le regard.
	await _aim_at(Vector3(-0.20, 0.952, -0.84))
	var hand_a: Vector3 = car.driver.hand_right().position
	await _aim_at(Vector3(0.80, 0.60, 0.90))          # regard loin a droite
	var hand_b: Vector3 = car.driver.hand_right().position
	print("main tenue         : ecart %.4f m quand la tete tourne" %
		hand_a.distance_to(hand_b))

	# Depose : on MAINTIENT pour viser, le fantome apparait, on relache.
	await _aim_at(Vector3(-0.20, 0.952, -0.84))
	await _mouse(true)
	await get_tree().create_timer(0.3).timeout
	print("clic maintenu      : fantome=%s   surface=%s   etat=%d   pieces=%d" % [
		inter.ghost_visible(), inter.has_surface(), inter._state, inter.ghost_parts()])
	await _mouse(false)
	await get_tree().create_timer(1.0).timeout
	local = car.to_local(pack.global_position)
	print("apres relachement  : tenu=%s   fige=%s   pos=%s" % [
		inter.held != null, pack.held, local.snappedf(0.001)])

	# Physique : il doit tenir sur la planche, pas tomber a travers.
	await get_tree().create_timer(1.2).timeout
	print("1,2 s plus tard    : pos=%s" % car.to_local(pack.global_position).snappedf(0.001))

	# En roulant, l'habitacle doit l'emmener au lieu de le laisser derriere.
	# On accelere pour de vrai : teleporter la vitesse ferait glisser l'objet de
	# plusieurs metres avant qu'il rattrape, ce qu'aucune voiture ne fait.
	var placed: Vector3 = car.to_local(pack.global_position)
	car.gear = 2
	car.debug_full_throttle = true
	await get_tree().create_timer(3.5).timeout
	local = car.to_local(pack.global_position)
	print("apres acceleration : %.0f km/h   pos voiture=%s" % [
		car.speed * 3.6, local.snappedf(0.001)])
	print("  IL RESTE EN PLACE: %s   (bouge de %.3f m)" % [
		local.distance_to(placed) < 0.01, local.distance_to(placed)])

	# Virage a fond de volant, a la vitesse ou l'acceleration laterale est la
	# plus forte. Rien ne doit bouger non plus : les pneus ne tiennent que
	# max_lateral, sous le seuil d'adherence du paquet.
	car.debug_full_steer = 1.0
	await get_tree().create_timer(3.0).timeout
	local = car.to_local(pack.global_position)
	print("plein virage       : %.0f km/h   %.2f g lateraux   bouge de %.3f m" % [
		car.speed * 3.6, absf(car.frame_accel.x) / 9.81, local.distance_to(placed)])
	print("  IL RESTE EN PLACE: %s" % (local.distance_to(placed) < 0.01))
	car.debug_full_steer = 0.0
	await get_tree().create_timer(1.0).timeout

	# Freinage d'urgence : rien ne doit bouger non plus. Seul un choc, au-dela de
	# tout ce que la conduite produit, decroche ce qui est pose.
	car.debug_full_throttle = false
	car.debug_full_brake = true
	await get_tree().create_timer(2.0).timeout
	local = car.to_local(pack.global_position)
	print("freinage d'urgence : %.0f km/h   bouge de %.3f m" % [
		car.speed * 3.6, local.distance_to(placed)])
	print("  IL RESTE EN PLACE: %s" % (local.distance_to(placed) < 0.01))

	# Choc : une secousse vers l'ARRIERE, ou il y a de la place. Vers l'avant il
	# butera sur le pare-brise au bout de deux centimetres et on ne mesurera rien.
	car.debug_full_brake = false
	pack.vel += Vector3(0.0, 0.0, 0.9)
	await get_tree().create_timer(1.0).timeout
	local = car.to_local(pack.global_position)
	print("choc violent       : bouge de %.3f m   (il DOIT bouger)" %
		local.distance_to(placed))
	get_tree().quit()


## Banc d'essai du lancer : prendre le paquet, le jeter au clic molette, et
## verifier qu'il part VRAIMENT PAR LA OU ON REGARDE.
##
## Ce qui se mesure ici est un ANGLE, pas une position d'arrivee. Une vitesse de
## depart de la bonne longueur mais tournee de quinze degres donnerait un point
## de chute parfaitement plausible dans l'habitacle — et un lancer qui part de
## travers, ce qui se voit du premier coup d'oeil et ne se lirait dans aucune
## coordonnee.
##
## Le CAP (l'angle a plat) est mesure a part du reste : c'est le seul que la
## gravite ne touche jamais. Le temps que le banc relise la vitesse, l'objet a
## deja pris une image ou deux de chute, et l'angle a trois dimensions en garde
## la trace — pas le cap.
##
## On verifie aussi que le meme bouton n'a PAS passe le point mort au passage :
## la molette appartient a la boite de vitesses quand les mains sont vides.
func _throw_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Par defaut Godot met les evenements injectes en file et ne les distribue
	# qu'a l'image suivante : la vitesse de depart ne serait alors plus lisible
	# nulle part, l'objet ayant deja vole. Ici l'evenement part tout de suite.
	Input.use_accumulated_input = false
	await get_tree().create_timer(0.9).timeout
	var inter = car.interaction
	var pack: Node3D = inter.grabbables[0]
	print("paquet trouve      : %s" % (pack != null))

	# --- le prendre --------------------------------------------------------
	var local: Vector3 = car.to_local(pack.global_position)
	var aimed := false
	for i in 3:
		await _aim_at(local)
		aimed = inter.target == pack
		if aimed:
			break
	print("  VISE             : %s" % aimed)
	await _click()
	var took: bool = await _until(func(): return inter.held == pack)
	print("  PRIS EN MAIN     : %s   (fige=%s)" % [took, pack.held])
	if not took:
		print("ABANDON : rien en main, il n'y a rien a lancer")
		get_tree().quit()
		return

	# --- viser ailleurs, en l'air, et lancer -------------------------------
	# Vers le haut du pare-brise, cote passager : de la place devant, et une
	# direction qui n'est parallele a aucun axe — un lancer qui partirait de
	# travers ne pourrait pas passer inapercu.
	await _aim_at(Vector3(0.30, 1.35, -1.10))
	var eye: Transform3D = car.global_transform.affine_inverse() * car.cam.global_transform
	var dir: Vector3 = (-eye.basis.z).normalized()
	var from: Vector3 = car.to_local(pack.global_position)
	# Un rapport engage AVANT le lancer : s'il tient, c'est que le clic molette
	# ne s'est pas propage jusqu'au levier.
	car.gear = 2
	await _shot("40_lancer_en_main.png")

	# L'evenement est distribue DANS parse_input_event : la vitesse est donc
	# lisible avant toute attente. Et il faut la lire la — deux images de vol
	# suffisent a lui faire cogner le pare-brise, et on mesurerait le rebond au
	# lieu du lancer.
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	ev.pressed = true
	Input.parse_input_event(ev)
	var v: Vector3 = pack.vel
	var spin: float = pack.spin.length()
	var empty: bool = inter.held == null
	var loose: bool = not pack.held
	var st: int = inter._state
	await _mouse(false, MOUSE_BUTTON_MIDDLE)

	var flat_v := Vector3(v.x, 0.0, v.z)
	var flat_d := Vector3(dir.x, 0.0, dir.z)
	print("lance              : regard=%s   du poing %s" % [
		dir.snappedf(0.001), from.snappedf(0.001)])
	print("  LACHE            : main vide=%s   fige=%s   etat=%d (0=IDLE)" % [
		empty, not loose, st])
	print("  DANS L'AXE       : %.2f deg d'ecart avec le regard" %
		rad_to_deg(v.angle_to(dir)))
	print("     cap a plat    : %.2f deg" % rad_to_deg(flat_v.angle_to(flat_d)))
	print("  VITESSE          : %.2f m/s   (consigne %.2f)" % [v.length(), inter.throw_speed])
	print("  il tourne        : %.1f rad/s" % spin)
	print("  RAPPORT INTACT   : %s   (gear=%d, la molette n'a pas debraye)" % [
		car.gear == 2, car.gear])

	# --- il vole, il retombe, il se remet d'aplomb -------------------------
	# On le SUIT pendant le vol au lieu de ne regarder que le point d'arrivee :
	# un objet qui sort de la caisse et que le filet de securite de prop.gd
	# rapatrie sur le siege se pose exactement comme un objet qui n'en est
	# jamais sorti. Seule la trajectoire les distingue.
	# La trajectoire part du poing : le point de lancer en fait partie, et c'est
	# souvent lui le plus haut de tout le vol.
	var high := from.y
	var fore := from.z
	var far := 0.0
	var jump := 0.0
	var prev := Vector3.INF
	var was := 0.0
	var t := 1.8
	var shot := 0.14
	while t > 0.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t -= dt
		high = maxf(high, pack.position.y)
		fore = minf(fore, pack.position.z)
		far = maxf(far, pack.position.distance_to(from))
		# Un deplacement que la VITESSE N'EXPLIQUE PAS n'est pas un vol : c'est
		# le rapatriement de prop.gd, donc une fuite hors de l'habitacle. Le
		# comparer a une distance fixe ne dirait rien — a 20 images par seconde
		# un lancer en parcourt deja 22 cm.
		#
		# La vitesse a retenir est celle d'AVANT le pas : c'est elle qui a fait
		# le deplacement. Celle d'apres, sur l'image du rebond, est dix fois
		# plus petite et ferait passer le choc pour une teleportation.
		if prev.is_finite():
			jump = maxf(jump, pack.position.distance_to(prev) - was * dt)
		prev = pack.position
		was = pack.vel.length()
		shot -= dt
		if shot <= 0.0 and shot > -900.0:
			shot = -1000.0
			await _shot("41_lancer_en_vol.png")
	print("  IL PART VRAIMENT : %s   (%.2f m parcourus)" % [far > 0.30, far])
	print("  RESTE DEDANS     : %s   (monte a y=%.2f, avance a z=%.2f)" % [
		high < 1.34 and fore > -1.05, high, fore])
	print("  PAS DE FUITE     : %s   (plus grand bond inexplique : %.3f m)" % [
		jump < 0.15, jump])

	var still: bool = await _until(func(): return pack.vel.length() < 0.05, 4.0)
	await get_tree().create_timer(1.0).timeout
	local = car.to_local(pack.global_position)
	var up: Vector3 = (car.global_transform.basis.inverse() * pack.global_transform.basis).y
	print("pose               : immobile=%s   pos voiture=%s" % [still, local.snappedf(0.001)])
	print("  REMIS D'APLOMB   : %s   (%.2f deg de la verticale)" % [
		up.angle_to(Vector3.UP) < deg_to_rad(1.0), rad_to_deg(up.angle_to(Vector3.UP))])
	print("  toujours dedans  : %s" % (local.y > -0.4 and local.y < 2.0))
	await _shot("42_lancer_pose.png")

	# --- les parois hautes de l'habitacle ----------------------------------
	# Le lancer precedent est reste sous la ceinture de caisse. On envoie
	# maintenant le paquet DROIT DANS LE HAUT DU PARE-BRISE, la ou l'habitacle
	# n'avait aucune paroi : il passait par-dessus le tablier, sortait de la
	# caisse, et le filet de securite de prop.gd le reposait sur le siege comme
	# si de rien n'etait. On le jette a la main plutot qu'au clic — ce qui est
	# eprouve ici est la GEOMETRIE, pas le bouton.
	pack.position = Vector3(0.0, 0.95, -0.20)
	pack.throw(Vector3(0.0, 3.0, -2.6))
	var high2: float = pack.position.y
	var fore2: float = pack.position.z
	var jump2 := 0.0
	var prev2 := Vector3.INF
	var was2 := 0.0
	var t2 := 1.6
	while t2 > 0.0:
		await get_tree().process_frame
		var dt2 := get_process_delta_time()
		t2 -= dt2
		high2 = maxf(high2, pack.position.y)
		fore2 = minf(fore2, pack.position.z)
		if prev2.is_finite():
			jump2 = maxf(jump2, pack.position.distance_to(prev2) - was2 * dt2)
		prev2 = pack.position
		was2 = pack.vel.length()
	print("jete au pare-brise : monte a y=%.2f   avance a z=%.2f" % [high2, fore2])
	print("  LA GLACE L'ARRETE: %s   (pavillon a 1.30, bas de baie a -0.92)" %
		(high2 < 1.34 and fore2 > -1.05))
	print("  PAS DE FUITE     : %s   (bond inexplique %.3f m)" % [jump2 < 0.15, jump2])
	print("  retombe a        : %s" % pack.position.snappedf(0.001))

	# --- l'habitacle tient DANS TOUTES LES DIRECTIONS ----------------------
	# Les deux lancers ci-dessus partent droit devant. C'est ce qui a laisse
	# passer la fuite : ils passaient tous les deux pendant que deux lancers sur
	# trois sortaient de la caisse. Un objet ne s'echappe pas par ou on regarde,
	# il s'echappe par les cotes — sous la portiere, au bord du plancher, devant
	# le tablier, la ou les boites de cabin.gd ne se rejoignent pas.
	#
	# On balaie donc l'eventail, y compris derriere et a la verticale : ce qui
	# est verifie n'est plus un point de chute mais un INVARIANT, "le paquet
	# reste dans la coque", et il ne vaut que s'il tient partout.
	await _leak_scan(pack)

	# --- mains vides, la molette redevient le point mort --------------------
	# Embraye d'abord : la boite refuse tout changement pedale relevee, et un
	# refus ressemblerait ici a un clic avale par interaction.gd.
	await _act("clutch", true)
	await _mouse(true, MOUSE_BUTTON_MIDDLE)
	await _mouse(false, MOUSE_BUTTON_MIDDLE)
	await _act("clutch", false)
	print("mains vides        : gear=%d" % car.gear)
	print("  POINT MORT       : %s   (le clic est redescendu au levier)" %
		(car.gear == car.GEAR_N))
	get_tree().quit()


## Jette le paquet dans tout l'eventail des directions et verifie qu'aucune ne
## le sort de l'habitacle.
##
## DEUX MESURES, parce qu'elles ne disent pas la meme chose.
##
## Le DEPASSEMENT dit que la coque de cabin.gd est bien branchee. Elle borne la
## position a chaque sous-pas, donc un objet dehors, meme d'un millimetre, veut
## dire qu'on ne la teste plus — _contain() debranche, un derive de prop.gd qui
## redefinit _resolve() sans elle.
##
## Le BOND INEXPLIQUE dit ce que le joueur, lui, voyait : un deplacement que la
## vitesse ne justifie pas, c'est le filet de securite qui rapatrie l'objet.
## C'est le symptome d'origine — "il disparait et reapparait au meme endroit" —
## et c'est le seul des deux qui se serait vu a l'ecran.
func _leak_scan(pack: Node3D) -> void:
	var lo: Vector3 = car.cabin.HULL_MIN + pack.half
	var hi: Vector3 = car.cabin.HULL_MAX - pack.half
	var from := Vector3(-0.21, 0.93, 0.0)          # le poing (interaction.gd, HOLD_POINT)
	var speed: float = car.interaction.throw_speed
	var tries := 0
	var leaks := 0
	var over := 0.0
	var jump := 0.0
	var worst := Vector3.ZERO

	for yaw in range(-180, 180, 30):
		for pitch in [-60, -30, 0, 30, 60]:
			var a := deg_to_rad(float(yaw))
			var b := deg_to_rad(float(pitch))
			var dir := Vector3(sin(a) * cos(b), sin(b), -cos(a) * cos(b)).normalized()
			pack.position = from
			pack.throw(dir * speed)
			tries += 1
			var out := 0.0
			var prev := Vector3.INF
			var was := 0.0
			var t := 0.6
			while t > 0.0:
				await get_tree().process_frame
				var dt := get_process_delta_time()
				t -= dt
				var q: Vector3 = pack.position
				out = maxf(out, _outside(q, lo, hi))
				if prev.is_finite():
					jump = maxf(jump, q.distance_to(prev) - was * dt)
				prev = q
				was = pack.vel.length()
			if out > 0.001:
				leaks += 1
			if out > over:
				over = out
				worst = dir

	print("balayage de fuite  : %d lancers, tout l'eventail" % tries)
	print("  COQUE ETANCHE    : %s   (%d fuites, depassement maxi %.3f m%s)" % [
		leaks == 0, leaks, over,
		"" if worst == Vector3.ZERO else ", vers %s" % str(worst.snappedf(0.01))])
	print("  AUCUN RAPATRIEMENT: %s   (plus grand bond inexplique : %.3f m)" % [
		jump < 0.15, jump])


## Banc d'essai du mille-pattes : par ou il entre, et comment il tient.
##
## IL EST AVANCE A LA MAIN, pas laisse tourner. `_physics_process` est coupe et
## le banc l'appelle lui-meme avec un pas fixe de 1/60 s. Ce n'est pas un
## raccourci, c'est la seule facon de mesurer la BESTIOLE et pas la machine :
## sous le rendu complet, ce projet tombe a quelques images par seconde, et un
## marcheur qui avance de 42 cm par image ne prouve rien de son adherence — il
## la met en defaut par la taille du pas. Les autres bancs ont paye ce piege
## deux fois (la 5e qui ne converge pas, la main a plat qui s'ouvre a 124°).
##
## Le corollaire compte aussi : les 40 s de promenade ci-dessous sont 40 s de
## bestiole, pas 40 s d'attente. Le banc entier tient en quelques secondes.
func _centipede_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.8).timeout
	var cabin = car.cabin
	var bug: Node3D = cabin.centipede
	if bug == null:
		print("pas de mille-pattes"); get_tree().quit(); return
	bug.rng.seed = 20250825
	bug.set_physics_process(false)
	var dt := 1.0 / 60.0
	# Les boucles ci-dessous tournent SANS rendre la main au moteur : ce que
	# `car.frame_accel` vaut a cet instant vaut donc pour toute la mesure. On la
	# met a zero — sinon un geant qui secoue la caisse au meme moment fige la
	# bestiole (elle se cramponne, c'est le §8) et le banc tourne sans fin. La
	# valeur est rendue a la voiture des la premiere image suivante.
	car.frame_accel = Vector3.ZERO

	# --- 1. Les bouches sont RELEVEES, et elles soufflent du bon cote ----------
	#
	# Le sens ne se lit dans aucune position : une bouche retournee donnerait
	# exactement les memes coordonnees, et la bestiole entrerait dans la planche
	# de bord au lieu d'en sortir. On teste donc le SIGNE, sur les huit.
	print("--- bouches relevees sur le .glb (%d) ---" % cabin.vents.size())
	var into := 0
	for v in cabin.vents:
		var ok: bool = (v["dir"] as Vector3).dot(cabin.EYE_REF - (v["pos"] as Vector3)) > 0.0
		if ok:
			into += 1
		var span: Vector3 = v["span"]
		print("  %-24s pos=%s dir=%s fente=%.0fx%.0f mm  %s" % [
			v["label"], (v["pos"] as Vector3).snappedf(0.001), v["dir"],
			maxf(maxf(span.x, span.y), span.z) * 2000.0,
			(span.x + span.y + span.z - maxf(maxf(span.x, span.y), span.z)) * 2000.0,
			"vers l'habitacle" if ok else "A L'ENVERS"])
	print("  TOUTES VERS L'HABITACLE : %s   (%d/%d)" % [
		into == cabin.vents.size(), into, cabin.vents.size()])

	# L'epaisseur du corps n'est pas un choix, c'est ce que laissent les lames.
	var s0: MeshInstance3D = cabin.find_child("DASH_SideVentSlat_L0", true, false)
	var s1: MeshInstance3D = cabin.find_child("DASH_SideVentSlat_L1", true, false)
	if s0 != null and s1 != null:
		var gap: float = _panel_box(s1).position.y - _panel_box(s0).end.y
		print("  jour entre deux lames : %.1f mm   corps : %.1f mm   IL PASSE : %s" % [
			gap * 1000.0, bug.BODY_T * 1000.0, bug.BODY_T <= gap])

	# --- 2. Vitres fermees : il n'entre que par les grilles --------------------
	var draws := 200
	var by_window := 0
	for i in draws:
		bug.rewind()
		bug.enter_now()
		if String(bug.entry_label).begins_with("vitre"):
			by_window += 1
	print("vitres fermees      : %d entrees, dont %d par une vitre" % [draws, by_window])
	print("  QUE PAR LES GRILLES : %s" % (by_window == 0))

	# --- 3. Vitre du conducteur baissee : c'est par la qu'il passe -------------
	#
	# La vitre est ouverte par le VRAI mecanisme (crank + wind, window.gd), pas
	# en ecrivant `open` : ce qui est en jeu ici, c'est que la bestiole lise la
	# course reelle de la glace. Le geste souris->manivelle, lui, est prouve par
	# `-- windowtest` et n'a pas a l'etre deux fois.
	var win = cabin.windows[0]
	win.crank(8.0)
	for i in 200:
		win.wind(dt)
	var top: float = win.glass_box.end.y - win.travel * win.open
	print("vitre conducteur    : ouverture=%.2f   haut de glace y=%.3f (fermee %.3f)" % [
		win.open, top, win.glass_box.end.y])

	by_window = 0
	for i in draws:
		bug.rewind()
		bug.enter_now()
		if String(bug.entry_label).begins_with("vitre"):
			by_window += 1
	print("  %d entrees, dont %d par la vitre (%.0f %%)" % [
		draws, by_window, 100.0 * float(by_window) / float(draws)])
	print("  LA VITRE L'EMPORTE  : %s   (elle pese plus que les huit grilles)" % (
		by_window > draws / 2))

	# --- 4. Il SORT du trou, il n'apparait pas dedans --------------------------
	#
	# C'est ce que la trace semee a l'avance doit donner : a l'instant de
	# l'entree, le corps est encore tout entier derriere la bouche, et il en est
	# paye anneau par anneau. Une bestiole qui apparaitrait d'un bloc dans
	# l'habitacle ne serait pas entree, elle aurait ete posee.
	var vent: Dictionary = cabin.vents[0]
	for v in cabin.vents:
		if v["label"] == "grille de degivrage":
			vent = v
	var mouth: Vector3 = vent["pos"]
	var mdir: Vector3 = vent["dir"]
	bug.rewind()
	bug.enter_by(vent)
	# ETRE ENCORE DEDANS, c'est etre DANS LA GARNITURE — pas "de l'autre cote du
	# plan de la bouche". Le degivrage souffle vers le HAUT : son plan coupe
	# l'habitacle en deux, et tout ce qui est plus bas que la planche de bord
	# serait compte comme "pas encore sorti", y compris le plancher. Un anneau
	# est dans la tole ou il n'y est pas, et les boites le disent.
	var buried0 := _buried(cabin, bug.segment_points())
	var tail0: float = (mouth - bug.segment_points()[bug.SEGMENTS - 1]).dot(mdir)
	print("entre par           : %s, a %s" % [bug.entry_label, mouth.snappedf(0.001)])
	print("  a l'instant zero  : %d anneaux sur %d encore dans la planche" % [
		buried0, bug.SEGMENTS])
	print("  QUEUE DANS LE TROU: %s   (%.0f mm derriere la bouche)" % [
		tail0 > bug.BODY_LEN * 0.9, tail0 * 1000.0])

	var steps_in := 0
	while bug.state != 2 and steps_in < 600:      # 2 = ROAMING
		bug._physics_process(dt)
		steps_in += 1
	print("  emerge apres      : %.0f mm, puis il se raccroche" % (bug._emerged * 1000.0))
	var half_out := -1
	var guard := 0
	while bug.walked < 0.40 and guard < 3000:
		guard += 1
		bug._physics_process(dt)
		if half_out < 0 and _buried(cabin, bug.segment_points()) <= bug.SEGMENTS / 2:
			half_out = 1
			print("  a mi-corps sorti  : la tete a fait %.0f mm" % (bug.walked * 1000.0))
	print("  apres 40 cm       : %d anneaux dans la planche" % [
		_buried(cabin, bug.segment_points())])
	print("  IL EST TOUT SORTI : %s" % (_buried(cabin, bug.segment_points()) == 0))

	# --- 5. Quarante secondes de promenade ------------------------------------
	#
	# Quatre choses a la fois, parce qu'elles se tiennent.
	#
	# IL NE FLOTTE JAMAIS. `clearance()` est la distance a la surface la plus
	# proche, et elle ne doit jamais depasser RIDE : au-dela il marche sur rien.
	# Elle descend en revanche legitimement a zero, la ou plusieurs epaisseurs de
	# tole se superposent : il est pose sur l'une tout en etant DANS l'autre. Ce
	# n'est donc pas un plancher a exiger.
	#
	# IL NE S'ENFONCE JAMAIS DANS LA TOLE. La mesure est posee AU MAILLAGE, pas a
	# la grille de collision, et c'est ce qui la rend non circulaire : la grille
	# est ce qui a place la bestiole. L'ancienne version interrogeait `solids`,
	# c'est-a-dire des boites saisies a la main qui ne correspondaient pas au
	# modele — elle repondait juste par accident.
	#
	# IL NE SORT JAMAIS DE LA COQUE, et LE CORPS NE SE DECOUD PAS.
	var lo := INF
	var hi := -INF
	var out_hull := -INF
	var sunk := 0.0
	var gap_max := 0.0
	var faces := {}
	var start: float = bug.walked
	var seen := AABB(bug.head_pos, Vector3.ZERO)
	var float_streak := 0
	var float_max := 0
	var sunk_streak := 0
	var sunk_max := 0
	for i in int(40.0 / dt):
		bug._physics_process(dt)
		var c: float = bug.clearance()
		lo = minf(lo, c)
		hi = maxf(hi, c)
		float_streak = float_streak + 1 if c > bug.RIDE + 0.001 else 0
		float_max = maxi(float_max, float_streak)
		out_hull = maxf(out_hull, _outside(bug.head_pos, cabin.HULL_MIN, cabin.HULL_MAX))
		# La tete fait 27 x 6 x 21 mm et le ventre est porte a RIDE (5 mm) : sa
		# demi-hauteur de 3 mm ne doit toucher aucun triangle. Si elle en touche
		# un, il est dans la piece, pas dessus.
		var piece: String = _mesh_probe().hits_box(bug.head_pos, Vector3(0.0135, 0.003, 0.0105))
		if piece != "":
			sunk += 1.0
			sunk_streak += 1
		else:
			sunk_streak = 0
		sunk_max = maxi(sunk_max, sunk_streak)
		var pts: Array[Vector3] = bug.segment_points()
		for k in range(1, pts.size()):
			gap_max = maxf(gap_max, pts[k - 1].distance_to(pts[k]))
		faces[(bug.head_nrm as Vector3).snappedf(0.9)] = true
		seen = seen.expand(bug.head_pos)
	# L'ETENDUE plutot que le nombre de normales : une bestiole qui tourne en
	# rond sur le plancher visite exactement autant de normales qu'une qui fait
	# le tour de l'habitacle, et le nombre de normales ne les distingue pas.
	# C'est le VOLUME visite qui dit s'il se promene ou s'il pietine.
	print("40 s de promenade   : %.2f m parcourus, %d orientations de tole" % [
		bug.walked - start, faces.size()])
	print("  etendue visitee   : %.2f x %.2f x %.2f m   (habitacle %.2f x %.2f x %.2f)" % [
		seen.size.x, seen.size.y, seen.size.z,
		cabin.HULL_MAX.x - cabin.HULL_MIN.x, cabin.HULL_MAX.y - cabin.HULL_MIN.y,
		cabin.HULL_MAX.z - cabin.HULL_MIN.z])
	print("  IL SE PROMENE     : %s   (il ne pietine pas un coin)" % (
		seen.size.x > 0.8 and seen.size.z > 0.8))
	print("  distance a la tole : %.1f a %.1f mm   (assise sur %.1f)" % [
		lo * 1000.0, hi * 1000.0, bug.RIDE * 1000.0])
	# Il ENJAMBE : depuis que le recollage ne teleporte plus (il APPROCHE la
	# surface d'apres, au pas), la tete franchit les creux portee par l'elan,
	# comme la vraie bestiole tend son avant-corps par-dessus un vide. Ce qu'on
	# exige n'est donc plus "jamais au-dela de l'assise" mais "jamais EN L'AIR
	# longtemps" : un quart de seconde d'enjambee, pas un vol plane.
	print("  IL NE PLANE PAS   : %s   (enjambee maxi %.2f s, pointe a %.1f mm)" % [
		float_max <= 15, float_max * dt, hi * 1000.0])
	# Et il FROLE sans s'installer : sur les pieces bombees (facade de console,
	# contre-portes) la grille de collision et le maillage se contredisent de
	# quelques millimetres — un frolement d'un dixieme de seconde ne se voit
	# pas, un sejour si. Le compte total reste imprime : s'il enfle, c'est la
	# grille qu'il faut recuire, pas la marche qu'il faut brider.
	print("  PAS INSTALLE DANS LA TOLE : %s   (%d images frolees sur %d, sejour maxi %.2f s)" % [
		sunk_max <= 30, int(sunk), int(40.0 / dt), sunk_max * dt])
	print("  JAMAIS HORS COQUE : %s   (depassement maxi %.1f mm)" % [
		out_hull <= 0.0, maxf(out_hull, 0.0) * 1000.0])
	print("  ecart entre anneaux : %.1f mm maxi   (espacement %.1f)" % [
		gap_max * 1000.0, bug.SEG_SPACING * 1000.0])
	print("  LE CORPS TIENT    : %s" % (gap_max <= bug.SEG_SPACING + 0.0005))

	# --- 6. L'ANGLE SAILLANT --------------------------------------------------
	#
	# Le coeur de la marche. Pose sur le dessus de la planche de bord, cap vers
	# le conducteur, il arrive au nez de la planche : il doit BASCULER par-dessus
	# l'arete et continuer sur la face verticale, pas continuer tout droit dans
	# le vide ni s'arreter au bord. Rien dans le code ne parle d'arete — c'est la
	# regle generale qui doit produire ca, sinon elle ne vaut rien.
	bug.head_pos = Vector3(0.0, 0.950, -0.62)
	bug.head_nrm = Vector3.UP
	bug._dir = Vector3.BACK                       # +z : vers le conducteur
	bug._goal = Vector3(0.0, 0.60, -0.50)         # en bas de la face verticale
	bug._running = true
	bug._wait = 99.0
	# On guette l'INSTANT ou la normale bascule, on ne relit pas l'etat final :
	# il continue sa route ensuite et finit sur le dessus de console, normale en
	# l'air, ce qui donnerait "il n'a pas bascule" alors qu'il vient d'y passer.
	# Premiere version du banc, premier faux negatif.
	var y0: float = bug.head_pos.y
	var tipped := Vector3.ZERO
	var tip_y := 0.0
	var tip_at := 0.0
	for i in int(1.2 / dt):
		bug._physics_process(dt)
		if tipped == Vector3.ZERO and absf(bug.head_nrm.y) < 0.4:
			tipped = bug.head_nrm
			tip_y = bug.head_pos.y
			tip_at = bug.head_pos.z
	print("le nez de la planche: normale (0, 1, 0) -> %s au bord z=%.3f" % [
		tipped.snappedf(0.01), tip_at])
	print("  IL A BASCULE      : %s   (a l'arete, %.0f mm sous le dessus)" % [
		tipped != Vector3.ZERO and tipped.z > 0.9, (y0 - tip_y) * 1000.0])
	print("  ET IL CONTINUE    : %s   (%.0f mm plus bas, ventre a %.1f mm)" % [
		bug.head_pos.y < y0 - 0.10, (y0 - bug.head_pos.y) * 1000.0,
		bug.clearance() * 1000.0])

	# --- 7. Fige, il ne pedale pas dans le vide -------------------------------
	bug._running = false
	bug._wait = 99.0
	var phase0: float = bug._phase
	var walked0: float = bug.walked
	for i in int(1.0 / dt):
		bug._physics_process(dt)
	print("fige 1 s            : pattes %+.4f   distance %+.4f m" % [
		bug._phase - phase0, bug.walked - walked0])
	print("  LES PATTES SE TAISENT : %s   (elles suivent la distance, pas le temps)" % (
		absf(bug._phase - phase0) < 0.0001))

	# --- 8. Coup de frein : il se cramponne -----------------------------------
	#
	# Il ne glisse pas — s'agripper est tout son metier — mais il arrete de
	# courir, ce qui est ce que fait une bestiole quand le monde bouge sous elle.
	bug._running = true
	bug._wait = 0.5
	walked0 = bug.walked
	for i in int(0.5 / dt):
		bug._physics_process(dt)
	var free: float = bug.walked - walked0

	car.frame_accel = Vector3(0.0, 0.0, 18.0)     # freinage pedale : 17 m/s^2
	bug._running = true
	bug._wait = 0.5
	walked0 = bug.walked
	for i in int(0.5 / dt):
		bug._physics_process(dt)
	var braked: float = bug.walked - walked0
	car.frame_accel = Vector3.ZERO
	print("0,5 s de marche     : libre %.3f m   sous 18 m/s^2 %.3f m" % [free, braked])
	print("  IL SE CRAMPONNE   : %s" % (braked < free * 0.25))

	# --- 9. Laisse tourner : il part TOUT SEUL --------------------------------
	#
	# Tout ce qui precede l'a avance a la main. Il reste a prouver la chaine
	# complete, moteur en marche : le compteur descend, `_choose_entry` tire une
	# ouverture, et il entre sans qu'on le lui demande. Sans ce dernier point, un
	# banc entierement vert pourrait couvrir une bestiole que rien ne declenche.
	bug.set_physics_process(true)
	bug.rewind()
	bug._wait = 0.5
	var came: bool = await _until(func(): return bug.state != 0, 5.0)
	print("laisse tourner      : il part seul=%s   par %s" % [came, bug.entry_label])

	# --- 10. Ce qu'on voit ----------------------------------------------------
	bug.rewind()
	bug.enter_by(vent)
	_env.ambient_light_energy = 1.6
	await _aim_at(Vector3(0.0, 0.95, -0.80))
	await get_tree().create_timer(0.5).timeout
	await _shot("20_millepattes_sort.png")
	await get_tree().create_timer(2.5).timeout
	await _shot("21_millepattes_planche.png")

	# Un gros plan, parce qu'a un metre et par 27 cm de long il ne fait que 13 %
	# de la largeur de l'image : de quoi le VOIR, pas de quoi juger la bete. On
	# resserre le champ plutot que de le grossir — c'est la meme bestiole.
	bug.set_physics_process(false)
	bug.head_pos = Vector3(-0.20, 0.950, -0.78)
	bug.head_nrm = Vector3.UP
	bug._dir = Vector3(1.0, 0.0, 0.35).normalized()
	bug._running = true
	bug._wait = 99.0
	bug._goal = Vector3(0.60, 0.95, -0.70)
	for i in int(0.7 / dt):
		bug._physics_process(dt)
	car.cam.fov = 26.0
	await _aim_at(bug.head_pos)
	await get_tree().create_timer(0.4).timeout
	await _shot("22_millepattes_gros_plan.png")
	get_tree().quit()


## Le geste qui sort le mille-pattes de la voiture : l'attraper, ouvrir la
## vitre, le jeter par le jour au-dessus de la glace. Trois verites a etablir,
## chacune contre sa tentation de tricher : vitre FERMEE il retombe dedans (le
## jour n'est pas un laissez-passer permanent), vitre OUVERTE il sort par le
## jour (et pas "des qu'il touche la zone de la vitre"), et trop BAS il cogne
## la glace reelle meme vitre ouverte (le jour est au-dessus de la glace, pas a
## sa place).
func _bugthrow_test() -> void:
	await get_tree().create_timer(0.8).timeout
	var cabin = car.cabin
	var bug: Node3D = cabin.centipede
	if bug == null:
		print("pas de mille-pattes"); get_tree().quit(); return
	bug.rng.seed = 20260826
	bug.set_physics_process(false)
	var dt := 1.0 / 60.0
	car.frame_accel = Vector3.ZERO
	var win = cabin.windows[0]
	var hand := Vector3(-0.30, 0.95, 0.05)
	# Vise le jour au-dessus de la glace baissee : mi-hauteur de l'ouverture
	# quand elle existe, la meme fenetre de tir quand la vitre est fermee.
	var gap_y: float = win.glass_box.end.y - 0.015
	var aim := Vector3(win.glass_box.get_center().x, gap_y, win.glass_box.get_center().z)

	# --- 1. Vitre fermee : il rebondit dedans ---------------------------------
	var r: float = _bug_grab(bug)
	print("attrape             : etat CARRIED=%s   rayon vise=%.0f mm" % [
		bug.state == 3, r * 1000.0])
	bug.transform = Transform3D(Basis(), hand)
	bug.throw((aim - hand).normalized() * 4.5)
	var flew: bool = bug.state == 4
	for i in 300:
		bug._physics_process(dt)
	print("vitre fermee        : il a vole=%s   retombe dedans=%s   tete=%s" % [
		flew, bug.state == 2, bug.head_pos.snappedf(0.01)])
	print("  PAS DE PASSE-MURAILLE : %s" % (bug.state == 2 and bug.visible))

	# --- 2. Vitre ENTROUVERTE : il sort par le jour, et rien que par lui ------
	# Un peu plus de la moitie de la course : 16 cm de jour — il passe large,
	# et la glace tient encore le bas du cadre, ce qui donne au §3 une vraie
	# vitre a cogner.
	win.crank(4.0)
	for i in 200:
		win.wind(dt)
	var gap: float = win.travel * win.open
	print("vitre conducteur    : ouverture=%.2f   jour=%.0f mm (mini %.0f)" % [
		win.open, gap * 1000.0, bug.THROW_GAP * 1000.0])
	aim.y = win.glass_box.end.y - gap * 0.35
	# Le lancer est balistique : sur 45 cm a 4,5 m/s, la pesanteur mange 5 cm.
	# On les rend au viseur, comme le fait un joueur qui a rate son premier jet.
	var tof: float = (aim - hand).length() / 4.5
	aim.y += 0.5 * 9.8 * tof * tof
	_bug_grab(bug)
	bug.transform = Transform3D(Basis(), hand)
	bug.throw((aim - hand).normalized() * 4.5)
	for i in 300:
		bug._physics_process(dt)
		if bug.state == 0:
			break
	print("vitre ouverte       : dehors=%s   invisible=%s   il reviendra dans %.0f s" % [
		bug.state == 0, not bug.visible, bug._wait])
	print("  IL EST SORTI      : %s" % (bug.state == 0 and not bug.visible))

	# --- 3. Vitre ouverte mais lancer trop bas : la glace le renvoie ----------
	var low := Vector3(aim.x, win.glass_box.end.y - gap - 0.03, aim.z)
	_bug_grab(bug)
	bug.transform = Transform3D(Basis(), hand)
	bug.throw((low - hand).normalized() * 4.5)
	for i in 300:
		bug._physics_process(dt)
	print("lancer sous le jour : retombe dedans=%s   tete=%s" % [
		bug.state == 2, bug.head_pos.snappedf(0.01)])
	print("  LA GLACE EST REELLE : %s" % (bug.state == 2 and absf(bug.head_pos.x) < 0.75))
	get_tree().quit()


## Met la bestiole en main comme interaction.gd le ferait : posee quelque part,
## en promenade, puis hold(). Rend le rayon de visee qu'elle offrait AVANT la
## prise — en main il retombe a zero, on ne re-attrape pas ce qu'on tient.
func _bug_grab(bug) -> float:
	bug.rewind()
	bug.head_pos = Vector3(0.0, 0.95, -0.70)
	bug.head_nrm = Vector3.UP
	bug._dir = Vector3.BACK
	bug._seed_trail()
	bug.state = 2                      # ROAMING
	bug.visible = true
	bug._place_segments()
	var r: float = bug.grab_radius()
	bug.hold()
	return r


## Combien d'anneaux sont encore DANS la tole — planche de bord, garniture,
## mobilier. C'est ce qui dit qu'il sort d'un trou au lieu d'y apparaitre, et ca
## vaut pour les huit bouches sans avoir a savoir de quel cote elles soufflent.
##
## LA QUESTION EST POSEE AU MAILLAGE, pas a la grille de collision. C'est ce qui
## la rend non circulaire : la grille est ce qui a PLACE la bestiole, lui
## demander ensuite si elle est bien placee ne prouverait rien. Le .glb, lui,
## n'a pas participe — et c'est lui que le joueur regarde.
##
## L'ancienne version interrogeait `solids + crawl_solids`, c'est-a-dire des
## boites saisies a la main qui, elles, ne correspondaient pas au modele : elle
## repondait juste par accident.
func _buried(_cabin, pts: Array[Vector3]) -> int:
	var mesh = _mesh_probe()
	# Un anneau : 22 mm de large, 6 mm d'epaisseur, 16 mm de long (centipede.gd).
	var half := Vector3(0.011, 0.003, 0.008)
	var n := 0
	for p in pts:
		if mesh.hits_box(p, half) != "":
			n += 1
	return n


## Le maillage de l'habitacle, charge une seule fois pour les bancs.
##
## 108 000 triangles et 400 ms : c'est cher pour le jeu, c'est gratuit pour un
## banc, et c'est le seul juge qui n'ait pas participe a ce qu'il juge.
func _mesh_probe():
	if _mesh_cache == null:
		_mesh_cache = MeshProbeScript.new()
		_mesh_cache.load_glb("res://assets/models/civic_interior.glb")
	return _mesh_cache


## De combien un point sort de la boite [lo, hi]. Negatif ou nul : il est dedans.
func _outside(q: Vector3, lo: Vector3, hi: Vector3) -> float:
	return maxf(maxf(maxf(lo.x - q.x, q.x - hi.x), maxf(lo.y - q.y, q.y - hi.y)),
		maxf(lo.z - q.z, q.z - hi.z))


## Oriente la tete vers un point exprime dans l'espace de la voiture. Deux
## passes : la camera se decale quand on tourne la tete, donc le premier calcul
## vise a cote.
func _aim_at(point: Vector3) -> void:
	for i in 2:
		var dir: Vector3 = (point - car.head.position).normalized()
		car.head.rotation = Vector3(
			asin(clampf(dir.y, -1.0, 1.0)), atan2(-dir.x, -dir.z), 0.0)
		await get_tree().create_timer(0.35).timeout


func _click() -> void:
	await _mouse(true)
	await _mouse(false)
	await get_tree().create_timer(0.25).timeout


func _mouse(pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


## Des crans de molette, envoyes comme la souris les envoie : un appui suivi
## d'un relachement, cran par cran. Un seul evenement "pressed" tenu ne
## ressemblerait a rien de ce que produit une vraie molette, et la manivelle ne
## lit QUE les appuis.
func _wheel(notches: int, button := MOUSE_BUTTON_WHEEL_DOWN) -> void:
	for i in notches:
		await _mouse(true, button)
		await _mouse(false, button)


## Une action du projet, poussee comme si la touche avait ete pressee. On ecrit
## l'etat ET on envoie l'evenement : interaction.gd lit les deux, l'evenement
## pour basculer d'etat et l'etat pour savoir si le bouton est toujours tenu.
func _act(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


## Attend qu'une condition devienne vraie, plutot que de dormir une duree fixe.
##
## Un banc qui dort ne mesure pas le jeu, il mesure la machine : a 6 images par
## seconde les deux images d'attente de _mouse() durent deja 0,33 s, et tout ce
## qui devait etre observe entre-temps est passe. C'est comme ca que ce banc a
## commence par annoncer un eclair de bouche mort alors qu'il fonctionnait.
func _until(check: Callable, timeout := 3.0) -> bool:
	var left := timeout
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
		if check.call():
			return true
	return false


## Banc d'essai du revolver : le ramasser, le lever, tirer six coups, recharger,
## le reposer. Ce qu'on verifie surtout, c'est que la bouche pointe VRAIMENT ou
## on regarde — une arme levee qui vise a cote se voit tout de suite.
func _revolver_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(1.2).timeout
	var inter = car.interaction
	var gun: Node3D = null
	for obj in inter.grabbables:
		if obj.name == "Revolver":
			gun = obj
	if gun == null:
		print("REVOLVER ABSENT des ramassables")
		get_tree().quit()
		return

	var local: Vector3 = car.to_local(gun.global_position)
	print("revolver trouve    : pos voiture=%s" % local.snappedf(0.001))
	print("  POSE SUR L'ASSISE: %s" % (local.y < 0.60))
	print("  demi-cotes       : %s" % gun.half.snappedf(0.001))

	# Etats de interaction.gd, dans l'ordre de son enum.
	var HELD := 2
	var RAISED := 7

	var aimed := false
	for i in 3:
		await _aim_at(local)
		aimed = inter.target == gun
		if aimed:
			break
	print("  VISE             : %s" % aimed)
	await _shot("20_revolver_pose.png")

	await _click()
	var took: bool = await _until(func(): return inter.held == gun)
	print("  PRIS EN MAIN     : %s   (fige=%s)" % [took, gun.held])
	await _shot("21_revolver_en_main.png")
	if not took:
		print("ABANDON : rien en main, la suite n'aurait aucun sens")
		get_tree().quit()
		return

	# --- la prise est-elle REPRODUCTIBLE ? --------------------------------
	# On repose l'arme et on la reprend, en variant le regard a chaque fois :
	# c'est ce transitoire-la dont la pose dependait quand l'arme lisait
	# l'orientation du poing qu'elle orientait elle-meme. Bouche vers le ciel a
	# chaque coup, ou rien ne va.
	var looks := [Vector3(0.90, 0.75, 0.30), Vector3(-0.20, 1.30, -0.90),
		Vector3(0.50, 0.55, 0.80)]
	var worst := 0.0
	for i in looks.size() + 1:
		await get_tree().create_timer(0.7).timeout      # la pose se stabilise
		var m: Vector3 = (gun.global_transform.basis * gun.aim_axis()).normalized()
		var off := rad_to_deg(m.angle_to(Vector3.UP))
		worst = maxf(worst, off)
		print("  prise %d : bouche a %.1f deg de la verticale" % [i + 1, off])
		if i >= looks.size():
			break
		await _aim_at(Vector3(-0.20, 0.952, -0.84))     # reposer sur la planche
		await _mouse(true)
		await _until(func(): return inter.ghost_visible())
		await _mouse(false)
		await _until(func(): return inter.held == null, 4.0)
		await _aim_at(looks[i])                          # detour du regard
		await _aim_at(car.to_local(gun.global_position))
		await _click()
		await _until(func(): return inter.held == gun)
	print("  CANON VERS LE HAUT: %s   (pire ecart %.1f deg)" % [worst < 8.0, worst])

	# --- on leve ----------------------------------------------------------
	await _aim_at(Vector3(1.20, 1.05, -0.60))          # par la vitre passager
	await _act("aim_weapon", true)
	var up: bool = await _until(func(): return inter._state == RAISED)
	print("  ARME LEVEE       : %s" % up)
	await _shot("22_revolver_leve.png")

	# Le bras met un instant a monter : mesurer avant qu'il soit arrive donnerait
	# une distance oeil-poing prise en cours de route.
	await get_tree().create_timer(0.8).timeout

	# La bouche suit-elle le regard ? Comparaison en repere MONDE.
	var bore: Vector3 = (gun.global_transform.basis * gun.aim_axis()).normalized()
	var look: Vector3 = -car.cam.global_transform.basis.z
	print("  ECART BOUCHE/VISEE: %.2f deg" % rad_to_deg(bore.angle_to(look)))
	# ... et l'arme est-elle a l'endroit ? Son dessus doit regarder le ciel :
	# une arme parfaitement pointee mais couchee sur le flanc passe le test
	# ci-dessus sans broncher.
	var top: Vector3 = (gun.global_transform.basis * gun.up_axis()).normalized()
	print("  ROULIS           : %.2f deg  (dessus vs verticale)" %
		rad_to_deg(top.angle_to(Vector3.UP)))
	# Distance oeil-poing et oeil-bouche : c'est ce qui fait le cadrage.
	var eye: Vector3 = car.cam.global_position
	print("  poing a %.2f m, bouche a %.2f m de l'oeil" % [
		eye.distance_to(car.driver.hand_right().global_position),
		eye.distance_to(gun.global_transform * gun._muzzle)])

	# --- six coups --------------------------------------------------------
	print("%.0f ips" % Engine.get_frames_per_second())
	var flashes := 0
	var kicks := 0
	for i in 6:
		var before: int = gun.rounds
		# Sommets remis a zero AVANT le clic : le chien tombe 0,13 s apres, et
		# les deux images d'attente de _mouse() peuvent deja durer plus.
		gun.take_peaks()
		await _mouse(true)
		await _mouse(false)
		var gone: bool = await _until(func(): return gun.rounds == before - 1)
		if i == 0:
			await _shot("23_revolver_tir.png")
		var peaks: Vector2 = gun.take_peaks()
		if peaks.y > 1.0:
			flashes += 1
		if peaks.x > 0.5:
			kicks += 1
		print("  coup %d : parti=%s  %d->%d  recul %.2f  eclair %.1f" % [
			i + 1, gone, before, gun.rounds, peaks.x, peaks.y])
		await _until(func(): return not gun.busy())
	print("  BARILLET VIDE    : %s   (%d/6)" % [gun.rounds == 0, gun.rounds])
	print("  SIX ECLAIRS      : %s   (%d/6)" % [flashes == 6, flashes])
	print("  SIX RECULS       : %s   (%d/6)" % [kicks == 6, kicks])

	# Chambre vide : le chien tombe, le barillet tourne, rien ne part.
	gun.take_peaks()
	await _click()
	await _until(func(): return not gun.busy())
	var dry: Vector2 = gun.take_peaks()
	print("  RIEN SOUS ZERO   : %s   (%d/6, eclair %.1f)" % [
		gun.rounds == 0 and dry.y < 0.01, gun.rounds, dry.y])

	# --- rechargement -----------------------------------------------------
	await _act("reload", true)
	await _act("reload", false)
	var opened: bool = await _until(func(): return gun.open_amount() > 0.9)
	print("  CANON OUVERT     : %s" % opened)
	await _shot("24_revolver_ouvert.png")
	var full: bool = await _until(
		func(): return gun.rounds == 6 and not gun.reloading(), 4.0)
	print("  SIX EN CHAMBRE   : %s   (%d/6)" % [full, gun.rounds])

	# --- on rabaisse et on repose ----------------------------------------
	await _act("aim_weapon", false)
	var lowered: bool = await _until(func(): return inter._state == HELD)
	print("  ARME BAISSEE     : %s" % lowered)

	await _aim_at(Vector3(-0.20, 0.952, -0.84))        # la planche de bord
	await _mouse(true)
	var ghost: bool = await _until(func(): return inter.ghost_visible())
	print("  FANTOME NON VIDE : %s   (surface %s)" % [ghost, inter.has_surface()])
	await _shot("25_revolver_fantome.png")
	await _mouse(false)
	var placed: bool = await _until(func(): return inter.held == null, 4.0)
	print("  REPOSE           : %s   pos=%s" % [
		placed, car.to_local(gun.global_position).snappedf(0.001)])
	await _shot("26_revolver_repose.png")
	get_tree().quit()


## Banc d'essai du volant : l'ENCHAINEMENT DE PRISES.
##
## Ce qu'on verifie n'est pas que les mains bougent — ca se voit — mais les
## trois choses sans lesquelles un braquage complet ne tient pas debout :
##
##  * il reste TOUJOURS au moins une main sur la jante. Deux mains en l'air en
##    meme temps, c'est un volant qui tourne tout seul ;
##  * aucune main ne va chercher plus loin que le bras (epaule -> poignet contre
##    `arm_span`). Le modele n'ayant plus de bras, rien ne le montrerait a
##    l'ecran : l'avant-bras invisible traverserait le buste en silence ;
##  * les deux mains ne se traversent pas en se croisant.
##
## Plus le releve des prises elles-memes : a quel angle de volant chacune lache,
## et ou elle se repose.
func _wheel_test() -> void:
	await get_tree().create_timer(0.6).timeout
	var drv = car.driver
	# En roulant : sans vitesse le volant ne se rappelle pas au centre, et on ne
	# verrait jamais les prises du RETOUR, qui sont la moitie du sujet.
	car.speed = 12.0
	car.gear = 4
	print("bras %.3f m   butee de volant %.0f deg   prise : tirer %.0f deg, pousser %.0f deg" % [
		drv.arm_span(), DriverScript.WHEEL_MAX_ANGLE,
		DriverScript.GRIP_PULL, DriverScript.GRIP_PUSH])

	# --- profil de portee --------------------------------------------------
	# Ou peut aller une main sans que le bras ait a s'allonger. C'est ce tableau
	# qui cale GRIP_PULL et GRIP_PUSH : la portee au repos (10 h 10) est deja de
	# 0,65 m pour 0,58 m de bras — position de conduite d'une Civic dont le siege
	# du modele est 15 cm trop loin (voir le README). Ce qu'on surveille n'est
	# donc pas une portee absolue, c'est de combien la prise EMPIRE en s'ecartant.
	var line := "  angle    "
	var g := "  gauche   "
	var d := "  droite   "
	for k in 11:
		var a := -125.0 + 25.0 * k
		line += "%6.0f" % a
		g += "%6.3f" % drv.reach_at(false, a)
		d += "%6.3f" % drv.reach_at(true, a)
	print("\nportee epaule -> poignet selon l'angle de la main (m) :")
	print(line)
	print(g)
	print(d)

	# --- un virage ordinaire ne fait rien lacher ---------------------------
	# Le defaut inverse de celui qu'on corrige : des mains qui se repositionnent
	# pour une correction de trajectoire. On ne lache pas le volant a 50 degres.
	print("\n-- virage de route, volant a ~50 deg --")
	car.speed = 12.0
	car.debug_full_steer = 0.18
	await _wheel_watch(3.0, "virage ordinaire", false)
	car.debug_full_steer = 0.0
	car.steer = 0.0
	await get_tree().create_timer(1.2).timeout

	for i in 2:
		var action := "steer_left" if i == 0 else "steer_right"
		print("\n-- %s a fond --" % action)
		car.speed = 12.0
		await _act(action, true)
		await _wheel_watch(2.4, "braquage", i == 0)
		await _act(action, false)
		car.speed = 12.0       # le rappel du volant depend de la vitesse
		await _wheel_watch(2.6, "retour au centre", false)
		# Le volant a fini de rentrer : les mains doivent etre revenues a 10 h 10.
		# Ce n'est pas un rangement — il n'y en a plus — c'est le glissement qui
		# les y a ramenees pendant que la jante filait dessous.
		car.speed = 12.0
		await get_tree().create_timer(2.0).timeout
		print("  repos             : volant %+.0f deg   mains G %+.0f  D %+.0f deg   A 10 H 10: %s" % [
			car.steer * DriverScript.WHEEL_MAX_ANGLE,
			drv.grip_angle(false), drv.grip_angle(true),
			maxf(absf(drv.grip_angle(false)), absf(drv.grip_angle(true))) < 25.0])

		# ... ET ELLES N'Y BOUGENT PLUS. Volant immobile, une main reste agrippee
		# ou elle tient : c'est le defaut inverse de celui qu'on corrige, et il ne
		# se voit que sur la duree. On braque a la main, on laisse tout se poser,
		# puis on regarde si quelque chose bouge encore.
		car.steer = 0.6 if i == 0 else -0.6
		car.speed = 0.0            # a l'arret, aucun rappel : le volant reste la
		await get_tree().create_timer(1.5).timeout
		var still_l: float = drv.grip_angle(false)
		var still_r: float = drv.grip_angle(true)
		await get_tree().create_timer(2.5).timeout
		print("  volant fige a %+.0f  : les mains bougent de G %.1f  D %.1f deg   AGRIPPEES: %s" % [
			car.steer * DriverScript.WHEEL_MAX_ANGLE,
			absf(drv.grip_angle(false) - still_l), absf(drv.grip_angle(true) - still_r),
			maxf(absf(drv.grip_angle(false) - still_l),
				absf(drv.grip_angle(true) - still_r)) < 1.0])
		car.steer = 0.0

	# --- le volant qui rentre tout seul ------------------------------------
	# On braque, on LACHE LA TOUCHE, et le rappel ramene la jante. Le conducteur
	# ne la ramene pas : il desserre et la laisse filer sous ses paumes. Ce qui
	# le prouve, c'est l'ecart entre ce que parcourt la JANTE et ce que
	# parcourent les MAINS pendant ce temps-la.
	print("\n-- volant rendu : la jante file sous les paumes --")
	car.speed = 16.0
	await _act("steer_left", true)
	await get_tree().create_timer(1.4).timeout
	await _act("steer_left", false)
	car.speed = 16.0
	var rim := 0.0
	var hands := 0.0
	var close_min := 1.0
	var slipping := 0
	var frames := 0
	var was_wheel: float = car.steer * DriverScript.WHEEL_MAX_ANGLE
	var was_l: float = drv.grip_angle(false)
	var was_r: float = drv.grip_angle(true)
	while frames < 150 and absf(car.steer) > 0.02:
		await get_tree().process_frame
		frames += 1
		car.speed = 16.0
		var now: float = car.steer * DriverScript.WHEEL_MAX_ANGLE
		rim += absf(now - was_wheel)
		hands += maxf(absf(drv.grip_angle(false) - was_l),
			absf(drv.grip_angle(true) - was_r))
		was_wheel = now
		was_l = drv.grip_angle(false)
		was_r = drv.grip_angle(true)
		close_min = minf(close_min, minf(drv.grip_close(false), drv.grip_close(true)))
		if car.wheel_returning:
			slipping += 1
	print("  jante parcourue   : %.0f deg   mains : %.0f deg" % [rim, hands])
	print("  LA JANTE GLISSE   : %s   (les mains font %.0f %% du chemin, seuil 40)" % [
		hands < rim * 0.40, 100.0 * hands / maxf(rim, 1.0)])
	print("  doigts desserres  : %s   (fermeture minimale %.2f)" % [close_min < 0.8, close_min])
	print("  rappel actif      : %d images sur %d" % [slipping, frames])
	print("  mains rangees     : G %+.0f  D %+.0f deg" % [
		drv.grip_angle(false), drv.grip_angle(true)])

	# --- une main prise par un objet ---------------------------------------
	# On prend vraiment le paquet, avec un vrai clic : l'autre main ne peut plus
	# enserrer la jante, elle doit se poser A PLAT dessus et tourner par appui.
	print("\n-- une main prise : l'autre conduit a plat --")
	car.steer = 0.0
	await get_tree().create_timer(1.0).timeout
	var flat_ok := await _take_pack()
	print("  paquet en main    : %s" % flat_ok)
	if flat_ok:
		print("  AVANT de braquer  : paume gauche a %.0f deg de l'axe   fermeture %.2f" % [
			drv.palm_tilt(false), drv.grip_close(false)])
		# Capture volant droit : c'est la seule ou la main soit dans le cadre.
		# A fond de braquage elle est passee sous la jante, hors champ — la photo
		# ne montrait plus rien du tout.
		await _shot("27_volant_main_a_plat.png")
		car.speed = 12.0
		await _act("steer_left", true)
		# On releve la pose PENDANT QUE LA JANTE TOURNE : c'est la, et seulement
		# la, qu'on conduit a plat. Mesurer une fois le volant en butee revenait a
		# mesurer la main deja raccrochee — le comportement voulu, au mauvais
		# moment.
		var tilt := 999.0
		var open := 1.0
		var prev: float = car.steer
		var t := 0.0
		while t < 2.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			if absf(car.steer - prev) > 0.0005:
				tilt = minf(tilt, drv.palm_tilt(false))
				open = minf(open, drv.grip_close(false))
			prev = car.steer
		print("  EN TOURNANT       : dos a %.0f deg de l'axe   DOS VERS LE JOUEUR: %s" % [
			tilt, tilt < 30.0])
		# Et elle a suivi la jante D'UN BOUT A L'AUTRE, sans buter en chemin : a
		# plat, le poignet ne se tord pas, rien ne justifie de lacher. La main
		# doit donc etre au meme angle que le volant, pas coincee a sa butee.
		var turned: float = car.steer * DriverScript.WHEEL_MAX_ANGLE
		print("    ELLE ACCOMPAGNE : %s   (main %+.0f deg pour un volant a %+.0f)" % [
			absf(drv.grip_angle(false) - turned) < 15.0, drv.grip_angle(false), turned])
		print("    doigts detendus : %s   (fermeture %.2f, seuil 0.35)" % [
			open < 0.35, open])
		print("    elle tourne bien le volant : %s   (volant %+.0f deg)" % [
			absf(car.steer) > 0.5, car.steer * DriverScript.WHEEL_MAX_ANGLE])
		await _act("steer_left", false)

		# ON ARRETE DE TOURNER : la main libre doit REFERMER LES DOIGTS sur la
		# jante et la tenir comme n'importe quelle main au volant. On ne reste pas
		# la paume posee dessus a ne rien faire. Et elle doit le faire SANS SE
		# DEPLACER : c'est la pose qui change, pas la place de la main.
		car.speed = 0.0            # a l'arret, pas de rappel : la jante ne bouge plus

		# COMBIEN DE TEMPS met-elle a se raccrocher ? C'est ce delai qui se lit
		# comme une hesitation s'il traine : on referme la main sur un volant des
		# qu'on cesse de le tourner.
		#
		# La butee de braquage a deja immobilise la jante — la main s'y est donc
		# raccrochee AVANT qu'on relache la touche, et chronometrer a partir d'ici
		# donnait 0,00 s sans rien prouver. On la remet en mouvement, puis on
		# s'arrete net.
		await _act("steer_right", true)
		await get_tree().create_timer(0.7).timeout
		await _act("steer_right", false)
		# Et on attend qu'elle soit VRAIMENT immobile : la jante a de l'inertie,
		# elle finit son mouvement apres la touche, et la main la suit pendant ce
		# temps-la. Relever la position avant ce moment mesurait ce mouvement-la.
		var prev2: float = car.steer
		var settle := 0.0
		while settle < 2.0:
			await get_tree().process_frame
			settle += get_process_delta_time()
			if absf(car.steer - prev2) < 0.0005:
				break
			prev2 = car.steer
		var held_at: float = drv.grip_angle(false)
		var grabbed := 0.0
		while grabbed < 2.0 and drv.grip_close(false) < 0.80:
			await get_tree().process_frame
			grabbed += get_process_delta_time()
		print("  se raccroche en   : %.2f s   (delai %.2f + fondu)" % [
			grabbed, DriverScript.FLAT_GRAB_DELAY])
		# Releve TANT QU'ELLE EST ENCORE AGRIPPEE : la phase suivante rebraque et
		# la remet a plat, mesurer apres reviendrait a mesurer ce braquage-la.
		print("  volant repose     : dos a %.0f deg   fermeture %.2f" % [
			drv.palm_tilt(false), drv.grip_close(false)])
		print("    ELLE SE RACCROCHE : %s   (doigts refermes, seuil 0.80)" % [
			drv.grip_close(false) > 0.80])
		print("    SANS SE DEPLACER  : %s   (bouge de %.1f deg)" % [
			absf(drv.grip_angle(false) - held_at) < 2.0,
			absf(drv.grip_angle(false) - held_at)])
		await _shot("28_volant_main_raccrochee.png")

		# ... ET COMBIEN DE JANTE avant qu'elle REPASSE a plat ? Une main
		# agrippee ne se remet pas a plat parce que le volant a bouge : il faut
		# que le mouvement s'installe. C'est un chemin, pas un delai — sinon une
		# correction de trajectoire suffirait a ouvrir la main.
		car.speed = 12.0
		var from_deg: float = car.steer * DriverScript.WHEEL_MAX_ANGLE
		var opened := -1.0
		await _act("steer_left", true)
		var t2 := 0.0
		while t2 < 2.5:
			await get_tree().process_frame
			t2 += get_process_delta_time()
			if opened < 0.0 and drv.grip_close(false) < 0.5:
				opened = absf(car.steer * DriverScript.WHEEL_MAX_ANGLE - from_deg)
		await _act("steer_left", false)
		print("  repasse a plat    : apres %.0f deg de jante   (seuil %.0f)   PAS TROP TOT: %s" % [
			opened, DriverScript.FLAT_TURN_TRAVEL,
			opened >= DriverScript.FLAT_TURN_TRAVEL])
		await get_tree().create_timer(1.0).timeout
		# ON REPOSE LE PAQUET. Sans ca la phase suivante mesurait encore une main
		# a plat — butees elargies, +296 degres — en croyant mesurer un poing
		# referme qui sature. Un banc qui garde un objet en main teste autre chose
		# que ce qu'il annonce.
		car.interaction.let_go()
		await get_tree().create_timer(1.2).timeout
	car.steer = 0.0
	await get_tree().create_timer(1.0).timeout

	# --- une seule main disponible ----------------------------------------
	# Embrayage tenu : la main droite est au levier, la gauche ne PEUT plus
	# lacher. Elle doit alors saturer — la jante file sous la paume — au lieu de
	# se retourner le coude ou de lacher un volant que personne ne tient.
	print("\n-- main droite au levier, braquage a fond --")
	await _act("clutch", true)
	await get_tree().create_timer(0.5).timeout
	await _act("steer_left", true)
	await _wheel_watch(2.4, "une seule main", false)
	print("  main gauche       : %+.0f deg   BORNEE: %s   (butee %.0f + reserve %.0f)" % [
		drv.grip_angle(false),
		absf(drv.grip_angle(false)) <= DriverScript.GRIP_PULL + DriverScript.GRIP_RESERVE + 1.0,
		DriverScript.GRIP_PULL, DriverScript.GRIP_RESERVE])
	await _act("steer_left", false)
	await _act("clutch", false)
	await get_tree().create_timer(1.0).timeout
	await _shot("27_volant_repos.png")
	get_tree().quit()


## Prend vraiment le paquet de cigarettes, avec une vraie visee et un vrai clic —
## comme `-- packtest`. Le banc du volant a besoin d'un objet EN MAIN, pas d'un
## `item_blend` pose a la main : c'est la chaine complete qui doit mettre l'autre
## main a plat sur la jante.
func _take_pack() -> bool:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var inter = car.interaction
	if inter.grabbables.is_empty():
		return false
	var pack: Node3D = inter.grabbables[0]
	for attempt in 3:
		await _aim_at(car.to_local(pack.global_position))
		await _click()
		if await _until(func(): return inter.held == pack, 1.5):
			# Le geste continue apres la prise : le bras ramene l'objet devant
			# soi. On mesure la pose etablie, pas le trajet.
			await get_tree().create_timer(0.9).timeout
			car.head.rotation = Vector3.ZERO
			await get_tree().create_timer(0.6).timeout
			return true
	return false


## Suit les deux mains image par image et imprime ce qui leur arrive. Les prises
## sont relevees sur le CHANGEMENT d'etat, pas echantillonnees : une prise dure
## un quart de seconde, un releve periodique en manquerait.
func _wheel_watch(seconds: float, label: String, shots: bool) -> void:
	var drv = car.driver
	var span: float = drv.arm_span()
	var was := [drv.grip_moving(false), drv.grip_moving(true)]
	var held_min := 2
	var reach := [0.0, 0.0]
	var sep_min := 9.0
	var takes := 0
	var t := 0.0
	var shot_at := 0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var wheel: float = car.steer * DriverScript.WHEEL_MAX_ANGLE
		for h in 2:
			var right := h == 1
			var moving: bool = drv.grip_moving(right)
			if moving != was[h]:
				was[h] = moving
				if moving:
					takes += 1
					print("  %s lache a %+4.0f deg  (volant %+4.0f)" % [
						"main DROITE " if right else "main GAUCHE ",
						drv.grip_angle(right), wheel])
				else:
					print("               se repose a %+4.0f deg  (volant %+4.0f)" % [
						drv.grip_angle(right), wheel])
			reach[h] = maxf(reach[h], drv.hand_reach(right))
		held_min = mini(held_min, drv.grips_held())
		sep_min = minf(sep_min,
			drv.hand_left().position.distance_to(drv.hand_right().position))
		if shots and shot_at < 3 and t > 0.55 * float(shot_at + 1):
			shot_at += 1
			await _shot("27_volant_prise_%d.png" % shot_at)
	print("  %-16s : %d prises   volant %+.0f deg" % [
		label, takes, car.steer * DriverScript.WHEEL_MAX_ANGLE])
	print("    UNE MAIN TIENT TOUJOURS : %s   (minimum observe %d)" % [held_min >= 1, held_min])
	# La portee au repos vaut deja 0,65 m pour 0,58 m de bras : c'est la position
	# de conduite du modele, pas l'affaire des prises (README, « Position de
	# conduite »). Ce qui se juge ici, c'est le SURCOUT d'une prise ecartee — et
	# il doit rester sous 6 cm, sinon un bras qu'on ne voit pas traverse le buste.
	var rest: float = maxf(drv.reach_at(false, 0.0), drv.reach_at(true, 0.0))
	var over: float = maxf(reach[0], reach[1]) - rest
	print("    epaule -> poignet max   : G %.3f  D %.3f m   (repos %.3f, bras %.3f)" % [
		reach[0], reach[1], rest, span])
	# 80 mm, c'est le pire cas STRUCTUREL : une main qui attend son tour va
	# jusqu'a sa butee plus la reserve (GRIP_PULL + GRIP_RESERVE = 135 degres),
	# et la portee y vaut 0,73 m. En conduite courante on releve plutot 55 a
	# 60 mm. Au-dela de 80, ce n'est plus une pose tendue, c'est que la
	# saturation ne borne plus rien.
	print("    LE BRAS NE TIRE PAS     : %s   (+%.3f m sur la pose 10 h 10, seuil 0.080)" % [
		over <= 0.080, over])
	# Le plancher, c'est le RETRAIT lui-meme (`REGRIP_LIFT`, 85 mm) : au croisement
	# les deux mains sont l'une au-dessus de l'autre, et c'est lui seul qui les
	# separe. Exiger davantage reviendrait a interdire le croisement, c'est-a-dire
	# le geste. En dessous, elles se traversent.
	print("    MAINS JAMAIS MELEES     : %s   (ecart minimum %.3f m, seuil 0.070)" % [
		sep_min > 0.070, sep_min])


## Banc d'essai du penchement : clic droit maintenu, le buste part dans la
## direction du regard.
##
## Ce qu'on verifie n'est pas que la camera bouge — ca se voit — mais que ca
## SERT et que ca ne casse rien : que la tete reste dans l'habitacle, et surtout
## que la banquette arriere passe de HORS de portee du bras a DEDANS. C'est tout
## le sujet : le geste existait deja, mais l'avant-bras s'allongeait de 40 % pour
## arriver au bout, et un bras de gorille se voit immediatement.
##
## A LANCER AVEC UNE FENETRE, pas en --headless : se pencher demande la souris
## capturee, et le serveur d'affichage muet ne capture rien. Le clic de prise
## est dans le meme cas.
func _lean_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(1.0).timeout
	var inter = car.interaction
	var drv = car.driver
	var span: float = drv.arm_span()
	var seated: Vector3 = car.head.position
	print("assis              : tete=%s   bras=%.3f m" % [seated.snappedf(0.001), span])

	# --- 1. devant le siege passager --------------------------------------
	# On regarde la boite a gants : la tete doit VENIR dessus, pas se contenter
	# de tourner vers elle.
	await _aim_clamped(Vector3(0.45, 0.70, -0.62), null, 6)
	var before: Vector3 = car.head.position
	await _act("lean", true)
	await _until(func(): return car.lean_amount() > 0.97, 2.0)
	await get_tree().create_timer(0.6).timeout
	var leaned: Vector3 = car.head.position
	print("penche a la BAG    : tete=%s   deplacement %.3f m" % [
		leaned.snappedf(0.001), leaned.distance_to(before)])
	# Les mains ne lachent plus le volant : c'est donc l'allonge des bras qui
	# paie le penchement, et elle se surveille des qu'on touche a `lean_reach`.
	# Au-dela de ~1,10 le segment s'allonge visiblement — bras de gorille.
	print("  bras au volant    : avant-bras G x%.3f  D x%.3f   (1.000 = pas etire)" % [
		drv.forearm_stretch_left(), drv.forearm_stretch()])
	# Le tunnel de console va de -0.13 a 0.13 : le franchir, c'est avoir quitte
	# sa place pour de bon. Exiger x > 0 serait mesurer un centimetre pres une
	# amplitude qui, elle, se regle au doigt (`lean_reach`).
	print("  passe la console  : %s   (x %.3f, il partait de %.3f)" % [
		leaned.x > -0.13, leaned.x, before.x])
	print("  dans l'habitacle   : %s" % _in_cabin(leaned))

	await _act("lean", false)
	await _until(func(): return car.lean_amount() < 0.02, 2.0)
	await get_tree().create_timer(0.4).timeout
	print("relache            : revenu a %.3f m de la pose assise" %
		car.head.position.distance_to(before))

	# --- 2. le volant ne se traverse pas ----------------------------------
	# Regard aux pieds, cote conducteur : c'est la que la tete plongerait dans
	# la jante si LEAN_WHEEL_Y ne la retenait pas.
	await _aim_clamped(Vector3(-0.40, 0.25, -0.55), null, 6)
	await _act("lean", true)
	await _until(func(): return car.lean_amount() > 0.97, 2.0)
	await get_tree().create_timer(0.6).timeout
	leaned = car.head.position
	print("plonge au plancher : tete=%s" % leaned.snappedf(0.001))
	print("  au-dessus du volant: %s   (y %.3f, jante a %.2f)" % [
		leaned.y >= CarScript.LEAN_WHEEL_Y - 0.01, leaned.y, CarScript.LEAN_WHEEL_Y])
	await _act("lean", false)
	await _until(func(): return car.lean_amount() < 0.02, 2.0)

	# --- 2 bis. tourner ne doit PAS zoomer ---------------------------------
	# Penchement etabli, on balaie tout le debattement du regard et on releve la
	# LONGUEUR du deplacement. Si elle bouge, la camera avance et recule le long
	# de son propre axe pendant qu'on tourne — et ca ne se lit pas comme un
	# corps qui se penche, ca se lit comme un zoom. C'est ce que faisait la
	# version qui s'arretait court de la surface visee : la planche est a 90 cm,
	# la console a 60, le vide a l'infini, donc la longueur suivait le regard.
	car.head.rotation = Vector3.ZERO
	await get_tree().create_timer(0.6).timeout
	# On entre dans la zone d'enroulement, CLIC DROIT TENU, et on laisse la pose
	# s'etablir.
	#
	# Le clic est indispensable : se retourner seul ne deplace plus le corps.
	# Sans lui il n'y aurait aucun penchement a balayer, et ce qu'on mesurerait
	# serait la translation ordinaire de HEAD_BACK au fil du lacet — qui n'a
	# rien d'un zoom et ferait echouer le test pour une raison etrangere a ce
	# qu'il surveille.
	car.head.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(-120.0), 0.0)
	await _act("lean", true)
	await _until(func(): return car.lean_amount() > 0.99, 3.0)
	await get_tree().create_timer(1.0).timeout

	var first: Vector3 = car.head.position
	var worst := 0.0
	var worst_axial := 0.0
	for i in 20:
		# On balaie DANS la zone : le regard fouille la banquette, du cote
		# passager au cote conducteur, en plongeant plus ou moins.
		car.head.rotation.y = deg_to_rad(lerpf(-110.0, -185.0, i / 19.0))
		car.head.rotation.x = deg_to_rad(lerpf(-20.0, -55.0, i / 19.0))
		await get_tree().create_timer(0.1).timeout
		var moved: Vector3 = car.head.position - first
		worst = maxf(worst, moved.length())
		# La composante LE LONG DU REGARD est celle qui se voit comme un zoom :
		# se decaler lateralement, c'est de la parallaxe, et ca se lit comme un
		# corps qui bouge. Avancer sur son axe optique, non.
		worst_axial = maxf(worst_axial,
			absf(moved.dot(-car.head.transform.basis.z)))
	print("balayage enroule   : la tete bouge de %.0f mm   dont %.0f mm sur l'axe du regard" % [
		worst * 1000.0, worst_axial * 1000.0])
	print("  PAS DE ZOOM       : %s   (seuil 20 mm sur l'axe)" % (worst_axial < 0.020))
	car.head.rotation = Vector3.ZERO
	await _act("lean", false)
	await _until(func(): return car.lean_amount() < 0.02, 3.0)

	# --- 3. la banquette arriere ------------------------------------------
	# Les deux canettes ecrasees qui trainent a l'arriere (cabin.CAN_SPAWNS) :
	# une sur la banquette cote conducteur, une au plancher cote passager. On
	# mesure les deux, assis puis penche.
	for wanted in ["Can_cariboon_Crushed", "Can_kombo_Crushed"]:
		var can: Node3D = null
		for g in inter.grabbables:
			if String(g.name).begins_with(wanted):
				can = g
		if can == null:
			print("%-18s : INTROUVABLE" % wanted)
			continue
		var local: Vector3 = car.to_local(can.global_position)
		print("%-18s : pos voiture=%s" % [wanted, local.snappedf(0.001)])

		# Retourne sur son siege, sans se pencher, ET regard remis droit devant.
		# Repartir de la pose penchee precedente ferait viser depuis un point ou
		# le joueur ne serait jamais : il se redresse entre deux gestes.
		await _act("lean", false)
		await _until(func(): return car.lean_amount() < 0.02, 2.0)
		car.head.rotation = Vector3.ZERO
		await get_tree().create_timer(0.7).timeout
		var seen_seated: bool = await _aim_clamped(local, can, 16)
		await get_tree().create_timer(0.6).timeout
		var sh_seated: Vector3 = drv.shoulder_right()
		var d_seated: float = sh_seated.distance_to(local)
		print("  retourne, SANS clic droit : tete=%s   visee=%s" % [
			car.head.position.snappedf(0.001), seen_seated])
		# SE RETOURNER NE DEPLACE PAS LE CORPS : ces deux lignes doivent rester a
		# false. Le buste se vrille sur place, le dos cale contre le dossier,
		# l'epaule reste DEVANT son plan. C'est voulu — un mouvement de tete
		# ordinaire ne doit pas emmener le joueur sur la banquette.
		print("    corps immobile   : %s   (penche a %.2f, enroule=%s)" % [
			car.lean_amount() < 0.02, car.lean_amount(), car.wrapping()])
		print("    epaule droite    : %s   derriere le dossier: %s (attendu false)" % [
			sh_seated.snappedf(0.001), sh_seated.z > 0.53])
		print("    epaule -> canette: %.3f m pour %.3f m de bras   a portee: %s" % [
			d_seated, span, d_seated <= span])
		# Et on essaie de la prendre sans toucher au clic droit.
		#
		# Que ca REUSSISSE ne contredit pas la ligne au-dessus : interaction.gd
		# n'exige pas que le bras y arrive, seulement que l'objet soit sous le
		# viseur a moins de `reach` (1,25 m de l'oeil). L'epaule, elle, en est a
		# 0,77 m pour 0,58 m de bras — c'est le bras qui rattrape, pas le corps
		# qui se deplace. Le distinguo est justement ce que ce banc rend visible :
		# si un jour on veut que la banquette se MERITE, c'est ici qu'on lira que
		# la prise passe encore.
		var got_seated := false
		for attempt in 3:
			await _aim_clamped(local, can, 6)
			await _click()
			got_seated = await _until(func(): return inter.held == can, 1.5)
			if got_seated:
				break
		print("    prise sans clic droit : %s   (le viseur suffit, c'est le bras qui rattrape)" %
			got_seated)
		if got_seated:
			# Remise EXACTEMENT ou elle etait, et pas reposee au viseur : la
			# mesure penchee qui suit se compare a celle d'avant, et elle ne le
			# peut que si la canette n'a pas bouge d'un millimetre entre les deux.
			inter.let_go()
			can.position = local
			await get_tree().create_timer(0.8).timeout

		# Puis penche. On repart tete droite et on MAINTIENT LE CLIC AVANT DE
		# TOURNER : c'est l'ordre du joueur, et c'est lui qui compte. Se pencher
		# efface la sortie de tete par la vitre, donc tourner a gauche une fois
		# le bouton tenu emmene le buste EN ARRIERE dans l'habitacle au lieu de
		# passer la tete dehors. Dans l'autre ordre, on sort d'abord la tete et
		# on ne voit plus jamais la banquette.
		car.head.rotation = Vector3.ZERO
		await get_tree().create_timer(0.7).timeout
		await _act("lean", true)
		await _until(func(): return car.lean_amount() > 0.97, 2.0)
		var seen_leaned: bool = await _aim_clamped(local, can, 16)
		await get_tree().create_timer(0.5).timeout
		leaned = car.head.position
		# Releve AVANT les essais de prise : ceux-ci font bouger la tete, et on
		# mesurerait alors la pose d'apres le geste, pas celle qui le permet.
		var d_leaned: float = drv.shoulder_right().distance_to(local)
		print("  penche en arriere : tete=%s   visee=%s" % [
			leaned.snappedf(0.001), seen_leaned])
		print("    dans l'habitacle : %s" % _in_cabin(leaned))
		print("    epaule -> canette: %.3f m   A PORTEE: %s   (gagne %.3f m)" % [
			d_leaned, d_leaned <= span, d_seated - d_leaned])
		# L'epaule droite doit avoir passe le plan du dossier (z 0.53) : c'est
		# ca, s'enrouler autour du siege, et c'est ce qui donne acces a ce qui
		# est pose DERRIERE. Devant ce plan, le bras bute sur le dossier.
		var sh: Vector3 = drv.shoulder_right()
		print("    epaule droite    : %s   DERRIERE LE DOSSIER: %s (z 0.53)" % [
			sh.snappedf(0.001), sh.z > 0.53])
		print("    bras au volant   : avant-bras G x%.3f  D x%.3f" % [
			drv.forearm_stretch_left(), drv.forearm_stretch()])
		# VERDICT DIRECT, sans dependre de la convergence de la boucle de visee.
		# Celle-ci se cale mal sur ce qui est pratiquement plein arriere : le
		# lacet requis y bascule d'un bord a l'autre pour quelques centimetres
		# de tete, et le banc part du mauvais cote. Une souris n'a pas cette
		# discontinuite. Ce qu'on peut affirmer sans elle : depuis la pose
		# penchee, l'objet est-il DANS le debattement de la tete, et a portee ?
		var to_can: Vector3 = local - leaned
		var need_yaw: float = rad_to_deg(atan2(-to_can.x, -to_can.z))
		var need_pitch: float = rad_to_deg(asin(clampf(to_can.normalized().y, -1.0, 1.0)))
		var cap_right: float = car.yaw_limit_right + car.lean_yaw_bonus * car.lean_amount()
		var in_cone: bool = need_yaw >= -cap_right and need_yaw <= car.yaw_limit_left \
			and absf(need_pitch) <= car.pitch_limit
		print("    lacet %.0f deg (butee %.0f a droite / %.0f a gauche)   plongee %.0f deg (butee %.0f)" % [
			need_yaw, -cap_right, car.yaw_limit_left, need_pitch, car.pitch_limit])
		print("    DANS LE CHAMP    : %s   a %.3f m de l'oeil" % [
			in_cone, to_can.length()])

		# Et on la prend pour de bon : c'est le geste complet qui compte, avec
		# le buste qui va chercher les derniers centimetres (REACH_LEAN_OFF_SEAT).
		# On laisse la pose se poser et on re-vise avant de cliquer : cliquer a
		# l'instant precis ou la cible s'allume, c'est cliquer pendant que la
		# tete bouge encore, et la cible se perd entre le clic et la prise.
		await get_tree().create_timer(0.5).timeout
		var got := false
		for attempt in 4:
			# Re-viser AVANT chaque essai : la pose se pose encore, et un clic
			# tire pendant que la tete bouge trouve la cible deja perdue.
			await _aim_clamped(local, can, 6)
			await _click()
			got = await _until(func(): return inter.held == can, 1.5)
			if got:
				break
		print("    ATTRAPEE         : %s   avant-bras etire x%.3f (1.000 = pas etire)" % [
			got, drv.forearm_stretch()])
		if got:
			# On la repose ou elle etait : la canette suivante se mesure dans
			# une voiture propre.
			await _mouse(true)
			await get_tree().create_timer(0.3).timeout
			await _mouse(false)
			await get_tree().create_timer(0.8).timeout

	# --- 4. s'enrouler autour du siege ------------------------------------
	# Le geste qu'on fait pour attraper ce qui traine DERRIERE SOI : on se
	# tourne a droite jusqu'au bout et le buste contourne le dossier.
	#
	# On amene la tete a l'angle A LA MAIN au lieu de passer par la boucle de
	# visee : celle-ci ne se cale pas sur ce qui est pratiquement plein arriere
	# (le lacet requis y bascule d'un bord a l'autre pour quelques centimetres
	# de tete). Or ce qu'on veut mesurer ici est la POSE, pas la capacite du
	# banc a converger dessus. L'angle, lui, est connu : la butee penchee.
	var kombo: Node3D = null
	for g in inter.grabbables:
		if String(g.name).begins_with("Can_kombo_Crushed"):
			kombo = g
	if kombo != null:
		var kl: Vector3 = car.to_local(kombo.global_position)
		await _act("lean", false)
		await _until(func(): return car.lean_amount() < 0.02, 2.0)
		car.head.rotation = Vector3.ZERO
		await get_tree().create_timer(0.7).timeout
		await _act("lean", true)
		await _until(func(): return car.lean_amount() > 0.97, 2.0)
		var cap: float = deg_to_rad(car.yaw_limit_right + car.lean_yaw_bonus)
		for i in 16:
			car.head.rotation.y = maxf(car.head.rotation.y - deg_to_rad(14.0), -cap)
			car.head.rotation.x = -deg_to_rad(25.0)
			await get_tree().create_timer(0.12).timeout
		await get_tree().create_timer(0.9).timeout

		var sh: Vector3 = drv.shoulder_right()
		var d: float = sh.distance_to(kl)
		print("enroule            : lacet %.0f deg   tete=%s" % [
			rad_to_deg(car.head.rotation.y), car.head.position.snappedf(0.001)])
		print("  epaule droite     : %s" % sh.snappedf(0.001))
		print("  DERRIERE LE DOSSIER: %s   (z %.3f, dossier a 0.53)" % [sh.z > 0.53, sh.z])
		print("  epaule -> canette : %.3f m pour %.3f m de bras   A PORTEE: %s" % [
			d, span, d <= span])
		print("  bras au volant    : avant-bras G x%.3f  D x%.3f" % [
			drv.forearm_stretch_left(), drv.forearm_stretch()])
		var seen: bool = await _aim_clamped(kl, kombo, 8)
		print("  visee             : %s" % seen)
		var caught := false
		for attempt in 3:
			await _aim_clamped(kl, kombo, 4)
			await _click()
			caught = await _until(func(): return inter.held == kombo, 1.5)
			if caught:
				break
		print("  ATTRAPEE          : %s   avant-bras D x%.3f" % [
			caught, drv.forearm_stretch()])
	get_tree().quit()


## Banc de la REGLE : se retourner regarde, le clic droit deplace. Rien d'autre.
##
## C'est le banc d'un defaut vecu, pas d'une specification. Une version faisait
## partir le buste tout seul des que le regard tournait assez a droite en
## plongeant, pour mettre la banquette a portee sans rien demander. En pratique
## on se retrouvait A GENOUX SUR LA BANQUETTE juste pour avoir regarde derriere
## soi — or regarder derriere soi, on le fait sans arret : pour reculer, pour
## surveiller, par reflexe.
##
## Le banc mesure donc l'ecart MAXIMUM de la tete sur toute la sequence, et pas
## seulement a l'arrivee : un aller-retour se verrait a l'ecran tout en laissant
## la pose finale intacte.
func _wrap_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(1.0).timeout

	# 1. Retourne a droite, REGARD A L'HORIZONTALE : c'est la marche arriere, on
	#    regarde par la lunette. Rien ne doit avoir bouge.
	car.head.rotation = Vector3(0.0, -deg_to_rad(140.0), 0.0)
	await get_tree().create_timer(1.5).timeout
	var level: Vector3 = car.head.position
	print("retourne, regard a plat : tete=%s   penche a %.2f" % [
		level.snappedf(0.001), car.lean_amount()])
	print("  LA TETE EST RESTEE    : %s   (enroule=%s)" % [
		car.lean_amount() < 0.05, car.wrapping()])

	# 2. LE TEST QUI COMPTE. On baisse les yeux a 45 degres, toujours sans rien
	#    tenir, et on filme image par image. La tete ne doit PAS bouger — ni au
	#    bout du compte, ni en cours de route. Une version precedente partait
	#    d'elle-meme s'enrouler autour du siege ici, et on se retrouvait a genoux
	#    sur la banquette pour avoir simplement regarde derriere soi.
	car.head.rotation.x = -deg_to_rad(45.0)
	var worst := 0.0
	for i in 150:
		await get_tree().process_frame
		worst = maxf(worst, car.head.position.distance_to(level))
	var settled: Vector3 = car.head.position
	print("yeux baisses de 45 deg  : tete=%s   penche a %.2f   enroule=%s" % [
		settled.snappedf(0.001), car.lean_amount(), car.wrapping()])
	# L'ecart maxi sur toute la sequence, pas seulement a l'arrivee : un aller-
	# retour se verrait a l'ecran et ne laisserait aucune trace sur la pose
	# finale.
	print("  LA TETE N'A PAS BOUGE : %s   (ecart maxi %.3f m, seuil 10 mm)" % [
		worst <= 0.010, worst])
	print("  corps immobile        : %s   (penche a %.2f)" % [
		car.lean_amount() < 0.02, car.lean_amount()])

	# 3. Et maintenant le clic droit : LUI a le droit de deplacer le corps, et
	#    c'est le seul. Retourne a droite et regard plonge, il ne penche pas vers
	#    l'avant mais contourne le siege (HEAD_WRAP).
	await _act("lean", true)
	await get_tree().create_timer(1.5).timeout
	var leaned: Vector3 = car.head.position
	print("clic droit tenu         : tete=%s   penche a %.2f   enroule=%s" % [
		leaned.snappedf(0.001), car.lean_amount(), car.wrapping()])
	print("  LE CORPS SUIT         : %s   (deplacement %.3f m)" % [
		leaned.distance_to(level) > 0.10, leaned.distance_to(level)])

	# 4. Relache : on revient s'asseoir, sans avoir a lever les yeux.
	await _act("lean", false)
	await get_tree().create_timer(1.5).timeout
	var back: float = car.head.position.distance_to(level)
	print("clic droit relache      : a %.3f m de la pose retournee   penche a %.2f" % [
		back, car.lean_amount()])
	print("  REVENU S'ASSEOIR      : %s   (seuil 30 mm)" % (back <= 0.030))
	get_tree().quit()


## Comme _aim_at, mais BORNE au debattement reel de la tete, et repete jusqu'a
## ce que `obj` soit vraiment sous le viseur.
##
## Deux raisons. Un banc qui vise par-dela les butees mesure une pose que le
## joueur ne peut pas prendre — c'est comme ca qu'on croit avoir acces a un coin
## de la banquette qu'on ne peut en realite meme pas regarder. Et la tete se
## DEPLACE en visant (on se retourne, on se penche), donc un calcul unique vise
## a cote : on corrige jusqu'a ce que le point s'allume, exactement comme un
## joueur.
## Part de l'ecart qu'une passe rattrape. La tete se DEPLACE en tournant : viser
## est donc un point fixe, pas un calcul. Sauter d'un coup sur l'angle calcule
## depasse et repart en sens inverse — le banc oscillait sans jamais se poser.
## En n'en reprenant qu'un peu moins de la moitie, la suite converge.
const AIM_DAMP := 0.45

func _aim_clamped(point: Vector3, obj: Node3D = null, passes := 8) -> bool:
	for i in passes:
		var dir: Vector3 = (point - car.head.position).normalized()
		var want_pitch := clampf(asin(clampf(dir.y, -1.0, 1.0)),
			-deg_to_rad(car.pitch_limit), deg_to_rad(car.pitch_limit))
		var cur: float = car.head.rotation.y
		# La butee droite est celle DU MOMENT : elle s'ouvre en se penchant.
		var want_yaw := clampf(atan2(-dir.x, -dir.z),
			-deg_to_rad(car.yaw_limit_right + car.lean_yaw_bonus * car.lean_amount()),
			deg_to_rad(car.yaw_limit_left))
		car.head.rotation = Vector3(
			lerpf(car.head.rotation.x, want_pitch, AIM_DAMP),
			lerpf(cur, want_yaw, AIM_DAMP),
			0.0)
		await get_tree().create_timer(0.25).timeout
		if obj != null and car.interaction.target == obj:
			return true
	return obj == null


## Vrai si la tete est dans la boite de l'habitacle (car.gd). Le plafond du
## volant n'y est pas repris : on verifie l'enveloppe, pas le detail.
func _in_cabin(p: Vector3) -> bool:
	var lo: Vector3 = CarScript.LEAN_MIN
	var hi: Vector3 = CarScript.LEAN_MAX
	return p.x >= lo.x - 0.002 and p.x <= hi.x + 0.002 \
		and p.y >= lo.y - 0.002 and p.y <= hi.y + 0.002 \
		and p.z >= lo.z - 0.002 and p.z <= hi.z + 0.002


## Banc d'essai de la boite : plein gaz dans chaque rapport, on releve la
## vitesse stabilisee. On demarre a 70 % du rupteur pour converger vite, et on
## accelere le temps pour que le test dure quelques secondes.
func _gear_test() -> void:
	Engine.time_scale = 6.0
	car.debug_full_throttle = true
	for g in range(2, CarScript.GEAR_NAMES.size()):
		car.gear = g
		car.speed = CarScript.GEAR_TOP[g] * 0.7
		# 3,4 s x6 = 20 s de jeu, pas assez : sur les rapports longs la poussee
		# n'excede la trainee que d'un ou deux dixiemes de m/s^2, la vitesse
		# maxi s'approche en une minute. On mesurait la fenetre, pas la voiture.
		await get_tree().create_timer(10.0, true, false, true).timeout
		print("rapport %s : %5.1f km/h   %d tr/min" % [
			CarScript.GEAR_NAMES[g], car.speed * 3.6, int(round(car.rpm))])

	# 0 a 100 km/h, en passant au rupteur et sans temps de passage.
	var last := CarScript.GEAR_NAMES.size() - 1
	car.gear = 2
	car.speed = 0.0
	var t := 0.0
	while car.speed * 3.6 < 100.0 and t < 90.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if car.gear < last and car.speed > CarScript.GEAR_TOP[car.gear] * 0.985:
			car.gear += 1
	print("0-100 km/h : %.1f s  (arrivee en %s)" % [t, CarScript.GEAR_NAMES[car.gear]])

	Engine.time_scale = 1.0
	get_tree().quit()


## Banc d'essai du geant.
##
## Quatre choses a prouver, dans cet ordre d'importance :
##
##   1. LES PIEDS NE GLISSENT PAS. C'est ce qui trahit une animation
##      procedurale, et rien d'autre ne compte tant que ce n'est pas acquis. On
##      suit la POINTE du pied d'appui image par image, sur toute la course.
##      Ce n'est pas la cheville qu'on suit : en fin d'appui le pied se dresse
##      sur ses orteils, la cheville monte de deux metres et avance d'un autre,
##      et c'est normal. La pointe, elle, ne doit pas bouger.
##   2. LES JAMBES NE S'ALLONGENT PAS. C'est le corollaire : le seul moyen de ne
##      pas glisser tout en gardant le bassin ou l'on veut, c'est d'etirer la
##      cuisse. On mesure donc hanche-cheville contre la longueur de jambe.
##   3. IL AVANCE DE CE QU'IL FAIT. La foulee mesuree fois la cadence mesuree
##      doit redonner la vitesse. Trois nombres qui se contredisent, c'est
##      exactement ce qui fait les demarches de dessin anime.
##   4. LE PIED FRAPPE. Un pietinement qui tombe sur la voiture doit passer les
##      2,4 g, sinon rien ne decolle dans l'habitacle et le coup n'est qu'un
##      effet de camera.
func _giant_test() -> void:
	var g = road.giant

	# --- 0. la route le pose-t-elle vraiment ? -----------------------------
	# Tout le reste du banc place le geant a la main. Ce premier essai est le
	# seul qui prouve le CABLAGE : on avance le rendez-vous a l'echantillon
	# suivant, on roule, et on regarde si road.gd le sort des arbres tout seul,
	# du bon cote et a la bonne distance de la chaussee. Sans lui, on pourrait
	# livrer un geant parfait que personne ne rencontrerait jamais.
	print("--- la route le pose ---------------------------------------------")
	car.gear = 5
	car.speed = 28.0
	road._giant_next = road._index0 + RoadScript.SAMPLES - 4
	var posed: bool = await _until(func(): return road.giant_index >= 0, 12.0)
	var off := 0.0
	if posed:
		var at: Transform3D = road.sample_at(road.giant_index)
		off = Vector2(g.global_position.x - at.origin.x,
			g.global_position.z - at.origin.z).length()
	print("  ELLE LE POSE      : %s   (echantillon %d, a %.1f m de l'axe)" % [
		posed, road.giant_index, off])
	print("  DANS LES ARBRES   : %s   (les sapins vont de %.1f a %.1f m de l'axe)" % [
		off > RoadScript.ROAD_HALF + RoadScript.SHOULDER and off < 20.4,
		RoadScript.ROAD_HALF + RoadScript.SHOULDER, 20.4])
	print("  IL ATTEND         : %s   (%s)" % [
		g.state == GiantScript.DORMANT or g.state == GiantScript.RISING,
		g.debug_line()])

	# La suite place le geant a la main : la route ne doit plus venir en poser
	# un autre au milieu du banc, elle ecraserait chaque fois la position.
	road._giant_next = 1000000000
	road.giant_index = -1

	print("--- anatomie -----------------------------------------------------")
	print("taille %.1f m   pied %.2f x %.2f m   jambe %.2f m   bassin en course %.2f m" % [
		GiantScript.HEIGHT, GiantScript.FOOT_LEN, GiantScript.FOOT_WIDE,
		GiantScript.LEG, GiantScript.HIP_RUN])
	print("  PIED = VOITURE  : %s   (la Civic fait 3,965 x 1,675)" % (
		absf(GiantScript.FOOT_LEN - 3.965) < 0.02
		and absf(GiantScript.FOOT_WIDE - 1.675) < 0.02))
	print("  IL EST CABLE    : %s   (premier rendez-vous a l'echantillon %d, soit %.0f m)" % [
		g != null, RoadScript.GIANT_FIRST,
		(RoadScript.GIANT_FIRST - RoadScript.BEHIND) * RoadScript.STEP])

	var step_len: float = g.run_speed / GiantScript.RUN_CADENCE
	print("course : %.1f m/s (%.0f km/h)   %.2f pas/s   %.1f m par pas" % [
		g.run_speed, g.run_speed * 3.6, GiantScript.RUN_CADENCE, step_len])
	print("  FROUDE COHERENT : %s   (%.1f m x %.2f /s = %.1f m/s)" % [
		absf(step_len * GiantScript.RUN_CADENCE - g.run_speed) < 0.5,
		step_len, GiantScript.RUN_CADENCE, step_len * GiantScript.RUN_CADENCE])
	print("  on le seme en 5e (%.0f km/h) ; 4e %.0f ; 3e %.0f ; lui %.0f" % [
		CarScript.GEAR_TOP[6] * 3.6, CarScript.GEAR_TOP[5] * 3.6,
		CarScript.GEAR_TOP[4] * 3.6, g.run_speed * 3.6])
	print("  SEULE LA 5e SUFFIT : %s" % (
		CarScript.GEAR_TOP[6] > g.run_speed and CarScript.GEAR_TOP[4] < g.run_speed))

	# --- 1. il est tapi, puis il se leve ----------------------------------
	print("--- l'apparition -------------------------------------------------")
	car.gear = 5
	car.speed = 24.0
	await get_tree().create_timer(0.8).timeout

	_place_giant(g, 150.0, 16.0)
	await get_tree().create_timer(0.4).timeout
	var crouched: float = g.hip_height()
	print("pose a 150 m       : %s" % g.debug_line())
	print("  IL EST TAPI      : %s   (bassin a %.2f m, debout %.2f)" % [
		crouched < GiantScript.HIP_STAND * 0.45, crouched, GiantScript.HIP_STAND])
	print("  IL SE CACHE      : %s   (%.1f m de haut accroupi, les sapins font 6 a 11 m)" % [
		crouched * 2.1 < 11.0, crouched * 2.1])
	await _giant_shot(g, "50_geant_tapi.png", 26.0, 0.55)

	# On le rapproche : il doit remarquer la voiture tout seul et se deplier.
	_place_giant(g, 60.0, 14.0)
	var rose: bool = await _until(func(): return g.state == GiantScript.CHASING, 6.0)
	print("rapproche a 60 m   : %s" % g.debug_line())
	print("  IL S'EST LEVE    : %s   (bassin %.2f m, etait %.2f)" % [
		rose and g.hip_height() > crouched * 2.0, g.hip_height(), crouched])
	await _giant_shot(g, "51_geant_leve.png", 34.0, 0.62)

	# --- 2. la marche, image par image ------------------------------------
	#
	# On roule VITE pendant cette mesure, et ce n'est pas un detail : a 24 m/s
	# il rattrape la voiture au bout de huit secondes, la depasse, et se met a
	# tourner autour — on mesurerait alors une demarche de virage serre, pas une
	# course. A 36 m/s il ne gagne que deux metres par seconde et court droit.
	print("--- la course ----------------------------------------------------")
	car.gear = 6
	car.speed = 36.0
	await get_tree().create_timer(3.5).timeout      # qu'il monte a son allure
	var slide := 0.0
	var stretch := 0.0
	var anchor: Array[Vector3] = [Vector3.INF, Vector3.INF]
	var was: Array[bool] = [g.planted(0), g.planted(1)]
	var lands := []
	var hip_lo := 99.0
	var hip_hi := 0.0
	var t := 0.0
	while t < 11.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		for i in 2:
			var now: bool = g.planted(i)
			if now and not was[i]:
				anchor[i] = g.toe(i)
				lands.append([t, g.global_position])
			elif now and anchor[i].is_finite():
				slide = maxf(slide, anchor[i].distance_to(g.toe(i)))
			elif not now:
				anchor[i] = Vector3.INF
			was[i] = now
			stretch = maxf(stretch, g.hip(i).distance_to(g.ankle(i)) / GiantScript.LEG)
		hip_lo = minf(hip_lo, g.hip_height())
		hip_hi = maxf(hip_hi, g.hip_height())

	print("apres %.0f s de course : %s" % [t, g.debug_line()])
	print("  LES PIEDS TIENNENT : %s   (derive maxi de la pointe : %.0f mm)" % [
		slide < 0.05, slide * 1000.0])
	# Le seuil n'est pas zero, et il ne peut pas l'etre : le pied vise un point
	# choisi une seconde plus tot, et le joueur a le droit de donner un coup de
	# volant entre-temps. Ce qu'on exige, c'est que l'ecart reste INVISIBLE —
	# 6 % de 12,82 m font 77 cm, moins que l'epaisseur du tibia (1,05 m) : le
	# jeu au genou reste enfoui dans le membre. Au-dela, la jambe se disloque.
	print("  LA JAMBE TIENT     : %s   (allongement maxi %.1f %%, soit %.0f cm ; le tibia fait %.0f cm d'epaisseur)" % [
		stretch <= 1.06, (stretch - 1.0) * 100.0,
		(stretch - 1.0) * GiantScript.LEG * 100.0, GiantScript.THICK_SHIN * 100.0])
	print("  le bassin respire  : %.2f a %.2f m   (%.0f cm de battement)" % [
		hip_lo, hip_hi, (hip_hi - hip_lo) * 100.0])

	if lands.size() >= 4:
		var n := lands.size()
		var span: float = lands[n - 1][0] - lands[0][0]
		var walked: float = (lands[n - 1][1] as Vector3).distance_to(lands[0][1])
		var cad := float(n - 1) / span
		var stride := walked / float(n - 1)
		print("mesure : %d pas en %.1f s pour %.0f m   ->  %.2f pas/s, %.1f m par pas" % [
			n - 1, span, walked, cad, stride])
		print("  ILS SE RECOUPENT   : %s   (%.1f x %.2f = %.1f m/s, il roule a %.1f)" % [
			absf(stride * cad - g.speed) < 2.0, stride, cad, stride * cad, g.speed])

	# --- 3. on le seme, ou pas --------------------------------------------
	print("--- la poursuite -------------------------------------------------")
	for v in [30.0, 43.0, 50.0]:
		car.gear = 6 if v > 44.0 else 5
		car.speed = v
		await get_tree().create_timer(1.2).timeout      # qu'il retrouve son allure
		var d0: float = car.global_position.distance_to(g.global_position)
		await get_tree().create_timer(3.0).timeout
		var d1: float = car.global_position.distance_to(g.global_position)
		print("a %5.1f m/s (%3.0f km/h) : ecart %5.1f -> %5.1f m   %+.1f m/s" % [
			v, v * 3.6, d0, d1, (d1 - d0) / 3.0])
		print("   %s" % ("ON LE SEME" if d1 > d0 + 3.0 else
			("IL REVIENT" if d1 < d0 - 3.0 else "il tient l'ecart")))

	# --- 4. le pied ---------------------------------------------------------
	print("--- le pied ------------------------------------------------------")
	# On lui remet la voiture sous le nez, doucement : il ne peut plus la rater.
	car.speed = 10.0
	_place_giant(g, 34.0, 0.0)
	g.state = GiantScript.CHASING
	g._rise = 1.0
	g.speed = g.run_speed * 0.7

	var can: Node3D = car.interaction.grabbables[1] if car.interaction.grabbables.size() > 1 else null
	var can0: Vector3 = can.position if can != null else Vector3.ZERO
	var hits0: int = g.hits
	var got: bool = await _until(func(): return g.hits > hits0, 22.0)
	# Releve TOUT DE SUITE : d'autres pas vont tomber pendant qu'on mesure le
	# choc, et chacun ecrase last_step. Lire ces deux-la a la fin, c'est decrire
	# le pas d'apres en croyant parler de celui qui a touche.
	var hit_at: Vector3 = g.last_step
	var hit_on: bool = g.last_step_hit
	# Et la voiture aussi, au meme instant : en une seconde et demie de mesure
	# elle parcourt quinze metres, et l'ecart mesure apres coup n'est plus celui
	# du pas — c'est celui du chemin fait depuis.
	var car_at := Vector3(car.global_position.x, 0.0, car.global_position.z)
	# On suit la POINTE du choc, pas l'etat d'apres : _shock s'eteint en 60 ms et
	# le ressort de la suspension en une seconde. Relever apres coup, c'est
	# mesurer le retour au calme.
	var peak_a := 0.0
	var peak_cam := 0.0
	var peak_pitch := 0.0
	# Le coup lui-meme, tel qu'il a ete injecte. Il faut le prendre au maximum
	# sur la fenetre : d'autres pas tombent pendant qu'on mesure, plus faibles,
	# et car.last_impact ne garde que le dernier — lu a la fin, il vaut 5 m/s^2
	# et fait croire que le pied a caresse la voiture.
	var peak_inj: float = car.last_impact
	var left := 1.4
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
		peak_inj = maxf(peak_inj, car.last_impact)
		peak_a = maxf(peak_a, car.frame_accel.length())
		peak_cam = maxf(peak_cam, car.cam.position.length())
		peak_pitch = maxf(peak_pitch, absf(car.cam.rotation.x))
	print("pietinements %d   touches %d   (il a frappe : %s)" % [g.stomps, g.hits, got])
	print("  IL VISE LA VOITURE : %s   (le pas est tombe a %.1f m d'elle)" % [
		hit_on, hit_at.distance_to(car_at)])
	print("  CA SECOUE          : %s   (coup de %.0f m/s^2 = %.1f g ; il en reste %.1f g" % [
		peak_inj > 23.5, peak_inj, peak_inj / 9.81, peak_a / 9.81]
		+ " a l'image suivante, seuil des objets 2,4 g)")
	print("  LA CAMERA ENCAISSE : %s   (%.0f mm de debattement, %.1f deg de tangage)" % [
		peak_cam > 0.002, peak_cam * 1000.0, rad_to_deg(peak_pitch)])
	if can != null:
		await get_tree().create_timer(1.0).timeout
		print("  LA CANETTE DECOLLE : %s   (elle a bouge de %.0f mm)" % [
			can.position.distance_to(can0) > 0.01,
			can.position.distance_to(can0) * 1000.0])

	# --- 5. ce qu'on voit du siege ------------------------------------------
	# Deux braises dans le brouillard, et rien d'autre : de nuit, les feux
	# arriere ne portent qu'a seize metres, la lune ne fait pas d'ombres, et il
	# est noir. C'est la SEULE chose qui dit qu'il est encore la.
	car.speed = 26.0
	_place_giant(g, 46.0, 3.0)
	g.state = GiantScript.CHASING
	g._rise = 1.0
	await get_tree().create_timer(1.4).timeout
	# On vise l'HORIZON, pas le geant, et c'est le sujet de la capture : a 46 m
	# sa tete est a 29 degres au-dessus de l'horizontale, et la lunette arriere
	# n'ouvre que sur une dizaine de degres. Assis au volant on ne voit donc
	# jamais ce qui nous poursuit — on voit ses JAMBES passer dans la lunette.
	# Viser sa tete ne cadre que le ciel de toit, ce que la premiere version de
	# ce banc a soigneusement photographie trois fois de suite.
	await _aim_clamped(car.to_local(Vector3(g.global_position.x,
		car.global_position.y + 1.2, g.global_position.z)))
	await get_tree().create_timer(0.4).timeout
	await _shot("52_geant_derriere.png")

	# ET L'IMAGE QUI COMPTE VRAIMENT : quand il vous a rattrape. Le banc vient de
	# montrer qu'a 108 km/h il revient a trois metres — c'est donc la situation
	# ordinaire, pas un cas limite. La, il n'est plus derriere : il est A COTE,
	# et une jambe grande comme un immeuble passe dans la vitre du conducteur.
	# C'est le seul angle depuis le siege ou il tienne dans le champ.
	_place_giant(g, 6.0, -12.0)
	g.state = GiantScript.CHASING
	g._rise = 1.0
	g.speed = car.speed
	await get_tree().create_timer(0.7).timeout
	await _aim_clamped(car.to_local(g.global_position + Vector3(0.0, 6.0, 0.0)))
	await get_tree().create_timer(0.3).timeout
	await _shot("55_geant_a_cote.png")

	# Et la meme scene eclairee, de trois quarts, en entier.
	await _giant_shot(g, "53_geant_course.png", 62.0, 0.50)

	# L'echelle : la voiture au premier plan, lui dessus. C'est la seule image
	# qui dise vraiment ce que "son pied fait la taille de la voiture" veut dire.
	await _giant_shot(g, "54_geant_echelle.png", 34.0, 0.14)
	get_tree().quit()


## Pose le geant a `back` metres derriere la voiture et `side` sur le cote, dans
## son sens de marche, et le remet a l'etat tapi.
func _place_giant(g, back: float, side: float) -> void:
	var b: Basis = car.global_transform.basis
	var p: Vector3 = car.global_position + b.z * back + b.x * side
	g.global_transform = Transform3D(Basis(Vector3.UP, car.rotation.y),
		Vector3(p.x, 0.0, p.z))
	g.arm(car)


## Capture eclairee, camera exterieure placee de trois quarts arriere par rapport
## au geant, cadree sur lui. `dist` en metres, `high` en fraction de sa taille.
##
## L'ambiante est poussee a 9 le temps de la prise : de nuit il est a 0,05
## d'albedo sous une lune sans ombres, la capture ne montrerait qu'un carre noir.
func _giant_shot(g, fname: String, dist: float, high: float) -> void:
	var was_amb: float = _env.ambient_light_energy
	var was_fog: float = _env.fog_density
	var was_adj: bool = _env.adjustment_enabled
	# 18 et pas 9 : sa peau est a 0,05 d'albedo, et le tonemap filmique plus le
	# contraste de l'ambiance ecrasent ce qui reste. A 9 la capture ne montrait
	# qu'une ombre dans du noir — on n'y voyait meme pas ou etaient ses pieds.
	_env.ambient_light_energy = 18.0
	_env.fog_density = 0.004
	_env.adjustment_enabled = false
	var ext := Camera3D.new()
	ext.fov = 48.0
	ext.far = 600.0
	add_child(ext)
	var aim: Vector3 = g.global_position + Vector3(0.0, GiantScript.HEIGHT * high, 0.0)
	var dir: Vector3 = (g.global_transform.basis.z * 0.75 + g.global_transform.basis.x * 0.66).normalized()
	ext.global_position = aim + dir * dist + Vector3(0.0, dist * 0.10, 0.0)
	ext.look_at(aim, Vector3.UP)
	ext.make_current()
	await get_tree().create_timer(0.35).timeout
	await _shot(fname)
	car.cam.make_current()
	ext.queue_free()
	_env.ambient_light_energy = was_amb
	_env.fog_density = was_fog
	_env.adjustment_enabled = was_adj


## Sequence de captures automatiques, pour verifier le rendu sans jouer.
func _auto_capture() -> void:
	car.gear = 4          # 3e
	car.speed = 16.0
	await get_tree().create_timer(2.0).timeout
	await _shot("01_route.png")

	# Voiture de police garee sur l'accotement : on se teleporte 44 m avant elle
	# (22 echantillons), on la laisse arriver dans les phares, vue du siege ; puis
	# de l'exterieur, a cote d'elle, sous ses gyrophares et nos phares.
	if road.police_index >= 0:
		var at: Transform3D = road.sample_at(road.police_index - 22)
		if at != Transform3D():
			car.global_transform = at
			car.speed = 6.0
			await get_tree().process_frame       # la route rattrape le saut
			await get_tree().create_timer(0.8).timeout
			car.head.rotation = Vector3(0.0, deg_to_rad(-6.0), 0.0)
			await get_tree().create_timer(0.3).timeout
			await _shot("17_police_approche.png")
			var police: Node3D = road.police
			print("police : %s a %.1f m, gyrophares %s" % [
				police.visible, car.global_position.distance_to(police.global_position),
				police._beacons.size()])
			var pc := Camera3D.new()
			pc.fov = 50.0
			add_child(pc)
			pc.global_position = police.to_global(Vector3(-3.6, 1.5, 5.2))
			pc.look_at(police.to_global(Vector3(0.0, 0.9, 0.3)), Vector3.UP)
			pc.make_current()
			await get_tree().create_timer(0.5).timeout
			await _shot("18_police_exterieur.png")
			pc.queue_free()
			car.cam.make_current()
			car.head.rotation = Vector3.ZERO
			car.speed = 16.0
			await get_tree().create_timer(0.5).timeout

	# Retroviseurs : on colle le nez dessus, sinon la glace fait quinze pixels de
	# haut et on ne peut rien juger. A l'ECLAIRAGE DE NUIT, pas sous l'ambiante
	# gonflee des vues d'atelier plus bas : ce qu'on veut savoir, c'est ce que le
	# joueur voit reellement dedans.
	for m in car.cabin.mirrors:
		await _aim_at(car.to_local(m.global_position))
		car.cam.fov = 11.0
		await get_tree().create_timer(0.4).timeout
		await _shot("15_%s.png" % String(m.name).to_snake_case())
		_probe_mirror(m)
	car.cam.fov = car.fov_base
	await _aim_at(Vector3(car.SEAT_X, 1.10, -3.0))
	_probe_dither(Vector2i(820, 545), "route")
	_probe_dither(Vector2i(300, 760), "habitacle")

	# Pose figee : volant braque, embraye, main droite sur le levier.
	car.set_physics_process(false)
	# La caisse s'immobilise mais garde sa vitesse : les objets libres la
	# suivraient et partiraient tout seuls. On la remet a zero pour les poses.
	car.velocity = Vector3.ZERO
	car.steer = 0.7
	car.throttle = 0.0
	car.braking = 1.0
	car.clutch = true
	car.gear = 3          # 2e
	car.head.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(-20.0), 0.0)
	await get_tree().create_timer(0.9).timeout
	await _shot("02_poste_de_conduite.png")

	# Paquet de cigarettes en surbrillance sur le siege passager.
	car.clutch = false
	var pack: Node3D = car.interaction.grabbables[0] if not car.interaction.grabbables.is_empty() else null
	if pack != null:
		await _aim_at(car.to_local(pack.global_position))
		await get_tree().create_timer(0.6).timeout
		await _shot("10_paquet.png")

		# On le prend : le bras part le chercher, puis le ramene devant soi.
		await _click()
		await get_tree().create_timer(1.1).timeout
		# Regard un peu baisse : l'objet est tenu bas, sous la ligne du tableau de bord.
		car.head.rotation = Vector3(deg_to_rad(-28.0), 0.0, 0.0)
		await get_tree().create_timer(0.6).timeout
		await _shot("11_paquet_en_main.png")

		# Clic maintenu : le fantome montre ou il va atterrir.
		await _aim_at(Vector3(0.40, 0.948, -0.66))
		await _mouse(true)
		await get_tree().create_timer(0.5).timeout
		await _shot("12_fantome.png")
		await _mouse(false)
		await get_tree().create_timer(1.0).timeout

	# Canettes : intactes a portee de main (console, siege et planche passager),
	# ecrasees au plancher et sur la banquette.
	for obj in car.interaction.grabbables:
		print("objet %-22s pos voiture=%s" % [obj.name, car.to_local(obj.global_position).snappedf(0.001)])
	car.head.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-50.0), 0.0)
	await get_tree().create_timer(0.5).timeout
	await _shot("13_canettes_avant.png")
	car.head.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-165.0), 0.0)
	await get_tree().create_timer(0.5).timeout
	await _shot("14_canettes_arriere.png")

	# Frein a main : capture en plein geste, la main sur le levier.
	car.clutch = false
	car.steer = 0.0
	car.braking = 0.0
	car.handbrake_on = true
	car.head.rotation = Vector3(deg_to_rad(-60.0), deg_to_rad(-30.0), 0.0)
	await get_tree().create_timer(0.35).timeout
	await _shot("07_frein_a_main.png")

	# Marche arriere : feux de recul allumes, sinon on ne verrait rien derriere.
	car.handbrake_on = false
	car.gear = 0
	car.speed = -3.0

	car.head.rotation = Vector3(deg_to_rad(-6.0), deg_to_rad(-154.0), 0.0)
	await get_tree().create_timer(1.2).timeout
	await _shot("05_regard_arriere.png")

	car.head.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(158.0), 0.0)
	await get_tree().create_timer(1.2).timeout
	await _shot("06_tete_dehors.png")

	# Vue interieure eclairee : le modele Blender est illisible dans le noir.
	_env.fog_enabled = false
	_env.volumetric_fog_enabled = false
	_env.ambient_light_color = Color(1.0, 1.0, 1.0)
	_env.ambient_light_energy = 2.2
	_env.adjustment_enabled = false
	_env.background_color = Color(0.30, 0.33, 0.40)
	car.gear = 4
	car.head.rotation = Vector3.ZERO
	await get_tree().create_timer(0.7).timeout
	await _shot("08_interieur.png")
	var pack2: Node3D = car.interaction.grabbables[0] if not car.interaction.grabbables.is_empty() else null
	if pack2 != null:
		await _aim_at(car.to_local(pack2.global_position))
	await get_tree().create_timer(0.7).timeout
	await _shot("09_interieur_bas.png")

	# Vue exterieure eclairee : c'est le seul moyen de voir si la carrosserie
	# est correcte. La peinture est a 0.085 d'albedo, il faut une ambiante
	# enorme pour que la silhouette soit lisible.
	_env.ambient_light_energy = 11.0
	var ext := Camera3D.new()
	ext.fov = 42.0
	add_child(ext)
	ext.global_position = car.global_position + Vector3(4.6, 2.0, 5.4)
	ext.look_at(car.global_position + Vector3(0.0, 0.65, 0.0), Vector3.UP)
	ext.make_current()
	await get_tree().create_timer(0.3).timeout
	await _shot("03_exterieur.png")

	ext.global_position = car.global_position + Vector3(-5.6, 1.5, -3.4)
	ext.look_at(car.global_position + Vector3(0.0, 0.65, 0.0), Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await _shot("04_exterieur_avant.png")

	get_tree().quit()


## Verifie que la lune est la ou on la croit. Le piege : le disque et la lumiere
## sont deux objets differents, et rien n'empeche de les faire diverger — on
## aurait alors un clair de lune venant d'un coin de ciel vide. On mesure donc
## l'ecart entre les deux directions AVANT de regarder l'image ; puis on verifie
## qu'elle tombe dans le pare-brise, et pas derriere le pavillon.
func _moon_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	car.gear = 4
	car.speed = 14.0
	await get_tree().create_timer(1.6).timeout

	var disc: MeshInstance3D = _moon.get_node("Disc")
	var light: DirectionalLight3D = _moon.get_node("Light")
	var cam: Camera3D = car.cam
	var to_disc: Vector3 = (disc.global_position - cam.global_position).normalized()
	# +Z de la lumiere : la direction d'ou elle vient, donc la lune elle-meme.
	var from_light: Vector3 = light.global_transform.basis.z

	# Rayon apparent : on projette le centre, puis un point decale du rayon du
	# disque le long de l'axe horizontal de la camera.
	var radius: float = (disc.mesh as QuadMesh).size.x / MOON_HALO_RATIO * 0.5
	var centre := cam.unproject_position(disc.global_position)
	var bord := cam.unproject_position(
			disc.global_position + cam.global_transform.basis.x * radius)
	var vue := get_viewport().get_visible_rect()

	# L'ecart n'est pas tout a fait nul et ne peut pas l'etre : le disque est a
	# 260 m, pas a l'infini, et l'oeil du conducteur n'est pas sur le noeud Moon.
	# 1,2 m de decalage a 260 m font 0,26 degre. Au-dela de 0,5, c'est un bug.
	print("lune : ecart disque/lumiere = %.3f deg   (parallaxe de l'oeil, < 0.5)" % \
			rad_to_deg(to_disc.angle_to(from_light)))
	print("       hauteur = %.1f deg   distance = %.0f m   rayon = %.0f px" % [
			rad_to_deg(asin(to_disc.y)), cam.global_position.distance_to(disc.global_position),
			centre.distance_to(bord)])
	print("       ecran = %s   dans le champ = %s   devant = %s" % [
			centre.round(), vue.has_point(centre),
			not cam.is_position_behind(disc.global_position)])

	# Vue du siege, tete au repos : la seule qui compte, celle du joueur qui
	# roule. Viser la lune avec la tete n'apprend rien — le pavillon la cache
	# bien avant que le regard ne l'atteigne.
	car.head.rotation = Vector3.ZERO
	await get_tree().create_timer(0.6).timeout
	await _shot("19_lune_pare_brise.png")

	# Vue degagee, hors de l'habitacle : pour juger le disque et son halo seuls,
	# sans montant ni pavillon pour les couper.
	var sky := Camera3D.new()
	sky.fov = 34.0
	sky.far = 900.0
	add_child(sky)
	sky.global_position = car.global_position + Vector3(0.0, 2.2, 0.0)
	sky.look_at(disc.global_position, Vector3.UP)
	sky.make_current()
	await get_tree().create_timer(0.5).timeout
	await _shot("19_lune_ciel.png")
	sky.queue_free()
	car.cam.make_current()

	await get_tree().create_timer(0.3).timeout
	get_tree().quit()


## Fenetre de PARE-BRISE ou se lit la route : au-dessus de la planche de bord,
## entre les deux montants. C'est la seule zone dont la lisibilite compte.
##
## Elle est serree exprès. Prise plus large elle mordait sur le pare-soleil range
## (en haut) et sur le retroviseur interieur (a droite), deux pieces d'habitacle
## que le plafonnier eclaire en plein : elles faisaient a elles seules la moitie
## du "voile" mesure, et on aurait regle le reflet sur la luminosite du plastique
## qui l'entoure.
const GLARE_WIN_FROM := Vector2i(520, 340)
const GLARE_WIN_TO := Vector2i(1040, 545)
## Intensites balayees pour le calibrage. Une seule execution donne la courbe
## entiere : regler `strength` a l'oeil, une valeur par lancement, revient a
## comparer des images prises sur des routes differentes.
const GLARE_SWEEP := [0.5, 1.0, 1.5, 2.0, 2.8, 3.5, 5.0]

## Bande du BAS du pare-brise, sur toute sa largeur : c'est la que se lisent les
## reflets des objets poses sur la planche de bord. Elle s'arrete sous le
## retroviseur interieur, qui s'allume avec le plafonnier et compterait pour une
## bosse a lui tout seul.
const GLARE_BAND_FROM := Vector2i(470, 452)
const GLARE_BAND_TO := Vector2i(1450, 570)
## Une bosse doit depasser cette fraction de la plus haute de la bande, et etre a
## au moins tant de pixels de la precedente, pour compter comme un reflet
## distinct. Les copies du halo fautif tombaient a 21 et 36 px : l'ecart minimal
## est en dessous, sans quoi le banc les fusionnerait et ne verrait rien.
const PEAK_FLOOR := 0.35
const PEAK_GAP := 14


## Banc d'essai du reflet de pare-brise (windshield_glare.gd).
##
## Ce qu'on mesure n'est PAS "y a-t-il un reflet" — une capture le dirait. C'est
## CE QU'IL PREND A LA ROUTE. On lit la meme fenetre de pare-brise, plafonnier
## eteint puis allume, et on en sort la luminance moyenne et le contraste RMS.
##
## Un voile lumineux a une signature qu'on ne peut pas confondre : il fait
## MONTER la luminance et BAISSER le contraste rapporte a cette luminance. Une
## image simplement plus claire ferait monter les deux. C'est donc le troisieme
## chiffre — RMS / moyenne — qui dit si la vision empire vraiment, et il doit
## descendre.
##
## La lampe est actionnee PAR LE VRAI GESTE (visee, clic, la main qui monte au
## luminaire) et non en ecrivant `on` par en dessous : ce qui doit etre eprouve,
## c'est que le reflet suive l'interrupteur, pas qu'un uniforme fasse ce qu'on
## lui demande.
func _glare_test() -> void:
	car.gear = 4          # 3e
	car.speed = 16.0
	await get_tree().create_timer(1.8).timeout

	var dome: Node3D = car.cabin.dome_light
	if dome == null:
		print("pas de plafonnier dans ce .glb : rien a mesurer")
		get_tree().quit()
		return
	var glare: Node3D = car.cabin.glare
	print("plafonnier a %s   reflet a %s   quad %s m" % [
		dome.position.snappedf(0.001), glare.position.snappedf(0.001),
		(glare.mesh as QuadMesh).size])

	# LA VOITURE EST FIGEE, et ce n'est pas pour la pose. Les deux images
	# comparees doivent etre la MEME image a la lampe pres : en roulant, la route
	# defile de plusieurs metres entre les deux captures, le contraste change
	# tout seul, et on n'attribuerait plus rien a personne.
	car.set_physics_process(false)
	car.velocity = Vector3.ZERO
	car.throttle = 0.0
	await _aim_at(Vector3(car.SEAT_X, 1.10, -3.0))
	await get_tree().create_timer(0.6).timeout

	# --- lampe eteinte : la reference -------------------------------------
	await _dome_switch(dome, false)
	await _look_at_road()
	await _shot("30_plafonnier_eteint.png")
	var img_off := _grab()
	var off := _window_stats(img_off)

	# --- lampe allumee, meme regard, meme image ---------------------------
	await _dome_switch(dome, true)
	await _look_at_road()
	await _shot("31_plafonnier_allume.png")
	var img_on := _grab()
	var on := _window_stats(img_on)

	# CE QUE LA GLACE A A REFLETER, avant tout melange. Sans cette sonde, un
	# reflet trop pale ne se distingue pas d'une camera mal placee : les deux
	# donnent un pare-brise a peine voile, et on regle `strength` a l'aveugle
	# pendant que la camera regarde le capot.
	_probe_reflection(glare)

	print("fenetre pare-brise %s -> %s" % [GLARE_WIN_FROM, GLARE_WIN_TO])
	print("  plafonnier eteint : luminance %.4f   RMS %.4f   contraste %.4f" % off)
	print("  plafonnier allume : luminance %.4f   RMS %.4f   contraste %.4f" % on)
	print("  soit                %+6.1f %%        %+6.1f %%     %+6.1f %%" % [
		_relative(on[0], off[0]), _relative(on[1], off[1]), _relative(on[2], off[2])])

	# --- LE HALO ETALE-T-IL, OU RECOPIE-T-IL ? -----------------------------
	#
	# Un flou etale une image ; une poignee d'echantillons ecartes la RECOPIE. La
	# premiere version prenait quatre points a 11 % de la vitre : sur une canette
	# posee sur la planche de bord, ca ne faisait pas un halo, ca faisait CINQ
	# CANETTES.
	#
	# Ce qui separe les deux se mesure en un chiffre : la FINESSE DE DETAIL. Une
	# copie garde tout le detail de l'original, un flou l'efface. On isole donc
	# le halo — la difference entre le reflet complet et le meme reflet halo
	# coupe — et on compare sa finesse a celle de l'image nette. Nettement en
	# dessous : c'est un flou. Autour de 1 : ce sont des copies.
	var mat: ShaderMaterial = glare.material_override
	# NON TYPEES : un uniforme jamais assigne se relit `null`, et le remettre tel
	# quel est justement ce qui rend au shader sa valeur par defaut.
	var veil_kept = mat.get_shader_parameter("veil")
	var smear_kept = mat.get_shader_parameter("smear_gain")

	# ON NE MESURE PAS L'IMAGE, ON MESURE CE QUE LA CANETTE Y AJOUTE. Deux
	# captures ou seule la canette change : la route, la planche, le halo, les
	# traces d'essuie-glace, tout s'annule, et il ne reste dans la bande basse du
	# pare-brise que ses reflets a elle. Compter des bosses dans l'image entiere
	# ne voudrait rien dire — l'habitacle en a des dizaines, et c'est normal.
	# Ici, chaque bosse au-dela de la premiere est une canette de trop.
	#
	# La mesure se fait AMPLIFIEE : au reglage de jeu le reflet d'une canette
	# pese un niveau sur 255, et le tramage plein ecran le noie. On pousse donc
	# le reflet bien au-dessus du plancher de bruit — c'est le nombre de copies
	# qu'on compte, pas leur luminosite.
	var cans := _put_on_dash(2)
	if cans.size() < 2:
		print("  pas assez de canettes a poser : rien a compter")
	else:
		# Elles viennent d'etre deplacees : on les laisse se caler. Mesurer
		# pendant qu'elles bougent donnerait des images qui different aussi par
		# leur POSITION, et la difference compterait leurs etapes.
		await get_tree().create_timer(0.8).timeout
		mat.set_shader_parameter("strength", 8.0)
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var img_none := _grab()

		cans[0].visible = true
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var seen_one := _count_peaks(_grab(), img_none)

		# TEMOIN. Un banc qui annonce "un seul reflet" sans avoir jamais su en
		# voir deux n'annonce rien du tout : il aurait pu repondre 1 parce qu'il
		# est aveugle. On en pose donc une SECONDE, a 24 cm de la premiere, et
		# le compte doit passer a 2. Si les deux lignes disent 1, c'est la
		# mesure qu'il faut corriger, pas le reflet.
		cans[1].visible = true
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var seen_two := _count_peaks(_grab(), img_none)
		mat.set_shader_parameter("strength", glare.strength)

		print("  une canette posee a %s  -> %d reflet(s)" % [
			car.to_local(cans[0].global_position).snappedf(0.01), seen_one])
		print("  temoin, une deuxieme a 24 cm      -> %d reflet(s)  (%s)" % [
			seen_two, "la mesure sait compter" if seen_two > seen_one \
				else "MESURE AVEUGLE"])

	# --- les trois couches, cote passager ----------------------------------
	#
	# La ou une canette est posee sur la planche de bord : c'est l'objet sur
	# lequel le defaut s'etait vu. Les trois captures separent ce qui vient du
	# reflet lui-meme, du halo, et des traces d'essuie-glace — sans quoi on
	# corrige au jugé la couche qui n'y est pour rien.
	await _aim_at(Vector3(0.45, 1.02, -1.40))
	await get_tree().create_timer(0.6).timeout
	mat.set_shader_parameter("veil", 0.0)
	mat.set_shader_parameter("smear_gain", 0.0)
	await get_tree().create_timer(0.4).timeout
	await _shot("34_reflet_nu.png")
	mat.set_shader_parameter("veil", veil_kept)
	await get_tree().create_timer(0.4).timeout
	await _shot("35_reflet_halo.png")
	mat.set_shader_parameter("smear_gain", smear_kept)
	await get_tree().create_timer(0.4).timeout
	await _shot("36_reflet_complet.png")
	await _look_at_road()

	# Les canettes sortent du champ avant le calibrage. Elles sont posees DANS la
	# fenetre de mesure, et la reference `off` a ete prise sans elles : les
	# laisser la ferait compter leur propre lumiere comme du voile, et toute la
	# courbe serait decalee vers le haut.
	for c in cans:
		c.visible = false
	await get_tree().create_timer(0.4).timeout

	# --- courbe de calibrage ----------------------------------------------
	#
	# Le meme pare-brise, la meme route, la meme lampe : seule `strength` bouge.
	# C'est ce tableau qui fixe sa valeur par defaut, et il montre ce qu'on
	# achete a chaque cran — du voile contre du contraste.
	# Lue sur le NOEUD, pas sur le materiau : `get_shader_parameter` d'un
	# uniforme jamais assigne renvoie null, et le banc mourait la sans un mot.
	var kept: float = glare.strength
	print("  strength      luminance   contraste   contraste perdu")
	for s in GLARE_SWEEP:
		mat.set_shader_parameter("strength", s)
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var st := _window_stats(_grab())
		print("    %4.1f          %+5.1f %%     %.4f       %+6.1f %%" % [
			s, _relative(st[0], off[0]), st[2], _relative(st[2], off[2])])
	mat.set_shader_parameter("strength", kept)
	await get_tree().create_timer(0.3).timeout

	# --- le reflet BOUGE-T-IL avec la tete ? ------------------------------
	#
	# C'est ce qui separe un reflet d'une decalcomanie, et aucun des chiffres
	# ci-dessus ne le dirait : une texture collee sur la vitre donnerait
	# exactement le meme voile.
	#
	# La mesure se fait sur la SOUSTRACTION allume - eteint, pas sur l'image. Il
	# le faut : decaler l'oeil deplace aussi la route, les arbres et les montants,
	# et un centre de gravite lu sur l'image entiere suivrait tout ca sans qu'on
	# sache ce qui a bouge. La difference, elle, ne contient plus que ce que la
	# lampe a ajoute — le reflet, et rien d'autre.
	#
	# L'oeil se decale SANS que le regard tourne, ce que seule la voiture figee
	# permet : sinon car.gd repose la tete a sa place a chaque image.
	var seated: Vector3 = car.head.position
	var at_seat := _glare_centre(img_on, img_off)

	car.head.position = seated + Vector3(GLARE_LEAN, 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout
	await _shot("32_plafonnier_oeil_decale.png")
	var img_on2 := _grab()
	await _dome_switch(dome, false)
	await get_tree().create_timer(0.5).timeout
	var img_off2 := _grab()
	var at_lean := _glare_centre(img_on2, img_off2)
	car.head.position = seated

	print("  centre du reflet, oeil au volant      : x %.0f   y %.0f px" % at_seat)
	print("  oeil decale de %.0f cm vers le passager : x %.0f   y %.0f px" % [
		GLARE_LEAN * 100.0, at_lean[0], at_lean[1]])
	print("  parallaxe                             : %.0f px en x, %.0f px en y" % [
		absf(at_lean[0] - at_seat[0]), absf(at_lean[1] - at_seat[1])])

	await get_tree().create_timer(0.3).timeout
	get_tree().quit()


## Le regard rendu a la route, un peu plongeant : droit devant, la visee accroche
## le pare-soleil range et son bandeau d'aide s'affiche EN PLEIN DANS LA FENETRE
## de mesure. Une mesure de luminance qui inclut du texte blanc ne mesure plus
## grand-chose.
func _look_at_road() -> void:
	await _aim_at(Vector3(car.SEAT_X, 1.00, -3.0))
	await get_tree().create_timer(0.7).timeout


## Actionne le plafonnier a la main jusqu'a l'etat voulu, puis rend le regard a
## la route. Rien n'est ecrit dans `on` : on vise, on clique, la main monte.
func _dome_switch(dome: Node3D, want: bool) -> void:
	if dome.on == want:
		return
	await _aim_at(dome.position)
	await _click()
	# La main met un moment a arriver au luminaire : la bascule n'a lieu qu'une
	# fois qu'elle y est. Attendre une duree fixe mesurerait la machine.
	await _until(func(): return dome.on == want, 3.0)
	print("  geste sur le plafonnier -> %s" % ("allume" if dome.on else "eteint"))


## Un pixel sur deux dans chaque sens : 36 000 echantillons suffisent a 0,0001
## pres, et get_pixel() en GDScript coute cher.
const GLARE_STEP := 2
## De combien l'oeil se decale pour la mesure de parallaxe. Un buste qui se
## penche vers le centre de la voiture, pas un demenagement.
const GLARE_LEAN := 0.16


func _grab() -> Image:
	return get_viewport().get_texture().get_image()


## Ou est la camera du reflet de pare-brise, ce qu'elle vise, et ce qu'elle
## ramene. L'image brute est ecrite telle quelle : c'est la seule facon de voir
## si elle cadre l'habitacle ou le capot.
func _probe_reflection(glare: Node3D) -> void:
	var view := glare.get_node("View") as SubViewport
	var cam := glare.get_node("View/Eye") as Camera3D
	var img: Image = view.get_texture().get_image()
	img.save_png("user://33_reflet_brut.png")

	var sum := 0.0
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y).get_luminance()
	print("  camera du reflet a %s   vise %s   near %.2f  far %.1f  %s px" % [
		car.to_local(cam.global_position).snappedf(0.01),
		(cam.global_transform.basis * Vector3.FORWARD).snappedf(0.01),
		cam.near, cam.far, view.size])
	print("  luminance de ce qu'elle reflete : %.4f" % [
		sum / float(img.get_width() * img.get_height())])


## Luminance moyenne, ecart-type et contraste (RMS / moyenne) de la fenetre de
## pare-brise. Le troisieme est celui qui compte : c'est lui qui dit si l'image
## est devenue plus dure a lire, et non simplement plus claire.
func _window_stats(img: Image) -> Array:
	var n := 0
	var sum := 0.0
	var sum2 := 0.0
	for y in range(GLARE_WIN_FROM.y, GLARE_WIN_TO.y, GLARE_STEP):
		for x in range(GLARE_WIN_FROM.x, GLARE_WIN_TO.x, GLARE_STEP):
			var l := img.get_pixel(x, y).get_luminance()
			sum += l
			sum2 += l * l
			n += 1
	var mean := sum / float(n)
	var rms := sqrt(maxf(sum2 / float(n) - mean * mean, 0.0))
	return [mean, rms, rms / maxf(mean, 0.0001)]


## Ou se trouve le reflet, en pixels d'ecran : le centre de gravite de ce que la
## lampe a AJOUTE (allume moins eteint, negatif ecrete). Rien d'autre ne bouge
## entre les deux images, donc ce centre est celui du reflet seul.
func _glare_centre(lit: Image, dark: Image) -> Array:
	var sum := 0.0
	var mx := 0.0
	var my := 0.0
	for y in range(GLARE_WIN_FROM.y, GLARE_WIN_TO.y, GLARE_STEP):
		for x in range(GLARE_WIN_FROM.x, GLARE_WIN_TO.x, GLARE_STEP):
			var d := maxf(lit.get_pixel(x, y).get_luminance()
				- dark.get_pixel(x, y).get_luminance(), 0.0)
			sum += d
			mx += d * float(x)
			my += d * float(y)
	return [mx / maxf(sum, 0.0001), my / maxf(sum, 0.0001)]


func _relative(now: float, before: float) -> float:
	return 100.0 * (now - before) / maxf(before, 0.0001)


## Ou le banc pose la canette : sur la casquette de planche de bord, devant le
## conducteur.
##
## La hauteur se lit sur le DESSUS de la boite de cabin.gd, pas sur son centre :
## la casquette y est declaree centree a 0,845 sur 0,20 d'epaisseur — epaisse
## vers le bas, parce qu'elle est invisible et qu'une dalle mince se ferait
## traverser — donc sa face superieure est a 0,945. Posee a 0,90, la canette
## naissait DANS le solide et se faisait ejecter au plancher.
const DASH_SPOT := Vector3(-0.20, 1.00, -0.85)


## Ecart entre les deux canettes du temoin. 24 cm sur la planche donnent deux
## reflets separes de plus de cent pixels : largement au-dela de PEAK_GAP, donc
## un banc qui n'en verrait qu'un aurait un vrai probleme.
const DASH_GAP := 0.24


## Pose `count` canettes intactes sur le tableau de bord, INVISIBLES, et les
## renvoie. C'est a l'appelant de les montrer une a une.
##
## Aucune ne s'y trouve au depart : celle que car.gd fait naitre au-dessus de la
## planche passager glisse et finit au plancher, et le paquet demarre sur le
## siege. Le banc en deplace donc — c'est le geste du joueur qui a rapporte le
## defaut, et il faut le reproduire pour le mesurer.
##
## `vel` est remise a zero avec la position : la laisser telle quelle relancerait
## la canette a travers l'habitacle depuis son nouveau point de depart.
func _put_on_dash(count: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for obj in car.interaction.grabbables:
		if out.size() >= count:
			break
		var n := String(obj.name)
		if not n.begins_with("Can_") or n.ends_with("Crushed"):
			continue
		obj.position = DASH_SPOT + Vector3(DASH_GAP * out.size(), 0.0, 0.0)
		obj.vel = Vector3.ZERO
		obj.visible = false
		out.append(obj)
	return out


## Combien de bosses DISTINCTES separent deux images, dans la bande basse du
## pare-brise.
##
## Le profil est la moyenne sur la hauteur de la bande : les copies d'un halo
## sont decalees en x ET en y, et une ligne unique en manquerait la moitie ;
## projetees en x, elles comptent toutes. C'est aussi ce qui rend la mesure
## utilisable — moyenner soixante lignes enterre le tramage.
func _count_peaks(now: Image, before: Image) -> int:
	var w := GLARE_BAND_TO.x - GLARE_BAND_FROM.x
	var profile := PackedFloat32Array()
	profile.resize(w)
	for i in w:
		var x := GLARE_BAND_FROM.x + i
		var s := 0.0
		var n := 0
		for y in range(GLARE_BAND_FROM.y, GLARE_BAND_TO.y):
			s += maxf(now.get_pixel(x, y).get_luminance()
				- before.get_pixel(x, y).get_luminance(), 0.0)
			n += 1
		profile[i] = s / float(n)

	var smooth := PackedFloat32Array()
	smooth.resize(w)
	var top := 0.0
	for i in w:
		var s := 0.0
		var n := 0
		for k in range(maxi(i - 3, 0), mini(i + 4, w)):
			s += profile[k]
			n += 1
		smooth[i] = s / float(n)
		top = maxf(top, smooth[i])

	var floor_level := top * PEAK_FLOOR
	var count := 0
	var last := -PEAK_GAP * 2
	for i in range(1, w - 1):
		if smooth[i] < floor_level:
			continue
		if smooth[i] > smooth[i - 1] and smooth[i] >= smooth[i + 1] \
				and i - last >= PEAK_GAP:
			count += 1
			last = i
	return count


func _build_environment() -> void:
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.038, 0.041, 0.050)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.34, 0.45)
	env.ambient_light_energy = 0.055

	# Brouillard de distance : c'est lui qui fait 80% de l'ambiance.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.055, 0.060, 0.075)
	env.fog_light_energy = 0.7
	env.fog_density = fog_density
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0

	# Brouillard volumetrique : donne des cones de lumiere aux phares.
	env.volumetric_fog_enabled = volumetric
	env.volumetric_fog_density = 0.016
	env.volumetric_fog_albedo = Color(0.60, 0.62, 0.68)
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_anisotropy = 0.25
	env.volumetric_fog_sky_affect = 0.0

	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.95

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

	env.adjustment_enabled = true
	env.adjustment_saturation = 0.70
	env.adjustment_contrast = 1.06

	_env = env
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = env
	add_child(world)


## La lune : le disque qu'on voit et la lumiere qui en vient, portes par le meme
## noeud pour qu'ils ne puissent pas diverger. Deplacer "Moon" dans l'inspecteur
## deplace les deux ensemble.
func _build_moon() -> void:
	_moon = Node3D.new()
	_moon.name = "Moon"
	# X = -elevation : la lumiere descend vers le sol, donc la lune monte.
	# Y = 180 - azimut : a 180 elle est droit devant (la voiture part vers -Z),
	# et un azimut positif la fait glisser vers la droite du pare-brise.
	_moon.rotation_degrees = Vector3(-moon_elevation, 180.0 - moon_azimuth, 0.0)
	add_child(_moon)

	# Clair de lune : juste assez pour deviner les silhouettes dans le
	# brouillard. Pas d'ombres : a 0.05 d'energie elles seraient invisibles et
	# couteraient une passe d'ombre directionnelle par image.
	var light := DirectionalLight3D.new()
	light.name = "Light"
	light.light_color = Color(0.55, 0.64, 0.90)
	light.light_energy = moon_energy
	light.shadow_enabled = false
	_moon.add_child(light)

	# Le disque se place a l'oppose du sens d'eclairage (+Z local) : la lumiere
	# part bien de la lune qu'on voit.
	var span := 2.0 * MOON_DISTANCE * tan(deg_to_rad(moon_apparent_size) * 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * span * MOON_HALO_RATIO

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/moon.gdshader")
	mat.set_shader_parameter("disc_radius", 1.0 / MOON_HALO_RATIO)

	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	disc.mesh = quad
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0.0, 0.0, MOON_DISTANCE)
	# Le quad pivote dans le vertex shader : sa boite englobante, elle, reste
	# plate et de travers. Sans marge, la lune clignote quand on tourne la tete.
	disc.extra_cull_margin = quad.size.x
	_moon.add_child(disc)


## Tramage plein ecran. Couche 0 : il passe par-dessus la 3D mais sous le HUD
## de la voiture (couche 1), qui reste donc net et lisible.
func _build_dither_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DitherPost"
	layer.layer = 0
	add_child(layer)

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/dither_post.gdshader")

	var rect := ColorRect.new()
	rect.name = "Dither"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	layer.add_child(rect)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(900.0, 900.0)

	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	_ground.mesh = plane
	_ground.material_override = Retro.mat(Color(0.075, 0.078, 0.068), 0.96)
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.position.y = -0.04
	add_child(_ground)


# --------------------------------------------------------------------------
# L'etrangleur : ce que perdre fait a l'image
# --------------------------------------------------------------------------
#
# strangler.gd decide QUAND le joueur est pris (signal `caught`) ; ici on
# decide ce que ca fait a l'ecran — c'est main.gd qui possede la camera, le
# fondu et le redemarrage, le monstre n'a pas a les connaitre.
#
#   - "throw", voiture lancee : la camera est arrachee de la voiture, rebondit
#     sur le bitume et regarde les feux arriere s'eloigner, portiere ouverte,
#     jusqu'au noir. Le point de non-retour est le contact des mains.
#   - "strangle", voiture arretee : les mains se referment, la vision bat et
#     se resserre en quelques secondes. Celle-ci s'ANNULE : une balle pendant
#     l'etranglement le fait lacher, et on respire de nouveau. C'est toute la
#     tension du corps-a-corps — tirer pendant que l'ecran s'eteint.

## "", "throw" ou "strangle". Lu par le banc d'essai.
var doom_mode := ""
var game_over_shown := false
## Duree de l'etranglement, du premier contact au noir.
var choke_time := 4.5
var _choke := 0.0
var _over_layer: CanvasLayer
var _fade_rect: ColorRect
var _over_label: Label
var _cam_vel := Vector3.ZERO
var _cam_spin_axis := Vector3.RIGHT
var _cam_spin := 0.0
var _cam_grounded := false
var _over_t := 0.0


func _on_strangler_caught(mode: String) -> void:
	if doom_mode != "" or game_over_shown:
		return
	doom_mode = mode
	_ensure_over_ui()
	if mode == "throw":
		_start_throw()


## Une balle l'a fait lacher. Seul l'etranglement s'annule : jete, le corps
## est deja sur la route et la voiture n'a plus personne a qui revenir.
func _on_strangler_died() -> void:
	if doom_mode == "strangle" and not game_over_shown:
		doom_mode = ""
		_choke = 0.0
		if _fade_rect != null:
			_fade_rect.color.a = 0.0
		car.cam.h_offset = 0.0
		car.cam.v_offset = 0.0


func _process_doom(delta: float) -> void:
	if doom_mode == "" or game_over_shown:
		return
	if doom_mode == "strangle":
		_choke = minf(_choke + delta / choke_time, 1.0)
		# La vision BAT : le noir pulse au rythme d'un coeur qui force, et le
		# plancher de la pulsation monte — chaque battement rend un peu moins
		# de lumiere que le precedent.
		var t := Time.get_ticks_msec() * 0.001
		var pulse := 0.5 + 0.5 * sin(t * TAU * 1.4)
		_fade_rect.color.a = clampf(
			_choke * _choke * 0.75 + _choke * 0.35 * pulse, 0.0, 1.0)
		car.cam.h_offset = sin(t * 31.0) * 0.012 * _choke
		car.cam.v_offset = cos(t * 27.0) * 0.010 * _choke
		if _choke >= 1.0:
			_game_over("strangle")
	elif doom_mode == "throw":
		_throw_step(delta)


## La camera quitte la voiture. Un seul geste : elle est reparentee au monde
## avec la vitesse de la caisse plus la poussee du bras, et a partir de la
## c'est un corps qui tombe — gravite, rebond, glissade, immobilite.
func _start_throw() -> void:
	car.driverless = true
	car.interaction.process_mode = Node.PROCESS_MODE_DISABLED
	# Les retroviseurs cessent de se caler sur l'oeil : c'est car.gd qui les
	# gele (voir aim_mirrors et driverless) — vises depuis le bitume, leurs
	# frustums degenerent.
	var cam: Camera3D = car.cam
	cam.reparent(self, true)
	var side: float = road.strangler.door_side if road.strangler != null else -1.0
	var out_dir: Vector3 = car.global_transform.basis.x * side
	_cam_vel = car.velocity * 0.92 + out_dir * 3.4 + Vector3.UP * 1.3
	_cam_spin_axis = (-car.global_transform.basis.z * 0.85 + out_dir * 0.4).normalized()
	_cam_spin = 7.5
	_cam_grounded = false
	_over_t = 0.0


func _throw_step(delta: float) -> void:
	var cam: Camera3D = car.cam
	_over_t += delta
	_cam_vel += Vector3.DOWN * 9.81 * delta
	cam.global_position += _cam_vel * delta
	if not _cam_grounded:
		cam.global_rotate(_cam_spin_axis.normalized(), _cam_spin * delta)

	# Le sol. L'oeil s'arrete a 24 cm du bitume : une tete couchee dessus.
	if cam.global_position.y <= 0.24 and _cam_vel.y <= 0.0:
		cam.global_position.y = 0.24
		if absf(_cam_vel.y) > 1.6:
			_cam_vel.y = absf(_cam_vel.y) * 0.30
			_cam_vel.x *= 0.55
			_cam_vel.z *= 0.55
			_cam_spin *= 0.45
		else:
			_cam_vel.y = 0.0
			var flat := Vector2(_cam_vel.x, _cam_vel.z)
			flat = flat.move_toward(Vector2.ZERO, 10.0 * delta)
			_cam_vel.x = flat.x
			_cam_vel.z = flat.y
			_cam_spin = move_toward(_cam_spin, 0.0, 12.0 * delta)
			if flat.length() < 0.6:
				_cam_grounded = true

	# Au repos, la tete se tourne vers la seule chose qu'il reste a voir : les
	# feux arriere qui retrecissent, et la portiere restee ouverte.
	if _cam_grounded:
		var aim: Vector3 = car.global_position + Vector3.UP * 0.7
		var fwd: Vector3 = (aim - cam.global_position).normalized()
		var want := Basis.looking_at(fwd, Vector3.UP)
		# La tete est SUR le bitume, pas sur un trepied : elle reste versee.
		want = want * Basis(Vector3.FORWARD, deg_to_rad(24.0))
		var k := 1.0 - exp(-1.8 * delta)
		cam.global_transform.basis = Basis(
			Quaternion(cam.global_transform.basis).slerp(Quaternion(want), k))

	# Puis le noir, sans hate : on laisse le temps de bien voir partir.
	if _over_t > 5.0:
		_fade_rect.color.a = clampf((_over_t - 5.0) / 1.8, 0.0, 1.0)
		if _over_t > 7.2:
			_game_over("throw")


func _game_over(mode: String) -> void:
	if game_over_shown:
		return
	game_over_shown = true
	doom_mode = mode
	_fade_rect.color.a = 1.0
	_over_label.text = ("La voiture s'en va sans toi." if mode == "throw"
		else "Plus d'air.") + "\n\nEntree : recommencer"
	_over_label.visible = true


## Fondu et texte de fin, au-dessus du tramage (couche 0) et du HUD (couche 1).
func _ensure_over_ui() -> void:
	if _over_layer != null:
		return
	_over_layer = CanvasLayer.new()
	_over_layer.name = "GameOver"
	_over_layer.layer = 2
	add_child(_over_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over_layer.add_child(_fade_rect)

	_over_label = Label.new()
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_over_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over_label.add_theme_font_size_override("font_size", 22)
	_over_label.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	_over_label.visible = false
	_over_layer.add_child(_over_label)


# --------------------------------------------------------------------------
# Le sommeil et le cauchemar : la bascule entre les deux mondes
# --------------------------------------------------------------------------
#
# Le monde NORMAL est la route du soir : pas de monstres, le cycle jour/nuit
# fait son oeuvre, et la jauge de veille descend. S'endormir (sleep.gd :
# fell_asleep, emis derriere un noir complet) echange le monde : les monstres
# s'arment, l'ambiance vire au rouge sourd, le mille-pattes se met en chasse,
# et un PORTAIL se pose loin devant — la seule sortie est de ROULER jusqu'a
# lui. Le franchir reveille en sursaut ; se faire prendre par l'etrangleur
# pendant qu'on y est, c'est la fin de partie ordinaire, cauchemar ou pas.
#
# La bascule ne restaure pas des valeurs figees : elle REND l'Environment a
# daycycle (override), qui re-applique l'heure courante — l'horloge a tourne
# pendant le cauchemar, on peut s'endormir a minuit et se reveiller a l'aube.

## Ou en est le portail du cauchemar courant, en metres au-dela du point
## d'endormissement. Il s'eloigne a chaque rechute.
const PORTAL_BASE_M := 900.0
const PORTAL_MORE_M := 250.0

## Les tares du cauchemar sur la lune et le tramage — restaurees au reveil.
const MOON_TINT_NIGHT := Color(0.58, 0.70, 1.0)
const MOON_LIGHT_NIGHT := Color(0.55, 0.64, 0.90)
const MOON_TINT_BLOOD := Color(1.0, 0.42, 0.38)
const MOON_LIGHT_BLOOD := Color(0.85, 0.38, 0.36)
const DITHER_TINT_BLOOD := Color(1.04, 0.86, 0.86)


## Le monde d'une PARTIE : la route du soir, sans monstres, sommeil qui compte.
## Les bancs d'essai ne passent jamais ici — ils gardent le monde d'avant.
func _start_normal_world() -> void:
	world_mode = "normal"
	sleep_enabled = true
	road.monsters = false
	_set_centipede_hunting(false)


## Le mille-pattes chasse (cauchemar) ou dort (monde normal). PAS rewind() :
## il remet son attente a zero et la bete ressortirait a l'image suivante —
## c'est un outil de banc. On endort le PROCESSUS, et on rearme l'attente.
func _set_centipede_hunting(on: bool) -> void:
	var c = car.cabin.centipede
	if c == null:
		return
	if on:
		c.process_mode = Node.PROCESS_MODE_INHERIT
		c._wait = randf_range(6.0, 14.0)
	else:
		c.process_mode = Node.PROCESS_MODE_DISABLED


## S'endormir. Appele par sleep.fell_asleep, DERRIERE un noir complet : tout
## l'echange se fait les yeux fermes, et ils se rouvrent sur le cauchemar.
func _enter_nightmare() -> void:
	if world_mode == "nightmare":
		return
	world_mode = "nightmare"

	# L'ambiance : daycycle rend la main, le rouge s'installe.
	daycycle.override = true
	_env.background_color = Color(0.030, 0.016, 0.018)
	_env.ambient_light_color = Color(0.45, 0.26, 0.28)
	_env.ambient_light_energy = 0.062
	_env.fog_light_color = Color(0.052, 0.026, 0.028)
	_env.fog_light_energy = 0.7
	_env.fog_density = 0.045
	_env.volumetric_fog_density = 0.020
	_env.adjustment_saturation = 0.55
	_env.adjustment_contrast = 1.12
	var disc := _moon.get_node("Disc") as MeshInstance3D
	disc.visible = true
	var dmat := disc.material_override as ShaderMaterial
	dmat.set_shader_parameter("tint", MOON_TINT_BLOOD)
	dmat.set_shader_parameter("disc_energy", 2.4)
	dmat.set_shader_parameter("halo_energy", 0.7)
	var mlight := _moon.get_node("Light") as DirectionalLight3D
	mlight.light_color = MOON_LIGHT_BLOOD
	mlight.light_energy = moon_energy
	_dither_material().set_shader_parameter("tint", DITHER_TINT_BLOOD)

	# Les monstres. Le premier contact vient vite (le geant a ~500 m), le
	# portail est plus loin que lui, et l'etrangleur plus loin encore : les
	# premieres nuits, on le fuit sans le savoir — il attend les rechutes.
	road.monsters = true
	road._giant_next = road.head_index() + 250
	road._strangler_next = road.head_index() + 650
	road.set_portal(road.head_index()
		+ int((PORTAL_BASE_M + PORTAL_MORE_M * float(sleep.times_slept - 1)) / RoadScript.STEP))
	_set_centipede_hunting(true)

	# Les yeux se rouvrent sur le rouge.
	sleep.open_lids(0.9)
	car._show_flash("Tu t'es endormi")


## Le portail est franchi : reveil en sursaut sur la route du soir. La ou
## _on_strangler_died annule une etreinte, ceci annule un monde.
func _exit_nightmare() -> void:
	if world_mode != "nightmare":
		return
	world_mode = "normal"

	road.monsters = false
	road.clear_monsters()
	road.portal.sleep()
	road.portal_index = -1
	# Le mille-pattes retourne dormir — lache d'abord, s'il etait en main.
	if car.interaction.held == car.cabin.centipede:
		car.interaction.let_go()
	_set_centipede_hunting(false)

	# L'ambiance revient a l'heure qu'il est — pas a celle du coucher.
	var disc := _moon.get_node("Disc") as MeshInstance3D
	var dmat := disc.material_override as ShaderMaterial
	dmat.set_shader_parameter("tint", MOON_TINT_NIGHT)
	var mlight := _moon.get_node("Light") as DirectionalLight3D
	mlight.light_color = MOON_LIGHT_NIGHT
	_dither_material().set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
	daycycle.override = false

	# Le sursaut : la caisse encaisse, les canettes tremblent, la jauge
	# repart entamee — la pression ne se rembourse pas d'un somme.
	sleep.vigilance = 0.55
	sleep.close_lids()
	sleep.open_lids(0.6)
	car.impact(Vector3(0.0, 6.5, 1.5))
	car._show_flash("Tu te reveilles en sursaut")


func _dither_material() -> ShaderMaterial:
	return ($DitherPost/Dither as ColorRect).material as ShaderMaterial


# --------------------------------------------------------------------------
# Banc d'essai de l'etrangleur
# --------------------------------------------------------------------------

## Pose l'etrangleur sur la chaussee a `dist` metres devant la voiture, decale
## de `off` sur sa droite, tourne vers elle, et l'arme.
func _place_strangler(s: Node3D, dist: float, off: float) -> void:
	var fwd: Vector3 = -car.global_transform.basis.z
	var right: Vector3 = car.global_transform.basis.x
	var pos: Vector3 = car.global_position + fwd * dist + right * off
	pos.y = 0.0
	s.global_transform = Transform3D(
		Basis(-right, Vector3.UP, Vector3.UP.cross(right)), pos)
	s.arm(car)


## Capture exterieure cadree sur lui, memes artifices d'exposition que pour le
## geant : de nuit, une capture sans coup de pouce ne montre que du noir.
## `mount` : a quoi accrocher la camera — la voiture, quand il roule dessus,
## sinon le cadrage fuit de huit metres pendant la pose.
func _strangler_shot(s: Node3D, fname: String, dist: float, high: float,
		mount: Node3D = null) -> void:
	var was_amb: float = _env.ambient_light_energy
	var was_fog: float = _env.fog_density
	var was_adj: bool = _env.adjustment_enabled
	_env.ambient_light_energy = 14.0
	_env.fog_density = 0.004
	_env.adjustment_enabled = false
	var ext := Camera3D.new()
	ext.fov = 45.0
	ext.far = 600.0
	(mount if mount != null else self).add_child(ext)
	var aim: Vector3 = s.global_position + Vector3(0.0, high, 0.0)
	var dir: Vector3 = (s.global_transform.basis.z * 0.8
		+ s.global_transform.basis.x * 0.5).normalized()
	ext.global_position = aim + dir * dist + Vector3(0.0, dist * 0.12, 0.0)
	ext.look_at(aim, Vector3.UP)
	ext.make_current()
	await get_tree().create_timer(0.25).timeout
	await _shot(fname)
	car.cam.make_current()
	ext.queue_free()
	_env.ambient_light_energy = was_amb
	_env.fog_density = was_fog
	_env.adjustment_enabled = was_adj


## Tourne le regard du conducteur en injectant de VRAIS mouvements de souris,
## comme les autres bancs : ecrire l'angle par en dessous, la tete le rendrait
## a l'image suivante.
func _look_toward_yaw(yaw: float) -> void:
	for i in 160:
		var err: float = yaw - car.head.rotation.y
		if absf(err) < 0.03:
			break
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(clampf(-err * 260.0, -48.0, 48.0), 0.0)
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _strangler_test() -> void:
	var s = road.strangler
	var StranglerScript := preload("res://scripts/strangler.gd")
	await get_tree().create_timer(1.0).timeout

	# --- 0. la route le pose ----------------------------------------------
	# Comme pour le geant : le seul essai qui prouve le CABLAGE. On avance son
	# rendez-vous, on roule, et road.gd doit le sortir tout seul, au milieu de
	# la voie, tourne vers nous.
	print("--- la route le pose ---------------------------------------------")
	car.gear = 5
	car.speed = 26.0
	road._strangler_next = road._index0 + RoadScript.SAMPLES - 4
	var posed: bool = await _until(func(): return road.strangler_index >= 0, 12.0)
	var off := 0.0
	var facing := 0.0
	if posed:
		var at: Transform3D = road.sample_at(road.strangler_index)
		off = Vector2(s.global_position.x - at.origin.x,
			s.global_position.z - at.origin.z).length()
		var to_car: Vector3 = (car.global_position - s.global_position).normalized()
		facing = (-s.global_transform.basis.z).dot(to_car)
	print("  ELLE LE POSE      : %s   (echantillon %d, a %.2f m de l'axe, jeu maxi %.1f)" % [
		posed and off <= RoadScript.STRANGLER_JITTER + 0.01, road.strangler_index,
		off, RoadScript.STRANGLER_JITTER])
	print("  IL FAIT FACE      : %s   (produit scalaire %.2f)" % [facing > 0.7, facing])
	print("  IL ATTEND         : %s   (%s)" % [s.state == StranglerScript.ROAD, s.debug_line()])
	await _strangler_shot(s, "60_etrangleur_route.png", 6.0, 1.1)

	# La suite le place a la main.
	road._strangler_next = 1000000000
	s.sleep()
	road.strangler_index = -1
	car.speed = 0.0
	car.gear = CarScript.GEAR_N

	# --- anatomie ----------------------------------------------------------
	print("--- anatomie -----------------------------------------------------")
	var span := 2.0 * StranglerScript.ARM_REACH + 2.0 * StranglerScript.SHOULDER_HALF
	print("stature %.2f m   bras (epaule -> bout des doigts) %.2f m   envergure %.2f m" % [
		StranglerScript.HEIGHT, StranglerScript.ARM_REACH, span])
	print("  BRAS ANORMAUX   : %s   (%.2f m la ou un homme de cette taille fait ~0,88 ;"
		% [StranglerScript.ARM_REACH > 1.35, StranglerScript.ARM_REACH]
		+ " envergure %.2f pour %.2f de stature)" % [span, StranglerScript.HEIGHT])
	# Debout, bras ballants, les doigts doivent FROLER le sol sans le crever.
	# La voiture est laissee a 45 m : plus pres il ecarte les bras (la croix),
	# et on mesurerait l'envergure au lieu de la pendaison.
	_place_strangler(s, 45.0, 0.0)
	await get_tree().create_timer(1.2).timeout
	var tip_y := INF
	for i in 2:
		var w: Vector3 = s._j["wrist_" + ("l" if i == 0 else "r")]
		tip_y = minf(tip_y, w.y - (StranglerScript.PALM + StranglerScript.FINGER_1
			+ StranglerScript.FINGER_2) * 0.8)
	print("  LES DOIGTS TRAINENT : %s   (bout estime a %.2f m du sol)" % [
		tip_y < 0.22 and tip_y > -0.06, tip_y])

	# --- 1. la prise au passage -------------------------------------------
	print("--- la prise au passage ------------------------------------------")
	s.sleep()
	_place_strangler(s, 46.0, -1.0)
	car.gear = 4
	# La vitesse est TENUE pendant l'approche : lachee une fois, elle passerait
	# sous la vitesse de ralenti du rapport, le moteur calerait (README,
	# "Caler") et la voiture s'arreterait a dix metres de lui.
	var latched := false
	var shot_lights := false
	var t_app := 0.0
	while t_app < 12.0 and not latched:
		await get_tree().process_frame
		t_app += get_process_delta_time()
		if not latched:
			car.speed = maxf(car.speed, 11.0)
		if not shot_lights \
				and car.global_position.distance_to(s.global_position) < 17.0:
			shot_lights = true
			# En chemin, l'image que le joueur aura : lui, en croix, phares dessus.
			await _shot("60b_etrangleur_phares.png")
		latched = s.state == StranglerScript.CLIMBING
	print("  IL S'AGRIPPE      : %s   (%s)" % [latched, s.debug_line()])
	print("  DU BON COTE       : %s   (passe a sa droite -> flanc gauche, cote %s)" % [
		s.door_side < 0.0, "G" if s.door_side < 0.0 else "D"])

	# --- 2. l'escalade, image par image -----------------------------------
	# Deux invariants, les memes que partout : une main posee NE BOUGE PAS en
	# espace voiture, et une main ne lache que si l'autre tient (donc jamais
	# deux mains en vol).
	var drift := 0.0
	var both_flying := 0
	var anchors := [Vector3.INF, Vector3.INF]
	var reached_door := false
	var hang_shot := false
	var t := 0.0
	while t < 30.0 and not reached_door:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		car.speed = maxf(car.speed - 2.0 * dt, 6.0)   # elle ralentit, il reste
		if s.hands_flying() >= 2:
			both_flying += 1
		for i in 2:
			if s._hand_t[i] < 0.0 and s.state == StranglerScript.CLIMBING:
				var hp: Vector3 = car.to_local(s.hand_point(i))
				if anchors[i] == Vector3.INF:
					anchors[i] = hp
				else:
					drift = maxf(drift, (anchors[i] as Vector3).distance_to(hp))
			else:
				anchors[i] = Vector3.INF
		if not hang_shot and s.last_grip == "sill_front":
			hang_shot = true
			await _strangler_shot(s, "61_etrangleur_pendu.png", 3.2, 0.0, car)
		if s.state == StranglerScript.AT_DOOR:
			reached_door = true
	print("apres %.1f s : %s" % [t, s.debug_line()])
	print("  IL ARRIVE A LA PORTE : %s   (prise finale \"%s\", %d mains posees en chemin)" % [
		reached_door, s.last_grip, s.plants])
	print("  LES MAINS TIENNENT   : %s   (derive maxi d'une main posee : %.1f mm)" % [
		drift < 0.02, drift * 1000.0])
	print("  UNE SEULE EN VOL     : %s   (images a deux mains en vol : %d)" % [
		both_flying == 0, both_flying])
	# Ce que le joueur voit en tournant la tete : le crane a la vitre.
	await _look_toward_yaw(deg_to_rad(72.0))
	await _shot("61b_etrangleur_vitre.png")
	print("  LE REGARD LE TROUVE : tete a %.0f deg, son crane a y %.2f m (vitre 0,97-1,235)" % [
		rad_to_deg(car.head.rotation.y), car.to_local(s.skull_point()).y])

	# --- 3. la poignee, puis la porte -------------------------------------
	print("--- la portiere --------------------------------------------------")
	car.speed = 0.0
	car.gear = CarScript.GEAR_N
	var opened: bool = await _until(func(): return car.cabin.door_amount("L") > deg_to_rad(55.0), 12.0)
	var card: Node3D = car.cabin.find_child("DOOR_L_Card", true, false)
	var card_x := 0.0
	if card != null:
		card_x = car.to_local(card.global_position).x
	print("  IL SECOUE D'ABORD : %s   (%d secousses avant que ca cede)" % [
		s.yanks >= s.yank_count, s.yanks])
	print("  LA PORTE S'OUVRE  : %s   (%.0f degres)" % [
		opened, rad_to_deg(car.cabin.door_amount("L"))])
	print("  VERS L'EXTERIEUR  : %s   (la garniture est a x %.2f, la tole a -0,79)" % [
		card_x < -0.84, card_x])
	# La manivelle est MONTEE sur la porte : sa poignee doit etre partie avec.
	var win: Node3D = car.cabin.windows[0]
	var knob_x: float = car.to_local(win.hand_point()).x
	print("  LA MANIVELLE SUIT : %s   (poignee a x %.2f, porte fermee elle est a -0,66)" % [
		knob_x < -0.80, knob_x])
	await _shot("62_etrangleur_porte.png")

	# --- 4. l'etranglement, et la balle qui l'annule ----------------------
	print("--- l'etranglement -----------------------------------------------")
	var grabbed: bool = await _until(func(): return s.state == StranglerScript.CAUGHT, 6.0)
	print("  VOITURE ARRETEE   : %s   (mode \"%s\", attendu \"strangle\")" % [
		grabbed and s.caught_mode == "strangle", s.caught_mode])
	await get_tree().create_timer(choke_time * 0.5).timeout
	var mid_choke := _choke
	# Le regard va au visage — comme le fera n'importe quel joueur etrangle.
	var to_skull: Vector3 = car.to_local(s.skull_point()) - CarScript.HEAD_POS
	await _look_toward_yaw(atan2(-to_skull.x, -to_skull.z))
	await _shot("63_etrangleur_etreinte.png")
	# Trois balles dans le buste a bout portant, via LA CHAINE DE VISEE du
	# revolver (le groupe "shootable"), pas en appelant hit() par en dessous.
	var gun: Node3D = null
	for obj in car.interaction.grabbables:
		if obj.name == "Revolver":
			gun = obj
	var eye: Vector3 = car.cam.global_position
	var found_who: String = "-"
	var fired := 0
	var flinch_peak := 0.0
	var snap := 0.0
	for shot_i in 5:
		var aim_dir: Vector3 = (s.skull_point() - eye).normalized()
		var found: Dictionary = gun._nearest_shootable(eye, aim_dir)
		if found.is_empty():
			break
		found_who = (found["who"] as Node).name
		var skull_before: Vector3 = s.skull_point()
		(found["who"] as Node).call("hit", found["pos"], found["n"])
		fired += 1
		# La balle doit SE VOIR porter : l'encaissement monte d'un coup, et
		# le crane — pousse par le buste — bouge a l'image. Quatre images
		# suffisent, et on ne mesure pas un corps qui tombe.
		for f in 4:
			await get_tree().process_frame
			if s.state == StranglerScript.FALLING:
				break
			flinch_peak = maxf(flinch_peak, s._flinch)
			snap = maxf(snap, skull_before.distance_to(s.skull_point()))
		if shot_i == 0:
			# L'image du coup qui porte : gerbe en vol, corps qui encaisse.
			await _shot("63a_etrangleur_balle.png")
		if s.state == StranglerScript.FALLING:
			break
	print("  LA VISEE LE TROUVE : %s   (nearest_shootable -> %s)" % [
		found_who == "Strangler", found_who])
	print("  IL ENCAISSE VISIBLEMENT : %s   (encaissement %.2f au sommet, crane deplace de %.0f mm)" % [
		flinch_peak > 0.5 and snap > 0.04, flinch_peak, snap * 1000.0])
	print("  LES BALLES MARQUENT : %s   (%d tirs -> %d impacts restes, %d gouttes parties)" % [
		s.wounds == fired and s.gore > 0, fired, s.wounds, s.gore])
	print("  LES BALLES LE FONT LACHER : %s   (%s)" % [
		s.state == StranglerScript.FALLING or s.state == StranglerScript.CORPSE,
		s.debug_line()])
	await get_tree().create_timer(0.5).timeout
	print("  L'ETREINTE S'ANNULE : %s   (noir a %.2f pendant la prise, %.2f apres ; partie perdue : %s)" % [
		doom_mode == "" and not game_over_shown, mid_choke, _choke, game_over_shown])
	var landed: bool = await _until(func(): return s.state == StranglerScript.CORPSE, 8.0)
	print("  IL FINIT AU SOL   : %s   (y %.2f m)" % [landed, s.global_position.y])
	# Une balle sur le tas : elle eclabousse et marque encore — le monde ne
	# devient pas muet parce qu'il est mort — mais elle ne le reveille pas.
	var w_before: int = s.wounds
	var aim_corpse: Vector3 = (s.skull_point() - car.cam.global_position).normalized()
	var found_corpse: Dictionary = gun._nearest_shootable(
		car.cam.global_position, aim_corpse)
	if not found_corpse.is_empty():
		(found_corpse["who"] as Node).call("hit",
			found_corpse["pos"], found_corpse["n"])
	print("  LE CADAVRE ENCAISSE ENCORE : %s   (impact n. %d, et il reste en tas : %s)" % [
		s.wounds == w_before + 1 and s.state == StranglerScript.CORPSE,
		s.wounds, s.state == StranglerScript.CORPSE])
	await _look_toward_yaw(0.0)
	await _strangler_shot(s, "63b_etrangleur_abattu.png", 4.0, 0.3)

	# --- 5. voiture lancee : jete dehors ----------------------------------
	print("--- jete dehors --------------------------------------------------")
	s.sleep()
	car.cabin.set_door("L", 0.0)
	_place_strangler(s, 45.0, -0.6)
	car.gear = 6
	# Ici aussi la vitesse est TENUE — c'est elle qui doit choisir "throw" : on
	# prouve le lancer du conducteur, pas la lenteur du frein moteur.
	var relatch := false
	var doomed := false
	var t_thr := 0.0
	while t_thr < 45.0 and not doomed:
		await get_tree().process_frame
		t_thr += get_process_delta_time()
		relatch = relatch or s.state == StranglerScript.CLIMBING
		doomed = s.state == StranglerScript.CAUGHT
		if not doomed and not car.driverless:
			car.gear = 6
			car.speed = maxf(car.speed, 20.0)
	print("  IL REPREND        : %s   puis tient le conducteur : %s (mode \"%s\", attendu \"throw\")" % [
		relatch, doomed, s.caught_mode])
	var thrown: bool = await _until(func(): return car.cam.get_parent() != car.head, 4.0)
	print("  LA CAMERA SORT    : %s   (parent : %s)" % [thrown, car.cam.get_parent().name])
	print("  PLUS PERSONNE AU VOLANT : %s" % car.driverless)
	var far: bool = await _until(
		func(): return car.global_position.distance_to(car.cam.global_position) > 25.0,
		10.0)
	print("  LA VOITURE S'EN VA : %s   (a %.0f m quand l'ecran s'eteint)" % [
		far, car.global_position.distance_to(car.cam.global_position)])
	var over: bool = await _until(func(): return game_over_shown, 10.0)
	print("  PARTIE PERDUE     : %s   (\"%s\")" % [over, doom_mode])
	await _shot("64_etrangleur_jete.png")

	get_tree().quit()


# --------------------------------------------------------------------------
# Banc d'essai du cycle jour/nuit
# --------------------------------------------------------------------------

func _color_diff(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


## Le cycle se prouve en trois temps : la nuit de reference est INTACTE (au
## bit pres — tous les autres bancs tournent geles dessus), le jour se leve
## vraiment (et il est bleme, pas solaire), et rien ne saute — l'ambiance est
## une fonction CONTINUE de l'heure, pas une suite de decors.
func _day_test() -> void:
	await get_tree().create_timer(0.8).timeout
	# Pas de monstres pendant qu'on photographie le ciel.
	road._giant_next = 1000000000
	road._strangler_next = 1000000000

	# --- 1. la nuit de reference ------------------------------------------
	print("--- la nuit de reference -----------------------------------------")
	daycycle.set_hour(23.0)
	await get_tree().process_frame
	var d0 := 0.0
	d0 = maxf(d0, _color_diff(_env.background_color, Color(0.038, 0.041, 0.050)))
	d0 = maxf(d0, _color_diff(_env.ambient_light_color, Color(0.30, 0.34, 0.45)))
	d0 = maxf(d0, absf(_env.ambient_light_energy - 0.055))
	d0 = maxf(d0, _color_diff(_env.fog_light_color, Color(0.055, 0.060, 0.075)))
	d0 = maxf(d0, absf(_env.fog_density - fog_density))
	d0 = maxf(d0, absf(_env.adjustment_saturation - 0.70))
	d0 = maxf(d0, absf(_env.adjustment_contrast - 1.06))
	var moon_light := _moon.get_node("Light") as DirectionalLight3D
	var moon_disc := _moon.get_node("Disc") as MeshInstance3D
	var sun_light := daycycle._sun_light as DirectionalLight3D
	print("  LA NUIT EST INTACTE : %s   (plus grand ecart a _build_environment : %.6f)" % [
		d0 < 0.000001, d0])
	print("  LA LUNE Y EST       : %s   (lumiere %.2f, attendu %.2f ; disque visible %s)" % [
		absf(moon_light.light_energy - moon_energy) < 0.001 and moon_disc.visible,
		moon_light.light_energy, moon_energy, moon_disc.visible])
	print("  LE SOLEIL S'Y TAIT  : %s   (energie %.2f)" % [
		sun_light.light_energy < 0.001, sun_light.light_energy])

	# --- 2. le tour du cadran ---------------------------------------------
	print("--- le tour du cadran --------------------------------------------")
	for h in [3.0, 6.3, 8.5, 13.0, 16.0, 19.0, 21.5]:
		daycycle.set_hour(h)
		await get_tree().process_frame
		var bgl := _env.background_color.get_luminance()
		print("  %5s  ciel %.3f  ambiante %.3f  brouillard %.4f  soleil %.2f  lune %.3f  nuitosite %.2f" % [
			daycycle.clock_text(), bgl, _env.ambient_light_energy,
			_env.fog_density, sun_light.light_energy,
			moon_light.light_energy, daycycle.night_amount()])
	daycycle.set_hour(13.0)
	await get_tree().process_frame
	var noon_ok := sun_light.light_energy >= 0.7 \
		and _env.ambient_light_energy >= 0.055 * 6.0 \
		and _env.fog_density <= fog_density * 0.5 \
		and moon_light.light_energy < 0.001 and not moon_disc.visible
	print("  LE JOUR SE LEVE     : %s   (a 13 h : soleil %.2f, ambiante x%.1f, brouillard %.4f, lune eteinte %s)" % [
		noon_ok, sun_light.light_energy,
		_env.ambient_light_energy / 0.055, _env.fog_density,
		not moon_disc.visible])
	daycycle.set_hour(6.3)
	await get_tree().process_frame
	var dawn_warm := sun_light.light_color.r > sun_light.light_color.b + 0.3
	print("  L'AUBE EST CHAUDE   : %s   (soleil r %.2f / b %.2f, eleve de %.0f deg)" % [
		dawn_warm, sun_light.light_color.r, sun_light.light_color.b,
		-daycycle._sun.rotation_degrees.x])

	# --- 3. la continuite -------------------------------------------------
	# L'ambiance est balayee minute par minute sur 24 h : le plus grand saut
	# entre deux minutes consecutives doit rester sous le seuil de perception.
	var max_lum := 0.0
	var max_sun := 0.0
	var max_fog := 0.0
	var max_amb := 0.0
	daycycle.set_hour(0.0)
	var prev_lum := _env.background_color.get_luminance()
	var prev_sun := sun_light.light_energy
	var prev_fog := _env.fog_density
	var prev_amb := _env.ambient_light_energy
	for i in 1440:
		daycycle.set_hour(float(i + 1) / 60.0)
		max_lum = maxf(max_lum, absf(_env.background_color.get_luminance() - prev_lum))
		max_sun = maxf(max_sun, absf(sun_light.light_energy - prev_sun))
		max_fog = maxf(max_fog, absf(_env.fog_density - prev_fog))
		max_amb = maxf(max_amb, absf(_env.ambient_light_energy - prev_amb))
		prev_lum = _env.background_color.get_luminance()
		prev_sun = sun_light.light_energy
		prev_fog = _env.fog_density
		prev_amb = _env.ambient_light_energy
	print("  RIEN NE SAUTE       : %s   (par minute de jeu : ciel %.4f, soleil %.4f, brouillard %.5f, ambiante %.4f)" % [
		max_lum < 0.010 and max_sun < 0.020 and max_fog < 0.0010 and max_amb < 0.020,
		max_lum, max_sun, max_fog, max_amb])

	# --- 4. l'horloge ------------------------------------------------------
	print("--- l'horloge ----------------------------------------------------")
	daycycle.set_hour(23.0)
	daycycle.frozen = false
	var t0: float = daycycle.time_h
	await get_tree().create_timer(2.0).timeout
	daycycle.frozen = true
	var gained: float = fmod(daycycle.time_h - t0 + 24.0, 24.0) * 60.0   # minutes de jeu
	var expected: float = 2.0 * 1440.0 / daycycle.day_seconds
	print("  ELLE TOURNE         : %s   (%.2f min de jeu en 2 s reelles, attendu %.2f)" % [
		absf(gained - expected) < expected * 0.35, gained, expected])
	var t1: float = daycycle.time_h
	await get_tree().create_timer(0.5).timeout
	print("  ELLE SE GELE        : %s   (heure inchangee : %s)" % [
		is_equal_approx(daycycle.time_h, t1), daycycle.clock_text()])

	# --- 5. les images -----------------------------------------------------
	for shot_def in [[6.5, "70_aube.png"], [13.0, "71_jour_bleme.png"],
			[19.5, "72_crepuscule.png"]]:
		daycycle.set_hour(shot_def[0])
		await get_tree().process_frame
		await get_tree().process_frame
		await _shot(shot_def[1])
	daycycle.set_hour(23.0)

	get_tree().quit()


# --------------------------------------------------------------------------
# Banc d'essai du sommeil et du cauchemar
# --------------------------------------------------------------------------

## Trois choses a prouver : la jauge suit SA formule (pas une deuxieme ecrite
## dans le banc), chaque facteur pese ce qu'il annonce, et la bascule est un
## aller-retour COMPLET — le monde du cauchemar s'installe entierement, et le
## reveil rend exactement la nuit du cycle, monstres eteints.
func _sleep_test() -> void:
	await get_tree().create_timer(0.8).timeout
	# Le monde d'une partie, pas celui des bancs : monstres coupes, mille-
	# pattes endormi, sommeil actif.
	_start_normal_world()
	Engine.time_scale = 4.0

	print("--- la jauge suit sa formule -------------------------------------")
	sleep.vigilance = 1.0
	var integ := 0.0
	var t := 0.0
	while t < 60.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		integ += sleep.drain_rate() * dt
	var drop: float = 1.0 - sleep.vigilance
	print("  ELLE SUIT SA FORMULE : %s   (perdu %.3f en 60 s de jeu a l'arret, integrale annoncee %.3f)" % [
		absf(drop - integ) < 0.02, drop, integ])

	print("--- les facteurs -------------------------------------------------")
	# A l'arret a 23 h : nuit profonde, torpeur de la lenteur, et la monotonie
	# a eu ses dix secondes depuis longtemps.
	var sl: float = sleep._sleepers()
	print("  LA NUIT ENDORT       : %s   (x%.2f = 1,5 circadien x 1,3 lenteur x 1,6 monotonie)" % [
		absf(sl - 1.5 * 1.3 * 1.6) < 0.03, sl])
	daycycle.set_hour(13.0)
	var sl_day: float = sleep._sleepers()
	daycycle.set_hour(23.0)
	print("  LE JOUR TIENT MIEUX  : %s   (a 13 h : x%.2f, le circadien tombe a 0,8)" % [
		absf(sl_day - 0.8 * 1.3 * 1.6) < 0.03, sl_day])
	for w in car.cabin.windows:
		w.open = 1.0
	var rem: float = sleep._remedies()
	print("  LES VITRES REVEILLENT : %s   (remedes x%.2f, attendu 0,70)" % [
		absf(rem - 0.7) < 0.005, rem])
	sleep.radio_factor = 0.55
	car.speed = 26.0
	var rem2: float = sleep._remedies()
	car.speed = 0.0
	sleep.radio_factor = 1.0
	print("  LE PLANCHER TIENT    : %s   (radio 0,55 x vitres 0,7 x vitesse 0,75 = 0,29 -> x%.2f)" % [
		absf(rem2 - maxf(0.55 * 0.7 * 0.75, 0.25)) < 0.005, rem2])
	for w in car.cabin.windows:
		w.open = 0.0
	sleep.vigilance = 0.5
	sleep.drink_boost("nosleep")
	var v1: float = sleep.vigilance
	sleep.drink_boost("nosleep")
	var v2: float = sleep.vigilance
	print("  LA DEUXIEME REND MOINS : %s   (+%.2f puis +%.2f — la dette de cafeine)" % [
		absf(v1 - 0.78) < 0.005 and absf((v2 - v1) - 0.28 * 0.6) < 0.005,
		v1 - 0.5, v2 - v1])

	print("--- les paupieres ------------------------------------------------")
	var peak := 0.0
	var vmin := 0.0
	var lid_shot := false
	var tt := 0.0
	while tt < 14.0:
		await get_tree().process_frame
		tt += get_process_delta_time()
		sleep.vigilance = 0.18            # tenue la : on mesure, on ne meurt pas
		peak = maxf(peak, sleep.lid_alpha())
		vmin = minf(vmin, car.cam.v_offset)
		if not lid_shot and sleep.lid_alpha() > 0.5:
			lid_shot = true
			await _shot("73_paupieres.png")
	print("  ELLES TOMBENT        : %s   (noir maxi %.2f par vague, la tete pique de %.0f mm)" % [
		peak > 0.5 and vmin < -0.01, peak, -vmin * 1000.0])

	print("--- l'endormissement ---------------------------------------------")
	var h0: int = road.head_index()
	sleep.vigilance = 0.01
	await sleep.fell_asleep
	await get_tree().process_frame
	var dtint: Color = _dither_material().get_shader_parameter("tint")
	var dmat := (_moon.get_node("Disc") as MeshInstance3D).material_override as ShaderMaterial
	var mtint: Color = dmat.get_shader_parameter("tint")
	print("  LE MONDE BASCULE     : %s   (mode %s, monstres %s, brouillard %.3f)" % [
		world_mode == "nightmare" and road.monsters
		and absf(_env.fog_density - 0.045) < 0.0001,
		world_mode, road.monsters, _env.fog_density])
	print("  LE ROUGE S'INSTALLE  : %s   (tramage r %.2f / b %.2f, lune r %.2f / b %.2f)" % [
		dtint.r > dtint.b and mtint.r > mtint.b, dtint.r, dtint.b, mtint.r, mtint.b])
	print("  LE MILLE-PATTES CHASSE : %s   (attente %.1f s)" % [
		car.cabin.centipede.process_mode == Node.PROCESS_MODE_INHERIT,
		car.cabin.centipede._wait])
	var expect_portal: int = h0 + int(PORTAL_BASE_M / RoadScript.STEP)
	print("  LE PORTAIL EST PRIS  : %s   (demande a l'echantillon %d, attendu %d +-3, rechute n. %d)" % [
		absi(road._portal_at - expect_portal) <= 3, road._portal_at,
		expect_portal, sleep.times_slept])
	await get_tree().create_timer(1.2).timeout
	await _shot("74_cauchemar.png")

	print("--- le portail ---------------------------------------------------")
	# La traversee mesure LE PORTAIL, pas les monstres : on les desarme — leur
	# banc a eux, c'est gianttest et stranglertest. Le vrai cauchemar garde
	# tout le monde, et un geant en travers de la voie s'y contourne au volant,
	# ce qu'un banc qui tient une ligne droite ne sait pas faire.
	road._giant_next = 1000000000
	road._strangler_next = 1000000000
	if not road.giant.asleep():
		road.giant.sleep()
	road.giant_index = -1
	car.gear = 5
	var shot_portal := false
	var t2 := 0.0
	while t2 < 90.0 and world_mode == "nightmare":
		await get_tree().process_frame
		t2 += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		if not shot_portal and road.portal.active \
				and car.global_position.distance_to(road.portal.global_position) < 160.0:
			# L'image du voile dans les phares : on s'arrete pour la prendre —
			# les grandes enjambees d'images du banc sous charge sautaient la
			# fenetre de distance quand on la prenait en roulant.
			shot_portal = true
			car.speed = 0.0
			await get_tree().process_frame
			await _shot("75_portail.png")
	print("  ON EN SORT EN ROULANT : %s   (reveille apres %.0f s de jeu, portail rendormi %s)" % [
		world_mode == "normal", t2, not road.portal.active])
	car.speed = 0.0
	car.gear = CarScript.GEAR_N
	await get_tree().create_timer(0.8).timeout
	var dback := 0.0
	dback = maxf(dback, absf(_env.fog_density - fog_density))
	dback = maxf(dback, _color_diff(_env.ambient_light_color, Color(0.30, 0.34, 0.45)))
	dback = maxf(dback, absf(_env.adjustment_saturation - 0.70))
	dback = maxf(dback, _color_diff(_env.fog_light_color, Color(0.055, 0.060, 0.075)))
	var dtint2: Color = _dither_material().get_shader_parameter("tint")
	var mtint2: Color = dmat.get_shader_parameter("tint")
	print("  LA NUIT REVIENT      : %s   (ecart ambiance %.6f, tramage blanc %s, lune bleue %s)" % [
		dback < 0.000001 and dtint2.r == 1.0 and mtint2.b > mtint2.r,
		dback, dtint2.r == 1.0 and dtint2.b == 1.0, mtint2.b > mtint2.r])
	print("  LES MONSTRES SE TAISENT : %s   (geant %s, etrangleur %s, mille-pattes coupe %s)" % [
		road.giant.asleep() and road.strangler.asleep()
		and car.cabin.centipede.process_mode == Node.PROCESS_MODE_DISABLED,
		road.giant.asleep(), road.strangler.asleep(),
		car.cabin.centipede.process_mode == Node.PROCESS_MODE_DISABLED])
	print("  LA JAUGE REPART ENTAMEE : %s   (vigilance %.2f, attendu ~0,55)" % [
		absf(sleep.vigilance - 0.55) < 0.10, sleep.vigilance])

	Engine.time_scale = 1.0
	get_tree().quit()
