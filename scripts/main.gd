extends Node3D
##
## Point d'entree du prototype.
## Construit l'ambiance de nuit, la route infinie et la voiture.
##

const CarScript := preload("res://scripts/car.gd")
const RoadScript := preload("res://scripts/road.gd")
const Retro := preload("res://scripts/retro.gd")

@export_group("Ambiance")
## Densite du brouillard : plus c'est haut, moins on voit loin.
@export var fog_density := 0.030
@export var volumetric := true
@export var moon_energy := 0.05

var car
var road
var _ground: MeshInstance3D
var _env: Environment
var _auto_shot := -1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_environment()
	_build_ground()
	_build_dither_overlay()

	car = CarScript.new()
	car.name = "Car"
	add_child(car)

	road = RoadScript.new()
	road.name = "Road"
	road.target = car
	add_child(road)

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


func _process(_delta: float) -> void:
	# Le sol suit la voiture : on ne voit jamais son bord dans le brouillard.
	if is_instance_valid(car):
		_ground.global_position = Vector3(car.global_position.x, -0.04, car.global_position.z)


func _unhandled_input(event: InputEvent) -> void:
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

	# E, tenu : la vitre descend.
	Input.action_press("crank_open")
	await get_tree().create_timer(2.6).timeout
	Input.action_release("crank_open")
	await get_tree().process_frame
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

	# A, tenu : elle remonte exactement d'ou elle vient.
	Input.action_press("crank_close")
	await get_tree().create_timer(2.6).timeout
	Input.action_release("crank_close")
	await get_tree().process_frame
	print("remontee            : ouverture=%.2f   haut y=%.3f" % [
		win.open, _panel_box(inner).end.y])
	print("  ELLE EST FERMEE   : %s" % (
		absf(_panel_box(inner).end.y - up_in.end.y) < 0.002))

	# On la rouvre a moitie, puis on LACHE LE CLIC en cours de route : la main
	# doit lacher, et la vitre rester ou elle en est. Verifier le relachement
	# vitre fermee ne prouverait rien, elle serait deja en butee.
	Input.action_press("crank_open")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("crank_open")
	await get_tree().process_frame
	var mid: float = win.open
	await _mouse(false)
	await get_tree().create_timer(0.4).timeout
	print("clic relache a %.2f  : la main a lache=%s   ouverture=%.2f" % [
		mid, inter._state == State_IDLE, win.open])
	print("  ELLE RESTE LA     : %s" % (absf(win.open - mid) < 0.001))

	# Et E ne doit plus rien faire : la poignee n'est plus en main.
	Input.action_press("crank_open")
	await get_tree().create_timer(0.8).timeout
	Input.action_release("crank_open")
	print("  E SANS LA POIGNEE : %s   (ouverture toujours %.2f)" % [
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
	print("clic maintenu      : fantome=%s   surface=%s" % [
		inter.ghost_visible(), inter.has_surface()])
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


func _mouse(pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


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

	# Clair de lune : juste assez pour deviner les silhouettes dans le brouillard.
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.64, 0.90)
	moon.light_energy = moon_energy
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	add_child(moon)


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
