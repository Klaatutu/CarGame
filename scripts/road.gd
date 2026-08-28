extends Node3D
##
## Route infinie et lisse.
##
## Ce n'est PAS une suite de blocs poses bout a bout : on garde une ligne
## mediane echantillonnee tous les STEP metres, et on reconstruit un unique
## ruban de triangles qui la suit. Aucun joint, aucun chevauchement, aucune
## marche, meme en plein virage.
##
## Le ruban est reconstruit a chaque fois qu'on avance d'un echantillon
## (environ 10 fois par seconde a pleine vitesse) : ~1500 sommets, c'est gratuit.
##

const Retro := preload("res://scripts/retro.gd")
const PoliceCar := preload("res://scripts/police_car.gd")
const GiantScript := preload("res://scripts/giant.gd")
const StranglerScript := preload("res://scripts/strangler.gd")
const PortalScript := preload("res://scripts/portal.gd")
const TownScript := preload("res://scripts/town.gd")

# Les bifurcations. Un Y : le ruban vivant s'incurve d'un cote, un BRIN MORT
# de BRANCH_LEN echantillons diverge de l'autre et meurt dans le brouillard.
# Le cote que prend la voiture entre F+FORK_FROM et F+FORK_TO choisit l'arete
# suivante — passer sur le brin mort ECHANGE les deux rubans (voir _swap).
const BRANCH_LEN := 40          # echantillons du brin mort (80 m)
const FORK_BEND := 0.0075       # rad/m d'ecartement, sous MAX_CURVE
const FORK_SPAN := 30           # echantillons de virage force sur le vivant
const FORK_FROM := 8            # la fenetre de choix, depuis la fourche...
const FORK_TO := 26             # ...jusqu'ici (echantillons)
const FORK_SIGN_AT := 45        # le panneau en Y, tant d'echantillons avant

const STEP := 2.0               # distance entre deux points de la ligne mediane
const SAMPLES := 150            # ~300 m de route vivante
const BEHIND := 12              # echantillons conserves derriere la voiture
const ROAD_HALF := 3.4          # demi-largeur de la chaussee
const SHOULDER := 2.4           # accotement de chaque cote
const ROAD_COLS := 2            # decoupe en largeur du ruban
const SHOULDER_COLS := 1
const LINE_INSET := 0.45        # retrait de la ligne continue par rapport au bord
const LINE_HALF := 0.075
const DASH_HALF := 0.08
const DASH_EVERY := 4           # un pointille tous les N echantillons
const MAX_CURVE := 0.009        # rad/m -> rayon mini ~110 m

# Hauteurs : tout est plat, seul l'ordre compte pour eviter le z-fighting.
const Y_SHOULDER := 0.0
const Y_ROAD := 0.02
const Y_PAINT := 0.026

const TREE_COUNT := 96
const POLE_COUNT := 18
const POLE_EVERY := 9           # echantillons entre deux poteaux

# Voiture de police garee sur l'accotement de droite, gyrophares allumes.
# La premiere a ~200 m du depart, les suivantes tous les 1,2 a 2,8 km.
const POLICE_FIRST := 110       # echantillon (global) de la premiere
const POLICE_EVERY_MIN := 600
const POLICE_EVERY_MAX := 1400
const POLICE_OFF := ROAD_HALF + 1.15   # centre de la caisse : sur l'accotement, hors de la voie
const POLICE_YAW := 7.0         # nez legerement tourne vers la route, comme garee a la hate
const POLICE_KEEP_BEHIND := 80.0      # on la laisse vivre tant qu'elle est a moins de 80 m derriere

# Le geant. Il est TAPI dans les arbres a l'echantillon prevu, bien avant que la
# voiture n'y arrive : c'est lui qui decide de se lever quand elle approche (voir
# giant.gd, notice_distance). La route ne fait que le poser et le rallumer.
#
# 480 m pour le premier, soit une vingtaine de secondes : le temps de partir, de
# passer les rapports et de croire qu'on est seul.
const GIANT_FIRST := 240              # echantillon (global)
const GIANT_EVERY_MIN := 900
const GIANT_EVERY_MAX := 1800
## Ecart a l'axe de la route. 15 m : dans la bande d'arbres (elle va jusqu'a
## 20 m), assez pres pour qu'il soit dans les phares en passant, assez loin pour
## qu'accroupi il se confonde avec les troncs.
const GIANT_OFF := 15.0

