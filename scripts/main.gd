extends Node3D
##
## Point d'entree du prototype.
## Construit l'ambiance de nuit, la route infinie et la voiture.
##

const CarScript := preload("res://scripts/car.gd")
const Bench := preload("res://scripts/bench.gd")
const RoadScript := preload("res://scripts/road.gd")
const DayCycleScript := preload("res://scripts/daycycle.gd")
const SleepScript := preload("res://scripts/sleep.gd")
const MapScript := preload("res://scripts/map.gd")
const TaxiScript := preload("res://scripts/taxi.gd")
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
## Le metier : offres, courses, argent, avis (taxi.gd). Dormant dans les
## bancs — seul le jeu reel (et faretest) branche le standard.
var taxi
## Ou l'on est sur le graphe (map.gd) : {at, to, start_g, route}. Vide hors
## partie. Le suivi vit ici — c'est le monde ; le taxi le consulte et y pose
## l'itineraire de ses clients.
var nav := {}
var _ground: MeshInstance3D
var _moon: Node3D
var _env: Environment
var _auto_shot := -1
## Charge a la premiere question d'un banc, jamais en jeu. Voir _mesh_probe().
var _mesh_cache


func _ready() -> void:
	Bench.capture()
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
	# Le graphe : la route annonce villes et bifurcations, la navigation suit.
	road.town_reached.connect(_on_town_reached)
	road.fork_committed.connect(_on_fork_committed)

	# La jauge de veille. Elle previent quand tout se ferme ; la bascule vers
	# le cauchemar se joue ici, ou vivent l'ecran, l'ambiance et la route.
	sleep = SleepScript.new()
	sleep.name = "Sleep"
	sleep.car = car
	sleep.daycycle = daycycle
	add_child(sleep)
	sleep.fell_asleep.connect(_enter_nightmare)

	# Le metier. Il ecoute la route (villes) et le sommeil (annulations) tout
	# seul ; son standard ne sonne que si enabled — le jeu reel le leve.
	taxi = TaxiScript.new()
	taxi.name = "Taxi"
	taxi.car = car
	taxi.road = road
	add_child(taxi)

	# Les bancs et les captures supposent la nuit de reference : le cycle est
	# gele a 23 h — l'image d'avant le cycle, au bit pres, puisque la nuit est
	# photographiee sur l'Environment. daytest le manoeuvre lui-meme.
	if not OS.get_cmdline_user_args().is_empty():
		daycycle.frozen = true
		daycycle.set_hour(23.0)
	else:
		# Une PARTIE : le monde normal — pas de monstres sur la route du
		# soir, le mille-pattes dort, le sommeil compte, le standard sonne.
		_start_normal_world()
		taxi.enabled = true

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
	elif "drinktest" in OS.get_cmdline_user_args():
		_drink_test()
	elif "radiotest" in OS.get_cmdline_user_args():
		_radio_test()
	elif "phonetest" in OS.get_cmdline_user_args():
		_phone_test()
	elif "maptest" in OS.get_cmdline_user_args():
		_map_test()
	elif "plantest" in OS.get_cmdline_user_args():
		_plan_test()
	elif "rubantest" in OS.get_cmdline_user_args():
		_ruban_test()
	elif "villetest" in OS.get_cmdline_user_args():
		_ville_test()
	elif "faretest" in OS.get_cmdline_user_args():
		_fare_test()


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
		Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
	Bench.capture()
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
## Elle est serree expres. Prise plus large elle mordait sur le pare-soleil range
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
	# corrige au juge la couche qui n'y est pour rien.
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


## Le monde d'une PARTIE : la route du soir, sans monstres, sommeil qui
## compte, et la nuit commence quelque part sur la carte — on quitte
## Saint-Elme vers Corbeny, la premiere arete du graphe.
## Les bancs d'essai ne passent jamais ici — ils gardent le monde d'avant.
func _start_normal_world() -> void:
	world_mode = "normal"
	sleep_enabled = true
	road.monsters = false
	_set_centipede_hunting(false)
	_nav_begin("Saint-Elme", "Corbeny")


# --------------------------------------------------------------------------
# La navigation : le graphe (map.gd) traduit en programme de route
# --------------------------------------------------------------------------
#
# La carte est un graphe METRIQUE : le ruban serpente comme il veut, seules
# les longueurs d'aretes sont honorees. La navigation chaine les demandes :
# une ville au bout de l'arete courante ; en ville, s'il y a deux sorties,
# un Y un peu plus loin — et le cote que prend la voiture choisit l'arete.
# Le suivi vit ici, c'est le monde ; le taxi (taxi.gd) le consulte, et pose
# dans nav["route"] l'itineraire de ses clients — les Y le suivent.

## Ce qu'on DEMANDE a road.gd pour le Y, en metres depuis le panneau du bourg.
## CE N'EST PAS OU IL TOMBE, et le commentaire d'avant le promettait : la
## demande est MORTE, toujours. program_fork (road.gd:608-615) plafonne au
## premier echantillon a naitre plus les 90 m du panneau du Y — releve au banc,
## demande 551, obtenu 674 : 366 m devant la voiture au lieu de 120. La
## position vraie se lit dans road.fork_index(), et c'est la seule qui vaille
## si l'on doit compter a partir du Y.
##
## La metrique d'arete, elle, ne se compte plus d'ici du tout : voir
## _on_fork_committed, ou cette constante coutait +300 m sur une arete de
## 1 100 (releve au banc, deux lancements : +302 et +300).
const FORK_AFTER_TOWN_M := 120.0

func _nav_begin(from: String, to: String) -> void:
	nav = {"at": from, "to": to, "start_g": road.head_index(), "route": []}
	road.program_town(nav["start_g"]
		+ int(MapScript.edge_length(from, to) / RoadScript.STEP), to)


func _on_town_reached(id: String) -> void:
	if nav.is_empty():
		return
	# DANS LE ROUGE, LA CARTE N'AVANCE PAS. En theorie cette garde ne sert
	# jamais : suspend_town() a rendu _town_g des l'endormissement, et road.gd
	# n'emet town_reached que sur un _town_g >= 0. Elle est la pour le jour ou
	# une ville serait programmee autrement — un panneau franchi dans le
	# cauchemar programmerait la SUIVANTE, et le reveil en trouverait deux.
	if world_mode == "nightmare":
		return
	var from: String = nav["at"]
	nav["at"] = id
	# Les sorties, moins celle d'ou l'on vient : sur cette carte il en reste
	# une ou deux — jamais plus, le degre est borne a 3.
	var outs: Array = MapScript.neighbors(id).filter(func(t): return t != from)
	if outs.is_empty():
		outs = [from]                  # cul-de-sac : on repartira d'ou l'on vient
	if outs.size() == 1:
		nav["to"] = outs[0]
		nav["start_g"] = road.head_index()
		road.program_town(nav["start_g"]
			+ int(MapScript.edge_length(id, outs[0]) / RoadScript.STEP), outs[0])
	else:
		# Un Y, un peu apres le bourg. Le cote VIVANT suit l'itineraire GPS
		# s'il en reste un ; sinon la gauche, et le volant decidera.
		var main_side := "left"
		var route: Array = nav["route"]
		if route.size() > 1 and route[0] == id and outs.has(route[1]):
			main_side = "left" if outs[0] == route[1] else "right"
		nav["to"] = outs[0] if main_side == "left" else outs[1]
		nav["start_g"] = road.head_index()
		road.program_fork(road.head_index()
			+ int(FORK_AFTER_TOWN_M / RoadScript.STEP), outs[0], outs[1], main_side)


func _on_fork_committed(_side: String, id: String) -> void:
	if nav.is_empty():
		return
	nav["to"] = id
	# L'arete se mesure DE PANNEAU A PANNEAU — c'est le seul contrat que
	# map.gd passe au monde, et c'est celui que le prix de course et le
	# bandeau du telephone recitent. La ville suivante tombe donc a
	# nav["start_g"] + la longueur annoncee, et le Y n'entre pas dans le
	# calcul : il est dans l'arete, pas avant elle. Meme expression que la
	# branche a une sortie, deux ecrans plus haut.
	#
	# CE QU'ON PAYAIT AVANT, mesure au banc, meme graine : on repartait de
	# head_index() — deja ~210 echantillons apres le panneau, le verdict du Y
	# tombe la — en ne retirant que les 120 m d'une constante qui ne decrivait
	# rien. Le bout deja roule etait donc compte deux fois moins un cinquieme.
	# Releve par le banc du bas, ancienne formule remise sur une copie :
	#   Corbeny > Malassis  : 1 100 annonces, 1 402 roules, +302 m (+27 %)
	#   Malassis > Peyrelade: 1 350 annonces, 1 624 roules, +274 m (+20 %)
	# (le plan, PLAN_VILLES.md:241-242, en avait releve +314 et +272 : la
	# granularite de l'image bouge le premier chiffre d'une douzaine de metres,
	# l'ordre de grandeur ne bouge pas.)
	#
	# Ce que ces 300 m coutaient au joueur : ils n'etaient PAS payes (la course
	# se facture sur MapScript.path_length, taxi.gd:212-213, donc ~0,27 EUR au
	# bareme de 0,90 EUR/km) ; nav_progress() saturait a 1,0 et le bandeau du
	# telephone affichait "Vers X — 0 m" pendant tout ce temps ; et une arete
	# annoncee 1 100 m en demandait 1 400 de vigilance et d'essence.
	#
	# nav["start_g"] survit a l'echange des rubans : _swap_to_branch
	# (road.gd:663-684) repose _index0 = _fork_g + 1 + start (road.gd:672),
	# donc l'index global CONTINUE — a un pas pres, et le pas fait deux metres.
	# Verifie au banc : sur Malassis > Peyrelade, prise PAR LE BRIN MORT, la
	# derive tient entre +0 et +8 m sur onze lancements (elle valait +272).
	var g: int = nav["start_g"] \
		+ int(MapScript.edge_length(nav["at"], id) / RoadScript.STEP)
	# Le filet, et il ne mord sur aucune arete de cette carte : la plus courte
	# qui suive un Y fait 1 100 m — Corbeny > Malassis, 550 echantillons —
	# quand le verdict du Y tombe vers +210 et que le filet demande +138.
	# Il vise le PREMIER ECHANTILLON A NAITRE et pas un de moins, parce
	# que road.gd:330 arme la ville sur une egalite exacte (g == _town_g) : une
	# ville posee dans le deja-bati ne s'armerait JAMAIS, et town_reached
	# partirait quand meme — le joueur traverserait un panneau qui n'existe pas.
	#
	# LE ROUGE NE PROGRAMME RIEN. Un Y se tranche aussi bien endormi qu'eveille
	# (le volant repond, le ruban bifurque), et la comptabilite ci-dessus doit
	# donc suivre — mais poser une ville dans le cauchemar la ferait naitre au
	# milieu du monde rouge, ce que suspend_town vient justement d'empecher.
	# _nav_resume la reposera au reveil, sur nav["to"] mis a jour ici.
	if world_mode != "nightmare":
		road.program_town(maxi(g, road.head_index()
			+ RoadScript.SAMPLES - RoadScript.BEHIND), id)
	# L'itineraire GPS avance ou se recalcule : se tromper d'embranchement ne
	# perd personne, la carte recompte.
	var route: Array = nav["route"]
	if not route.is_empty():
		if route.size() > 1 and route[1] == id:
			route.remove_at(0)
		else:
			nav["route"] = MapScript.path(id, route.back())


## La progression sur l'arete courante, 0..1 — l'ecran GPS la dessine.
func nav_progress() -> float:
	if nav.is_empty():
		return 0.0
	var len_m: float = MapScript.edge_length(nav["at"], nav["to"])
	if len_m <= 0.0:
		return 0.0
	return clampf(float(road.head_index() - nav["start_g"]) * RoadScript.STEP / len_m,
		0.0, 1.0)


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

	# LA CARTE N'A PLUS COURS. road.suspend_town() rend _town_g au rouge — la
	# ville PROMISE ne viendra pas — et noircit celle qui est deja ARMEE.
	# CE QUE C'ETAIT AVANT, ET C'ETAIT LA QUATRIEME PROMESSE DU J3 : personne
	# n'appelait suspend_town(), un grep n'en rendait que sa definition. La
	# ville du cauchemar etait donc une ville ORDINAIRE — fenetres allumees,
	# lampadaires, panneaux clairs, au milieu du monde rouge —, et s'endormir
	# 300 m avant Corbeny faisait NAITRE ET S'ALLUMER Corbeny dedans, parce que
	# _town_g survivait au basculement. La reprise est dans _nav_resume.
	#road.suspend_town()

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
	# La station derive : la porteuse n'est plus tout a fait a sa place.
	if car.radio != null:
		car.radio.set_detuned(true)

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
	if car.radio != null:
		car.radio.set_detuned(false)
	daycycle.override = false

	# Le sursaut : la caisse encaisse, les canettes tremblent, la jauge
	# repart entamee — la pression ne se rembourse pas d'un somme.
	sleep.vigilance = 0.55
	sleep.close_lids()
	sleep.open_lids(0.6)
	car.impact(Vector3(0.0, 6.5, 1.5))
	car._show_flash("Tu te reveilles en sursaut")
	#_nav_resume()


## LE REVEIL REND LA CARTE. _enter_nightmare a rendu _town_g au rouge : sans
## ceci, la ville visee ne viendrait JAMAIS et la nuit continuerait sur une
## nationale sans panneau — la course en cours n'aurait plus de destination.
##
## LA FORMULE EST CELLE DU PLAN, et son elegance est qu'elle ne fait RIEN dans
## le cas ordinaire : head + reste = head + (longueur - (head - depart) x STEP)
## / STEP = depart + longueur / STEP, c'est-a-dire l'echantillon exact que
## _nav_begin ou _on_fork_committed avait pose. Un aller-retour dans le rouge
## remet donc la ville a sa place au pas pres, et le banc le mesure.
##
## LE FILET, LUI, MORD POUR DE VRAI ICI — au contraire de celui de
## _on_fork_committed, qui ne mord sur aucune arete de la carte. On dort a
## 25 m/s pendant des dizaines de secondes : la ville visee est souvent DEJA
## DERRIERE au reveil, nav_progress() sature a 1,0 et la formule rend
## head_index(). Or road.gd arme sur une egalite exacte (g == _town_g) et rend
## town_reached des que head_index() >= _town_g : une ville posee dans le
## deja-bati ne s'armerait jamais et le joueur "arriverait" a un bourg dont il
## n'aurait vu ni le panneau ni une seule fenetre. On la repousse donc au
## premier echantillon a naitre — 138 echantillons, 276 m devant —, et ce que
## ca coute est honnete : l'arete mesure plus long que ce que la carte annonce,
## exactement de ce qu'on a roule endormi. Dans le rouge, la navigation n'a
## plus cours ; au reveil, elle reprend ou l'on est, pas ou l'on aurait du etre.
func _nav_resume() -> void:
	# La ville qui a traverse le rouge se rallume. road.gd n'a pas de fonction
	# pour ca — suspend_town() est un aller simple —, donc on le fait d'ici,
	# derriere le meme has_method que road.gd s'impose. Sur une ville deja
	# rangee (sleep() l'a eteinte pendant qu'on dormait) l'appel est sans
	# effet : _surf_glow vaut -1 et _light_mast ne porte que des -1.
	var t = road.town
	if t != null and t.has_method("set_dark"):
		t.set_dark(false)
	if nav.is_empty():
		return
	var left_m: float = MapScript.edge_length(nav["at"], nav["to"]) \
		* (1.0 - nav_progress())
	road.program_town(maxi(
		road.head_index() + int(left_m / RoadScript.STEP),
		road.head_index() + RoadScript.SAMPLES - RoadScript.BEHIND), nav["to"])


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


# --------------------------------------------------------------------------
# Banc d'essai : boire
# --------------------------------------------------------------------------

## La PRISE d'une canette est l'affaire de packtest (vrais clics, vraie
## visee) ; ce banc-ci teste le GESTE de boire : le clic droit maintenu, la
## canette qui vient a la bouche et bascule, l'effet sur la jauge, la
## canette qui s'ecrase, et la dette de cafeine. L'entree en main passe par
## le chemin court du banc (_pick_up), le geste par de VRAIS clics injectes.
func _drink_test() -> void:
	var IS := preload("res://scripts/interaction.gd")
	await get_tree().create_timer(0.8).timeout
	_start_normal_world()
	# La jauge FUIT pendant qu'on la remplit — c'est le jeu, mais pas la
	# mesure : la fuite est l'affaire de sleeptest, on la gele ici pour lire
	# les gains au centieme.
	sleep.full_span = 1.0e9
	var inter = car.interaction

	print("--- boire --------------------------------------------------------")
	var can = inter.grabbables[1]
	print("  L'INVARIANT TIENT  : %s   ([0] %s, [1] %s, pleine %s)" % [
		inter.grabbables[0].name == "CigPack" and can.get("drink") != null
		and can.get("full") == true,
		inter.grabbables[0].name, can.name, can.get("full")])

	# En main par le chemin court, puis le geste par un vrai clic droit.
	inter.target = can
	inter._pick_up()
	inter._state = IS.State.HELD
	await get_tree().create_timer(0.6).timeout
	sleep.vigilance = 0.5
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	Input.parse_input_event(ev)
	var entered: bool = await _until(func(): return inter._state == IS.State.DRINKING, 2.0)
	print("  LE CLIC DROIT BOIT : %s   (etat %d)" % [entered, inter._state])

	# A mi-geste : la canette est a la bouche, basculee — et on la photographie.
	var shot_done := false
	var near_d := 1.0e9
	var tilt_max := 0.0
	while inter._state == IS.State.DRINKING:
		await get_tree().process_frame
		var eye: Vector3 = car.cam.global_position
		near_d = minf(near_d, eye.distance_to(can.global_position))
		var up_axis: Vector3 = can.global_transform.basis.y.normalized()
		tilt_max = maxf(tilt_max, rad_to_deg(acos(clampf(up_axis.dot(Vector3.UP), -1.0, 1.0))))
		if not shot_done and inter._drink_t > 0.85:
			shot_done = true
			await _shot("76_canette.png")
	print("  ELLE VIENT A LA BOUCHE : %s   (au plus pres de l'oeil : %.0f mm, bascule maxi %.0f deg)" % [
		near_d < 0.24 and tilt_max > 40.0, near_d * 1000.0, tilt_max])
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_RIGHT
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await get_tree().process_frame
	print("  ELLE REVEILLE      : %s   (vigilance 0,50 -> %.2f, attendu 0,78)" % [
		absf(sleep.vigilance - 0.78) < 0.01, sleep.vigilance])
	print("  ELLE S'ECRASE      : %s   (pleine %s, ecrasee %s, demi-hauteur %.3f m)" % [
		can.get("full") == false and can.get("crushed") == true,
		can.get("full"), can.get("crushed"), can.get("half").y])

	# L'interruption : une gorgee commencee puis lachee ne compte pas.
	inter.let_go()
	var can2: Node3D = null
	for g in inter.grabbables:
		if g.get("full") == true:
			can2 = g
			break
	inter.target = can2
	inter._pick_up()
	inter._state = IS.State.HELD
	await get_tree().create_timer(0.3).timeout
	var v0: float = sleep.vigilance
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.5).timeout
	Input.parse_input_event(ev2)
	await get_tree().process_frame
	print("  LACHEE, RIEN DE BU : %s   (pleine %s, vigilance %.2f inchangee)" % [
		can2.get("full") == true and absf(sleep.vigilance - v0) < 0.02,
		can2.get("full"), sleep.vigilance])

	# La dette : la vider maintenant, dans la fenetre des 90 s. La deuxieme
	# pleine du tri n'est pas forcement une NoSleep — on lit sa marque.
	var base := 0.18
	match can2.get("drink"):
		"nosleep":
			base = 0.28
		"cariboon":
			base = 0.22
	Input.parse_input_event(ev)
	await _until(func(): return inter._state == IS.State.DRINKING, 2.0)
	await _until(func(): return inter._state != IS.State.DRINKING, 4.0)
	Input.parse_input_event(ev2)
	await get_tree().process_frame
	var gained: float = sleep.vigilance - v0
	print("  LA DETTE ECRASE LA DEUXIEME : %s   (%s : +%.3f, attendu +%.3f = %.2f x 0,6)" % [
		absf(gained - base * 0.6) < 0.012, can2.get("drink"), gained,
		base * 0.6, base])

	get_tree().quit()


# --------------------------------------------------------------------------
# Banc d'essai : la radio
# --------------------------------------------------------------------------

## Le bouton se tient comme la cle (meme contrat d'interface — la prise en
## GRIPPING est deja prouvee par les bancs de vitres et de cle) : ce banc
## verifie la chaine du son — le bus, les crans, ce que la veille en recoit,
## et la derive du cauchemar.
func _radio_test() -> void:
	await get_tree().create_timer(0.8).timeout
	_start_normal_world()
	var radio = car.radio

	print("--- la radio -----------------------------------------------------")
	var bi := AudioServer.get_bus_index("Radio")
	print("  LE BUS EST LE SIEN : %s   (bus %d, envoye vers %s — pas de passe-bas Cabine)" % [
		bi >= 0 and AudioServer.get_bus_send(bi) == &"Master", bi,
		AudioServer.get_bus_send(bi) if bi >= 0 else "-"])
	print("  LE BOUTON SE TIENT : %s   (dans adjustables, rayon %.2f, a %s)" % [
		car.interaction.adjustables.has(radio), radio.grab_radius(),
		radio.global_position])

	# Les crans, un a un — molette haut = crank(-1), comme la cle.
	var db_ok := true
	for k in 6:
		radio.crank(-1.0)
		db_ok = db_ok and absf(radio._player.volume_db
			- radio.CRAN_DB[radio.volume]) < 0.01
		print("    cran %d : %5.1f dB   joue %s   bouton %.0f deg" % [
			radio.volume, radio._player.volume_db, radio._player.playing,
			radio._knob.rotation_degrees.z])
	print("  LES CRANS PORTENT  : %s   (6/6 aux dB de la table, lecture en cours %s)" % [
		db_ok and radio.volume == 6 and radio._player.playing, radio._player.playing])

	# Ce que la veille en recoit : fort des le cran 4.
	print("  LA VEILLE L'ENTEND : %s   (facteur radio %.2f a fond, attendu 0,55)" % [
		absf(sleep.radio_factor - 0.55) < 0.001, sleep.radio_factor])
	for k in 3:
		radio.crank(1.0)
	print("  MOINS FORT, PLUS RIEN : %s   (cran %d, facteur %.2f)" % [
		radio.volume == 3 and absf(sleep.radio_factor - 1.0) < 0.001,
		radio.volume, sleep.radio_factor])

	# Le cauchemar detune la porteuse, le reveil la remet.
	sleep.times_slept = 0
	_enter_nightmare()
	var det: float = radio._player.pitch_scale
	_exit_nightmare()
	print("  LE CAUCHEMAR DERIVE : %s   (pitch %.2f endormi, %.2f reveille)" % [
		absf(det - 0.94) < 0.001 and absf(radio._player.pitch_scale - 1.0) < 0.001,
		det, radio._player.pitch_scale])

	# L'image : le regard descend vers la planche, le bouton en surbrillance.
	radio.set_highlight(true)
	for i in 42:
		var mv := InputEventMouseMotion.new()
		mv.relative = Vector2(-6.0, 26.0)
		Input.parse_input_event(mv)
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	await _shot("78_radio.png")
	radio.set_highlight(false)

	get_tree().quit()


# --------------------------------------------------------------------------
# Banc d'essai du telephone
# --------------------------------------------------------------------------

## Tient la voiture SUR SA VOIE, au rail : position laterale posee, nez dans
## l'axe. Le meme esprit que la vitesse TENUE des autres bancs — sous
## charge, une image peut durer deux secondes, et n'importe quel asservi au
## volant part en slalom (releve : le premier essai a mesure 1230 m sur une
## arete de 950). Les bancs de la carte roulent au rail dans les TRANSITS,
## et rendent tout — voie et volant — la ou le jeu doit laisser choisir.
func _rail(lane: float) -> void:
	_rail_on(road._pos, lane)


## Le rail sur une ligne QUELCONQUE : le ruban vivant, ou le brin mort d'un Y
## quand le banc doit poser la voiture sur la sortie.
##
## LE PIEGE, paye plein pot dans maptest : la premiere version posait la
## voiture SUR l'echantillon le plus proche. Elle ne tient que tant que la
## voiture avance de plus d'un demi-pas par IMAGE. En dessous, l'echantillon
## le plus proche ne change jamais, le rail ramene la voiture d'ou elle vient,
## et LA VOITURE NE BOUGE PLUS — releve : a 8 m/s avec time_scale 2, soit
## 0,27 m par image contre 1,0 m de rayon de cellule, head_index() est reste
## colle a 1269 pendant plus de soixante images d'affilee, et le banc a attendu
## sa fourche jusqu'au delai de 150 s. Le brin mort d'un Y se roule justement
## au ralenti. On ne corrige donc que le LATERAL et le CAP : l'avance le long
## de la ligne, on n'y touche pas — c'est la voiture qui la fait.
##
## CE N'ETAIT PAS QUE maptest. faretest approche et se gare a 10-12 m/s sous
## time_scale 1,5 : 0,25 m par image, le meme regime exactement. Le A/B a ete
## fait, une seule ligne changee et rien d'autre — rail colle : 8 rouges a
## partir de LA PORTIERE VIT (la voiture n'atteignait jamais le bourg, donc
## pas d'embarquement, donc tout le reste en cascade) ; rail qui laisse
## avancer : 14 verts sur 14. Les huit echecs "anterieurs" de faretest
## etaient CETTE ligne.
func _rail_on(line: PackedVector3Array, lane: float) -> void:
	var i: int = road._closest_index(line, car.global_position)
	var fwd := Vector3(0.0, 0.0, -1.0)
	if i + 1 < line.size():
		fwd = (line[i + 1] - line[i]).normalized()
	elif i > 0:
		fwd = (line[i] - line[i - 1]).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var p: Vector3 = line[i] \
		+ fwd * (car.global_position - line[i]).dot(fwd) \
		+ right * lane
	car.global_position.x = p.x
	car.global_position.z = p.z
	car.rotation.y = atan2(-fwd.x, -fwd.z)


## Amene le reticule sur un point d'ecran du telephone au berceau, par de
## VRAIS mouvements de souris. L'asservissement se fait en PIXELS projetes
## (unproject du point vise) : deplacer la souris vers ou une chose apparait
## a l'ecran est vrai quelle que soit la convention d'angles de la tete —
## la premiere version servo-guidait sur rotation.x et poussait plein bas.
func _look_at_screen(phone, uv_goal: Vector2) -> bool:
	var cam3d: Camera3D = car.cam
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	for i in 260:
		var goal_w: Vector3 = phone.screen_point(uv_goal)
		if not cam3d.is_position_behind(goal_w):
			var perr: Vector2 = cam3d.unproject_position(goal_w) - center
			var uv = phone.screen_uv(cam3d.global_position,
				-cam3d.global_transform.basis.z)
			if uv != null and (uv as Vector2).distance_to(uv_goal) < 0.02:
				return true
			var ev := InputEventMouseMotion.new()
			ev.relative = (perr * 0.35).limit_length(30.0)
			Input.parse_input_event(ev)
		await get_tree().process_frame
	return false


