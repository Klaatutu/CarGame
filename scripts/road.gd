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

var target: Node3D

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


# --------------------------------------------------------------------------
# Ligne mediane
# --------------------------------------------------------------------------

func _append_sample() -> void:
	_advance_curve()
	var forward := -_head.basis.z
	_pos.append(_head.origin)
	_right.append(forward.cross(Vector3.UP).normalized())
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


func _reset() -> void:
	_v.clear()
	_n.clear()
	_f.clear()


## Bande continue entre deux decalages lateraux, le long de toute la route.
##
## Enroulement horaire vu du dessus : Godot considere les faces horaires comme
## faces avant, sinon la route est purement et simplement invisible.
func _strip(off_a: float, off_b: float, y: float, cols: int) -> void:
	var base := _v.size()
	var lift := Vector3(0.0, y, 0.0)
	var count := _pos.size()
	var stride := cols + 1
	for i in count:
		for c in stride:
			var t := float(c) / float(cols)
			_v.append(_pos[i] + _right[i] * lerpf(off_a, off_b, t) + lift)
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
	if _f.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_INDEX] = _f
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.surface_set_material(_mesh.get_surface_count() - 1, mat)


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