# L'etrangleur (strangler.gd). Lui ne se cache pas : il est POSE debout au
# milieu de la voie, face au sens de circulation, et il attend. Le premier
# vient apres le premier geant — on a appris qu'on pouvait fuir, et voila
# quelque chose qu'on ne fuit pas, qu'on evite ou qu'on abat.
const STRANGLER_FIRST := 420          # echantillon (global), ~820 m
const STRANGLER_EVERY_MIN := 800
const STRANGLER_EVERY_MAX := 1600
## Jeu lateral autour de l'axe : jamais exactement au milieu, comme quelqu'un
## qui est ARRIVE la, pas qui y a ete dessine.
const STRANGLER_JITTER := 0.8

var target: Node3D

## Les monstres ont-ils le droit d'apparaitre ? Vrai par defaut — les bancs
## d'essai gardent le monde d'avant. Le jeu normal le baisse : geant et
## etrangleur vivent dans le CAUCHEMAR (main.gd, la bascule du sommeil).
var monsters := true

var _pos := PackedVector3Array()      # points de la ligne mediane
var _right := PackedVector3Array()    # vecteur "droite" unitaire a chaque point
var _index0 := 0                      # index global du premier echantillon

var _head := Transform3D()
var _curve := 0.0
var _curve_goal := 0.0
var _until_new_curve := 16
var _rng := RandomNumberGenerator.new()

var _mesh := ArrayMesh.new()
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _f := PackedInt32Array()

var _mat_asphalt: ShaderMaterial
var _mat_shoulder: ShaderMaterial
var _mat_paint: ShaderMaterial
var _mat_bark: ShaderMaterial
var _mat_leaf: ShaderMaterial
var _mat_pole: ShaderMaterial

var _mesh_trunk: CylinderMesh
var _mesh_crown: CylinderMesh
var _mesh_pole: CylinderMesh
var _mesh_crossarm: BoxMesh

var _trees: Array[Node3D] = []
var _tree_i := 0
var _poles: Array[Node3D] = []
var _pole_i := 0
var _since_pole := 0

var police: Node3D
## Echantillon global ou la voiture de police est posee (-1 : nulle part).
var police_index := -1
var _police_next := POLICE_FIRST

var giant: Node3D
## Echantillon global ou le geant est tapi (-1 : il n'est nulle part).
var giant_index := -1
var _giant_next := GIANT_FIRST

var strangler: Node3D
## Echantillon global ou l'etrangleur est poste (-1 : nulle part).
var strangler_index := -1
var _strangler_next := STRANGLER_FIRST

## Le portail du cauchemar (portal.gd) : arme par set_portal, un seul.
var portal: Node3D
var portal_index := -1
var _portal_at := -1

## La ville franchie (le panneau vient d'etre depasse par la VOITURE).
signal town_reached(id: String)
## Le Y est tranche : "left"/"right", et la ville vers laquelle ce cote mene.
signal fork_committed(side: String, id: String)

## La ville en approche (town.gd, un seul exemplaire en pool).
var town: Node3D
var _town_g := -1
var _town_id := ""

## La fourche en cours. _fork_state : "" (aucune), "grow" (posee, brin mort
## construit), "window" (la voiture choisit), "done" (tranchee, le brin mort
## reste en decor jusqu'a passer derriere).
var _fork_g := -1
var _fork_left := ""
var _fork_right := ""
var _fork_main := "left"
var _fork_state := ""
var _bpos := PackedVector3Array()
var _bright := PackedVector3Array()
var _bhead := Transform3D()
var _bhead_end := Transform3D()
var _branch_mesh := ArrayMesh.new()
var _branch_mi: MeshInstance3D
var _fork_sign: Node3D