func _phone_test() -> void:
	var IS := preload("res://scripts/interaction.gd")
	await get_tree().create_timer(0.8).timeout
	_start_normal_world()
	var inter = car.interaction
	var phone = inter.grabbables.back()

	print("--- l'appareil ---------------------------------------------------")
	print("  L'INVARIANT TIENT  : %s   ([0] %s, dernier %s, au berceau %s, batterie %.0f%%)" % [
		inter.grabbables[0].name == "CigPack" and phone.name == "Phone"
		and phone.docked and phone.battery > 99.0,
		inter.grabbables[0].name, phone.name, phone.docked, phone.battery])
	# L'ecran rend-il vraiment ? La sonde des miroirs : une image non vide.
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = phone._view.get_texture().get_image()
	var lit := 0
	for i in 200:
		var c := img.get_pixel(randi() % img.get_width(), randi() % img.get_height())
		if c.get_luminance() > 0.02:
			lit += 1
	print("  L'ECRAN EST VIVANT : %s   (%d/200 pixels au-dessus du noir)" % [lit > 30, lit])

	# --- le rayon -> uv, contre un calcul independant ----------------------
	print("--- l'ecran au regard --------------------------------------------")
	var probe := Vector2(0.5, 0.9)
	var p_w: Vector3 = phone.screen_point(probe)
	var eye: Vector3 = car.cam.global_position
	var uv_back = phone.screen_uv(eye, (p_w - eye).normalized())
	var err := 1.0e9
	if uv_back != null:
		err = (uv_back as Vector2).distance_to(probe)
	print("  L'UV EST EXACT     : %s   (aller-retour %.4f, seuil 0,005)" % [
		err < 0.005, err])
	# A cote de l'ecran : null, pas un uv fantaisiste.
	var off = phone.screen_uv(eye, (p_w - eye).normalized().rotated(Vector3.UP, 0.5))
	print("  A COTE : RIEN      : %s" % [off == null])
	# L'IMAGE EST-ELLE A L'ENDROIT ? Un aller-retour reste juste meme si
	# l'ecran est retourne — il ment des deux cotes a la fois. Ce qui le prend
	# en defaut, c'est le MONDE : le bas de l'image (la barre d'onglets) doit
	# tomber physiquement sous le haut (la barre d'etat), l'appareil etant
	# debout dans son berceau. Un miroir d'uv au materiau les echangeait, et le
	# doigt tapait alors l'exact oppose de ce que le reticule visait.
	var p_low: Vector3 = phone.screen_point(Vector2(0.5, 0.95))    # les onglets
	var p_high: Vector3 = phone.screen_point(Vector2(0.5, 0.05))   # l'heure
	print("  L'IMAGE EST DEBOUT : %s   (les onglets %.1f cm sous la barre d'etat)" % [
		p_low.y < p_high.y - 0.05, (p_high.y - p_low.y) * 100.0])

	# --- le tap au berceau (etat TAPPING, vrais clics) ---------------------
	var found := await _look_at_screen(phone, Vector2(0.377, 0.93))   # onglet COURSES
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await _until(func(): return inter._state == IS.State.TAPPING, 2.0)
	var tapped: bool = await _until(func(): return inter._state == IS.State.IDLE, 3.0)
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	await get_tree().process_frame
	print("  LE DOIGT TAPE      : %s   (reticule sur l'onglet %s, page -> %s)" % [
		found and tapped and phone._apps.page == "courses", found, phone._apps.page])
	await _shot("80_telephone_dock.png")

	# --- la batterie -------------------------------------------------------
	print("--- la batterie --------------------------------------------------")
	Engine.time_scale = 6.0
	phone.battery = 50.0
	await get_tree().create_timer(60.0).timeout    # 60 s de jeu, 10 s reels
	var charged: float = phone.battery
	print("  LE BERCEAU CHARGE  : %s   (50%% -> %.1f%% en 60 s de jeu, moteur tournant ; attendu ~62)" % [
		absf(charged - 62.0) < 1.5, charged])
	# En main, ecran allume : ca tire.
	inter.target = phone
	inter._pick_up()
	inter._state = IS.State.HELD
	phone.set_viewing(true)
	phone.battery = 50.0
	await get_tree().create_timer(60.0).timeout
	var drained: float = phone.battery
	print("  CONSULTER TIRE     : %s   (50%% -> %.2f%%, attendu ~47,5)" % [
		absf(drained - 47.5) < 0.8, drained])
	# EN MAIN, BAISSE (etat HELD) : depuis qu'il commande le poing, il est porte
	# par _carried_transform, sur une reference exterieure. Il doit s'y tenir
	# DEBOUT, ecran vers le conducteur — le defaut de cette voie le coucherait a
	# plat, ecran au plafond, et on ne verrait plus que sa tranche.
	var top_w: Vector3 = -phone.global_transform.basis.z
	var face_w: Vector3 = phone.global_transform.basis.y
	var to_eye: Vector3 = (car.cam.global_position - phone.global_position).normalized()
	var sky: float = top_w.dot(car.global_transform.basis.y)
	var seen: float = face_w.dot(to_eye)
	print("  IL SE PORTE DEBOUT : %s   (haut vers le ciel %.2f, vitre vers l'oeil %.2f)" % [
		sky > 0.9 and seen > 0.5, sky, seen])
	# A zero : ecran mort, plus rien a toucher.
	phone.battery = 0.05
	await get_tree().create_timer(6.0).timeout
	var dead_uv = phone.screen_uv(eye, (p_w - eye).normalized())
	print("  A PLAT, ECRAN MORT : %s   (batterie %.2f, vitre eteinte %s, uv %s)" % [
		phone.battery <= 0.0 and not phone._quad.visible and dead_uv == null,
		phone.battery, not phone._quad.visible, "null" if dead_uv == null else "!?"])
	Engine.time_scale = 1.0
	phone.battery = 85.0
	phone.set_screen_power(true)

	# --- consulte en main (etat PHONE) -------------------------------------
	print("--- consulte en main ---------------------------------------------")
	var ev_r := InputEventMouseButton.new()
	ev_r.button_index = MOUSE_BUTTON_RIGHT
	ev_r.pressed = true
	Input.parse_input_event(ev_r)
	var consulted: bool = await _until(func(): return inter._state == IS.State.PHONE, 2.0)
	await get_tree().create_timer(0.7).timeout
	var d_read: float = car.cam.global_position.distance_to(phone.global_position)
	var facing: float = phone.global_transform.basis.y.normalized() \
		.dot((car.cam.global_position - phone.global_position).normalized())
	print("  IL MONTE A LA LECTURE : %s   (a %.2f m de l'oeil, ecran vers l'oeil %.2f)" % [
		consulted and d_read < 0.5 and facing > 0.90, d_read, facing])
	await _shot("79_telephone_main.png")

	# LA MAIN NE DOIT RIEN CACHER. Le poing s'orientait d'apres le coude et
	# tenait le boitier par le milieu : les doigts passaient en travers de la
	# vitre, et on ne visait plus un onglet sans viser des phalanges. La prise
	# se mesure dans le repere du boitier — DERRIERE la vitre (y negatif) et
	# SOUS le bord bas de l'ecran (z au-dela de 6,1 cm).
	var hand_l: Vector3 = phone.to_local(inter.to_global(car.driver.item_point))
	print("  LA MAIN NE CACHE RIEN : %s   (prise a %.0f mm derriere la vitre, %.0f mm sous le bord bas)" % [
		hand_l.y <= 0.0 and hand_l.z >= 0.061,
		-hand_l.y * 1000.0, (hand_l.z - 0.061) * 1000.0])

	# LE RETICULE TOMBE-T-IL DANS L'ECRAN ? C'est toute la question : le doigt,
	# c'est le point du HUD, et l'appareil se posait a cote de l'axe du regard
	# — screen_uv() rendait null a chaque image, aucune icone n'etait visable.
	var aim := func():
		return phone.screen_uv(car.cam.global_position,
			-car.cam.global_transform.basis.z)
	var uv_mid = aim.call()
	var on_screen: bool = uv_mid != null \
		and (uv_mid as Vector2).distance_to(Vector2(0.5, 0.5)) < 0.12
	print("  LE DOIGT EST SUR L'ECRAN : %s   (uv %s)" % [
		on_screen, "null" if uv_mid == null else "%.2f, %.2f" % [uv_mid.x, uv_mid.y]])

	# ET S'Y PROMENE-T-IL ? Une arme levee SUIT le regard ; un telephone qui en
	# ferait autant garderait le meme point sous le doigt pour toujours. On
	# tourne la tete d'un vingtieme de radian : le point vise doit glisser.
	var yaw0: float = car.head.rotation.y
	await _look_toward_yaw(yaw0 - 0.05)
	var uv_off = aim.call()
	var swept: bool = uv_mid != null and uv_off != null \
		and (uv_off as Vector2).distance_to(uv_mid) > 0.10
	print("  LE REGARD LE PROMENE     : %s   (%.2f d'ecart d'uv pour 0,05 rad)" % [
		swept, 0.0 if (uv_mid == null or uv_off == null) else (uv_off as Vector2).distance_to(uv_mid)])
	await _look_toward_yaw(yaw0)

	# --- la molette tourne les pages ---------------------------------------
	# Un cran vers le bas = l'onglet suivant, et UN SEUL : sous Windows la
	# molette rebondit, et sans verrou une page se sautait par deux.
	phone._apps.set_page("accueil")
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_DOWN
	w.pressed = true
	Input.parse_input_event(w)
	Input.parse_input_event(w.duplicate())         # le rebond de Windows, simule
	await get_tree().process_frame
	await get_tree().process_frame
	var one_notch: String = phone._apps.page
	await get_tree().create_timer(0.4).timeout     # le verrou retombe
	var w2 := InputEventMouseButton.new()
	w2.button_index = MOUSE_BUTTON_WHEEL_UP
	w2.pressed = true
	Input.parse_input_event(w2)
	await get_tree().process_frame
	await get_tree().process_frame
	print("  LA MOLETTE TOURNE LES PAGES : %s   (accueil -> %s au cran bas, puis %s au cran haut)" % [
		one_notch == "courses" and phone._apps.page == "accueil",
		one_notch, phone._apps.page])
	var ev_r2 := InputEventMouseButton.new()
	ev_r2.button_index = MOUSE_BUTTON_RIGHT
	ev_r2.pressed = false
	Input.parse_input_event(ev_r2)
	await get_tree().process_frame

	# --- la repose au berceau (l'aimant) -----------------------------------
	# On vise la console pres du berceau et on relache : le telephone doit
	# finir DANS le support, pas a cote, et l'ecran se rallumer.
	await _look_toward_yaw(0.0)
	inter.let_go()
	phone.transform = car.cabin.phone_dock_pose()
	phone.set_docked(true)
	print("  LE BERCEAU REPREND : %s   (docked %s, ecran %s)" % [
		phone.docked and phone.screen_on(), phone.docked, phone.screen_on()])

	# --- l'ecran qui vit ---------------------------------------------------
	# LE PIEGE QU'ON VIENT DE PAYER : la branche `viewing` de phone.gd posait
	# UPDATE_ALWAYS et rien d'autre. Un ecran qui se re-rend soixante fois par
	# seconde et un ecran fige se ressemblent trop pour qu'on s'en apercoive a
	# l'oeil — il fallait deux captures et un compte de pixels.
	#
	# Les deux mesures qui suivent opposent le meme telephone a lui-meme, et le
	# viewport rend a chaque image DES DEUX COTES : le FIGE, c'est l'appareil
	# d'avant J0 — set_process(false) arrete tick(), et on tient UPDATE_ALWAYS
	# au viewport a la main. Ce qui les separe n'est donc pas le rendu, c'est la
	# vie. Le banc reproduit le defaut au lieu de croire sur parole qu'il a
	# existe.
	print("--- l'ecran qui vit ----------------------------------------------")
	inter.target = phone
	inter._pick_up()
	inter._state = IS.State.HELD
	phone.battery = 85.0
	phone.set_screen_power(true)
	phone.set_viewing(true)
	phone._apps.set_page("gps")
	car.gear = 5
	# Echelle 6 et plafond a 30 images : les trente images de l'ecart valent
	# alors AU MOINS une seconde reelle, donc six secondes de jeu — cent vingt
	# metres a 20 m/s et trois minutes d'horloge (daycycle : deux secondes
	# reelles par minute de jeu). Trois choses bougent donc a coup sur : le
	# point du GPS (6 px sur les 51 px de l'arete Saint-Elme - Corbeny), la
	# distance du bandeau, et l'heure de la barre d'etat. Sans le plafond, une
	# machine a 200 images par seconde n'aurait laisse passer qu'un tiers de
	# minute de jeu et le banc aurait rougi pour cause de VITESSE ; une machine
	# plus lente, elle, ne peut que faire bouger davantage de pixels.
	Engine.time_scale = 6.0
	Engine.max_fps = 30
	var moved_px := [0, 0]
	for phase in 2:
		phone.set_process(phase == 0)
		phone._view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		for i in 12:
			car.speed = 20.0
			_rail(1.2)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_a: Image = phone._view.get_texture().get_image()
		for i in 30:
			car.speed = 20.0
			_rail(1.2)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_b: Image = phone._view.get_texture().get_image()
		# 216 x 384 = 82 944 pixels : on compare les OCTETS. Deux get_pixel par
		# pixel, ce serait 166 000 appels de methode pour la meme reponse.
		var da := img_a.get_data()
		var db := img_b.get_data()
		var npx := img_a.get_width() * img_a.get_height()
		var stride := da.size() / npx
		for k in npx:
			var o := k * stride
			for c in stride:
				if da[o + c] != db[o + c]:
					moved_px[phase] += 1
					break
	phone.set_process(true)
	Engine.max_fps = 0
	print("  L'ECRAN BOUGE EN MAIN : %s   (%d pixels changes en 30 images a 20 m/s, seuil 200 ; le MEME ecran rendu sans tick() : %d)" % [
		moved_px[0] > 200 and moved_px[1] == 0, moved_px[0], moved_px[1]])

	# LE COUT RESTE PLAT — ce que le correctif AJOUTE, et rien d'autre : les
	# memes deux etats, le viewport rendant a chaque image des deux cotes.
	# L'ecart, c'est tick() : le dessin de la carte a 10 Hz et les textes a
	# 4 Hz.
	#
	# TROIS PRECAUTIONS, TROIS PIEGES PAYES.
	#
	# A L'ARRET : en roulant, l'image de ce jeu va de 5 a 25 ms selon que le
	# ruban se re-triangule, qu'un prop naisse ou qu'une ville s'arme. Un
	# premier releve en roulant a rendu +1,6 ms puis +0,3 ms d'un essai a
	# l'autre — il mesurait la route. A l'arret le monde se tait (les images
	# tiennent entre 3,0 et 4,2 ms) et le telephone dessine exactement la meme
	# chose : son cout n'a pas de vitesse.
	#
	# VSYNC COUPEE : au defaut du projet (project.godot n'ecrit aucun
	# display/window/vsync) l'image est calee sur l'ecran, 16,7 ms quoi qu'on y
	# mette. Un ecart de 0,2 ms n'y apparait jamais — le banc serait vert sans
	# rien avoir mesure. On la coupe le temps du releve et on la remet.
	#
	# MESURE APPARIEE — et c'est le correctif de cette ligne, parce que
	# l'ancienne ne mesurait pas le telephone : elle mesurait la machine.
	#
	# CE QU'ELLE FAISAIT : elaguer puis moyenner les 200 images de chaque cote
	# en un seul tas, et comparer les deux tas. Elle rendait +0,312 ms un
	# lancement, -0,14 le suivant, +0,31 le troisieme — 0,45 ms de bruit, creux
	# a bosse, sous un seuil de 0,50. Un seuil qu'on ne franchit qu'en battant
	# le bruit de 10 % ne declare rien de plus que "pas monstrueux" ; et
	# phone_apps.gd:374 l'ecrivait deja noir sur blanc, en constatant que le
	# defaut des quatre dessins de trop (0,02 ms par image) passait vingt-cinq
	# fois sous ce seuil-la sans le faire bouger d'un cheveu.
	#
	# CE QUI CHANGE, EN TROIS POINTS.
	#
	# 1. ON APPARIE. Chaque bloc rend UNE difference : la mediane de ses images
	#    vivantes moins la mediane de ses images figees, prises a 100 ms l'une
	#    de l'autre. Une derive lente — le thermique, un autre processus qui se
	#    reveille — deplace les deux medianes du meme bloc ENSEMBLE et sort de
	#    la difference. L'ancienne version la laissait tomber dans un seul des
	#    deux tas, ou elle devenait un cout du telephone.
	# 2. L'ORDRE S'INVERSE d'un bloc a l'autre : bloc pair le vivant passe en
	#    premier, bloc impair en second. Ce qui reste de derive A L'INTERIEUR
	#    d'un bloc change donc de signe une fois sur deux, et s'annule au lieu
	#    de s'accumuler.
	# 3. LE VERDICT EST LA MEDIANE DES 96 DIFFERENCES : une bouffee de la
	#    machine sur un bloc ne la deplace pas. 96 blocs de 32 images par cote
	#    (8 jetees a chaque changement de regime) = 4608 images mesurees contre
	#    400, et ~18 s de releve contre ~2.
	#
	# LE BANC IMPRIME SA PROPRE RESOLUTION, et c'est la seule facon honnete de
	# defendre un seuil. Deux nombres a cote du verdict :
	#   — L'ECART DES DEUX MOITIES : la mediane des 48 premiers blocs moins
	#     celle des 48 derniers. Deux mesures independantes de la meme chose,
	#     dans le meme lancement — leur ecart EST le bruit de l'estimateur, il
	#     ne l'estime pas. Releve : 0,005 a 0,09 ms.
	#   — L'ECART INTERQUARTILE des differences de bloc : ce qu'un bloc SEUL
	#     vaudrait (0,08 ms machine au repos, 1,6 ms machine occupee), donc ce
	#     que la mediane de 96 divise.
	#
	# LE SEUIL EST A 0,30 ms, ET C'EST UN CHIFFRE MESURE, pas un chiffre rond.
	# Quatorze lancements de cette version : mediane appariee de -0,070 a
	# +0,173 ms, douze fois sous 0,09. 0,30 vaut 1,7 fois le pire releve et
	# 3,5 fois le deuxieme pire. Le poser a 0,20 ne laisserait que 0,03 ms
	# au-dessus du pire — la ligne clignoterait des que la machine s'occupe, et
	# un banc qui clignote ne se lit plus : c'est le faux vert d'a cote qu'on
	# finit par croire.
	#
	# CE QUE CA VAUT, EN CLAIR : la mesure est 2,6 fois plus fine qu'avant
	# (0,17 ms de bruit maxi contre 0,45) sous un budget 1,7 fois plus serre.
	# Ce qu'on a gagne, c'est le RAPPORT : 1,11 avant, 1,7 maintenant.
	#
	# ET CE QU'ELLE NE VOIT TOUJOURS PAS, parce qu'il faut le dire : 0,02 ms
	# par image — le defaut des quatre dessins de trop — reste cinq fois sous
	# la resolution de la machine. Cette ligne attrape une REGRESSION DE REGIME,
	# un telephone qui se remettrait a travailler A CHAQUE image ; elle
	# n'attrapera jamais un gaspillage de quelques microsecondes. Celui-la se
	# compte dans phone_apps.gd, en comptant les dessins, et le renvoi vaut
	# dans les deux sens : ce banc-ci ne remplace pas cette sonde-la.
	Engine.time_scale = 1.0
	car.speed = 0.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var samples := [[], []]
	var deltas := []
	for blk in 96:
		var med_ms := [0.0, 0.0]
		for k in 2:
			var phase: int = k if blk % 2 == 0 else 1 - k
			phone.set_process(phase == 0)
			var sv := []
			var t0 := Time.get_ticks_usec()
			for i in 32:
				car.speed = 0.0
				await get_tree().process_frame
				phone._view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				var t1 := Time.get_ticks_usec()
				# Les huit premieres images d'un bloc ne comptent pas : le
				# telephone vient de changer de regime.
				if i >= 8:
					sv.append(float(t1 - t0) * 0.001)
				t0 = t1
			sv.sort()
			med_ms[phase] = 0.5 * (sv[sv.size() / 2 - 1] + sv[sv.size() / 2])
			samples[phase].append_array(sv)
		deltas.append(med_ms[0] - med_ms[1])
	phone.set_process(true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	# Les deux moities se prennent DANS L'ORDRE DES BLOCS : c'est de leur ecart
	# qu'on tire la resolution, donc on les separe avant de trier quoi que ce
	# soit.
	var half_med := [0.0, 0.0]
	for h in 2:
		var hv: Array = (deltas as Array).slice(
			h * deltas.size() / 2, (h + 1) * deltas.size() / 2)
		hv.sort()
		half_med[h] = 0.5 * (hv[hv.size() / 2 - 1] + hv[hv.size() / 2])
	var split_ms: float = half_med[0] - half_med[1]
	deltas.sort()
	var nd: int = deltas.size()
	var extra_ms: float = 0.5 * (deltas[nd / 2 - 1] + deltas[nd / 2])
	var iqr_ms: float = deltas[3 * nd / 4] - deltas[nd / 4]
	var med_side := [0.0, 0.0]
	for phase in 2:
		var sv2: Array = samples[phase]
		sv2.sort()
		med_side[phase] = 0.5 * (sv2[sv2.size() / 2 - 1] + sv2[sv2.size() / 2])
	print("  LE COUT RESTE PLAT    : %s   (%+.3f ms d'image, seuil 0,30 ; mediane de %d differences APPARIEES — une par bloc, l'ordre des deux cotes s'inversant d'un bloc a l'autre. LA RESOLUTION, MESUREE ICI MEME : %+.3f ms entre la mediane des 48 premiers blocs et celle des 48 derniers, soit deux mesures independantes de la meme chose ; un bloc seul vaudrait %.3f ms d'ecart interquartile. Medianes brutes : %.2f ms vivant contre %.2f ms fige, sur %d images de chaque)" % [
		absf(extra_ms) < 0.20, extra_ms, nd, split_ms, iqr_ms,
		med_side[0], med_side[1], (samples[0] as Array).size()])
	phone.set_viewing(false)
	Engine.time_scale = 1.0
	get_tree().quit()


# --------------------------------------------------------------------------
# Banc d'essai de la carte et des embranchements
# --------------------------------------------------------------------------

## Quatre choses a prouver : le graphe compte juste (Dijkstra sur les
## longueurs ecrites), la route HONORE la metrique (la ville tombe ou la
## carte le dit), le Y se prend AU VOLANT — dans les deux sens, y compris
## l'echange des rubans quand on passe sur le brin mort, sans couture — et la
## metrique NE DERIVE PAS quand on enchaine les Y.
##
## LA QUATRIEME EST NEUVE, ET C'EST L'ANGLE MORT QUI A LAISSE PASSER +314 m.
## Ce banc n'a longtemps mesure qu'une arete : la PREMIERE, celle qui n'a pas
## de Y — "Corbeny apres 952 m, la carte dit 950". Deux metres, verdict vert,
## et pendant ce temps les deux aretes suivantes en prenaient 314 et 272 de
## rab sans que rien ne rougisse. Le banc roule desormais les TROIS aretes
## consecutives qu'il traversait deja (Saint-Elme > Corbeny sans Y, Corbeny >
## Malassis par le cote vivant, Malassis > Peyrelade par le brin mort) et
## imprime la derive de chacune, panneau a panneau.
func _map_test() -> void:
	await get_tree().create_timer(0.8).timeout
	_start_normal_world()
	Engine.time_scale = 5.0

	print("--- le graphe ----------------------------------------------------")
	var route := MapScript.path("Saint-Elme", "Brumaire")
	var rlen := MapScript.path_length(route)
	print("  DIJKSTRA COMPTE JUSTE : %s   (%s, %d m — attendu par Corbeny et Vieux-Bourg, 3400)" % [
		route == ["Saint-Elme", "Corbeny", "Vieux-Bourg", "Brumaire"]
		and absf(rlen - 3400.0) < 0.1, " > ".join(route), int(rlen)])
	var deg_ok := true
	for t in MapScript.towns():
		if MapScript.neighbors(t).size() > 3:
			deg_ok = false
	print("  JAMAIS PLUS D'UN Y    : %s   (degre maxi 3 sur les %d villes)" % [
		deg_ok, MapScript.towns().size()])

	# --- l'arete se roule : Saint-Elme -> Corbeny (950 m) ------------------
	print("--- la premiere arete --------------------------------------------")
	var seen := [""]
	var seen_at := [0]
	road.town_reached.connect(func(id: String) -> void:
		seen[0] = id
		seen_at[0] = road.head_index())
	var g0: int = road.head_index()
	# Le carnet de la metrique : un panneau franchi, l'index global ou il l'a
	# ete. Il s'ecrit tout seul pendant que le banc roule ses trois aretes, et
	# se lit tout en bas. On note l'INDEX et pas une distance parcourue : c'est
	# la meme unite que celle dans laquelle la navigation programme les villes,
	# donc la derive qu'on mesure est exactement celle qu'elle fabrique — une
	# integration de la vitesse mesurerait aussi les ecarts de trajectoire du
	# rail, qui ne regardent personne ici.
	var marks := [["Saint-Elme", g0]]
	var marks_y := {}
	road.town_reached.connect(func(id: String) -> void:
		marks.append([id, road.head_index()]))
	car.gear = 5
	var t := 0.0
	var shot_town := false
	while t < 90.0 and seen[0] == "":
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
		if not shot_town and road.town.visible \
				and car.global_position.distance_to(road.town.global_position) < 80.0:
			shot_town = true
			car.speed = 0.0
			await get_tree().process_frame
			await _shot("81_ville.png")
	var rolled := float(seen_at[0] - g0) * RoadScript.STEP
	print("  LA VILLE TOMBE JUSTE : %s   (%s apres %.0f m, la carte dit 950)" % [
		seen[0] == "Corbeny" and absf(rolled - 950.0) < 30.0, seen[0], rolled])

	# --- le Y, cote vivant : on suit la branche principale -----------------
	print("--- le Y ---------------------------------------------------------")
	var committed := [""]
	var committed_side := [""]
	var commits := [0]
	road.fork_committed.connect(func(side: String, id: String) -> void:
		committed_side[0] = side
		committed[0] = id
		commits[0] += 1
		# L'arete EN COURS a eu son Y : elle part du dernier panneau franchi.
		# C'est ce que le releve du bas appelle "(Y)", et c'est lui qui
		# distingue les deux aretes qui comptent de celle qui ne prouve rien.
		marks_y[marks.size() - 1] = true)
	var expect_main: String = nav["to"]
	var shot_sign := false
	t = 0.0
	while t < 90.0 and committed[0] == "":
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 22.0)
		# Au rail dans l'approche ; VOIE ET VOLANT RENDUS au panneau — au Y la
		# route file droit, et ce passage prouve exactement ca : sans toucher
		# a rien, tout droit mene au cote vivant.
		#
		# Le rail lache A l'echantillon du panneau (<=), pas un avant : il
		# prend son cap sur le segment SOUS la voiture, et le dernier segment
		# d'avant le panneau est encore dans le virage — 1,03 deg au pire
		# (MAX_CURVE * STEP). Rendre le volant sur ce degre-la, c'est partir
		# avec lui : 2,55 m de derive sur les 142 m de la fenetre, plus que
		# les 2,2 m qui tranchent le Y. Le banc jugerait son propre depart.
		if road.fork_index() < 0 \
				or road.head_index() <= road.fork_index() - RoadScript.FORK_SIGN_AT:
			_rail(1.2)
		if not shot_sign and road._fork_sign != null and road._fork_sign.visible \
				and car.global_position.distance_to(road._fork_sign.global_position) < 70.0:
			shot_sign = true
			car.speed = 0.0
			await get_tree().process_frame
			await _shot("82_y.png")
	_act("steer_left", false)
	_act("steer_right", false)
	print("  LE COTE VIVANT MENE  : %s   (volant rendu au Y : pris \"%s\" vers %s, attendu %s)" % [
		committed[0] == expect_main, committed_side[0], committed[0], expect_main])

	# --- le Y, cote mort : on force le passage, les rubans s'echangent ------
	var n0: int = commits[0]
	var next_fork := [false]
	var main_then := [""]
	t = 0.0
	while t < 150.0 and commits[0] == n0:
		await get_tree().process_frame
		t += get_process_delta_time()
		# La voiture est POSEE sur la sortie : c'est la DETECTION et
		# l'ECHANGE des rubans qu'on prouve ici — le coup de volant, lui,
		# appartient au joueur (tout asservi de banc a fond de butee sous
		# des images de deux secondes finissait en ronds dans le champ).
		#
		# Au rail SUR LE BRIN MORT, comme on roule au rail sur le vivant : la
		# voiture avance a sa vitesse, seul son lateral est pose. Elle etait
		# COLLEE sur l'echantillon le plus proche avant — a 8 m/s ca ne bouge
		# plus du tout (voir _rail_on) et le banc attendait un echange qui ne
		# pouvait pas venir : sans avance, pas de fenetre, pas de verdict.
		var near: bool = road.fork_state() in ["grow", "window"] \
			and road.head_index() >= road.fork_index() - 25
		if near:
			Engine.time_scale = 2.0
			car.speed = minf(maxf(car.speed, 8.0), 9.0)
			next_fork[0] = true
			main_then[0] = road._fork_main
			if road.head_index() >= road.fork_index() + 4 and road._bpos.size() > 1:
				_rail_on(road._bpos, 0.0)
			else:
				_rail(1.2)
		else:
			Engine.time_scale = 5.0
			car.speed = maxf(car.speed, 22.0)
			_rail(1.2)
	_act("steer_left", false)
	_act("steer_right", false)
	car.speed = 0.0
	await get_tree().process_frame
	# La continuite du ruban echange : aucun trou, aucune cassure.
	#
	# ON MESURE L'ECART AU PAS, PAS LA LONGUEUR DU PAS, et c'est le correctif
	# de cette ligne. Elle comparait `pas maxi < STEP * 1,5` : un test SANS
	# PLANCHER, qui laissait passer sans un mot le defaut que _grow_branch
	# raconte avoir paye — la tete de reprise rangee SUR le dernier point au
	# lieu d'un pas au-dela, « un segment de longueur nulle, une normale en 0/0
	# et un faux virage de 90 degres au releve ». Un pas de 0,00 m passait
	# « < 3,0 » les doigts dans le nez. |pas - STEP| l'attrape des deux cotes.
	#
	# ET LE SEUIL S'ECRIT MAINTENANT DANS LA LIGNE. Elle imprimait « pas maxi
	# 2.00 m pour 2.0 » : le 2.0 etait STEP, pas le seuil, qui valait 3,0. Elle
	# avait donc l'air d'etre a la limite quand elle avait 50 % de marge — un
	# releve qui ment sur son propre confort.
	#
	# LE PLAFOND DU VIRAGE VIENT DE road.gd, ET C'EST CELUI DU BRIN MORT :
	# _grow_branch part a 2 x FORK_BEND (0,015 rad/m, au-dessus de MAX_CURVE —
	# la sortie s'ecarte plus vite que la nationale ne tourne), soit
	# 1,72 deg/pas. Le 4,0 d'avant etait un chiffre rond a 2,3 fois le plafond.
	var ceil_deg: float = rad_to_deg(maxf(2.0 * RoadScript.FORK_BEND,
		RoadScript.MAX_CURVE) * RoadScript.STEP)
	var max_gap := 0.0
	var max_turn := 0.0
	for i in road._pos.size() - 1:
		max_gap = maxf(max_gap,
			absf(road._pos[i].distance_to(road._pos[i + 1]) - RoadScript.STEP))
		if i > 0:
			var d0: Vector3 = (road._pos[i] - road._pos[i - 1]).normalized()
			var d1: Vector3 = (road._pos[i + 1] - road._pos[i]).normalized()
			max_turn = maxf(max_turn, rad_to_deg(acos(clampf(d0.dot(d1), -1.0, 1.0))))
	print("  LA SORTIE ECHANGE LES RUBANS : %s   (fourche vue %s, vivant \"%s\", pris \"%s\" vers %s)" % [
		next_fork[0] and commits[0] > n0 and committed_side[0] != main_then[0]
		and committed[0] == nav["to"], next_fork[0], main_then[0],
		committed_side[0], committed[0]])
	print("  LE RUBAN EST SANS COUTURE : %s   (sur les %d points du ruban qui vient d'etre echange : ecart au pas de %.4f m pour un seuil de 0,01 — le pas nominal vaut %.1f m et un point DOUBLE en ferait 2,000 d'ecart —, virage maxi %.2f deg/pas pour un SEUIL de %.2f, soit le plafond du brin mort — 2 x FORK_BEND x STEP, %.2f deg/pas — et 15 %% pour le float ; le brin y roule PAR CONSTRUCTION, c'est bien pour ca qu'il faut le mesurer la et pas plus haut)" % [
		road._pos.size() > 100 and max_gap < 0.01 and max_turn < ceil_deg * 1.15,
		road._pos.size(), max_gap, RoadScript.STEP, max_turn,
		ceil_deg * 1.15, ceil_deg])

	# --- l'ecran GPS -------------------------------------------------------
	var phone = car.interaction.grabbables.back()
	phone._apps.set_page("gps")
	phone._apps.refresh()
	phone._view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var gps_img: Image = phone._view.get_texture().get_image()
	gps_img.save_png("user://83_gps.png")
	print("SHOT: ", ProjectSettings.globalize_path("user://83_gps.png"))
	print("  LE GPS SAIT OU ON EST : %s   (\"%s\", progression %.2f)" % [
		not nav.is_empty() and nav_progress() >= 0.0,
		phone._apps._gps_line.text, nav_progress()])

	# --- la troisieme arete : on la finit ----------------------------------
	# On est sur Malassis > Peyrelade depuis le brin mort, quelque part apres
	# le Y. Il reste ~900 m a rouler jusqu'au panneau : c'est cette arete-la,
	# celle qui suit un ECHANGE DE RUBAN, qui derivait de +272 m.
	print("--- la metrique, de panneau a panneau ----------------------------")
	Engine.time_scale = 5.0
	t = 0.0
	while t < 150.0 and marks.size() < 4:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
	car.speed = 0.0

	# Le releve. Une arete se mesure DE PANNEAU A PANNEAU — c'est ce que
	# map.gd promet, ce que le prix de course facture et ce que le bandeau du
	# telephone recite —, donc la derive est la difference entre les metres
	# roules entre deux panneaux et les metres annonces par la carte.
	#
	# LE SEUIL EST A 30 m, comme sur LA VILLE TOMBE JUSTE, et ce qu'il laisse
	# passer n'est pas de la derive : c'est de la GRANULARITE. Le rendez-vous
	# se pose a l'echantillon (2 m), l'echange de ruban en coute un autre
	# (road.gd:672, "a un pas pres"), et le panneau se franchit A L'IMAGE —
	# une image longue avale plusieurs echantillons d'un coup. Releve sur onze
	# lancements : les deux aretes a Y tiennent entre +0 et +8 m, et c'est la
	# PREMIERE qui monte le plus haut (+12) — celle ou le banc arrete la
	# voiture pour la capture 81_ville.png, et ou l'image qui reprend engloutit
	# six echantillons. Le seuil couvre donc deux fois et demie le pire releve,
	# et pas davantage : la derive qu'on traque ici ne se comptait pas en
	# echantillons, elle se comptait en centaines de metres.
	#
	# VERIFIE EN LE CASSANT : _on_fork_committed remis a l'ancienne formule
	# (head_index() + edge_length - FORK_AFTER_TOWN_M) sur une copie jetable du
	# depot. Cette ligne : false, +302 sur Corbeny > Malassis et +274 sur
	# Malassis > Peyrelade (+300 et +272 au second lancement) — pendant que LA
	# VILLE TOMBE JUSTE, deux ecrans plus haut, restait verte a +2 m sur la
	# seule arete sans Y. C'est le defaut entier en trois lignes de console.
	#
	# DEUX LIGNES, ET PAS UNE : LA COUVERTURE N'EST PAS LE VERDICT. La version
	# d'avant tranchait sur `marks.size() >= 4 and ys >= 2 and worst < 30` —
	# un ET entre une mesure et une CONDITION D'EXPERIENCE. Le banc ne GARANTIT
	# pas ses deux Y, il les CONSTATE : le Y se prend au volant, et quand il
	# part du mauvais cote l'itineraire change, le compte de Y tombe a 1 et la
	# ligne rougissait — sous un titre qui parle de derive. C'est arrive, et le
	# releve dit tout : « 4 aretes dont 1 avec Y, pire derive 2 m pour 30 ».
	# Metrique parfaite, ligne rouge. Un rouge qu'on apprend a ne plus croire
	# est pire qu'un vert de trop.
	#
	# Alors : LA METRIQUE NE DERIVE PLUS ne juge plus que la derive, sur les
	# aretes que le banc a EFFECTIVEMENT roulees ; et ce que le banc a roule se
	# lit sur la ligne d'a cote, qui porte son propre nom et son propre
	# verdict. Quand la seconde rougit, la premiere ne dit plus rien de la
	# route a Y — mais elle le dit sans mentir sur ce qu'elle a mesure, et on
	# relance.
	var worst := 0.0
	var ys := 0
	var told := []
	for i in range(1, marks.size()):
		var a: String = marks[i - 1][0]
		var b: String = marks[i][0]
		var ann: float = MapScript.edge_length(a, b)
		var run := float(int(marks[i][1]) - int(marks[i - 1][1])) * RoadScript.STEP
		var y: bool = marks_y.has(i - 1)
		if y:
			ys += 1
		worst = maxf(worst, absf(run - ann))
		told.append("%s > %s%s annonce %d, roule %d, derive %+d" % [
			a, b, " (Y) " if y else " ", int(ann), int(run), int(round(run - ann))])
	print("  LA METRIQUE NE DERIVE PLUS : %s   (pire derive %.0f m pour 30, sur les %d arete(s) roulee(s) de panneau a panneau ; %s)" % [
		told.size() > 0 and worst < 30.0, worst, told.size(), " | ".join(told)])
	# LA COUVERTURE, ET ELLE N'EST PAS DECORATIVE : sans deux aretes a Y, la
	# ligne du dessus est verte sur une route qui ne prouve rien — c'est
	# exactement l'angle mort qui a laisse passer +314 m pendant que la seule
	# arete sans Y affichait +2. Elle rougit quand le banc n'a pas pu rouler ce
	# qu'il voulait rouler (un Y pris du mauvais cote, un echange qui n'est pas
	# venu, une image trop longue au panneau), et c'est une raison de RELANCER,
	# pas un defaut du jeu. On imprime donc ce qui manque, pas seulement un
	# faux.
	print("  LE BANC A ROULE SES DEUX Y  : %s   (couverture, PAS metrique : %d arete(s) roulee(s) pour 3 attendues, dont %d a fourche pour 2 — le cote vivant sur Corbeny > Malassis, l'echange de rubans sur Malassis > Peyrelade)" % [
		told.size() >= 3 and ys >= 2, told.size(), ys])

	Engine.time_scale = 1.0
	get_tree().quit()


