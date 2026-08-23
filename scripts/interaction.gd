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

enum State { IDLE, REACHING, HELD, AIMING, PLACING, ADJUSTING, GRIPPING }

## Ou l'objet est tenu, FIXE dans l'espace de la voiture : devant la poitrine,
## un peu a droite, sous la ligne des yeux.
##
## Surtout pas en local camera : la main suivrait le regard, le bras se tordrait
## a chaque mouvement de tete et partirait en butee des qu'on regarde de cote.
## Une main ne suit pas les yeux.
## Recule avec le conducteur : l'oeil est passe de 0.10 a 0.28, un objet laisse
## a -0.22 se serait retrouve a un demi-metre du visage, hors de portee du geste.
const HOLD_POINT := Vector3(-0.21, 0.93, 0.0)

## Portee du bras. Le paquet sur le siege passager est a 0,9 m de l'oeil.
@export var reach := 1.25
## Duree du geste, aller chercher comme reposer.
@export var reach_time := 0.45
## Position de l'objet dans le poing (origine de la main = axe de prise).
@export var in_hand := Vector3(0.0, 0.0, 0.0)

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
				# Rien ne tourne tant que la main n'y est pas arrivee.
				if _blend >= 1.0:
					target.call("wind", Input.get_action_strength("crank_open")
						- Input.get_action_strength("crank_close"), delta)
			_blend = move_toward(_blend, 1.0, delta / reach_time)

	driver.item_point = _goal
	driver.item_blend = _blend

	# L'objet tenu suit la main, pas la visee. Transforms locales : l'objet et la
	# main sont tous deux exprimes dans le repere de la voiture. Son axe de prise
	# (grip_axis) se couche sur celui du poing (-Z local de la main, cote pouce),
	# et il tourne autour pour presenter sa face avant (front_axis) au joueur.
	if held != null:
		held.transform = _held_transform(origin)

	_update_hud()


## Un cran de souris pendant un reglage. car.gd nous l'envoie au lieu de tourner
## la tete du conducteur : on ne peut pas viser et orienter avec le meme geste.
## Transform de l'objet tenu (repere voiture). `eye` : position de l'oeil.
func _held_transform(eye: Vector3) -> Transform3D:
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
	return Transform3D(target * local.transposed(), pos)


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
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event.pressed:
		match _state:
			State.IDLE:
				if target == null:
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
		# le bouton. La vitre reste evidemment ou elle en est.
		_state = State.IDLE
		driver.item_radius = 0.0
	else:
		if _state != State.AIMING:
			return                       # c'est le relachement du clic de prise
		if _surface_hit:
			_drop = _rest_on(_surface_point)
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


## Surface de depose sous le viseur. Toutes sont horizontales : une intersection
## avec le plan de leur dessus suffit.
func _aim_surface(origin: Vector3, dir: Vector3) -> void:
	_surface_hit = false
	if absf(dir.y) < 0.0001:
		return
	var best_t := reach
	for s in cabin.surfaces:
		var t: float = (float(s["y"]) - origin.y) / dir.y
		if t < 0.05 or t > best_t:
			continue
		var p := origin + dir * t
		var lo: Vector2 = s["min"]
		var hi: Vector2 = s["max"]
		if p.x < lo.x or p.x > hi.x or p.z < lo.y or p.z > hi.y:
			continue
		best_t = t
		_surface_point = p
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
	held = null
	_state = State.IDLE


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
	for c in held.get_children():
		if not (c is MeshInstance3D):
			continue
		var src := c as MeshInstance3D
		var g := MeshInstance3D.new()
		g.mesh = src.mesh
		g.transform = src.transform
		g.material_override = _ghost_material()
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(g)


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


## Vrai si une surface de depose est sous le viseur. Sert au banc d'essai.
func has_surface() -> bool:
	return _surface_hit


## Vrai si le fantome est affiche. Sert au banc d'essai.
func ghost_visible() -> bool:
	return _ghost != null and _ghost.visible


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
	_hint.offset_left = -260.0
	_hint.offset_top = 26.0
	_hint.offset_right = 260.0
	_hint.offset_bottom = 52.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82, 0.75))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)


func _update_hud() -> void:
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
			else:
				_hint.text = "Clic gauche : prendre"
		State.HELD:
			_dot.visible = true
			_hint.text = "Maintiens clic gauche : poser"
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