func _ready() -> void:
	_rng.randomize()
	_build_resources()
	_build_prop_pools()

	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# On demarre la route derriere la voiture, et bien droite au depart.
	_head = Transform3D(Basis(), Vector3(0.0, 0.0, BEHIND * STEP))
	for i in SAMPLES:
		_append_sample()
	_rebuild()


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var forward := -target.global_transform.basis.z
	var moved := false
	var guard := 0
	while guard < SAMPLES:
		if (target.global_position - _pos[0]).dot(forward) < BEHIND * STEP:
			break
		_pos.remove_at(0)
		_right.remove_at(0)
		_index0 += 1
		_append_sample()
		moved = true
		guard += 1
	if moved:
		_rebuild()
	# Une fois depassee, la voiture de police reste visible un moment (retroviseurs),
	# puis s'eteint jusqu'a la prochaine.
	if police.visible and (target.global_position - police.global_position).dot(forward) > POLICE_KEEP_BEHIND:
		police.visible = false
		police.set_process(false)
		police_index = -1

	# Le geant s'eteint tout seul une fois seme. On lui donne alors un nouveau
	# rendez-vous, loin devant : il faut avoir eu le temps de se croire tire
	# d'affaire avant de retomber sur le suivant.
	if giant_index >= 0 and giant.asleep():
		giant_index = -1
		_giant_next = _index0 + SAMPLES + _rng.randi_range(GIANT_EVERY_MIN, GIANT_EVERY_MAX)

	# L'etrangleur pareil : depasse, abattu ou vainqueur, il s'eteint de
	# lui-meme, et le suivant prend rendez-vous.
	if strangler_index >= 0 and strangler.asleep():
		strangler_index = -1
		_strangler_next = _index0 + SAMPLES \
			+ _rng.randi_range(STRANGLER_EVERY_MIN, STRANGLER_EVERY_MAX)

	# La ville : le panneau depasse par la VOITURE, l'evenement part ; le
	# decor, lui, vit encore un moment (retroviseurs) puis s'eteint.
	if _town_g >= 0 and head_index() >= _town_g:
		var id := _town_id
		_town_g = -1
		town_reached.emit(id)
	if town != null and town.visible \
			and (target.global_position - town.global_position).dot(forward) > 130.0:
		town.sleep()

	# La fourche. Dans la fenetre, la voiture choisit PAR SA TRAJECTOIRE :
	# plus pres du brin mort que du vivant d'une largeur de voie, on echange
	# les deux rubans — rien n'apparait ni ne disparait a moins de 200 m.
	if _fork_state == "grow" and head_index() >= _fork_g + FORK_FROM:
		_fork_state = "window"
	if _fork_state == "window":
		if head_index() > _fork_g + FORK_TO:
			# Le verdict — meme si la fenetre entiere a ete avalee par une
			# grosse image (machine chargee : releve au banc, grow -> window
			# -> commit dans le meme _process). Ou la voiture est-elle, LA :
			# plus pres du brin mort, c'est lui qu'elle a pris.
			if _closest_dist(_bpos, target.global_position) + 0.5 \
					< _closest_dist(_pos, target.global_position):
				_swap_to_branch()
			else:
				_fork_state = "done"
				fork_committed.emit(_fork_main,
					_fork_left if _fork_main == "left" else _fork_right)
		else:
			var d_main := _closest_dist(_pos, target.global_position)
			var d_branch := _closest_dist(_bpos, target.global_position)
			if d_branch + 2.2 < d_main:
				_swap_to_branch()
	# Le vieux ruban et le panneau se rangent une fois TOUT LEUR LOIN derriere
	# nous : apres un echange, l'ancienne fenetre s'etendait 280 m au-dela de
	# la fourche — la ranger trop tot ferait disparaitre une route sous les
	# yeux du retroviseur.
	if _fork_g >= 0 and _fork_state != "" and _fork_g < _index0 - 170:
		_clear_fork()


# --------------------------------------------------------------------------
# Ligne mediane
# --------------------------------------------------------------------------