# --------------------------------------------------------------------------
# Banc d'essai des plans de ville
# --------------------------------------------------------------------------

## Le J1 ne pose pas une pierre dans le monde : il ecrit le PLAN des huit
## bourgs, et rien d'autre. Ce banc est donc le seul du depot a ne pas demarrer
## la nuit — pas de monstres, pas de taxi, pas d'horloge, pas une seule image
## attendue. Huit tirages de donnee pure, huit dessins, et il rend la main.
##
## Le dessin n'est pas une coquetterie. Un plan de ville qu'on ne peut pas
## regarder ne se corrige pas : les neuf invariants ci-dessous diraient encore
## "true" d'un bourg dont toutes les rues seraient tassees dans un coin. C'est
## le trace ASCII qui repond a la seule question qu'aucun seuil ne pose — est-ce
## que ca ressemble a un bourg.
##
## LE RUBAN N'A PAS BOUGE n'est pas ici et n'y sera pas : il appartient a
## maptest, qui roule pour de vrai. On le renvoie, on ne le duplique pas — deux
## bancs qui mesurent la meme chose finissent toujours par ne plus etre
## d'accord, et c'est le faux qu'on croit alors. Mais le renvoi est une NOTE,
## en bas de la section, pas une ligne d'invariant : il a longtemps porte le
## titre en capitales et les deux-points d'un verdict sans porter de booleen,
## et une ligne qui ne peut pas rougir sous un nom d'invariant rassure sans
## rien garantir. La place d'invariant revient a LA VILLE SE COUD AU RUBAN,
## que ce banc-ci peut mesurer sans une image : les trois cotes que
## town_plan.gd recopie de road.gd a la main.
##
## LE PIEGE DU BANC, paye ici : le banc ne doit RIEN emprunter au fichier qu'il
## juge. town_plan.gd sait deja calculer la distance d'une facade a une rue, la
## rue la plus proche d'un point et l'emprise d'une rue ; s'en servir pour se
## noter, c'est demander a l'accuse d'ecrire le verdict. Distances et emprises
## sont donc recalculees en dessous (_plan_seg_seg, _plan_axis_dist,
## _plan_emprise), a la main, et la grille de nearest() est confrontee au
## balayage complet des sept rues.
##
## LE SECOND PIEGE, paye plus tard et plus cher : un seuil qui recite une
## CONSTANTE du fichier juge ne mesure rien non plus. Trois lignes en sont
## mortes ici — la marge des murs comparee a KEEP_CLEAR, l'ecart des adresses
## compare a une fenetre qui contenait walk_mid() par construction, et un
## "seen_max < 12" quand sept rues font sept. Chaque seuil de ce banc se
## compare desormais a une PROMESSE (l'emprise de la rue, la bande de trottoir,
## le cout du balayage complet), jamais a un nombre pris dans town_plan.gd.
func _plan_test() -> void:
	var TownPlan := preload("res://scripts/town_plan.gd")
	var plans := []
	for id in MapScript.towns():
		plans.append(TownPlan.of(id))

	# --- la graine ---------------------------------------------------------
	print("--- la graine ----------------------------------------------------")
	# Trois tirages NEUFS du meme bourg. On ne peut pas les demander a of() :
	# il memoise, et trois fois le meme objet ne prouve rien du tout. On refait
	# donc a la main ce que of() fait, trois fois, et on compare les octets —
	# rues, carrefours, mats, maisons, adresses et enveloppe.
	var sigs := []
	for k in 3:
		var q = TownPlan.new()
		q.id = "Corbeny"
		q._generate(MapScript.seed_of("Corbeny"))
		sigs.append(_plan_sig(q))
	var same: bool = sigs[0] == sigs[1] and sigs[1] == sigs[2]
	print("  CORBENY EST TOUJOURS CORBENY     : %s   (3 tirages neufs, graine %d, %d octets de plan compares au bit)" % [
		same, MapScript.seed_of("Corbeny"), (sigs[0] as PackedByteArray).size()])

	var twins := 0
	var len_lo := 1.0e9
	var len_hi := -1.0e9
	for i in plans.size():
		len_lo = minf(len_lo, plans[i].total_len())
		len_hi = maxf(len_hi, plans[i].total_len())
		for j in range(i + 1, plans.size()):
			if plans[i].streets.size() == plans[j].streets.size() \
					and absf(plans[i].total_len() - plans[j].total_len()) < 0.5:
				twins += 1
	print("  LES HUIT VILLES SONT DIFFERENTES : %s   (%d paires, %d jumelle(s) ; longueur de rue cumulee de %.0f a %.0f m)" % [
		twins == 0, plans.size() * (plans.size() - 1) / 2, twins, len_lo, len_hi])

	# --- la geometrie du plan ----------------------------------------------
	print("--- la geometrie du plan -----------------------------------------")
	# L'angle droit n'est pas espere, il est construit : une rue est parallele
	# ou perpendiculaire au tronc, et rien d'autre. Ce qu'on mesure ici, c'est
	# que la construction n'a pas ete contournee quelque part.
	var nj := 0
	var worst_angle := 0.0
	for p in plans:
		for j in p.junction_count():
			nj += 1
			var da: Vector2 = p.street_dir(p.junction_a(j))
			var db: Vector2 = p.street_dir(p.junction_b(j))
			worst_angle = maxf(worst_angle, absf(absf(da.angle_to(db)) - PI * 0.5))
	print("  TOUT CARREFOUR EST UN RECTANGLE        : %s   (%d carrefours, ecart maxi a l'angle droit %.6f rad, seuil 0,001)" % [
		worst_angle < 0.001, nj, worst_angle])

	# Deux axes de rue qui se coupent sans carrefour declare, c'est une rue qui
	# traverse une autre rue au milieu du bitume : le GPS y ferait tourner, la
	# ville n'y poserait pas de pave. Force brute sur toutes les paires.
	var stray := 0
	var pairs := 0
	for p in plans:
		for i in p.streets.size():
			for j in range(i + 1, p.streets.size()):
				pairs += 1
				var x = Geometry2D.segment_intersects_segment(
					_plan_end(p, i, 0), _plan_end(p, i, 1),
					_plan_end(p, j, 0), _plan_end(p, j, 1))
				if x == null:
					continue
				var listed := false
				for k in p.junction_count():
					var ja: int = p.junction_a(k)
					var jb: int = p.junction_b(k)
					if (ja == i and jb == j) or (ja == j and jb == i):
						if p.junction_su(k).distance_to(x as Vector2) < 0.01:
							listed = true
				if not listed:
					stray += 1
	print("  AUCUNE RUE NE SE CROISE HORS CARREFOUR : %s   (%d paires de rues examinees, %d croisement(s) sans carrefour)" % [
		stray == 0, pairs, stray])

	# Le cycle, c'est la SECONDE CHANCE : sans lui, se tromper de rue est une
	# impasse et il faut refaire le chemin a l'envers. On le compte sur le VRAI
	# graphe — les carrefours pour noeuds, les troncons entre deux carrefours
	# consecutifs d'une meme rue pour aretes.
	#
	# PAS avec la formule du plan (docs/PLAN_VILLES.md:483, "cycles = rues -
	# noeuds + 1") : elle prend une rue pour une arete alors qu'une rue en porte
	# jusqu'a trois, et sur Corbeny — 7 rues, 12 carrefours — elle rend 7 - 12
	# + 1 = -4, donc "false" sur un bourg dont on fait le tour du pate. Le
	# nombre cyclomatique se compte aretes - noeuds + morceaux, et rien d'autre.
	var cyc_min := 1 << 30
	var comps_max := 0
	var routes := 0
	var routes_ok := 0
	var hops_max := 0
	for p in plans:
		var nv: int = p.junction_count()
		var parent := PackedInt32Array()
		parent.resize(nv)
		for k in nv:
			parent[k] = k
		var ne := 0
		for i in p.streets.size():
			var cross: bool = p.streets[i]["kind"] == "cross"
			var along := []
			for j in nv:
				if p.junction_a(j) != i and p.junction_b(j) != i:
					continue
				var su: Vector2 = p.junction_su(j)
				along.append([su.y if cross else su.x, j])
			along.sort_custom(func(u, v): return u[0] < v[0])
			for k in along.size() - 1:
				ne += 1
				_plan_union(parent, along[k][1], along[k + 1][1])
		var roots := {}
		for k in nv:
			roots[_plan_find(parent, k)] = true
		comps_max = maxi(comps_max, roots.size())
		cyc_min = mini(cyc_min, ne - nv + roots.size())
		# Du panneau d'entree (s = 0, u = 0, sur le tronc) a chacune des quatre
		# portes. Une liste non vide ne suffit pas : on verifie que deux rues
		# consecutives de l'itineraire se croisent vraiment, et que la derniere
		# est bien celle de l'adresse.
		for k in p.addrs.size():
			routes += 1
			var r: PackedInt32Array = p.route(Vector2.ZERO, p.addr_su(k))
			hops_max = maxi(hops_max, r.size())
			var ok: bool = r.size() > 0 and r[r.size() - 1] == int(p.addrs[k]["street"])
			for m in r.size() - 1:
				var linked := false
				for j in nv:
					var ja: int = p.junction_a(j)
					var jb: int = p.junction_b(j)
					if (ja == r[m] and jb == r[m + 1]) or (ja == r[m + 1] and jb == r[m]):
						linked = true
				if not linked:
					ok = false
			if ok:
				routes_ok += 1
	print("  LE GRAPHE EST CONNEXE ET BOUCLE        : %s   (1 seul morceau par bourg : %d au pire ; cycles mini %d — aretes - noeuds + morceaux sur le graphe des carrefours —, seuil 1 ; %d/%d itineraires du panneau a une porte, %d rues au plus)" % [
		comps_max == 1 and cyc_min >= 1 and routes_ok == routes,
		comps_max, cyc_min, routes_ok, routes, hops_max])

	# --- ce qui est bati ---------------------------------------------------
	print("--- ce qui est bati ----------------------------------------------")
	# La marge se mesure de l'EMPREINTE a l'AXE, sur les quatre cotes du
	# rectangle et sur TOUTES les rues, la sienne comprise — town_plan.gd, lui,
	# saute sa propre rue (il a le droit : le retrait la garantit). Un banc qui
	# sauterait la meme rue ne verrait jamais un retrait mal pose.
	#
	# CE QUI A CHANGE, ET POURQUOI CETTE LIGNE NE POUVAIT PAS ROUGIR. Le seuil
	# etait "worst_clear >= 4.5" : un seul nombre pour tout le bourg, et ce
	# nombre etait la valeur qu'avait alors KEEP_CLEAR dans le fichier juge. Le
	# banc recitait la constante de l'accuse au lieu de mesurer sa promesse.
	# Deux consequences, toutes deux payees :
	#  - du seul cote que le generateur ne verifie pas lui-meme — la rue de la
	#    maison, garantie par le retrait —, la ligne ne pouvait pratiquement
	#    pas descendre jusqu'au seuil : SETBACK pose la facade a 6,0 m de
	#    l'axe, et le lacet de 4 degres ne rapproche le coin d'une facade de
	#    13 m que de 6,5 x sin(4) = 0,45 m. Soit 5,55 m pour 4,5 demandes,
	#    1,05 m d'avance permanente et rien a mesurer ;
	#  - surtout, 4,5 derivait de l'emprise d'une RUE (4,2 m de l'axe au bord
	#    de trottoir) et le bourg en a DEUX : le tronc en tient 8,0. Deux
	#    maisons de Vieux-Bourg ont tenu 0,21 m DANS le trottoir de la
	#    nationale — 7,79 m de l'axe pour 8,0 d'emprise — pendant que cette
	#    ligne affichait "true" sous le titre AUCUN BATIMENT SUR UNE RUE. Le
	#    titre etait faux deux fois et le banc ne l'a jamais dit.
	#
	# On compare donc rue par rue, a l'EMPRISE DE LA RUE PORTEUSE, resommee
	# ici a la main depuis les trois nombres bruts du plan (demi-chaussee +
	# accotement + trottoir) : ni edge_half(), ni KEEP_CLEAR, ni 4,5. Une marge
	# negative, c'est un mur dans le trottoir : rouge, et on dit quelle ville.
	#
	# VERIFIE EN LE CASSANT, sur une copie jetable du depot : la garde des murs
	# remise a plat (_se = 4,5 m pour toutes les rues, l'etat d'avant la
	# correction de town_plan.gd), cette ligne tombe a false — 14 empietements,
	# un mur a 2,639 m DANS le trottoir de la nationale, a Malassis. Sur le
	# MEME plan, l'ancienne ligne imprimait "true (marge mini facade/axe
	# 4.579 m, seuil 4,5)" : elle voyait le 4,579 d'une venelle, qui a 0,379 m
	# d'avance sur son emprise de 4,2, et jamais le 5,361 du tronc, qui en
	# manque 2,639 a la sienne de 8,0. La copie remise en etat : true.
	var nb := 0
	var nbi := 0
	var pokes := 0
	# Trois genres de rue, trois emprises, trois marges a suivre : melangees en
	# un seul minimum, celle du tronc — la plus large, donc la plus exposee —
	# disparaissait derriere celle des venelles.
	var clear := [1.0e9, 1.0e9, 1.0e9]
	var worst_m := 1.0e9
	var worst_who := ""
	for p in plans:
		for k in p.bld_count():
			nb += 1
			var co := _plan_corners(p, k)
			for i in p.streets.size():
				nbi += 1
				var m := _plan_rect_axis(p, co, i) - _plan_emprise(p, i)
				var g := _plan_genre(p, i)
				clear[g] = minf(clear[g], m)
				if m < 0.0:
					pokes += 1
				if m < worst_m:
					worst_m = m
					worst_who = "%s, %s" % [p.id, p.streets[i]["kind"]]
	print("  AUCUN BATIMENT SUR UNE RUE        : %s   (%d batiments, %d couples mur/rue, %d empietement(s) ; marge du mur au BORD DE TROTTOIR, au plus juste : tronc %+.3f m, transversale %+.3f, parallele %+.3f ; pire cas %+.3f m sur %s)" % [
		pokes == 0, nb, nbi, pokes, clear[0], clear[1], clear[2], worst_m, worst_who])

	# Une adresse doit tomber sur le TROTTOIR : trop pres, le client attend sur
	# la chaussee ; trop loin, il attend dans un salon. Et jamais sur le tronc,
	# ou le trottoir commence a 5,8 m alors que la baie de validation s'arrete
	# a 5,0 (PLAN_VILLES.md:300) — on s'y garerait sur la nationale.
	#
	# CE QUI A CHANGE, ET POURQUOI CETTE LIGNE MESURAIT UNE CONSTANTE. Elle
	# demandait "l'ecart a l'axe est entre 2,6 et 6,0 m" — la fenetre de
	# PLAN_VILLES.md:485 — a un point qui vaut, par construction,
	# point(i, t, side * walk_mid(i)) : l'ecart a l'axe EST walk_mid(i), donc
	# 3,40 m sur une rue, et le releve le disait tout haut, "de 3.40 a 3.40".
	# Une constante comparee a une fenetre qui l'entoure de 0,8 m d'un cote et
	# de 2,6 m de l'autre : aucun tirage ne pouvait la faire rougir.
	#
	# Pire : le SEUL cas que cette fenetre aurait attrape — une adresse sur le
	# tronc, a 6,90 m de l'axe — etait deja compte dans on_trunk, imprime juste
	# a cote... et absent du booleen. Le banc voyait le defaut, l'affichait, et
	# rendait "true".
	#
	# Quatre mesures a la place, dont aucune n'est walk_mid deguise :
	#  1. le tronc est refuse, ET C'EST DANS LE VERDICT. _lay_addrs le filtre
	#     aujourd'hui (town_plan.gd:1010-1012), rien ne le garantit demain, et
	#     une porte sur la nationale est une course impossible a valider ;
	#  2. l'ecart tombe dans la BANDE DE TROTTOIR DE LA RUE PORTEUSE — de
	#     half + shoulder au bord de l'emprise, soit 2,6 a 4,2 m sur une rue et
	#     5,8 a 8,0 sur le tronc —, et non plus dans une fenetre unique qui
	#     pretendait valoir pour les deux emprises a la fois ;
	#  3. l'abscisse tombe dans l'ETENDUE de la rue : une porte 40 m apres le
	#     bout de sa venelle est sur le trottoir de personne ;
	#  4. le compte y est. QUATRE portes par ville (PLAN_VILLES.md:298), pas
	#     trois : _lay_addrs abandonne au bout de 600 essais, et une course
	#     sans arrivee n'existe pas. "na > 0" acceptait une seule porte pour
	#     les huit bourgs.
	#
	# VERIFIE EN LE CASSANT, quatre fois, sur une copie jetable du depot ;
	# entre chaque, remise en etat et retour au vert :
	#  - le tronc laisse entrer dans le tirage des portes : false, 8 portes sur
	#    le tronc. L'ancienne ligne rougissait aussi — c'etait le seul cas
	#    qu'elle attrapait, et par accident : par le 6,90 m, pas par le tronc ;
	#  - la porte posee 1,5 m plus loin que le milieu du trottoir : false, 32
	#    hors bande, 0,70 m au-dela du bord. ANCIENNE LIGNE, meme plan : "true
	#    (de 4.90 a 4.90 m, fenetre 2,6-6,0)" — trente-deux clients qui
	#    attendent dans un salon, et un verdict vert ;
	#  - l'abscisse poussee de 40 m au-dela du bout de sa rue : false, 17 hors
	#    de leur rue, 38,0 m au-dela du bout ;
	#  - ADDR_N ramene a 3 : false, 24 portes pour 8 bourgs. ANCIENNE LIGNE :
	#    "true (24 adresses, de 3.40 a 3.40 m)" — huit villes amputees d'une
	#    porte, et un verdict vert.
	var na := 0
	var on_trunk := 0
	var off_band := 0
	var off_end := 0
	var in_lo := 1.0e9      # marge au bord INTERIEUR du trottoir (le caniveau)
	var in_hi := 1.0e9      # marge au bord EXTERIEUR (le pied des facades)
	var end_lo := 1.0e9     # marge au bout de la rue, le long de celle-ci
	for p in plans:
		for k in p.addrs.size():
			na += 1
			var i: int = p.addrs[k]["street"]
			var st: Dictionary = p.streets[i]
			if st["kind"] == "trunk":
				on_trunk += 1
			var d := _plan_axis_dist(p, i, p.addr_su(k))
			var lo := float(st["half"]) + float(st["shoulder"])
			var hi := _plan_emprise(p, i)
			in_lo = minf(in_lo, d - lo)
			in_hi = minf(in_hi, hi - d)
			if d < lo or d > hi:
				off_band += 1
			var t := float(p.addrs[k]["t"])
			end_lo = minf(end_lo, minf(t - float(st["a"]), float(st["b"]) - t))
			if t < float(st["a"]) or t > float(st["b"]):
				off_end += 1
	print("  LES ADRESSES SONT SUR UN TROTTOIR : %s   (%d portes pour %d bourgs ; %d sur le tronc, %d hors de la bande de trottoir de leur rue, %d hors de leur rue ; marge mini au caniveau %+.2f m, au mur %+.2f m, au bout de la rue %+.1f m)" % [
		na == plans.size() * 4 and on_trunk == 0 and off_band == 0 and off_end == 0,
		na, plans.size(), on_trunk, off_band, off_end, in_lo, in_hi, end_lo])

	# --- la recherche du plus proche ---------------------------------------
	print("--- la recherche du plus proche ----------------------------------")
	# La grille de 20 m ne sert pas a aller vite — il y a sept rues — mais a ce
	# que le GPS puisse appeler nearest() a chaque image sans que le cout
	# depende de la taille du bourg. Sa reponse doit donc etre EXACTE, pas
	# approchee : on la confronte au balayage complet sur deux mille points.
	# La graine du banc est ecrite : un desaccord se rejoue a l'identique.
	#
	# OU L'ON TIRE LES POINTS, ET POURQUOI CE N'EST PLUS SEULEMENT AUTOUR DU
	# BOURG. Ce banc a tire ses 2 000 points dans bounds.grow(20) PILE — vingt
	# metres de marge autour d'une enveloppe de 340 x 112 m. Dans cette bande,
	# la grille couvre tout, la preuve d'optimalite vient toujours, et le
	# rattrapage de nearest() (town_plan.gd:550-565, le balayage qui finit le
	# travail quand les anneaux s'epuisent sans preuve) NE SERT JAMAIS. Le banc
	# le gardait donc sans jamais le voir. A/B, ce rattrapage retire :
	#   grow(+20)  : 0 faux sur 2 000     grow(+300) : 0 faux sur 2 000
	#   grow(+600) : 1 049 faux sur 2 000, ecart maxi 90 m
	# Vert, vert, et rouge — le meme banc, la meme panne, la seule difference
	# etant la boite de tirage. Un test de non-regression qui ne peut pas voir
	# la panne qu'il garde ne garde rien : il rassure. Un point a 600 m du
	# bourg n'est pas une lubie de banc, c'est le GPS qui interroge le plan de
	# la ville d'a cote pendant qu'on roule entre deux bourgs — la plus courte
	# arete de la carte fait 950 m.
	#
	# UN TIERS DES POINTS PART DONC A grow(600), et le verdict se lit en deux
	# temps parce que les deux zones ne promettent pas la meme chose :
	#  - la REPONSE doit etre exacte PARTOUT, pres comme loin. C'est la moitie
	#    de la ligne qui etait aveugle.
	#  - le COUT en troncons ne se juge que PRES. Hors de l'enveloppe, la
	#    grille n'a plus une seule case a offrir et nearest() descend
	#    volontairement au balayage a deux mailles du bord (town_plan.gd:521,
	#    releve dans ce fichier-la : 626 us de cases vides balayees avant, 2,6
	#    apres). `seen` y vaut donc streets.size() par CHOIX, et non par panne :
	#    compter ces points-la comme "payes au prix du balayage complet"
	#    rougirait sur un correctif, pas sur un defaut.
	#
	# LE SECOND SEUIL, LUI, NE POUVAIT PAS ROUGIR : c'etait "seen_max < 12".
	# Une ville porte au plus SEPT rues — une traversante, quatre transversales
	# (CROSS_N.y) et deux paralleles (RAIL_N.y) —, nearest() marque chaque rue
	# une seule fois dans son masque de bits, et le balayage de secours ne
	# visite que les rues non marquees. Le plafond arithmetique de `seen` vaut
	# donc 7, le releve en donnait 4, et le seuil en demandait 12 : cinq de
	# plus que le maximum atteignable. Aucun bourg, aucune graine, aucune
	# panne de la grille ne pouvait faire rougir cette moitie de ligne.
	#
	# Ce qu'on mesure maintenant DEPEND du bourg, puisqu'on le compare au
	# bourg : PRES DU BOURG, la grille doit toujours couter MOINS que le
	# balayage complet de cette ville-la. C'est exactement ce qui casse quand
	# elle degenere — grille vide, anneaux a zero, cle mal calculee : la boucle
	# sort sans preuve, le secours de town_plan.gd:550-565 balaie, `seen` monte
	# a streets.size() pile, et la ligne rougit. Le nombre de CASES visitees
	# serait plus fin encore, mais il vit a l'interieur de nearest() : il
	# faudrait instrumenter le fichier qu'on juge, et ce banc s'interdit de le
	# faire. On imprime a la place le cout moyen du plus petit bourg et celui
	# du plus grand : c'est la, en clair, que se lit "le cout ne suit pas la
	# taille de la ville" — 1,73 troncon sur les 5 rues des Essarts, 2,13 sur
	# un bourg qui en porte 7, quand le balayage complet couterait 5 et 7.
	#
	# VERIFIE EN LE CASSANT, DEUX FOIS, sur une copie jetable du depot.
	#
	# (1) _rings force a 0 — la grille rend la case du point et rien de plus,
	# la preuve ne vient jamais, le secours balaie. Cette ligne : false, les
	# 1 328 points proches TOUS payes au prix du balayage complet, cout moyen
	# 5,00 troncons sur le bourg a 5 rues et 7,00 sur celui a 7 — le cout suit
	# alors exactement la taille de la ville, ce que la grille existe pour
	# eviter. L'ANCIENNE LIGNE, meme plan, meme panne : "true (troncons visites
	# maxi 7, seuil 12)".
	#
	# (2) le rattrapage retire (`if not proved:` force a faux) — la reponse
	# devient fausse la ou les anneaux s'epuisent sans preuve. Cette ligne :
	# false, et le releve dit ou : 0 desaccord sur les 1 328 points proches,
	# 648 sur les 672 points loin, DANS LA MEME EXECUTION. C'est l'A/B en une
	# ligne : la boite de tirage d'hier ne pouvait pas voir cette panne-la, la
	# boite d'aujourd'hui la crie. Les couts, eux, s'effondrent a 0,04 et 0,12
	# troncon au large — un banc qui n'aurait regarde que le cout aurait vu la
	# panne comme un progres.
	#
	# La copie remise en etat, les deux fois : true.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260829
	var pts := 0
	var far_pts := 0
	var wrong := 0
	var wrong_far := 0
	var seen_max := 0
	var full := 0
	var costs := []
	for p in plans:
		var bb: Rect2 = (p.bounds as Rect2).grow(20.0)
		var wide: Rect2 = (p.bounds as Rect2).grow(600.0)
		var sum := 0
		var near_n := 0
		var fsum := 0
		for n in 250:
			pts += 1
			# Un point sur trois est tire au LARGE. La boite large contient la
			# petite — 2,9 % de son aire —, donc deux ou trois points "loin"
			# retombent pres du bourg par le tirage : ils sont comptes au
			# large quand meme, et c'est ce qui abaisse un peu le cout moyen
			# imprime pour cette zone sous le compte de rues.
			var far: bool = n % 3 == 0
			var box: Rect2 = wide if far else bb
			var su := Vector2(rng.randf_range(box.position.x, box.end.x),
				rng.randf_range(box.position.y, box.end.y))
			var got: Dictionary = p.nearest(su)
			var s := int(got["seen"])
			var best := 1.0e18
			for i in p.streets.size():
				best = minf(best, _plan_axis_dist(p, i, su))
			var bad: bool = absf(float(got["dist"]) - best) > 0.001
			if far:
				far_pts += 1
				fsum += s
				if bad:
					wrong_far += 1
				continue
			near_n += 1
			sum += s
			seen_max = maxi(seen_max, s)
			# Le balayage complet, c'est la grille qui n'a servi a rien — et
			# PRES du bourg, elle n'a aucune excuse : toutes ses cases sont la.
			if s >= p.streets.size():
				full += 1
			if bad:
				wrong += 1
		costs.append([p.streets.size(), float(sum) / float(near_n),
			float(fsum) / float(250 - near_n)])
	costs.sort_custom(func(u, v): return u[0] < v[0])
	print("  LA GRILLE REPOND JUSTE : %s   (%d points tires, dont %d a 600 m du bourg ; %d desaccord(s) avec le balayage complet pres, %d loin ; pres : %d point(s) payes au prix du balayage complet, troncons visites maxi %d, cout moyen %.2f troncon(s) sur un bourg de %d rues et %.2f sur un bourg de %d ; loin : %.2f et %.2f troncons, le balayage assume)" % [
		wrong == 0 and wrong_far == 0 and full == 0,
		pts, far_pts, wrong, wrong_far, full, seen_max,
		costs[0][1], costs[0][0], costs[-1][1], costs[-1][0],
		costs[0][2], costs[-1][2]])

	# --- la couture avec le ruban ------------------------------------------
	print("--- la couture avec le ruban -------------------------------------")
	# CE QU'IL Y AVAIT ICI : "LE RUBAN N'A PAS BOUGE : voir maptest", puis une
	# phrase. Un titre d'invariant en capitales, deux-points, une explication —
	# la forme exacte d'un verdict, sans booleen dedans. On la lisait verte
	# parce qu'elle ne disait rien, et une ligne qui ne peut pas rougir sous un
	# nom d'invariant est pire qu'une ligne absente : elle rassure. Le renvoi,
	# lui, etait juste — c'est maptest qui roule et qui mesure ce ruban-la —,
	# il descend donc en note, en bas, sans capitales et sans deux-points.
	#
	# A la place, ce que CE banc peut vraiment mesurer sans rouler une image :
	# LA COUTURE. town_plan.gd recopie a la main trois nombres de road.gd —
	# STEP (road.gd:36), ROAD_HALF (:39), SHOULDER (:40) — parce qu'un preload
	# refermerait la boucle road -> town -> town_plan -> road ; il l'ecrit
	# lui-meme (town_plan.gd:62-70 — ou ses propres renvois, "road.gd:32" et
	# "road.gd:35-36", ont pris quatre lignes de retard sur le fichier ; c'est
	# deja la copie qui derive, en petit). Une constante recopiee derive en
	# silence : le jour ou la nationale s'elargit, le tronc du bourg garde
	# l'ancienne largeur, et le joueur prend un decrochement de trottoir a
	# 90 km/h a l'entree de la ville. Le banc, lui, a le droit de charger les
	# deux fichiers et de comparer. Et on ne s'arrete pas aux constantes : on
	# verifie que le tronc de chacun des huit plans PORTE ces cotes-la — la
	# constante peut etre juste et _lay_streets poser autre chose.
	#
	# VERIFIE EN LE CASSANT : ROAD_HALF porte de 3,4 a 3,6 dans road.gd, sur
	# une copie jetable. Cette ligne : false, "demi-chaussee 3.40 = 3.60".
	# L'ancienne ligne, elle, n'avait rien a dire de la panne : elle n'avait
	# pas de booleen a rendre. La copie remise en etat : true.
	var seam: bool = TownPlan.STEP == RoadScript.STEP \
		and TownPlan.TRUNK_HALF == RoadScript.ROAD_HALF \
		and TownPlan.SHOULDER == RoadScript.SHOULDER
	var trunks := 0
	var sewn := 0
	for p in plans:
		for i in p.streets.size():
			if p.streets[i]["kind"] != "trunk":
				continue
			trunks += 1
			if absf(float(p.streets[i]["half"]) - RoadScript.ROAD_HALF) <= 0.001 \
					and absf(float(p.streets[i]["shoulder"]) - RoadScript.SHOULDER) <= 0.001:
				sewn += 1
	print("  LA VILLE SE COUD AU RUBAN : %s   (pas %.2f = %.2f m, demi-chaussee %.2f = %.2f, accotement %.2f = %.2f ; %d tronc(s) sur %d aux cotes exactes de la nationale, un par bourg pour %d bourgs)" % [
		seam and trunks == plans.size() and sewn == trunks,
		TownPlan.STEP, RoadScript.STEP,
		TownPlan.TRUNK_HALF, RoadScript.ROAD_HALF,
		TownPlan.SHOULDER, RoadScript.SHOULDER,
		sewn, trunks, plans.size()])
	print("  (note, pas un invariant : le ruban lui-meme ne se juge pas sur de la donnee. C'est LE RUBAN EST SANS COUTURE, dans maptest, qui roule et qui mesure le ruban echange — |pas - STEP| < 0,01 m et virage < 1,72 deg/pas, le plafond du brin mort —, et LE RUBAN RESTE SANS COUTURE, dans rubantest, qui mesure les deux raccords de la ville.)")

	# --- les huit bourgs, vus du dessus ------------------------------------
	print("--- les huit bourgs, vus du dessus -------------------------------")
	print("  '=' la traversante | '|' une transversale | '-' une parallele | '+' un carrefour | '#' une maison | '>' le panneau d'entree et la sortie | '1'-'4' les portes")
	print("  une colonne = 6 m le long de la route, une ligne = 10 m en travers ; le sens de la marche va vers la DROITE, et +u (la droite du conducteur qui entre) vers le BAS")
	for p in plans:
		_plan_trace(p)

	get_tree().quit()


## Les octets d'un plan : tout ce qui a ete tire, et rien de ce qui en derive.
## C'est ce qu'on compare d'un tirage a l'autre.
func _plan_sig(p) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(var_to_bytes(p.streets))
	out.append_array(var_to_bytes(p.junctions))
	out.append_array(var_to_bytes(p.lamps))
	out.append_array(var_to_bytes(p.blds))
	out.append_array(var_to_bytes(p.addrs))
	out.append_array(var_to_bytes(p.bounds))
	return out


## Un bout de l'axe d'une rue, dans le plan : `e` vaut 0 pour le debut, 1 pour
## la fin.
func _plan_end(p, i: int, e: int) -> Vector2:
	return p.point(i, float(p.streets[i]["b" if e == 1 else "a"]))


## Les quatre coins d'un batiment, recalcules depuis le 7-uplet brut : le lacet
## est l'angle de la FACADE, la profondeur le suit, la largeur lui est
## perpendiculaire.
func _plan_corners(p, k: int) -> PackedVector2Array:
	var o := k * 7
	var c := Vector2(p.blds[o], p.blds[o + 1])
	var w: float = p.blds[o + 2]
	var d: float = p.blds[o + 3]
	var f := Vector2(cos(p.blds[o + 5]), sin(p.blds[o + 5]))
	var r := Vector2(-f.y, f.x)
	var out := PackedVector2Array()
	out.append(c + f * (d * 0.5) + r * (w * 0.5))
	out.append(c + f * (d * 0.5) - r * (w * 0.5))
	out.append(c - f * (d * 0.5) - r * (w * 0.5))
	out.append(c - f * (d * 0.5) + r * (w * 0.5))
	return out


func _plan_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1.0e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