func _append_sample() -> void:
	_advance_curve()
	var g := _index0 + _pos.size()

	# Le programme d'arete plie la geometrie : droit a l'approche d'une
	# ville (on arrive SUR un bourg, pas en glissade), ecarte au Y.
	if _town_g >= 0 and absi(g - _town_g) < 20:
		_curve = lerpf(_curve, 0.0, 0.4)
		_curve_goal = 0.0
	# Au Y, le ruban VIVANT file DROIT — du panneau jusqu'au bout du
	# raccord : continuer ne demande rien, c'est la sortie qui diverge. Tout
	# droit est un choix qu'on fait sans le savoir, braquer un choix qu'on
	# fait expres — et le panneau se lit sur une route qui ne tourne pas.
	if _fork_g >= 0 and _fork_state in ["", "grow"] \
			and g >= _fork_g - FORK_SIGN_AT and g <= _fork_g + FORK_SPAN:
		_curve = 0.0
		_curve_goal = 0.0

	var forward := -_head.basis.z
	_pos.append(_head.origin)
	_right.append(forward.cross(Vector3.UP).normalized())

	# Le panneau en Y, quelques dizaines de metres avant la fourche.
	if _fork_g >= 0 and _fork_state == "" and not _fork_sign.visible \
			and g >= _fork_g - FORK_SIGN_AT:
		_arm_fork_sign(_pos.size() - 1)
	# La fourche elle-meme : le brin mort part d'ici, le vivant s'incurve.
	if _fork_g >= 0 and _fork_state == "" and g >= _fork_g:
		_fork_g = g                    # si la fenetre l'a depasse : ici meme
		_bhead = _head
		_fork_state = "grow"
		_grow_branch()
	# La ville : posee a son echantillon, la traversee commence au panneau.
	if _town_g >= 0 and g == _town_g and town != null and not town.visible:
		var r := _right[_pos.size() - 1]
		town.arm(Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)),
			_pos[_pos.size() - 1]), _town_id)

	_place_props(_pos.size() - 1)
	_head.origin += forward * STEP
	_head = _head.rotated_local(Vector3.UP, _curve * STEP)


func _advance_curve() -> void:
	_until_new_curve -= 1
	if _until_new_curve <= 0:
		_until_new_curve = _rng.randi_range(14, 40)
		_curve_goal = clampf(_rng.randfn(0.0, 0.005), -MAX_CURVE, MAX_CURVE)
	# Lissage : la courbure ne change jamais d'un coup, sinon on sent la cassure.
	_curve = lerpf(_curve, _curve_goal, 0.09)


# --------------------------------------------------------------------------
# Ruban
# --------------------------------------------------------------------------

func _rebuild() -> void:
	_mesh.clear_surfaces()

	_reset()
	_strip(-(ROAD_HALF + SHOULDER), -ROAD_HALF, Y_SHOULDER, SHOULDER_COLS)
	_strip(ROAD_HALF, ROAD_HALF + SHOULDER, Y_SHOULDER, SHOULDER_COLS)
	_commit(_mat_shoulder)

	_reset()
	_strip(-ROAD_HALF, ROAD_HALF, Y_ROAD, ROAD_COLS)
	_commit(_mat_asphalt)

	_reset()
	var e := ROAD_HALF - LINE_INSET
	_strip(-e - LINE_HALF, -e + LINE_HALF, Y_PAINT, 1)
	_strip(e - LINE_HALF, e + LINE_HALF, Y_PAINT, 1)
	_dashes()
	_commit(_mat_paint)


## Le brin mort d'une fourche : le meme ruban, les memes bandes, dans SON
## maillage — nu, sans pointilles ni props, et il meurt dans le brouillard.
func _rebuild_branch() -> void:
	_branch_mesh.clear_surfaces()
	if _bpos.size() < 2:
		return
	_reset()
	_strip_of(_bpos, _bright, -(ROAD_HALF + SHOULDER), -ROAD_HALF, Y_SHOULDER, SHOULDER_COLS)
	_strip_of(_bpos, _bright, ROAD_HALF, ROAD_HALF + SHOULDER, Y_SHOULDER, SHOULDER_COLS)
	_commit_into(_mat_shoulder, _branch_mesh)
	_reset()
	_strip_of(_bpos, _bright, -ROAD_HALF, ROAD_HALF, Y_ROAD, ROAD_COLS)
	_commit_into(_mat_asphalt, _branch_mesh)
	_reset()
	var e := ROAD_HALF - LINE_INSET
	_strip_of(_bpos, _bright, -e - LINE_HALF, -e + LINE_HALF, Y_PAINT, 1)
	_strip_of(_bpos, _bright, e - LINE_HALF, e + LINE_HALF, Y_PAINT, 1)
	_commit_into(_mat_paint, _branch_mesh)


## Distance de p au plus proche echantillon d'une ligne (2 m de pas : bien
## assez fin pour departager deux chaussees qui s'ecartent).
func _closest_dist(line: PackedVector3Array, p: Vector3) -> float:
	var best := 1.0e18
	for q in line:
		var d := Vector2(p.x - q.x, p.z - q.z).length_squared()
		if d < best:
			best = d
	return sqrt(best)


func _reset() -> void:
	_v.clear()
	_n.clear()
	_f.clear()


## Bande continue entre deux decalages lateraux, le long de toute la route.
##
## Enroulement horaire vu du dessus : Godot considere les faces horaires comme
## faces avant, sinon la route est purement et simplement invisible.
func _strip(off_a: float, off_b: float, y: float, cols: int) -> void:
	_strip_of(_pos, _right, off_a, off_b, y, cols)


## La meme bande, sur une ligne quelconque : le ruban vivant ou le brin mort
## d'une fourche — un seul code de geometrie, deux maillages.
func _strip_of(pos: PackedVector3Array, right: PackedVector3Array,
		off_a: float, off_b: float, y: float, cols: int) -> void:
	var base := _v.size()
	var lift := Vector3(0.0, y, 0.0)
	var count := pos.size()
	var stride := cols + 1
	for i in count:
		for c in stride:
			var t := float(c) / float(cols)
			_v.append(pos[i] + right[i] * lerpf(off_a, off_b, t) + lift)
			_n.append(Vector3.UP)
	for i in count - 1:
		for c in cols:
			var a := base + i * stride + c
			var b := a + stride
			_f.append_array([a, b, b + 1, a, b + 1, a + 1])


## Pointilles centraux : un quad par echantillon, un echantillon sur DASH_EVERY.
func _dashes() -> void:
	var lift := Vector3(0.0, Y_PAINT, 0.0)
	for i in _pos.size() - 1:
		if (_index0 + i) % DASH_EVERY != 0:
			continue
		var base := _v.size()
		_v.append(_pos[i] - _right[i] * DASH_HALF + lift)
		_v.append(_pos[i] + _right[i] * DASH_HALF + lift)
		_v.append(_pos[i + 1] - _right[i + 1] * DASH_HALF + lift)
		_v.append(_pos[i + 1] + _right[i + 1] * DASH_HALF + lift)
		for k in 4:
			_n.append(Vector3.UP)
		_f.append_array([base, base + 2, base + 3, base, base + 3, base + 1])


func _commit(mat: Material) -> void:
	_commit_into(mat, _mesh)


func _commit_into(mat: Material, mesh: ArrayMesh) -> void:
	if _f.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v.duplicate()
	arrays[Mesh.ARRAY_NORMAL] = _n.duplicate()
	arrays[Mesh.ARRAY_INDEX] = _f.duplicate()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


# --------------------------------------------------------------------------
# Decor
# --------------------------------------------------------------------------

func _place_props(i: int) -> void:
	if _rng.randf() < 0.55:
		var tree := _trees[_tree_i]
		_tree_i = (_tree_i + 1) % _trees.size()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var off := _rng.randf_range(ROAD_HALF + SHOULDER + 0.6, ROAD_HALF + 17.0)
		tree.position = _pos[i] + _right[i] * (side * off)
		tree.visible = true
		var s := _rng.randf_range(0.75, 1.5)
		tree.scale = Vector3(s * _rng.randf_range(0.8, 1.1), s, s * _rng.randf_range(0.8, 1.1))
		tree.rotation = Vector3(
			_rng.randf_range(-0.04, 0.04),
			_rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.04, 0.04))

	_since_pole += 1
	if _since_pole >= POLE_EVERY:
		_since_pole = 0
		var pole := _poles[_pole_i]
		_pole_i = (_pole_i + 1) % _poles.size()
		var r := _right[i]
		# Traverse perpendiculaire a la route : on aligne X sur le vecteur droite.
		pole.transform = Transform3D(
			Basis(r, Vector3.UP, -Vector3.UP.cross(r)),
			_pos[i] - r * (ROAD_HALF + SHOULDER * 0.6))
		pole.visible = true

	# Voiture de police : a l'echantillon prevu, posee sur l'accotement de droite,
	# dans le sens de la route (France : on roule a droite, elle est garee dans
	# notre sens), le nez un peu vers la chaussee.
	var g := _index0 + i
	if g >= _police_next and not police.visible:
		var r := _right[i]
		var basis := Basis(r, Vector3.UP, -Vector3.UP.cross(r)).rotated(Vector3.UP, deg_to_rad(POLICE_YAW))
		police.transform = Transform3D(basis, _pos[i] + r * POLICE_OFF)
		police.visible = true
		police.set_process(true)
		police_index = g
		_police_next = g + _rng.randi_range(POLICE_EVERY_MIN, POLICE_EVERY_MAX)

	# Le geant, tapi dans les arbres d'un cote ou de l'autre, tourne vers la
	# route. Il est pose ICI, a 275 m devant la voiture, et il ne bougera pas
	# avant qu'elle soit a 72 m : le temps qu'elle arrive, il fait partie du
	# paysage.
	if monsters and g >= _giant_next and giant_index < 0 and target != null:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var r := _right[i]
		var basis := Basis(r, Vector3.UP, -Vector3.UP.cross(r)).rotated(
			Vector3.UP, deg_to_rad(90.0 * side + _rng.randf_range(-25.0, 25.0)))
		giant.transform = Transform3D(basis, _pos[i] + r * (side * GIANT_OFF))
		giant.arm(target)
		giant_index = g

	# L'etrangleur, debout au milieu de la voie, tourne vers la voiture qui
	# vient. Pose a ~275 m devant : le temps que les phares le trouvent, il est
	# la depuis toujours.
	if monsters and g >= _strangler_next and strangler_index < 0 and target != null:
		var r := _right[i]
		var basis := Basis(r, Vector3.UP, -Vector3.UP.cross(r)) \
			.rotated(Vector3.UP, PI)
		strangler.transform = Transform3D(basis,
			_pos[i] + r * _rng.randf_range(-STRANGLER_JITTER, STRANGLER_JITTER))
		strangler.arm(target)
		strangler_index = g

	# Le portail du cauchemar : pose en travers de la voie a l'echantillon
	# demande — ou au premier qui nait apres lui, si la fenetre vivante l'a
	# deja depasse quand la demande arrive (la distance est un "au moins").
	if _portal_at >= 0 and g >= _portal_at:
		var r := _right[i]
		portal.arm(Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)), _pos[i]))
		portal_index = g
		_portal_at = -1