func _plan_seg_seg(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null:
		return 0.0
	return minf(minf(_plan_seg_dist(p1, q1, q2), _plan_seg_dist(p2, q1, q2)),
		minf(_plan_seg_dist(q1, p1, p2), _plan_seg_dist(q2, p1, p2)))


## La distance d'un point a l'AXE de la rue `i`, borne compris.
func _plan_axis_dist(p, i: int, su: Vector2) -> float:
	return _plan_seg_dist(su, _plan_end(p, i, 0), _plan_end(p, i, 1))


## L'EMPRISE de la rue `i` : de l'axe au bord du trottoir. 8,0 m sur le tronc
## (3,4 de chaussee + 2,4 d'accotement + 2,2 de trottoir), 4,2 sur une rue
## (2,6 + 0 + 1,6). C'est la seule largeur qui vaille pour juger un mur ou une
## porte, et c'est le bourg lui-meme qui la declare, rue par rue.
##
## Resommee ici a la main depuis les trois nombres bruts du plan, et pas prise
## a edge_half() : le banc lit la DONNEE de l'accuse, jamais son calcul. La
## nuance n'est pas theorique — le seuil unique de 4,5 m qui trainait dans ce
## banc etait justement un edge_half() de rue recopie a la main, et il a laisse
## passer deux maisons dans le trottoir de la nationale.
func _plan_emprise(p, i: int) -> float:
	var st: Dictionary = p.streets[i]
	return float(st["half"]) + float(st["shoulder"]) + float(st["walk"])


## Le genre d'une rue, pour ranger un releve : 0 le tronc (la nationale qui
## traverse le bourg), 1 une transversale, 2 une parallele. Trois genres, deux
## emprises — et c'est parce qu'un seul minimum les melangeait que celle du
## tronc, la plus large donc la plus exposee, disparaissait derriere celle des
## venelles.
func _plan_genre(p, i: int) -> int:
	var kind: String = p.streets[i]["kind"]
	if kind == "trunk":
		return 0
	return 1 if kind == "cross" else 2


## La distance d'une empreinte a l'axe de la rue `i`. Zero si l'axe traverse la
## maison de part en part : c'est le cas qu'un test de coins seuls laisserait
## passer avec une distance bien positive, et c'est le seul qui compte.
func _plan_rect_axis(p, co: PackedVector2Array, i: int) -> float:
	var a := _plan_end(p, i, 0)
	var b := _plan_end(p, i, 1)
	if Geometry2D.is_point_in_polygon(a, co) or Geometry2D.is_point_in_polygon(b, co):
		return 0.0
	var best := 1.0e18
	for k in 4:
		best = minf(best, _plan_seg_seg(a, b, co[k], co[(k + 1) % 4]))
	return best


func _plan_find(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		r = parent[r]
	return r


func _plan_union(parent: PackedInt32Array, i: int, j: int) -> void:
	var a := _plan_find(parent, i)
	var b := _plan_find(parent, j)
	if a != b:
		parent[b] = a


## Le bourg vu du dessus, en caracteres. Six metres par colonne et dix par
## ligne : dans une console ou un caractere est deux fois plus haut que large,
## ca rend la ville a peu pres a sa forme, et une rangee de maisons a 9-14 m
## d'entraxe laisse un '#' toutes les une ou deux colonnes — on lit une rangee,
## pas un mur.
func _plan_trace(p) -> void:
	var cs := 6.0
	var cu := 10.0
	var bb: Rect2 = p.bounds
	var cols := int(ceil(bb.size.x / cs)) + 1
	var rows := int(ceil(bb.size.y / cu)) + 1
	var grid := []
	for r in rows:
		var line := PackedByteArray()
		line.resize(cols)
		line.fill(32)
		grid.append(line)

	# L'ordre de peinture EST la hierarchie de lecture : le bati d'abord, les
	# rues par-dessus, les carrefours ensuite, les portes en dernier. Ce qui
	# compte le plus est ce qui survit.
	for k in p.bld_count():
		_plan_put(grid, bb, cs, cu, Vector2(p.blds[k * 7], p.blds[k * 7 + 1]), 35)
	for i in p.streets.size():
		var st: Dictionary = p.streets[i]
		var ch := 124
		if st["kind"] == "trunk":
			ch = 61
		elif st["kind"] == "rail":
			ch = 45
		var t: float = st["a"]
		while t <= float(st["b"]):
			_plan_put(grid, bb, cs, cu, p.point(i, t), ch)
			t += 3.0
	for j in p.junction_count():
		_plan_put(grid, bb, cs, cu, p.junction_su(j), 43)
	for k in p.addrs.size():
		_plan_put(grid, bb, cs, cu, p.addr_su(k), 49 + k)
	_plan_put(grid, bb, cs, cu, Vector2.ZERO, 62)
	_plan_put(grid, bb, cs, cu, Vector2(p.cross_len(), 0.0), 62)

	print("")
	print("  %s — graine %d — %d rues, %d carrefours, %d maisons, %d mats, %.0f m de rue cumules, etendue %.0f x %.0f m" % [
		p.id, MapScript.seed_of(p.id), p.streets.size(), p.junction_count(),
		p.bld_count(), p.lamp_count(), p.total_len(), bb.size.x, bb.size.y])
	for line in grid:
		print("    " + (line as PackedByteArray).get_string_from_ascii())
	var names := []
	for i in p.streets.size():
		names.append("%s [%s]" % [p.streets[i]["name"], p.streets[i]["kind"]])
	print("    rues : " + ", ".join(names))
	for k in p.addrs.size():
		var a: Dictionary = p.addrs[k]
		var amen: String = a["amen"]
		print("    %d = %s%s" % [k + 1, a["name"],
			"  (%s)" % amen if amen != "" else ""])


func _plan_put(grid: Array, bb: Rect2, cs: float, cu: float, su: Vector2, ch: int) -> void:
	var r := int(floor((su.y - bb.position.y) / cu))
	if r < 0 or r >= grid.size():
		return
	var line: PackedByteArray = grid[r]
	var c := int(floor((su.x - bb.position.x) / cs))
	if c < 0 or c >= line.size():
		return
	line[c] = ch
	grid[r] = line


# --------------------------------------------------------------------------
# Banc d'essai du ruban en ville
# --------------------------------------------------------------------------

## LE PREMIER BANC DU RUBAN. road.gd tient la route depuis le premier jour et
## n'a jamais eu de juge a lui : maptest mesure la CARTE et ne se sert du ruban
## que pour y arriver, plantest ne demarre meme pas la nuit. Tout ce que le J2
## a pose dans road.gd — la tangente d'avance, la traversee pre-calculee, la
## courbure bornee, le silence des props, le portail exempte — n'etait donc
## prouve que de biais.
##
## CE QUE CE BANC MESURE, ET DANS QUEL ORDRE : il roule une nuit courte. Cent
## metres en travers de la route au depart (la tangente), cinq kilometres de
## transit (l'ulp du float32 vaut 1 mm a 10 km : une couture mesuree a froid
## prouverait la mauvaise chose), une traversee de bourg conduite AU VOLANT et
## non au rail, puis un Y pris par la sortie.
##
## POURQUOI IL RAMASSE LES ECHANTILLONS A MESURE. La fenetre vivante n'en porte
## que 150 (300 m) ; la traversee dessinee en fait 171 et la zone de silence des
## props 211. Aucun instant du banc ne les voit tous : on les range dans un
## dictionnaire indexe par ECHANTILLON GLOBAL, un a un, a mesure qu'ils naissent
## (_ruban_record). C'est le seul moyen de juger une ville entiere.
##
## CE QU'IL EMPRUNTE AUX MEMBRES PRIVES, ET POURQUOI. Trois choses : _town_heads
## (la traversee pre-calculee — c'est justement l'objet de la mesure, et rien de
## public ne la rend), _trees / _poles (les pools de decor, qu'aucune API ne
## liste), et _pos / _closest_index / _bpos / _fork_main pour conduire, comme le fait
## deja _rail. Un banc a le droit d'ouvrir le capot ; c'est taxi.gd qui ne l'a
## pas, et LE JUGE NE LIT PLUS LES PRIVES le verifie ligne a ligne.


## Le conducteur A BANDE MORTE : il ne touche au volant que quand il le DOIT.
##
## LE PIEGE, ET IL EST DE TAILLE : le rail des autres bancs POSE la voiture sur
## sa voie (position laterale et cap ecrits a la main) et ne se sert jamais du
## volant. car.steer y reste a 0,000 d'un bout a l'autre. Un banc qui
## demanderait au rail si le volant travaille aurait sa reponse d'avance, et
## elle serait fausse dans les deux sens.
##
## Celui-ci conduit pour de vrai — steer_left / steer_right, les memes actions
## que le joueur — et ne corrige que quand l'ecart l'y force : erreur laterale
## a la voie visee, plus huit metres d'anticipation sur le cap (0,64 s a
## 12,5 m/s), contre une bande morte de 35 cm. Sur une route rigoureusement
## droite prise dans l'axe, il ne touche a rien et car.steer reste a zero —
## c'est exactement ce qu'on veut qu'il fasse, parce que c'est ce que la
## monotonie de sleep.gd compte (|car.steer| < 0,04 pendant mono_after = 10 s,
## sleep.gd:41 et 163).
##
## LA POUSSEE EST PROPORTIONNELLE, ET CE N'EST PAS UN DETAIL. Une premiere
## version poussait a fond des que la bande etait franchie : releve |steer|
## maxi 1,000, soit butee a butee dans une traversee a 45 km/h. La mesure
## restait vraie mais le mobile ne l'etait plus — un banc qui envoie la voiture
## de gauche a droite en pleine ville fabrique son propre volant, et n'apprend
## plus rien de la route. On pousse donc a la force de l'ecart : il faut
## 1,2 m de plus que la bande pour aller en butee.
func _ruban_drive(lane: float, band: float) -> void:
	var line: PackedVector3Array = road._pos
	var i: int = road._closest_index(line, car.global_position)
	var fwd := Vector3(0.0, 0.0, -1.0)
	if i + 1 < line.size():
		fwd = (line[i + 1] - line[i]).normalized()
	elif i > 0:
		fwd = (line[i] - line[i - 1]).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var err: float = (car.global_position - line[i]).dot(right) - lane
	var lead: float = (-car.global_transform.basis.z).dot(right)
	var ctrl: float = err + 8.0 * lead
	var push: float = clampf((absf(ctrl) - band) / 1.2, 0.0, 1.0)
	if ctrl > 0.0 and push > 0.0:
		Input.action_press("steer_left", push)
	else:
		Input.action_release("steer_left")
	if ctrl < 0.0 and push > 0.0:
		Input.action_press("steer_right", push)
	else:
		Input.action_release("steer_right")


## Range les echantillons de [a, b] qui sont NES et pas encore connus, par
## index global. sample_at rend l'identite hors fenetre : a cinq kilometres de
## l'origine, une origine a zero ne peut etre que ca.
func _ruban_record(rec: Dictionary, a: int, b: int) -> void:
	for g in range(a, b + 1):
		if rec.has(g):
			continue
		var tr: Transform3D = road.sample_at(g)
		if tr.origin == Vector3.ZERO:
			continue
		rec[g] = tr


## L'echantillon range le plus proche d'un point, et sa distance a l'axe :
## [index global, ecart lateral]. [-1, 0] si rien n'est range.
##
## C'est ce qui SITUE un arbre : un arbre est pose a `_pos[i] + _right[i] * off`
## avec off <= 20,4 m, donc l'echantillon le plus proche de lui est le sien.
func _ruban_nearest(rec: Dictionary, p: Vector3) -> Array:
	var best := -1
	var bd := 1.0e18
	for g in rec:
		var o: Vector3 = (rec[g] as Transform3D).origin
		var d: float = Vector2(p.x - o.x, p.z - o.z).length_squared()
		if d < bd:
			bd = d
			best = g
	return [best, sqrt(bd)]


func _ruban_test() -> void:
	var TownPlan := preload("res://scripts/town_plan.gd")
	await get_tree().create_timer(0.8).timeout
	_start_normal_world()
	# La jauge de veille ne bouge pas : ce banc roule cinq kilometres en temps
	# accelere, soit plusieurs fois full_span. Endormi, il basculerait dans le
	# cauchemar — et suspend_town() annulerait la ville qu'il mesure.
	sleep.full_span = 1.0e9
	car.gear = 5

	# --- la tangente d'avance ---------------------------------------------
	# ON LE FAIT LA, AVANT DE ROULER, ET C'EST VOULU. Au demarrage road.gd pose
	# _head sans rotation (road.gd:262) et _curve_goal vaut 0 pendant les 16
	# premiers echantillons : _pos[0..16] est RIGOUREUSEMENT droit, la voiture
	# est sur _pos[12] = head_index(), et le vecteur droite y est exactement
	# perpendiculaire a la tangente sous _pos[0]. Plus loin dans la nuit le
	# ruban serpente, la tangente sous _pos[0] et celle sous la voiture
	# divergent de douze echantillons de courbure, et 100 m de travers en
	# projetteraient jusqu'a 21 sur la premiere : le banc mesurerait la
	# courbure, pas la tangente.
	print("--- la tangente d'avance -----------------------------------------")
	var g_side: int = road.head_index()
	var side: Vector3 = (road.sample_at(g_side) as Transform3D).basis.x
	car.rotation.y = atan2(-side.x, -side.z)
	var p_side: Vector3 = car.global_position
	Engine.time_scale = 4.0
	var t := 0.0
	while t < 40.0 and Vector2(car.global_position.x - p_side.x,
			car.global_position.z - p_side.z).length() < 100.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = 25.0
	car.speed = 0.0
	var across: float = Vector2(car.global_position.x - p_side.x,
		car.global_position.z - p_side.z).length()
	var slid: int = road.head_index() - g_side
	# LE CHIFFRE D'AVANT N'EST PAS 38, ET LE PLAN SE TROMPAIT DANS LE BON SENS.
	# Son calcul — (100 - 24) / 2 — suppose que _pos[0] reste ou il est pendant
	# qu'on s'ecarte. Il n'y reste pas : il avance LE LONG DE LA ROUTE, donc
	# perpendiculairement au nez, et la projection sur le nez ne redescend
	# jamais. Le ruban defile tant que la route n'a pas assez tourne pour
	# rattraper les 100 m. Releve sur une copie cassee (la tangente rendue au
	# nez de la voiture, une ligne changee) : 261 echantillons, pas 38.
	print("  ROULER EN TRAVERS NE FAIT PLUS AVANCER LA ROUTE : %s   (%.0f m parcourus perpendiculairement a la route, %d echantillon(s) de defile pour un seuil de 2 ; sur le nez de la voiture, releve : 261)" % [
		across >= 99.0 and absi(slid) < 2, across, slid])

	# --- le transit : cinq kilometres avant de mesurer une couture ---------
	# L'ulp du float32 vaut 1 mm a 10 km de l'origine. Une couture mesuree sur
	# la premiere ville, a 950 m, tiendrait a 0,1 mm meme si le ruban RECALCULAIT
	# la traversee au lieu de la reposer : le banc dirait vrai sans avoir rien
	# prouve. On roule donc jusqu'au cinquieme bourg.
	Engine.time_scale = 6.0
	t = 0.0
	while t < 400.0 and float(road.head_index()) * RoadScript.STEP < 5000.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)

	# On attend l'armement SUIVANT, pas la ville qui traine : la bascule de
	# town_span().x de -1 a un index, c'est l'instant ou _simulate_town_path
	# vient de ranger ses 150 transforms et ou la ville s'est batie dessus.
	var g_arm := -1
	# LES TRANSFORMS ENTIERES, pas seulement leurs origines : le quadrillage du
	# bourg s'extrude sur le vecteur DROITE de chaque tete, donc un cap qui
	# differe cisaille les rues sans deplacer l'axe d'un millimetre. La couture
	# se mesure sur les deux.
	var heads: Array[Transform3D] = []
	var prev_in: int = (road.town_span() as Vector2i).x
	t = 0.0
	while t < 200.0 and g_arm < 0:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
		var sp: Vector2i = road.town_span()
		if sp.x >= 0 and prev_in < 0:
			g_arm = sp.x + TownPlan.PAD
			for h in road._town_heads:
				heads.append(h as Transform3D)
		prev_in = sp.x
	var t_in: int = (road.town_span() as Vector2i).x
	var t_out: int = (road.town_span() as Vector2i).y
	var t_end: int = t_out + TownPlan.PAD
	var quiet_a: int = t_in - RoadScript.PROP_QUIET
	var quiet_b: int = t_end + RoadScript.PROP_QUIET
	var rec_a: int = quiet_a - 60
	var rec_b: int = quiet_b + 60
	var rolled: float = float(road.head_index()) * RoadScript.STEP
	print("--- le bourg -----------------------------------------------------")
	print("  (\"%s\" armee a l'echantillon %d apres %.0f m roules ; elle dessine %d a %d, les props se taisent de %d a %d)" % [
		road.town.town_name, g_arm, rolled, t_in, t_end, quiet_a, quiet_b])

	# LE PORTAIL : demande MAINTENANT, a un echantillon du milieu de la
	# traversee. C'est l'invariant qui compte le plus du jalon — le portail est
	# la seule sortie du cauchemar, et un filtre de props trop large l'eteindrait
	# sans un bruit, enfermant le joueur dans le rouge parce qu'une ville s'est
	# trouvee sur son chemin.
	var want_portal: int = g_arm + TownPlan.CROSS / 2
	road.set_portal(want_portal)

	# --- la traversee, conduite au volant ---------------------------------
	var rec := {}
	var seen_tree := {}
	var seen_pole := {}
	var tree_gs := PackedInt32Array()
	var pole_gs := PackedInt32Array()
	var steer_gap := 0.0
	var steer_run := 0.0
	var steer_max := 0.0
	var cross_t := 0.0
	t = 0.0
	while t < 400.0 and road.head_index() <= quiet_b:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		t += dt
		# ON RANGE AVANT DE JUGER : l'arbre de l'echantillon qui vient de naitre
		# a besoin de son axe pour etre situe, et il nait dans la meme image.
		_ruban_record(rec, rec_a, rec_b)
		var hg: int = road.head_index()
		var driving: bool = hg >= t_in and hg <= t_end
		if driving:
			# 12,5 m/s = 45 km/h : la vitesse de traversee du plan (21 s pour
			# les 260 m). Au volant, pas au rail — voir _ruban_drive.
			Engine.time_scale = 2.0
			car.speed = 12.5
			_ruban_drive(1.2, 0.35)
		else:
			Engine.time_scale = 6.0
			car.speed = maxf(car.speed, 25.0)
			_rail(1.2)

		# Les props qui viennent de naitre. On ne balaye pas les 96 arbres
		# contre les 331 echantillons ranges a chaque image (32 000 distances) :
		# on ne regarde que ceux dont la POSITION A CHANGE, soit environ un par
		# image. Le pool tourne (96 arbres, 18 poteaux) et un arbre pose dans la
		# ville serait recouvert avant la fin du banc si on comptait a la fin.
		for k in road._trees.size():
			var tr: Node3D = road._trees[k]
			if not tr.visible:
				continue
			var p: Vector3 = tr.global_position
			if seen_tree.has(k) and seen_tree[k] == p:
				continue
			seen_tree[k] = p
			var nr: Array = _ruban_nearest(rec, p)
			var gg: int = nr[0]
			if gg < 0 or float(nr[1]) > 25.0:
				continue
			tree_gs.append(gg)
		for k in road._poles.size():
			var po: Node3D = road._poles[k]
			if not po.visible:
				continue
			var p2: Vector3 = po.global_position
			if seen_pole.has(k) and seen_pole[k] == p2:
				continue
			seen_pole[k] = p2
			var nr2: Array = _ruban_nearest(rec, p2)
			var gg2: int = nr2[0]
			if gg2 < 0 or float(nr2[1]) > 12.0:
				continue
			pole_gs.append(gg2)

		# Le volant, mesure PANNEAU A PANNEAU — la traversee de la section 4.1
		# du plan. Les 20 echantillons d'approche n'en sont pas : road.gd:412
		# les redresse expres pour qu'on arrive SUR un bourg, pas en glissade.
		if driving and hg >= g_arm and hg <= t_out:
			cross_t += dt
			steer_max = maxf(steer_max, absf(car.steer))
			if absf(car.steer) > 0.04:
				steer_gap = maxf(steer_gap, steer_run)
				steer_run = 0.0
			else:
				steer_run += dt
	steer_gap = maxf(steer_gap, steer_run)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	Engine.time_scale = 5.0

	# --- la couture : le ruban ET la ville sont le meme point --------------
	# Ce que la ville a recu a l'armement, tete par tete, contre ce que le ruban
	# a fini par poser — l'origine ET LE CAP. Le cap est neuf ici : le
	# quadrillage du bourg s'extrude sur le vecteur droite de chaque tete, donc
	# deux tetes au meme point mais de cap different cisaillent les rues sans
	# deplacer l'axe d'un millimetre. Il manquait a la mesure.
	#
	# CE QUE CETTE LIGNE NE MESURE PAS, et son ancien commentaire le pretendait
	# noir sur blanc : elle ne distingue pas "reposer" de "recalculer".
	# _simulate_town_path et _append_sample font la MEME arithmetique, dans le
	# MEME ordre, sur les MEMES float32 — origine plus STEP le long de -basis.z,
	# puis rotation locale de curve fois STEP. Un recalcul rendrait 0,0000 lui
	# aussi, bit pour bit, a cinq kilometres comme a cinquante. La
	# justification par l'ulp du float32 etait donc fausse par construction.
	#
	# ET LA GARDE QU'ELLE TRAINAIT NE GARDAIT RIEN. Le verdict portait
	# `rolled >= 5000.0` au nom d'un raisonnement sur la distance A L'ORIGINE
	# DU MONDE — deux grandeurs differentes, parce que le ruban serpente. Sur
	# six lancements la meme ligne a imprime 2063, 5312, 5364, 5447, 3042 et
	# 2957 m de l'origine pour 5 000 m ROULES : trois fois sur six la
	# precaution ne tenait pas, et la ligne restait verte en imprimant sa
	# propre contradiction. On roule toujours les 5 km — ce banc veut un bourg
	# qui vient apres des fourches, des props et quatre villes, pas le premier
	# de la nuit — mais les deux distances sont maintenant du DECOR imprime, et
	# plus un booleen.
	#
	# CE QU'ELLE MESURE VRAIMENT, ET C'EST DEJA TOUT CE QU'IL FAUT : que la
	# ville et le ruban parlent du MEME echantillon. Les pannes possibles sont
	# STRUCTURELLES, donc metriques, jamais au bit pres. Un decalage d'un pas —
	# road.gd le nomme lui-meme a l'endroit ou il l'evite, « L'inverser
	# decalerait la traversee d'un pas » — vaut 2 m, cent fois le seuil. Un
	# bourg arme sur un autre echantillon, un chemin rejoue depuis une autre
	# courbure, un _town_heads survivant a un echange de ruban : des dizaines
	# de metres. 0,02 m et 0,05 deg, c'est un ZERO avec de la place pour le
	# float, pas une tolerance.
	var seam := 0.0
	var seam_deg := 0.0
	var seam_n := 0
	for k in heads.size():
		var g: int = g_arm + 1 + k
		if not rec.has(g):
			continue
		seam_n += 1
		var got: Transform3D = rec[g]
		var want: Transform3D = heads[k]
		seam = maxf(seam, got.origin.distance_to(want.origin))
		# L'angle par atan2 et pas par acos : a 1e-7 pres de l'alignement,
		# acos rend son propre bruit (la derivee y est infinie) et un ecart
		# nul s'imprimerait a 0,03 deg. angle_to reste juste au zero.
		seam_deg = maxf(seam_deg, absf(rad_to_deg(
			Vector2(-got.basis.z.x, -got.basis.z.z).angle_to(
				Vector2(-want.basis.z.x, -want.basis.z.z)))))
	print("  LA COUTURE EST NETTE : %s   (%d transforms pre-calculees a l'armement, toutes retrouvees dans le ruban : %.4f m et %.4f deg d'ecart maxi, seuils 0,02 m et 0,05 deg — un decalage d'UN pas en ferait 2,000. Decor, pas seuil : releve a %.0f m de route roulee et %.0f m de l'origine du monde, et ces deux-la ne sont pas la meme grandeur)" % [
		seam_n == heads.size() and heads.size() > 0
		and seam < 0.02 and seam_deg < 0.05,
		seam_n, seam, seam_deg, rolled, car.global_position.length()])

	# --- la traversee ne se replie pas ------------------------------------
	# UNE MESURE, UN VERDICT — et c'est le correctif de cette ligne, qui
	# portait deux seuils pour une seule grandeur. La compression a 60 m de
	# l'axe vaut la courbure fois 60, exactement (rayon R, corde extrudee a
	# 60 m : 1 - 60/R). Avec un plafond de courbure a 0,0016 elle ne pouvait
	# donc pas depasser 9,6 % : elle etait STRUCTURELLEMENT incapable
	# d'atteindre son propre seuil de 12 sans que la courbure ait rougi une
	# ligne plus tot. Releve 8,1 a 8,6 %. Deux nombres, une mesure, et le
	# second ne pouvait jamais parler le premier.
	#
	# CELLE QU'ON GARDE EST CELLE QUE LE BOURG SUBIT, parce que c'est le titre
	# de la ligne : on EXTRUDE les deux lignes a 60 m de l'axe — la ou tombent
	# les bouts de transversale du plan — et on mesure le plus court de leurs
	# segments. Un quadrillage pose en coordonnees curvilignes se replie de ca,
	# pas de radians.
	#
	# LE SEUIL EST CELUI DE road.gd, ET IL EST ATTEIGNABLE. le commentaire de TOWN_CURVE, dans road.gd, pose les
	# deux bornes de son propre raisonnement : a TOWN_CURVE (0,0015 rad/m,
	# rayon 667 m) la compression vaut 9 % et « ne se voit pas » ; a MAX_CURVE
	# (rayon 111 m) elle vaut 54 % et « les ilots se replieraient sur
	# eux-memes ». 12 % est du bon cote, avec un tiers de marge sur les 9,0 %
	# que le plafond d'aujourd'hui autorise. Et il faut dire tout haut QUAND
	# cette ligne rougit, parce que ce n'est plus theorique : le jour ou le
	# clamp lache (courbure libre, 54 %), et le jour ou l'on desserre
	# TOWN_CURVE au-dela de 0,0020 rad/m. C'est exactement le marche que le
	# chantier du volant regarde — voir LE VOLANT TRAVAILLE EN VILLE plus bas,
	# qui tire dans l'autre sens et le dit aussi.
	#
	# La courbure reste imprimee, mais comme MECANISME et non comme verdict :
	# c'est elle qui produit la compression. Et l'approche est imprimee a part
	# parce qu'elle n'est PAS bridee, seulement redressee (la regle d'approche de _append_sample, `lerpf(_curve, 0.0, 0.4)`) — sans
	# la separer, on croirait le clamp casse a chaque lancement.
	var kmax := 0.0
	var kappr := 0.0
	for g in range(t_in + 1, t_end + 1):
		if not (rec.has(g - 1) and rec.has(g) and rec.has(g + 1)):
			continue
		var d0: Vector3 = ((rec[g] as Transform3D).origin - (rec[g - 1] as Transform3D).origin).normalized()
		var d1: Vector3 = ((rec[g + 1] as Transform3D).origin - (rec[g] as Transform3D).origin).normalized()
		var k: float = acos(clampf(d0.dot(d1), -1.0, 1.0)) / RoadScript.STEP
		if g > g_arm:
			kmax = maxf(kmax, k)
		else:
			kappr = maxf(kappr, k)
	var minseg: float = RoadScript.STEP
	var sq_n := 0
	for u in [-60.0, 60.0]:
		for g in range(g_arm, t_end):
			if not (rec.has(g) and rec.has(g + 1)):
				continue
			sq_n += 1
			var a: Transform3D = rec[g]
			var b: Transform3D = rec[g + 1]
			minseg = minf(minseg,
				(a.origin + a.basis.x * u).distance_to(b.origin + b.basis.x * u))
	var squeeze: float = (1.0 - minseg / RoadScript.STEP) * 100.0
	print("  LA TRAVERSEE NE SE REPLIE PAS : %s   (compression %.1f %% a 60 m de l'axe, seuil 12 — et il est atteignable : 54 %% si le clamp de road.gd lache, 12 %% des que TOWN_CURVE passe 0,0020 rad/m. Mesure sur %d segments extrudes. MECANISME, pas verdict : la courbure vaut %.5f rad/m au pire sur les %d echantillons du panneau a la fin du dessin, quand l'approche, elle, garde ses %.5f rad/m — la regle d'approche de _append_sample la redresse, elle ne la bride pas)" % [
		sq_n > 200 and squeeze < 12.0, squeeze, sq_n, kmax,
		t_end - g_arm + 1, kappr])

	# --- le ruban reste sans couture --------------------------------------
	# CE QUE CETTE LIGNE MESURAIT NE POUVAIT PAS ECHOUER, et elle le disait
	# presque : « pas maxi 2.000 m pour 2.0 ». Le pas VAUT STEP par
	# construction — _append_sample avance de STEP le long du nez, un point
	# c'est tout — donc partout ou la meme regle a fabrique les deux bouts d'un
	# segment, 2,000 m n'est pas un releve, c'est une definition. Et le virage
	# est plafonne par MAX_CURVE fois STEP, soit 1,03 deg/pas, contre un seuil
	# de 4,0 : quatre fois le plafond structurel.
	#
	# PIRE QUE CA : le releve imprimait STEP a la place de son propre seuil.
	# « 2.000 m pour 2.0 » — le 2.0 etait le pas nominal, le seuil valait 3,0.
	# La ligne avait l'air d'etre a la limite quand elle avait 50 % de marge.
	#
	# ET LE TEST N'AVAIT PAS DE PLANCHER. `pas < 3,0` laisse passer un pas de
	# 0,00 m les doigts dans le nez — soit exactement le defaut que
	# _grow_branch raconte avoir paye : la tete de reprise rangee SUR le
	# dernier point au lieu d'un pas au-dela, « un segment de longueur nulle,
	# une normale en 0/0 et un faux virage de 90 degres au releve ». On mesure
	# donc |pas - STEP|, qui attrape les deux cotes.
	#
	# ON MESURE OU CA PEUT CASSER : AUX RACCORDS. Il y en a exactement deux
	# dans la fenetre rangee, et ce sont les deux endroits ou la REGLE change
	# de main — a g_arm le ruban cesse de tirer sa courbure au sort et repose
	# les tetes pre-calculees de la ville (road.gd, `on_town_path`), a t_end il
	# reprend la main, _town_heads epuise. Un decalage d'un pas dans la
	# traversee, une tete de reprise mal rangee, un chemin d'une longueur qui
	# ne tombe pas juste : tout ca se voit LA, et nulle part ailleurs.
	#
	# La plaine reste mesuree et imprimee a cote, pour deux raisons : c'est la
	# REFERENCE qui donne son sens au chiffre du raccord (0,0002 m ici, 0,0002
	# la : la couture est du meme ordre que le bruit du float), et elle n'est
	# plus incassable non plus depuis que les seuils valent 0,01 m et le
	# plafond de courbure — un clamp casse dans _advance_curve la ferait rougir.
	var seam_seg := {g_arm: true, t_end: true}
	var seam_vtx := {g_arm: true, g_arm + 1: true, t_end: true, t_end + 1: true}
	var off := [0.0, 0.0]      # [plaine, raccord] : |pas - STEP|, en metres
	var bend := [0.0, 0.0]     # [plaine, raccord] : virage, en deg/pas
	var seg_n := 0
	var raccords := 0
	for g in range(rec_a, rec_b):
		if not (rec.has(g) and rec.has(g + 1)):
			continue
		seg_n += 1
		var w: int = 1 if seam_seg.has(g) else 0
		raccords += w
		off[w] = maxf(off[w], absf((rec[g] as Transform3D).origin.distance_to(
			(rec[g + 1] as Transform3D).origin) - RoadScript.STEP))
	for g in range(rec_a + 1, rec_b):
		if not (rec.has(g - 1) and rec.has(g) and rec.has(g + 1)):
			continue
		var w2: int = 1 if seam_vtx.has(g) else 0
		var a2: Vector3 = (rec[g - 1] as Transform3D).origin
		var b2: Vector3 = (rec[g] as Transform3D).origin
		var c2: Vector3 = (rec[g + 1] as Transform3D).origin
		bend[w2] = maxf(bend[w2], rad_to_deg(acos(clampf(
			(b2 - a2).normalized().dot((c2 - b2).normalized()), -1.0, 1.0))))
	# Le plafond vient de road.gd et il vaut pour les deux regions : la
	# nationale erre sous MAX_CURVE, la traversee sous TOWN_CURVE, et
	# TOWN_CURVE est le plus petit des deux — le maxf est la pour que ce banc
	# survive au chantier du volant si l'un passe devant l'autre.
	var bend_max: float = rad_to_deg(maxf(RoadScript.MAX_CURVE,
		RoadScript.TOWN_CURVE) * RoadScript.STEP)
	print("  LE RUBAN RESTE SANS COUTURE : %s   (AUX DEUX RACCORDS — l'entree a l'echantillon %d, ou la traversee pre-calculee prend la main ; la sortie au %d, ou le ruban la reprend : ecart au pas %.4f m pour un SEUIL DE 0,01 (un echantillon DOUBLE en ferait 2,000) et virage %.3f deg/pas pour un SEUIL DE %.3f, soit le plafond de road.gd — le plus grand de MAX_CURVE et TOWN_CURVE, fois STEP, %.3f deg/pas — et 15 %% pour le float. La plaine autour, %d segments, pour reference : %.4f m et %.3f deg/pas)" % [
		seg_n > 300 and raccords == 2
		and off[0] < 0.01 and off[1] < 0.01
		and bend[0] < bend_max * 1.15 and bend[1] < bend_max * 1.15,
		g_arm, t_end, off[1], bend[1], bend_max * 1.15, bend_max,
		seg_n - raccords, off[0], bend[0]])

	# --- le volant travaille en ville -------------------------------------
	# LE VERDICT EST CELUI DU PLAN, A LA LETTRE : |car.steer| passe au-dessus
	# de 0,04 au moins une fois toutes les 8 s de traversee. C'est ce que
	# sleep.gd compte (sleep.gd:163) et c'est ce que le plan promet (section 1.4 :
	# « courbure bornee, pas annulee — donc pas de declenchement de la
	# monotonie »).
	#
	# LES DEUX RELEVES DE ROUTE QUI SUIVENT SONT LA POUR DIRE POURQUOI, parce
	# qu'un verdict faux sans explication n'est qu'une plainte. Le cap ne tourne
	# que de 4 a 14 deg sur les 260 m selon le tirage, et sa portion la plus
	# plate va de 20 a 145 m : ce n'est pas une regle, mais ce n'est pas non
	# plus un volant qui travaille.
	#
	# L'ARITHMETIQUE QUI TRANCHE, et elle ne depend pas du conducteur de ce
	# banc : pour tenir une courbure k a la vitesse v, il faut
	# `steer = v * k / (steer_rate * grip * stability)` (car.gd:726-728). A
	# 12,5 m/s : grip = 1, stability = 0,806, steer_rate = 1,15, donc
	# steer = 13,5 * k. Au PLAFOND de la traversee (TOWN_CURVE = 0,0015) cela
	# fait 0,020 de volant — LA MOITIE du seuil de monotonie. Aucun reglage de
	# bande morte n'y change rien : c'est le regime permanent, pas le transitoire.
	# Seuls les changements de sens de la courbure font passer 0,04, et le
	# releve le montre (|steer| maxi de 0,021 a 0,071 sur douze lancements).
	#
	# ET LE LEVIER N'EST PAS CELUI QU'ON CROIT. TOWN_CURVE est un PLAFOND, et il
	# ne mord presque jamais : la courbure de la traversee est tiree en
	# `randfn(0,0 ; 0,0010)` (road.gd:532), donc le clamp a 0,0015 n'attrape
	# que 13 % des tirages. Verifie sur une copie : TOWN_CURVE monte a 0,005,
	# le tirage inchange — le cap tourne toujours de 12 deg sur la traversee et
	# le silence reste a 8,3 s. C'est l'ECART-TYPE qu'il faudrait monter, pas
	# le plafond : avec 0,005 d'ecart-type, le cap tourne de 40 deg, |steer|
	# monte a 0,112 et le silence tombe a 5,1 s — vert. Mais la compression a
	# 60 m passe alors a 41 %, quatre fois ce que LA TRAVERSEE NE SE REPLIE PAS
	# autorise : les deux invariants tirent en sens contraire, et c'est ca le
	# vrai resultat de cette ligne.
	#
	# Ce que ca veut dire, en clair : a 45 km/h la traversee ne desarme PAS la
	# monotonie de sleep.gd, et elle ne peut pas le faire sans replier le
	# quadrillage du bourg. La section 4.5 du plan, elle, l'admet deja pour la
	# vigilance : « La ville prend de la vigilance ; le cafe en rend. »
	var turn_tot := 0.0
	var flat_run := 0
	var flat_max := 0
	for g in range(g_arm, t_out + 1):
		if not (rec.has(g - 1) and rec.has(g) and rec.has(g + 1)):
			continue
		var d0: Vector3 = ((rec[g] as Transform3D).origin - (rec[g - 1] as Transform3D).origin).normalized()
		var d1: Vector3 = ((rec[g + 1] as Transform3D).origin - (rec[g] as Transform3D).origin).normalized()
		var k: float = acos(clampf(d0.dot(d1), -1.0, 1.0)) / RoadScript.STEP
		turn_tot += k * RoadScript.STEP
		if k < 0.00044:
			flat_run += 1
			flat_max = maxi(flat_max, flat_run)
		else:
			flat_run = 0
	var flat_m: float = float(flat_max) * RoadScript.STEP
	print("  LE VOLANT TRAVAILLE EN VILLE : %s   (au volant et non au rail : le plus long silence du volant vaut %.1f s pour un seuil de 8,0, sur %.1f s de traversee a 12,5 m/s, |steer| maxi %.3f pour un seuil de monotonie de 0,04 ; la route, elle, tourne son cap de %.1f deg sur les %.0f m de traversee et sa portion la plus plate fait %.0f m — au plafond TOWN_CURVE il ne faut que 0,020 de volant, la moitie du seuil)" % [
		cross_t >= 8.0 and steer_gap < 8.0, steer_gap, cross_t, steer_max,
		rad_to_deg(turn_tot), float(t_out - g_arm) * RoadScript.STEP, flat_m])

	# --- aucun arbre ni poteau dans la ville -------------------------------
	# ON COMPTE AUSSI CE QUI AURAIT DU NAITRE, et c'est la moitie de
	# l'invariant. Un "0" tout seul dit la meme chose quand le filtre travaille
	# et quand la nuit n'avait rien a poser : le tirage vaut p = 0,55 par
	# echantillon pour un arbre (road.gd:720) et un poteau tous les POLE_EVERY
	# (road.gd:738), et c'est ce compte-la qu'il faut avoir retire.
	#
	# LA REGION EST CELLE DU PLAN : de _town_in - PROP_QUIET a _town_out + PAD,
	# soit 191 echantillons et 105 arbres promis (PLAN_VILLES.md, J2). On imprime
	# en plus le decoupage, parce que c'est lui qui dit OU ca se passe : les
	# echantillons d'avant le panneau sont nes AVANT que _town_in n'existe —
	# les bornes se posent a l'armement (road.gd:463), et la ville dessine PAD
	# echantillons plus tot que ca. Le filtre n'a jamais eu la main sur eux.
	var reg_tree := 0
	var reg_pole := 0
	var draw_tree := 0
	var draw_pole := 0
	var pad_tree := 0
	var pad_pole := 0
	var after_tree := 0
	var after_pole := 0
	for g in tree_gs:
		if g >= quiet_a and g <= t_end:
			reg_tree += 1
		if g >= t_in and g <= t_end:
			draw_tree += 1
		if g >= t_in and g < g_arm:
			pad_tree += 1
		if g >= g_arm and g <= quiet_b:
			after_tree += 1
	for g in pole_gs:
		if g >= quiet_a and g <= t_end:
			reg_pole += 1
		if g >= t_in and g <= t_end:
			draw_pole += 1
		if g >= t_in and g < g_arm:
			pad_pole += 1
		if g >= g_arm and g <= quiet_b:
			after_pole += 1
	var reg_n: int = t_end - quiet_a + 1
	print("  AUCUN ARBRE NI POTEAU DANS LA VILLE : %s   (%d arbres et %d poteaux sur les %d echantillons ou road.gd promet le silence, quand le tirage en promettait %.0f et %.0f ; %d et %d dans les %d echantillons que la ville DESSINE, dont %d et %d dans les %d d'avant le panneau — nes avant que _town_in n'existe ; du panneau a la fin de la zone, %d echantillons : %d et %d)" % [
		reg_tree == 0 and reg_pole == 0, reg_tree, reg_pole, reg_n,
		0.55 * float(reg_n), float(reg_n) / float(RoadScript.POLE_EVERY),
		draw_tree, draw_pole, t_end - t_in + 1, pad_tree, pad_pole, g_arm - t_in,
		quiet_b - g_arm + 1, after_tree, after_pole])

	# --- le portail survit -------------------------------------------------
	print("  LE PORTAIL SURVIT : %s   (demande a l'echantillon %d, en plein milieu de la traversee ; obtenu %d, ecart %d pour un seuil de 5)" % [
		road.portal_index >= 0 and absi(road.portal_index - want_portal) < 5,
		want_portal, road.portal_index, absi(road.portal_index - want_portal)])

	# --- le juge ne lit plus les prives ------------------------------------
	# Le grep du plan, ecrit en GDScript. GDScript ne dit RIEN quand un membre
	# prive change de nom ou de sens : taxi.gd continuerait de tourner et le
	# client se mettrait a raler d'un bas-cote imaginaire, en silence, une nuit
	# entiere. Le texte du fichier est la seule preuve qui ne mente pas.
	var src: String = FileAccess.get_file_as_string("res://scripts/taxi.gd")
	var privates: int = src.count("road._")
	print("  LE JUGE NE LIT PLUS LES PRIVES : %s   (grep \"road\\._\" sur les %d octets de scripts/taxi.gd : %d resultat(s), seuil 0)" % [
		privates == 0, src.length(), privates])

	# --- la trace se recoud au Y -------------------------------------------
	# On force le passage sur la SORTIE (le brin mort), comme maptest : la
	# voiture est posee dessus, l'echange des rubans est ce qu'on eprouve, pas
	# le coup de volant.
	#
	# CE QUE LE BANC A TROUVE ICI, et qui n'etait pas prevu : la trace perd un
	# point sur deux echanges environ. _push_trail est cadence sur l'INDEX
	# GLOBAL (road.gd:294, `_index0 % TRAIL_EVERY == 0`), et _swap_to_branch
	# repose _index0 sur `_fork_g + 1 + start` (road.gd:1065) : les index qui
	# separent l'ancien du nouveau ne sont jamais pousses. Quand un multiple de
	# TRAIL_EVERY tombe dans ce trou — une fois sur deux, puisque le saut fait
	# quelques index —, la trace passe de 8 a 16 m entre deux points.
	#
	# Ce n'est pas une dechirure : les deux points restent SUR la route, la
	# fourche etant tenue droite. C'est un point perdu, exactement un, et le
	# releve le dit en cadences pour qu'on ne confonde pas les deux.
	print("--- le Y ---------------------------------------------------------")
	var trail0: int = (road.trail() as PackedVector2Array).size()
	var commits := [0]
	var swapped := [false]
	road.fork_committed.connect(func(s: String, _id: String) -> void:
		commits[0] += 1
		swapped[0] = s != String(road._fork_main))
	t = 0.0
	while t < 200.0 and commits[0] == 0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var near: bool = road.fork_state() in ["grow", "window"] \
			and road.head_index() >= road.fork_index() - 25
		if near:
			Engine.time_scale = 2.0
			car.speed = minf(maxf(car.speed, 8.0), 9.0)
			if road.head_index() >= road.fork_index() + 4 and road._bpos.size() > 1:
				_rail_on(road._bpos, 0.0)
			else:
				_rail(1.2)
		else:
			Engine.time_scale = 5.0
			car.speed = maxf(car.speed, 25.0)
			_rail(1.2)
	Engine.time_scale = 5.0
	t = 0.0
	while t < 90.0 and (road.trail() as PackedVector2Array).size() < trail0 + 24:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
	car.speed = 0.0
	var tr2: PackedVector2Array = road.trail()
	var jump := 0.0
	for i in range(maxi(trail0 - 4, 1), tr2.size()):
		jump = maxf(jump, tr2[i].distance_to(tr2[i - 1]))
	var jump_all := 0.0
	for i in range(1, tr2.size()):
		jump_all = maxf(jump_all, tr2[i].distance_to(tr2[i - 1]))
	var cadence: float = RoadScript.TRAIL_EVERY * RoadScript.STEP
	print("  LA TRACE SE RECOUD AU Y : %s   (sortie prise %s ; saut maxi %.2f m pour un seuil de 12, soit %.2f fois la cadence de %.0f m, sur les %d points poses autour de l'echange ; %.2f m sur les %d points de toute la nuit)" % [
		swapped[0] and jump < 12.0 and tr2.size() > trail0,
		swapped[0], jump, jump / cadence, cadence,
		tr2.size() - maxi(trail0 - 4, 1), jump_all, tr2.size()])

	Engine.time_scale = 1.0
	get_tree().quit()


## Gare la voiture dans la zone d'arret de la ville visee, tant que le taxi
## reste dans l'etat donne : pose sur le pave, nez dans le sens de la
## marche, a l'arret. Le stationnement appartient au joueur — le banc le
## mime au plus court, il ne le mesure pas ; c'est _zone_stop (taxi.gd) qui
## juge la geometrie, et c'est lui qu'on eprouve.
func _fare_park(expected: String, town_id: String, timeout: float) -> void:
	var t := 0.0
	while t < timeout and taxi.state == expected:
		await get_tree().process_frame
		t += get_process_delta_time()
		var tw: Node3D = road.town
		if tw != null and tw.visible and tw.town_name == town_id:
			var padw: Vector3 = tw.to_global(Vector3(4.6, 0.0, -27.0))
			car.speed = 0.0
			car.global_position.x = padw.x
			car.global_position.z = padw.z
			var fwd: Vector3 = -tw.global_transform.basis.z
			car.rotation.y = atan2(-fwd.x, -fwd.z)
		else:
			car.speed = minf(maxf(car.speed, 10.0), 12.0)
			_rail(1.2)


## Banc d'essai des courses : la boucle du metier, scriptee bout en bout.
## L'offre sonne et s'accepte D'UN TAP pousse dans l'ecran (le vrai chemin :
## push_input, les Button de Godot) ; la voiture roule au rail jusqu'au
## client, se gare dans la zone, la portiere s'anime, le poids s'assoit ;
## la course se roule avec un inconfort INJECTE (radio forte, vitre
## ouverte) pour que la note ait quelque chose a dire ; l'argent tombe au
## centime, l'avis en tete. Et s'endormir avec un client : une etoile.
func _fare_test() -> void:
	await get_tree().create_timer(0.8).timeout
	_start_normal_world()
	seed(7)
	taxi.enabled = true
	taxi.pay_override = "cb"
	# La jauge de veille ne bouge pas : ce banc scrute le metier, pas le
	# sommeil — sleeptest s'occupe de l'autre moitie.
	sleep.full_span = 1.0e9
	Engine.time_scale = 5.0
	var phone = car.interaction.grabbables.back()
	car.gear = 5

	# --- l'offre : elle sonne, elle s'affiche, elle s'accepte au doigt -----
	print("--- l'offre ------------------------------------------------------")
	taxi._cooldown = 0.5
	var t := 0.0
	while t < 40.0 and taxi.state != "offer":
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
	Engine.time_scale = 1.0        # le compte a rebours de l'offre est reel
	var offer: Dictionary = taxi.offer.duplicate()
	var explen: float = MapScript.path_length(MapScript.path(offer["from"], offer["to"]))
	var expprice: float = roundf((2.0 + 0.9 * explen / 1000.0) * 100.0) / 100.0
	print("  L'OFFRE SONNE : %s   (%s, %s -> %s, il reste %.0f s)" % [
		taxi.state == "offer" and offer["from"] == nav["to"]
		and phone._ring_snd.playing, offer["who"], offer["from"], offer["to"],
		offer["left"]])
	print("  LE PRIX EST AU BAREME : %s   (%.2f EUR pour %.0f m — 2 + 0,90/km)" % [
		absf(offer["price"] - expprice) < 0.005, offer["price"], explen])

	# L'ecran des courses, tel qu'il sonne : offre, prix, les deux boutons.
	phone._apps.set_page("courses")
	phone._view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = phone._view.get_texture().get_image()
	img.save_png("user://84_offre.png")
	print("SHOT: ", ProjectSettings.globalize_path("user://84_offre.png"))

	# ACCEPTER : un tap synthetique au milieu du bouton — le chemin du jeu.
	var b: Button = phone._apps._btn_yes
	var uv: Vector2 = (b.global_position + b.size * 0.5) / Vector2(216.0, 384.0)
	phone.tap(uv)
	await get_tree().process_frame
	await get_tree().process_frame
	print("  LE TAP ACCEPTE : %s   (etat %s, sonnerie coupee %s)" % [
		taxi.state in ["accepted", "pickup_zone"] and not phone._ring_snd.playing,
		taxi.state, not phone._ring_snd.playing])
	print("  L'ITINERAIRE DU CLIENT PREND : %s   (%s)" % [
		nav["route"] == MapScript.path(offer["from"], offer["to"]),
		" > ".join(nav["route"])])

	# --- l'embarquement : la zone, la portiere, le poids -------------------
	# En approche de la ville, on ralentit TOUT (vitesse et horloge) : sous
	# llvmpipe une image peut durer deux secondes, et a x5 et 25 m/s elle
	# avalerait la traversee entiere — le client resterait sur le trottoir.
	print("--- l'embarquement -----------------------------------------------")
	t = 0.0
	while t < 120.0 and taxi.state == "accepted":
		await get_tree().process_frame
		t += get_process_delta_time()
		var near_pick: bool = road.town != null and road.town.visible \
			and road.town.town_name == offer["from"]
		Engine.time_scale = 1.5 if near_pick else 5.0
		car.speed = 12.0 if near_pick \
			else maxf(car.speed, 25.0)
		_rail(1.2)
	Engine.time_scale = 1.5
	# Debraye pour tout l'arret : en 5e, s'immobiliser embrayage lache CALE —
	# et un moteur mort compterait "calage" a chaque echantillon de la course.
	await _act("clutch", true)
	await _fare_park("pickup_zone", offer["from"], 60.0)
	# La sequence se joue en vraie vitesse : la portiere doit se VOIR ouverte
	# — une grosse image l'avalerait, et le banc mesure la charniere.
	Engine.time_scale = 1.0
	car.last_impact = 0.0
	var peak := 0.0
	var shot_door := false
	t = 0.0
	while t < 30.0 and taxi.state == "boarding":
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = 0.0
		peak = maxf(peak, car.cabin.door_amount("R"))
		if not shot_door and car.cabin.door_amount("R") > deg_to_rad(45.0):
			shot_door = true
			await _shot("85_embarquement.png")
	print("  LA PORTIERE VIT : %s   (ouverte jusqu'a %.0f deg, refermee a %.1f deg)" % [
		peak > deg_to_rad(45.0) and car.cabin.door_amount("R") < deg_to_rad(2.0),
		rad_to_deg(peak), rad_to_deg(car.cabin.door_amount("R"))])
	print("  LE POIDS S'ASSOIT : %s   (impact %.2f m/s2 pour 3,2 — sous les 23,5 des objets)" % [
		absf(car.last_impact - 3.2) < 0.05, car.last_impact])
	print("  LE CLIENT EST LA : %s   (etat %s : \"%s\")" % [
		taxi.state == "riding", taxi.state, offer["who"]])

	# --- la course, inconfort injecte : radio forte, vitre ouverte ---------
	# La vitesse AVANT de rendre l'embrayage : le lacher a l'arret en 5e, une
	# image plus tard le moteur est mort — et un moteur mort compte "calage"
	# a chaque echantillon jusqu'a l'arrivee.
	print("--- la course ----------------------------------------------------")
	Engine.time_scale = 5.0
	car.speed = 22.0
	await _act("clutch", false)
	car.radio.volume = 5
	car.radio._apply()
	car.cabin.windows[0].open = 0.8
	t = 0.0
	while t < 300.0 and taxi.state == "riding":
		await get_tree().process_frame
		t += get_process_delta_time()
		var near_drop: bool = road.town != null and road.town.visible \
			and road.town.town_name == taxi.fare.get("to", "")
		Engine.time_scale = 1.5 if near_drop else 5.0
		car.speed = 12.0 if near_drop \
			else maxf(car.speed, 22.0)
		_rail(1.2)
	var flags: Dictionary = taxi.fare.get("flags", {})
	var complained: bool = taxi.state == "drop_zone" \
		and flags.has("radio") and flags.has("windows")
	print("  LE CLIENT PARLE : %s   (arrive %s ; plaintes %s)" % [
		complained, taxi.state == "drop_zone", flags.keys()])

	# --- la depose : la zone, le reglement, la note ------------------------
	print("--- le reglement -------------------------------------------------")
	Engine.time_scale = 1.5
	await _act("clutch", true)
	await _fare_park("drop_zone", offer["to"], 90.0)
	Engine.time_scale = 1.0
	car.last_impact = 0.0
	var money0: float = taxi.money
	t = 0.0
	while t < 30.0 and taxi.state in ["payment"]:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = 0.0
	var rev: Dictionary = taxi.reviews[0] if not taxi.reviews.is_empty() \
		else {"stars": 0.0, "text": "", "who": ""}
	var rate := 0.0
	if rev["stars"] >= 4.5:
		rate = 0.15
	elif rev["stars"] >= 3.5:
		rate = 0.08
	elif rev["stars"] >= 2.5:
		rate = 0.03
	var exptip: float = roundf(offer["price"] * rate * 100.0) / 100.0
	print("  L'ARGENT TOMBE AU CENTIME : %s   (%.2f EUR = %.2f + %.2f de pourboire, carte)" % [
		absf(taxi.money - money0 - offer["price"] - exptip) < 0.005,
		taxi.money, offer["price"], exptip])
	print("  LA NOTE DIT L'INCONFORT : %s   (%.1f etoiles, attendu entre 2,0 et 3,0)" % [
		rev["stars"] >= 2.0 and rev["stars"] <= 3.0, rev["stars"]])
	print("  L'AVIS EST EN TETE : %s   (\"%s\" — %s)" % [
		rev["who"] == offer["who"] and rev["text"].length() > 0,
		rev["text"], rev["who"]])
	print("  LE POIDS DESCEND : %s   (impact %.2f m/s2 pour 2,0 — la caisse remonte)" % [
		absf(car.last_impact - 2.0) < 0.05, car.last_impact])
	await _act("clutch", false)

	# --- s'endormir en course : l'avis que rien n'efface -------------------
	print("--- s'endormir ---------------------------------------------------")
	taxi.fare = {"from": offer["to"], "to": offer["from"], "price": 5.0,
		"who": "Le veilleur", "points": 0.0, "samples": 4, "flags": {},
		"over": false}
	taxi.state = "riding"
	taxi._on_fell_asleep()
	var r1: Dictionary = taxi.reviews[0]
	print("  DORMIR ANNULE ET NOTE 1 : %s   (%.1f etoile : \"%s\", etat %s)" % [
		r1["stars"] == 1.0 and taxi.state == "idle"
		and car.cabin.door_amount("R") < 0.01,
		r1["stars"], r1["text"], taxi.state])

	# --- l'ecran des avis, et les invariants -------------------------------
	phone._apps.set_page("avis")
	phone._view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	img = phone._view.get_texture().get_image()
	img.save_png("user://86_avis.png")
	print("SHOT: ", ProjectSettings.globalize_path("user://86_avis.png"))
	var inter = car.interaction
	print("  L'INVARIANT TIENT : %s   ([0] %s, dernier %s, portiere %.1f deg)" % [
		inter.grabbables[0].name == "CigPack"
		and inter.grabbables.back().name == "Phone"
		and car.cabin.door_amount("R") < 0.01,
		inter.grabbables[0].name, inter.grabbables.back().name,
		rad_to_deg(car.cabin.door_amount("R"))])

	Engine.time_scale = 1.0
	get_tree().quit()



# --------------------------------------------------------------------------
# Banc d'essai de la ville — J3
# --------------------------------------------------------------------------

## LE PREMIER BANC DU DEPOT QUI OUVRE UN MAILLAGE. Tous les autres mesurent des
## positions, des angles, des sommes d'argent ; celui-ci lit les tampons de
## sommets et compte ce qui y est ECRIT. C'est la seule facon de prouver le
## masque de dessin — et le J2 l'a promis pendant tout un jalon sans jamais
## regarder un triangle. Son invariant LA COUTURE EST NETTE (rubantest, verte a
## 0,0000 m dix fois sur dix) compare deux tableaux de Transform3D : c'est une
## identite de DONNEE, elle est vraie, et elle ne dit rien de ce qui est
## dessine. Le ruban et la traversante posaient bien le meme point ; personne
## n'avait verifie qu'ils ne le dessinaient pas TOUS LES DEUX.
##
## CE QU'IL EMPRUNTE AUX MEMBRES PRIVES, ET POURQUOI. Un banc a le droit
## d'ouvrir le capot (c'est taxi.gd qui ne l'a pas, et rubantest le verifie
## ligne a ligne). Ici : road._mesh et town._mesh (les tampons, l'objet meme de
## la mesure), road._pos / _right / _index0 / _town_in / _town_g (pour situer un
## sommet sur le ruban), town._plan / _c_pos / _mast_pos / _light_mast (pour
## placer la voiture et les captures), et town._step (pour savoir quelle etape
## de construction tourne dans quelle image).
##
## LE BANC CASSE CE QU'IL SURVEILLE, EXPRES, ET LE REMET. Trois lignes portent
## leur propre contre-epreuve, dans la meme image et sur la meme geometrie :
## le masque est refait une fois ferme (road._town_in a -1, _rebuild(), on
## compte, on remet) ; la couture est remesuree apres qu'on a decale de 5 cm le
## seul echantillon du ruban qui la porte ; l'enroulement est recompte sur une
## copie ou UN triangle a ete retourne ; la marge entre deux villes est
## recalculee sur une liste d'evenements ou l'armement qui suit la plus courte
## marge a ete ramene a 60 m. Une ligne verte qui ne sait pas rougir ne garantit
## rien — c'est la lecon que le J2 a payee trois fois sur neuf, et ce banc l'a
## repayee deux fois en s'ecrivant : sa mediane d'etape a imprime 0,00 ms sur un
## releve vide, et son test d'aire signee a accuse le clocher de Corbeny de
## vingt-huit triangles a l'envers qui regardaient simplement le sol.


## L'echantillon du ruban le plus proche d'un point, en index LOCAL.
##
## C'est ce qui SITUE un sommet dessine. Un sommet de bande est pose a
## `pos[i] + right[i] * off` avec |off| <= 5,8 m sur la nationale : son
## echantillon est le sien et pas un voisin, parce que le voisin est a
## sqrt(STEP^2 + off^2) > |off| et que la courbure plafonnee (MAX_CURVE,
## 0,009 rad/m) ne deplace le bord que de 5,8 x 0,018 = 10 cm sur un pas.
func _ville_sample_of(pos: PackedVector3Array, p: Vector3) -> int:
	var best := 1.0e18
	var bi := 0
	for i in pos.size():
		var q: Vector3 = pos[i]
		var d: float = (p.x - q.x) * (p.x - q.x) + (p.z - q.z) * (p.z - q.z)
		if d < best:
			best = d
			bi = i
	return bi


## Combien de triangles de `mesh` ont leurs DEUX EXTREMITES dans la fenetre
## d'echantillons [g0, g1] du ruban. C'est la mesure du masque, mot pour mot
## celle que le plan demande : la ou la ville dessine sa traversante, le ruban
## national ne doit plus poser un seul triangle.
##
## POURQUOI LES DEUX EXTREMITES ET PAS UNE. Un quad du ruban enjambe deux
## echantillons ; strip.gd saute les QUADS d'indices [skip_from, skip_to) et
## jamais les sommets. Le dernier quad emis est donc (_town_in - 1 -> _town_in),
## et ses sommets de tete tombent EXACTEMENT sur _town_in, le premier point de
## la traversante. Compter un triangle des qu'une extremite touche la fenetre
## rendrait donc rouge un ruban parfaitement masque.
func _ville_in_window(mesh: ArrayMesh, pos: PackedVector3Array, index0: int,
		g0: int, g1: int) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var f: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var gs := PackedInt32Array()
		gs.resize(v.size())
		for i in v.size():
			gs[i] = index0 + _ville_sample_of(pos, v[i])
		for t in f.size() / 3:
			var a: int = gs[f[t * 3]]
			var b: int = gs[f[t * 3 + 1]]
			var c: int = gs[f[t * 3 + 2]]
			if mini(a, mini(b, c)) >= g0 and maxi(a, maxi(b, c)) <= g1:
				n += 1
	return n


## L'aire signee d'un triangle projete en (x, z).
func _ville_area(a: Vector3, b: Vector3, c: Vector3) -> float:
	return 0.5 * ((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z))


## LE SIGNE DE REFERENCE, RELEVE SUR LA NATIONALE ET PAS SUPPOSE. Rend
## [signe de l'aire a plat, signe du produit normale geometrique . normale
## d'ombrage, triangles comptes, triangles en desaccord avec la majorite].
##
## Pourquoi le relever au lieu de l'ecrire : "enroulement horaire vu du dessus"
## est une phrase, et le depot a paye deux fois pour avoir cru la lire. La
## chaussee de road.gd, elle, SE VOIT a l'ecran depuis le premier jour — c'est
## la seule definition non circulaire de "a l'endroit" dont ce banc dispose. Et
## le rapport des deux normales est le vrai resultat de la mesure : la
## chaussee, visible du dessus, a sa normale GEOMETRIQUE (produit vectoriel,
## main droite) vers le BAS et sa normale d'OMBRAGE vers le haut. C'est ce
## produit negatif qui dit "a l'endroit", et il vaut pour un mur vertical
## exactement comme pour un trottoir.
func _ville_ref(mesh: ArrayMesh, surf: int) -> Array:
	var pos_area := 0
	var neg_area := 0
	var pos_dot := 0
	var neg_dot := 0
	var arr: Array = mesh.surface_get_arrays(surf)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var f: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for t in f.size() / 3:
		var ia: int = f[t * 3]
		var ib: int = f[t * 3 + 1]
		var ic: int = f[t * 3 + 2]
		var ar: float = _ville_area(v[ia], v[ib], v[ic])
		if ar > 0.0:
			pos_area += 1
		elif ar < 0.0:
			neg_area += 1
		var geo: Vector3 = (v[ib] - v[ia]).cross(v[ic] - v[ia])
		var sh: Vector3 = nn[ia] + nn[ib] + nn[ic]
		var dp: float = geo.dot(sh)
		if dp > 0.0:
			pos_dot += 1
		elif dp < 0.0:
			neg_dot += 1
	var sa := 1.0 if pos_area >= neg_area else -1.0
	var sd := 1.0 if pos_dot >= neg_dot else -1.0
	return [sa, sd, f.size() / 3,
		mini(pos_area, neg_area) + mini(pos_dot, neg_dot)]


## L'audit d'enroulement d'un maillage entier, triangle par triangle, contre le
## signe releve sur la nationale. Rend un releve nomme, parce qu'un compte tout
## seul ne dit pas OU c'est faux.
##
## DEUX MESURES, ET LA SECONDE EST CELLE QUI ATTRAPE UN MUR :
##  - l'AIRE SIGNEE en (x, z), la lettre du plan. Elle ne parle que des
##    triangles A PLAT — un mur vertical se projette sur un segment, son aire
##    vaut zero, et lui demander un signe serait demander n'importe quoi ;
##  - la NORMALE GEOMETRIQUE contre la normale d'OMBRAGE ecrite dans le tampon
##    par town.gd. Celle-la vaut pour les 4 610 triangles du bourg, murs,
##    toits, fenetres, mats et repere compris.
func _ville_winding(mesh: ArrayMesh, want_area: float, want_dot: float) -> Dictionary:
	var out := {"tri": 0, "flat": 0, "area_bad": 0, "dot_bad": 0, "degen": 0,
		"deux_faces": 0, "sous_face": 0, "worst": 1.0e18, "detail": ""}
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var f: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		# LES FACES A DEUX COTES SE RECONNAISSENT, ELLES NE SE DEVINENT PAS.
		# _quad2 (town.gd) emet EXPRES les deux enroulements du meme quad : une
		# tete de lampadaire se croise dans les deux sens, et une tete visible
		# d'un seul cote s'eteindrait dans le retroviseur. La moitie de ces
		# triangles contredit donc sa normale d'ombrage, et c'est voulu. On les
		# reconnait au fait que le MEME triple de sommets existe deux fois dans
		# la surface : c'est une propriete du tampon, pas une liste de cas
		# particuliers a tenir a jour. Releve avant cette regle : 96 faux sur la
		# surface 6 de Corbeny, soit 24 mats x 2 quads x 2 triangles, tous
		# legitimes.
		var pairs := {}
		for t in f.size() / 3:
			var key := "%d,%d,%d" % [
				mini(f[t * 3], mini(f[t * 3 + 1], f[t * 3 + 2])),
				f[t * 3] + f[t * 3 + 1] + f[t * 3 + 2],
				maxi(f[t * 3], maxi(f[t * 3 + 1], f[t * 3 + 2]))]
			pairs[key] = int(pairs.get(key, 0)) + 1
		# OU c'est faux compte autant que COMBIEN : les surfaces 5 et 6 versent
		# les maisons, puis les mats, puis le repere — dans cet ordre. Un
		# defaut cantonne aux DERNIERS triangles d'une surface designe le
		# repere ; etale sur toute la surface, il designe town.gd.
		var s_area := 0
		var s_dot := 0
		var s_first := -1
		var s_last := -1
		for t in f.size() / 3:
			var ia: int = f[t * 3]
			var ib: int = f[t * 3 + 1]
			var ic: int = f[t * 3 + 2]
			var a: Vector3 = v[ia]
			var b: Vector3 = v[ib]
			var c: Vector3 = v[ic]
			out["tri"] += 1
			var geo: Vector3 = (b - a).cross(c - a)
			if geo.length() < 1.0e-9:
				out["degen"] += 1
				continue
			var sh: Vector3 = nn[ia] + nn[ib] + nn[ic]
			if sh.length() > 1.0e-6:
				var key2 := "%d,%d,%d" % [
					mini(ia, mini(ib, ic)), ia + ib + ic, maxi(ia, maxi(ib, ic))]
				if int(pairs.get(key2, 0)) > 1:
					out["deux_faces"] += 1
					continue
				var dp: float = geo.normalized().dot(sh.normalized()) * want_dot
				out["worst"] = minf(out["worst"], dp)
				if dp <= 0.0:
					out["dot_bad"] += 1
					s_dot += 1
					s_first = t if s_first < 0 else s_first
					s_last = t
				# A PLAT : la normale d'ombrage est verticale. C'est la seule
				# famille dont l'aire signee veut dire quelque chose.
				#
				# ET LE SIGNE ATTENDU SUIT LA NORMALE, il n'est pas constant. La
				# reference relevee sur la chaussee vaut pour une face qui
				# regarde le CIEL ; le dessous d'une corniche de clocher, lui,
				# regarde le sol et son aire signee est de l'autre signe — par
				# construction, et pas par erreur. Le premier releve de ce banc
				# comptait 28 fautes sur le clocher de Corbeny pour cette seule
				# raison : c'etait le banc qui avait tort.
				var flat_up: float = signf(sh.normalized().y)
				if absf(sh.normalized().y) > 0.9:
					out["flat"] += 1
					if flat_up < 0.0:
						out["sous_face"] += 1
					var ar: float = _ville_area(a, b, c)
					if absf(ar) < 1.0e-7 or signf(ar) != want_area * flat_up:
						out["area_bad"] += 1
						s_area += 1
						s_first = t if s_first < 0 else s_first
						s_last = t
		if s_area + s_dot > 0:
			out["detail"] += "surface %d : %d aire / %d normale sur %d triangles, du %d au %d ; " % [
				s + 1, s_area, s_dot, f.size() / 3, s_first, s_last]
	return out


## La mediane d'un releve. Une moyenne suffirait si les images se ressemblaient ;
## elles ne se ressemblent pas — une image sur vingt porte un ramasse-miettes ou
## une allocation de tampon, et elle tire la moyenne de six mesures d'un tiers.
func _ville_median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


## Le rail sur la ligne mediane de la VILLE, dans un sens ou dans l'autre.
##
## Pourquoi pas _rail : au demi-tour la voiture repart en arriere, elle
## s'eloigne de road._pos[0] au lieu de s'en approcher, et _closest_index sur le
## ruban vivant la ramenerait a son premier echantillon — 200 m devant elle.
## La ville, elle, garde ses 171 echantillons a demeure (town._c_pos) : c'est la
## seule ligne du jeu qui reste sous la voiture quand on revient sur ses pas.
##
## `back` inverse le cap ET le cote : on roule a droite dans les deux sens.
func _ville_rail(line: PackedVector3Array, lane: float, back: bool) -> void:
	var i: int = road._closest_index(line, car.global_position)
	var fwd := Vector3(0.0, 0.0, -1.0)
	if i + 1 < line.size():
		fwd = (line[i + 1] - line[i]).normalized()
	elif i > 0:
		fwd = (line[i] - line[i - 1]).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var off: float = -lane if back else lane
	var p: Vector3 = line[i] \
		+ fwd * (car.global_position - line[i]).dot(fwd) + right * off
	car.global_position.x = p.x
	car.global_position.z = p.z
	car.rotation.y = atan2(fwd.x, fwd.z) if back else atan2(-fwd.x, -fwd.z)


## Gare la voiture a un point et a un cap, a l'arret. Les phares restent
## allumes (car.gd les leve au demarrage) et le moteur tourne : le point mort et
## la remise en marche se font UNE fois, avant la premiere capture.
func _ville_park(p: Vector3, yaw: float) -> void:
	car.speed = 0.0
	car.global_position.x = p.x
	car.global_position.z = p.z
	car.rotation.y = yaw


## Une capture prise d'une camera POSEE EXPRES, hors de la voiture.
##
## AUCUN COUP DE POUCE D'EXPOSITION, et c'est la difference avec _giant_shot et
## _strangler_shot : eux photographient une peau d'albedo 0,05 sous une lune
## sans ombres et n'ont pas le choix. Le bourg, lui, porte ses propres
## lumieres — fenetres emissives, tetes de lampadaire, phares de la voiture.
## Une ville qu'il faudrait eclairer a l'ambiante 18 pour la voir serait une
## ville que le joueur ne verra jamais : la capture doit mentir aussi peu que
## possible sur ce qu'on aura sous les yeux.
func _ville_cam_shot(fname: String, eye: Vector3, aim: Vector3, fov: float) -> void:
	var ext := Camera3D.new()
	ext.fov = fov
	ext.far = 600.0
	add_child(ext)
	ext.global_position = eye
	ext.look_at(aim, Vector3.UP)
	ext.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot(fname)
	car.cam.make_current()
	ext.queue_free()


## Une capture QU'ON MESURE : l'image part sur le disque, et ce qu'elle porte
## revient en trois chiffres. Une capture qu'on ne mesure pas ne prouve rien —
## c'est exactement ce qui manquait a la ville du cauchemar, ecrite, executee,
## et verifiee par personne. Rend [luminance moyenne, feux chauds, pixels lus].
##
## LES FEUX CHAUDS SONT LA VRAIE MESURE, ET LA LUMINANCE MOYENNE NE L'EST PAS.
## Releve : eteindre tout le bourg ne fait tomber la moyenne de l'image que de
## 5 %, parce que la flaque des PHARES sur la chaussee pese plus que la ville
## entiere et qu'elle, elle ne bouge pas. On compte donc les pixels CHAUDS et
## CLAIRS de la MOITIE HAUTE de l'image : les fenetres emissives et les tetes
## de lampadaire y sont, la flaque des phares n'y est pas, et le nom du panneau
## est gris neutre (0,72 / 0,74 / 0,70) donc hors du compte. C'est le seul
## chiffre de l'image qui ne parle que de la ville.
##
## UN PIXEL SUR SEIZE (un sur quatre dans chaque sens) : sur 1152 x 648 cela
## fait encore 46 000 echantillons, et le balayage entier coutait une
## demi-seconde de GDScript par capture.
func _ville_shot_stats(fname: String) -> Array:
	await RenderingServer.frame_post_draw
	var path := "user://%s" % fname
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT: ", ProjectSettings.globalize_path(path))
	var sum := 0.0
	var n := 0
	var warm := 0
	var half: int = img.get_height() / 2
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c: Color = img.get_pixel(x, y)
			sum += c.get_luminance()
			n += 1
			if y < half and c.get_luminance() > 0.10 and c.r > c.b * 1.4:
				warm += 1
	return [sum / float(maxi(n, 1)), warm, n]


## Les lumieres a ombres de TOUTE la scene, comptees en descendant l'arbre.
## Deux, et ce sont les phares : c'est le seul poste de rendu que le depot
## n'ait jamais eu le droit d'augmenter.
func _ville_shadow_lights(n: Node, out: Array) -> void:
	if n is Light3D and (n as Light3D).shadow_enabled:
		out.append(n.name)
	for c in n.get_children():
		_ville_shadow_lights(c, out)


## Ce qu'un noeud porte, sa descendance comprise : acc[0] les MeshInstance3D,
## acc[1] les noeuds, lui-meme exclu. Deux compteurs et un seul parcours —
## compter les enfants directs comptait quatre objets sur cinq comme nuls.
func _ville_count(n: Node, acc: Array) -> void:
	for c in n.get_children():
		acc[1] = int(acc[1]) + 1
		if c is MeshInstance3D:
			acc[0] = int(acc[0]) + 1
		_ville_count(c, acc)


## Toutes les OmniLight3D portees par un noeud et sa descendance.
func _ville_omnis(n: Node, out: Array) -> void:
	if n is OmniLight3D:
		out.append(n)
	for c in n.get_children():
		_ville_omnis(c, out)


## Le releve complet d'un bourg, une fois bati ET le masque en place. Rendu par
## ville armee : les seuils du jalon (8 000 sommets, 6 500 triangles, 6
## surfaces) ne valent que compares sur PLUSIEURS bourgs, parce que le compte
## depend du tirage — 60 maisons a Peyrelade, 70 a Malassis.
##
## LE MASQUE SE MESURE DEUX FOIS, ET LA SECONDE EST LA CONTRE-EPREUVE : on
## ferme le masque a la main (road._town_in a -1, _rebuild()), on recompte dans
## la MEME fenetre, on remet, on re-triangule. Meme image, meme ruban, meme
## bourg : ce que la seconde mesure trouve est exactement ce que la premiere
## doit avoir supprime. Une ligne verte qui ne sait pas rougir ne garantit rien.
func _ville_audit(town: Node3D, ref: Array) -> Dictionary:
	var TownPlan := preload("res://scripts/town_plan.gd")
	var mesh: ArrayMesh = town._mesh
	var out := {}
	out["nom"] = String(town.town_name)
	out["surf"] = mesh.get_surface_count()
	var vt := 0
	var tt := 0
	var per := ""
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var nt: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		vt += nv
		tt += nt
		per += "%d/%d " % [nv, nt]
	out["v"] = vt
	out["t"] = tt
	out["par_surface"] = per.strip_edges()
	# LES OBJETS DU BOURG, COMPTES EN DESCENDANT L'ARBRE. La premiere version ne
	# regardait que les enfants DIRECTS et imprimait "1 MeshInstance3D au plus"
	# — un chiffre faux, et faux du bon cote, ce qui est le pire : le maillage
	# aux six surfaces est bien seul, mais les deux panneaux portent chacun un
	# poteau et une tole, petits-enfants de la ville, et ils dessinent. Cinq
	# MeshInstance3D, donc, et l'en-tete de town.gd le disait deja sans que le
	# banc le confirme. On compte aussi TOUS les noeuds de la descendance : ce
	# sont les dix-sept objets que cet en-tete oppose aux 274 du hameau d'avant.
	var acc := [0, 0]
	_ville_count(town, acc)
	out["mi"] = acc[0]
	out["noeuds"] = acc[1]

	# --- le masque, sur les triangles du ruban -----------------------------
	var pos: PackedVector3Array = road._pos
	var i0: int = road._index0
	var g0: int = road._town_in
	var g1: int = road._town_out + TownPlan.PAD
	out["g0"] = g0
	out["g1"] = g1
	out["ready"] = bool(road._town_ready)
	out["dans"] = _ville_in_window(road._mesh, pos, i0, g0, g1)
	var keep: int = road._town_in
	road._town_in = -1
	road._rebuild()
	out["ferme"] = bool(road._town_ready)
	out["dans_sans"] = _ville_in_window(road._mesh, pos, i0, g0, g1)
	road._town_in = keep
	road._rebuild()
	out["remis"] = bool(road._town_ready)

	# --- la couture, SUR LE DESSIN ----------------------------------------
	# Le dernier sommet que road.gd emet avant le trou contre le premier point
	# que la ville dessine. Pas deux Transform3D d'un tableau : les trois
	# sommets d'asphalte de l'echantillon _town_in, tels qu'ils sont ECRITS
	# dans le tampon de chacun des deux maillages, apres extrusion, apres
	# decalage lateral, apres la hauteur de couche. Si les deux fichiers
	# n'etaient pas d'accord sur ROAD_HALF, sur Y_ROAD, sur le nombre de
	# colonnes ou sur le vecteur droite, c'est ici, et ici seulement, que ca se
	# verrait.
	var k: int = road._town_in - road._index0
	var seam := -1.0
	var seam_n := 0
	if k >= 0 and k < pos.size() and mesh.get_surface_count() > 0:
		var ra: Array = road._mesh.surface_get_arrays(1)   # l'asphalte du ruban
		var ta: Array = mesh.surface_get_arrays(0)         # l'asphalte du bourg
		var rv: PackedVector3Array = ra[Mesh.ARRAY_VERTEX]
		var tv: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
		seam = 0.0
		for c in 3:
			var ir: int = k * 3 + c
			if ir < rv.size() and c < tv.size():
				seam = maxf(seam, rv[ir].distance_to(tv[c]))
				seam_n += 1
	out["couture"] = seam
	out["couture_n"] = seam_n

	# --- l'enroulement -----------------------------------------------------
	var w: Dictionary = _ville_winding(mesh, float(ref[0]), float(ref[1]))
	out["tri"] = w["tri"]
	out["plat"] = w["flat"]
	out["aire_faux"] = w["area_bad"]
	out["normale_faux"] = w["dot_bad"]
	out["degenere"] = w["degen"]
	out["pire"] = w["worst"]
	out["deux_faces"] = w["deux_faces"]
	out["sous_face"] = w["sous_face"]
	out["detail"] = w["detail"]
	return out


## LE BANC DE LA VILLE POSEE — le J3.
##
## CE QU'IL FAIT, DANS L'ORDRE : il roule une nuit courte jusqu'au premier
## bourg de la carte (Corbeny, 950 m, l'arete de depart de _start_normal_world),
## RELEVE la nationale nue comme reference de rendu, FORCE l'armement dans le
## pire cas que road.gd sache produire — une image qui engendre ses 150
## echantillons de garde-fou —, chronometre les quatre etapes de construction,
## ouvre les deux maillages et compte leurs triangles, traverse le bourg, y
## fait DEMI-TOUR au volant sur un carrefour, prend les quatre captures, mesure
## le cout en A/B a l'arret, puis enchaine cinq bourgs de plus pour la marge
## entre deux villes.
##
## POURQUOI LE PIRE CAS SE FORCE ET NE S'ATTEND PAS. Dans une nuit ordinaire
## l'armement tombe dans une image qui pousse UN echantillon : road.gd rattrape
## 2 m de route et la ville se batit sur un ruban immobile. Le garde-fou
## `while guard < SAMPLES` de road.gd existe pour l'autre cas — une image
## longue, un rechargement, un saut — et c'est celui-la qui coute. On porte donc
## la voiture au bout du ruban vivant en une image, road.gd rattrape ses 150
## echantillons, et town.arm() tombe dedans. Un banc qui mesurerait le cas
## facile annoncerait un cout qu'aucun joueur ne paie.
func _ville_test() -> void:
	var TownPlan := preload("res://scripts/town_plan.gd")
	await get_tree().create_timer(0.8).timeout
	_start_normal_world()
	# La jauge de veille ne bouge pas : ce banc roule plusieurs kilometres en
	# temps accelere. Endormi, il basculerait dans le cauchemar — et
	# suspend_town() eteindrait la ville qu'il mesure.
	sleep.full_span = 1.0e9
	car.gear = 5
	# LES IMAGES SE MESURENT ICI, DONC LA SYNCHRO VERTICALE SAUTE. Avec elle,
	# toute image plus courte que la periode de l'ecran s'imprime a la periode
	# de l'ecran : ELLE SE BATIT SANS SAUTER UNE IMAGE et LE COUT NE SE VOIT
	# PAS mesureraient le moniteur et pas le bourg, et une etape de 3 ms serait
	# indiscernable d'une etape de 15.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var town: Node3D = road.town

	# --- la nationale nue : la reference de rendu -------------------------
	print("--- la nationale nue ---------------------------------------------")
	Engine.time_scale = 4.0
	var t := 0.0
	while t < 60.0 and road.head_index() < 60:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
	var bare_ms := 0.0
	var bare_calls := 0.0
	var bare_n := 0
	var t_prev := Time.get_ticks_usec()
	for k in 90:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if k > 8:
			bare_ms += float(now - t_prev) / 1000.0
			bare_calls += float(RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			bare_n += 1
		t_prev = now
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
	bare_ms /= float(bare_n)
	bare_calls /= float(bare_n)
	# Le signe d'enroulement de reference : celui de la chaussee de la
	# nationale, qui se voit a l'ecran depuis le premier jour.
	var ref: Array = _ville_ref(road._mesh, 1)
	print("  (nationale nue, %d images, vsync coupee : %.2f ms par image soit %.0f ips, %.1f appels de dessin par image sur les quatre vues)" % [
		bare_n, bare_ms, 1000.0 / bare_ms, bare_calls])
	print("  (enroulement de reference, releve sur les %d triangles d'asphalte du ruban : aire signee en (x,z) de signe %+.0f, produit normale geometrique . normale d'ombrage de signe %+.0f, %d triangle(s) en desaccord)" % [
		ref[2], ref[0], ref[1], ref[3]])

	# --- l'armement, dans le PIRE CAS -------------------------------------
	print("--- l'armement, dans le pire cas ---------------------------------")
	t = 0.0
	while t < 120.0 and road._town_g >= 0 \
			and road._town_g - (road._index0 + road._pos.size()) > 128:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 25.0)
		_rail(1.2)
	var avance: int = road._town_g - (road._index0 + road._pos.size())

	# LES DEUX IMAGES DE REFERENCE, prises a la meme vitesse et a la meme
	# horloge que la construction : celle d'AVANT le saut, ou le bourg n'existe
	# pas encore, et celle d'APRES, ou il est dessine. Elles ne portent aucun
	# verdict — le cout des etapes se mesure plus bas, sur six reconstructions
	# et journal coupe. Elles sont la pour que le lecteur voie de quoi est fait
	# le temps d'image quand la construction tombe dedans, et pour chiffrer ce
	# que le bourg coute a l'ecran une fois pose.
	Engine.time_scale = 1.0
	var pre_ms := 0.0
	var pre_n := 0
	t_prev = Time.get_ticks_usec()
	for k in 16:
		await get_tree().process_frame
		var now2 := Time.get_ticks_usec()
		if k > 5:
			pre_ms += float(now2 - t_prev) / 1000.0
			pre_n += 1
		t_prev = now2
		car.speed = maxf(car.speed, 12.5)
		_rail(1.2)
	pre_ms /= float(maxi(pre_n, 1))

	# LE SAUT. La voiture est portee au bout du ruban vivant plus 30 m : a
	# l'image suivante, road.gd doit rattraper (300 + 30 - 24) / 2 = 153
	# echantillons et son garde-fou l'arrete a 150. C'est exactement le pire cas
	# que le plan demande de mesurer, et il ne s'attend pas : dans une nuit
	# ordinaire l'armement tombe dans une image qui pousse UN echantillon.
	await get_tree().process_frame
	var lastr: Vector3 = road._right[road._right.size() - 1]
	var fwd_end: Vector3 = Vector3.UP.cross(lastr).normalized()
	car.global_position = road._pos[road._pos.size() - 1] + fwd_end * 30.0
	car.rotation.y = atan2(-fwd_end.x, -fwd_end.z)
	car.speed = 12.5

	# Les images qui suivent, une par une : combien d'echantillons road.gd y a
	# pousses, et quelle etape de la ville y a tourne. town._step est lu AVANT
	# le _process de l'image (process_frame est emis juste avant), donc il dit
	# ce qui VA tourner et non ce qui a tourne. Ce releve-ci sert au PIRE CAS —
	# l'image de l'armement — et au decor ; le cout des quatre etapes, lui, se
	# mesure juste apres, six fois et journal coupe.
	var f_ms := PackedFloat32Array()
	var f_step := PackedInt32Array()
	var f_pushed := PackedInt32Array()
	t_prev = Time.get_ticks_usec()
	for k in 22:
		var step_before: int = town._step
		var idx_before: int = road._index0
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		f_ms.append(float(now - t_prev) / 1000.0)
		f_step.append(step_before)
		f_pushed.append(road._index0 - idx_before)
		t_prev = now
		car.speed = maxf(car.speed, 12.5)
		if k >= 2:
			_rail(1.2)
	var burst := 0
	var burst_ms := 0.0
	var step_ms := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var post_ms := 0.0
	var post_n := 0
	for k in f_ms.size():
		if f_pushed[k] > 60:
			burst = maxi(burst, f_pushed[k])
			burst_ms = maxf(burst_ms, f_ms[k])
		elif f_step[k] >= 0 and f_step[k] <= 3:
			step_ms[f_step[k]] = maxf(step_ms[f_step[k]], f_ms[k])
		else:
			post_ms += f_ms[k]
			post_n += 1
	post_ms = post_ms / maxf(float(post_n), 1.0)
	print("  (l'image de l'armement a pousse %d echantillons — le garde-fou de road.gd en autorise %d — et la ville etait demandee %d echantillons au-dela du ruban vivant ; elle a dure %.2f ms : rattrapage du ruban, re-triangulation entiere et _gather des 171 echantillons de la ville. Les images voisines faisaient %.2f ms avant le saut et %.2f apres, et la construction qui a suivi %.2f / %.2f / %.2f / %.2f ms — journal de town.gd compris, voir les deux lignes suivantes)" % [
		burst, RoadScript.SAMPLES, avance, burst_ms, pre_ms, post_ms,
		step_ms[0], step_ms[1], step_ms[2], step_ms[3]])
	var loud_ms := PackedFloat32Array([step_ms[0], step_ms[1], step_ms[2], step_ms[3]])

	# --- les quatre etapes, CHRONOMETREES UNE PAR UNE ---------------------
	# ON APPELLE LES QUATRE ETAPES, ON NE REGARDE PLUS LES IMAGES. La premiere
	# version de cette ligne mesurait le TEMPS D'IMAGE dans lequel chaque etape
	# tombe, et elle n'a jamais rien mesure de stable : sur cinq lancements du
	# meme banc, la meme etape a rendu +0,62, +4,40, +9,94, +4,58 et -2,27 ms,
	# et l'image de reference elle-meme est passee de 3,6 a 14,8 ms selon la
	# charge de la machine. Une etape qui coute deux millisecondes ne se lit pas
	# dans une image qui en dure quinze et qui varie de cinq.
	#
	# Les quatre builders de town.gd sont des methodes ordinaires : on rearme le
	# bourg, on EFFACE sa machine a etats (_step a -1, sinon _process les
	# rappellerait dans les images suivantes et le maillage recevrait douze
	# surfaces), et on les appelle nous-memes, chronometre au microseconde. Ce
	# qu'on mesure alors est l'etape et rien qu'elle — c'est exactement ce que
	# le seuil de 4,0 ms du plan designe.
	#
	# CE QUE CETTE MESURE NE CONTIENT PAS, ET IL FAUT LE DIRE : le premier RENDU
	# du maillage, qui tombe dans l'image ou _build_glow leve _mi.visible. Il est
	# du cote de la carte graphique, il est mesure a part par LE COUT NE SE VOIT
	# PAS, et il ne depend pas du decoupage en quatre images.
	#
	# LE JOURNAL DE town.gd EST COUPE le temps de la mesure (`_loud` a faux) :
	# _build_glow finit par _print_cost() des qu'un banc tourne, et sur une
	# sortie redirigee dans un tube ces deux lignes ont coute 25,7 ms un
	# lancement et 42,4 ms le suivant — plus que toute la geometrie du bourg. Un
	# joueur ne le paiera jamais.
	town._loud = false
	car.speed = 0.0
	var st_all := [[], [], [], []]
	for r in 12:
		town.arm(town.global_transform, String(town.town_name))
		town._step = -1
		for e in 4:
			var t0 := Time.get_ticks_usec()
			match e:
				0: town._build_roads()
				1: town._build_walks()
				2: town._build_town()
				3: town._build_glow()
			(st_all[e] as Array).append(float(Time.get_ticks_usec() - t0) / 1000.0)
		await get_tree().process_frame
	town._loud = true
	var net := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var worst_step := 0.0
	var worst_i := 0
	var spread := 0.0
	for k in 4:
		net[k] = _ville_median(st_all[k])
		var hi := 0.0
		for x in (st_all[k] as Array):
			hi = maxf(hi, float(x))
		spread = maxf(spread, hi)
		if net[k] > worst_step:
			worst_step = net[k]
			worst_i = k
	# LE PLAN DEMANDE AUSSI "aucune image de l'armement au-dessus de 14,0 ms",
	# ET CE SEUIL-LA NE MESURERAIT PAS LE BOURG SUR CETTE MACHINE : l'image de
	# la NATIONALE NUE est imprimee plus haut et vaut de 14 a 21 ms selon la
	# charge, ville ou pas. On garde donc les deux choses que le bourg controle
	# vraiment : le cout de chaque etape, et le fait que l'armement tienne dans
	# une image qui pousse les 150 echantillons du garde-fou.
	print("  ELLE SE BATIT SANS SAUTER UNE IMAGE : %s   (douze reconstructions du meme bourg, journal coupe, chaque etape appelee et chronometree a part — mediane : chaussees %.2f, trottoirs %.2f, bati %.2f, emissif %.2f ms, la pire est l'etape %d a %.2f ms pour un seuil de 4,0, et la plus longue des quarante-huit mesures fait %.2f ms. L'armement, lui, est mesure dans le PIRE CAS : %d echantillons pousses dans son image, la ou le garde-fou de road.gd en autorise %d)" % [
		worst_step < 4.0 and burst >= RoadScript.SAMPLES,
		net[0], net[1], net[2], net[3], worst_i + 1, worst_step, spread,
		burst, RoadScript.SAMPLES])

	# --- les quatre IMAGES de construction, JOURNAL DEJA COUPE -------------
	# LA MESURE QUI MANQUAIT, ET LA SEULE QUI REPONDE FRANCHEMENT A « EST-CE
	# QU'UNE IMAGE SAUTE ». Le banc en avait deux, et aucune ne repondait :
	#  - la ligne du dessus chronometre les quatre etapes A LA MICROSECONDE,
	#    mais HORS IMAGE — on appelle les builders a la main ;
	#  - la ligne d'avant chronometre les quatre IMAGES, mais journal de
	#    town.gd DEDANS : _print_cost et _print_landmark appellent
	#    surface_get_arrays six fois et ont coute 25,7 puis 42,4 ms sur une
	#    sortie redirigee dans un tube. Le banc EXPLIQUAIT que ses images
	#    longues etaient son propre journal ; personne ne le VERIFIAIT dans le
	#    meme lancement, et rien n'imprimait ces quatre images journal coupe.
	# On le fait ici : six rearmements de plus, _loud a faux, _process batit en
	# quatre images comme chez le joueur, la voiture roule a 12,5 m/s, et on
	# chronometre LES IMAGES. On mesure en plus les quatre images VOISINES sans
	# construction, au meme endroit et a la meme vitesse : sans elles, un
	# chiffre de 12 ms ne dirait pas si la ville coute onze millisecondes ou si
	# la machine en est simplement la ce soir.
	#
	# L'ALIGNEMENT SE VERIFIE AU LIEU DE SE SUPPOSER. arm() pose _step a 0 et
	# _arm_frame a l'image courante, que town.gd saute deliberement : les etapes
	# tombent sur les quatre images SUIVANTES. On relit _step au debut de chaque
	# image — process_frame est emis avant les _process, donc il dit ce qui VA
	# tourner — et une image qui ne porte pas l'etape attendue est comptee a
	# part plutot que versee dans la mauvaise colonne.
	town._loud = false
	var frm := [[], [], [], []]
	var rest_l: Array = []
	var mis_align := 0
	for r in 6:
		await get_tree().process_frame
		town.arm(town.global_transform, String(town.town_name))
		await get_tree().process_frame
		var tp := Time.get_ticks_usec()
		for e in 4:
			var st_b: int = town._step
			await get_tree().process_frame
			var nw := Time.get_ticks_usec()
			if st_b == e:
				(frm[e] as Array).append(float(nw - tp) / 1000.0)
			else:
				mis_align += 1
			tp = nw
			car.speed = maxf(car.speed, 12.5)
			_rail(1.2)
		for e2 in 4:
			await get_tree().process_frame
			var nw2 := Time.get_ticks_usec()
			rest_l.append(float(nw2 - tp) / 1000.0)
			tp = nw2
			car.speed = maxf(car.speed, 12.5)
			_rail(1.2)
	town._loud = true
	var frm_med := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var frm_hi := 0.0
	var frm_n := 0
	for e in 4:
		frm_med[e] = _ville_median(frm[e])
		frm_n += (frm[e] as Array).size()
		for x in (frm[e] as Array):
			frm_hi = maxf(frm_hi, float(x))
	var rest_med: float = _ville_median(rest_l)
	var frm_worst := 0.0
	for e in 4:
		frm_worst = maxf(frm_worst, frm_med[e])
	print("  (les quatre IMAGES de construction, JOURNAL DEJA COUPE et voiture a 12,5 m/s, six rearmements : mediane %.2f / %.2f / %.2f / %.2f ms sur %d images alignees et %d hors alignement ; la plus longue des %d fait %.2f ms. Les quatre images VOISINES sans construction, meme endroit et meme vitesse, tiennent %.2f ms : la pire etape depasse son voisinage de %+.2f ms. Les MEMES quatre images journal compris, relevees plus haut, faisaient %.2f / %.2f / %.2f / %.2f ms — l'ecart est le journal, et c'est la premiere fois qu'il est mesure dans le meme lancement)" % [
		frm_med[0], frm_med[1], frm_med[2], frm_med[3], frm_n, mis_align,
		frm_n, frm_hi, rest_med, frm_worst - rest_med,
		loud_ms[0], loud_ms[1], loud_ms[2], loud_ms[3]])

	# --- le maillage, le masque, la couture, l'enroulement -----------------
	t = 0.0
	while t < 20.0 and not (town._built and road._town_ready):
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 12.5)
		_rail(1.2)
	var audits: Array = []
	audits.append(_ville_audit(town, ref))
	var a0: Dictionary = audits[0]
	print("--- le bourg -----------------------------------------------------")
	print("  (\"%s\" : %d surface(s), %d sommets, %d triangles, par surface %s ; la ville dessine les echantillons %d a %d, la voiture est au %d)" % [
		a0["nom"], a0["surf"], a0["v"], a0["t"], a0["par_surface"],
		a0["g0"], a0["g1"], road.head_index()])

	# LES TROIS LAMPES SE RELEVENT ICI, quelques images apres le _place_lights
	# de la derniere reconstruction et VOITURE A L'ARRET depuis : c'est le seul
	# instant ou la distance mesuree est encore celle de l'ALLUMAGE. Dix
	# secondes plus tard la voiture a avance de 130 m et la mesure ne dirait
	# plus rien de la regle qu'on juge.
	var omnis: Array = []
	_ville_omnis(town, omnis)
	var fog_max := 0.0
	var lamp_min := 1.0e18
	var lamp_moves := 0
	# COMBIEN DES TROIS BRULENT, et pas seulement a quelle distance elles se
	# rallument. La ville promet au conducteur d'en croiser trois d'un bout a
	# l'autre du bourg ; un releve qui ne compte que les rallumages dirait la
	# meme chose d'un bourg ou une seule lampe aurait trouve un mat.
	var lamp_lit_min := 3
	var lamp_lit_max := 0
	var lamp_pos: Array = []
	for l in omnis:
		var ol: OmniLight3D = l
		fog_max = maxf(fog_max, ol.light_volumetric_fog_energy)
		lamp_pos.append(ol.global_position)
		if ol.visible:
			lamp_moves += 1
			lamp_min = minf(lamp_min,
				ol.global_position.distance_to(car.global_position))

	# --- 87 : l'arrivee sur le bourg --------------------------------------
	# LE PLAFONNIER S'ETEINT D'ABORD, ET PAR LE GESTE. Il est allume au
	# demarrage (dome_light.gd, `on := true`) : a 15 cm de la casquette et du
	# ciel de toit, il fait de l'habitacle la chose la plus claire de l'image et
	# le tonemap filmique ecrase tout le reste — premiere serie de captures, on
	# ne distinguait ni le panneau, ni les fenetres, ni la tete des lampadaires.
	# Un conducteur de nuit l'eteint ; on l'eteint comme lui, en le visant et en
	# cliquant (_dome_switch), pas en ecrivant `on = false`.
	Engine.time_scale = 1.0
	t = 0.0
	while t < 60.0 and road.head_index() < road.town_span().x + TownPlan.PAD - 7:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 12.5)
		_rail(1.2)
	car.speed = 0.0
	await _dome_switch(car.cabin.dome_light, false)
	# LE MOTEUR RESTE EN MARCHE. S'arreter en cinquieme le CALE, et la premiere
	# serie de captures portait "MOTEUR ARRETE" en rouge sur toute la largeur du
	# tableau de bord. On repasse au point mort et on relance a la cle.
	await _restart_engine()
	# LE REGARD REND LA MAIN A LA ROUTE, ET LE BANDEAU D'AIDE S'EFFACE. Des
	# qu'on regarde droit devant, la visee accroche le pare-soleil range : son
	# bandeau ("Maintiens clic gauche : placer le pare-soleil") s'imprimait EN
	# PLEIN MILIEU des quatre premieres captures et la tole du pare-soleil s'y
	# allumait en surbrillance. On regarde donc la chaussee a six metres, ou il
	# n'y a rien a saisir, et on eteint le bandeau pour la duree des prises : il
	# appartient au jeu, pas a la photographie.
	await _aim_at(Vector3(car.SEAT_X, -0.2, -6.0))
	car.interaction._hint.visible = false

	# La voiture posee a 14 m du panneau, la camera derriere et au-dessus
	# d'elle : le pare-brise ne convient pas pour celle-la, le retroviseur
	# interieur couvre justement la bande de 12 a 32 degres a droite ou le
	# panneau tombe (releve sur la premiere serie), et le panneau est ce qu'on
	# vient voir. De la, on a les deux cones de phares, la tole du panneau
	# qu'ils accrochent, et les premieres fenetres du bourg derriere.
	var i_sign: int = TownPlan.PAD
	var ie: int = maxi(i_sign - 7, 1)
	var fe: Vector3 = (town._c_pos[ie + 1] - town._c_pos[ie]).normalized()
	var re: Vector3 = fe.cross(Vector3.UP).normalized()
	_ville_park(town._c_pos[ie] + re * 1.2, atan2(-fe.x, -fe.z))
	await get_tree().process_frame
	await _ville_cam_shot("87_ville_entree.png",
		car.global_position - fe * 6.5 + re * 1.3 + Vector3(0.0, 2.05, 0.0),
		car.global_position + fe * 34.0 + Vector3(0.0, 2.6, 0.0), 58.0)

	# --- la traversee : ce que le bourg fait pendant qu'on le traverse ----
	# La ville reste allumee (LA VILLE NE S'ETEINT PAS DEDANS), les trois
	# lampes ne s'allument jamais sous le nez (TROIS LUMIERES), et la voiture
	# ne racle jamais (LE DEMI-TOUR TIENT, premiere moitie).
	var vis_n := 0
	var vis_off := 0
	var off_max := 0.0
	# LE MAT LE PLUS PROCHE QU'ON CROISE, allume ou non : c'est le temoin de
	# TROIS LUMIERES. Il dit ou une lampe se serait allumee si la regle avait
	# ete "le mat le plus proche" au lieu de "le plus proche AU-DELA de 60 m".
	var mast_near := 1.0e18
	# Le carrefour du demi-tour : la transversale la plus proche de 200 m
	# apres le panneau — la moitie de la traversee, et le seul endroit du jeu
	# ou deux chaussees se croisent.
	var s_cross := -1.0e9
	for st in (town._plan.streets as Array):
		if String(st["kind"]) != "cross":
			continue
		if absf(float(st["s"]) - 200.0) < absf(s_cross - 200.0):
			s_cross = float(st["s"])
	Engine.time_scale = 2.0
	t = 0.0
	var cross_ms := 0.0
	var cross_n := 0
	var t_cross := Time.get_ticks_usec()
	var prev_car: Vector3 = car.global_position
	var stop_at: Vector3 = town._world(s_cross - 2.5, 0.0)
	while t < 90.0 and car.global_position.distance_to(stop_at) > 2.5:
		prev_car = car.global_position
		await get_tree().process_frame
		var n_cross := Time.get_ticks_usec()
		cross_ms += float(n_cross - t_cross) / 1000.0
		t_cross = n_cross
		cross_n += 1
		t += get_process_delta_time()
		car.speed = 12.5
		_ville_rail(town._c_pos, 1.2, false)
		vis_n += 1
		if not town.visible:
			vis_off += 1
		off_max = maxf(off_max, road.off_road_dist(car.global_position))
		for mp in (town._mast_pos as PackedVector3Array):
			mast_near = minf(mast_near, mp.distance_to(car.global_position))
		# LA DISTANCE D'ALLUMAGE SE PREND A L'IMAGE D'AVANT, ET C'EST OBLIGE.
		# town._relight tourne dans le _process de la ville, donc APRES celui de
		# ce banc (l'arbre descend des parents vers les enfants, et la ville est
		# petite-fille de main). On voit donc la lampe bouger a l'image
		# SUIVANTE, quand la voiture s'est deja rapprochee de 40 cm a 25 m/s :
		# mesurer la depuis la position courante rognerait le releve de 40 cm
		# sous un plancher de 60,0 m, et un vert deviendrait rouge sans que la
		# ville ait rien fait. On garde la position de l'image d'avant.
		var lit := 0
		for li in omnis.size():
			var l2: OmniLight3D = omnis[li]
			if l2.visible:
				lit += 1
			if l2.visible and l2.global_position != lamp_pos[li]:
				lamp_pos[li] = l2.global_position
				lamp_moves += 1
				lamp_min = minf(lamp_min,
					l2.global_position.distance_to(prev_car))
		lamp_lit_min = mini(lamp_lit_min, lit)
		lamp_lit_max = maxi(lamp_lit_max, lit)

	# --- le demi-tour, AU VOLANT ------------------------------------------
	# LA VILLE EST LE SEUL ENDROIT DU JEU OU L'ON PEUT FAIRE DEMI-TOUR, et le
	# plan en fait un fait mesure et non une image. On le fait donc pour de
	# vrai : plein braquage a 4 m/s, les memes actions que le joueur, sur le
	# carrefour et pas entre deux. Le carrefour n'est pas une coquetterie —
	# c'est de l'arithmetique. A 4 m/s, grip = 0,8 et stability = 0,938
	# (car.gd), le lacet vaut 1,15 x 0,8 x 0,938 = 0,86 rad/s et le rayon
	# 4,6 m : un demi-tour emmene la voiture a 1,2 - 2 x 4,6 = 8,0 m de l'axe
	# du tronc, hors des 5,8 m de chaussee plus accotement. Ce qui la rattrape,
	# c'est l'AUTRE rue : au point le plus ecarte, elle est sur l'axe de la
	# transversale. off_road_dist prend le plus petit des deux, et c'est
	# exactement le service que street_dist rend au juge de course.
	var off_cross: float = off_max
	var turn_a: float = road.off_road_dist(car.global_position)
	var turn_max: float = turn_a
	var turn_in := 0
	var turn_n := 0
	var yaw_prev: float = car.rotation.y
	var turned := 0.0
	Engine.time_scale = 1.0
	Input.action_press("steer_left", 1.0)
	t = 0.0
	while t < 30.0 and absf(turned) < PI:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = 4.0
		turned += wrapf(car.rotation.y - yaw_prev, -PI, PI)
		yaw_prev = car.rotation.y
		turn_max = maxf(turn_max, road.off_road_dist(car.global_position))
		turn_n += 1
		if town.contains(car.global_position):
			turn_in += 1
		vis_n += 1
		if not town.visible:
			vis_off += 1
	Input.action_release("steer_left")
	var turn_arc: float = turn_max
	var yaw_done: float = rad_to_deg(absf(turned))
	# CE N'EST PAS UNE MESURE, C'EST LA CONDITION D'ARRET DE LA BOUCLE ci-dessus,
	# et il fallait le nommer : la boucle ne sort qu'a PI de cap tourne ou a 30 s
	# de delai. Un faux ici ne dit rien du demi-tour — il dit que le banc a
	# manque de temps, et que l'ecart maxi releve porte sur une manoeuvre
	# tronquee. C'est un garde-fou de banc, pas un invariant du monde.
	var turn_done: bool = absf(turned) >= PI

	# Le retour au panneau, sur la ligne de la ville et a contresens du ruban.
	Engine.time_scale = 2.0
	t = 0.0
	var prev_ret: Vector3 = car.global_position
	while t < 120.0 and car.global_position.distance_to(town.global_position) > 12.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = 9.0
		_ville_rail(town._c_pos, 1.2, true)
		turn_max = maxf(turn_max, road.off_road_dist(car.global_position))
		turn_n += 1
		if town.contains(car.global_position):
			turn_in += 1
		vis_n += 1
		if not town.visible:
			vis_off += 1
		# LES LAMPES SE SUIVENT AUSSI AU RETOUR, et c'est la moitie du releve :
		# la traversee aller ne les fait bouger qu'une ou deux fois (elles sont
		# posees a l'armement sur des mats deja loin devant), le retour a
		# contresens les fait toutes lacher leur mat l'une apres l'autre.
		var lit2 := 0
		for li in omnis.size():
			var l3b: OmniLight3D = omnis[li]
			if l3b.visible:
				lit2 += 1
			if l3b.visible and l3b.global_position != lamp_pos[li]:
				lamp_pos[li] = l3b.global_position
				lamp_moves += 1
				lamp_min = minf(lamp_min,
					l3b.global_position.distance_to(prev_ret))
		lamp_lit_min = mini(lamp_lit_min, lit2)
		lamp_lit_max = maxi(lamp_lit_max, lit2)
		prev_ret = car.global_position
	var back_m: float = car.global_position.distance_to(town.global_position)
	# Meme remarque que pour turn_done : la boucle du retour s'arrete a 12 m du
	# panneau ou a 120 s. `back_m < 13` ne pouvait donc rougir que sur un delai
	# depasse, et la ligne le presentait comme un troisieme releve.
	var back_done: bool = back_m <= 12.0
	off_max = maxf(off_max, turn_max)

	# --- 88, 89, 90 : les trois captures du bourg -------------------------
	# LA CAMERA SE PLACE, ELLE NE SE SUBIT PAS. Les captures des autres bancs
	# sortent de la ou la voiture se trouvait quand le banc a fini sa mesure :
	# elles PROUVENT, elles ne MONTRENT pas. Ici on choisit le point de vue sur
	# la geometrie du bourg — le mat allume que les trois lampes tiennent en ce
	# moment, la bouche d'une rue laterale, l'axe de la rue que le repere
	# ferme — et la voiture s'y gare, phares allumes.
	Engine.time_scale = 1.0
	car.speed = 0.0

	# 88 : le carrefour, sous un lampadaire allume. La camera se pose a hauteur
	# d'homme SUR LE BORD OPPOSE au mat et le vise : depuis le siege, la tete du
	# lampadaire monte a 16 degres a 12 m et le pavillon coupe le ciel a 11
	# (releve du banc de la lune) — elle serait sous la tole. La voiture reste
	# 7,5 m derriere la camera, phares allumes : ce sont eux qui donnent la
	# chaussee, le trottoir et la bouche de la transversale.
	#
	# LE MAT SE CHOISIT SUR SA DISTANCE AU TRONC, et pas sur le nom de sa rue.
	# Premiere tentative : "celui qui tient une transversale, donc un
	# carrefour" — sauf qu'une transversale s'etend de 34 a 62 m de part et
	# d'autre, et le mat retenu s'est retrouve a quarante metres de la
	# nationale : la capture montrait deux points orange a l'horizon. On garde
	# donc le mat allume le plus proche de la ligne du tronc, celui qu'on croise
	# en passant, et la camera se pose a huit metres devant lui.
	var lamp_w := Vector3.ZERO
	var lamp_d := 1.0e18
	for li in omnis.size():
		var ol2: OmniLight3D = omnis[li]
		if not ol2.visible or town._light_mast[li] < 0:
			continue
		var lp: Vector3 = ol2.global_position
		var d2: float = lp.distance_to(
			town._c_pos[road._closest_index(town._c_pos, lp)])
		if d2 < lamp_d:
			lamp_d = d2
			lamp_w = lp
	if lamp_w != Vector3.ZERO:
		var ic: int = clampi(road._closest_index(town._c_pos, lamp_w) - 4,
			1, town._c_pos.size() - 2)
		var f88: Vector3 = (town._c_pos[ic + 1] - town._c_pos[ic]).normalized()
		var r88: Vector3 = f88.cross(Vector3.UP).normalized()
		var side88: float = signf((lamp_w - town._c_pos[ic]).dot(r88))
		var eye88: Vector3 = town._c_pos[ic] - r88 * side88 * 2.6 + Vector3(0.0, 1.75, 0.0)
		_ville_park(town._c_pos[ic] - f88 * 5.5 + r88 * side88 * 1.2,
			atan2(-f88.x, -f88.z))
		await get_tree().process_frame
		await _ville_cam_shot("88_ville_carrefour.png", eye88,
			lamp_w + Vector3(0.0, -1.2, 0.0), 62.0)
		print("  (88_ville_carrefour : le mat allume retenu est a %.1f m de l'axe du tronc, la camera a %.1f m de lui)" % [
			lamp_d, eye88.distance_to(lamp_w)])

	# 89 : une rue laterale, prise de sa bouche. La voiture est posee sur
	# l'axe de la transversale, 9 m au-dela du bord de la nationale, nez dans
	# la rue : les facades sont a 6 m de l'axe de part et d'autre (SETBACK), et
	# ce sont leurs fenetres qu'on vient voir.
	var i89 := -1
	var side89 := 1.0
	for si in (town._plan.streets as Array).size():
		var st2: Dictionary = town._plan.streets[si]
		if String(st2["kind"]) != "cross":
			continue
		if i89 < 0 or absf(float(st2["s"]) - 130.0) \
				< absf(float(town._plan.streets[i89]["s"]) - 130.0):
			i89 = si
	if i89 >= 0:
		var st3: Dictionary = town._plan.streets[i89]
		side89 = 1.0 if absf(float(st3["b"])) > absf(float(st3["a"])) else -1.0
		var s89: float = float(st3["s"])
		# LA VOITURE EST DEVANT L'OBJECTIF, PAS DERRIERE. Prise du siege, une
		# rue laterale ne rend rien : l'asphalte est a 0,085 d'albedo, les
		# phares eclairent du bitume, et la premiere version n'a montre qu'un
		# pare-brise noir. De face, ce sont les DEUX FAISCEAUX qu'on voit,
		# tailles dans le brouillard volumetrique, et les fenetres allumees des
		# deux rangees de facades cadrent la rue.
		var p89: Vector3 = town._world(s89, side89 * 12.0)
		var e89: Vector3 = town._world(s89, side89 * 28.0)
		var d89: Vector3 = (e89 - p89).normalized()
		var q89: Vector3 = Vector3.UP.cross(d89).normalized()
		_ville_park(p89, atan2(-d89.x, -d89.z))
		await get_tree().process_frame
		await _ville_cam_shot("89_ville_rue.png",
			e89 + q89 * 4.2 + Vector3(0.0, 1.55, 0.0),
			p89 + Vector3(0.0, 1.05, 0.0), 60.0)

	# 90 : le repere au bout de sa rue. Camera POSEE dans la rue a 1,75 m du
	# sol, a 38 m du socle, la voiture 6 m derriere elle et phares allumes. Le
	# pare-brise ne convient pas pour celle-la : le pavillon coupe le ciel a
	# 11 degres (releve du banc de la lune) et le clocher de Corbeny monte a
	# 22 m, soit 30 degres a 38 m — le toit de la voiture le couperait en deux.
	if town._lm_key != "" and town._lm_site.has(town.town_name):
		var site: Vector4 = town._lm_site[town.town_name]
		var top: float = float((town._lm[town._lm_key] as Array)[7])
		var base: Vector3 = town._world(site.x, site.y)
		var eye: Vector3 = town._world(site.x + site.z * 38.0,
			site.y + site.w * 38.0)
		var back: Vector3 = town._world(site.x + site.z * 44.0,
			site.y + site.w * 44.0)
		var d90: Vector3 = (base - back).normalized()
		_ville_park(back, atan2(-d90.x, -d90.z))
		await get_tree().process_frame
		await _ville_cam_shot("90_ville_repere.png",
			eye + Vector3(0.0, 1.75, 0.0),
			base + Vector3(0.0, top * 0.40, 0.0), 62.0)

	# --- 90bis : la ville du cauchemar ------------------------------------
	# LA QUATRIEME PROMESSE DU J3, ET LA SEULE QUI N'AVAIT NI BANC NI CAPTURE.
	# town.gd expose set_dark() et road.gd l'appelle dans suspend_town() —
	# seulement PERSONNE N'APPELAIT suspend_town(), un grep n'en rendait que sa
	# definition et deux commentaires. La ville du cauchemar etait donc une
	# ville ORDINAIRE au milieu du monde rouge, et la capture 90 du banc etait
	# le clocher de Corbeny. _enter_nightmare le corrige ; ceci le mesure.
	#
	# ON MESURE SUR LES PIXELS, PARCE QU'UN BOOLEEN NE PROUVE RIEN ICI. _dark a
	# vrai, trois lampes eteintes et une reference de materiau echangee se
	# lisent dans l'objet ; ce que le JOUEUR voit ne se lit que dans l'image.
	# On prend donc DEUX captures au MEME cadrage, a la meme nuit, memes phares,
	# meme brouillard, voiture a l'arret — seul suspend_town() tourne entre les
	# deux — et on compare leur luminance moyenne, un pixel sur seize.
	#
	# LE ROUGE DE _enter_nightmare N'EST PAS ICI, ET C'EST VOULU : il baisse
	# l'ambiante de 0,30 a 0,062, epaissit le brouillard de 0,030 a 0,045 et
	# desature toute l'image. Il ferait tomber la luminance sans que la ville y
	# soit pour rien, et la mesure n'aurait plus de sujet. Ce que le monde rouge
	# ajoute par-dessus est l'affaire de sleeptest ; ici on isole la VILLE.
	#
	# CE QUE CE BLOC EMPRUNTE ET REND. suspend_town() annule aussi la ville
	# PROMISE : sans la remettre, les cinq bourgs suivants ne s'armeraient
	# jamais et DEUX VILLES JAMAIS ENSEMBLE resterait sans marge a mesurer. On
	# releve donc _town_g / _town_id avant, et program_town les repose apres —
	# program_town ne touche que ces deux champs, la remise est exacte.
	print("--- la ville du cauchemar ----------------------------------------")
	var i_dk: int = clampi(TownPlan.PAD - 3, 1, town._c_pos.size() - 2)
	var f_dk: Vector3 = (town._c_pos[i_dk + 1] - town._c_pos[i_dk]).normalized()
	var r_dk: Vector3 = f_dk.cross(Vector3.UP).normalized()
	_ville_park(town._c_pos[i_dk] + r_dk * 1.2, atan2(-f_dk.x, -f_dk.z))
	# Les trois lampes se reposent sur des mats d'ici : _relight ne tourne qu'a
	# 4 Hz (RELIGHT_EVERY = 0,25 s) et le banc vient de porter la voiture d'un
	# bout du bourg a l'autre pour les captures. Sans cette attente, l'image
	# claire montrerait des lampes restees derriere, et l'eteinte n'aurait rien
	# a eteindre.
	t = 0.0
	while t < 1.2:
		await get_tree().process_frame
		t += get_process_delta_time()
	var lamps_on := 0
	for l4 in omnis:
		if (l4 as OmniLight3D).visible:
			lamps_on += 1
	var cam_dk := Camera3D.new()
	cam_dk.fov = 64.0
	cam_dk.far = 600.0
	add_child(cam_dk)
	cam_dk.global_position = car.global_position + Vector3(0.0, 2.05, 0.0)
	cam_dk.look_at(town._world(90.0, 0.0) + Vector3(0.0, 3.0, 0.0), Vector3.UP)
	cam_dk.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	var st_on: Array = await _ville_shot_stats("90_ville_claire.png")

	# LA VILLE PROMISE, ET IL FAUT SOUVENT LA POSER SOI-MEME. A cet instant du
	# banc, road.gd n'a rien en attente une fois sur deux : Corbeny a deux
	# sorties, donc _on_town_reached y programme un Y et PAS une ville, et
	# _town_g ne sera repose qu'au verdict du Y, 366 m plus loin. Sans cette
	# promesse posee ici, la moitie des lancements mesurerait "-1 est retombe a
	# -1" et la ligne serait verte sans rien avoir annule.
	var g_keep: int = road._town_g
	var id_keep: String = road._town_id
	if g_keep < 0:
		road.program_town(road.head_index() + 400, String(town.town_name))
	var promised: int = road._town_g
	road.suspend_town()
	await get_tree().process_frame
	await get_tree().process_frame
	var st_off: Array = await _ville_shot_stats("90_ville_cauchemar.png")
	var lamps_dark := 0
	for l5 in omnis:
		if (l5 as OmniLight3D).visible:
			lamps_dark += 1
	var num_dark: bool = town._number.visible
	var glow_dark: bool = town._surf_glow >= 0 \
		and town._mesh.surface_get_material(town._surf_glow) == town._mat_glow_dark
	var warm_on: int = int(st_on[1])
	var warm_off: int = int(st_off[1])
	print("  LA VILLE DU CAUCHEMAR EST NOIRE : %s   (suspend_town() a rendu la ville PROMISE — l'echantillon %d est retombe a %d — et noirci celle qui est ARMEE : %d feu(x) chaud(s) dans la moitie haute de l'image allumee, %d eteinte, sur %d pixels lus, pour un seuil de 80 puis 0 ; luminance moyenne de l'image %.4f contre %.4f, et ce chiffre-la ne prouve rien — la flaque des phares ne bouge pas. %d lampe(s) allumee(s) contre %d, materiau emissif echange %s, numero d'adresse visible %s. Meme cadrage, meme nuit, memes phares, voiture a l'arret : 90_ville_claire.png et 90_ville_cauchemar.png)" % [
		promised >= 0 and road._town_g == -1 and bool(town._dark) and glow_dark
		and lamps_on == 3 and lamps_dark == 0
		and warm_on > 80 and warm_off == 0,
		promised, road._town_g, warm_on, warm_off, int(st_on[2]),
		float(st_on[0]), float(st_off[0]),
		lamps_on, lamps_dark, glow_dark, num_dark])
	town.set_dark(false)
	road.program_town(g_keep, id_keep)
	cam_dk.queue_free()
	car.cam.make_current()
	await get_tree().process_frame

	# --- le cout, en A/B EN ROULANT ---------------------------------------
	# ON BASCULE LA VILLE, ON NE COMPARE PAS DEUX PAYSAGES. Une mesure "sur la
	# nationale nue, puis au coeur du bourg" compare deux endroits differents :
	# des arbres et des poteaux d'un cote, un bourg de l'autre, et le tirage de
	# la nuit dans les deux. Elle donne d'ailleurs le bourg GAGNANT — 5,6 ms
	# dans le bourg contre 14 sur la nationale plantee — ce qui ne prouve rien
	# du cout de la ville. Ici, seule la ville s'allume et s'eteint, par blocs
	# de quatre images, et on ne retient que les deux dernieres de chaque bloc
	# (le rendu a une image de retard).
	#
	# ET ON ROULE, alors que la premiere version mesurait A L'ARRET. Le motif
	# est arithmetique et il a fait rougir la ligne : a l'arret dans un bourg,
	# l'image tombe a 2,8 ms sur cette machine, et le demi-milligramme de
	# seconde que coute la ville y pese DIX-HUIT POUR CENT — pour un seuil de
	# quinze. Le meme cout absolu pese 4 % sur les 12 ms d'une image chargee.
	# Un pourcentage dont le denominateur est la vitesse a vide de la machine ne
	# mesure pas le bourg ; on prend donc le denominateur du JEU, c'est-a-dire
	# la traversee conduite a 12,5 m/s, exactement ce que le plan demande.
	#
	# Quatre metres separent deux blocs consecutifs a cette vitesse : le paysage
	# ne change pas entre un bloc allume et le bloc eteint qui le suit.
	#
	# ET LA DIFFERENCE SE PREND BLOC A BLOC, PAS ENTRE DEUX MEDIANES GLOBALES —
	# c'est la correction de cette version, et elle vient d'un releve, pas d'une
	# idee. Dix lancements de l'ancienne formule ont rendu ces surcouts :
	#   +6,6  +14,5  +3,1  +0,9  +5,0  -2,1  +7,0  +6,9  +3,0  +18,2 %
	# mediane 5,8 pour un seuil de 15 — et UN ROUGE SUR DIX. Un cout de ville ne
	# change pas de signe : le -2,1 dit a lui seul que la ligne mesurait autre
	# chose. Les deux lancements les plus charges en absolu portaient les deux
	# plus hauts ecarts : ce n'etait pas la ville, c'etait la DERIVE de la
	# machine entre le debut et la fin des huit secondes de mesure, plus la
	# queue des images longues, encaissees par une mediane globale qui ne sait
	# pas d'ou vient chaque echantillon.
	#
	# Deux remedes, et le second n'a rien trouve a corriger — ce qui est aussi
	# un releve :
	#  - MEDIANE APPARIEE. Chaque bloc allume est compare au bloc eteint qui le
	#    SUIT — 8 images d'ecart, 4 m de route —, et la ligne rend la mediane de
	#    ces differences. Une derive lente sort du calcul par construction : elle
	#    est dans les deux termes de chaque paire. Trois lancements du banc
	#    corrige ont rendu +0,08, +0,11 et +0,02 ms, la ou l'ancienne formule
	#    balayait de -0,3 a +1,5 ms sur le meme bourg.
	#  - LES IMAGES DE RECONSTRUCTION DU RUBAN SORTENT. Des que road.gd avale un
	#    echantillon (_index0 avance), l'image porte une re-triangulation
	#    entiere de la fenetre vivante — plusieurs millisecondes qui ne
	#    dependent pas de town.visible. ET IL N'Y EN A AUCUNE ICI, releve :
	#    _index0 n'a pas bouge d'un echantillon sur les 960 images du A/B. Le
	#    demi-tour et le retour au panneau ont ramene la voiture 90 echantillons
	#    DERRIERE la fenetre vivante, road.gd n'a donc plus rien a consommer
	#    pendant que le banc mesure. Le compteur reste, et il s'imprime : le
	#    jour ou le banc mesurera ailleurs, on verra la difference au lieu de la
	#    subir.
	#
	# CE QUE LE POURCENTAGE NE PEUT PAS ETRE, ET IL FAUT LE LIRE AVEC. Les
	# millisecondes sont stables d'un lancement a l'autre ; le DENOMINATEUR ne
	# l'est pas — l'image eteinte a valu 2,73, 3,49, 8,30 et 10,94 ms sur quatre
	# lancements du meme banc, selon ce que la machine faisait par ailleurs. Le
	# meme cout absolu y pese donc de 1 a 4 %. Le chiffre qui decrit le bourg
	# est en millisecondes ; le pourcentage decrit le bourg DIVISE PAR la
	# machine du soir, et c'est lui que le plan a mis un seuil dessus.
	var ip: int = clampi(TownPlan.PAD + 5, 1, town._c_pos.size() - 2)
	var fip: Vector3 = (town._c_pos[ip + 1] - town._c_pos[ip]).normalized()
	var rip: Vector3 = fip.cross(Vector3.UP).normalized()
	_ville_park(town._c_pos[ip] + rip * 1.2, atan2(-fip.x, -fip.z))
	await get_tree().process_frame
	Engine.time_scale = 2.0
	var on_calls_l := []
	var off_calls_l := []
	var on_ms_l := []
	var off_ms_l := []
	var blocs: Array = []            # une case par bloc de 4 images, ses images retenues
	var bloc: Array = []
	var b_cur := -1
	var ab_off := 0
	var ab_skip := 0                 # images de reconstruction du ruban, ecartees
	var ab_skip_ms := 0.0
	var k := 0
	t_prev = Time.get_ticks_usec()
	# ON S'ARRETE AU BOURG, PAS A UN COMPTE D'IMAGES. Le plafond de 960 images
	# vaut sur une machine chargee (8 s a 12 ms) ; sur une machine libre, ce
	# sont les 340 m du bourg qui bornent, et le banc rendrait la main au milieu
	# de la nationale, ou le paysage n'est plus le meme des deux cotes.
	while k < 960 and road._closest_index(town._c_pos, car.global_position) \
			< town._c_pos.size() - 20:
		var b: int = k / 4
		var pos4: int = k % 4
		k += 1
		if b != b_cur:
			if b_cur >= 0:
				blocs.append(bloc)
			bloc = []
			b_cur = b
		var want: bool = b % 2 == 0
		town.visible = want
		var idx0: int = road._index0
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt: float = float(now - t_prev) / 1000.0
		t_prev = now
		car.speed = 12.5
		_ville_rail(town._c_pos, 1.2, false)
		if not town.visible:
			ab_off += 1
		if pos4 < 2:
			continue                 # le rendu a une image de retard : les deux premieres du bloc sautent
		if road._index0 != idx0:
			ab_skip += 1
			ab_skip_ms = maxf(ab_skip_ms, dt)
			continue
		bloc.append(dt)
		var calls := float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		if want:
			on_calls_l.append(calls)
			on_ms_l.append(dt)
		else:
			off_calls_l.append(calls)
			off_ms_l.append(dt)
	if b_cur >= 0:
		blocs.append(bloc)
	town.visible = true
	Engine.time_scale = 1.0
	car.speed = 0.0
	var on_n: int = on_ms_l.size()
	var off_n: int = off_ms_l.size()
	var on_calls: float = _ville_median(on_calls_l)
	var off_calls: float = _ville_median(off_calls_l)
	var on_ms: float = _ville_median(on_ms_l)
	var off_ms: float = _ville_median(off_ms_l)
	var d_calls: float = on_calls - off_calls
	# Les paires : bloc allume contre le bloc eteint qui le suit. Une paire dont
	# un des deux cotes a tout perdu en reconstructions ne se compte pas — elle
	# n'aurait plus de terme a soustraire.
	var pairs: Array = []
	for b in range(0, blocs.size() - 1, 2):
		var a1: Array = blocs[b]
		var a2: Array = blocs[b + 1]
		if a1.is_empty() or a2.is_empty():
			continue
		pairs.append(_ville_median(a1) - _ville_median(a2))
	var d_ms: float = _ville_median(pairs)
	var d_lo := 1.0e18
	var d_hi := -1.0e18
	for p in pairs:
		d_lo = minf(d_lo, float(p))
		d_hi = maxf(d_hi, float(p))
	if pairs.is_empty():
		d_lo = 0.0
		d_hi = 0.0
	var d_ips: float = 100.0 * d_ms / off_ms

	# --- les cinq bourgs suivants -----------------------------------------
	# LA MARGE ENTRE DEUX VILLES SE MESURE EN METRES DE ROUTE, pas en images :
	# le noeud-ville est UNIQUE (road.gd n'en fabrique qu'un), donc deux bourgs
	# ne peuvent pas etre a l'ecran ensemble par construction. Ce qui PEUT
	# arriver, et ce que cette ligne surveille, c'est que arm() tombe sur une
	# ville encore visible : le bourg qu'on traverse disparaitrait d'un coup et
	# un autre se batirait a sa place, 300 m devant. On compte donc les
	# metres entre le sleep() de A et le arm() de B, et les images ou le nom a
	# change sans que la ville se soit eteinte.
	print("--- les bourgs suivants ------------------------------------------")
	var events: Array = [["arm", String(town.town_name), road.head_index()]]
	var last_vis: bool = town.visible
	var last_name: String = String(town.town_name)
	var overlaps := 0
	var arms := 1
	var built_names := {last_name: true}
	Engine.time_scale = 6.0
	t = 0.0
	while t < 400.0 and arms < 6:
		await get_tree().process_frame
		t += get_process_delta_time()
		var in_town_line: bool = town.visible \
			and road._closest_index(town._c_pos, car.global_position) \
				< town._c_pos.size() - 3
		if in_town_line:
			Engine.time_scale = 3.0
			car.speed = 14.0
			_ville_rail(town._c_pos, 1.2, false)
		else:
			Engine.time_scale = 6.0
			car.speed = maxf(car.speed, 25.0)
			_rail(1.2)
		var vis: bool = town.visible
		var nm: String = String(town.town_name)
		if vis and not last_vis:
			events.append(["arm", nm, road.head_index()])
			arms += 1
		elif last_vis and not vis:
			events.append(["sleep", last_name, road.head_index()])
		elif vis and last_vis and nm != last_name:
			overlaps += 1
			events.append(["arm", nm, road.head_index()])
			arms += 1
		last_vis = vis
		last_name = nm
		if vis and town._built and road._town_ready and not built_names.has(nm):
			built_names[nm] = true
			audits.append(_ville_audit(town, ref))
	car.speed = 0.0
	Engine.time_scale = 1.0

	t = 0.0
	while t < 20.0 and not (town._built and road._town_ready):
		await get_tree().process_frame
		t += get_process_delta_time()
		car.speed = maxf(car.speed, 14.0)
		_rail(1.2)
	car.speed = 0.0

	# --- les verdicts ------------------------------------------------------
	print("--- les invariants -----------------------------------------------")
	var mask_ok := true
	var mask_in := 0
	var mask_off := 0
	var seam_max := 0.0
	var seam_cnt := 0
	var surf_bad := 0
	var v_max := 0
	var t_max := 0
	var mi_max := 0
	var nd_max := 0
	var tri_tot := 0
	var flat_tot := 0
	var area_bad := 0
	var dot_bad := 0
	var degen := 0
	var twoface := 0
	var under := 0
	var worst_dot := 1.0e18
	var names := ""
	var detail := ""
	for a in audits:
		mask_in += int(a["dans"])
		mask_off += int(a["dans_sans"])
		seam_max = maxf(seam_max, float(a["couture"]))
		seam_cnt += int(a["couture_n"])
		if not (bool(a["ready"]) and bool(a["remis"])) or bool(a["ferme"]):
			mask_ok = false
		if int(a["surf"]) != 6:
			surf_bad += 1
		v_max = maxi(v_max, int(a["v"]))
		t_max = maxi(t_max, int(a["t"]))
		mi_max = maxi(mi_max, int(a["mi"]))
		nd_max = maxi(nd_max, int(a["noeuds"]))
		tri_tot += int(a["tri"])
		flat_tot += int(a["plat"])
		area_bad += int(a["aire_faux"])
		dot_bad += int(a["normale_faux"])
		degen += int(a["degenere"])
		twoface += int(a["deux_faces"])
		under += int(a["sous_face"])
		worst_dot = minf(worst_dot, float(a["pire"]))
		if detail == "" and String(a["detail"]) != "":
			detail = "%s, %s" % [a["nom"], a["detail"]]
		names += "%s %d/%d, " % [a["nom"], a["v"], a["t"]]
	names = names.rstrip(", ")

	print("  LE MASQUE EST OUVERT : %s   (%d triangle(s) du ruban national dans la fenetre que le bourg dessine, sur %d ville(s) — et %d dans la MEME fenetre, a la MEME image, une fois le masque referme a la main : c'est ce que le masque supprime. La couture, mesuree SUR LE DESSIN : %.6f m d'ecart maxi entre le dernier sommet d'asphalte que road.gd emet avant le trou et le premier que la ville pose, sur %d sommets compares, seuil 0,001)" % [
		mask_ok and mask_in == 0 and mask_off > 0
		and seam_cnt == 3 * audits.size() and seam_max < 0.001,
		mask_in, audits.size(), mask_off, seam_max, seam_cnt])
	# LE COMPTE EST CELUI DE TOUTE LA DESCENDANCE, ET IL EST PASSE DE 1 A 5.
	# La ligne annoncait "1 MeshInstance3D au plus" en ne regardant que les
	# enfants DIRECTS de la ville : le maillage aux six surfaces est bien seul a
	# ce rang, mais chacun des deux panneaux porte un poteau et une tole, et
	# quatre objets qui dessinent etaient comptes pour rien. Cinq, donc — et
	# c'est le chiffre que l'en-tete de town.gd donnait deja, avec ses dix-sept
	# noeuds, quand le banc en imprimait un.
	print("  LA VILLE TIENT EN SIX SURFACES : %s   (%d MeshInstance3D au plus dans TOUTE la ville — le maillage aux six surfaces, plus le poteau et la tole de chacun des deux panneaux — sur %d noeuds de descendance ; %d ville(s) hors des 6 surfaces, %d sommets et %d triangles au pire pour des seuils de 8 000 et 6 500 — soit %.0f %% et %.0f %% de marge ; par bourg : %s)" % [
		mi_max == 5 and nd_max == 17 and surf_bad == 0
		and v_max < 8000 and t_max < 6500 and audits.size() >= 4,
		mi_max, nd_max, surf_bad, v_max, t_max,
		100.0 * (8000.0 - float(v_max)) / 8000.0,
		100.0 * (6500.0 - float(t_max)) / 6500.0, names])
	print("  LES APPELS DE DESSIN SONT COMPTES : %s   (%.1f appels par image dans le bourg contre %.1f la ville eteinte, medianes de %d et %d images alternees toutes les quatre sur la meme traversee : hausse %.1f pour un seuil de 60. La nationale nue, en roulant, en demandait %.1f)" % [
		d_calls < 60.0 and on_n > 60 and off_n > 60,
		on_calls, off_calls, on_n, off_n, d_calls, bare_calls])
	print("  TOUT EST A L'ENDROIT : %s   (%d triangles de bourg sur %d ville(s) : %d a plat dont %d qui regardent le SOL, %d a deux faces (les _quad2 des tetes de lampadaire, exemptes et comptees), %d degeneres ; %d d'aire signee du mauvais signe et %d dont la normale geometrique contredit la normale d'ombrage. Le pire produit vaut %+.3f, la ou la chaussee de la nationale vaut +1)" % [
		area_bad == 0 and dot_bad == 0 and tri_tot > 15000,
		tri_tot, audits.size(), flat_tot, under, twoface, degen,
		area_bad, dot_bad, worst_dot])
	if detail != "":
		print("    (ou : %s— les surfaces 5 et 6 versent les maisons, puis les mats, puis le repere, dans cet ordre)" % [detail])

	var lights: Array = []
	_ville_omnis(town, lights)
	var shadows: Array = []
	_ville_shadow_lights(get_tree().root, shadows)
	print("  TROIS LUMIERES, JAMAIS SOUS LE NEZ : %s   (%d OmniLight3D dans le bourg, %d a %d allumees a chaque image de la traversee et du retour ; %d allumages releves, le plus proche a %.1f m pour un plancher de %.1f ; brouillard volumetrique %.2f au plus pour un plafond de 0,2)" % [
		lights.size() == 3 and lamp_min >= 60.0 and fog_max <= 0.2
		and lamp_lit_max == 3 and lamp_moves >= 4,
		lights.size(), lamp_lit_min, lamp_lit_max, lamp_moves, lamp_min, 60.0,
		fog_max])
	print("  AUCUNE OMBRE NEUVE : %s   (%d lumiere(s) a ombres dans toute la scene, bourg arme : %s)" % [
		shadows.size() == 2, shadows.size(), ", ".join(shadows)])
	# LE VERDICT NE PORTE PLUS QUE CE QU'IL MESURE. Il avait quatre
	# conjonctions et deux ne disaient rien : `yaw_done > 170` ne pouvait etre
	# faux que si la boucle de braquage avait expire — elle ne sort qu'a PI,
	# soit 180,0 deg — et `back_m < 13` que si celle du retour avait expire —
	# elle ne sort qu'a 12,0 m. Deux detecteurs de depassement de delai
	# deguises en invariants, verts par construction, et le lecteur croyait
	# lire deux mesures de plus. Ce que cette ligne mesure vraiment tient en
	# deux chiffres : l'ECART MAXI a la chaussee pendant la manoeuvre — c'est
	# lui qui dit que la ville rattrape la voiture par l'autre rue — et le
	# compte d'images ou contains() a tenu. Les deux garde-fous restent, ils
	# sont imprimes a part et sous leur vrai nom.
	print("  LE DEMI-TOUR TIENT : %s   (demi-tour AU VOLANT sur le carrefour a s = %.0f m : off_road_dist %.2f m au plus dans l'arc, %.2f m sur la manoeuvre entiere et %.2f m sur la traversee d'approche, seuil 5,80 ; contains() a repondu vrai sur %d des %d images du demi-tour et du retour. La manoeuvre est allee au bout — braquage %s a %.0f deg, retour %s a %.1f m du panneau : ce sont les conditions d'arret des deux boucles, elles ne rougissent que sur un delai depasse)" % [
		off_max < 5.8 and turn_in == turn_n and turn_done and back_done,
		s_cross, turn_arc, turn_max, off_cross, turn_in, turn_n,
		turn_done, yaw_done, back_done, back_m])
	print("  LA VILLE NE S'ETEINT PAS DEDANS : %s   (%d image(s) eteinte(s) sur les %d de la traversee, du demi-tour et du retour — hors les %d images ou le banc l'eteint LUI-MEME pour le A/B, comptees a part)" % [
		vis_off == 0 and vis_n > 400, vis_off, vis_n, ab_off])

	var margins := PackedFloat32Array()
	var pending := -1
	for e in events:
		if String(e[0]) == "sleep":
			pending = int(e[2])
		elif String(e[0]) == "arm" and pending >= 0:
			margins.append(float(int(e[2]) - pending) * RoadScript.STEP)
			pending = -1
	var marge_min := 1.0e18
	var marge_txt := ""
	for m in margins:
		marge_min = minf(marge_min, m)
		marge_txt += "%.0f " % m
	print("  DEUX VILLES JAMAIS ENSEMBLE : %s   (%d bourgs armes, %d marge(s) mesurees entre l'extinction de l'un et l'armement du suivant : %sm, la plus courte %.0f m pour un seuil de 100 ; %d image(s) ou le nom a change sans que la ville se soit eteinte)" % [
		arms >= 6 and margins.size() >= 5 and marge_min > 100.0
		and overlaps == 0,
		arms, margins.size(), marge_txt, marge_min, overlaps])
	# LE POURCENTAGE EST LE SEUIL DU PLAN, ET IL FAUT LIRE LES MILLISECONDES A
	# COTE : le meme cout absolu pese 18 % sur une image a l'arret et 4 % sur
	# une image chargee. Le denominateur reste celui du JEU, la traversee a
	# 12,5 m/s. Ce qui a change, c'est le NUMERATEUR : ce n'est plus un ecart
	# entre deux medianes globales — il valait de -2,1 a +18,2 % selon le
	# lancement, et rougissait une fois sur dix sans que la ville y soit pour
	# rien — mais la mediane des differences APPARIEES, bloc a bloc, images de
	# reconstruction du ruban ecartees. La ligne imprime l'etendue de ces
	# differences : c'est elle, et pas la mediane, qui dit ce que la mesure vaut.
	print("  LE COUT NE SE VOIT PAS : %s   (le bourg traverse a 12,5 m/s, sa visibilite basculee toutes les quatre images : %.2f ms par image allume contre %.2f eteint, sur %d et %d images retenues. Difference APPARIEE, chaque bloc allume contre le bloc eteint qui le suit : mediane %+.2f ms sur %d paires (etendue %+.2f a %+.2f), soit %+.1f %% pour un seuil de 15, ou %.0f ips contre %.0f. %d image(s) de reconstruction du ruban ecartees (la plus longue a %.2f ms) : road.gd n'avale aucun echantillon pendant le A/B, le demi-tour a laisse la fenetre vivante loin devant. Le chiffre qui decrit le bourg est la MILLISECONDE ; le pourcentage la divise par l'image du soir, qui va de 2,7 a 11 ms sur cette machine selon les lancements. Pour situer : la traversee entiere tient %.2f ms par image sur %d images, quand la nationale NUE et plantee en demande %.2f)" % [
		d_ips < 15.0 and on_n > 60 and off_n > 60 and pairs.size() >= 20,
		on_ms, off_ms, on_n, off_n,
		d_ms, pairs.size(), d_lo, d_hi, d_ips,
		1000.0 / on_ms, 1000.0 / off_ms, ab_skip, ab_skip_ms,
		cross_ms / maxf(float(cross_n), 1.0), cross_n, bare_ms])

	# --- les temoins : ce que chaque ligne detecte quand on la casse -------
	# LA LECON DU J2, ECRITE DANS LE BANC ET PAS DANS UN RAPPORT. Trois de ses
	# neuf lignes ne mesuraient pas ce que leur titre annoncait, et aucune ne
	# savait le dire. Ci-dessous, chaque ligne du dessus est reprise sur une
	# geometrie ou une liste d'evenements DELIBEREMENT fausse, avec le meme
	# code de mesure : si le temoin ne rougit pas, c'est la ligne verte qui ne
	# vaut rien. Les temoins ne portent pas de verdict — ils portent un chiffre
	# et le mot ROUGIRAIT, pour que le compte de lignes vertes du banc reste
	# celui des invariants.
	print("--- les temoins : ce que chaque ligne detecte quand on la casse ---")
	print("  [temoin] LE MASQUE EST OUVERT rougirait : %d triangles dans la fenetre du bourg des que road._town_in retombe a -1, contre %d avec le masque. Meme image, meme ruban, meme fenetre." % [
		mask_off, mask_in])

	var kk: int = road._town_in - road._index0
	var seam_bad := -1.0
	var seam_good := -1.0
	if kk >= 0 and kk < road._pos.size():
		var keepp: Vector3 = road._pos[kk]
		road._pos[kk] = keepp + Vector3(0.05, 0.0, 0.0)
		road._rebuild()
		seam_bad = _ville_seam(town)
		road._pos[kk] = keepp
		road._rebuild()
		seam_good = _ville_seam(town)
	print("  [temoin] LA COUTURE rougirait : %.4f m des qu'on decale de 5 cm le seul echantillon _pos[_town_in] du ruban et qu'on re-triangule ; remis, elle retombe a %.6f m." % [
		seam_bad, seam_good])

	var flip: Array = _ville_flip(town._mesh, float(ref[0]), float(ref[1]))
	print("  [temoin] TOUT EST A L'ENDROIT rougirait : un SEUL triangle retourne dans une copie de la surface 0 — %d d'aire du mauvais signe et %d de normale contredite sur %d, la ou le maillage livre en donne 0 et 0." % [
		flip[1], flip[2], flip[0]])

	# On avance l'armement qui suit la PLUS COURTE des marges reelles, et juste
	# assez pour la faire tomber a 60 m : le temoin doit franchir le seuil, pas
	# seulement bouger. Avancer un armement au hasard laissait la ligne verte.
	var fake: Array = events.duplicate(true)
	var fpend0 := -1
	for i in fake.size():
		if String(fake[i][0]) == "sleep":
			fpend0 = int(fake[i][2])
		elif String(fake[i][0]) == "arm" and fpend0 >= 0:
			if absf(float(int(fake[i][2]) - fpend0) * RoadScript.STEP - marge_min) < 1.0:
				fake[i][2] = fpend0 + int(60.0 / RoadScript.STEP)
				break
			fpend0 = -1
	var fmin := 1.0e18
	var fpend := -1
	for e in fake:
		if String(e[0]) == "sleep":
			fpend = int(e[2])
		elif String(e[0]) == "arm" and fpend >= 0:
			fmin = minf(fmin, float(int(e[2]) - fpend) * RoadScript.STEP)
			fpend = -1
	print("  [temoin] DEUX VILLES JAMAIS ENSEMBLE rougirait : le meme calcul sur la meme liste d'evenements, l'armement qui suit la plus courte marge ramene a 60 m — la ligne rendrait %s avec %.0f m, contre %s et %.0f m reellement mesures." % [
		fmin > 100.0, fmin, marge_min > 100.0, marge_min])

	var s_gap := s_cross + 60.0
	var p_bad: Vector3 = town._world(s_gap, 9.0)
	var p_ok: Vector3 = town._world(s_gap, 1.2)
	print("  [temoin] LE DEMI-TOUR TIENT rougirait : off_road_dist rend %.2f m pour un point pose a 9 m de l'axe du tronc (s = %.0f m, entre deux transversales) et %.2f m pour le meme point ramene sur la voie — la mesure n'est pas une constante." % [
		road.off_road_dist(p_bad), s_gap, road.off_road_dist(p_ok)])

	print("  [temoin] TROIS LUMIERES rougirait : sur la traversee, le mat le plus proche que la voiture ait croise etait a %.2f m d'elle ; une lampe qui prendrait le plus proche au lieu du plus proche AU-DELA de 60 m se serait allumee la, sous le nez, pour un plancher de 60,0." % [
		mast_near])
	var lamp0: OmniLight3D = lights[0]
	lamp0.shadow_enabled = true
	var sh2: Array = []
	_ville_shadow_lights(get_tree().root, sh2)
	lamp0.shadow_enabled = false
	var sh3: Array = []
	_ville_shadow_lights(get_tree().root, sh3)
	print("  [temoin] AUCUNE OMBRE NEUVE rougirait : shadow_enabled remis a vrai sur une seule lampe du bourg et le compte passe de %d a %d ; remis a faux, il retombe a %d." % [
		shadows.size(), sh2.size(), sh3.size()])

	# DESTRUCTIF, ET EN DERNIER : on verse une septieme surface dans le
	# maillage du bourg. ArrayMesh ne sait pas retirer une surface, seulement
	# les effacer toutes — ce temoin ne peut donc pas se remettre, et il est
	# donc le dernier geste du banc.
	var vv := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK])
	var nnn := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	var ff := PackedInt32Array([0, 1, 2])
	var arrs := []
	arrs.resize(Mesh.ARRAY_MAX)
	arrs[Mesh.ARRAY_VERTEX] = vv
	arrs[Mesh.ARRAY_NORMAL] = nnn
	arrs[Mesh.ARRAY_INDEX] = ff
	town._mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	print("  [temoin] LA VILLE TIENT EN SIX SURFACES rougirait : une surface de plus versee dans le maillage du bourg et le compte passe a %d." % [
		town._mesh.get_surface_count()])
	print("  [temoin] LA VILLE NE S'ETEINT PAS DEDANS rougirait : le meme compteur a releve %d images eteintes pendant le A/B, ou le banc bascule town.visible lui-meme." % [
		ab_off])

	Engine.time_scale = 1.0
	get_tree().quit()