## L'echantillon global a hauteur de voiture : la distance parcourue, en pas
## de STEP. C'est l'unite des rendez-vous — monstres, portail.
func head_index() -> int:
	return _index0 + BEHIND


## Demande un portail a l'echantillon global g (a venir). Le precedent, s'il
## en restait un, s'eteint.
func set_portal(g: int) -> void:
	portal.sleep()
	portal_index = -1
	_portal_at = g


## Eteint tout ce qui vit et repousse les rendez-vous loin devant : le reveil
## du cauchemar. Les monstres ne reviendront que si `monsters` remonte.
func clear_monsters() -> void:
	if not giant.asleep():
		giant.sleep()
	giant_index = -1
	_giant_next = _index0 + SAMPLES + _rng.randi_range(GIANT_EVERY_MIN, GIANT_EVERY_MAX)
	if not strangler.asleep():
		strangler.sleep()
	strangler_index = -1
	_strangler_next = _index0 + SAMPLES \
		+ _rng.randi_range(STRANGLER_EVERY_MIN, STRANGLER_EVERY_MAX)


# --------------------------------------------------------------------------
# Le programme d'arete : ce que la carte demande, la route l'execute
# --------------------------------------------------------------------------

## Une ville a l'echantillon global g (a venir). Le ruban arrive droit
## dessus, le panneau tombe a g, l'evenement part quand la voiture y est.
func program_town(g: int, id: String) -> void:
	_town_g = g
	_town_id = id
	if town != null:
		town.sleep()


## Un Y a l'echantillon global g : le cote gauche mene a left_id, le droit a
## right_id, et le ruban VIVANT continue du cote main_side — l'autre devient
## le brin mort. La voiture tranche au volant dans la fenetre.
func program_fork(g: int, left_id: String, right_id: String,
		main_side: String) -> void:
	_clear_fork()
	_fork_g = g
	_fork_left = left_id
	_fork_right = right_id
	_fork_main = main_side
	_fork_state = ""


func fork_state() -> String:
	return _fork_state


## Le brin mort : la SORTIE. Il diverge du cote oppose au vivant (qui file
## droit), se detend, et s'arrete a BRANCH_LEN — 80 m, la moitie de ce que
## le brouillard laisse voir, et il s'incurve pour derober sa fin.
func _grow_branch() -> void:
	_bpos = PackedVector3Array()
	_bright = PackedVector3Array()
	var h := _bhead
	var curve := -2.0 * FORK_BEND * (1.0 if _fork_main == "left" else -1.0)
	for i in BRANCH_LEN:
		var fwd := -h.basis.z
		h.origin += fwd * STEP
		h = h.rotated_local(Vector3.UP, curve * STEP)
		if i > 18:
			curve = lerpf(curve, 0.0, 0.12)
		fwd = -h.basis.z
		_bpos.append(h.origin)
		_bright.append(fwd.cross(Vector3.UP).normalized())
	# La tete de reprise vit UN PAS AU-DELA du dernier point — comme dans
	# _append_sample, ou l'avance suit l'ajout. La ranger SUR le dernier
	# point dupliquait l'echantillon a l'echange : un segment de longueur
	# nulle, une normale en 0/0 et un faux virage de 90 degres au releve.
	h.origin += -h.basis.z * STEP
	_bhead_end = h
	_rebuild_branch()


## L'ECHANGE. La voiture est passee sur la sortie : la fenetre vivante
## REPART du brin, depuis l'echantillon sous la voiture — et l'ANCIENNE
## fenetre entiere (le troncon d'avant la fourche PLUS la continuation qu'on
## n'a pas prise, d'un seul tenant) devient le decor de la route qu'on
## quitte. Rien n'a besoin de l'echantillon de fourche : il peut etre sorti
## de la fenetre depuis longtemps — c'etait le piege de la premiere version,
## BEHIND ne garde que 24 m derriere la voiture et l'echange n'etait
## geometriquement possible que onze echantillons durant.
func _swap_to_branch() -> void:
	var j := _closest_index(_bpos, target.global_position)
	var start := maxi(j - BEHIND, 0)
	var old_p := _pos
	var old_r := _right
	_pos = _bpos.slice(start)
	_right = _bright.slice(start)
	# L'index global repart de la fourche : la METRIQUE continue — a un pas
	# pres, et le pas fait deux metres.
	_index0 = _fork_g + 1 + start
	_head = _bhead_end
	_curve = 0.0
	_curve_goal = 0.0
	_bpos = old_p
	_bright = old_r
	_rebuild_branch()
	while _pos.size() < SAMPLES:
		_append_sample()
	_rebuild()
	_fork_state = "done"
	var side := "right" if _fork_main == "left" else "left"
	fork_committed.emit(side, _fork_left if side == "left" else _fork_right)