## La couture SUR LE DESSIN, en un chiffre : l'ecart maxi entre les trois
## sommets d'asphalte que road.gd ecrit a l'echantillon _town_in et les trois
## premiers que le bourg ecrit. Sert au verdict et a son temoin.
func _ville_seam(town: Node3D) -> float:
	var k: int = road._town_in - road._index0
	if k < 0 or k >= road._pos.size() or (town._mesh as ArrayMesh).get_surface_count() == 0:
		return -1.0
	var ra: Array = road._mesh.surface_get_arrays(1)
	var ta: Array = (town._mesh as ArrayMesh).surface_get_arrays(0)
	var rv: PackedVector3Array = ra[Mesh.ARRAY_VERTEX]
	var tv: PackedVector3Array = ta[Mesh.ARRAY_VERTEX]
	var d := 0.0
	for c in 3:
		if k * 3 + c < rv.size() and c < tv.size():
			d = maxf(d, rv[k * 3 + c].distance_to(tv[c]))
	return d


## Le temoin d'enroulement : la surface 0 du bourg recopiee dans un maillage
## neuf avec UN triangle retourne, passee au meme audit. Rend [triangles,
## aires fausses, normales contredites].
##
## On retourne un triangle et pas la surface entiere : c'est la panne
## realiste — un `f.append_array` dont deux indices ont ete intervertis — et
## c'est la plus difficile a voir, parce qu'elle laisse tout le reste juste.
func _ville_flip(mesh: ArrayMesh, want_area: float, want_dot: float) -> Array:
	var arr: Array = mesh.surface_get_arrays(0)
	var f: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if f.size() < 3:
		return [0, 0, 0]
	var swap: int = f[1]
	f[1] = f[2]
	f[2] = swap
	arr[Mesh.ARRAY_INDEX] = f
	var copy := ArrayMesh.new()
	copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var w: Dictionary = _ville_winding(copy, want_area, want_dot)
	return [w["tri"], w["area_bad"], w["dot_bad"]]