func _closest_index(line: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var bd := 1.0e18
	for i in line.size():
		var d := Vector2(p.x - line[i].x, p.z - line[i].z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


func _clear_fork() -> void:
	_fork_g = -1
	_fork_state = ""
	_bpos = PackedVector3Array()
	_bright = PackedVector3Array()
	_branch_mesh.clear_surfaces()
	if _fork_sign != null:
		_fork_sign.visible = false


## Le panneau en Y : un poteau, deux toles inclinees, les deux noms — la
## meme tole et la meme peinture que les panneaux de ville (town.gd).
func _build_fork_sign() -> Node3D:
	var mat_metal := Retro.mat(Color(0.10, 0.11, 0.13), 0.5)
	var mat_pole := Retro.mat(Color(0.055, 0.055, 0.06), 0.9)
	var root := Node3D.new()
	root.name = "ForkSign"
	root.visible = false
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.05
	pcyl.bottom_radius = 0.06
	pcyl.height = 2.9
	pole.mesh = pcyl
	pole.material_override = mat_pole
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position = Vector3(0.0, 1.45, 0.0)
	root.add_child(pole)
	for spec in [["PlateL", 2.55, 24.0], ["PlateR", 1.95, -24.0]]:
		var plate := Node3D.new()
		plate.name = spec[0]
		plate.position = Vector3(0.0, spec[1], 0.0)
		plate.rotation_degrees.y = spec[2]
		root.add_child(plate)
		var tin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 0.5, 0.04)
		tin.mesh = box
		tin.material_override = mat_metal
		tin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plate.add_child(tin)
		var label := Label3D.new()
		label.name = "Name"
		label.text = "?"
		label.font_size = 52
		label.pixel_size = 0.004
		label.modulate = Color(0.72, 0.74, 0.70)
		label.position = Vector3(0.0, 0.0, 0.035)
		plate.add_child(label)
	return root


func _arm_fork_sign(i: int) -> void:
	if _fork_sign == null:
		return
	(_fork_sign.get_node("PlateL/Name") as Label3D).text = _fork_left.to_upper()
	(_fork_sign.get_node("PlateR/Name") as Label3D).text = _fork_right.to_upper()
	var r := _right[i]
	_fork_sign.global_transform = Transform3D(
		Basis(r, Vector3.UP, -Vector3.UP.cross(r)),
		_pos[i] + r * (ROAD_HALF + SHOULDER + 0.4))
	_fork_sign.visible = true


## Pose (centre de la chaussee, face a la route) a l'echantillon global g, ou
## l'identite s'il n'est plus dans la fenetre vivante. Sert aux bancs d'essai.
func sample_at(g: int) -> Transform3D:
	var i := g - _index0
	if i < 0 or i >= _pos.size():
		return Transform3D()
	var r := _right[i]
	return Transform3D(Basis(r, Vector3.UP, -Vector3.UP.cross(r)), _pos[i])


func _build_prop_pools() -> void:
	police = PoliceCar.new()
	police.name = "PoliceCar"
	police.visible = false
	police.set_process(false)
	add_child(police)

	# Un seul portail : arme au fond du cauchemar, rendormi au reveil.
	portal = PortalScript.new()
	portal.name = "Portal"
	add_child(portal)

	# Une seule ville a la fois (comme la police), le maillage du brin mort,
	# et le panneau en Y — le decor du graphe (map.gd).
	town = TownScript.new()
	town.name = "Town"
	add_child(town)

	_branch_mi = MeshInstance3D.new()
	_branch_mi.name = "Branch"
	_branch_mi.mesh = _branch_mesh
	_branch_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_branch_mi)

	_fork_sign = _build_fork_sign()
	add_child(_fork_sign)

	# Un seul geant, reutilise : il n'y en a jamais deux a la fois.
	giant = GiantScript.new()
	giant.name = "Giant"
	add_child(giant)

	# Un seul etrangleur aussi. Il change de parent quand il s'accroche a la
	# voiture, et revient ici en s'eteignant.
	strangler = StranglerScript.new()
	strangler.name = "Strangler"
	add_child(strangler)

	for i in TREE_COUNT:
		var tree := Node3D.new()
		tree.visible = false
		add_child(tree)
		_add_mesh(tree, _mesh_trunk, _mat_bark, Vector3(0.0, 1.6, 0.0))
		_add_mesh(tree, _mesh_crown, _mat_leaf, Vector3(0.0, 5.6, 0.0))
		_trees.append(tree)

	for i in POLE_COUNT:
		var pole := Node3D.new()
		pole.visible = false
		add_child(pole)
		_add_mesh(pole, _mesh_pole, _mat_pole, Vector3(0.0, 3.75, 0.0))
		_add_mesh(pole, _mesh_crossarm, _mat_pole, Vector3(0.0, 7.1, 0.0))
		_poles.append(pole)


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _build_resources() -> void:
	_mat_asphalt = Retro.mat(Color(0.085, 0.086, 0.094), 0.55, 0.10)
	_mat_shoulder = Retro.mat(Color(0.060, 0.058, 0.052), 0.94)
	_mat_paint = Retro.mat(Color(0.58, 0.56, 0.50), 0.70)
	_mat_bark = Retro.mat(Color(0.075, 0.068, 0.058), 0.96)
	_mat_leaf = Retro.mat(Color(0.038, 0.045, 0.036), 0.96)
	_mat_pole = Retro.mat(Color(0.085, 0.082, 0.076), 0.86)

	_mesh_trunk = CylinderMesh.new()
	_mesh_trunk.top_radius = 0.10
	_mesh_trunk.bottom_radius = 0.17
	_mesh_trunk.height = 3.2
	_mesh_trunk.radial_segments = 6
	_mesh_trunk.rings = 3

	# Sapin mort : un cone tres etroit, parfait dans le brouillard.
	_mesh_crown = CylinderMesh.new()
	_mesh_crown.top_radius = 0.0
	_mesh_crown.bottom_radius = 1.15
	_mesh_crown.height = 6.5
	_mesh_crown.radial_segments = 7
	_mesh_crown.rings = 5

	_mesh_pole = CylinderMesh.new()
	_mesh_pole.top_radius = 0.09
	_mesh_pole.bottom_radius = 0.13
	_mesh_pole.height = 7.5
	_mesh_pole.radial_segments = 6
	_mesh_pole.rings = 6

	_mesh_crossarm = BoxMesh.new()
	_mesh_crossarm.size = Vector3(1.5, 0.09, 0.09)
	_mesh_crossarm.subdivide_width = 4
